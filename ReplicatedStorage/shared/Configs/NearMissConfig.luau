--[[
	NearMissConfig
	--------------
	GETTING CLOSE TO A CAR AND GETTING AWAY WITH IT. What counts as one, what it pays, and what the
	screen says about it.

	The road already priced every way of getting a car WRONG — a clip costs HP (TrafficConfig.Clip),
	an obstacle costs more, a wreck costs three quarters of the run. Nothing priced getting one
	right. So a run had exactly one lever on it: drive further. This is the second: drive CLOSER.
	It is the whole reason to pick the gap between two cars over the empty lane beside them, and it
	is deliberately the only reward in the game you cannot buy, level up, or park.

	THREE TIERS, NAMED AFTER WHAT THEY ARE — the ladder every racing game has, in that game's own
	words:

	  • TRADING PAINT — you touched it, and it shrugged it off. The bottom rung, and the only one
	    that costs you something (a clip is still a clip: `TrafficConfig.Clip.Damage` takes HP for
	    it). Named rather than merely billed, because the rub IS the racing.
	  • NEAR MISS — close enough that you meant it.
	  • CLOSE CALL — close enough to make you flinch.

	The top two are one event at two gaps and the bottom one is a contact, so everything downstream —
	the cash, the word, how long the toast holds, how hard it punches — comes off which of the three
	it was. Exactly the shape a clip already has: one event with a severity.

	THE ORDER OF THAT LADDER IS THE WHOLE BALANCE, and it only holds because a rub pays LESS than a
	clean pass AND costs HP. Bumping a car is easier than shaving one; pay the two the same and the
	efficient way to earn would be to lean on the traffic, which is the opposite of the skill this is
	supposed to reward. `Cash.Paint = 0` turns the bottom rung into pure acknowledgement — the word
	with no money under it — and the toast handles that on its own.

	=== THE GEOMETRY, AND THE ONE STUD THAT ISN'T WHERE IT LOOKS ================================

	`Gap` is measured between the player's HITBOX and a traffic car's `Hit` volume, in the road's
	cross axis. Those two are NOT the same kind of box, and the difference is load-bearing:

	  • the player's HitBox is the CarBones chassis's narrow mid-height hull — 8.43 studs wide
	  • a traffic car's `Hit` is sized to the VISIBLE bodywork — 10.36 studs on the test body

	So a measured gap of 0 is not two cars touching: it is the hulls touching, by which point the
	visible panels have already overlapped by about a stud. Everything below is stated in the
	measured space (which is the space the code can actually work in), and reads about one stud
	tighter than it looks on screen. Lanes are 15 apart (ObstacleConfig.Lanes), so a car passed
	dead centre in the next lane measures 15 - 4.215 - 5.18 = 5.6 studs clear — that is the number
	the thresholds have to sit meaningfully under, or every ordinary overtake would pay.

	=== WHY THIS IS THE FIRST CLIENT-REPORTED CASH IN THE GAME ==================================

	It has to be. Traffic is client-local and always was (TrafficController's header) — there is no
	traffic car on the server to measure a gap against, and there cannot be one — so the only
	machine that can see a near miss is the one that made it. RewardService, whose whole boast is
	that it measures the distance itself and takes no numbers from anyone, now takes this one.

	`Guard` is what that costs and what bounds it, and the bound is the interesting part: the total
	bonus a run may pay is capped as a MULTIPLE OF ITS DISTANCE CASH, and distance is measured off
	the car by the server. So the exploit ceiling is tied to something the client cannot fake — you
	cannot farm this standing still, and a run that drives nowhere can claim nothing. The worst a
	liar gets is the run they actually drove, paid at `MaxBonusRatio` extra. See `Guard`.

	=== THE STREAK IS PRICED BY BOTH SIDES, FROM THIS FILE =====================================

	The toast has to name the cash the instant the cars are level — a round trip to be told what it
	was worth would land the number a tenth of a second after the moment it belongs to. So the
	client prices it for the screen and the server prices it for the bank, independently, out of the
	same two functions below (`nextStreak`, `cashFor`). That is only safe because the streak rule is a
	pure function of ONE input both sides have: the seconds since the last one.

	A CRASH IS INVISIBLE TO THE CHAIN, which is worth stating because the tempting reading is that it
	should end it. Two reasons it does not. One is mechanical: a hard clip is reported on a DIFFERENT
	channel, rate-limited server-side (TrafficConfig.ClipCooldown), so a crash-breaks-the-chain rule is
	one the two sides would eventually disagree about — and a screen that promises money the bank
	refuses is worse than a chain that survives a scrape. The other is that it needs no help: a crash
	takes a third of your HP and most of your speed, so the next near miss rarely arrives inside the
	window anyway. A LIGHT contact is not a crash and is a rung of this ladder in its own right (see
	`Paint` and the `Streak` note on why it keeps a chain without building it).

	The two can still differ, in exactly one direction: the server refuses reports the guards catch,
	and the results screen is the authority. An honest player never sees a difference.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ For ONE number: what the road already considers a contact the other car shrugged off. See
	`Paint`. This is the only thing this file reads from anywhere else, and it is a definition rather
	than a value — a rub is defined as "not a crash", and the road is where "a crash" is decided. ]]
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)

