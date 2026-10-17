--[[
	MusicConfig
	-----------
	The soundtrack: which tracks play where, how loud, and how one hands over to the next. Read by
	`MusicController` (which owns the decks) and `TopbarController` (which owns the mute button).

	THE TRACKS ARE IDS HERE, NOT INSTANCES IN THE PLACE, and that is the one way this file parts
	company with `SoundController`. That one looks its clips up in `SoundService` because they are
	interchangeable one-shot variations the boss pastes ids into; a soundtrack is an ORDERED,
	NAMED thing that wants to be diffed, re-ordered and swapped per world in one place, and a
	folder of empty Sounds in a place file is a bad diff. So the ids live here and the decks are
	built at runtime. Nothing about the two systems conflicts — they play through different groups
	and neither knows the other exists.

	SIX THINGS TO KNOW.

	1. A PLAYLIST IS CHOSEN BY CONTEXT, AND THERE ARE ONLY TWO KINDS OF CONTEXT: the lobby, and a
	   world you are racing in. `playlistFor` is the whole mapping. The lobby list is what plays
	   everywhere that is not a run — the forecourt, the dealership, every screen — because those
	   are all the same place to a player standing in it, and cutting the music when they open a
	   menu would be the only thing that made a menu feel like somewhere else.

	2. EVERY ROAD PLAYS THE DRIVING LIST unless its world has a list of its own in `Worlds`. That
	   table is an override and it ships empty: the soundtrack is one lobby set and one driving
	   set, and a world gets its own music only on the day someone wants that road to sound
	   different. Adding a world to `WorldConfig` therefore ships with music on day one, which is
	   the same bargain `WorldConfig` makes for maps: a missing entry reads as "not themed yet",
	   never as "broken". An empty driving list falls back to the lobby's rather than to silence.

	3. THE LOBBY AND DRIVING LISTS ARE THE OWNER'S PICKS, off the Trello cards "New Background
	   Music" and "Driving Music" (2026-09-15). All four are licensed Creator Store music from
	   verified publishers (APMOfficial and DistrokidOfficial), so they play in any experience.
	   Each was loaded in Studio before it went in, and the seconds in the comments are measured
	   `TimeLength`, not the catalogue's. They replaced nineteen stand-ins from 2026-08-20, a
	   themed list per world among them, which git history still has.

	   Checking a NEW id before it goes in the list is worth the minute it costs: an id that does
	   not resolve is not an error anywhere downstream, it is a deck that starts, plays silence for
	   its watchdog's timeout, and moves on. See `MusicController._armWatchdog` for why that is
	   survivable and still invisible.

	4. `Volume` ON A TRACK IS A TRIM, NOT ITS VOLUME. Tracks from different albums are mastered at
	   different levels, and the fix for one that jumps out of the set is a number on that one
	   track rather than riding the master. It multiplies `Volume` below; absent is 1. The trims
	   below were MEASURED, not guessed by ear; the note above the lobby list has the method, and a
	   new track wants the same treatment.

	5. THE MUTE IS THE PLAYER'S, AND THE SERVER ONLY REMEMBERS IT. There is no authority question
	   here — nothing the server could decide about whether your speakers make noise — so the
	   client applies a press instantly and tells the server afterwards, which is the opposite of
	   how every other press in this game works and is deliberate. `MusicController` has the full
	   reasoning under "Who owns the level".

	   THE MUTE IS ALSO THE SETTINGS SCREEN'S VOLUME SLIDER, and the two are one number rather than
	   two facts that have to agree: muted IS a level of zero. The keys below are still the mute's
	   own and are still written, but `AudioConfig.Music` is where the level lives and is what wins
	   when a profile has both. That file's header has the whole arrangement.

	6. IT MUTES THE MUSIC AND NOTHING ELSE. Engine noise, UI clicks and the wind all keep playing,
	   because they are the game telling you what is happening and the music is not. That is no
	   longer the only lever a player has, either: `AudioConfig.Sfx` is the slider for everything
	   this one does not cover, so there is no longer any reason for this to grow into a master
	   mute.
]]

local MusicConfig = {}

--- The master A/B. Off = no decks, no soundtrack, and no button on the topbar.
MusicConfig.Enabled = true

-- === Levels and timings =====================================================

--[[ Base deck volume, before a track's own `Volume` trim. Music sits UNDER the game: the engine,
	the near-misses and the crashes are what a player is listening to, and this is the room they
	happen in. If it ever fights the car, this is the number, not the mix. ]]
MusicConfig.Volume = 0.35

