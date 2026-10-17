--[[
	AudioConfig
	-----------
	HOW LOUD THE GAME IS, as the player decides it. Two settings, one per half of the mix: the
	SOUNDTRACK, and EVERYTHING ELSE. Read by `MusicController` and `SoundController`, which apply
	them, by `Pages/Settings`, which draws the two sliders, and by `SettingsService`, which
	remembers them.

	A PLAYER VOLUME IS A MULTIPLIER ON THE AUTHORED MIX, NEVER THE MIX ITSELF. 1 means "however
	loud the game was built to be" and is the default for both, so a player who never touches
	either slider hears exactly what shipped. That is the whole contract, and it is what lets the
	levels in `MusicConfig.Volume`, in the SoundService groups and on individual clips go on being
	the mix: this file scales them, it does not replace them.

	=== WHY THE MUSIC MUTE IS STILL IN `MusicConfig` ============================================

	Because the mute is the TOPBAR BUTTON and it predates this screen by a long way, and because
	moving a live profile key to buy tidiness is a migration for nothing (`SettingsService` makes
	the same argument about `MusicService`). What changed is that the button and the slider are now
	ONE FACT rather than two: `MusicController.isMuted()` answers `volume <= 0`, the button sets the
	volume to zero and back, and the slider dragged to zero mutes. A separate mute flag beside a
	volume slider is the arrangement where pressing unmute does nothing because the slider is at 0,
	and there is no way to write that bug if the two cannot disagree.

	The old boolean is still written (`MusicConfig.ProfileKey`) so a build that rolls back reads a
	sensible answer, and it is still what an old profile is seeded from. `Music.ProfileKey` below
	is what wins when both are present.

	=== WHY SFX IS A SWEEP AND MUSIC IS ONE GROUP ===============================================

	The soundtrack plays through exactly one SoundGroup that `MusicController` owns, so its volume
	is one number on one instance. Sound effects are not like that and cannot be made to be:
	SoundGroups DO NOT NEST in Roblox (there is no `SoundGroup.SoundGroup`), and most of the noise
	this game makes comes from `Sound` instances authored inside the cars with no group at all.

	So `SoundController` does two things instead of one. It scales every SoundGroup under
	`SoundService` that is not on `Sfx.Exclude`, remembering each one's authored level so the
	scaling is reversible; and it adopts every ungrouped `Sound` in the Workspace into a master
	group of its own (`Sfx.GroupName`) so the engines, the doors and the crashes ride the same
	number. See that file for the adoption's cost and why it is affordable.
]]

local AudioConfig = {}

--[[ Master switch for the two ROWS. Off = no volume sliders on the settings screen and neither
	controller touches a level, so the game plays at its authored mix and nothing can change it.
	Each half has its own switch below as well, for taking one row out without the other. ]]
AudioConfig.Enabled = true

--[[ THE SLIDER'S GRAIN. A volume slider that lands on 47% is a slider you cannot put back where it
	was; one that steps in twentieths can be dragged to exactly half and exactly off, which is what
	people actually want from this control. It is also what makes the readout honest: every value
	the slider can hold is a whole number of percent.

	Fine enough that a drag still feels continuous at the size this panel renders at (the track is
	about 220px on a 1080p screen, so a step is 11px). ]]
AudioConfig.Step = 0.05

--- How long a level takes to arrive after the slider moves. Short: this has to feel like the knob
--- is dragging the sound rather than steering it.
AudioConfig.RampSeconds = 0.08

--[[ WHAT A PROFILE THAT HAS NEVER BEEN ASKED SAYS, and it is a negative number rather than nil for
	one reason: a nil is what a key that has not been RECONCILED yet also looks like, and the two
	need telling apart.

	It matters exactly once, for the music, and it is what makes the mute survive this feature
	landing. A player who muted the game last month has `MusicMuted = true` and no level at all;
	reconcile fills their new `MusicVolume` in with the template's value, and if that value were the
	default they would come back un-muted with nothing to blame. `SettingsService` reads this
	sentinel as "never chosen" and inherits the old boolean instead.

	It is never a level. Everything that takes one runs it through `clamp`, which folds a negative
	into the fallback rather than into 0. ]]
AudioConfig.Unset = -1

-- === The soundtrack =========================================================

AudioConfig.Music = {
	Enabled = true,

	--[[ Full, which is `MusicConfig.Volume` and the track trims exactly as mixed. See the header:
		a player volume is a multiplier and its default has to be the identity, or every build
		would ship quieter than it was tuned. ]]
	Default = 1,

	--[[ Where it is kept between sessions, and the three names that get it there. TOP-LEVEL in the
		profile for the reason every other preference gives: `PlayerProfile`'s string path is a
		recursive key search, so a nested key is a bug waiting for a table with the same name.

		`Attribute` is a SEED, not a channel, exactly as the mute's and the sky's are: written when
		the profile lands, read once on the way in, and never listened to again. ]]
	ProfileKey = "MusicVolume",
	Attribute = "MusicVolume",
	RemoteName = "SetMusicVolume",

	--- Published on `Dispatcher` with the new level whenever it moves, however it moved. The slider
	--- is drawn from this and decides nothing, the same bargain the topbar's mute button makes.
	StateEvent = "MusicVolumeState",

	Copy = {
		Row = "Music",
	},
}