local BalanceConfig = require(script.Parent.BalanceConfig)
local NearMissConfig = {}

--[[ Master switch. Off = no detection, no toast, no bonus, and `RunSettled` carries a zero — the
	run pays for its distance exactly as it did before this existed. ]]
NearMissConfig.Enabled = true

-- === What counts ============================================================

--[[ Studs of daylight, hull to bodywork, at the closest point of the pass. See the header for why
	this space reads a stud tighter than the screen does.

	NEAR at 3.2 puts the bar at 2.4 studs off your own lane centre, toward the car — a lean, not a
	drift. CLOSE at 1.5 needs 4.1, which is better than a quarter of a lane and cannot be done by
	accident.

	CLOSE CALL AND TRADING PAINT ARE ADJACENT RUNGS, not overlapping ones, and what separates them is
	whether you actually brushed rather than a threshold. The clip poll charges from about half a stud
	inside this measurement (`TrafficConfig.Collision.ClipMargin`), and a pass whose narrowest moment is
	under a stud can go either way as the two cars move — measured both ways in a playtest at the same
	lane offset. A contact always wins (the clip is flagged before this is judged), so the pair is
	exhaustive and never double-pays: shave it and it is a close call, touch it and it is a rub.

	Raising NEAR much past 4 is the failure mode to know about. At 5.6 every centred overtake in the
	game pays, the toast never leaves the screen, and the word "near" stops meaning anything.

	`Floor` IS A WIRE CHECK, and it exists because the first version of `tierFor` did not have one:
	anything at or under `Close` was a close call, so a client sending "the gap was minus a hundred
	studs" got paid for it. It bought nothing extra — a close call is the top tier either way — but a
	measurement that is nonsense should be refused rather than priced, and that is what this is.

	A SLIGHTLY negative gap is genuinely reachable and still pays: the hulls can overlap by a fraction
	of a stud before the clip poll's sensor catches it, and this space reads a stud tighter than the
	bodywork anyway (see above). A full car-width of overlap is a car driven THROUGH another, which is
	what `TrafficConfig.Collision.Enabled = false` allows and which is not a near miss by any reading.
	-1 sits between the two. ]]
NearMissConfig.Gap = {
	Near = 3.2,
	Close = 1.5,
	Floor = -1,
}

--[[ Studs/s you must be closing on the car, along the road, for the pass to count as YOURS.

	Without it, sitting in the next lane at matched speed pays — and pays again every time the two
	of you drift a stud apart and back. With it, the reward is for OVERTAKING: a car that passes you
	because it is faster earns you nothing, which is the honest reading of whose driving that was.

	6 is the same floor `TrafficConfig.Knock.ScrapeSpeed` uses for the same reason (below it, two
	cars are travelling together rather than one going past the other), and it is comfortably under
	the ~8 studs/s a cruising player closes on the top rung at. ]]
NearMissConfig.MinPassSpeed = 6

--[[ …and the bottom rung, which is a CONTACT rather than a gap and is therefore measured in the one
	unit a contact has: the severity `TrafficController._severity` already works out from the closing
	speed between the two cars (0..1 across `TrafficConfig.Knock.ScrapeSpeed`..`FullSpeed`).

	`MaxSeverity` IS BORROWED FROM THE ROAD ON PURPOSE. `TrafficConfig.Knock.MinSeverity` is where
	this game decides whether a contact was a crash: under it the car you hit twitches, keeps its
	traction and drives on (a SCRAPE); over it, it is unanchored and handed to the physics engine and
	its run is over. Trading paint is therefore not a threshold of its own — it is exactly "the
	contact the other car shrugged off", and defining it by anything but that number would let the two
	drift until a hit that spun a car across two lanes was congratulated as a rub.

	Retuning `Knock.MinSeverity` moves this with it, which is the intent. (Read at load, like every
	other config value here, so a table edited live mid-playtest is not tracked.) Set a number here to
	break the tie if a rub should ever be tighter than a scrape — never looser. ]]