--[[ HANDING OVER BETWEEN PLAYLISTS is a crossfade, because the two moments it happens at are the
	two moments the game is already moving the player somewhere — into a race, and back out of one.
	A cut there lands on top of a fade-to-black and reads as a glitch.

	HANDING OVER *WITHIN* a playlist is not: a track that has finished has finished, and the next
	one starts after `GapSeconds` of air. Crossfading two tracks of the same set only ever muddles
	them, and the silence is what tells you the soundtrack is a soundtrack and not a loop. ]]
MusicConfig.CrossfadeSeconds = 1.75
MusicConfig.GapSeconds = 2.5

--- How long the fade to (and from) silence takes when the button is pressed. Short — a mute that
--- takes a second to arrive reads as a button that did not work.
MusicConfig.MuteFadeSeconds = 0.35

--[[ How long after a track was due to end before the deck gives up on it and moves on.

	A SOUNDTRACK MUST NOT BE ABLE TO STOP. `Sound.Ended` is what normally advances a playlist, and
	it never fires for an id that failed to load, was moderated after it went in the list, or was
	made private by whoever uploaded it — so without this, one bad number is not one skipped track,
	it is the end of the music for that session. The watchdog turns every one of those into a
	few seconds of silence. ]]
MusicConfig.TrackTimeoutSlack = 3