-- === Everything else ========================================================

AudioConfig.Sfx = {
	Enabled = true,

	Default = 1,

	ProfileKey = "SfxVolume",
	Attribute = "SfxVolume",
	RemoteName = "SetSfxVolume",
	StateEvent = "SfxVolumeState",

	--[[ The master group ungrouped Sounds are adopted into. Adopted itself if one of this name is
		already authored under `SoundService`, so the mix can be trimmed in Studio without a build:
		its Volume AS FOUND is what 100% means. Absent, one is made at runtime at Volume 1.

		Same rule and same trap as `MusicConfig.SoundGroupName` names for the music group. ]]
	GroupName = "SFX",

	--[[ SoundGroups this slider must not touch, by name.

		BOTH ARE THE OTHER SLIDER'S. The soundtrack plays through `MusicConfig.SoundGroupName` and
		the car radios through `RadioConfig`'s own group, which is muted alongside the music rather
		than inside it. A player turning sound effects down is not asking for the radio to go quiet,
		and scaling either of these here would mean two controllers writing one Volume and the last
		one to run winning. ]]
	Exclude = {
		Music = true,
		StarMusic = true, -- StarController follows the Music slider; never scale it with SFX.
		Radio = true,
		CarSounds = true, -- the Car sounds slider's (`AudioConfig.Car`); never scaled twice.
	},

	--[[ Where the ungrouped Sounds are looked for.

		WORKSPACE, AND WORKSPACE ONLY. Every clip this slider is for is either in a SoundGroup
		already (the UI, the near misses, the siren) or is parented inside a car, and a car is in
		the Workspace. Sounds under `PlayerGui` are the UI's and are grouped; sounds under
		`ReplicatedStorage` are templates that get cloned into the Workspace before they play.

		THE COST IS ONE `DescendantAdded` CONNECTION ON WORKSPACE, which is a hot signal in this
		game because the road is built client-side a tile at a time. The handler is an `IsA` test
		and an early return, measured in tens of nanoseconds, so a tile of two hundred parts costs
		less than a tenth of a millisecond. That is affordable; anything doing real work in there
		would not be. ]]
	AdoptFrom = "Workspace",

	Copy = {
		Row = "Sound effects",
	},
}

--[[ THE CAR SOUNDS LEVEL (2026-10-15, "add car sounds slider to the settings menu"). WAS: engines,
	tyres and drifts were ungrouped Sounds the SFX slider adopted into its master group, so the
	loudest thing in the game rode the same knob as the UI clicks. IS: they are adopted into a group
	of their own, `GroupName`, scaled by this slider alone (and excluded from the SFX one above).

	WHAT COUNTS AS A CAR SOUND (`SoundController._isCarSound`): an engine layer (`EngineAudio.Prefix`),
	any Sound under a car's `Effects` folder (the rigs' engine, door and tyre clips), and the named
	ones in `Names` (the lobby drift, the test engine). A Sound already in a group is never taken,
	the SFX slider's rule. Same contract as `Sfx`: 1 is the mix as shipped, the level multiplies.
	`Enabled = false`: no row, and car sounds go back under the SFX slider, as before. ]]
AudioConfig.Car = {
	Enabled = true,
	Default = 1,
	ProfileKey = "CarVolume",
	Attribute = "CarVolume",
	RemoteName = "SetCarVolume",
	StateEvent = "CarVolumeState",
	GroupName = "CarSounds",
	EffectsFolder = "Effects",
	Names = { DriftSound = true, TestEngine = true },
	Copy = {
		Row = "Car sounds",
	},
}

-- === Reading it =============================================================

--[[ `value` as a level this file will vouch for: a number, in range, and on the grain. Everything
	that takes a volume from anywhere (a slider, a remote, a profile, an attribute) goes through
	this, so there is one definition of a valid level rather than one per caller.

	NEGATIVE IS NOT ZERO, IT IS "NOT A LEVEL", and falls back rather than clamping up. That is what
	makes `Unset` above readable as a sentinel by everything, including a caller that has never heard
	of it. Above 1 does clamp down: too loud is a value, just not one we will honour.

	`isSet` is the same test without the fallback, for the one caller that needs to know whether a
	stored value is an answer at all. ]]
function AudioConfig.isSet(value: unknown): boolean
	local number = tonumber(value)
	return number ~= nil and number == number and number >= 0
end

function AudioConfig.clamp(value: unknown, fallback: number?): number
	if not AudioConfig.isSet(value) then
		return fallback or 0
	end
	local number = math.min(tonumber(value) :: number, 1)
	return math.round(number / AudioConfig.Step) * AudioConfig.Step
end

--- What the readout beside a slider says. Rounded rather than truncated, so 0.95 is 95% and not
--- 94%, and always a whole number because `Step` guarantees one.
function AudioConfig.format(value: number): string
	return string.format("%d%%", math.round(math.clamp(value, 0, 1) * 100))
end

return AudioConfig