NearMissConfig.Paint = {
	MaxSeverity = TrafficConfig.Knock.MinSeverity,
}

-- === What it pays ===========================================================

--[[ Cash for one near miss, before the streak multiplies it.

	Sized against the thing it sits beside rather than against a feel. Distance pays 0.1/stud
	(RewardConfig.Distance), so a clean four-thousand-stud run is $400. Measured against the live
	road — twelve cars in a ~1,200-stud window, closing at ~25 studs/s from a cruise — a run like
	that passes roughly forty cars, of which a player who is actually threading traffic shaves maybe
	a dozen. At these two numbers and an average multiplier of ~1.4 that is $120ish: a real bump on
	top of the distance, and nowhere near enough to replace it.

	THAT ORDERING IS THE POINT, and it is the same argument RewardConfig makes about the car being
	the prize: distance is the floor, the car is the prize, and this is the skill on top. Double
	these and the fastest way to earn is to stop making progress and grind the traffic; halve them
	and nobody changes a line to collect it.

	`Paint` IS THE SMALLEST NUMBER IN THIS FILE, and it is sized against what a rub already COSTS
	rather than against the two above it: 5 HP at the very lightest (`TrafficConfig.Clip.Damage`), out
	of the 80-130 a car has. The HP bar is therefore what caps this, with no config guard needed — a
	dozen rubs is a wrecked car, and every one of them is HP that is no longer there for an obstacle.
	Two dollars on top of that is an acknowledgement with a coin taped to it, which is the right weight
	for the easy version of the thing this feature exists to reward. Zero is a perfectly good setting
	and leaves the word on its own. ]]
NearMissConfig.Cash = {
	Paint = 2,
	Near = 5,
	Close = 12,
	--[[ THREADING THE NEEDLE (see `Thread` below). Not a rung `tierFor` can return — priced by name, by
		both sides, from here. Paid ON TOP of the second pass's own near miss, so threading two near
		misses is 5 + 5 + 15 before the multiplier: roughly double what the same two cars pay passed
		separately, which is the right size for "the scariest gap on the road". ]]
	Thread = 15,
}

--[[ THREADING THE NEEDLE: two clean passes on OPPOSITE sides of you, inside `Window` seconds. That is
	the gap between two cars in the lanes either side — which is exactly what it looks like on screen.

	`Window` is client-side. At the ~25 studs/s you close on traffic, 0.45s is about eleven studs of
	stagger between the two cars — they are plainly "a gap", not "one car, then another".

	`ServerSlack` is added on the server's side only. The server times the two reports by when they
	ARRIVED, and network jitter can stretch a real 0.4s pair past 0.45 by the time it lands. A server
	that is slightly more generous than the toast means an honest player's thread is always paid; the
	opposite would mean a toast promising money the bank refuses.

	A thread CONSUMES the pair: the next pass starts a new one rather than threading with the second car
	again, so a slalom of alternating cars is one thread per two cars, not one per car. ]]
NearMissConfig.Thread = {
	Enabled = true,
	Window = 0.45,
	ServerSlack = 0.25,
}