--[[ How long a deck waits for a track's length to arrive before assuming the worst.

	`TimeLength` is 0 until the asset streams in, so the watchdog above has nothing to count
	against for the first moment of every track. This is what it counts instead, and it is
	deliberately longer than any reasonable load: it is the timeout for "this id is never going to
	resolve", not for "this id is still downloading". ]]
MusicConfig.LoadTimeout = 20

--[[ THE ROAD'S MUSIC STARTS WHEN THE ROAD CAN BE SEEN, not when the server starts building it.
	`RaceStart` lands behind the entry's loading screen, so the lobby list plays on under that screen
	and the crossfade to the road's music begins on `RaceConfig.RevealedEvent`, the instant the screen
	starts to lift. `MusicController._holdRoad` has the rest.

	This is how long after `RaceStart` it will wait for that before starting anyway: the floor under
	a loading screen that never says it lifted (a `RaceUIController` that failed to start). It must
	stay longer than the slowest REAL reveal or it would cut in early on a slow phone, and the
	screen's own safety has it down by about 12s after it went up (`RaceConfig.EnterReadyTimeout`
	has the measured worst case, 12.6s). ]]
MusicConfig.RevealTimeout = 15

-- === Where the sound comes out ==============================================

--[[ The SoundGroup both decks play through — the thing the mute actually turns down, and the one
	place to put a music-wide effect.

	ADOPTED IF IT ALREADY EXISTS. Author a SoundGroup of this name under `SoundService` and its
	Volume becomes the unmuted target, so the mix can be trimmed in Studio without a build. Absent,
	one is created at runtime at Volume 1 and `MusicConfig.Volume` above is the whole level. Either
	way it is client-side and local: nothing here replicates. ]]
MusicConfig.SoundGroupName = "Music"

-- === The mute, as it is stored and broadcast ================================

--[[ `Attribute` is the server's copy of the flag, mirrored onto the Player the way `Cash` and
	`World` are — but read ONCE, on the way in, and never again while the session runs. It is the
	seed for a fresh client, not a live channel; see `MusicController` under "Who owns the mute"
	for why a preference is the one thing in this game the attribute does not get to keep deciding.

	`ProfileKey` is where it is kept between sessions (top-level in the profile template, for the
	reason every other top-level key there gives: `PlayerProfile`'s string path is a recursive key
	search). `RemoteName` is the client saying so. ]]
MusicConfig.MuteAttribute = "MusicMuted"
MusicConfig.ProfileKey = "MusicMuted"
MusicConfig.RemoteName = "SetMusicMuted"

--[[ How long the client will wait for the server's seed before it starts playing.

	The profile is a datastore round trip and the topbar is up long before it lands, so something
	has to decide what a player who has not been answered about yet hears. Waiting is the right
	answer and this is how long for: starting unmuted and correcting a second later means a muted
	player gets a second of music every single join, which is precisely the thing they turned off.
	Past this, silence is assumed to be nobody's preference and the music starts. ]]
MusicConfig.SeedTimeout = 6

-- === The playlists ==========================================================

--[[ WHAT PLAYS IN THE LOBBY: the forecourt, the dealership, the garage, every screen, and the
	whole of the time between runs. Cartoon caper music. This is the room where the player looks at
	what they own and decides what to go and steal next, and it is the only music most of them will
	hear for most of a session, so it is the list that most needs to not wear out.

	Names are the Creator Store's own, kept so a track can be found again; the seconds are measured
	`TimeLength`. Neither is read by anything.

	THE dB IN EACH COMMENT IS THE TRACK'S OWN LEVEL and the trims are built from it (note 4). Each
	track was played through an `AudioPlayer` wired to an `AudioAnalyzer` in edit mode, which
	measures without making a sound, and its RMS was taken over the whole length. Every trim here
	and on the driving list lands its track at about -15 dB, which is this set's own average and
	within 2 dB of the stand-ins `MusicConfig.Volume` was first set against (they averaged -13). ]]
MusicConfig.Lobby = {
	{ Id = 117314599439697, Name = "Legend in Action", Seconds = 240, Volume = 1.2 }, -- -16.8 dB
	{ Id = 1838674668, Name = "Cartoon Scene", Seconds = 124 }, -- -15.6 dB
	{ Id = 1841647421, Name = "Cartoon Capers", Seconds = 269, Volume = 0.8 }, -- -12.9 dB
}

--[[ WHAT PLAYS ON THE ROAD, in every world that has no list of its own (note 2).

	ONE TRACK, SO A LONG RUN HEARS IT AGAIN, with `GapSeconds` of air between plays rather than a
	seamless loop; the bag shuffle is a no-op on a one-track list. A second track added here is
	dealt like any other list, with nothing else to change.

	THE TRIM IS DOING REAL WORK. "Really Fast" is mastered hot: -10.1 dB, 5 dB over the lobby set
	and 11 dB or more over the stand-in race music it replaced. Untrimmed it would be the loudest
	thing on the road, over the engine and the near-misses, and the crossfade into a run would jump
	with it. 0.55 sets it level with the lobby. ]]
MusicConfig.Driving = {
	{ Id = 1846911135, Name = "Really Fast", Seconds = 198, Volume = 0.55 }, -- -10.1 dB
}

--[[ A WORLD'S OWN LIST, keyed by the index into `WorldConfig.Worlds`, which OVERRIDES `Driving` on
	that world's road. Empty, so every road plays the driving list.

	To give a road its own music, add `[index] = { ...tracks }` in the shape above. A key that is
	not a world is harmless, and nothing here validates against `WorldConfig`, on purpose: a
	mismatch should read as the wrong music in a playtest, not as a config that refuses to load. ]]
MusicConfig.Worlds = {} :: { [number]: { Track } }

-- === Derived ================================================================

export type Track = { Id: number, Name: string?, Seconds: number?, Volume: number? }

--- The lobby's context token. A world's is its index, so this is the one that needs a name.
MusicConfig.LobbyContext = "lobby"

--[[ Published on Dispatcher whenever the mute changes, however it changed — a press, or the
	server's saved answer arriving. The topbar button is drawn from it and decides nothing, the
	same bargain the world cards make with `WorldConfig.StateEvent`. ]]
MusicConfig.StateEvent = "MusicState"

--[[ Which list plays in `context`: the lobby token (or nil, which means the same) for everywhere
	that is not a run, a world index for a road.

	ALWAYS ANSWERS WITH A LIST, possibly an empty one — a caller should never have to hold a nil
	playlist, and an empty list is a real answer meaning "nothing is configured", which the
	controller renders as silence rather than as a stall. ]]
function MusicConfig.playlistFor(context: unknown): { Track }
	if type(context) == "number" then
		local list = MusicConfig.Worlds[context]
		if list and #list > 0 then
			return list
		end
		-- Note 2: a world with no list of its own plays the driving list, and no driving list is the lobby's.
		if #MusicConfig.Driving > 0 then
			return MusicConfig.Driving
		end
		return MusicConfig.Lobby
	end
	return MusicConfig.Lobby
end

--- A track's effective volume: the base level times its own trim (note 4).
function MusicConfig.volumeOf(track: Track): number
	local trim = tonumber(track.Volume) or 1
	return MusicConfig.Volume * trim
end

--- Every id in every list, deduplicated. For preloading, and for anything that wants to audit them.
function MusicConfig.allTracks(): { Track }
	local seen: { [number]: boolean } = {}
	local out: { Track } = {}

	local function take(list: { Track })
		for _, track in list do
			if not seen[track.Id] then
				seen[track.Id] = true
				table.insert(out, track)
			end
		end
	end

	take(MusicConfig.Lobby)
	take(MusicConfig.Driving)
	for _, list in MusicConfig.Worlds do
		take(list)
	end
	return out
end

return MusicConfig
