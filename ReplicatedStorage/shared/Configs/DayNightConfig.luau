--[[
	DayNightConfig
	--------------
	THE LOBBY'S CLOCK. One real quarter of an hour is one in-game day, and every player standing on
	the forecourt is standing in the same one. Read by `DayNightController` (which owns Lighting),
	`UIController/Pages/Settings` (which draws the three choices) and `SettingsService` (which remembers
	which one a player picked).

	=== SIX THINGS TO KNOW BEFORE EDITING ======================================================

	1. THE CLOCK IS DERIVED, NOT DRIVEN. Nothing counts up and nothing is broadcast: the time of day
	   is a pure function of `workspace:GetServerTimeNow()`, which every client in a server already
	   agrees on to the frame. That is what makes the sky SHARED without a single remote, and it is
	   the same bargain the dealership's income makes with its collect stamp: a value computed from
	   a timestamp cannot drift, cannot be missed by a late joiner, and costs nothing to replicate.

	2. THE LOOK IS KEYFRAMED AGAINST THE CLOCK, NOT AGAINST THE CYCLE. `Keys` below is a list of
	   skies indexed by `ClockTime`, and `lookAt` blends between them. The cycle's only job is to
	   move the clock. That split is what makes the DAY and NIGHT settings one line each: a locked
	   sky is the same `lookAt` call with a clock that stops moving.

	3. NOON STARTS FROM THE MAP, NOT FROM A HARDCODED PALETTE. Every colour field of every keyframe
	   is optional, and an absent field means "whatever this place is authored to". The `Day`
	   keyframes only add subtle exposure, reflections, soft shadows and post effects; the authored
	   daytime colours remain the source of truth. Only skies the builder did not author (dawn,
	   dusk, evening and night) carry absolute colours.

	4. NIGHT IS LIT BY THE MAP, NOT BY THIS FILE. Refitted on 2026-09-08 after counting what is
	   actually out there: the City road carries 129 lights and 269 neon parts spread evenly over
	   all six tiles, and the lobby carries another 107. Every one of them is the same sodium amber,
	   255,170,33 at brightness 13.7 and RANGE 30.

	   The first fit did not know that. It was made standing at plot 5, and the nearest lobby light
	   to any plot is 88 to 95 studs away against that range of 30, so not one of them reaches a
	   forecourt. Fitting there means fitting in the single darkest spot in the game, and what came
	   out was a bright blue wash doing the job the map's own lights already do everywhere else: a
	   flat navy sheet over a road that lights itself, with `Saturation` at -0.12 and a cool tint
	   draining the amber back out of 236 lamps.

	   So the wash is gone and the lamps do the work. What replaced it is warmer, slightly BRIGHTER
	   than the old one rather than darker, and positively saturated so the lit windows read yellow
	   and the sodium reads orange. The forecourt was checked against the old values at the same
	   camera and is more legible than before, not less, because colour separation does what the
	   flat lift was being asked to do. If it ever wants to go properly dark, the plots still need
	   lamps of their own first.

	5. THE GRADE IS OURS AND IT IS THE ONLY THING THAT MOVES THE SKYBOX. `Sky5` is a painted
	   texture, so it does not darken when the sun goes down: a `ColorCorrectionEffect` is the one
	   thing that reaches it, because post-processing runs over the whole frame including the sky.
	   That is why every keyframe carries a `Grade`. The night one is no longer doing most of the
	   work, though: the sky is sunk by the ATMOSPHERE (a dark `Color` with `Haze` over it), which
	   leaves the grade free to ADD saturation rather than cut it. That split is what lets the neon
	   be neon without the painted skybox turning back into a daytime blue.
	   The effect is our own instance, never the place's authored `ColorCorrection`.

	6. A RACE INHERITS WHATEVER THE LOBBY WAS. `DayNightController` stops writing for the length of
	   a run, `WeatherController` captures Lighting as it finds it and puts it back at the end, so a
	   run that starts at dusk is driven at dusk and the clock resumes where it left off. That is
	   free rather than designed: it falls out of the two files not fighting. `PauseDuringRace`
	   below is the whole of the arrangement and there is nothing on the race side to keep in step.

	   THE ONE THING THAT REACHES THE SKY MID-RUN is a press on this setting, and it goes THROUGH
	   the arrangement rather than around it: `DayNightController._rebase` hands the new look to
	   `WeatherController.rebase`, which swaps it in as the sky its event is composed over and
	   repaints. Still one file writing Lighting during a run. The settings gear sits on the topbar
	   during a race even though the rail and the pages do not, so that press is reachable, and
	   before the rebase existed it was accepted and saved while the sky sat still until the end.

	HOUSE RULE: no wiki-style double-bracket links in this comment, the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local DayNightConfig = {}

--[[ Master switch. Off = `DayNightController` captures nothing, writes nothing and creates no
	grade, the lobby stays at whatever the map is authored to, and the Time of day row does not
	appear on the settings screen. A complete switch, not something three call sites remember.

	TEMPORARILY OFF (2026-09-13): night made the road too dark to read traffic at speed. The map's
	authored lighting is the daytime look (see `LockedClock`), so off means permanent day. Saved sky
	preferences are untouched and come back as they were when this is switched on again. ]]
DayNightConfig.Enabled = false

-- === The cycle ==============================================================

--[[ How long one full 24 hours takes in real seconds.

	FIFTEEN MINUTES, and the number was chosen against how long a player is actually IN the lobby
	rather than against realism. A session is a run of a minute or two and then a stretch of
	business on the forecourt, so a cycle much longer than this means most players only ever see
	one sky and the feature may as well not exist. Much shorter and the sun visibly races, which
	stops reading as a time of day and starts reading as a strobe.

	At this length the keyframes below give roughly five minutes of daylight, four and a half of
	night, and the rest in dawn or dusk. ]]
DayNightConfig.CycleSeconds = 900

--[[ Where the cycle sits against the server clock, in HOURS of game time.

	The phase is `GetServerTimeNow()` folded into `CycleSeconds`, so with an offset of zero a
	server that starts at an arbitrary moment lands at an arbitrary time of day. That is fine and
	is left alone deliberately: a server should not always open at midnight, and no player can tell
	the difference between an arbitrary start and a designed one. Set this if a particular time of
	day is ever wanted for the first minute of a fresh server. ]]
DayNightConfig.Offset = 0

--[[ How long the sky takes to glide when the clock JUMPS rather than advances: a player switching
	the setting, and the moment a race hands the lobby back.

	IT IS A GLIDE AND NOT A CUT, and that is most of what makes the setting feel like something
	rather than a graphics toggle: switching to NIGHT fast-forwards the sun down through dusk in
	two seconds, which is the same movement the cycle makes slowly. The clock takes the SHORT way
	round the 24 hour circle, so nothing ever runs backwards through a whole day to get somewhere
	an hour away. ]]
DayNightConfig.GlideSeconds = 2.2

--[[ How often Lighting is written, in times per second.

	NOT EVERY FRAME. Writing `Lighting.Ambient` and friends is not free (each one dirties the
	engine's lighting state), and at this cycle length the clock moves 0.027 game-hours a second,
	so eight steps a second is a change of 0.003 per write. Nobody can see the stair and the cost
	is a twentieth of what a RenderStepped write would be. Raise it if a much shorter cycle ever
	makes the stepping visible. ]]
DayNightConfig.UpdateHz = 8

--[[ A run freezes the sky. See note 6: the controller stops writing between `RaceStart` and
	`RaceEnd` so that `WeatherController`, which captures Lighting at the start of a run and
	restores it at the end, is the only thing touching it while a race is on.

	TURNING THIS OFF IS NOT A TOGGLE, IT IS A FIGHT. Both files would be writing the same six
	properties from two different sources with no ordering between them. It is here to name the
	arrangement, not to offer the other half of it.

	A PRESS ON THIS SETTING STILL CHANGES THE SKY MID-RUN, and does not need this off to do it. See
	note 6: it is handed to `WeatherController` rather than written past it. ]]
DayNightConfig.PauseDuringRace = true

-- Authored world fixtures opt in by tag. A `NightLight` must be a Light; a `NightNeon` must be a
-- BasePart. Their current brightness/transparency is treated as the night look, so tagging existing
-- art does not require copying its tuned values into code.
DayNightConfig.Fixtures = {
	Enabled = true,
	LightTag = "NightLight",
	NeonTag = "NightNeon",
	DayBrightnessScale = 0,
	DayNeonTransparency = 0.38,
	DawnOff = 7.25,
	DawnStart = 5.6,
	DuskStart = 17.1,
	DuskOn = 19.15,
}

-- === The setting ============================================================

--[[ The three answers, as they are stored. The empty string is AUTO for the reason every other
	preference in the profile uses one: absent and "never chosen" have to be the same answer, so
	every profile written before this feature existed already reads correctly and nothing needs
	migrating. ]]
DayNightConfig.Preference = {
	Auto = "",
	Day = "day",
	Night = "night",
}

--[[ Where the clock STOPS for the two locked answers.

	DAY IS EXACTLY NOON, which is exactly the map as the builder authored it (note 3). That is
	worth preserving through any retune of the keyframes: a player who picks DAY should be looking
	at the game's own artwork, not at a sky this file invented.

	NIGHT IS A LITTLE PAST MIDNIGHT rather than on it, only so the moon is somewhere in the sky
	rather than exactly overhead. ]]
DayNightConfig.LockedClock = {
	[DayNightConfig.Preference.Day] = 12,
	[DayNightConfig.Preference.Night] = 0.4,
}

--[[ `Attribute` is the server's copy of the preference, mirrored onto the Player exactly as the
	music mute is: written when the profile lands and on every accepted set, and read ONCE by the
	client on the way in. It is a seed for a fresh client, not a live channel.

	`ProfileKey` is where it is kept between sessions. TOP-LEVEL, for the reason every other
	top-level key in that template gives: `PlayerProfile`'s string path is a recursive key search,
	so a key nested inside a Settings table would be reachable only by array path.

	`RemoteName` is the client saying so afterwards. Like the mute, this is a statement rather than
	a request: nothing about a player's own sky is the server's to rule on. ]]
DayNightConfig.Attribute = "SkyPreference"
DayNightConfig.ProfileKey = "SkyPreference"
DayNightConfig.RemoteName = "SetSkyPreference"

--[[ Published on Dispatcher whenever the preference changes, however it changed: a press on the
	settings screen, or the server's saved answer arriving. The three pills are drawn from it and
	decide nothing, which is the same bargain the world cards make with `WorldConfig.StateEvent`
	and the topbar's mute button makes with `MusicConfig.StateEvent`. ]]
DayNightConfig.StateEvent = "SkyPreferenceState"

--- How long the client waits for the server's seed before it assumes AUTO. Shorter than the
--- music's, because there is nothing to hold back: an unseeded sky simply runs the cycle, which is
--- what most players want anyway, and adopting a saved DAY a second later is a two second glide.
DayNightConfig.SeedTimeout = 6

-- === What the settings screen says ==========================================

--[[ Every word this feature puts on screen, in one table, for the reason `RadioConfig.Copy` gives:
	a feature owns its own copy and the screen that shows it owns only its own chrome. Adding a
	second row to the settings screen should mean editing that feature's config, not this one.

	THE THREE OPTIONS ARE A LIST AND NOT THREE FIELDS, so the pills are built by walking it. A
	fourth answer (a "dusk" lock, say) is an entry here plus a clock in `LockedClock`, and the
	screen lays it out without being told.

	`OnAuto` carries the cycle length rather than stating a number, so the sentence cannot drift
	away from `CycleSeconds` above. ]]
DayNightConfig.Copy = {
	Row = "Time of day",

	--- The line under the row title: what this player's sky is doing right now, in a sentence.
	OnAuto = "The lobby runs a full day every %d minutes",
	OnDay = "Your sky is held at daytime",
	OnNight = "Your sky is held at night",

	--[[ ...and the thing a player will otherwise wonder about the moment they see the pills, which
		is whether they have just changed the sky for the whole server. They have not. Nobody has
		asked yet, which is exactly why it is worth answering before they do. ]]
	Note = "Only you see this",

	--[[ ONE WORD EACH, AND IT IS A HARD LIMIT NOW RATHER THAN A PREFERENCE. These are the captions
		on the settings screen's gold pill (`UIController/Pages/Settings`), which shows one at a time in a
		is 40% of a row wide, and `TextScaled` answers a longer caption by shrinking it against its
		neighbours rather than by wrapping.

		They did once have a second line (`Sunrise to sunset`, `Always noon`, `Always midnight`),
		cut when the screen was three pills across a panel and a two line caption set the second at
		about a third of the first. The switch has no room for one at all, which settles it.

		It costs nothing, because the row already explains itself twice over. DAY and NIGHT are the
		two words in this whole config that need no gloss, and what CYCLE means is the sentence
		beside them, which `statusFor` keeps pointed at whichever one is on. ]]
	Options = {
		{ Key = DayNightConfig.Preference.Auto, Name = "Cycle" },
		{ Key = DayNightConfig.Preference.Day, Name = "Day" },
		{ Key = DayNightConfig.Preference.Night, Name = "Night" },
	},
}

--- The sentence for the row's status line, given a preference. One place, so the screen never has
--- to switch on a preference key itself.
function DayNightConfig.statusFor(preference: unknown): string
	local key = DayNightConfig.resolve(preference)
	if key == DayNightConfig.Preference.Day then
		return DayNightConfig.Copy.OnDay
	elseif key == DayNightConfig.Preference.Night then
		return DayNightConfig.Copy.OnNight
	end
	return string.format(DayNightConfig.Copy.OnAuto, math.max(1, math.floor(DayNightConfig.CycleSeconds / 60 + 0.5)))
end

-- === The skies ==============================================================

export type Grade = { Brightness: number, Contrast: number, Saturation: number, Tint: Color3 }
export type Bloom = { Intensity: number, Size: number, Threshold: number }
export type SunRays = { Intensity: number, Spread: number }

export type Look = {
	Ambient: Color3?,
	Outdoor: Color3?,
	Brightness: number?,
	Exposure: number?,
	ColorShiftTop: Color3?,
	ColorShiftBottom: Color3?,
	ShadowSoftness: number?,
	EnvironmentDiffuse: number?,
	EnvironmentSpecular: number?,
	Atmosphere: { Color: Color3?, Decay: Color3?, Glare: number?, Haze: number? }?,
	Grade: Grade?,
	Bloom: Bloom?,
	SunRays: SunRays?,
}

export type Key = Look & { Clock: number }

--[[ THE DAY, AS EIGHT SKIES. `lookAt` blends between neighbours, wrapping past 24 back to 0, so
	these are keyframes and not states: the clock is never AT one of them for longer than an
	instant except where two carry the same values.

	THAT REPETITION IS THE POINT AND IS NOT REDUNDANT. Night appears three times (0, 5.0 and 21.2)
	and day twice (8.4 and 16.6), which is what gives each of them a FLAT stretch instead of a
	single instant at the top of a curve. Without the pair, a day would be one moment of noon
	between a sunrise and a sunset, and the lobby would never simply look like itself.

	EVERY FIELD IS OPTIONAL AND ABSENT MEANS "THE MAP'S OWN" (note 3), which is why the two day
	keys are almost empty. Each block is guarded rather than defaulted for the reason
	`WeatherConfig`'s `Look` gives: a default would make "unspecified" and "authored to the
	default" the same thing, and the first designer who wants a sky with no grade would have no way
	to say so.

	Fitted against the real lobby at plot 5 on 2026-08-27, one candidate at a time, by looking at
	the screen. The numbers are not derived from anything and there is nothing to recompute. ]]
DayNightConfig.Keys = {
	--[[ MIDNIGHT. City glow rather than moonlight: a violet sky, a warm horizon, and the map's own
		sodium doing the lighting. Note 4 is the whole argument for it. ]]
	{
		Clock = 0,
		Ambient = Color3.fromRGB(128, 118, 142),
		Outdoor = Color3.fromRGB(114, 104, 130),
		Brightness = 1.42,
		Exposure = -0.24,
		ColorShiftTop = Color3.fromRGB(210, 216, 255),
		ColorShiftBottom = Color3.fromRGB(255, 226, 190),
		ShadowSoftness = 0.32,
		EnvironmentDiffuse = 0.34,
		EnvironmentSpecular = 0.72,
		Atmosphere = { Color = Color3.fromRGB(58, 52, 92), Decay = Color3.fromRGB(200, 124, 80), Glare = 0.85, Haze = 2.15 },
		--[[ Saturation is POSITIVE here, which is the one number in this table most likely to look
			like a typo. It is not: the sky is already sunk by the Atmosphere above (note 5), so the
			grade's job at night is to let 236 sodium lamps and 269 neon parts be their own colour.
			The old fit cut saturation and tinted the frame blue, and that is precisely what turned
			a lit city street into one flat navy sheet. The tint is left a touch warm rather than
			neutral so the amber carries without the whole frame going orange. ]]
		Grade = { Brightness = -0.025, Contrast = 0.06, Saturation = 0.11, Tint = Color3.fromRGB(246, 236, 232) },
		Bloom = { Intensity = 0.34, Size = 32, Threshold = 1.2 },
		SunRays = { Intensity = 0, Spread = 0.75 },
	},

	--- Still the same night. The pair is what gives night a length rather than a peak.
	{
		Clock = 5.0,
		Ambient = Color3.fromRGB(128, 118, 142),
		Outdoor = Color3.fromRGB(114, 104, 130),
		Brightness = 1.42,
		Exposure = -0.24,
		ColorShiftTop = Color3.fromRGB(210, 216, 255),
		ColorShiftBottom = Color3.fromRGB(255, 226, 190),
		ShadowSoftness = 0.32,
		EnvironmentDiffuse = 0.34,
		EnvironmentSpecular = 0.72,
		Atmosphere = { Color = Color3.fromRGB(58, 52, 92), Decay = Color3.fromRGB(200, 124, 80), Glare = 0.85, Haze = 2.15 },
		Grade = { Brightness = -0.025, Contrast = 0.06, Saturation = 0.11, Tint = Color3.fromRGB(246, 236, 232) },
		Bloom = { Intensity = 0.34, Size = 32, Threshold = 1.2 },
		SunRays = { Intensity = 0, Spread = 0.75 },
	},

	--[[ DAWN. Cool pink and hazy, and deliberately a different colour from dusk: the two happen at
		opposite ends of the same cycle and a player who cannot tell them apart has been given one
		effect drawn twice. Sunrise is the pale one. ]]
	{
		Clock = 6.7,
		Ambient = Color3.fromRGB(180, 156, 176),
		Outdoor = Color3.fromRGB(150, 130, 156),
		Brightness = 1.7,
		Exposure = -0.04,
		ColorShiftTop = Color3.fromRGB(255, 218, 204),
		ColorShiftBottom = Color3.fromRGB(255, 188, 148),
		ShadowSoftness = 0.46,
		EnvironmentDiffuse = 0.52,
		EnvironmentSpecular = 0.82,
		Atmosphere = { Color = Color3.fromRGB(150, 118, 132), Decay = Color3.fromRGB(214, 122, 118), Glare = 1.1, Haze = 3.2 },
		Grade = { Brightness = 0.01, Contrast = 0.02, Saturation = 0.04, Tint = Color3.fromRGB(255, 226, 216) },
		Bloom = { Intensity = 0.18, Size = 28, Threshold = 1.45 },
		SunRays = { Intensity = 0.115, Spread = 0.78 },
	},

	--- MORNING: authored colours with restrained highlights and softer daylight shadows.
	{
		Clock = 8.4,
		Exposure = 0.04,
		ShadowSoftness = 0.62,
		EnvironmentDiffuse = 0.7,
		EnvironmentSpecular = 0.92,
		Bloom = { Intensity = 0.08, Size = 24, Threshold = 1.8 },
		SunRays = { Intensity = 0.045, Spread = 0.62 },
	},

	--- ...and still the map's, all the way through the afternoon.
	{
		Clock = 16.6,
		Exposure = 0.03,
		ShadowSoftness = 0.58,
		EnvironmentDiffuse = 0.68,
		EnvironmentSpecular = 0.94,
		Bloom = { Intensity = 0.09, Size = 24, Threshold = 1.75 },
		SunRays = { Intensity = 0.05, Spread = 0.64 },
	},

	--[[ DUSK. The warm one, and the loudest sky in the table by some way. It is allowed to be:
		it holds for about a minute and a quarter of a fifteen minute cycle, and a sunset that is
		polite is a sunset nobody notices. Softened about 15% from the first fit, which was
		handsome and slightly too much of a filter over the whole forecourt. ]]
	{
		Clock = 18.1,
		Ambient = Color3.fromRGB(202, 156, 142),
		Outdoor = Color3.fromRGB(172, 130, 118),
		Brightness = 1.78,
		Exposure = 0.08,
		ColorShiftTop = Color3.fromRGB(255, 196, 142),
		ColorShiftBottom = Color3.fromRGB(255, 150, 92),
		ShadowSoftness = 0.38,
		EnvironmentDiffuse = 0.55,
		EnvironmentSpecular = 1,
		Atmosphere = { Color = Color3.fromRGB(172, 116, 92), Decay = Color3.fromRGB(232, 134, 64), Glare = 1.28, Haze = 3.4 },
		Grade = { Brightness = 0.01, Contrast = 0.02, Saturation = 0.1, Tint = Color3.fromRGB(255, 218, 186) },
		Bloom = { Intensity = 0.2, Size = 30, Threshold = 1.35 },
		SunRays = { Intensity = 0.14, Spread = 0.82 },
	},

	--[[ EVENING. The handover, and it exists only so that dusk does not blend straight into
		midnight: a straight line between those two runs the sky through a muddy brown that is not
		a colour any evening is. This is the blue hour, and it is what that line should pass
		through instead. ]]
	{
		Clock = 19.6,
		Ambient = Color3.fromRGB(138, 128, 166),
		Outdoor = Color3.fromRGB(118, 112, 152),
		Brightness = 1.5,
		Exposure = -0.12,
		ColorShiftTop = Color3.fromRGB(200, 208, 255),
		ColorShiftBottom = Color3.fromRGB(232, 178, 188),
		ShadowSoftness = 0.3,
		EnvironmentDiffuse = 0.42,
		EnvironmentSpecular = 0.82,
		Atmosphere = { Color = Color3.fromRGB(88, 80, 116), Decay = Color3.fromRGB(96, 64, 92), Glare = 0.5, Haze = 2.8 },
		Grade = { Brightness = 0, Contrast = 0.03, Saturation = -0.04, Tint = Color3.fromRGB(216, 220, 246) },
		Bloom = { Intensity = 0.25, Size = 31, Threshold = 1.3 },
		SunRays = { Intensity = 0.025, Spread = 0.72 },
	},

	--- Night again, and the wrap: this and the midnight key are the same sky, so the blend from
	--- here through 24 to 0 is flat and the seam cannot be seen.
	{
		Clock = 21.2,
		Ambient = Color3.fromRGB(128, 118, 142),
		Outdoor = Color3.fromRGB(114, 104, 130),
		Brightness = 1.42,
		Exposure = -0.24,
		ColorShiftTop = Color3.fromRGB(210, 216, 255),
		ColorShiftBottom = Color3.fromRGB(255, 226, 190),
		ShadowSoftness = 0.32,
		EnvironmentDiffuse = 0.34,
		EnvironmentSpecular = 0.72,
		Atmosphere = { Color = Color3.fromRGB(58, 52, 92), Decay = Color3.fromRGB(200, 124, 80), Glare = 0.85, Haze = 2.15 },
		Grade = { Brightness = -0.025, Contrast = 0.06, Saturation = 0.11, Tint = Color3.fromRGB(246, 236, 232) },
		Bloom = { Intensity = 0.34, Size = 32, Threshold = 1.2 },
		SunRays = { Intensity = 0, Spread = 0.75 },
	},
}

--- The neutral grade: what a sky with no `Grade` of its own resolves to, and what the effect is
--- left at when the feature is switched off. Not a keyframe value, a zero.
DayNightConfig.NeutralGrade = {
	Brightness = 0,
	Contrast = 0,
	Saturation = 0,
	Tint = Color3.new(1, 1, 1),
} :: Grade

-- === Derived ================================================================

--- Whether `value` is one of the three answers. Anything else, including a number or a key from a
--- future build, reads as AUTO rather than as an error: a preference is not worth refusing over.
function DayNightConfig.isPreference(value: unknown): boolean
	return value == DayNightConfig.Preference.Auto
		or value == DayNightConfig.Preference.Day
		or value == DayNightConfig.Preference.Night
end

--- `value` as one of the three, with everything else folded into AUTO. The one place a stored or
--- wired answer is turned into something the rest of the code can switch on.
function DayNightConfig.resolve(value: unknown): string
	if DayNightConfig.isPreference(value) then
		return value :: string
	end
	return DayNightConfig.Preference.Auto
end

--[[ The clock this preference wants right now, in game hours.

	AUTO IS THE ONLY ONE THAT MOVES, and it is a pure function of the shared server clock (note 1),
	so two players standing next to each other are looking at the same sky without either of them
	having been told anything. The other two answers ignore the cycle entirely. ]]
function DayNightConfig.clockFor(preference: unknown): number
	local key = DayNightConfig.resolve(preference)
	local locked = DayNightConfig.LockedClock[key]
	if locked then
		return locked
	end

	local phase = (workspace:GetServerTimeNow() / DayNightConfig.CycleSeconds) % 1
	return (phase * 24 + DayNightConfig.Offset) % 24
end

--- Blend two numbers. Named rather than inlined only because `lookAt` reads better for it.
local function mixNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function mixColor(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

--[[ The two keyframes `clock` sits between, and how far between them it is.

	IT WRAPS, which is the only thing here worth a comment: a clock of 23 is between the last key
	(21.2) and the FIRST one (0, read as 24), and a clock of 2 is between the same pair read the
	other way round. The table is required to be sorted by `Clock`, which it is by inspection and
	which nothing checks, because an unsorted table is a mistake a designer makes once and sees
	immediately. ]]
local function bracket(clock: number): (Key, Key, number)
	local keys = DayNightConfig.Keys
	local count = #keys
	clock = clock % 24

	local previous = keys[count]
	local previousClock = keys[count].Clock - 24

	for _, key in keys do
		if clock < key.Clock then
			local span = key.Clock - previousClock
			local t = if span > 0 then (clock - previousClock) / span else 0
			return previous, key, t
		end
		previous = key
		previousClock = key.Clock
	end

	--- Past the last keyframe, so the pair is (last, first + 24).
	local first = keys[1]
	local span = (first.Clock + 24) - previousClock
	local t = if span > 0 then (clock - previousClock) / span else 0
	return previous, first, t
end

--[[ THE SKY AT `clock`, with every field resolved against `base`, which is the map's own lighting
	as the controller found it.

	`base` IS PASSED IN RATHER THAN STORED, because this file must not hold a copy of the map's
	sky: the controller reads the live values once at boot and this blends against whatever it read
	(note 3). Pass the same table every call.

	ALWAYS RETURNS A COMPLETE LOOK, never a partial one. Every consumer would otherwise need its
	own "and if this field is nil" branch, and the branch would have to know the base, which is the
	thing this function exists to hide. ]]
function DayNightConfig.lookAt(clock: number, base: {
	Ambient: Color3,
	Outdoor: Color3,
	Brightness: number,
	Exposure: number,
	ColorShiftTop: Color3,
	ColorShiftBottom: Color3,
	ShadowSoftness: number,
	EnvironmentDiffuse: number,
	EnvironmentSpecular: number,
	Atmosphere: { Color: Color3, Decay: Color3, Glare: number, Haze: number },
	Bloom: Bloom,
	SunRays: SunRays,
}): {
	Ambient: Color3,
	Outdoor: Color3,
	Brightness: number,
	Exposure: number,
	ColorShiftTop: Color3,
	ColorShiftBottom: Color3,
	ShadowSoftness: number,
	EnvironmentDiffuse: number,
	EnvironmentSpecular: number,
	Atmosphere: { Color: Color3, Decay: Color3, Glare: number, Haze: number },
	Grade: Grade,
	Bloom: Bloom,
	SunRays: SunRays,
}
	local from, to, t = bracket(clock)
	t = smooth(t)

	local neutral = DayNightConfig.NeutralGrade
	local fromGrade = from.Grade or neutral
	local toGrade = to.Grade or neutral

	local fromAir = from.Atmosphere
	local toAir = to.Atmosphere
	local baseAir = base.Atmosphere
	local fromBloom = from.Bloom or base.Bloom
	local toBloom = to.Bloom or base.Bloom
	local fromRays = from.SunRays or base.SunRays
	local toRays = to.SunRays or base.SunRays

	return {
		Ambient = mixColor(from.Ambient or base.Ambient, to.Ambient or base.Ambient, t),
		Outdoor = mixColor(from.Outdoor or base.Outdoor, to.Outdoor or base.Outdoor, t),
		Brightness = mixNumber(from.Brightness or base.Brightness, to.Brightness or base.Brightness, t),
		Exposure = mixNumber(from.Exposure or base.Exposure, to.Exposure or base.Exposure, t),
		ColorShiftTop = mixColor(from.ColorShiftTop or base.ColorShiftTop, to.ColorShiftTop or base.ColorShiftTop, t),
		ColorShiftBottom = mixColor(from.ColorShiftBottom or base.ColorShiftBottom, to.ColorShiftBottom or base.ColorShiftBottom, t),
		ShadowSoftness = mixNumber(from.ShadowSoftness or base.ShadowSoftness, to.ShadowSoftness or base.ShadowSoftness, t),
		EnvironmentDiffuse = mixNumber(from.EnvironmentDiffuse or base.EnvironmentDiffuse, to.EnvironmentDiffuse or base.EnvironmentDiffuse, t),
		EnvironmentSpecular = mixNumber(from.EnvironmentSpecular or base.EnvironmentSpecular, to.EnvironmentSpecular or base.EnvironmentSpecular, t),
		Atmosphere = {
			Color = mixColor((fromAir and fromAir.Color) or baseAir.Color, (toAir and toAir.Color) or baseAir.Color, t),
			Decay = mixColor((fromAir and fromAir.Decay) or baseAir.Decay, (toAir and toAir.Decay) or baseAir.Decay, t),
			Glare = mixNumber((fromAir and fromAir.Glare) or baseAir.Glare, (toAir and toAir.Glare) or baseAir.Glare, t),
			Haze = mixNumber((fromAir and fromAir.Haze) or baseAir.Haze, (toAir and toAir.Haze) or baseAir.Haze, t),
		},
		Grade = {
			Brightness = mixNumber(fromGrade.Brightness, toGrade.Brightness, t),
			Contrast = mixNumber(fromGrade.Contrast, toGrade.Contrast, t),
			Saturation = mixNumber(fromGrade.Saturation, toGrade.Saturation, t),
			Tint = mixColor(fromGrade.Tint, toGrade.Tint, t),
		},
		Bloom = {
			Intensity = mixNumber(fromBloom.Intensity, toBloom.Intensity, t),
			Size = mixNumber(fromBloom.Size, toBloom.Size, t),
			Threshold = mixNumber(fromBloom.Threshold, toBloom.Threshold, t),
		},
		SunRays = {
			Intensity = mixNumber(fromRays.Intensity, toRays.Intensity, t),
			Spread = mixNumber(fromRays.Spread, toRays.Spread, t),
		},
	}
end

-- 0 in full daylight, 1 at night, with smooth shoulders through dawn and dusk.
function DayNightConfig.nightAmount(clock: number): number
	local fixture = DayNightConfig.Fixtures
	clock %= 24
	if clock < fixture.DawnStart or clock >= fixture.DuskOn then
		return 1
	elseif clock < fixture.DawnOff then
		return 1 - smooth((clock - fixture.DawnStart) / (fixture.DawnOff - fixture.DawnStart))
	elseif clock < fixture.DuskStart then
		return 0
	end
	return smooth((clock - fixture.DuskStart) / (fixture.DuskOn - fixture.DuskStart))
end

--[[ The shorter of the two ways round the clock face, from `from` to `to`, as a signed number of
	hours in the range (-12, 12].

	THE GLIDE USES THIS AND NOTHING ELSE. Without it, switching from 23:00 to 01:00 is a two hour
	step that the code would run as a twenty two hour rewind: the sun would climb back up through
	a whole day to reach a point two hours ahead of it. ]]
function DayNightConfig.shortestStep(from: number, to: number): number
	local delta = (to - from) % 24
	if delta > 12 then
		delta -= 24
	end
	return delta
end

return DayNightConfig
