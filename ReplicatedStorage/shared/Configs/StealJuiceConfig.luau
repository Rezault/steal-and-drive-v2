--[[
	StealJuiceConfig
	----------------
	THE STEAL'S FEEDBACK: its sounds, its camera punches and the STOLEN! toast (2026-09-30). The steal's
	MECHANICS are `StealConfig`'s and are untouched by anything here — this file only decides what the
	player hears and sees on beats that already happen.

	=== WHY IT EXISTS: THE FEEDBACK HIERARCHY WAS UPSIDE DOWN ==================================

	Audited 2026-09-30, from the code rather than a playtest: every ROUTINE event had feedback — a pickup,
	a near miss, nitro, a speed trap and every UI click play a sound; an obstacle hit and a near miss
	punch the camera (`RaceCameraController.impact` / `nearPass`) — and the SIGNATURE event had none. The
	bail, the flight, the landing, the door, the driver going over the side and the takeover were all
	silent, the camera did nothing but switch into its flight shot and back, and nothing on screen said
	what you had just taken. A bumped cone out-punched a stolen supercar. The three blocks below are the
	fix, one each, each with its own `Enabled` so the old behaviour is one flag away for an A/B.

	=== THE BEATS, AND WHERE EACH IS FIRED =====================================================

	Every sound is fired from the frame its event HAPPENS on in `StealController` / `GetawayController`,
	not from a timer beside it — a mediocre sound on the right frame beats a good one 150ms late, and
	the clips have no animation markers to sync to (checked), so the code's own events are the markers:

	    Bail       `_onBail`           the frame the key is pressed
	    Whoosh     launch -> air       the rise ends and the arc begins
	    Land       `_mount`            contact with the roof
	    Door       `_mount`            the target's door starts swinging (the same frame, by design —
	                                    `_mount` says the three halves of the landing are one event)
	    Throw      `_releaseDriver`    the driver actually leaves the car, `Driver.ReleaseAt` into the
	                                    clip, so it is NOT stacked on the landing's two
	    Takeover   `_notifyStolen`     the handoff has run; you are driving it
	    GetawayArrive  `GetawayController._spawn`  the truck is on the road
	    GetawayBank    `GetawayController._stepMechanism`  the doors start shutting behind you (armed
	                                    by `_bank`; until 2026-10-03 it played at the bank itself, ~1s
	                                    before the doors moved — it is a door sound)

	THE SOUNDS LIVE IN THE PLACE: `SoundService.<Sounds.Group>` with one Sound per beat, named as below
	(the owner authored them 2026-09-30). A missing group warns once and goes quiet
	(`SoundController`'s rule), and a missing Sound in it is silence, so a beat with no clip yet costs
	nothing.
]]

local StealJuiceConfig = {}

-- === Sounds =================================================================

StealJuiceConfig.Sounds = {
	--- Off = the steal and the getaway are silent again, exactly as before.
	Enabled = true,
	--- The SoundGroup under SoundService that holds every clip below.
	Group = "Steal",
	Bail = "StealBail",
	Whoosh = "StealWhoosh",
	Land = "StealLand",
	Door = "StealDoor",
	Throw = "StealThrow",
	Takeover = "StealTakeover",
	GetawayArrive = "GetawayArrive",
	GetawayBank = "GetawayBank",
}

-- === Camera punches =========================================================
--[[ Two punches on the same springs the obstacle hit uses (`CameraConfig.Juice.Spring`), so they
	decay with the same feel. Peaks in DEGREES, the unit `CameraConfig.Juice.Impact` speaks, and sized
	against it on purpose:

	    obstacle hit, hardest   roll 3   pitch 2.2   fov -4
	    Land                    roll 0   pitch 2.6   fov -3     a HEAVY landing, straight down (no roll:
	                                                            you land square), a hair under a max hit
	                                                            so a crash still out-hurts a landing
	    Takeover                roll 0   pitch -0.8  fov +5.5   the OPPOSITE sign of a hit: the lens
	                                                            opens and the nose lifts — power, the car
	                                                            pulling away — larger than a near miss's
	                                                            top +2.5 because it is the bigger event

	UNTESTED IN PLAY when written — they are sized by that table, not by feel. They are the first
	numbers to move after a playtest, and `Enabled = false` is the honest A/B. The Land punch fires
	while the flight camera is still on (the handoff has not run), which is why it goes through its
	own entry point (`RaceCameraController.stealPunch`) rather than `impact`, which ignores flight.
	`CameraConfig.Juice` (its `Enabled` and `Scale`) governs both, as it governs every punch. ]]
StealJuiceConfig.Punch = {
	Enabled = true,
	Land = { RollPeakDeg = 0, PitchPeakDeg = 2.6, FovPeakDeg = -3 },
	Takeover = { RollPeakDeg = 0, PitchPeakDeg = -0.8, FovPeakDeg = 5.5 },
}