--[[ THE PASS-BY. A positional whoosh played ON the car you just overtook, so it pans to the side the
	car went past on — the single most important sound in a traffic game.

	Every overtake inside `MaxGap` studs of daylight gets one, not just near misses, because the whoosh
	is how the road feels fast; the near-miss sound on top is what says you did it well. Pitch rises
	with closing speed between `MinClosing` and `FullClosing`.

	`Group` is a SoundService group name (see SoundController's header — blank ids are silent until an
	id lands). `RollOff*` are the Sound's own 3D distances. ]]
NearMissConfig.Whoosh = {
	Enabled = true,
	Group = "PassBy",
	MaxGap = 9,
	MinClosing = 10,
	FullClosing = 50,
	PitchMin = 0.95,
	PitchMax = 1.25,
	VolumeMin = 0.7,
	VolumeMax = 1.1,
	ChainPitchStep = 0.025,
	ChainPitchMax = 0.15,
	RollOffMinDistance = 8,
	RollOffMaxDistance = 120,
}

--[[ The chain. Near misses back to back are worth more than the same near misses spread out,
	because threading three cars in a row is a different act from shaving one and coasting.

	`Window` is the seconds a chain survives without a new near miss. 4 is about how long a lull
	between two cars in real traffic lasts at cruise — long enough that a deliberate second pass
	keeps the chain, short enough that an accidental one four seconds later does not inherit it.

	`Step` and `Max`: x1, x1.25, x1.5, x1.75, x2, and no further. Capped at two because this
	multiplies a payout that already scales with how MANY you made — leave it uncapped and the tail
	of a good run is worth more than the run, which is how a bonus quietly becomes the economy.

	TRADING PAINT KEEPS A CHAIN ALIVE AND DOES NOT ADVANCE IT (`nextStreak`'s third argument), which is
	the one rule in this file that had to be argued rather than measured. Advancing on a rub would make
	bumping cars the cheap route to x2 — easier than shaving them, and therefore the route people would
	take, which inverts the whole ladder. Resetting on a rub would mean a clean run of four ended by one
	graze, which is not how a driver would describe what just happened: rubbing is racing, and you are
	still in it. Keeping it is the reading that leaves both the fiction and the balance intact, and it
	is a rule both sides can apply from one input, which is what makes it safe to price twice. ]]
NearMissConfig.Streak = {
	Window = 4,
	Step = 0.25,
	Max = 2,
}

--[[ A persistent reading of the streak that already prices near misses. This creates no second
	economy and trusts no new client value: the server still derives every payout from the encounter
	reports above. Flow simply keeps the chain's timer and multiplier visible, and adds a restrained
	camera push while the player is driving cleanly. ]]
NearMissConfig.Flow = {
	Enabled = true,
	MinimumStreak = 2,
	CameraFov = 2.5,
	CameraRise = 8,
	CameraFall = 5,
	Position = Vector2.new(0.5, 0.105),
	Size = Vector2.new(0.22, 0.034),
	--- On TOUCH (2026-10-13, punch list M4): at 0.105 the bar sat on Roblox's top-bar buttons, which
	--- on a landscape phone run to y ~0.15 and x ~0.51, and 0.034 of a 390px screen is 13px of text.
	TouchPosition = Vector2.new(0.5, 0.2),
	TouchSize = Vector2.new(0.3, 0.05),

	--[[ THE KIT'S PROGRESS BAR, read out of `car ui (3).psd` at `Quest/Progress Bar copy` (the
		"Time Left" bar; `Index/Progress Bar copy` is the same bar in orange). It is flat colour with
		no texture, so it is rebuilt from Frames rather than cut from the uploaded `Page.Bar` art, which
		would need 9-slice maths at a HUD bar's height.

		The two ratios are the mockup's own geometry. It draws the bar 60px tall with a 27px corner
		radius, a 5px OUTSIDE stroke on the track, and the same 5px stroke round the label, so both
		strokes scale with the bar's rendered height rather than sitting at a pixel count. ]]
	TrackColor = Color3.fromRGB(35, 39, 53), -- #232735
	StrokeColor = Color3.fromRGB(21, 29, 45), -- #151D2D, the track's border and the label's outline
	TextColor = Color3.fromRGB(255, 255, 255),
	StrokeRatio = 5 / 60,
	CornerRatio = 27 / 60,

	--[[ The fill is the Quest bar's blue until the chain reaches `Streak.Max`, then the Index bar's
		orange. It STEPS rather than blends: blue and orange are opposites, so every point between
		them is a grey (x1.50 rendered sage green). The multiplier is written on the bar anyway, so the
		colour only has to say one thing, which is "maxed". ]]
	LowColor = Color3.fromRGB(0, 102, 255), -- #0066FF
	HighColor = Color3.fromRGB(255, 162, 0), -- #FFA200

	--[[ The "Kit" style's rims, as ScaledSize shares of the bar's height. The shelf's ProgressBar ships
		0.32 navy outside and 0.25 white inside, on the track AND the fill, which suits a page's fat bar
		but read heavy on a HUD strip (Dylan, 2026-10-17: "the outlines are too aggressive"). The fill
		keeps a hairline of navy so its end still parts cleanly from the grey. ]]
	KitRims = {
		TrackOuter = 0.16,
		TrackInner = 0.12,
		FillOuter = 0.06,
		FillInner = 0.14,
	},
}

--[[ What the server does with a number a client sent it. See the header for the whole argument;
	this is the shape of it.

	`MinInterval` is an anti-flood floor and NOT a cooldown, which is why it is 16 times shorter
	than `TrafficConfig.ClipCooldown`. Threading the gap between two cars in adjacent lanes is two
	genuine near misses on very nearly the same frame, and a cooldown long enough to be worth
	calling one would refuse the most skilful thing a player can do on this road. So the rate limit
	only stops a script sending hundreds a second, and the CAPS below do the actual work.

	`MaxPerRun` bounds the bookkeeping rather than the money — a run cannot legitimately produce
	250 of these — and `MaxBonusRatio` bounds the money against the one number on this screen the
	server measured for itself. At 2 the most a run can pay in bonus is twice its distance cash, so
	the ceiling on lying is "the run I actually drove, paid three times over" rather than "any
	number I like". An honest run lands nowhere near it: the arithmetic above puts a good one at
	about 0.3 of its distance cash, so this is a fence and not a budget. Applied at settle, once the
	distance is final, so nothing is ever refused mid-run and the toasts stay truthful. ]]
NearMissConfig.Guard = {
	MinInterval = 0.06,
	MaxPerRun = 250,
	MaxBonusRatio = 2,
}

-- === The toast ==============================================================

--[[ The one thing on the driving screen that says it happened.

	BUILT IN CODE, unlike the rest of the driving HUD (`StarterGui.DrivingHud`, `StarterGui.CarHud`
	and `StarterGui.CarHpBar` are authored in Studio, deliberately, so their layout can be nudged in
	the Explorer). This is the
	exception and it earns it: there is no mockup of a near-miss toast to import, it has no layout to
	nudge — it is one word and one number in a compact side callout — and every frame is animation,
	code either way. If art ever lands for it, this table is what it replaces.

	NO PANEL BEHIND IT, on purpose. Anything drawn on the road ahead during a race is something the
	player has to see through, and a navy pill in the middle of the screen at the exact moment they
	are threading traffic is the single worst place to put an opaque rectangle in this game. So it is
	text with an outline, which reads over tarmac, sky and a white car alike and occludes nothing. ]]
NearMissConfig.Ui = {
	Enabled = true,

	--[[ WHICH LOOK, for the toast AND the Flow bar (2026-10-17, Dylan: on a list of screens "not
		consistent with the new template"). Read once, when the screen is built.
		"Kit": the Cartoony Kit's. Fredoka type with the kit's navy ScaledSize outline, the money in the
		HUD cash's yellow-to-green ramp, and the Flow bar is the kit's own progress bar
		(`ArcadeKit.bar`), blue and then gold at the cap. Still no panel, for the reason below.
		"Classic": Ubuntu type with the viewport-resolved near-black outline below, and the Flow bar
		drawn from `NearMissConfig.Flow`'s colours. ]]
	Style = "Kit",

	--[[ Where it sits, in fractions of the screen. The gauge cluster owns the bottom and the road
		reading corridor owns the centre, so reward text lives in a compact upper-left lane. It is close
		enough to the action to register without covering the next traffic gap.

		HIGH AND SMALL ON PURPOSE. It sat lower and bigger and read as distracting — it was the
		thing your eye went to at the exact moment you were threading a gap, which is backwards for
		a reaction to something you did WELL. Up here it is over the horizon, clear of the car and
		the traffic ahead of it, and small enough to be caught in the corner of the eye and read
		without being looked AT. The per-tier scales below still do the severity work off this size,
		so a close call is still visibly bigger than a near miss — just from a quieter baseline. ]]
	-- Keep the road-reading corridor clear. Near-miss feedback owns the upper-left lane while speed
	-- trap results mirror it on the upper-right; simultaneous rewards therefore never stack.
	Position = Vector2.new(0.24, 0.22),
	Size = Vector2.new(0.21, 0.062),
	--- On TOUCH (2026-10-13, punch list M4): the luck panel's 240x74px floor at (16, 76) covers 0.19-0.385
	--- of a 390px phone's height on the left, right where this sat. Below it, still left of the road.
	TouchPosition = Vector2.new(0.24, 0.45),

	--[[ Colours. The tier is the COLOUR of the word, which is the fastest way to say which of the
		three this was without making the player read it: steel for trading paint, white for a near
		miss, the kit's gold for a close call — one step warmer and brighter per rung. The money is the
		kit's own money green (#0DB415, the same one the customer bubbles and the cash pill use), so
		cash is the same colour everywhere in the game. ]]
	PaintColor = Color3.fromRGB(158, 176, 204),
	NearColor = Color3.fromRGB(238, 242, 255),
	CloseColor = Color3.fromRGB(255, 205, 76),
	CashColor = Color3.fromRGB(13, 180, 21),
	StreakColor = Color3.fromRGB(255, 255, 255),
	OutlineColor = Color3.fromRGB(6, 8, 12),

	--[[ Thickness of that outline as a fraction of the VIEWPORT HEIGHT. `UIStroke.Thickness` is the
		one property on this toast with no scale form at all, so it is resolved from the camera when
		the toast is shown — same trick, same reason, as the results screen's spinner ring. ]]
	OutlineThickness = 0.003,

	--[[ The pop, and the one place the three tiers differ by more than a colour.

		A near miss springs to its own size and goes; a close call springs BIGGER and stays a beat
		longer. That is the whole severity language on this screen, and it is deliberately the
		restrained version of it — the effect-intensity note in this project is that a small reaction
		which varies by severity beats a big one that does not, and a toast that leaps 40% at every
		car you pass would be the loudest thing in a game about driving fast.

		TRADING PAINT IS THE QUIET END OF THAT SAME SCALE: a little under its own size, gone a beat
		sooner. It has to be, because unlike the other two it lands ON TOP of feedback the road is
		already giving for the same instant — a jolt, a puff of smoke, and an HP bar flashing — and a
		loud congratulation over the top of that reads as the game not being sure which of the two
		things just happened to you. ]]
	PopFrom = 0.86, -- scale it springs up from, every tier
	PopTime = 0.1,
	PaintScale = 0.84, -- ...and the scale each settles at
	NearScale = 0.92,
	CloseScale = 1,
	PaintHold = 0.25, -- seconds it holds before fading
	NearHold = 0.34,
	CloseHold = 0.48,
	FadeTime = 0.22,

	--[[ The outline's share of `FadeTime`: it is gone by this fraction of the way through, and the
		letters finish the fade on their own.

		Fading the two together is what made the outline LINGER. A UIStroke on text is drawn under the
		whole glyph, not only round it, so a half-transparent letter shows the dark stroke through its
		own face and turns grey; and a dark outline on a bright sky stays readable long after white
		letters have gone. Taking the outline out first leaves only faint white text at the end. ]]
	StrokeFade = 0.5,

	-- Fraction of the screen it drifts upward while fading. Tiny: this is the toast getting out of
	-- the way, not a thing flying off the screen.
	Rise = 0.022,

	--[[ SoundService group names, played through `SoundController`. BLANK IS FINE AND MEANS SILENT:
		the project's convention is that UI sounds live in the place with their ids left empty
		(SoundController's header), so create `SoundService.NearMiss` / `SoundService.CloseCall` with
		a blank-id Sound child each and they get audible the moment an id lands, with no code change.
		Set either to "" here to take the sound out entirely. ]]
	PaintSound = "TradingPaint",
	NearSound = "NearMiss",
	CloseSound = "CloseCall",

	-- Threading the needle. Same shape as the three rungs above.
	ThreadColor = Color3.fromRGB(255, 120, 220),
	ThreadScale = 1.05,
	ThreadHold = 0.55,
	ThreadSound = "ThreadNeedle",
}

--[[ The two words, and they are what the whole feature is called. Non-breaking spaces because
	every label on a screen in this project is `TextScaled`, and a TextScaled label would sooner
	break "NEAR MISS" onto a second line than pick a smaller font — see the note in
	RaceUIController, which is the only warning anyone gets about that. ]]
local NBSP = utf8.char(0xA0)
NearMissConfig.Labels = {
	Paint = "TRADING" .. NBSP .. "PAINT",
	Near = "NEAR" .. NBSP .. "MISS",
	Close = "CLOSE" .. NBSP .. "CALL",
	Thread = "THREAD" .. NBSP .. "THE" .. NBSP .. "NEEDLE",
}

-- === Derived ================================================================

--[[ Which tier an encounter with a traffic car was, or nil for one that was not any of them.

	ONE FUNCTION FOR BOTH KINDS, because there is one ladder. `severity` is a CONTACT — the number the
	road already measured for the clip — and it takes precedence when present; `gap` is a clean pass.
	Exactly one of the two is ever meaningful, and the caller knows which because it knows whether the
	cars touched.

	Called by the client with what it measured and by the server with what it was sent, so a report can
	never be a tier the road would not have produced. It is therefore also the whole of the wire
	validation: nil, a string, NaN, forty studs of daylight, minus a hundred, and a severity that says
	the other car was flung across two lanes all answer nil, and nil buys nothing.

	Note which way "malformed" points here. A clip prices garbage at the MAXIMUM (TrafficService),
	because the only exploitable direction there is downward; this pays garbage NOTHING, for exactly
	the mirrored reason. Same instinct, opposite default. ]]
function NearMissConfig.tierFor(gap: unknown, severity: unknown): string?
	if not NearMissConfig.Enabled then
		return nil
	end

	--[[ A CONTACT. Trading paint only, and only while the other car shrugged it off — over
		`Paint.MaxSeverity` the same event is a car being handed to the physics engine, which is a crash
		by this game's own definition and is not something to be congratulated for. ]]
	if severity ~= nil then
		if type(severity) ~= "number" or severity ~= severity then
			return nil
		end
		if severity < 0 or severity > NearMissConfig.Paint.MaxSeverity then
			return nil
		end
		return "Paint"
	end

	if type(gap) ~= "number" or gap ~= gap then
		return nil
	end
	if gap > NearMissConfig.Gap.Near or gap < NearMissConfig.Gap.Floor then
		return nil
	end
	return if gap <= NearMissConfig.Gap.Close then "Close" else "Near"
end

-- Does this tier BUILD the chain, or merely keep it alive? See the `Streak` header — trading paint is
-- the one that does not, and it is asked as a question about the tier so that both sides get the same
-- answer without either having to remember the rule.
function NearMissConfig.advancesStreak(tier: unknown): boolean
	return tier ~= "Paint"
end

--[[ The next number in a chain, given the last one, how long ago it was, and whether this one builds
	the chain or only keeps it alive (`advancesStreak`).

	Priced by both sides from this one function — see the header. `sinceLast` of nil is a fresh chain
	(nothing to continue), and anything past the window starts again at 1. A rub that arrives with no
	chain in hand starts one at 1 rather than at 0: it is still the first thing that happened. ]]
function NearMissConfig.nextStreak(previous: unknown, sinceLast: unknown, advances: boolean?): number
	local kept = if type(previous) == "number" and previous >= 1 and previous == previous then previous else 0
	if kept == 0 then
		return 1
	end
	if type(sinceLast) ~= "number" or sinceLast ~= sinceLast or sinceLast > NearMissConfig.Streak.Window then
		return 1
	end
	if advances == false then
		return kept
	end
	return kept + 1
end

--[[ Which side of the player a pass was on, off the wire: exactly 1 or -1, or nil for anything else.
	A missing or malformed side simply cannot thread; it still pays its own near miss. ]]
function NearMissConfig.sideOf(side: unknown): number?
	if side == 1 or side == -1 then
		return side :: number
	end
	return nil
end

--[[ Does this clean pass THREAD with the previous unconsumed one? `previousSide`/`side` are 1/-1,
	`sinceLast` is seconds between the two, and `slack` widens the window (the server passes
	`Thread.ServerSlack`; the client passes nothing). See `Thread`. ]]
function NearMissConfig.isThread(previousSide: unknown, side: unknown, sinceLast: unknown, slack: number?): boolean
	if not (NearMissConfig.Enabled and NearMissConfig.Thread.Enabled) then
		return false
	end
	local a, b = NearMissConfig.sideOf(previousSide), NearMissConfig.sideOf(side)
	if not (a and b) or a == b then
		return false
	end
	if type(sinceLast) ~= "number" or sinceLast ~= sinceLast or sinceLast < 0 then
		return false
	end
	return sinceLast <= NearMissConfig.Thread.Window + (slack or 0)
end

-- What a chain of this length multiplies a near miss by. 1 at the first one, so every call site can
-- apply it unconditionally.
function NearMissConfig.multiplierFor(streak: unknown): number
	if type(streak) ~= "number" or streak ~= streak or streak <= 1 then
		return 1
	end
	local cfg = NearMissConfig.Streak
	return math.min(1 + cfg.Step * (streak - 1), cfg.Max)
end

--[[ What one near miss is worth. Whole dollars, because every other number the player is shown is.

	Floored rather than rounded so the client's toast and the server's ledger cannot disagree by a
	dollar on a x1.25 — they are running the same arithmetic on the same integers, and floor is the
	only rounding that stays true when a caller adds them up in a different order. ]]
function NearMissConfig.cashFor(tier: unknown, streak: unknown, world: number?): number
	if not NearMissConfig.Enabled or type(tier) ~= "string" then
		return 0
	end
	local base = NearMissConfig.Cash[tier]
	if type(base) ~= "number" then
		return 0
	end
	return math.max(0, math.floor(base * BalanceConfig.roadValue(world) / BalanceConfig.NearMissCashDivisor * NearMissConfig.multiplierFor(streak)))
end

--[[ The run's bonus, fenced against what the run actually drove. `distanceCash` is the run's
	distance payout at full rate, which the server measured off the car it owns (RewardService).

	This is the guard that matters, and it is the reason the rest of them can be as loose as they
	are. See `Guard`. A run with no distance cash — one that never reached `MinStuds` — pays no
	bonus either, which is the same rule the distance payout already follows for the same reason:
	an entry that fell over before the car went live has nothing to be paid for. ]]
function NearMissConfig.cap(bonus: unknown, distanceCash: unknown): number
	if not NearMissConfig.Enabled or type(bonus) ~= "number" or bonus ~= bonus or bonus <= 0 then
		return 0
	end
	if type(distanceCash) ~= "number" or distanceCash ~= distanceCash or distanceCash <= 0 then
		return 0
	end
	return math.floor(math.min(bonus, distanceCash * NearMissConfig.Guard.MaxBonusRatio))
end

--[[ How the results screen names the tally. Plural-aware because "1 near misses" on the one screen a
	player reads at the end of every run is the kind of thing that gets noticed every time.

	NEAR MISSES AND CLOSE CALLS COUNT TOGETHER and rubs count separately, which is not an arbitrary
	split: the first two are the same achievement at two gaps, while a rub is the one you did NOT quite
	make, and rolling it in would have the line claim credit for contact. Splitting all three would be
	three numbers explaining one figure on a screen that is already four lines deep — and the player has
	just watched every one of them land individually.

	"rubs" rather than "traded paint" for the compact form, because the line has to fit on a phone and
	"3 traded paint" is not English. It is the same event the toast calls TRADING PAINT, in the same
	sport's other word for it. One string if it should read differently. ]]
function NearMissConfig.tallyLabel(count: unknown, paint: unknown): string?
	local clean = if type(count) == "number" and count == count then math.floor(count) else 0
	local rubs = if type(paint) == "number" and paint == paint then math.floor(paint) else 0
	if clean < 1 and rubs < 1 then
		return nil
	end

	local parts = {}
	if clean >= 1 then
		table.insert(parts, string.format("%d near %s", clean, if clean == 1 then "miss" else "misses"))
	end
	if rubs >= 1 then
		table.insert(parts, string.format("%d %s", rubs, if rubs == 1 then "rub" else "rubs"))
	end
	return table.concat(parts, " · ")
end

-- Approved economy balance, 2026-10-04.
NearMissConfig.Guard.MaxBonusRatio = 0.5

-- Collection feedback uses the existing pickup chime; chain pitch rises gently to a cap.
NearMissConfig.SkillSound = { Enabled = true, Group = "PickupCollect", PitchStep = 0.045, MaxPitch = 1.3, VolumeScale = 0.7 }

-- Presentation only; no changes to the streak timer, payout, or nitro reward.
NearMissConfig.CuttingFeedback = {
	Enabled = true,
	SoundPitchStep = 0.035,
	SoundPitchMax = 1.25,
	SoundVolume = 0.85,
	MilestoneGroup = "CuttingMilestone",
	MilestoneEvery = 5,
	ComboPopStep = 0.025,
	ComboPopMax = 1.15,
}

function NearMissConfig.feedbackFor(streak: number, advances: boolean)
	local cfg = NearMissConfig.CuttingFeedback
	local count = math.max(math.floor(streak), 0)
	return {
		Pitch = if advances then math.min(1 + math.max(count - 1, 0) * cfg.SoundPitchStep, cfg.SoundPitchMax) else 1,
		Pop = if advances then math.min(1 + math.max(count - 1, 0) * cfg.ComboPopStep, cfg.ComboPopMax) else 1,
		Milestone = cfg.Enabled and advances and count > 0 and count % cfg.MilestoneEvery == 0,
	}
end

return NearMissConfig


