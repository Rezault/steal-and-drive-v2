--[[
	TutorialConfig
	--------------
	The onboarding: eight beats that take a brand-new player by the hand through one whole lap of the
	game — press play, pull away, steer, survive some traffic, jump, steal, catch the truck, collect
	what it earned — and then get out of the way forever.

	=== 1. IT IS A CAGE NOW, AND THAT IS THE CHANGE ============================================

	This file used to open by arguing the opposite. It was a TRACKER: a card naming an objective, a
	pointer at the thing it named, and nothing anywhere that blocked, dimmed, waited or refused. The
	reasoning was that three of its five steps happened at 33mph on a road with traffic on it, and
	there is nothing in that moment you can safely stop.

	That was wrong, and what made it wrong was that the moment CAN be stopped — properly, both
	halves of it. `Modules/TimeScale` holds every scripted per-frame system in the game at zero with
	one number, and `RaceFreezeController` anchors the two things that are physics rather than
	script (your car, and any traffic shell already tumbling). Together they are a real pause, not a
	slow-down with a caption on it. Once a pause exists, the argument for a tracker collapses: the
	tutorial's job is to guarantee a new player finishes their first loop, and the surest way to
	teach somebody a key is to stop the world until they press it.

	So three of the eight FREEZE (`Freeze = true`): the one that teaches the throttle, the one that asks
	for the jump, and the one that holds you in mid-air over the car you are about to take. They are
	exactly the three the board card marks "keep the game paused", and they are the three where the
	player is being asked for an input they have never made before.

	The other five do not freeze, and that is as deliberate. STEER does not, because a lesson about
	moving sideways cannot be taught by a car that will not move. SURVIVE does not, because its
	whole content is eight seconds of the real game. And both lobby beats do not, because a lobby
	has no motion to stop — what those two gate is INPUT, not time (see `Gate` below).

	=== 2. WHAT ADVANCES A BEAT ================================================================

	Two kinds, and the split is the security boundary:

	    Kind = "Signal"   a server signal some service already fires for its own reasons. The
	                      server sees it, advances, and tells the client. A client cannot fake one.
	    Kind = "Input"    something only the client can witness — a key held, a lane changed, a
	                      jump. The client reports it, the server validates that it is the beat
	                      that is actually live, and advances.

	NO INPUT BEAT IS WORTH FAKING and that is why they are allowed to exist. Faking "hold W" wins
	you a beat that was going to end the moment you pressed the key the card named, and nothing else
	— there is no reward behind any of them. What the server refuses is a report for a beat that is
	not live, which is not an exploit guard so much as a guarantee that the funnel numbers mean
	something.

	Every signal beat below names a signal that ALREADY EXISTS:

	    play      RaceService.RaceEntered           you entered a race
	    airborne  StealService.CarStolen            a steal the server ratified
	    bank      RewardService.RunSettled(banked)  you drove into the truck
	    collect   GarageService.CashCollected       a foot on a mat

	`TutorialService._bind` walks this list and connects what it finds, so a beat whose signal is
	misspelled fails loudly at boot with its own id in the message, rather than being a hole a
	player discovers.

	=== 3. EVERY BEAT IS A FUNNEL STEP =========================================================

	`Funnel` is the step number reported to `AnalyticsService:LogOnboardingFunnelStepEvent`, which is
	Roblox's own first-class onboarding funnel — the board card asks for this explicitly ("track
	every single step with funnels ofc") and it is the reason the beat list is FLAT rather than a
	tree of sub-steps. A funnel wants a monotonic sequence of numbered stages, so the list is one.

	Numbers are stated rather than derived from position. A funnel read across a week of sessions is
	comparing yesterday's build to today's, and a beat inserted in the middle would silently
	renumber every stage after it — every historical chart would bend at the deploy. So inserting a
	beat means giving it the next FREE number, not the next one in reading order, and the two are
	allowed to disagree. See `Funnel` on each beat.

	=== 4. THE STEP IS SERVER-OWNED AND MIRRORED ONTO THE PLAYER ===============================

	`ProfileKey` stores where they are; `StepAttribute` broadcasts it. The attribute is what lets
	`GetawayController` — and anything else that ever wants to know — read "is this player still on
	their first run?" with no remote, no dependency edge and no subscription, exactly the way
	`GarageConfig.CashAttribute` publishes the balance for the HUD.

	It is a STEP ID and not an index. An index is a number whose meaning changes the day a beat is
	inserted, and profiles written yesterday would silently resume onto whatever step 3 has become;
	an id that is no longer in `Steps` is simply an unknown step, which `TutorialService` reads as
	"start from the top of whatever is left". Ids are therefore the one field here that must never
	be reused for a different objective.

	=== 5. THE FIRST RUN IS RIGGED, AND NOW IT IS STAGED AS WELL ===============================

	See `Rig`. It used to change one thing — the getaway truck came sooner — on the argument that a
	first-timer who wrecks at 40 seconds having never seen a truck has been shown two thirds of a
	game. That still holds and is still here.

	What is new is `Rig.Stage`: the tutorial's run is CHOREOGRAPHED. The road is cleared and then
	dealt a known hand — a few cars at a known spacing to steer between, a car placed in a clear
	radius to be stolen — and the player is held above a damage floor so that the eight seconds of
	real traffic can hurt without being able to end the run. That is the one place this feature
	touches gameplay, and every number in it is in one table so that `Stage.Enabled = false` puts a
	first run back on the shipped road exactly.

	IT IS ALL CLIENT-SIDE, which is what makes it cheap. The road, the traffic, the obstacles and
	the truck are already the client's own copy of the world (see `TrafficController`'s header:
	driving is solo and none of it replicates), so staging a run costs one controller reading this
	table and no server surface at all.

	HOUSE RULE: no wiki-style double-bracket links in these comments — the closing pair ends the
	block comment early and the parse error points at the wrong line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--[[ For `Income.Passive` alone: the last beat teaches collecting or tipping depending on which
	income is live (`Steps`, COLLECT). A config requiring a config, and GarageConfig's own requires
	never reach this file, so it cannot cycle. ]]
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
--- For the SELL beat, which exists only while buyers do (and which replaces COLLECT when it does). Requires nothing that reaches back here.
local BuyerConfig = require(ReplicatedStorage.shared.Configs.BuyerConfig)

local TutorialConfig = {}

--[[ Master switch. Off = no card, no arrow, no pause, no profile key written, and `TutorialService`
	binds nothing at all. Every beat it would have watched is either a signal some other service
	fires for its own reasons or an input the client was going to receive anyway, so turning this
	off cannot affect a single thing about how the game plays. ]]
TutorialConfig.Enabled = true

--[[ ...and the DEVELOPER's switch, which is the same result and nowhere near the same decision.

	`Enabled` above is an editorial call about the shipped game: it lives in git, it turns up in a
	diff, and somebody has to agree to it. This one is a Workspace attribute: tick `SkipTutorial` on
	Workspace in the Properties panel, or run `workspace:SetAttribute("SkipTutorial", true)` once in
	edit mode. It exists so that anybody working on the lobby, the road, a car or a screen does not
	sit through nine beats on every playtest, and does not have to edit a config line they might
	then commit by accident.

	IT IS STUDIO-ONLY, and that restriction is the whole reason it is allowed to be an attribute.
	Attributes are saved INTO the place file and published with it, so a tick nobody remembered would
	otherwise be a silent "no onboarding for anybody" on the live game, and turning the tutorial off
	for real players is a decision about the product, which is what `Enabled` is for. In a published
	server the flag is read, ignored, and named in the boot log, so a forgotten tick is visible
	instead of expensive.

	`BypassInStudioOnly = false` lifts that if a live bypass is ever genuinely wanted (a test place, a
	soft launch), and it is deliberately a code edit for the same reason `Enabled` is one.

	READ AT BOOT by both halves (the service binds nothing, the controller never builds a card), so
	set it in edit mode and then playtest. TICKING it mid-session changes nothing until the next run;
	UNTICKING it mid-session boots the tutorial there and then (`whenOn`), which is how the admin
	panel's Replay works in a place that carries the tick. NOTHING IS WRITTEN TO A PROFILE either way,
	which is what makes it a bypass rather than a skip: untick it and every player is exactly on the
	beat they were on. ]]
TutorialConfig.BypassAttribute = "SkipTutorial"
TutorialConfig.BypassInStudioOnly = true

--- Is the developer bypass on for THIS peer? The attribute replicates, so a Studio client and its
--- Studio server answer the same, and a live client and its live server both answer no.
function TutorialConfig.isBypassed(): boolean
	if Workspace:GetAttribute(TutorialConfig.BypassAttribute) ~= true then
		return false
	end
	return RunService:IsStudio() or not TutorialConfig.BypassInStudioOnly
end

--[[ THE READ EVERY CONSUMER MAKES. `Enabled` stays the record of intent; this is the answer to "is
	there a tutorial running right now", and it is what the service, the controller, the director and
	the two rig helpers below all ask.

	Nothing outside this file should read `Enabled` directly. A consumer that does is one the bypass
	silently does not reach, which is the failure mode where the card is gone but the freeze is not. ]]
function TutorialConfig.isOn(): boolean
	return TutorialConfig.Enabled and not TutorialConfig.isBypassed()
end

--[[ Run `boot` the first time the tutorial is on for this peer: straight away if it already is, or
	the moment the developer bypass is lifted mid-session. Never, when `Enabled` is off, since that is
	a code edit and cannot change under a running server.

	THE THREE THINGS THAT GATE ON `isOn` AT BOOT GO THROUGH THIS (`TutorialService`,
	`TutorialController`, `TutorialDirector`), so that a Studio place carrying the bypass tick can
	still have a tutorial brought up inside one playtest. The admin panel's Replay clears the
	attribute on the server, which replicates, and in a playtest never reaches the place file.

	ONE WAY ONLY. Ticking the bypass under a running tutorial does not take it down: a card, a freeze
	and a gate torn out mid-beat is a teardown nobody has needed, and the next run already honours
	the tick. ]]
function TutorialConfig.whenOn(boot: () -> ())
	if not TutorialConfig.Enabled then
		return
	end
	if TutorialConfig.isOn() then
		boot()
		return
	end

	local connection: RBXScriptConnection
	connection = Workspace:GetAttributeChangedSignal(TutorialConfig.BypassAttribute):Connect(function()
		if connection.Connected and TutorialConfig.isOn() then
			connection:Disconnect()
			boot()
		end
	end)
end

-- === Where it is kept =======================================================

--[[ The profile key, top-level beside `ExtraLives`, `LastSeen` and `Quests` and for the same lookup
	reason those give: `PlayerProfile`'s string path is a recursive key search, so a key nested
	inside `Garage` would be reachable only by array path. ]]
TutorialConfig.ProfileKey = "Tutorial"

--[[ The live step id, mirrored onto the Player. Empty string means "nothing to do" — finished,
	skipped, or the feature switched off — and every reader treats those three the same, which is
	the point: there is no state in which a client has to work out WHY there is no objective. ]]
TutorialConfig.StepAttribute = "TutorialStep"

--[[ === THE NITRO HINT — 2026-10-17 ===
	A SHIFT key cap over the nitro badge (on a controller, nitro's pad button in that controller's own
	glyph art, so LB on an Xbox pad and L1 on a PlayStation one), while the beat named `Step` is up (the
	drive to the truck, right after the first steal), and gone for the rest of the session the first
	time nitro's key is pressed. Aleafo's call over a nitro BEAT: "so its not forced to players to
	use it to proceed". NOTHING WAITS ON IT: it is drawn by `DrivingHudController._stepNitroHint`,
	not served as a beat, so ignoring it costs nothing.

	Only once the tank can fire (`NitroConfig.Tank.MinToFire`): a key that does nothing when pressed
	teaches the opposite. No phone version, whose nitro is the `Controls.Nitro` button already on
	screen. `Text` is the keyboard cap's word; the pad's glyph comes off `NitroConfig.Keys`.
	`Enabled = false`: no cap. ]]
TutorialConfig.NitroHint = {
	Enabled = true,
	Step = "bank",
	Text = "SHIFT",
}

-- === The vocabulary =========================================================

--[[ WHAT A BEAT MAY SAY ABOUT ITSELF. Stated here rather than left to be inferred from the entries,
	because half of these fields are absent on most beats and an absent field is exactly the thing a
	reader cannot learn from examples.

	    Id        stored in the profile and broadcast on the attribute; never reuse one
	    Funnel    the stage number reported to Roblox's onboarding funnel; see note 3
	    Title     the objective, shouted on the card
	    Hint      the one line under it saying how
	    Where     "Lobby" or "Race" — which half of the game this beat happens in
	    Advance   what finishes it; see note 2 and `Advance.Kind` below
	    Freeze    hold the whole world still while this beat is up; see note 1
	    FreezeWhen  WHEN that hold goes on. "Arrival" (the default) is as soon as the beat's grace
	              is served; "Airborne" is only while a flight is over a car it could take
	    Gate      "Input" on a lobby beat: refuse every button except the one being pointed at
	    Target    what the arrow points at, or nil for "nothing to point at"
    Count     this beat is done N times, and the card shows a tally; see `steer`
	    Grace     seconds after the beat arrives before it may be completed or its freeze applied
	    Card      `false` on a beat the ARROW already explains — no panel, just the pointer; see below
	    Fill      which keys fill this beat's `%s` directives, in order; see `Keys` below
	    Staged    the director deals this beat's road, and the damage floor is on; see `Rig.Stage`
	    Arrived   a second face, shown once the thing the beat is waiting for turns up; see `bank`
	    Meter     the live feedback hung under the card, and what closes some beats; see `Meters`
	    Watched   the client tells the server once this beat's card is up with nothing over it; see `sell`
	    Look      on a face: turn the camera toward this beat's buyer as they walk in; see `Look`
	    Guide     on a face: the green guide line runs to this beat's buyer once they stand; see `sell`
	    QuietBays this player's own podium prompts are off while the beat is live; see `sell`
	    Celebrate the finish card's confetti plays as this beat lands, and finishing it is quiet; see `again`

	`Advance.Kind` is two words:

	    "Signal"  { Service, Signal, Accept? } — a server signal, optionally filtered
	    "Input"   { Input } — a named thing the client witnesses; see `TutorialConfig.Inputs`

	`Target.Kind` is three:

	    "Hud"     a button in `MainUI.HUD` by path — the arrow points at it, and it pulses
	    "Page"    a button inside whichever page is open, found by path at the time
	    "World"   a thing standing in the map — the arrow floats over it, with a distance line

	...and a "World" target names WHAT it is looking for, which `TutorialController._findWorld`
	resolves against the map as it stands at that moment:

	    "Truck"   the getaway truck, while there is one on the road
	    "Bay"     the podium's collect mat, on the bay the SERVER named (see `TutorialService._bay`)
	    "FreeBay" the nearest bay on this player's own lot that a carried car could go on — chosen
	              on the client, because "nearest" is a fact about where the player is standing

	Two flags ride along with it. `Above` hangs the chip over the target rather than under it (see
	`bank`), and `Follow` means the answer can change to a DIFFERENT OBJECT while the beat is up, so
	the pointer asks again on a slow beat instead of resolving once. Only "FreeBay" needs the second
	one: a truck that drives and a mat that streams in are both one object moving or arriving, which
	the chip already rides.

	Anything the pointer cannot find is simply not pointed at. A missing target must never be a
	missing beat — except on the beats that have already decided the pointer IS the teaching:

	=== WHEN THERE IS NO CARD AT ALL (`Card = false`) ==========================================

	A card exists to say a thing the player cannot see. On a beat whose whole content is "press the
	button this enormous red arrow is bouncing on", there is no such thing — the card is a second
	instruction for a decision that has already been made, and reading it costs longer than doing it.
	The PLAY chain is three of those presses in a row, and it was three cards.

	So the beats that point at something you press are POINTER ONLY: the arrow, the pulse, the gate,
	and no panel. What keeps a card is a beat that asks for something no arrow can draw — which key,
	which direction, what is about to happen to you — and that is every beat that happens at speed on
	the road. Left and right cannot be pointed at. `W` cannot be pointed at.

	The rule reads the FACE rather than the beat, so a race beat seen from the lobby (`Offroad`, which
	is another "hit PLAY") drops its card for as long as that is what it is saying, and gets it back
	the moment there is a road again. ]]

--[[ The named inputs an "Input" beat can wait on. Names rather than key codes, because what the
	beat means is "the player accelerated", and which key that is depends on whether they are on a
	keyboard, a stick or a touchscreen — `TutorialController` owns that mapping and this owns the
	vocabulary. The card's copy is per-device for the same reason (see `Copy.Keys`). ]]
TutorialConfig.Inputs = {
	--- Accelerate held down — W, R2, or the touch pedal. `HoldSeconds` below is how long for.
	Accelerate = "Accelerate",
	--- A deliberate lane change, left or right. Counted per DIRECTION; see `steer`.
	Steer = "Steer",
	--- The jump that starts a bail. Space, or the touch button.
	Bail = "Bail",
}

--[[ How long `Accelerate` has to be held before the beat counts it. Not zero, and not long: a
	single frame of a key bouncing is not "held", and anything over about half a second reads as the
	game ignoring you. The freeze lifts on the FIRST frame of the hold rather than at the end of it,
	so this is a debounce on the beat completing and never on the car moving. ]]
TutorialConfig.HoldSeconds = 0.25

--[[ === THE METERS UNDER THE CARD (2026-10-01) =================================================

	WHY. Every race beat finished on the first frame its input showed up. BOOST went in a quarter
	second, STEER on the first frame a key was down, and a player who tapped through them never
	saw what the key DID. So each race beat now hangs one piece of live feedback under its card,
	named by the beat's `Meter`, and the input beats only close once that feedback is full:

	    "Speed"   BOOST. A bar filling with the speedo's MPH toward a target above cruise. Closes at
	              the target with the key held. A tap lets it settle short of full.
	    "Steer"   STEER. Two arrows, left and right, captioned with this device's keys. Each fills
	              while its direction is held and the beat closes when both are full.
	    "Timer"   SURVIVE. The bar again, counting the seconds up to the beat's own `Seconds`.
	    "Key"     BAIL and AIRBORNE. A key cap naming the key, breathing while it waits and
	              sinking orange when the press lands.
	    "Chase"   BANK. The bar counts down to the truck, then fills as the gap to it closes.

	The lobby beats get none: their arrow already points at the thing to press.

	`Enabled = false` on the whole table, or on one kind, takes that feedback away and puts the
	beat back on its old rule (BOOST's quarter-second hold, STEER's one frame per direction).

	=== SPEED: THE TARGET IS PER CAR ==========================================================

	It is `TargetOverCruise` times this car's cruise, rounded to `RoundTo`, and never above
	`CeilingShare` of the boosted ceiling, so a rounding step cannot put it out of reach. That is
	55 MPH on the starter Civic, which cruises about 46 and boosts to about 60; measured, holding
	from the freeze reaches 55 in about 2.5 seconds. `FallbackMph` is only for a car with no cruise,
	and `GiveUpSeconds` of key-down time closes the beat for a car that cannot get there. ]]
TutorialConfig.Meters = {
	Enabled = true,

	--- The bar's shape, shared by Speed, Timer and Chase. Height and width are shares of the card's,
	--- the gap under the card a share of the bar's own height. `Lerp` is how fast the fill chases
	--- its value, per second.
	Bar = { Height = 0.3, Width = 0.9, Gap = 0.35, Lerp = 12 },

	Speed = {
		Enabled = true,
		TargetOverCruise = 1.08,
		CeilingShare = 0.92,
		RoundTo = 5,
		FallbackMph = 55,
		GiveUpSeconds = 4, -- Keep the first lesson brief even before the car reaches its target.
		--- `%d` twice: the speed now, and the target. Both are the speedo's MPH.
		LabelFormat = "%d / %d MPH",
	},

	Steer = {
		Enabled = true,
		--- How long one direction has to be held to fill its arrow. About one lane change.
		HoldSeconds = 0.3,
		--- Shares of the card's height (the arrows and their key captions) and width, and the gap.
		Height = 0.9,
		Width = 0.7,
		Gap = 0.15,
	},

	Timer = {
		Enabled = true,
		--- `%d` twice: seconds survived, and the beat's `Seconds`.
		LabelFormat = "%d / %d SEC",
	},

	Key = {
		Enabled = true,
		Height = 0.5,
		Gap = 0.25,
		--- The breath while it waits: how much bigger at the top of it, and how long one takes.
		PulseScale = 1.06,
		PulsePeriod = 1.1,
	},

	Chase = {
		Enabled = true,
		--- Before the truck is on the road: `%d` is whole seconds until it is.
		CountdownFormat = "TRUCK IN %d",
		--- Once it is: `%d` is the distance to it in studs, the same number the chip over it shows.
		DistanceFormat = "%d STUDS AWAY",
		--- Armed but with no countdown to show, and banked.
		ComingText = "TRUCK COMING",
		DoneText = "MADE IT",
	},
}

--[[ THE TWO TARGETS THAT MOVE WITH THE NEW UI (`docs/NewUI-Migration-Plan.md`, Phase 3). The
	worlds screen and the car picker are rebuilt on the Cartoony Kit, whose pages hold their rows in
	`Main.ScrollingFrame` rather than the old `Cards`, so a `Page` link can carry `PathV2` beside
	`Path` and `TutorialController._findGui` walks it instead whenever `UIRoot.isNewUI()`.

	Written once here because both chains below (the PLAY beat and `Offroad`) point at the same two
	buttons. Each is filled in by the Phase 3 page that owns it; until then it names nothing, and a
	missing hop is an arrow that waits for its target rather than an error. ]]
TutorialConfig.TeleportPathV2 = { "Main", "ScrollingFrame", "World1", "Btns", "PlayBtn" }
TutorialConfig.StartCarPathV2 = { "Main", "ScrollingFrame", "Starter", "Btns", "EquipBtn" }

-- === The beats ==============================================================

--[[ In order, and the order in this table IS the order they are served. ]]
TutorialConfig.Steps = {
	--[[ ---------------------------------------------------------------- 1. PLAY

		Four items off the board card in one beat: join, the arrow and pulse on PLAY, the arrow
		moving to world one, and the starter car pulsing on the screen after that.

		THEY ARE ONE BEAT AND NOT FOUR because they are one decision — "start a run" — taken through
		however many screens that currently costs. `RaceConfig.PlayOpensWorldSelect` and
		`StartCarConfig.Enabled` can each take a press out of it, and a beat list that hard-coded
		three presses would be wrong the moment somebody flips either. The arrow follows what is on
		screen (`Target.Then`); the objective is the run. ]]
	{
		Id = "play",
		Funnel = 1,
		Title = "START YOUR FIRST RUN",
		Hint = "Hit PLAY",
		Where = "Lobby",
		Advance = { Kind = "Signal", Service = "RaceService", Signal = "RaceEntered" },

		--[[ POINTER ONLY. Three presses, and on every one of them the arrow is already sitting on
			the single button that works — the other one is REFUSED (`Gate`, below), so there is not
			even a wrong choice for a card to steer them away from. `Title` and `Hint` are kept
			because the chain's links still carry per-screen copy and taking that out would be taking
			out the writing rather than the panel; nothing draws them while this is false. ]]
		Card = false,

		--[[ A LOBBY BEAT GATES INPUT INSTEAD OF TIME. There is no motion in a lobby to freeze, so
			"the game is waiting on you" has to be said some other way, and the way that guarantees
			the beat is completing is to make the pointed-at button the only one that works.

			It is a soft refusal rather than an invisible wall: a press on anything else bumps the
			arrow rather than doing nothing, so a player who tries the shop learns where to go instead
			of learning that the game is broken. See `TutorialController._gateButton`. ]]
		Gate = "Input",

		Target = {
			Kind = "Hud",
			Path = { "Play" },
			--[[ ...and once the WORLDS screen is up, the card on it; and once the SELECT CAR screen
				is up, the STARTER card on that. Each `Then` is taken while its own page is visible,
				so the arrow follows the player through all three presses without any of them being a
				beat of its own.

				EACH LINK CARRIES ITS OWN HINT, and that is not polish. The beat's own hint is "Hit
				PLAY", which stops being true the instant the WORLDS screen opens — two presses later
				the card was still saying it while the pointer sat on a car. A player reading the
				words and a player following the arrow were being sent to different places, which is
				the one thing a tutorial may never do. The TITLE stays the beat's throughout, because
				the objective has not changed: all three presses are still "start your first run".

				`Starter` is the one card on that screen with a name known in advance — the rest are
				named after the car key they stand for, which depends on what the player owns — and it
				is also the right one to point a player who has stolen nothing at, since it is the
				only car they have. ]]
			Then = {
				Kind = "Page",
				Page = "Teleport",
				Path = { "Cards", "Viewport", "Track", "Card1", "TeleportButton" },
				PathV2 = TutorialConfig.TeleportPathV2,
				Hint = "Pick a world. CITY is the one you have",
				Then = {
					Kind = "Page",
					Page = "StartCar",
					Path = { "Cards", "List", "Starter" },
					PathV2 = TutorialConfig.StartCarPathV2,
					Hint = "Take your car out",
				},
			},
		},
	},

	--[[ ---------------------------------------------------------------- 2. BOOST

		The run has just gone live and the world is already stopped. The card names one key; holding
		it lifts the freeze and the car pulls away under boost.

		WHY THE FIRST LESSON IS BOOST AND NOT "DRIVE". The board card says "hold W to drive", and in
		most games of this shape that is what W does. Not here: `DriveConfig.AutoThrottle` is 1, the
		throttle is always full, and W is the one thing on top of it — it lifts the speed ceiling by
		`BoostSpeedScale` for as long as it is held. Teaching "hold W to drive" would be teaching a
		control that does not exist, and the player would discover within ten seconds that letting go
		changes nothing about whether they are moving.

		So the beat teaches the real verb and uses the freeze to make the sentence true anyway: from
		a standstill, holding W IS what makes the car go, and it goes fast. The hint says the rest.

		THIS IS THE ONE PLACE A PAUSE IS FREE. The freeze lands before the car has moved a stud, so
		there is no motion to interrupt and nothing to jerk — the run simply has not started yet. ]]
	{
		Id = "boost",
		Funnel = 2,
		Title = "HOLD %s TO BOOST",
		Hint = "The car will always drive forward, but use %s to go faster!",
		Where = "Race",
		Freeze = true,
		Advance = { Kind = "Input", Input = "Accelerate" },
		--- Both the title and the hint name the same key, and `_fill` passes this list to each.
		Fill = { "Accelerate" },
		--- The speed bar under the card, and the speed target that closes the beat. See `Meters`.
		Meter = "Speed",
		Staged = true,

		--[[ A beat and a half of daylight before the freeze bites. The road fades in, the camera
			settles behind the car and the engine starts — all of it on real time and none of it
			worth stopping. Freezing into the first frame of that looks like the game hung. ]]
		Grace = 1.2,
	},

	--[[ ---------------------------------------------------------------- 3. STEER

		Two lane changes, tallied on the card, and no freeze at all.

		A LESSON ABOUT MOVING SIDEWAYS CANNOT BE TAUGHT BY A STOPPED CAR. Every other paused beat
		asks for an input whose effect is visible from a standstill — the throttle pulls you away,
		the jump throws you out of the seat. A steering input at zero speed does nothing you can see:
		`DriveController._lane` writes a cross VELOCITY, so with the car anchored the player would
		press A, watch nothing happen, and conclude the key is not the one the card named.

		It is also the beat that least needs a cage. It arrives seconds after the player has just
		successfully pressed a key the game asked for, on an empty road, with nothing to hit — and
		the tally is its own instruction. The board card asks for a pause on three beats and this is
		not one of them.

		COUNTED PER DIRECTION, not per press: `Count = 2` with the two directions distinct, so
		leaning on A alone does not finish it. That is what makes it "LEFT AND RIGHT" rather than
		"press a key twice". ]]
	{
		Id = "steer",
		Funnel = 3,
		Title = "MOVE LEFT AND RIGHT",
		Hint = "%s and %s to change lane",
		Where = "Race",
		Advance = { Kind = "Input", Input = "Steer" },
		--- Two arrows that fill while each direction is held. See `Meters`.
		Meter = "Steer",
		--- The title names no key; only the hint does, and it names both. Extra arguments to a
		--- format with fewer directives are ignored, which is what lets one list serve both lines.
		Fill = { "SteerLeft", "SteerRight" },
		Count = 2,
		Staged = true,
	},

	--[[ ---------------------------------------------------------------- 4. SURVIVE

		Eight seconds of the real game, staged. The director clears the road ahead and deals a known
		hand of cars and obstacles onto it (`Rig.Stage`), so a first-timer meets traffic in a shape
		somebody chose rather than in whatever the spawner happened to roll.

		NOT INVINCIBLE, AND ALSO NOT ABLE TO DIE. Those are different things and the board card asks
		for both: hitting something has to hurt, or the run is teaching that nothing matters, but a
		player who wrecks eight seconds into their first ever run has been shown none of the game.
		So damage lands, the bar drops, and the bar stops at a floor (`Rig.Stage.HealthFloor`).

		It is the one beat with no input to give and nothing to press. Its Advance is a timer, and
		the timer runs on the real clock — a freeze cannot happen during it, because this beat is the
		definition of the world running. ]]
	{
		Id = "survive",
		Funnel = 4,
		Title = "WATCH THE TRAFFIC",
		Hint = "Weave through it. Clipping a car costs you",
		Where = "Race",
		Advance = { Kind = "Timer", Seconds = 3 },
		Meter = "Timer",
		Staged = true,
	},

	--[[ ---------------------------------------------------------------- 5. BAIL

		The world stops, and the card asks for the jump. This is the game's actual verb — the thing
		the whole loop is named after — and it is the input a new player is least likely to try
		unprompted, because every other driving game on the platform punishes leaving the car.

		FROZEN, and the board card says so. It is also the beat where a freeze earns the most: the
		player is doing 50 studs/s in traffic when they are asked to read a sentence and find a key
		they have not used. Unpaused, the honest outcome is that they read half of it and rear-end
		something. ]]
	{
		Id = "bail",
		Funnel = 5,
		Title = "JUMP OUT",
		Hint = "Press %s to leap out of the car",
		Where = "Race",
		Freeze = true,
		Advance = { Kind = "Input", Input = "Bail" },
		--- A key cap naming `Fill`'s first key. See `Meters`.
		Meter = "Key",
		Fill = { "Bail" },
		Staged = true,
		--[[ THE ARROW ON THE THUMB BUTTON, touch only (2026-10-16). A young playtester on a phone sat
			30s tapping the word JUMP on the card, which is not a button; the button pulsing in the
			corner (`TutorialControlHighlight`) was not enough to say "this one". `CardHome` keeps the
			card where it was rather than moving it in among the thumb controls. Remove `Target`: the
			pulse alone again, exactly. ]]
		Target = { Kind = "Hud", Gui = "DrivingHud", Path = { "Controls", "Jump" }, TouchOnly = true, CardHome = true },

		--[[ Long enough for `TutorialDirector` to get a tick in and put the target car on the road
			BEFORE the world stops. Its poll is every 0.2s (`INTERVAL`), so this is two of them plus
			room for a slow frame.

			The order matters more than the length: a freeze that landed first would stop the world
			and then have a car appear inside it, which is the one thing a paused world must never
			show. Placed first, the car is simply part of the road the player is looking at. ]]
		Grace = 0.5,
	},

	--[[ ---------------------------------------------------------------- 6. AIRBORNE

		Held in mid-air, over a car the director has put in a clear radius ahead, with the prompt to
		take it. The one beat where the pause is not a convenience but the whole shot: the game's
		signature moment, stopped at its apex, with the thing you are about to steal underneath you.

		THE FREEZE WORKS HERE FOR FREE and that is worth knowing before touching it. A flight is
		already scripted rather than simulated — `StealController` anchors your car and advances the
		arc off `dt * TimeScale.get()` — so a hold stops the arc dead with no special case anywhere.
		The rig clips hold their pose for the same reason (`AnimationTrack:AdjustSpeed(0)`).

		AND ITS ADVANCE IS A SERVER SIGNAL, not the E press. The press starts a lunge; the STEAL is
		what the server ratifies at the end of it, and that is the thing worth funnelling. The freeze
		is lifted by the press so the lunge can play. See `TutorialController._onBeatInput`. ]]
	{
		Id = "airborne",
		Funnel = 6,
		Title = "TAKE THAT CAR",
		Hint = "Press %s to steal the one below you",
		Where = "Race",
		Freeze = true,
		--[[ NOT ON ARRIVAL, which is what every other frozen beat does. This beat is served the
			instant the bail is reported, and at that instant the player is still in the SEAT — a
			hold there would stop the world before the jump had left the ground and the shot this
			beat exists for would never happen.

			So the hold waits for the arc to be over the top and for there to be a car within reach
			(`StealController:getFlight`). That second half is not a refinement: a freeze in mid-air
			with nothing in range would hold a player still, in the sky, with a prompt they cannot
			satisfy and no way down. Tying the hold to the same condition the E prompt is drawn under
			means the pause can only ever happen at a moment the player can act on. ]]
		FreezeWhen = "Airborne",
		Advance = { Kind = "Signal", Service = "StealService", Signal = "CarStolen" },
		Meter = "Key",
		--- The MOUNT key, not the bail one: by the time this beat is up the player is already out of
		--- the car and the only thing left to press is the one that takes the new one.
		Fill = { "Mount" },
		--- The same thumb button, now wearing its STEAL face, and the same "tap the word" trap: see
		--- `bail`'s `Target`.
		Target = { Kind = "Hud", Gui = "DrivingHud", Path = { "Controls", "Jump" }, TouchOnly = true, CardHome = true },
		--- The last staged beat. `bank`, which follows it, is deliberately the first road a new
		--- player drives on the shipped rules — see `Rig.Stage`.
		Staged = true,
	},

	--[[ ---------------------------------------------------------------- 7. BANK

		Drive until the truck comes, then drive into it. `Rig.TruckDelay` puts it five to eight
		seconds out rather than the shipped ten to sixteen, so this beat is short.

		`RunSettled` fires for a wreck too, so this is the one beat with a FILTER on it. `Accept` is
		handed the signal's arguments after the player — `(cash, studs, banked, ...)` — and a run
		that ended in a wreck is a run that taught the lesson and did not pass it.

		Named as `RunSettled` rather than as some "BankedCar" signal because that is the signal that
		exists; this file does not get to invent server API. ]]
	{
		Id = "bank",
		Funnel = 7,
		Title = "GET AWAY WITH IT",
		Hint = "Catch the truck and drive up its ramp to keep your car",
		Where = "Race",
		Advance = {
			Kind = "Signal",
			Service = "RewardService",
			Signal = "RunSettled",
			Accept = function(_cash: number, _studs: number, banked: boolean)
				return banked == true
			end,
		},

		--[[ ...AND WHAT IT SAYS ONCE THE TRUCK IS ACTUALLY THERE, which is the board card's "show the
			truck notification" and is a face rather than a beat of its own.

			The beat spans two quite different situations and one sentence cannot serve both. Before
			the truck spawns there is nothing on the road to look at and the only honest instruction
			is "keep driving, it is coming". After it spawns there IS something, it is 300-460 studs
			ahead and closing, and the instruction is to catch it. A card still saying "a truck is
			coming" while one is filling the windscreen is a card the player has stopped reading.

			IT ALSO GETS THE POINTER. The truck is the one thing this tutorial points at that MOVES,
			and it is exactly the thing a first-timer will not recognise — `GetawayConfig`'s own notes
			say the beat the whole game is built on is the one they are most likely to never see. A
			chip floating over it with the distance counting down is the fix for that.

			`TutorialController._face` decides which of the two is live, off `GetawayController.getTruck`
			— so the card and the road can never disagree about whether there is a truck. ]]
		--- The countdown to the truck, then the gap to it, on the bar. Both faces show it. See `Meters`.
		Meter = "Chase",
		Arrived = {
			Title = "GETAWAY TRUCK",
			Hint = "Drive up the ramp to save your car for the showroom",
			--[[ `Above` because the truck is the one world target you are never standing next to. The
				chip's default for something this tall is to hang UNDER it — right for a dealership
				sign you are parked in front of, wrong here, where it put a banner over the middle
				of the road the player was steering down. See `TutorialController._chipHeight`. ]]
			Target = { Kind = "World", What = "Truck", Above = true },
		},
		--[[ ...AND WHILE THE POLICE ARE ON THEM (2026-10-19), which only the heat arm's tutorial has
			(`PoliceConfig.Heat.Tutorial`). The truck's wait is held through a chase
			(`GetawayConfig.PoliceLock`), so "catch the truck" over a frozen countdown read as broken.
			This face says the one thing that is true and comes before the truck. No pointer and no
			meter: the police HUD's bar is the gauge. A steal made meanwhile only stretches the chase;
			nothing here asks for one (Aleafo). `TutorialController._chased` decides it. ]]
		Chased = {
			Title = "LOSE THE COPS!",
			Hint = "Don't crash, don't stop. The truck comes once they give up",
		},
	},

	--[[ ---------------------------------------------------------------- 8. PLACE

		Home, holding the car they just got away with. It goes on a podium when they put it there.

		THIS BEAT EXISTS BECAUSE THE CAR STOPPED PARKING ITSELF (`CarryConfig`). Before it, banking
		ended with the car already on a bay and COLLECT was the next thing to teach. Now the last step
		of getting the car is an action, and a tutorial that skipped straight to "stand on the mat"
		would be pointing at an empty podium while the player wonders what the thing in their hands is.

		ITS POINTER NAMES THE NEAREST FREE BAY, AND ONLY FOR AS LONG AS IT IS THE NEAREST. This beat
		had no pointer at all until now, on the argument that `What = "Bay"` means "the bay the car is
		standing on" — the question this beat asks rather than one it can answer — and that the lit
		decks are a better arrow than one chip, because the player is the one choosing.

		The lit decks stay and they are still what says "any of these". What that argument missed is
		that a first-timer holding a car does not yet know a glowing slab IS an invitation, and the
		glow only reaches `CarryConfig.Glow.Studs` — so a player who lands facing away from their lot
		has nothing on screen naming anywhere to walk. Every other objective in this list gets an
		arrow, and this is the one where the player is furthest from the thing being asked for.

		So `What = "FreeBay"` resolves to whichever free bay is nearest RIGHT NOW, asked again as the
		player walks (`Follow`). That is what keeps it from taking the choice away: walk at a
		different podium and the chip is over that one before you reach it.

		`Funnel = 9` RATHER THAN 8, with COLLECT keeping the 8 it has always had. Note 3 at the top of
		this file is the rule: a beat inserted in the middle takes the next FREE number, so a funnel
		read across a deploy does not bend where the sequence changed under it.

		IT ADVANCES ON THE PARK ITSELF, which is the same signal whichever way the player did it: out
		of their hands at a podium, or off the Cars Inventory screen. Both are the lesson. With
		`CarryConfig` switched off the car parks itself and this beat is satisfied the instant it is
		published, which is the correct behaviour for a build that does not have the feature.

		=== THE CAR IS NOT IN THEIR HANDS ANY MORE — 2026-09-28 ===================================

		WHAT IT WAS. "It is in your hands. Stand at a glowing bay and put it down" — the bank carried
		the car, so this beat taught the drop.

		WHAT IT IS. The bank puts the car in the Cars Inventory (`GarageConfig.Banking`,
		`CarryConfig`'s last header block), so a first-timer comes home empty-handed. The beat now
		teaches the podium: walk up, press it, pick the car. The pointer is unchanged — the nearest
		free bay is still the right place to send them, and `getFreeDecks` answers it whether or not
		anything is being carried — and so is the advance, since `CarParked` fires for a car picked
		off the podium exactly as for one put down from the hands. The decks only GLOW while
		carrying, which is why the hint no longer mentions a glow.

		=== IN THEIR HANDS AGAIN — 2026-09-28, later the same day =================================

		The bank carries again (`CarryConfig.Sources.Bank`, and that file's last header block for the
		hotbar that came with it), so a first-timer comes home holding the car and the beat is back to
		teaching the drop, glow and all. The pointer and the advance never changed.

		=== IT PARKS ITSELF NOW — 2026-10-19 ======================================================

		The biggest drop in the game: of the players who banked their first car, about 29% left before
		putting it on a bay, and neither look of the guide trail moved that (Gamebeast experiment 65).
		Dylan: "make them auto park the car in the bay if the bay is empty". So while this beat is live
		a car landing in the hands goes straight onto the lowest empty showroom bay
		(`TutorialConfig.AutoPark`, `TutorialService._autoPark`), before the player is even home, and
		the beat completes off the same `CarParked` it always waited for.

		IT STAYS IN THE LIST, and keeps funnel stage 9, so the funnel reads the same before and after
		the change (it should now read close to 100%). With no empty showroom bay (a Replay on a full
		lot) the car stays in the hands and this beat teaches the drop exactly as before. ]]
	{
		Id = "place",
		Funnel = 9,
		Title = "PARK YOUR NEW CAR",
		Hint = "Park it in a glowing bay. Parked cars earn tips while you drive",
		Where = "Lobby",
		Advance = { Kind = "Signal", Service = "GarageService", Signal = "CarParked" },
		Target = { Kind = "World", What = "FreeBay", Follow = true },
	},

	--[[ ---------------------------------------------------------------- 9. COLLECT

		Home, with a car on the forecourt that is earning. The arrow floats over the bay it was
		parked in and the beat ends on a foot hitting the mat.

		THE BAY NUMBER IS THE SERVER'S. Only `GarageService.awardCar` knows which bay it picked, so
		it travels with the beat rather than being worked out on the client. See
		`TutorialService._bay`.

		THERE IS NO PRICE GATE ON THIS ANY MORE. There used to be — the beat after it was SPEND IT,
		and a player sent to a board they could not afford learns that the card lies — but the board
		card's list ends here and so does this. What replaced the gate is nothing: collecting is the
		last thing asked, the money is theirs, and where it goes is the game's business rather than
		the tutorial's. ]]
	{
		Id = "collect",
		Funnel = 8,
		--[[ OUT OF THE LIST WHEN THERE ARE BUYERS (2026-10-06, Dylan): SELL's opening card says what
			tips are, so a beat that only waited for one was a wait with nothing to do. It stays for a
			build with passive income or no buyers, where it is still the lesson. A profile saved on it
			resumes on SELL (`Renamed`). ]]
		Only = GarageConfig.Income.Passive or not BuyerConfig.Enabled,

		--[[ === IT TEACHES THE TIP WITHOUT PASSIVE INCOME — 2026-09-28 =========================

			WHAT IT WAS. "COLLECT YOUR CASH" — stand on the mat in front of the car you just parked,
			advancing on `GarageService.CashCollected`.

			WHAT IT IS, with `GarageConfig.Income.Passive` off. There are no mats and that signal can
			never fire, so the beat would hang forever. It now waits for the first customer to tip for
			the car (`CustomerService.CustomerPaid`) — the thing that actually makes the dealership
			money now — with the same pointer on the same bay. It gets a CARD, which the old beat did
			not need: "walk at the marker" explains itself, "wait for a stranger to like your car" does
			not. The id and the funnel number stay, so a profile parked on this beat carries on. ]]
		Title = if GarageConfig.Income.Passive then "COLLECT YOUR CASH" else "YOUR FIRST TIP",
		--- 2026-10-06: was "Customers tip for cars they like. Wait by your car for one". Nothing needs
		--- the player beside the car, so the hint no longer asks for it.
		Hint = if GarageConfig.Income.Passive
			then "Your car earns while it sits. Stand on the mat in front of it"
			else "Customers walk up and tip for cars they like",
		Where = "Lobby",
		Advance = if GarageConfig.Income.Passive
			then { Kind = "Signal", Service = "GarageService", Signal = "CashCollected" }
			else { Kind = "Signal", Service = "CustomerService", Signal = "CustomerPaid" },
		Target = { Kind = "World", What = "Bay" },

		--[[ POINTER ONLY, and the one whose chip says more than a card could: the arrow floats over
			the bay with the distance to it counting down, which is the whole instruction. "Walk at
			the marker" is not a sentence anybody needs written down.

			The FINISH card that follows this one is not covered by the flag and is still shown — it
			is a send-off rather than an objective, and it is the only place the game gets to say
			what the loop is. ]]
		Card = if GarageConfig.Income.Passive then false else nil,
	},

	--[[ ---------------------------------------------------------------- 10. SELL

		The car is on its bay; a customer walks up and the player answers their offer. Added
		2026-10-06 for Leaf: "guarantee a car sale quicker on the onboarding after stealing a car".
		Before this, buyers were only ever random (`BuyerConfig.MeanArrivalSeconds`), so a first-timer
		could finish the tutorial without ever seeing one.

		IT FOLLOWS PLACE DIRECTLY. It came after a YOUR FIRST TIP beat for one afternoon; Dylan cut
		that beat, and this card now says what customers do (tips AND offers) in one line.

		THE BUYER IS SENT, NOT ROLLED. While a player is on this beat `BuyerService` holds back random
		arrivals and puts one buyer on the bay the car parked on, `BuyerConfig.Tutorial.Delay` seconds
		in, priced in the `BuyerConfig.Tutorial.Band` band. A buyer who leaves unanswered (the car
		moved, the clock ran out) is replaced the same way.

		TWO FACES, like BANK. Until the buyer exists the card explains and points at nothing; once one
		is on the lot (walking in included) it wears `Arrived`: the chip rides the customer while they
		walk in and gives way to their offer sign once they stand, and a gold outline stays on them
		throughout (`TutorialController._chipRide`, `BUYER_GLOW`).

		EITHER ANSWER FINISHES IT. Selling is the lesson Leaf asked for, and the offer is a good one so
		that ACCEPT is the easy call, but a player who would rather keep their only car has still
		learnt what a buyer is. `BuyerService.OfferAnswered` fires for both.

		=== ONE NPC, AND THEY ARE MADE TO WATCH IT — 2026-10-19 ===================================

		Dylan: "we just have one npc come up and that is the offer npc ... we grab their attention to
		watch the npc give an offer". Four things changed, all for this beat only:

		  • NOBODY ELSE ON THE LOT. Tipping customers are held off until this beat is answered
		    (`BuyerConfig.Tutorial.SoleNpc`, `CustomerService._wantedFloor`), so the one person who
		    walks up is the buyer. They come back with the next beat.
		  • THE BUYER WAITS FOR THEM TO BE WATCHING. The car now parks itself at the bank, so this beat
		    starts while the player is still on the road; the buyer used to arrive before they were
		    home. Now the client says when this card is up with nothing over it (`Watched`: no results
		    screen, no NEW BEST stage) and the buyer is sent `BuyerConfig.Tutorial.Delay` after that.
		  • THE CAMERA TURNS TO THEM (`Look` on the face, `TutorialConfig.Look`) while they walk in.
		  • THE PLAYER GOES TO THEM. Once the buyer is standing at the car the green guide line runs
		    from the player to them (`Guide` on the face, `GuideTrailConfig.Person`) and their gold
		    outline breathes, so the See Offer prompt is found rather than hunted for. The offer
		    opened by itself for one build (`BuyerConfig.Tutorial.OpenOnArrival`, now off); Dylan:
		    "it guides you with classic guide arrow to the offer maybe can highlight the npc so they
		    open the offer". Opening it themselves is the lesson: every later buyer works that way.
		  • THE BAYS GO QUIET (`QuietBays`, `DealershipController`). The buyer stands beside the car,
		    and on the way to them the car's Pick Up prompt (16 studs) came up before See Offer (12);
		    one E lifted the car and withdrew the offer. Every podium prompt on their lot is off until
		    the offer is answered.

		With buyers switched off this beat is out of the list, and COLLECT is the last beat. ]]
	{
		Id = "sell",
		Funnel = 10,
		Only = BuyerConfig.Enabled,
		--- Was "CUSTOMERS ARE COMING" / "Parked cars earn tips. Selling removes the car from your
		--- showroom", when the player had just parked it themselves and customers were walking in.
		Title = "YOUR CAR IS PARKED",
		Hint = "A buyer is on the way with an offer for it",
		Where = "Lobby",
		Advance = { Kind = "Signal", Service = "BuyerService", Signal = "OfferAnswered" },
		Watched = true,
		QuietBays = true,
		--- The face once this player's buyer is on the lot. See `TutorialController._arrived`.
		ArrivedWhen = "Buyer",
		Arrived = {
			Title = "YOUR FIRST OFFER",
			--- Was "Decline to keep earning tips, or accept to sell your car", while the offer opened
			--- by itself. Now the player has to go to the buyer, so the card says that.
			Hint = "Walk over to the buyer to see their offer",
			Target = { Kind = "World", What = "Buyer", OverSign = true, Follow = true },
			Look = true,
			Guide = true,
		},
	},

	--[[ ---------------------------------------------------------------- 11. AGAIN

		The offer is answered and the lessons are over: now the second run. Added 2026-10-19 (Dylan:
		"lets continue to hand hold them a little bit more into the next race, then add a funnel step
		... that starts their second race").

		THE FINISH CARD MOVED HERE. It used to come up as SELL closed and send the player off alone,
		with Play beckoning (`RaceConfig.PlayBeckon`). Now the confetti and TUTORIAL COMPLETE! come up
		as this beat lands (`Celebrate`), and the card stays up with the arrow on PLAY, through the
		WORLDS and SELECT CAR screens exactly as the first run's PLAY beat goes, with every other
		button gated. Entering a race finishes it, and with it the tutorial, quietly: the card has
		already said its last word, and the road is the send-off.

		TWO FUNNEL STAGES. Reaching this beat is stage 11 (the offer answered). Starting the race is
		stage 12, reported as the tutorial finishes (`TutorialConfig.FinishFunnel`), because a funnel
		counts arrivals and nothing arrives after the last beat. ]]
	{
		Id = "again",
		Funnel = 11,
		Title = "TUTORIAL COMPLETE!",
		Hint = "Now hit PLAY and steal a better car",
		Where = "Lobby",
		Advance = { Kind = "Signal", Service = "RaceService", Signal = "RaceEntered" },
		Celebrate = true,
		--- The PLAY beat's gate, for its reason: there is one thing to do. See `play`.
		Gate = "Input",
		--- The PLAY beat's chain, with its per-screen hints. See `play` for why each link has one.
		Target = {
			Kind = "Hud",
			Path = { "Play" },
			Then = {
				Kind = "Page",
				Page = "Teleport",
				Path = { "Cards", "Viewport", "Track", "Card1", "TeleportButton" },
				PathV2 = TutorialConfig.TeleportPathV2,
				Hint = "Pick a world. CITY is the one you have",
				Then = {
					Kind = "Page",
					Page = "StartCar",
					Path = { "Cards", "List", "Starter" },
					PathV2 = TutorialConfig.StartCarPathV2,
					Hint = "Take your car out",
				},
			},
		},
	},
}

--[[ Beats with `Only = false` are not served in this build. Filtered here rather than left as `nil`
	in the table above, which would put a hole in the array and cut `#Steps` short. ]]
do
	local served = {}
	for _, step in TutorialConfig.Steps do
		if step.Only ~= false then
			table.insert(served, step)
		end
	end
	TutorialConfig.Steps = served
end

--[[ THE FIRST CAR PARKS ITSELF (2026-10-19). While `Beat` is a player's live beat, a car landing in
	their hands is put on the lowest empty showroom bay by `TutorialService._autoPark`. See the PLACE
	beat for why. Only an EMPTY bay: a full lot keeps the car in the hands and the beat teaches the
	drop. `Enabled = false`: PLACE is the player's to do, as it was.

	`After` is the seconds between the car landing in the hands and the park. Never 0 and never a
	`task.defer`: inside one frame the FirstCarCarried and FirstCarPlaced markers (and BANK done and
	PLACE done) get the same millisecond stamp, and Gamebeast funnels cannot order a tie, so the
	onboarding board would show nobody parking. The bank happens out on the road, so nobody sees it. ]]
TutorialConfig.AutoPark = {
	Enabled = true,
	Beat = "place",
	After = 0.1,
}

--[[ THE CAMERA TURNS TO THE BUYER (2026-10-19), on a face carrying `Look = true` (SELL's, once the
	buyer is on the lot): the stock camera swings round behind the player to face the buyer as they
	walk in, and keeps facing them until they have stood at the car for `Linger` seconds. Only a buyer
	still walking is watched; one already standing (a rejoin) is just pointed at. `Modules/CameraFacing`
	does the turning, the same way it turns the camera behind the player after a run.

	`PitchDeg` is how far the shot looks down. Steeper than the line to the buyer on purpose: it puts
	them above the player's head on screen rather than behind it. `Rate` is how fast the swing closes
	the gap, per second (the gap shrinks by about 1 - e^-Rate each second). `MinStuds`: closer than
	this there is nothing to turn toward. `MaxSeconds` is the backstop for a buyer who never arrives.
	The player cannot turn the camera while it runs, which is why it is short.

	`Enabled = false`: the chip and the gold outline are the only pointer, as before. ]]
TutorialConfig.Look = {
	Enabled = true,
	PitchDeg = 22,
	Rate = 3,
	Linger = 0.8,
	MinStuds = 6,
	MaxSeconds = 10,
	--- 2026-10-20: any move or camera turn of the player's ends the turn at once (`CameraFacing.watch`);
	--- walking is camera-relative, so turning the camera under a moving player bent their path.
	StopOnInput = true,
}

--[[ ...OR AS A SHOT (2026-10-20: "a nice camera transition that shows them walking up to the car, then
	it fades back to the player camera"). With this on, the same moment `Look` waits for (the buyer
	walking onto the lot, once per beat) plays `TutorialController._buyerCinematic` instead of turning
	the player's camera: a dip to black, a fixed camera `Ahead` studs up the buyer's path and `Side`
	studs off it, `Rise` up, panning after them (`PanRate`, per second) as they walk up and past it to
	the car, then a dip back to the player's own camera behind them. Controls and the card are off for
	it. It ends `Linger` after the buyer stands at the car, or at `MaxSeconds`. `Fade` is each dip.
	`Enabled = false`: the camera turn above, as the tutorial had it before. ]]
TutorialConfig.Cinematic = {
	--- 2026-10-20: off for a demo; the camera turn (`Look`) is the one shown. True brings the shot back.
	Enabled = false,
	Ahead = 14,
	Side = 9,
	Rise = 4,
	PanRate = 4,
	Linger = 0.8,
	MaxSeconds = 8,
	Fade = 0.25,
	--- Over the card and the HUD, under the race fade (1000).
	DisplayOrder = 990,
}

--[[ THE STAGE AFTER THE LAST BEAT (2026-10-19). Roblox's onboarding funnel counts players REACHING a
	stage (`TutorialService._funnel`), so finishing the last beat has no stage of its own unless one is
	reported for it. The last beat is AGAIN, which a race entry finishes, so this stage reads "started
	their second race". Reported once, by `TutorialService._advance`, with the same per-session guard
	as every other stage. `Stage = nil`: nothing after the last beat. ]]
TutorialConfig.FinishFunnel = {
	Stage = 12,
	Id = "race2",
}

--[[ WHERE AN OLD PROFILE'S BEAT LANDS. This file used to hold five steps — play, steal, bank,
	collect, upgrade — and the rewrite renamed two of them and retired one. Every save written by
	that build names a step id in one of those three groups, and a profile is not something you get
	to break because a design changed.

	    play, bank, collect   still exist under the same ids, so they are not in here at all
	    steal   ->  bail      the old single "steal a car" step is now three beats. A player mid-way
	                          through it is put at the START of that stretch rather than at its end:
	                          the two beats they would skip are the two that teach the jump, which is
	                          exactly what somebody stuck on the old step had not worked out.
	    upgrade ->  DONE      it was the LAST step of that list. Somebody who reached it finished the
	                          tutorial that existed when they played it, and running them through a
	                          longer one now would be punishing them for having been early.

	ANY ID NOT LISTED AND NOT IN `Steps` restarts the player from the top, loudly — see
	`TutorialService._resume`, case 5. That is the safe direction, and the log line is there because
	the only way to reach it is to edit `Steps` without editing this. ]]
TutorialConfig.RenamedDone = "__done__"

TutorialConfig.Renamed = {
	steal = "bail",
	upgrade = TutorialConfig.RenamedDone,
	--- Only reached when COLLECT is out of the list (it is looked up for ids `Steps` lacks).
	collect = "sell",
}

--[[ WHAT A RACE BEAT SAYS WHEN THERE IS NO RACE.

	Five of the eight beats happen on the road, and a player can be sitting in their dealership on
	any one of them: they wrecked, they whiffed the jump, they left mid-run, they rejoined. The beat
	is still correct — the server has not advanced it, because they have not done the thing — but
	the WORDS are not. A card reading "TAKE THAT CAR / Press E to steal the one below you" while
	somebody stands on their own forecourt is the tutorial talking about a world that is not there,
	and it is the single most likely way this feature ends up looking broken.

	So every race beat has the same lobby face, and it is the same one because the answer is the
	same for all five: you are not on the road, and the way back onto it is the PLAY button. It
	gates like the first beat does, for the same reason — there is exactly one thing to do.

	IT IS A FACE AND NOT A BEAT. Nothing about the sequence changes: the player is still on `bail`
	or `airborne` or wherever they were, the funnel still says so, and the moment a run goes live
	the card goes back to naming the objective. This is what the card says in the meantime.

	WHY THE COPY DOES NOT MENTION WHAT WENT WRONG. It cannot know — a wreck, a whiff, a bank that
	did not count and a rejoin all land here, and a sentence that guessed would be wrong most of the
	time. What every one of them has in common is that another run is the answer. ]]
TutorialConfig.Offroad = {
	Title = "BACK ON THE ROAD",
	Hint = "Hit PLAY to start another run",
	Gate = "Input",
	--- Pointer only, for the PLAY beat's reason exactly: it IS the PLAY beat, worn by a different
	--- objective. The card comes back the moment the run is live and the beat says its own name.
	Card = false,
	Target = {
		Kind = "Hud",
		Path = { "Play" },
		--- Hints per link, for the reason spelled out on the PLAY beat's own chain.
		Then = {
			Kind = "Page",
			Page = "Teleport",
			Path = { "Cards", "Viewport", "Track", "Card1", "TeleportButton" },
			PathV2 = TutorialConfig.TeleportPathV2,
			Hint = "Pick a world. CITY is the one you have",
			Then = {
				Kind = "Page",
				Page = "StartCar",
				Path = { "Cards", "List", "Starter" },
				PathV2 = TutorialConfig.StartCarPathV2,
				Hint = "Take your car out",
			},
		},
	},
}

--- The beat at `index`, or nil. Used by both halves so neither has to know the table is an array.
function TutorialConfig.stepAt(index: unknown)
	local n = tonumber(index)
	if not n or n < 1 or n > #TutorialConfig.Steps then
		return nil
	end
	return TutorialConfig.Steps[math.floor(n)]
end

--- Where `id` sits in the list, or nil if it is not a beat (a profile from a build that had a beat
--- this one does not). Never falls back to 1 — resuming a stranger onto the first objective would
--- restart a tutorial somebody had half finished. `TutorialService` decides what to do about it.
function TutorialConfig.indexOf(id: unknown): number?
	if type(id) ~= "string" then
		return nil
	end
	for index, step in TutorialConfig.Steps do
		if step.Id == id then
			return index
		end
	end
	return nil
end

--- The beat with this id, or nil.
function TutorialConfig.stepOf(id: unknown)
	local index = TutorialConfig.indexOf(id)
	return if index then TutorialConfig.Steps[index] else nil
end

--- Is `id` one of the beats that happens on the road? Read by the rig, by the director and by
--- anything that wants to stay quiet during a run. Derived from `Where` rather than listed twice.
function TutorialConfig.isInRace(id: unknown): boolean
	local step = TutorialConfig.stepOf(id)
	return step ~= nil and step.Where == "Race"
end

--[[ NO EVENTS IN THE TUTORIAL. Two questions every "extra" system (police, weather, speed traps) asks
	so the first run is only ever the lessons, and they are asked of the step id on
	`StepAttribute`:

	  • `isUnfinished` — is there any tutorial left at all, lobby beats included? For things that can
	    interrupt the lobby too, like the weather notice.
	  • `isTutorialRun` — is a race starting NOW the tutorial's run? True from the first beat through
	    the last beat that happens on the road (`bank`), so the whole drive home is covered even though
	    `bank` lets the road go back to its real rules. A later race taken before `collect` is done is
	    an ordinary run.

	Callers LATCH `isTutorialRun` when the race starts and keep it for the whole run (a revive
	included): the step advances mid-run, and a chase or a storm arriving the moment the player lands
	the steal is exactly what this exists to stop. ]]
function TutorialConfig.isUnfinished(stepId: unknown): boolean
	return TutorialConfig.isOn() and TutorialConfig.indexOf(stepId) ~= nil
end

function TutorialConfig.isTutorialRun(stepId: unknown): boolean
	if not TutorialConfig.isOn() then
		return false
	end
	local index = TutorialConfig.indexOf(stepId)
	if not index then
		return false
	end
	local lastRace = 0
	for i, step in TutorialConfig.Steps do
		if step.Where == "Race" then
			lastRace = i
		end
	end
	return index <= lastRace
end

--- Does this beat stop the world while it is up? One function so that the card, the director and
--- the freeze itself cannot disagree about which three beats those are.
function TutorialConfig.freezes(id: unknown): boolean
	local step = TutorialConfig.stepOf(id)
	return step ~= nil and step.Freeze == true
end

--[[ THE FIRST BEAT ON WHICH THE JUMP IS THE PLAYER'S TO MAKE. Everything before it refuses a bail
	outright — see `TutorialConfig.allowsBail` below and `StealController._canBail`.

	It is a beat id rather than a number for `StepAttribute`'s reason exactly: an index is a value
	whose meaning changes the day a beat is inserted, and this one would silently start gating the
	wrong stretch of the run. ]]
TutorialConfig.BailBeat = "bail"

--[[ May a player whose live beat is `stepId` jump out of their car?

	=== WHY THE JUMP IS TAKEN AWAY AT ALL ======================================================

	A bail is bound for the whole race — the key is live from the moment the run starts — and the
	tutorial's first four beats are not asking for it. A player who presses it on BOOST, STEER or
	SURVIVE gets a flight the tutorial never dealt a target for, and lands in a run whose remaining
	beats are all describing a car they are no longer in. Reported from the 24 Aug playtest as a
	car that stopped responding mid-run with the truck objective on screen, and it is the same
	stretch of road the two anchor bugs in `StealController._onBail` and `_watchFreeze` were both
	found on: a bail from inside a frozen beat is a flight the world is holding still.

	Both of those are fixed and both fixes stay — they are what makes a bail from inside the BAIL
	beat's own hold work, which is a thing the tutorial DOES require. This is the narrower rule
	they cannot state: not "survive a jump taken at the wrong moment" but "there is no wrong
	moment, because the jump is not there yet". The verb arrives with the beat that teaches it.

	=== AND WHY IT COMES BACK AND NEVER GOES AWAY AGAIN ========================================

	`bail` and everything after it is the whole rest of the game. AIRBORNE is mid-flight and needs
	the jump that got there; BANK is deliberately the first road a new player drives on the shipped
	rules (see `Rig.Stage`), and a player who wants to trade up once more on the way to the truck is
	playing the game correctly. So the gate is a floor on the sequence, not a window.

	FAIL OPEN, three times over, and each of them for the same reason: this function's job is to
	hold back a verb for four beats of one run, and every unknown here is a player the tutorial is
	not currently teaching. A gate that guessed wrong in the other direction would take the game's
	signature mechanic off somebody who has finished it. So the tutorial being off, a beat id this
	build does not have (a profile from another build, or the empty string that means finished or
	skipped), and a `BailBeat` that has been renamed out of `Steps` all answer yes. ]]
function TutorialConfig.allowsBail(stepId: unknown): boolean
	if not TutorialConfig.isOn() then
		return true
	end
	local gate = TutorialConfig.indexOf(TutorialConfig.BailBeat)
	local index = TutorialConfig.indexOf(stepId)
	if not (gate and index) then
		return true
	end
	return index >= gate
end

--[[ Does this FACE get a panel, or is it pointer only? See the `Card = false` note in the vocabulary
	above for what the two mean.

	It takes a face rather than an id on purpose: which one is live changes under a beat that does
	not — `Offroad` and `Arrived` are both faces of beats that go on being themselves — and the card
	has to follow whichever is being SAID. Absent means shown, so a new beat gets a card by writing
	nothing, and dropping one is the deliberate act. ]]
function TutorialConfig.showsCard(face): boolean
	return face ~= nil and face.Card ~= false
end

-- === The staged first run ===================================================

--[[ What is different about the run a first-timer takes, and — just as importantly — what is not.

	WHAT IS NOT: the car, the controls, the road, the world, the payout, the wreck. The run is the
	real run, at the real speed, and every hazard on it can hurt. A tutorial that cannot be failed
	teaches a game that does not exist, and this one's whole tension (GDD §3.2) is that a wreck costs
	you the car you are holding. (The hits still land; since 2026-10-05 the RUN cannot end on them —
	see `TutorialConfig.Unlosable`.)

	WHAT IS: the timing of the exit, and the CONTENTS of the road for the first half-minute.

	`Rig.Enabled = false` puts the tutorial run on the shipped numbers and changes nothing else. ]]
TutorialConfig.Rig = {
	Enabled = true,

	--[[ Seconds after the arming steal before the truck appears, replacing
		`GetawayConfig.Spawn.Delay` while a tutorial run is in progress.

		About half the shipped band. Not shorter than this: the truck spawns 300-460 studs ahead and
		has to be CAUGHT, which is 14-21 seconds of closing at a cruise, so the delay is the small
		half of the wait either way. Cutting it to nothing would only mean the truck is already
		waiting when the player looks up, which reads as scenery rather than as an event. ]]
	TruckDelay = { 5, 8 },

	--[[ ...and after one has been missed. The shipped 14-22 makes blowing past a truck a real cost,
		which is correct for a game and wrong for a lesson: the tutorial player who misses one did
		not decide to, they did not know what it was. So the retry is quick enough to still be part
		of the same lesson. ]]
	TruckRetryDelay = { 6, 10 },

	--[[ Studs behind the driver at which a missed truck gives up and leaves, replacing
		`GetawayConfig.DespawnBehind` (280). Wider, so a first-timer who drives past the ramp, works
		out what it was and lifts off has a chance to get back to it. The truck is slower than the
		player, so this is the only thing deciding how long "past it" lasts. ]]
	DespawnBehind = 520,

	--[[ THE CHOREOGRAPHY. Everything under here is `TutorialDirector`'s, it is all client-side, and
		it only ever applies to a player whose live beat is one of the in-race ones.

		The shipped spawner is good at keeping a road populated and has no opinion about what the
		first thirty seconds of somebody's life in this game look like. `TrafficConfig.PrimeCount`
		seeds ten cars between 140 and 1,500 studs at race start and `MaxCars` holds twelve around
		the driver after that, rolled at random lanes and random speeds. That is the right road for
		the eight hundredth run and the wrong one for the first, where "is there a car near me" and
		"can I get past it" both need to be answerable at a glance.

		So for the length of the tutorial's beats the director takes the wheel: it holds the road
		clear while the player is being taught a key, deals `SurviveCars` at a known spacing when the
		beat is about traffic, and puts exactly one car in a known place when the beat is about
		stealing one. Then it lets go, and the shipped spawner has the road back for the rest of the
		run — including the whole of the truck beat, which is deliberately the first unstaged part of
		the game a new player sees.

		WHICH BEATS ARE STAGED IS A FLAG ON EACH (`Staged`), not "the ones that happen in a race".
		Those were the same set right up until `bank` existed, and the difference between them is the
		entire point of `bank`. See `TutorialConfig.isStaged`. ]]
	Stage = {
		Enabled = true,

		--[[ Studs of road ahead of the driver kept EMPTY while a beat is being taught. Covers the
			boost, steer and bail beats, all three of which end with a key press rather than with a
			manoeuvre, and none of which is improved by a lorry appearing during it.

			Sized off stopping distance rather than off taste: at a boosted 71 studs/s this is a bit
			under four seconds of road, which is longer than any of those three beats has ever taken
			in a playtest. ]]
		ClearAhead = 260,

		--[[ ...and how many cars the SURVIVE beat puts back, with the gap between them in studs.

			Four, which is the board card's number, at a spacing that is deliberately not even: a
			regular pulse of cars reads as a wall and gets driven at rather than through, and the
			point of the beat is that the player picks a gap. The lane each one takes is chosen at
			the time so that no two adjacent cars sit in the same one — the director owns that, and
			it is the one rule that makes four cars a slalom rather than a queue. ]]
		SurviveCars = 4,
		SurviveGap = { 95, 150 },

		--[[ How far ahead of the driver the first of them is put. Far enough that it arrives rather
			than appears — a car materialising inside the range you can read is the one thing the
			shipped spawner is careful about too (`TrafficConfig.SpawnAheadMin`). ]]
		SurviveLead = 230,

		--[[ The floor the tutorial run's HP will not go below, as a fraction of the car's maximum.
			The board card's "don't make the car invincible but don't allow the player to die" in one
			number.

			A quarter, because it has to be low enough that the bar visibly plummets on a bad clip —
			the lesson is that hitting things hurts — and high enough that a player who hits
			everything still arrives at the jump with a car under them. It is a FLOOR on the damage,
			not a shield: every hit is priced normally and the bar moves by the real amount until it
			reaches this.

			Lifted the moment the tutorial's in-race beats are over, which is at the steal — so the
			truck beat, the first part of the run the player drives unaided, is played for real. ]]
		HealthFloor = 0.25,

		--[[ THE CAR THE TUTORIAL PUTS UP TO BE STOLEN, placed when the BAIL beat arms so that it is
			already on the road and already moving by the time the player is in the air over it.

			=== THERE IS NO `Ahead` HERE ANY MORE, AND THAT IS THE FIX ===========================

			This used to be one constant, and it was wrong at every value it was ever given — 120
			studs first, then 30. Both whiffed, because the distance a bail covers is not a property
			of the game. It is a property of how fast the player was going when they pressed Space:
			the arc brakes toward traffic pace on the way down (`StealConfig.Flight.Glide`), so a slow
			bail and a fast one do not cover the same ground at all.

			    airtime     ~2.0s   apex at `Launch.Up` 108 / `RiseGravity` 240, floated back down
			    travel      96 studs from a 60 studs/s bail, 122 from a 90 studs/s one
			    closing     the target is DRIVING AWAY at ~31, so what the jump closes is 34 studs
			                from the slow bail and 67 from the fast one

			No constant lands on a car from both ends of that, and at the cruise this game is actually
			driven at the shipped 30 was short by half a road: the player sailed clean over the car
			they were aimed at, which is what it was reported as. So the director asks the flight
			instead — `StealController.predictBail` runs the real integrator forward on a jump nobody
			has made yet, and `TutorialDirector._placeStealTarget` puts the car where that lands.

			`Fallback` is the only distance left in this table, and it is a distance nobody should see:
			it is used when the prediction cannot be made at all (no road, no car), which is a state
			the beat cannot be played in anyway.

			`Clear` is how far PAST the target the road is emptied, and it has to be past it rather
			than up to it: the board card asks for "a clear radius", and the landing volume is the
			whole difficulty of a steal. A first attempt that clips a bystander on the way down reads
			as the mechanic not working rather than as a miss.

			`Lead` is the gap the car is put at, and `MinPace` is what the tutorial is allowed to slow it
			to in order to leave that gap catchable. Together they are the answer to a case no
			placement can fix on its own:

			    A BAIL CLOSES THE DIFFERENCE IN SPEED, not a distance. At cruise the arc covers ~120
			    studs while a tier 2 covers ~55, so it closes sixty-odd and the car can be put well out
			    in front. Arrive at this beat SLOW — rear-ended during SURVIVE, caught behind
			    somebody — and the arc covers 58 while the car covers 51, so it closes seven. There is
			    no distance that makes that work, because at that point the gap is barely shrinking at
			    all; put the car anywhere visible and the jump lands behind it.

			So the target's cruise is chosen rather than rolled: fast enough to keep its own tier's pace
			when the player is quick (which is every ordinary run, and the car behaves exactly like
			traffic), and slowed toward `MinPace` when they are not, so `Lead` studs of gap is a gap
			the jump actually closes. `MinPace` is a floor because a car crawling at walking pace on a
			motorway reads as broken, and at that point `Reach` is the better tool.

			`Settle` is how long the player goes on DRIVING between the car being put down and the world
			stopping, and it is a measured number rather than a derived one. The obvious derivation is
			the beat's own `Grace` (0.5s) and it is wrong by a factor of three: the card has to slide
			in and stamp DONE over the last objective before this beat's clock starts at all, and the
			whole of that is real time with the player at cruise. Measured end to end, from the beat
			arriving to the world stopping: 1.70s, over which a driver at 70 studs/s eats 119 studs of
			road and closes seventy-odd on the target.

			That is the error that made the placement look random. Under-led, the player reached the
			car before they were ever asked to jump, drove PAST it, and then jumped at a car that was
			behind them — which no arc can reach and no correction can undo. So this errs LONG on
			purpose: a car placed too far ahead is one `_aimStealTarget` can slow down to meet the
			jump, and a car placed too close is one the player has already passed.

			`MaxPace` is the other end of the same dial, and it is there for the correction the
			placement CANNOT make in advance: the gap goes on changing between the moment the car is
			put down and the moment the player actually jumps, because the card takes a beat to arrive
			and the player is driving the whole time. So the target's pace is nudged again, every tick
			of the flight, toward whatever puts it under the arc — see `TutorialDirector._aimStealTarget`.
			Fifty-two is a shade above the fastest car this road ever spawns (a Supercar at 44), so the
			correction can always be made and the car never moves like something that is not a car.

			`Clean` is how far ahead of the mark the player's own LANE has to be free of obstacles for
			the car to be put there, and it is short on purpose. The road's own number is 200 studs
			(`TrafficConfig.AvoidLookahead`), which is the right horizon for a car that has to drive
			this lane for the next ten seconds and the wrong one for a car that is stolen two seconds
			later. On the long horizon the target was vetoed out of the driver's lane and into
			whichever one was free, which on a five-lane road is usually two over — and two lanes is
			thirty studs of sideways, which no jump covers. Ninety is one flight of driving with room.

			`Reach` is how far E works from while the rig is on (`StealController._reach`), and it is
			the slop budget for everything the placement cannot know: the car's cruise is rolled
			inside its tier's band, the player keeps driving for the beat's `Grace`, and they can
			steer in the air. It widens the prompt, the tutorial's mid-air freeze and the perch
			together, because all three ask the same lookup. It does NOT lengthen the dive — the
			freeze is taken at the arc's closest approach, so E is always pressed from as near as that
			jump was ever going to get.

			`Tier` is which rung of the ladder it is rolled from. One above the starter, so the car is
			plainly BETTER than the one being left behind — the loop is "steal a better car", and a
			first steal that hands you a sidegrade teaches the verb and not the reason.

			`Regrow` is how far ahead the road has to be EMPTY before the beat gives up on the car it
			dealt and deals another (`TutorialDirector._targetLost`). It is a horizon rather than a
			gap, and it is generous on purpose: a player who is merely trailing their target has a
			car to steal and wants no help, and re-dealing on a small number would put a second car
			on a road that already had one.

			Measured off the placement rather than guessed. A target is aimed at `Fallback`-and-up
			and the road is cleared `Clear` past it, so anything under about 210 studs is still
			inside the hole this beat dug for itself and would re-deal into its own clearance. Above
			that, an empty window this long means the car is genuinely gone: taken, wrecked into
			debris, recycled behind the driver, or simply never caught.

			=== FOUR OF THESE ARE SHARES OF THE PLAYER'S OWN CRUISE NOW ==========================

			`Fallback`, `Lead`, `MinPace` and `MaxPace` are studs and studs/s, and every one of them
			was measured against a game that cruised at 52. The roster cruises at 71 to 103 today and
			traffic went with it: `TrafficConfig` stopped authoring tier speeds in absolute studs/s
			for exactly this reason and made them shares of whatever the player is driving. So four
			constants sized against 52 were four constants wrong by half a road, and wrong by a
			DIFFERENT half depending on which car the player had stolen their way into by then.

			Each one now has a `...Fraction` twin, and the absolute under it is what a frame with no
			resolvable cruise falls back to. Three of the fractions are simply the old number over
			the cruise it was authored against, so a slow game plays exactly as it always did:

			    Lead      40 / 52  =  0.77     the gap the car is put at
			    MinPace   14 / 52  =  0.27     the crawl the aim is allowed to slow it to
			    Fallback  70 / 52  =  1.35     the distance nobody should ever see

			`MaxPaceFraction` is the one that is not a division, because 52 was never a fact about the
			player: it was "a shade above the fastest car this road ever spawns, a Supercar at 44".
			The fastest car on the road is the top of `TrafficConfig.Tiers`, which is 0.94 of cruise
			now, and the same shade above that is 1.10. At the old absolute the correction could not
			even hold a tier 2 at its own pace: a tier 2 at a cruise of 85 runs 55, and every tick of
			the flight dragged it back down to 52. ]]
		StealTarget = {
			Fallback = 70,
			FallbackFraction = 1.35,
			Clear = 140,
			Clean = 90,
			Lead = 40,
			LeadFraction = 0.77,
			MinPace = 14,
			MinPaceFraction = 0.27,
			MaxPace = 52,
			MaxPaceFraction = 1.1,
			Settle = 1.8,
			Reach = 30,
			Tier = 2,
			Regrow = 260,

			--[[ Seconds of DRIVING on BAIL or AIRBORNE, with no jump started, before the director
				stops staging the steal and hands the road back to the shipped spawner
				(`TutorialDirector._ignoredTheJump`). Added 2026-10-15.

				A player who does not press the key gets the world back after `FREEZE_TIMEOUT` and
				keeps driving, and until this existed the beat had no end: the spawner stayed shut,
				every re-deal cleared the road ahead, and the only car ever on it was the next target
				dropped into their lane. No traffic, no truck (one needs a steal), and no wreck (the
				run cannot be lost), so the run went on forever down an empty road.

				Only time the world is moving counts, so the frozen ask itself spends none of it,
				and any jump starts the count again: a player who is trying keeps their staged car.
				Handing back is the existing rule that the objective is to take A car. ]]
			HandBack = 12,
		},
	},
}

-- === The tutorial cannot be lost ============================================

--[[ === A FIRST RUN THAT ENDS IN A LOSS IS NOT A LESSON — 2026-10-05 ======================
	A playtester: "I can lose in the tutorial, that's really bad", and then the run they restarted
	asked them to TAKE THAT CAR while they were sat driving on the road. Two holes, both real:

	  • The damage floor (`Rig.Stage.HealthFloor`) only covered the STAGED beats and was lifted at the
	    steal, so the truck beat was played for real — a wreck there ended the run. And a MISSED JUMP
	    was never covered by any floor at all: landing on the tarmac goes straight to `wreckRace`
	    ("badLanding"), which is not a revivable cause, so the run simply ended.
	  • The AIRBORNE beat is entered the instant the bail is reported, and its only exit is a steal.
	    A miss left the player on it — so the next run, or the rest of a revived one, showed "TAKE THAT
	    CAR / Press E to steal the one below you" to somebody who was not in the air.

	WAS: the header of `Rig` — "a tutorial that cannot be failed teaches a game that does not exist".
	That is still true of the HITS, and they still land at full price. What it is no longer true of
	is the ENDING: the owner's call is that a first run must not be lost, so NOW, for every in-race
	beat (the truck beat included):

	  `Floor`   the HP floor holds for the whole tutorial run, not only the staged part of it.
	  `Rescue`  anything that would still end the run — a missed jump, the police — is a free,
	            automatic revive instead (`RaceService.wreckRace`): the wreck beat plays as normal, and
	            then the car is put back on the road with no offer screen, no price and no revive
	            counted against the player's ladder. "fell" is left alone: it is the void guard
	            catching a physics failure, not a mistake, and it already goes home for free.
	  `Rewind`  a beat whose attempt failed is put back on the beat that STARTS it — a miss on
	            AIRBORNE goes back to BAIL — at the failure, and on a rejoin from it.

	`Enabled = false` is the tutorial exactly as before this note: floor on the staged beats only,
	the run lost on a wreck or a miss, AIRBORNE kept through a miss.

	=== A MISS IS NOT A WRECK AT ALL — 2026-10-05, same day ==================================
	The first version let a miss wreck the run and then revived it, and in play that was "super
	duper glitchy": a ragdoll left on the road beside the camera, a car fought over by the server's
	freeze and the client's flight, a revive path no miss had ever taken before. NOW a tutorial miss
	never becomes a wreck (`Catch`): the flight is called off on the spot and the player is simply
	back in the seat of the car they jumped out of, driving — the same restore a flight interrupted
	by the race ending already uses (`StealController._abort`), which is a well-worn path. The server
	only hears that the attempt failed (`StealMissed`), and rewinds the beat. `Rescue` stays, for the
	one ending the floor cannot stop (the police). ]]
TutorialConfig.Unlosable = {
	Enabled = true,
	Floor = true,
	Rescue = true,
	Catch = true,
}

--- Beat id -> the beat that starts its attempt, for `Unlosable` (see `TutorialService.rewindAttempt`).
TutorialConfig.Rewind = {
	airborne = "bail",
}

--- Is a run by a player on `stepId` one the tutorial will not let them lose? Pure.
function TutorialConfig.isUnlosable(stepId: unknown): boolean
	return TutorialConfig.isOn() and TutorialConfig.Unlosable.Enabled and TutorialConfig.isInRace(stepId)
end

--- Should the tutorial's numbers be used for a player whose live beat is `stepId`? One function so
--- that every consumer agrees on when the rig is on, and so that turning it off is one switch.
function TutorialConfig.isRigged(stepId: unknown): boolean
	return TutorialConfig.isOn() and TutorialConfig.Rig.Enabled and TutorialConfig.isInRace(stepId)
end

--[[ ...and whether the ROAD should be staged for them, which is a narrower question than `isRigged`
	in two ways and both of them matter.

	It has its own switch (`Rig.Stage.Enabled`), so the truck timings are worth keeping when the
	choreography is off. And it is per-BEAT rather than per-half-of-the-game: `bank` happens on the
	road and is deliberately NOT staged, because it is where the tutorial lets go. The player has
	just stolen a car; what is left is to drive it to the truck, and that has to be the real road on
	the real rules or the first thing they ever do unaided is also the first thing that surprises
	them.

	Reading a per-beat flag rather than "is this beat in a race" is what fixed that: the two were the
	same set until `bank` was added, at which point the spawner stayed shut and the damage floor
	stayed on for the whole run home. ]]
function TutorialConfig.isStaged(stepId: unknown): boolean
	if not (TutorialConfig.isOn() and TutorialConfig.Rig.Enabled and TutorialConfig.Rig.Stage.Enabled) then
		return false
	end
	local step = TutorialConfig.stepOf(stepId)
	return step ~= nil and step.Staged == true
end

-- === The card ===============================================================

--[[ Copy and timings for the objective card and the arrow. Here rather than in the controller for
	the reason `QuestConfig`'s copy block gives: these are sentences somebody who is not me will want
	to rewrite, and none of them should need a diff of a layout file to find. ]]

--[[ THERE IS NO HEADER AND NO SKIP, and both were taken out at the same time because they were the
	same object: a coloured title bar across the top of the card carrying "GETTING STARTED 3/8" on
	the left and the word SKIP on the right.

	The header was a PROGRESS READOUT on a thing nobody is choosing to do. "3 of 8" is the right
	furniture for a quest log, where the count is the reward; on a card that interrupts a run it is
	one more line to read before the line that matters, and the objective under it already says
	everything the player can act on.

	SKIP went with the bar rather than moving somewhere else, and that is a real trade worth stating:
	three beats stop the world, and SKIP was the way out for somebody who could not make the input
	those beats ask for. What covers that now is `TutorialController`'s freeze timeout, which hands
	the game back on its own — a slower door, and one nobody presses by accident on the way past.

	The server end of the skip is untouched (`TutorialService`'s `TutorialSkip` remote and its funnel
	event); nothing on the client fires it. ]]

--- Stamped over the card when a beat completes, before the next one slides in. The beat exists so
--- that finishing an objective is a thing that HAPPENS rather than the card quietly changing.
TutorialConfig.DoneText = "DONE"

--- ...and what the last one says, once, before the card leaves for good. The board card's twelfth
--- item, in the game's own voice.
--- 2026-10-06 (Dylan): a congratulations now, fired with confetti (`FinishConfetti`), straight after
--- the first offer is answered. Was "THAT'S IT, HAVE FUN!" / "Steal a better car every run. The lot
--- pays while you drive."
TutorialConfig.FinishTitle = "TUTORIAL COMPLETE!"
TutorialConfig.FinishHint = "Steal, bank and park better cars to earn more tips!"

--[[ Screen confetti behind the finish card: the NEW BEST reveal's paper (`Modules/ScreenConfetti`,
	tuned in `ShowcaseConfig.Reveal.Confetti`) with a lighter burst, since this one goes off over the
	live lobby rather than a cutscene. It rains for `RainSeconds`, then the last pieces fall out. ]]
TutorialConfig.FinishConfetti = {
	Enabled = true,
	Burst = 45,
	RainPerSecond = 12,
	RainSeconds = 2.5,
}

--[[ Which side of the screen the card rests on when it has nothing to sit beside: "Left" or
	"Right". Left since 2026-10-06 (Leaf: "def on the left cuz this is annoying"); on the right it
	covered the road on the BOOST and GET AWAY WITH IT beats. It rests under Roblox's top bar either
	way, and above the kit's left rail, which starts at 30% of the screen height. ]]
TutorialConfig.CardSide = "Left"

--[[ The card's size on a TOUCH screen, as a multiple of the template's (2026-10-13, punch list M3:
	"tutorial looks shit", on a landscape phone). At 1 the card took a third of the screen's width
	and its meters ran down the left side. 0.72 is a taste call, not measured in the simulator yet:
	lower it if the card still crowds the road, raise it if the hint text gets too small to read.
	1 = the template's size, as before. Keyboard and gamepad are never scaled. ]]
TutorialConfig.TouchCardScale = 0.72

--- What the arrow says over a world target, `%s` being the formatted distance to it. Only drawn
--- while the target is off screen or far enough away to be worth walking to.
TutorialConfig.DistanceFormat = "%d studs"

--- The tally on a counted beat, appended to its hint. `%d` twice: done, and needed. Bracketed
--- because it is a counter rather than a sentence, and the board card writes it that way.
TutorialConfig.CountFormat = "  [%d/%d]"

--[[ WHICH KEY THE CARD NAMES, per device. Every `%s` in a beat's Title or Hint above is filled from
	here, in order, so the copy reads correctly on a keyboard, a stick and a phone without any beat
	knowing which of the three it is on.

	It is a lookup and not a string per beat because the beats do not vary by device and the KEYS do.
	`TutorialController._fill` picks the row and substitutes. ]]
TutorialConfig.Keys = {
	Keyboard = { Accelerate = "W", SteerLeft = "A", SteerRight = "D", Bail = "SPACE", Mount = "E" },
	Gamepad = { Accelerate = "RT", SteerLeft = "LEFT", SteerRight = "RIGHT", Bail = "A", Mount = "X" },
	Touch = { Accelerate = "GO", SteerLeft = "LEFT", SteerRight = "RIGHT", Bail = "JUMP", Mount = "STEAL" },
}

TutorialConfig.Timing = {
	--- How long the DONE stamp holds before the next objective arrives.
	DoneHold = 0.5,
	--- ...and the finish card, which nothing follows. Six (was 4) so the confetti has room to land.
	FinishHold = 6,
	--- The card's raise and drop, matching the WELCOME BACK panel's so the two feel like one game.
	Raise = 0.3,
	Drop = 0.2,
	--[[ A beat that arrives while the screen is busy waits this long before the card comes up: the
		race fade, the results screen and the WELCOME BACK panel all own the first moments after
		their own beat, and an objective sliding in underneath one is an objective nobody reads. ]]
	Settle = 1.2,

	--[[ ...and how long after the player is actually HOME before the card comes back up.

		A SIGNAL NOW, NOT A NUMBER, and that reversal is the whole of it. This used to be the only
		thing standing between a run ending and the card returning: eight seconds measured from
		`RaceEnd`, argued for on the grounds that being wrong costs a card a beat early or late and
		that keying off the results screen would be a dependency on the shape of its animation.

		Both halves of that were wrong. `RaceConfig.ReturnedEvent` is not the results animation's
		internals — it is a published contract meaning "a screen that was not an entry has finished
		lifting and the player is stood in their own lobby", and `CarryController` already waits on
		exactly it for exactly this reason. And the cost of being wrong was never a beat: the PLACE
		beat is served by a signal that fires at the BANK, which is `BankHoldTime + ReturnFadeTime`
		before the trip home even starts, so "PARK YOUR NEW CAR" was landing over the truck's closing
		doors while the player was still on the road.

		So this is the beat AFTER landing rather than the wait for it, and it is longer than the carry
		notice's own delay (`CarryConfig.Hint.Delay`, 0.4) on purpose. That card announces the car and
		this one says what to do with it, and they should arrive in that order rather than together. ]]
	ReturnSettle = 1.2,

	--[[ ...and how long after a run ends to give up waiting for that event and raise the card anyway.

		A FENCE, NOT A TIMER, and the same one `CarryConfig.Hint.Fallback` sets for the same wait.
		Every way home goes through the results screen and that screen drops itself after twelve
		seconds whatever happens (`RaceUIController`'s safety timeout), so nothing should reach this.
		What it buys is that a run which somehow ends with no screen leaves the player with a late
		objective rather than with none at all. ]]
	ReturnFallback = 14,
}

--[[ THE ARROW. There is no arrow art in the kit and none was uploaded for this — it is drawn from
	two triangles out of Roblox's own `rbxasset` set, tinted to the kit's brand blue, which is the
	same route `ReviveController` takes for the shapes the artist never drew.

	IT IS BIG ON PURPOSE. The board card asks for a "giant arrow" three times, and the reason it is
	right is that this pointer has to be findable by somebody who is not yet looking for it — a ring
	drawn around a button (which is what this feature used to do) is legible only once you have
	already found the button. ]]
TutorialConfig.Arrow = {
	--[[ Fraction of the screen's SHORTER side, so it is the same arrow in portrait and landscape.

		BIG. On a 620-pixel-tall window this is 99 pixels, which is a third again the height of the
		PLAY button it sits over — and that is the point: this pointer has to be findable by somebody
		who is not yet looking for it. The first pass at 0.11 measured 68 pixels against a 1187-wide
		screen and read as a decoration beside the card rather than as the thing to follow. ]]
	Size = 0.16,

	--- How far the tip sits from the thing it names, as a fraction of the arrow's own size. Enough
	--- that it reads as pointing AT rather than as sitting ON.
	Standoff = 0.35,

	--- The bob toward and away from the target: studs of travel as a fraction of the arrow's size,
	--- and the period of one cycle. Motion is what makes it findable in peripheral vision, which is
	--- the whole reason it moves rather than sitting still and being bigger.
	Bob = 0.22,
	BobPeriod = 0.9,

	--- ...and how long it takes to slide from one target to the next. The board card asks for the
	--- arrow to ANIMATE to the world button rather than cut, and this is that: one object that
	--- travels, so the player's eye is carried to the next press instead of having to find it.
	Travel = 0.45,
}

--[[ THE PULSE on whatever the arrow is naming. A scale breath rather than a glow, for the reason
	the rest of this game's effects are tuned to: small, physical, and cheap enough to run on a
	button that is already animating for its own reasons.

	`Scale` is the peak, so 1.06 is a six percent swell. Deliberately smaller than it sounds — the
	arrow is the thing doing the finding, and a button that pumps hard next to it reads as two
	things competing rather than one thing being named. ]]
TutorialConfig.Pulse = {
	Scale = 1.06,
	Period = 0.75,
}

--[[ THE DIM behind a frozen beat. Not a modal and not a vignette: one flat sheet at low opacity
	over the whole screen, under the card and the arrow and over everything else.

	WHY IT IS THERE AT ALL, given the world has already visibly stopped: a stopped world does not
	read as stopped in a screenshot, and a first-timer has no expectation of motion to notice the
	absence of. The dim is what says "this is a moment, not a hang" — and it is what makes the two
	things still moving, the card and the arrow, the two things you look at.

	`Opacity` is the sheet's alpha, `Fade` how long it takes either way. Kept well under half: any
	darker and the beat stops being a pause in the game and starts being a menu over it. ]]
TutorialConfig.Dim = {
	Enabled = true,
	Opacity = 0.42,
	Fade = 0.22,
}

return TutorialConfig
