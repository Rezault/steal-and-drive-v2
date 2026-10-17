--[[
	RadioConfig
	-----------
	THE CAR RADIO: a Robux game pass, four stations, and the option of pasting your own track — and
	whatever you put on comes out of YOUR car, in the world, for everyone standing near it. Read by
	`RadioService` (which decides what a car is allowed to play) and `RadioController` (which is the
	only thing that ever makes a sound).

	=== READ THIS FIRST: IT IS THE FIRST PASS, NOT THE FIFTH PRODUCT ===========================

	Every other thing sold in this game is a DEVELOPER PRODUCT and they all have the same shape:
	Roblox delivers a receipt, `DevProductsHandler` banks a counter on the profile, and a feature
	spends it. That shape exists because a receipt arrives when it arrives — mid-race, next session,
	days later after a retry — and a reward that only exists while a panel is on screen is Robux
	paid for nothing.

	A PASS HAS NOTHING TO BANK. Ownership lives on Roblox, `UserOwnsGamePassAsync` is the only copy
	that counts, and there is no receipt to process at all. So nothing about this appears in
	`DevProductsHandler`, nothing about it is in `Settings.TEMPLATE` except a REMEMBERED STATION
	(which is a preference, not an entitlement — see `ProfileKey`), and `RadioService` caches an
	answer from Roblox rather than reading the profile. If a second pass is ever added, that is the
	division to copy.

	=== THE SERVER HAS NO PART IN THE SOUND ====================================================

	This is `MusicService` / `MusicController`'s split, made again and for the same reason, and it
	is the single most important thing about how this feature is built.

	THE SERVER DECIDES *WHAT* IS ON: it owns the pass check, the station list, the audio-id
	validation and the three attributes it stamps on the car. It creates no Sound, sets no volume,
	and runs no playlist timer.

	THE CLIENT DECIDES *HOW IT SOUNDS*: every listener builds their own `Sound` on the car in front
	of them, in their own SoundGroup, at their own distance, and puts it away when the car streams
	out. Four things fall out of that and every one of them is load-bearing:

	  • THE MUSIC MUTE WORKS ON IT. `MusicConfig`'s topbar button is a client-side SoundGroup fade;
	    a Sound the server made would sit outside that group and would be the one piece of music in
	    the game the mute button could not touch. Somebody else's car is exactly the music a player
	    reaches for that button about.
	  • STREAMING IS FREE. `StreamingEnabled` means a lobby car is simply not there for a client
	    standing across the map, and a client-built Sound is created when the car arrives and
	    destroyed when it goes. A server-built one replicates to people who cannot see the car.
	  • THE PLAYLIST NEEDS NO TIMER ANYWHERE. See the next section — the schedule is a pure function
	    of the clock, so there is no `task.delay` on the server per car, and a listener who walks up
	    halfway through a song hears the middle of it rather than the start.
	  • A CLIENT THAT LIES ABOUT IT ONLY LIES TO ITSELF. The worst a hacked client can do here is
	    change what its own speakers play, which is the same "worst case" `MusicService`'s header
	    describes for the mute.

	=== THE STATION SCHEDULE IS A PURE FUNCTION OF THE CLOCK ===================================

	A station is a list, and a list has to advance. The obvious build is a server loop per playing
	car that swaps the track when the last one ends; this does not have one, and `sliceAt` is why.

	The car carries THREE attributes and nothing else — which station, which custom track, and the
	server clock reading at the moment the radio was switched on. `sliceAt(station, seed, elapsed)`
	turns those into "this track, this many seconds in, this long left", deterministically. Every
	listener runs it, they all get the same answer, and nobody has to be told anything:

	  • THEY ARE IN SYNC BY CONSTRUCTION. Two people standing at the same car are not kept in step
	    by messages that could be dropped or arrive late — they compute the same value from the same
	    clock. `workspace:GetServerTimeNow()` is the same number on every machine in the server.
	  • ARRIVING LATE IS THE NORMAL CASE AND IT IS FREE. A player who walks up eighty seconds into a
	    song, or whose client only just streamed the car in, starts at second eighty. There is no
	    "join in progress" path because there is no progress to join.
	  • A REJOINING OWNER RESUMES. `RadioService` restores the remembered station on the next car
	    they spawn with a fresh stamp; nothing has to remember where the needle was.

	THE ORDER IS SHUFFLED PER CYCLE, not fixed: `sliceAt` re-deals the list every time it wraps, so
	four tracks do not become an audible four-track loop. Deterministic all the same — the shuffle
	is seeded by the stamp plus the cycle number, so every listener deals the same hand.

	=== WHY THERE ARE STATIONS AT ALL, AND NOT JUST A BOX TO PASTE AN ID INTO ==================

	Because most ids do not work, and a radio that mostly does not work is worse than no radio.

	Roblox audio uploaded since the 2022 privacy change is PRIVATE to its uploader unless they
	explicitly grant an experience permission or publish it to the Creator Store. So the classic
	boombox — a text box, paste any id — fails for the great majority of ids a player will try, and
	it fails SILENTLY: `Sound.Ended` never fires, no error is raised anywhere, and the player is
	looking at a car that is simply not making a noise. That is a refund request.

	SO THE STATIONS ARE THE PRODUCT AND THE BOX IS THE EXTRA. Four lists of Creator Store tracks,
	every one of them checked (see `Stations`), so a player who buys this and presses the first
	thing they see hears music. `Custom` is still there, because pasting your own song is half of
	why anyone wants a radio — but it is the second thing on the panel, and it is the one path that
	can honestly answer "that track will not play here" (`RadioController._armLoad`).

	=== IT IS A LOBBY-CAR FEATURE ==============================================================

	The radio plays out of a car standing in the lobby (`LobbyCarConfig`), and not out of a race
	car. Two reasons, and the first one alone would be enough:

	  • THERE IS NOBODY TO PLAY IT TO. A run happens on a road that exists only on the driver's own
	    client (`RaceService`), so a race car is not in a place other players can walk up to. A
	    radio that only its owner can hear is a soundtrack, and the game already has one.
	  • THE RUN ALREADY HAS MUSIC, chosen per world by `MusicConfig` and crossfaded in and out at
	    the run's own brackets. A second track over the top of it is not a feature.

	Nothing here would have to change to lift that: it is `RadioService._carOf` asking
	`LobbyCarService` and nothing else.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- The rbxsync-generated id table. The pass id is resolved out of here by KEY, never pasted — see
--- `Key` below and the header on `shared/GameIds`.
local GameIds = require(ReplicatedStorage.shared.GameIds)

local RadioConfig = {}

--[[ Master switch. Off = no topbar button, no panel, no sound, and every request refused. A car
	already playing when it is switched off goes quiet on the next spawn, because the attributes are
	only ever written by a request this refuses. ]]
RadioConfig.Enabled = true

-- === The pass ===============================================================

--[[ Ties this to its `[passes.<key>]` block in `rbxsync.toml`. The id is filled in below from the
	rbxsync-generated `GameIds` and is 0 only if the sync has never been run — which reads
	downstream as "this cannot be sold" and takes the whole feature off the screen, never as "it is
	free". Same contract as `RandomCarConfig.Key`. ]]
RadioConfig.Key = "Radio"
RadioConfig.PassId = GameIds["passes." .. RadioConfig.Key] or 0

--[[ What the PANEL says, in Robux. Roblox charges what the pass is priced at in `rbxsync.toml`, so
	this is a display value kept honest by hand — the same contract `OfflineConfig.Boost.Price` and
	`RandomCarConfig.Price` have, and the same one-line failure if it is broken. ]]
RadioConfig.Price = 49

--[[ Mirrored onto the Player by `RadioService` the moment Roblox has answered, and again after a
	purchase. The panel is drawn from it and decides nothing — the same bargain the world cards make
	with `WorldConfig.StateEvent` and the Cars Inventory makes with `LobbyCarConfig.SpawnedAttribute`.

	UNSET IS NOT "NO". It means "Roblox has not answered yet", and the panel says so rather than
	offering to sell the pass to somebody who may already own it — see `RadioController._paint`. ]]
RadioConfig.OwnedAttribute = "RadioPass"

--- Whether the pass can be sold at all. False takes the feature off the screen entirely; see `PassId`.
function RadioConfig.sellable(): boolean
	return RadioConfig.Enabled and RadioConfig.PassId ~= 0
end

-- === What a playing car carries =============================================

--[[ THE WHOLE PROTOCOL, and it is three attributes on the car Model. Everything a listener needs to
	work out what it should be hearing is in here; nothing else is ever sent.

	`Station` is a station's `Key`, or `CustomStation` for a pasted track, or absent/"" for a radio
	that is off. `Track` is the audio id, and it is only meaningful for a custom track — a station
	works out its own from the clock (see the header). `StartedAt` is `workspace:GetServerTimeNow()`
	at the moment the radio was switched on, and it is doing two jobs at once: it is the origin the
	schedule is measured from, AND it is the seed the per-cycle shuffle is dealt from.

	ONE STAMP FOR BOTH JOBS rather than a fourth attribute, because the two can never disagree that
	way: a shuffle seeded independently of the origin could be re-rolled without the clock moving,
	and two listeners who read the pair a frame apart would deal different hands. ]]
RadioConfig.StationAttribute = "RadioStation"
RadioConfig.TrackAttribute = "RadioTrack"
RadioConfig.StartedAttribute = "RadioStartedAt"

--- The `Station` value meaning "the id in `Track` is a track the player pasted", rather than a key
--- into `Stations`. Not a station key itself, so it can never collide with one.
RadioConfig.CustomStation = "@custom"

--[[ Every lobby car is tagged with this at spawn, playing or not, and `RadioController` watches the
	tag rather than the folder.

	TAGGED ALWAYS, NOT ONLY WHILE PLAYING, and that is the part worth keeping. `CollectionService`'s
	added/removed signals fire on STREAMING as well as on parenting, which is exactly the event a
	listener needs — a car that streams back in has to have its Sound rebuilt, and it arrives
	carrying the attributes that say what to build. Tagging only while the radio is on would make
	"the radio was switched on" and "the car came into range" two different arrival paths for the
	same work. ]]
RadioConfig.CarTag = "RadioCar"

-- === Talking to the server ==================================================

--[[ client -> server. `station` is a station key, `CustomStation`, or nil for "turn it off";
	`trackId` is only read for a custom track. `RadioService` re-derives everything else. ]]
RadioConfig.RemoteName = "RequestRadio"

--[[ server -> client, and it is the panel's status line and nothing more: `(ok: boolean, message:
	string)`. A refusal that the player could not otherwise see the cause of gets one; a refusal
	because they do not own the pass does NOT, because the answer to that is Roblox's own purchase
	prompt opening in front of them. ]]
RadioConfig.ReplyName = "RadioReply"

--[[ Published on `Dispatcher` whenever the local player's own radio state changes — the station
	they have on, or nil. The topbar caption is drawn from it. ]]
RadioConfig.StateEvent = "RadioState"

--[[ Published on `Dispatcher` when the radio PANEL opens or shuts, `(open: boolean)`, so the topbar
	button can follow it. The panel shuts without its button (its X, B on a pad), and a button left
	selected over a shut panel is what reopened the radio when SETTINGS was pressed: TopbarPlus
	deselects every other icon when one is selected, and that deselect arrives looking like a press.
	See `TopbarController._buildDoor`. ]]
RadioConfig.PanelEvent = "RadioPanel"

--[[ The `Action` attribute on the new HUD grid's Radio cell (`BuildHudV2`), published on `Dispatcher`
	as `UIAction` by `ButtonPress` and answered by `RadioPanelController`. An action rather than a
	`Page` because the radio panel is not a `UIController` page. Dylan moved the radio off the topbar
	and into the grid on 2026-09-16; the topbar chip now only comes back for a race, when the grid is
	hidden (`TopbarController._setRacing`). ]]
RadioConfig.PanelAction = "OpenRadio"

--[[ Per-player floor between accepted requests. Same shape and the same reason as
	`LobbyCarConfig.RequestCooldown`: this is a client-driven remote and a custom track costs a web
	call. Stamped on the ATTEMPT, so a refusal is as cheap as a change. ]]
RadioConfig.RequestCooldown = 1

--[[ Where the remembered station lives on the profile (top-level, for the reason every other
	top-level key gives: `PlayerProfile`'s string path is a recursive key search).

	IT IS A PREFERENCE, NOT AN ENTITLEMENT, which is the distinction the header's first section
	draws. Nothing is unlocked by it and nothing is spent from it: it is the station you had on last
	time, so the car you spawn tomorrow comes up playing what it was playing today. A player without
	the pass can hold one — they simply never get to hear it — and that is deliberate, because
	buying the pass then rewards them with the radio already tuned to the last thing they tried.

	A CUSTOM TRACK IS NOT REMEMBERED, only stations. Storing an arbitrary id would mean re-validating
	somebody's saved number on every spawn (a web call on a hot path), and an id that was fine last
	month and has since been moderated would come back as a car playing nothing. ]]
RadioConfig.ProfileKey = "RadioStation"

-- === How it sounds ==========================================================

--[[ The Sound every listener builds on the car. All of it is client-side (header, section 2), so
	these are the numbers each machine applies to its own copy.

	`Volume` SITS UNDER THE SOUNDTRACK'S 0.35 ON PURPOSE. This is somebody else's music arriving
	uninvited in a shared space, and the difference between a car going past with the windows down
	and a car nobody can get away from is entirely this number.

	THE ROLL-OFF IS THE WHOLE SOCIAL CONTRACT and it is worth reading as one shape rather than as
	two numbers. `MinDistance` is how far the sound carries at full level — a bit over a car length,
	so standing AT the car is the full experience — and `MaxDistance` is where it reaches silence.
	100 studs is deliberately modest: it is far enough that a car parked across the forecourt is
	part of the scene, and near enough that walking away from one actually works. A player who
	cannot escape another player's music has been given a griefing tool, which is the same thing
	`LobbyCarConfig`'s collision rule exists to prevent in the physical layer.

	`InverseTapered` rather than `Linear`, because linear roll-off holds a sound near full volume for
	most of its range and then collapses, where inverse falls off the way distance actually sounds.
	Tapered rather than plain inverse because plain inverse never quite reaches zero — it only
	approaches it — so `MaxDistance` would be the point the music got quiet rather than the point it
	stopped, and "walk away from it" has to actually work. ]]
RadioConfig.Sound = {
	Volume = 0.28,
	RollOffMode = Enum.RollOffMode.InverseTapered,
	MinDistance = 26,
	MaxDistance = 100,

	--[[ The SoundGroup all radios play through, created client-side on demand. SEPARATE FROM
		`MusicConfig.SoundGroupName`, and muted alongside it rather than inside it: two groups means
		the mix can be trimmed independently in Studio (a radio that fights the soundtrack is one
		number, not a re-balance), while `RadioController` subscribing to `MusicConfig.StateEvent`
		means one button still silences both. ]]
	GroupName = "Radio",

	--- How long a radio takes to fade up when it starts, and down when it stops. Short: a radio
	--- being switched on is a switch, not a swell.
	FadeSeconds = 0.35,
}

--[[ The lobby soundtrack makes way for a car radio. While the listener is within `Radius` of a car
	whose radio is ON, `RadioController` publishes `NearbyEvent` true and `MusicController` fades the
	lobby music out and pauses it; past `ReleaseRadius` it fades back in where it left off.

	TWO RADII, NOT ONE, so standing on the line does not flick the soundtrack in and out every poll.
	Measured from the camera, which is where Roblox hears from. Any car's radio counts, not only
	yours: two songs at once is the same clash whoever owns the car. Only the LOBBY playlist ducks;
	a road's music never does. A radio in the gap between two tracks still counts as on, so the
	soundtrack does not pop in for 2.5 seconds between songs. ]]
RadioConfig.DuckMusic = {
	Enabled = true,
	Radius = 70,
	ReleaseRadius = 85,
	PollSeconds = 0.25,
	FadeSeconds = 0.75,
}

--- Published on `Dispatcher` as `(near: boolean)` when the listener moves in or out of a playing
--- radio's `DuckMusic.Radius`. `RadioController.isNearby` answers the same question on demand.
RadioConfig.NearbyEvent = "RadioNearby"

--- Air between tracks on a station, and the same 2.5s the soundtrack leaves between its own — the
--- silence is what tells you a playlist is a playlist. Part of the schedule, so it is the same on
--- every listener's machine by construction.
RadioConfig.GapSeconds = 2.5

--[[ How long a track gets to prove it is real before the listener gives up on it.

	THE SAME WATCHDOG `MusicController` HAS, and it exists here for a sharper version of the same
	reason. `TimeLength` is 0 until an asset streams in and stays 0 forever for an id that was
	moderated, made private, or simply mistyped — and a custom track is, by definition, a number a
	player typed. Without this, a bad id is not a skipped track: it is a car that silently makes no
	noise and an owner who thinks the pass they just bought is broken.

	Longer than the soundtrack's 20s would only delay that message; shorter would call a slow
	download a failure on a bad connection. ]]
RadioConfig.LoadTimeout = 20

-- === The custom track =======================================================

--[[ Pasting your own audio id. See the header's fourth section for why this is the SECOND thing on
	the panel rather than the whole feature.

	`MaxSeconds` is a ceiling on length, and it is not about storage — it is the only defence
	against the thing this feature would otherwise be abused for. An hour-long upload set playing in
	a public lobby is a car that has to be waited out; the cap makes every custom track something
	that ends.

	IT IS ENFORCED BY THE LISTENER, NOT BY THE SERVER, and that is forced rather than chosen: the
	server has no way to learn an audio's duration. `GetProductInfo` returns the asset type and
	whether it is public and no length at all (checked, 2026-08-24), so the only machine that knows
	how long a track is, is one that has loaded it. `RadioController._armLoad` has the argument for
	why that is nonetheless the right place for THIS rule — the ear it protects is the one enforcing
	it, so a patched client only chooses to keep listening.

	The two checks the SERVER can make it does make, in `RadioService._checkTrack`: is this an Audio
	asset at all, and is it one this experience is allowed to play.

	`MinLength` / `MaxLength` bound the STRING the box will accept, so a paste of a whole URL or a
	line of text never reaches the web call. Roblox asset ids are currently 9-16 digits; the range
	is deliberately wider than that at both ends, because an id length is Roblox's to change and a
	config that refuses tomorrow's ids would be a very confusing bug. ]]
RadioConfig.Custom = {
	Enabled = true,
	MaxSeconds = 600,
	MinLength = 4,
	MaxLength = 20,
	Placeholder = "Paste an audio ID",
}

--[[ Pull the audio id out of whatever the player put in the box, or nil.

	IT ACCEPTS A URL AS WELL AS A NUMBER, because a player who has found a song on the Creator Store
	has a browser tab, and what is in their clipboard is a link. Taking the digits out of it here
	costs one pattern and saves the panel having to explain a format.

	Returns nil rather than 0 for anything it cannot read, so a caller can never treat a failure as
	the id zero. ]]
function RadioConfig.parseId(text: unknown): number?
	if type(text) ~= "string" then
		return nil
	end
	local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
	if #trimmed < RadioConfig.Custom.MinLength or #trimmed > 200 then
		return nil
	end

	--[[ The LAST run of digits, not the first. A Creator Store URL is
		`.../store/asset/1234567890/Some-Song-2` — the id is the long number in the middle, and a
		title ending in a number is common enough to matter. So: take every run, keep the longest,
		and on a tie keep the earliest, which is the id in every URL shape Roblox uses. ]]
	local best: string? = nil
	for run in string.gmatch(trimmed, "%d+") do
		if best == nil or #run > #best then
			best = run
		end
	end
	if best == nil or #best < RadioConfig.Custom.MinLength or #best > RadioConfig.Custom.MaxLength then
		return nil
	end

	local id = tonumber(best)
	if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then
		return nil
	end
	return id
end

-- === What the panel says ====================================================

--[[ Every word `RadioPanelController` puts on screen, in one place — the same arrangement
	`PlotConfig.Rename` and `OfflineConfig`'s `Boost*` strings have, and for the same reason: copy is
	the thing most often changed by somebody who is not going to open a controller.

	THE SERVER'S REFUSALS ARE NOT IN HERE, deliberately. `RadioService` answers "spawn a car first",
	"that track is private" and the rest inline, because each one is a sentence about a specific
	check and belongs beside the check that produced it — a table of them here would be a list of
	messages with nothing to say when each is used. These are the things the screen says on its own.

	`R$%d` IS THE HOUSE FORM for a Robux price (`OfflineConfig.BoostBuyFormat`,
	`RandomCarConfig.CardBuyFormat`), and the number it takes is `Price` above — which is a display
	value kept honest by hand against `rbxsync.toml`. ]]
RadioConfig.Copy = {
	Title = "Car Radio",

	--- The one button with two meanings (`RadioPanelController._paint`): a way back for an owner,
	--- the price for everybody else, and the third state for a pass Roblox has not answered on yet.
	Off = "Off",
	Buy = "Get radio   R$%d",
	Checking = "Checking...",

	--- The custom track's own button.
	Play = "Play",

	--[[ The soundtrack switch, which shares the bottom row with the button above and is the game's
		background music rather than anything to do with a car (`MusicConfig` note 6).

		BOTH NAME THE STATE AND NOT THE ACTION, which is the convention every media player has
		already taught the player and the one the topbar icon this replaced was captioned in. The
		pill is dimmed when it says OFF, so the two halves say the same thing twice: nobody has to
		work out whether a press turns it on or reports that it is. ]]
	MusicOn = "Music on",
	MusicOff = "Music off",

	--[[ The line under the title. Five of them, and `RadioPanelController._nowPlayingText` picks
		between them in the order the player would ask the questions in — see its own note on why
		"spawn a car" outranks even the price. ]]
	OnStation = "Now playing: %s", -- the track, or the station's name until the track is known
	OnCustom = "Playing your own track",
	NoCar = "Spawn one of your cars to use the radio",
	Pitch = "Play music out of your car for everyone nearby",
	Idle = "Pick a station",

	--- What the panel refuses on its own, before the server has been asked anything.
	BadId = "Paste an audio ID, or a link to one.",
	CustomOff = "Custom tracks are switched off right now.",

	--[[ ...and the two refusals a LISTENER makes rather than the server
		(`RadioController._armLoad`). `%d` is `Custom.MaxSeconds` in whole minutes. ]]
	TooLong = "That track is too long. The limit is %d minutes.",
	WillNotPlay = "That track will not play here. Try another one.",
}

-- === The stations ===========================================================

export type Track = { Id: number, Name: string, Seconds: number }
export type Station = { Key: string, Name: string, Blurb: string, Tracks: { Track } }

--[[ FOUR STATIONS, SIXTEEN TRACKS, ALL OF THEM CHECKED — 2026-08-24.

	Every id below came off the Creator Store's licensed audio library and every one was verified
	the way `MusicConfig` note 3 describes: real `Sound` instances, `ContentProvider:PreloadAsync`,
	`IsLoaded` true and a non-zero `TimeLength` for all sixteen. The `Seconds` beside each is that
	MEASURED length, not the catalogue's, and it is not decoration — `sliceAt` schedules against it,
	so a number that is wrong here is a listener whose radio drifts out of step with the audio.

	CHECKING A NEW ID BEFORE IT GOES IN A LIST IS WORTH THE MINUTE IT COSTS, and more so than it is
	for the soundtrack: a bad id in `MusicConfig` is a few seconds of silence in a playlist only its
	own player hears, while a bad id here is a car in a public lobby making no noise with a paying
	owner sitting in it.

	FOUR RATHER THAN ONE BIG LIST, because a station is a CHOICE and the choice is most of what is
	being bought. One shuffled pool of sixteen would be the same music with nothing to pick.

	The names are the Creator Store's own, kept so a track can be found again; nothing reads them
	except the panel's now-playing line. ]]
RadioConfig.Stations = {
	--[[ The one a car game is expected to have, and the default for a new owner (`DefaultStation`).
		Drift phonk is the genre this whole category of game runs on; if a player buys this pass and
		presses exactly one button, this is the one they press. ]]
	{
		Key = "Drift",
		Name = "Drift FM",
		Blurb = "Phonk",
		Tracks = {
			{ Id = 123208818121704, Name = "Asphalt Phantoms", Seconds = 237.0 },
			{ Id = 110718293732117, Name = "Speed Drift Phonk", Seconds = 133.9 },
			{ Id = 112666300174210, Name = "Lethal Velocity", Seconds = 151.7 },
			{ Id = 89970906101910, Name = "Midnight Phonk Vibes", Seconds = 140.3 },
		},
	},

	--[[ The opposite end, and the one that makes the pass liveable in a shared space. Somebody has
		to be able to park a car outside their dealership and put something on that the six people
		standing near it will not resent. ]]
	{
		Key = "Cruise",
		Name = "Cruise 101",
		Blurb = "Lo-fi",
		Tracks = {
			{ Id = 123173764707481, Name = "Late Nights", Seconds = 193.6 },
			{ Id = 107825000149766, Name = "Late Night Commute", Seconds = 133.8 },
			{ Id = 112489000993233, Name = "Smooth Beats", Seconds = 139.3 },
			{ Id = 98374986066675, Name = "Night Chill Beats", Seconds = 194.7 },
		},
	},

	-- Retro, and the one that sounds most like a car stereo rather than a game soundtrack.
	{
		Key = "Neon",
		Name = "Neon Nights",
		Blurb = "Synthwave",
		Tracks = {
			{ Id = 92888430075812, Name = "Upbeat Synthwave", Seconds = 180.0 },
			{ Id = 139683217563657, Name = "Ridin' a Synthwave", Seconds = 218.5 },
			{ Id = 136153393604107, Name = "Synthwave Serenade", Seconds = 110.9 },
			{ Id = 112038236012512, Name = "Timelapse", Seconds = 183.1 },
		},
	},

	-- The theme of the game, more or less: this is a game about driving off in somebody else's car.
	{
		Key = "Getaway",
		Name = "Getaway",
		Blurb = "Trap",
		Tracks = {
			{ Id = 127756103878588, Name = "Night Rider", Seconds = 194.7 },
			{ Id = 104236851420263, Name = "312", Seconds = 124.7 },
			{ Id = 94674170756923, Name = "Trap Type Beat", Seconds = 215.0 },
			{ Id = 121901096844297, Name = "As Such", Seconds = 222.2 },
		},
	},
}

--[[ What a car comes up playing when its owner has the pass but has never chosen anything — a
	brand new owner's first spawn, and the fallback for a remembered station whose key no longer
	exists (a station renamed or dropped from the list above).

	A STATION AND NOT SILENCE, because the first thing a player does after buying this is spawn a
	car, and a car that comes out silent is a pass that looks like it did not work. ]]
RadioConfig.DefaultStation = "Drift"

-- === Derived ================================================================

--- The station with this key, or nil. The one lookup; nothing else indexes `Stations` by hand.
function RadioConfig.stationByKey(key: unknown): Station?
	if type(key) ~= "string" then
		return nil
	end
	for _, station in RadioConfig.Stations do
		if station.Key == key then
			return station
		end
	end
	return nil
end

--[[ A deterministic shuffle of `1..count`, dealt from `seed`.

	`math.random` IS NOT USABLE HERE and that is the whole reason this exists. Every listener has to
	deal the SAME hand from the same seed, and Roblox's global generator carries state that every
	other script on the machine also draws from — two clients would deal different orders, and the
	car would be playing a different song for each of them.

	MINSTD (Lehmer, 16807 / 2^31-1) because it is four lines, has no state outside this function,
	and is more than good enough to stop four tracks sounding like a fixed loop. ]]
local function dealOrder(count: number, seed: number): { number }
	local order = table.create(count)
	for i = 1, count do
		order[i] = i
	end

	-- Into MINSTD's 1..m-1 domain. Zero is the generator's fixed point, so it is stepped off it.
	local state = math.abs(math.floor(seed)) % 2147483647
	if state == 0 then
		state = 1
	end

	for i = count, 2, -1 do
		state = (state * 16807) % 2147483647
		local j = (state % i) + 1
		order[i], order[j] = order[j], order[i]
	end
	return order
end

--[[ WHAT A STATION SHOULD BE PLAYING `elapsed` SECONDS AFTER IT WAS SWITCHED ON. The whole schedule,
	and the reason nothing anywhere runs a playlist timer — see the header's third section.

	Returns (track, offsetIntoTrack, secondsLeftInThisSlice). A nil track means the gap between two
	tracks, which is a real answer and not a failure: the caller plays nothing and comes back when
	the slice runs out.

	`seed` is the car's `StartedAt` stamp. It is re-mixed with the CYCLE number, so the list is dealt
	afresh every time it wraps rather than repeating the same four in the same order forever — and
	still identically on every machine, because the cycle number is a function of the clock too. ]]
function RadioConfig.sliceAt(station: Station, seed: number, elapsed: number): (Track?, number, number)
	local tracks = station.Tracks
	if #tracks == 0 then
		return nil, 0, math.huge
	end

	local gap = RadioConfig.GapSeconds
	local total = 0
	for _, track in tracks do
		total += math.max(track.Seconds, 0) + gap
	end
	if total <= 0 then
		return nil, 0, math.huge
	end

	elapsed = math.max(elapsed, 0)
	local cycle = math.floor(elapsed / total)
	local within = elapsed - cycle * total

	--[[ The seed is quantised to whole seconds before the cycle is folded in. `StartedAt` is a float
		and two clients can read it back at slightly different precisions through the attribute; a
		seed taken from its fractional part would be a different hand on each of them. ]]
	local hand = dealOrder(#tracks, math.floor(seed) + cycle * 7919)

	for _, index in hand do
		local track = tracks[index]
		local length = math.max(track.Seconds, 0)
		if within < length then
			return track, within, length - within
		end
		within -= length
		if within < gap then
			return nil, 0, gap - within
		end
		within -= gap
	end

	--[[ Floating-point tail: `within` landed a hair past the end of the last gap. Answer with the
		start of the next cycle rather than with nothing — this recurses exactly once, because the
		argument is an exact cycle boundary and lands in the first track. ]]
	return RadioConfig.sliceAt(station, seed, (cycle + 1) * total)
end

--- Every track id on every station, deduplicated. For preloading, and for anything that wants to
--- audit them (the check described above `Stations` is this list).
function RadioConfig.allTracks(): { Track }
	local seen: { [number]: boolean } = {}
	local out: { Track } = {}
	for _, station in RadioConfig.Stations do
		for _, track in station.Tracks do
			if not seen[track.Id] then
				seen[track.Id] = true
				table.insert(out, track)
			end
		end
	end
	return out
end

return RadioConfig
