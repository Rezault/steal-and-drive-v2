--[[
	GuideTrailConfig
	----------------
	THE LINE FROM A PLAYER HOLDING A CAR TO THE BAY IT GOES ON (2026-10-16, Aleafo: "The biggest
	drop in users rn is players placing the cars on the dealership ... lets do a arrow from the player
	directly to the bay. Like the one that guides players in other games").

	The funnel behind it: 299 players carried their first car and only 167 placed it, so 44% stopped
	at the one step that has no arrow. Everything else on the way to a parked car already had one: the
	pin over the lot (`PlotConfig.Marker`), the tutorial's chip, the glow on the decks. The glow is the
	weak link, because it only lights within `CarryConfig.Glow.Studs` and a gold wash on a deck is
	not something a first-timer reads as "walk here".

	=== TWO LOOKS, ONE SWITCH ==================================================================

	    Classic   one camera-facing beam from the player's waist to the bay, wearing a row of fat
	              chevrons that scroll towards it. Straight through walls, the way every simulator's
	              quest beam works: it says WHERE, and the player works out the route.
	    Modern    a strip of racing track painted on the floor along the route a person can actually
	              walk (`PathfindingService`): dark asphalt, red and white kerbs, gold chevrons
	              flowing along it, and a chequered finish line at the bay's edge. It says HOW.

	Both are built so one can be deleted without touching the other once the owner has picked:
	`Modules/GuideTrailClassic` and `Modules/GuideTrailModern` are the two looks, and
	`GuideTrailController` is the part that decides whether to draw and what at. The admin panel's
	Showroom tab swaps between them live, and can draw one with empty hands to look at it.

	=== WHAT IT POINTS AT ======================================================================

	The same bay the rest of the carry already names, by asking `CarryController` rather than walking
	the lot again: the nearest EMPTY showroom bay, or the CUSTOMIZE podium while the customize pointer
	is up, or the bay the tutorial's chip is over during the PLACE beat. An arrow at one bay and a chip
	over another is the one way this could make the step harder.

	No free bay, nothing drawn. A full lot is a veteran's lot, and the hotbar is where that car goes.
]]

local GuideTrailConfig = {}

--- Off = nothing is ever drawn and no path is ever computed.
GuideTrailConfig.Enabled = true

--[[ The look a player gets when Gamebeast has not said otherwise: "Modern", "Classic" or "Off". Since
	the A/B (`Remote` below) this is only the FALLBACK, for a client whose remote configs have not
	loaded or a game Gamebeast cannot reach, and it should stay equal to the base configuration's
	value so a player outside the experiment sees the same thing either way. The admin panel can
	override the look for one client (`GuideTrailController:setStyle`), which never reaches anybody
	else. ]]
GuideTrailConfig.Style = "Classic"

--[[ === THE A/B: EACH PLAYER'S LOOK COMES FROM GAMEBEAST (2026-10-16) =======================

	Dylan: "we will use gamebeast a/b experiment to see which is better modern or classic". The
	Gamebeast remote configuration "live" holds `GuideTrail.Style`, and the experiment
	"Guide trail: Modern vs Classic" sets it per player (half each, by a stable hash of the player).
	The client reads its own value (`GuideTrailController._observeRemote`), which already has the
	player's group applied, and the server stamps the same value on the first-car markers as
	`guideStyle` (`AnalyticsService._guideStyle`), so the 44% drop between FirstCarCarried and
	FirstCarPlaced can be read per look.

	SHIPPING THE WINNER: end the experiment on the dashboard, set `GuideTrail.Style` in "live" to it,
	and set `Style` above to match. Deleting the losing module is then safe (see the header).

	SHIPPED 2026-10-19: CLASSIC. Neither look moved the PLACE beat, and the tutorial now parks the
	first car for the player (`TutorialConfig.AutoPark`), so the trail only serves later carries.
	Dylan: "we can switch over to just classic". Experiment 65 is terminated and "live" says Classic,
	which matches `Style`. Modern is kept for the admin panel's Look pick; nobody else is served it.

	Studio playtests read Gamebeast's separate "studio" environment, which has no "live", so Studio
	always draws `Style` (and the server logs one "No Gamebeast config found" per first-car marker).
	`Path` starts with the configuration's name; renaming it on the dashboard breaks this. ]]
GuideTrailConfig.Remote = {
	Enabled = true,
	Path = { "live", "GuideTrail", "Style" },
}

--[[ Only until this profile has parked a car (`CarryConfig.Guide.ParkedBeforeAttribute`)?

	OFF, on the marker's argument rather than the hint's: a hint is a sentence and nobody needs it
	twice, while a line to the nearest empty bay is a waypoint, and a waypoint is not a lesson anybody
	outgrows. A player who does not want to park simply puts the car away (its hotbar slot), and
	empty hands take the line down with them. On = first-timers only. ]]
GuideTrailConfig.UntilFirstPark = false

--[[ Studs around the bay's own footprint inside which the line is taken down: the player is there,
	the prompt is up, the deck is glowing, and a stub of trail under their feet says nothing. ]]
GuideTrailConfig.ArriveStuds = 3

--[[ Beyond this many studs from the bay nothing is drawn. Further than that the player is on
	somebody else's lot or out on the plaza, the pin over their own roof is the waypoint, and a path
	would be computed through streets this client has not streamed. ]]
GuideTrailConfig.MaxStuds = 260

--- Seconds between re-picks of the bay. The same quarter second the glow rescans on.
GuideTrailConfig.Interval = 0.25

--[[ The bay the line is on keeps it unless another is this many studs nearer. Without it a player
	walking down the middle of the row would watch the line swap between two decks every step. The
	tutorial's `FOLLOW_MARGIN` is the same idea for the same row. ]]
GuideTrailConfig.SwitchMargin = 6

--[[ Seconds the whole line takes to come up and to go down. Short: it is a waypoint appearing, not
	an event, and a long fade on a line that follows you reads as lag. ]]
GuideTrailConfig.FadeIn = 0.3
GuideTrailConfig.FadeOut = 0.2

--[[ === A PERSON, NOT A BAY (2026-10-19) =====================================================

	The tutorial's SELL beat points this same line at its buyer once they are standing at the car,
	with empty hands (Dylan: "it guides you with classic guide arrow to the offer maybe can highlight
	the npc so they open the offer"). `TutorialController._stepGuide` hands the buyer's root to
	`GuideTrailController:pointAt`, and while it is set it wins over any bay.

	ALWAYS THE CLASSIC BEAM, whatever the look: Modern lays a track to a deck's edge, and a person
	has no deck. `Lift` is studs above their root the line ends at (the chest). Within `ArriveStuds`
	of them, measured flat, the line comes down; that is inside `BuyerConfig.Prompt.MaxDistance`, so
	their See Offer prompt is already on screen when it goes.

	`Arc` and `ArcMax` replace Classic's for this line, and are three times as tall on purpose. The
	tutorial's camera turn (`TutorialConfig.Look`) leaves the view looking straight down the line from
	behind the player, and at Classic's low arch the whole line hid behind their own body (seen in a
	playtest, 2026-10-19). Tall, it climbs over their head and drops on to the buyer. ]]
GuideTrailConfig.Person = {
	Lift = 0.5,
	ArriveStuds = 8,
	Arc = 0.3,
	ArcMax = 9,
}

-- === Classic ================================================================

GuideTrailConfig.Classic = {
	--[[ `assets/ui/guide/arrow_classic.png`: one white chevron with a navy keyline, pointing down the
		image, which on a Beam is towards Attachment1 (that script's header has the measurement). ]]
	Texture = "rbxassetid://129386131330976",

	--- Studs across. Thick enough to read from the top down lobby camera, thin enough not to hide
	--- the floor it crosses.
	Width = 2.8,
	--- Studs between one arrow and the next (one texture tile).
	Spacing = 2.6,
	--- Studs a second the arrows travel towards the bay. Walking pace is 16; under a third of it
	--- reads as flowing rather than racing past.
	Speed = 4.5,

	--[[ Light green at the player's end, full green at the bay's. GREEN since 2026-10-16 on the
		owner's feedback; it was gold, to match the bay's glow (`CarryConfig.Glow.Color`). Green is
		also what the lobby's own "go here" arrow over Play wears. Not white at the near end: white
		arrows on the lot's pale paving were measured on screen as barely there. ]]
	NearColor = Color3.fromRGB(130, 255, 110),
	FarColor = Color3.fromRGB(30, 210, 60),

	--- Studs below the root the line leaves from (the waist) and in front of it towards the bay,
	--- so it starts clear of the character instead of out of their chest.
	Drop = 1.1,
	Lead = 1.8,
	--- Studs above the deck's top the line ends at: where the car will stand, not inside the slab.
	EndLift = 1.6,

	--[[ How far the middle rises, as a share of the line's length, and the most it may rise. A
		gentle arch reads as thrown towards the bay; a straight line along the floor is hidden by
		every planter and step on the way. ]]
	Arc = 0.1,
	ArcMax = 6,

	--- Share of the length the line takes to fade in from the player's end, so it does not start
	--- with a hard edge at their waist.
	FadeStart = 0.12,
}

-- === Modern =================================================================

GuideTrailConfig.Modern = {
	--- All three are drawn running down the image, Attachment0 at the top (see `Classic.Texture`).
	Textures = {
		--- `assets/ui/guide/track_modern.png`: asphalt between red and white kerbs, one segment.
		Track = "rbxassetid://76576373474594",
		--- `assets/ui/guide/chevron_modern.png`: a white chevron with a speed streak, one segment.
		Chevron = "rbxassetid://76150595662055",
		--- `assets/ui/guide/finish_modern.png`: a chequered finish line, two rows by eight.
		Finish = "rbxassetid://97801727595684",
	},

	--- Studs across the track, kerbs included, and across the chevrons running down its middle.
	Width = 3.2,
	ChevronWidth = 2.3,
	--- Gold, the bay glow's own colour, so the line and the deck it ends at read as one thing.
	ChevronColor = Color3.fromRGB(255, 198, 0),

	--[[ Studs per segment, and so per kerb block and per chevron. The route is resampled to the
		nearest length that divides it exactly, so every segment is the same and no chevron is drawn
		squashed at the end. ]]
	Segment = 3,
	--- Studs a second the chevrons flow towards the bay.
	Speed = 7,

	--- Studs above the floor the strip is laid at. Just enough to clear the paving's own surface.
	Lift = 0.1,

	--- Studs in front of the player's feet over which the strip fades in.
	FadeStuds = 5,
	--- Studs a second the strip draws itself out towards the bay when it first appears.
	DrawSpeed = 140,

	--[[ The chequered line across the strip where it reaches the bay. Its length runs past the
		kerbs by `Overhang` a side, and `Depth` is how far it runs along the route. ]]
	Finish = true,
	FinishDepth = 1.1,
	FinishOverhang = 0.5,

	--[[ WHEN THE ROUTE IS WORKED OUT AGAIN. A path is computed when the bay changes, when the player
		strays more than `OffPath` studs from the line, and never more often than every `Recompute`
		seconds. A player who walks along it never triggers one: the strip is simply eaten from the
		near end as they go. ]]
	OffPath = 5,
	Recompute = 0.6,

	--- What the route is planned for: a character, not a car. Jumping on, because a lot has steps.
	Agent = {
		AgentRadius = 1.6,
		AgentHeight = 5,
		AgentCanJump = true,
		WaypointSpacing = 4,
	},

	--- Corner-cutting passes over the route before it is resampled. Each one rounds every bend a
	--- little more; two turns pathfinding's sharp elbows into curves a track would have.
	Smoothing = 2,
}

return GuideTrailConfig