-- === The cinematic ==========================================================
--[[ THE TAKEOVER, DIRECTED (2026-09-30, the owner: "go crazy, make it very cinematic").

	IT SPENDS NO GAMEPLAY TIME, and that is what makes it affordable on every steal. The mount beat — the
	~1.6s between hitting the roof and driving the car (`StealController._mountBeat`, the landing clip's
	own length) — already exists and already has no steering in it. The camera was simply watching it from
	the flight shot. Now it cuts through it:

	    0 ..... Hero shot: low and close on the door side, or a crane straight down onto the roof
	            (`HeroVariants`, picked per steal so it is not the same shot twenty times a run),
	            with a slow-mo pulse on contact (`SlowMo`) and the landing punch on top
	    cut ... a whip across to the DOOR, timed off the driver's own release (`Driver.ReleaseAt`)
	            so the cut lands a beat BEFORE he goes, never after
	    door .. close, Dutch-tilted, and it TRACKS the thrown driver as he flies out
	    out .. a swoop back into the chase shot, arriving at weight 0 on the beat's last frame — so
	            control returns in the ordinary camera and the player is never handed a car they can
	            not see the road in front of

	`Enabled = false` is the steal exactly as before (the flight shot watching the roof). `MinBand` keeps
	it for rarer cars only; `Cooldown` skips it on a steal chained right after another, if every steal
	turns out to be too many. Both off by default — the owner asked for all of it. UNTESTED IN PLAY when
	written: the offsets are placed by reasoning about the car's frame, and are the numbers to move. ]]
StealJuiceConfig.Cinematic = {
	Enabled = true,
	--- Only for cars of at least this rarity band (1 = Beater .. 5 = Supercar). 1 = every steal.
	MinBand = 1,
	--- Real seconds after one cinematic before another may play. 0 = every steal.
	Cooldown = 0,

	--[[ The beat's timeline, as fractions of the mount beat. `CutLead` is how far BEFORE the driver's
		release the whip to the door starts; `CutTime` is the whip itself; `OutFrom` is where the swoop
		back to the chase shot begins (it always ends at 1). `BlendIn` is the fraction the first shot
		takes to fade over the flight shot — small, so it reads as a cut, not a drift. ]]
	BlendIn = 0.05,
	CutLead = 0.1,
	CutTime = 0.07,
	CutMin = 0.28, -- never cut earlier than this, so the hero shot always gets its moment
	OutFrom = 0.8,

	--[[ Shot offsets in the STOLEN CAR'S road frame, studs: `Ahead` along the road, `Out` toward the
		driver's door side, `Up` above the roof (negative = below it). The avatar is `FocusUp` above the
		roof. Each shot has its own lens (degrees) and roll (degrees, signed toward the door side). ]]
	--[[ === PULLED BACK — 2026-09-30 =========================================================
		First playtest: "much too close". WAS Low 8.5/4/-1.8 @48°, Crane -2.5/1.5/10 @55°, Door 5/8/0.5
		@56° (Ahead/Out/Up). Every shot roughly doubled its distance and widened its lens a few degrees,
		and the Low shot came up from under the roofline to just above the door so it stops looking up
		the car's side. Still the numbers to move next — the direction was measured, the amount was not. ]]
	FocusUp = 2.5,
	HeroVariants = {
		{ Name = "Low", Ahead = 17, Out = 9, Up = 0.5, Fov = 55, Roll = 5, PushIn = 2.5 },
		{ Name = "Crane", Ahead = -5, Out = 3, Up = 20, Fov = 60, Roll = 0, PushIn = 3 },
	},
	Door = { Ahead = 10, Out = 15, Up = 2.5, Fov = 62, Roll = -8, Track = 0.6 },

	--[[ The slow-motion pulse on contact: the world drops to `Scale` for `Seconds` of REAL time, easing
		in over `EaseIn` and back over `EaseOut`. It STRETCHES the beat (the beat runs on flight time), by
		about `Seconds × (1 − Scale)` ≈ 0.3s at these numbers. Independent of `StealConfig.SlowMo`, which
		is the flight's own and stays as it is. ]]
	SlowMo = { Enabled = true, Scale = 0.3, Seconds = 0.45, EaseIn = 0.05, EaseOut = 0.2 },
}

-- === The STOLEN! toast ======================================================
--[[ What you just took, on the frame you take it: "STOLEN!" over the car's rarity and name, in the
	rarity's colour (`Modules/CarRarity`). The traffic badge told you the rarity BEFORE the jump; this is
	the receipt after it.

	SCALED BY RARITY so the hierarchy holds inside the event too: a Beater gets a small, short toast and a
	Supercar a big, long one. `band` 1..5 (`TrafficConfig.Bands`) lerps each pair below. It sits upper
	centre, under the near-miss toast (`NearMissConfig`, at 0.105) and clear of the road ahead. ]]
StealJuiceConfig.Toast = {
	Enabled = true,
	Title = "STOLEN!",
	--- Screen position (scale) of the toast's centre.
	Position = Vector2.new(0.5, 0.24),
	--- Pixel width at scale 1, and the height of its two lines.
	Width = 460,
	TitleHeight = 46,
	LineHeight = 28,
	--- { Beater, Supercar } — the scale it pops to and how long it holds, lerped by band.
	Scale = { 0.85, 1.25 },
	Hold = { 1.1, 2.2 },
	PopTime = 0.28,
	FadeTime = 0.3,
	TitleColor = Color3.fromRGB(255, 214, 64),
}

-- === The player's switch for the cinematic ======================================
--[[ A SETTINGS ROW THAT TURNS `Cinematic` OFF FOR ONE PLAYER (2026-10-02, the owner: "some people
	wont want it enabled"). The cinematic takes the camera away for about a second on every steal, and
	a player chaining steals for speed can reasonably want that second back. Off, `_startCinematic`
	returns before anything is set up, so the steal plays on the chase camera with no slow-motion pulse
	(the pulse only exists while a cinematic does) — the steal exactly as it was before 2026-09-30. The
	punches, sounds and toast are NOT part of it: they cost the player no time and no view.

	SAVED, unlike Hide UI (`InterfaceConfig` says why that one is not): a camera preference is a
	preference, and having to switch it off again every session is the annoyance the row exists to end.
	It goes through `SettingsService` like the sky and the volumes — a statement, not a request, since
	which camera somebody watches their own steal through is no advantage to anyone.

	`Enabled = false` takes the row off the settings screen and leaves every player on `Default`. ]]
StealJuiceConfig.Setting = {
	Enabled = true,
	--- Stored keys rather than a boolean, because the settings screen walks a list of options.
	On = "on",
	Off = "off",
	Default = "on",
	--- Top-level profile key, player attribute (the server's seed), the client's remote, the client's
	--- repaint event. Same four `DayNightConfig` has, for the same reasons.
	ProfileKey = "StealCinematic",
	Attribute = "StealCinematic",
	RemoteName = "SetStealCinematic",
	StateEvent = "StealCinematicState",
	--- Seconds to wait for the seed before settling on `Default`. Same floor as `DayNightConfig.SeedTimeout`.
	SeedTimeout = 6,
	Copy = {
		Row = "Steal camera",
		--[[ OFF FIRST. The settings screen draws a two-answer row as a switch whose FIRST option is
			the knob on the left (switched off) and the second the knob on the right (switched on) —
			`InterfaceConfig.Copy.Options` lists Off before On for the same reason. Listed the other way
			round (2026-10-02, first build) the switch read off while the cinematic was on. ]]
		Options = {
			{ Key = "off", Name = "Off" },
			{ Key = "on", Name = "On" },
		},
	},
}

--- `value` as "on" or "off", anything else folded into `Setting.Default`. Pure.
function StealJuiceConfig.resolveSetting(value: unknown): string
	local setting = StealJuiceConfig.Setting
	if value == setting.On or value == setting.Off then
		return value :: string
	end
	return setting.Default
end


--[[ THE RARITY FLASH (2026-10-07, the polish pass). The STOLEN! toast says what you took; the screen
	did not. Now a steal of a car of band `MinBand` and up washes the edges of the screen in its rarity
	colour for `Seconds` — the same colour the bank flash and the podium glow use for that car, so the
	colour is learned once and means the same thing everywhere. Commons get nothing, so the flash is
	news. `Strength` is how opaque the edges start (0 = solid). `Enabled = false`: no flash. ]]
StealJuiceConfig.RarityFlash = {
	Enabled = true,
	MinBand = 3,
	Strength = 0.35,
	Seconds = 0.7,
	--- How far in from each edge the wash reaches, as a share of the screen.
	Width = 0.18,
}

--[[ THE RARITY BURST (2026-10-13, punch list V2). Aleafo: "a different type of VFX each time you steal a
	car depending on the rarity". The flash above is on the SCREEN; this is on the CAR: a one-shot spray
	of sparkles off the stolen car in its rarity colour, from `MinBand` (Epic) up, bigger the rarer —
	`Count` and `Speed` run { Epic, Legendary }. Commons and Rares keep the screen flash alone, so a burst
	is news. Drawn by `StealToastController._burst` on the player's own chassis (the body is swapped on a
	steal, the chassis is not), and cleaned up after `Lifetime` + 0.5s. `Enabled = false`: no burst. ]]
StealJuiceConfig.RarityBurst = {
	Enabled = true,
	MinBand = 4,
	Count = { 45, 110 },
	Speed = { 18, 32 },
	Lifetime = 1.1,
	Size = 1.4,
}

return StealJuiceConfig
