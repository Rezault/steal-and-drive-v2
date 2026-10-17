--[[
	LegendConfig
	------------
	THE CONTROL LEGEND: a stack of "this button does that" rows in a corner of the screen, and the
	first answer this game has ever given to "what am I supposed to press".

	IT EXISTS BECAUSE OF A CONSOLE BUG (Trello, "Console: no on-screen button prompts or controls",
	reported by Drakeyym8). A pad could always DRIVE this game — `GamepadConfig`'s header lays out
	which button does what and every one of those bindings has been live since the day it was
	written — but a console player is handed the DESKTOP hud, which is a gauge cluster and nothing
	else. No keycaps, no glyphs, and no touch buttons either, because those are gated on
	`TouchEnabled`. The whole control scheme had to be guessed at eighty-five studs a second.

	SO THE LEGEND IS A READOUT, NOT A CONTROL. It binds nothing, sinks nothing, and is not `Active`
	— pressing it does nothing at all, on any device. That is the same contract the getaway
	countdown card and the tutorial card are on and it is load-bearing on a phone, where the corner
	it sits in is where thumbs live.

	=== WHY IT IS A MODULE, AND WHAT THE OTHER USES LOOK LIKE ==================================

	`Modules/ControlLegend` builds these; this file is the paint and the one list the driving screen
	asks for. Nothing about the module knows what a race is — it takes a corner, a title and a list
	of `{ label, keys }` and draws it — because the driving HUD is the first place that needs one
	and plainly not the last. The lobby has the same problem in miniature (nothing says X enters a
	car, or that the DPad opens the menu — `GamepadConfig.FocusKeys`), the tutorial teaches verbs
	one at a time and would rather show than tell, and the garage screens have their own.

	A caller that wants one writes a second entry list next to `LegendConfig.Driving` and passes it,
	rather than a second panel.

	=== THE KEYS ARE NOT DECLARED HERE, EXCEPT WHERE THEY HAVE TO BE ===========================

	Every row below pulls its `keys` straight out of the config that BINDS that key, so the legend
	cannot end up advertising a button that does nothing: nitro is `NitroConfig.Keys`, the indicators
	are `TurnSignalConfig.Keys`, the bail is `StealConfig.BailKeys`, the steal is
	`StealConfig.Prompt.Keys`. Change the binding and the legend follows it in the same commit.

	THE THREE THAT CANNOT DO THAT ARE THE STOCK CHASSIS'S OWN, and they are `Steer`, `Boost` and
	`Brake`. Those live in the CarBones `Keymap`, which is a place-side ModuleScript inside every
	car model (43 copies of it, not in git — see the standing note in `DriveConfig.ExitKeys`, which
	mirrors that same module's enter key for exactly this reason and says so at length). Mirroring
	three constants that have not moved since the kit shipped beats depending on a structure a
	redress or a fresh CarBones import can change. Verified against
	`Workspace.CarSystem.NewSports31.Scripts.Keymap` on 2026-08-25:

	    Keymap.SteerLeft/SteerRight   A / Left / Thumbstick1      (and D / Right)
	    Keymap.Throttle               W / Up / ButtonR2
	    Keymap.Brake                  S / Down / ButtonL2

	If a future kit rebinds any of them, this table and `DriveConfig.ExitKeys` are the two places to
	follow it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- `FirstPerson.ToggleKey`, for the camera row.
local CameraConfig = require(ReplicatedStorage.shared.Configs.CameraConfig)
local NitroConfig = require(ReplicatedStorage.shared.Configs.NitroConfig)
local StealConfig = require(ReplicatedStorage.shared.Configs.StealConfig)
local TurnSignalConfig = require(ReplicatedStorage.shared.Configs.TurnSignalConfig)

local LegendConfig = {}

--[[ The master A/B for every legend in the game. Off = `ControlLegend.new` hands back a live handle
	that builds nothing and whose methods are no-ops, so a caller never has to ask. ]]
LegendConfig.Enabled = true

--[[ === WHO SEES ONE =========================================================================

	A legend is worth screen space exactly when the controls are NOT already on the screen, which is
	a different answer on each of the three devices this game runs on:

	  • GAMEPAD — yes, and this is the bug. There is nothing else: no glyphs anywhere on the driving
	    screen and no touch buttons, because those are gated on `TouchEnabled` which a console is
	    not. See `DrivingHudController._applyTouchOnly`.

	  • TOUCH — no, and it would be actively wrong. The buttons ARE the legend on a phone: six of
	    them, drawn with the verb on the face, and they are laid out in precisely the two bottom
	    corners a legend would want. A seventh block of text there is clutter over the top of the
	    thing it is describing.

	  • KEYBOARD — YES since 2026-09-17, and this is the only one of the three that was ever a
	    judgement call rather than a fact. The argument for leaving it off was that a desktop player
	    is not stuck (WASD is the universal default and the throttle can be found by pressing
	    things) and that a permanent block of text on every desktop screen is a bigger change than
	    the console bug asked for. Dylan asked for it anyway, with a reference, and the second half
	    of that objection is answered by `ReturnSeconds`: the panel is not permanent on any device.
	    What a keyboard player genuinely cannot guess — LeftShift for the nitro, Space for the bail,
	    Q for the pickup — is three of the six rows.

	`ControlLegend` re-asks this every time the player's input device changes, so a pad picked up
	mid-race brings the legend in and putting it down takes it away — the same subscription the
	steal prompt swaps its keycap on (`GamepadInput.observePreferred`). ]]
LegendConfig.ShowFor = {
	Gamepad = true,
	Keyboard = true,
	Touch = false,
}

--[[ === THE PANEL ============================================================================

	SIZED IN SCALE ON BOTH AXES, like the getaway card beside it and for the reason that card's own
	note gives: the panel's aspect drifts a little with the viewport, which is tolerable for a
	glyph and a word and is NOT tolerable for the glyph itself — that carries its own
	`UIAspectRatioConstraint` and stays square at every aspect (see `Row.Glyph` below).

	No offset pixels anywhere in this file. The one exception is `StrokeThickness`, which is a
	hairline and is a hairline everywhere.

	=== WHICH BOX A FRACTION IS A FRACTION OF ==================================================

	Two spaces, and every number below says which one it is in. It is the same split
	`GetawayHudController` uses — the card is sized against the screen and everything inside it
	against the card — and getting it wrong is silent, so it is worth being explicit:

	    SCREEN   `Panel.Width` and `Panel.Margin` (of the screen's width / its two axes),
	             `Title.Height`, `Title.Gap` and `Row.Pitch` (of the screen's HEIGHT).
	    PARENT   everything else. `Panel.Padding` and `Panel.CornerRadius` are fractions of the
	             panel; `Row.Glyph`, `Row.Label` and `Cap` are fractions of the ROW they sit in.

	The vertical run is authored against the screen rather than against the panel because the panel
	does not have a height to be a fraction of — see the next paragraph.

	WIDTH AND HEIGHT ARE NOT BOTH FREE. `Height` is DERIVED from the row count by `ControlLegend`
	— padding, plus the title, plus N rows at `Row.Pitch` — so the panel is exactly as tall as what
	is in it, a five-row legend and a two-row one are the same design, and adding a row never means
	re-tuning a height by eye. Only `Width` is authored. ]]
LegendConfig.Panel = {
	--- Fraction of the screen's WIDTH. 0.17 held the legend clear of the gauge cluster when both
	--- were on the right-hand half; on the left it is simply the width the longest verb needs.
	Width = 0.17,

	--[[ The corner it hangs in, and the gap from the two screen edges it touches.

		BOTTOM LEFT SINCE 2026-09-17, and it was the bottom RIGHT. The speed readout moved into that
		corner (Dylan; `SpeedoConfig.Panel.Corner`) and the nitro readout is following it there, so
		the right-hand corner is spoken for and two panels cannot share it. The left is the better
		half of the bargain anyway: the only thing that has ever been drawn there is the pair of
		touch steering arrows, and this legend is never shown on a touch device.

		`Margin.X` is the getaway card's own 0.017, so the legend and the right-hand furniture are
		inset from their respective edges by the same amount; `Margin.Y` is a little more because
		the bottom edge of a television is the one most likely to be eaten by overscan.

		Anchored INTO its corner, so a margin is a gap from the edge at any viewport rather than a
		gap that grows with the panel. ]]
	Corner = "BottomLeft" :: "BottomRight" | "BottomLeft" | "TopRight" | "TopLeft",
	Margin = Vector2.new(0.017, 0.035),

	--[[ The in-race chrome language, and it is deliberately the getaway countdown card's exactly:
		same navy, same transparency, same border, same corner curve. The two are on the same screen
		at the same time on the right-hand side, and two panels an inch apart that disagree about
		their own colour read as two games.

		At 0.45 the road still shows through, which is what makes a block this size acceptable over
		live gameplay at all. ]]
	Color = Color3.fromRGB(20, 27, 45),
	Transparency = 0.45,
	StrokeColor = Color3.fromRGB(12, 18, 34),
	StrokeThickness = 2,
	--- A fraction of the panel's own WIDTH, so it is the same curve on a phone and on a monitor.
	--- (The getaway card takes its radius off its height; that card is a wide letterbox and this is
	--- a tall column, so "the short side" is a different axis for the two of them.)
	CornerRadius = 0.075,

	--- Fraction of the panel, inside the border, on every side.
	Padding = 0.05,
}

--[[ === THE TITLE ============================================================================

	One line above the rows saying what the block IS, because a bare stack of glyphs in a corner
	reads as decoration until something names it. `nil` for a legend that does not want one —
	`ControlLegend` then takes the row back rather than leaving a gap.

	CONTROLS and not "KEYBINDS" or "HOW TO PLAY": it is the word that is true on all three devices,
	and this module is meant to end up on more than the driving screen. ]]
LegendConfig.Title = {
	Text = "CONTROLS",
	--- Fractions of the SCREEN's height: the line itself, and the air under it before the first
	--- row. Both feed the derived panel height, which is why they are in the screen's space and not
	--- the panel's.
	Height = 0.032,
	Gap = 0.010,
	Color = Color3.fromRGB(158, 176, 204),
	--- The muted title against the rows' near-white is the kit's own hierarchy (`#7B85A9` secondary
	--- under `#FFFFFF` primary). The legend's rows are the content; this is the label on the tin.
	Transparency = 0,
}

--[[ === A ROW ================================================================================

	    [ glyph ]  LABEL

	The picture, then what it does, which is the shape every chip in this kit uses. Everything below
	is a fraction of the ROW rather than of the panel, which is what makes the layout survive a
	viewport that is much wider than it is tall: the glyph's box is bounded by the row's HEIGHT, so
	an ultrawide screen makes the column looser rather than making the glyph overflow its own row.
	See the `Glyph` note. ]]
LegendConfig.Row = {
	--[[ Fraction of the SCREEN's height, per row, the gap under it included. The panel's height is
		derived from this and the row count, so this is the one number that changes how tall a
		legend is — and, through the glyph's height-bounded box, how big the glyphs are.

		0.042 is 45px on a 1080p screen, which puts the glyph at 37 and lands it in the same family
		as `GamepadConfig.Icon.Size`'s 36 reference pixels. The two are the same drawing at the same
		size in two different places, which is what stops a legend glyph and a button badge reading
		as two different kits. ]]
	Pitch = 0.042,
	--- ...and how much of that pitch is the row itself rather than the gap under it.
	Fill = 0.86,

	--[[ THE GLYPH COLUMN. Width is a fraction of the ROW's width and height a fraction of the ROW's
		height, and the square is resolved by a `UIAspectRatioConstraint` inside that box — which
		takes the SMALLER of the two, so the glyph is height-bounded on a normal screen and
		width-bounded on nothing this game will ever run on. Never a zero-width box: the default
		`FitWithinMaxSize` collapses one of those to nothing rather than resolving it from the
		aspect (a trap this project has already paid for once).

		The stock controller art is drawn on a SQUARE canvas for every keycode we use — measured,
		not assumed: A, X, Y, B, L1, L2, R2, the DPad and Thumbstick1 are all 96x96, and the ink
		fills 96-100% of the width in every one. So one square column gives the round face buttons
		and the shoulder pills the same visual weight with no per-key special case. ]]
	Glyph = {
		Width = 0.22,
		Height = 0.95,
		--- Where the column's centre sits across the row.
		CentreX = 0.14,
	},

	--[[ The verb. Starts clear of the glyph column and runs to the row's right edge.

		UPPERCASE by convention rather than by `string.upper`, so a row that wants a mixed-case
		label can have one. ]]
	Label = {
		--[[ TWO LEFT EDGES, ONE PER DEVICE, and it is not a fudge. A pad glyph is a SQUARE and a
			keycap is a wide rectangle — SHIFT and SPACE are five letters — so a column wide enough
			for the cap leaves the glyph swimming in it, and a column tight to the glyph cannot hold
			the cap at all. The two are never on screen at once (a row draws one or the other), so
			the honest answer is for the label to start where whichever one is showing ends.
			`ControlLegend._dressRow` picks. ]]
		Left = 0.26,
		LeftKeyboard = 0.37,
		Right = 1,
		Height = 0.72,
		Color = Color3.fromRGB(238, 242, 255),
	},

	--[[ === A ROW THAT IS NOT AVAILABLE RIGHT NOW ============================================

		Some verbs are contextual — the steal only exists while you are in the air over a car worth
		taking — and a legend that lists one as though it were always there is teaching something
		false. `ControlLegend:setRowActive` dims a row to these instead of hiding it, because a row
		that comes and goes makes the rows under it JUMP, and a legend that reshuffles itself
		mid-corner is worse than one that is briefly greyed.

		Restrained on purpose. The dim has to read as "not now" at a glance without becoming a
		second thing on the screen that is animating.

		Both numbers are the OPACITY A DIMMED ROW KEEPS, as a fraction of what the legend as a whole
		is currently drawn at — so they multiply with the panel's own fade rather than overriding
		it, and a dimmed row on a legend that is half faded in is half of this. The GLYPH goes
		further down than the WORD on purpose: what is unavailable is the button, and the row still
		has to say which row it is. ]]
	Dim = {
		Glyph = 0.35,
		Label = 0.5,
		--- Seconds to cross-fade between the two states. Long enough not to blink, short enough
		--- that it has finished by the time a player has looked down at it.
		Fade = 0.18,
	},
}

--[[ === COMING AND GOING =====================================================================

	Seconds, and the three are three different pieces of news. In is quick because the legend arrives
	with the race and wants to be there by the time the player has finished looking at the road
	ahead. Out is quicker still, because by then the run is over and the results screen is coming.

	EXPIRE IS THE SLOW ONE, and it is slow precisely because nothing happened: a panel that blinks
	out on a timer reads as an event, and a player who catches it going will look around for what
	caused it. It has to drift. ]]
LegendConfig.Fade = {
	In = 0.3,
	Out = 0.2,
	Expire = 0.7,
}

--[[ HOW LONG THE LEGEND STAYS UP once shown, in seconds, or 0 to keep it up for as long as its
	owner wants it.

	IT GOES AWAY, BECAUSE A CONTROL LEGEND THAT NEVER LEAVES IS NOT THE CONVENTION. A persistent
	button strip is a MENU footer — it describes the screen you are looking at and it belongs to
	that screen. During gameplay the pattern everywhere is teach, then get out of the way, and
	prompt anything situational in context instead.

	THIS GAME ALREADY DOES THE SECOND HALF, which is what makes the first half safe: the steal — the
	one verb a player would need reminding of at the exact moment it matters — is drawn on the car
	you are flying over, with its own ButtonX glyph, by `StealController`'s prompt billboard. So
	what retires here is a teaching aid for four verbs that are held down continuously and learned
	in one go, not a reference someone will need mid-corner.

	12 SECONDS, and it is measured against reading rather than against a run: five rows is three or
	four seconds of reading, and this is a driving screen at eighty-five studs a second where those
	seconds have to be taken a glance at a time between gaps in traffic. Twelve is about three
	glances. It is deliberately NOT sized as a fraction of a run — a run can end in fifteen seconds
	or last two minutes, and the legend's job is over either way once it has been read.

	TWO THINGS RE-OPEN THE WINDOW, both in `ControlLegend`:

	  • A REVIVE, because a wreck hides the legend and the revive shows it again, and a fresh show
	    arms a fresh timer. That is the right answer rather than an accident of the plumbing: a
	    player who has just been wrecked and paid to carry on is a player who was getting something
	    wrong, and this is the cheapest thing that might tell them what.

	  • PLUGGING A PAD IN MID-RUN. Someone who connects a controller thirty seconds into a race has
	    at that moment become the person this whole feature is for, and a window that had already
	    closed on them would mean they never saw it at all. `ControlLegend.refresh` re-arms on the
	    false->true edge of the device test.

	0 puts it back to being up for the whole run. Worth trying if a playtest says twelve seconds was
	not enough — but the better fix for that is probably a way to ASK for it back (the DPad is the
	one input free during a race) rather than never taking it away. ]]
LegendConfig.HoldSeconds = 12

--[[ ...AND HOW LONG IT STAYS UP ON EVERY RACE AFTER THE FIRST ONE OF THE SESSION (Dylan, 2026-09-17).

	`HoldSeconds` is sized against READING a panel nobody has seen before. This is sized against
	RECOGNISING one: a player on their fourth run already knows the shape, already knows which row
	is which, and is looking for one line of it at most. Five seconds is a glance and a second
	glance, and it is short enough that a panel appearing at the start of every single race does not
	become furniture the player learns to look past.

	IT IS NOT ZERO, and that is the whole reason this constant exists rather than the legend simply
	retiring for good after one race. Two of the six rows are things a player forgets — Q is the
	only key in the game bound to a slot, and the bail is the one verb with a consequence — and a
	reminder that has to be earned by rejoining is not a reminder. 0 here does mean "never again
	after the first", if a playtest says the repeat is noise.

	The clock itself is `ControlLegend`'s; which of the two numbers a race gets is
	`DrivingHudController._show`, and it is one `setHold` with no counter behind it. ]]
LegendConfig.ReturnSeconds = 5

--[[ === WHAT THE DRIVING SCREEN SAYS =========================================================

	Five rows, in the order a run uses them: point the car, make it go, make it stop, the bottle,
	and the button the whole game is named after.

	`id` is what `ControlLegend:setRowActive` / `:setRowLabel` address a row by, so it is a stable
	string and not the label.

	`keys` is a MIXED list — the keyboard key and the pad button together — which is the shape every
	binding in this game is configured in (`StealConfig.Prompt.Keys` is `{ E, ButtonX }`) and the
	shape `GamepadInput.gamepadKeyIn` already knows how to read the controller half out of. The
	legend picks whichever half matches the device it is drawing for.

	`keyboard` overrides what the keycap SAYS when it is drawing the keyboard half, for the two
	cases where the key's own name is not what a player calls it ("LeftShift" is SHIFT) or where one
	row covers two keys (steering is A and D, and no single KeyCode means that).

	=== THE THROTTLE IS NOT ON THIS LIST, AND THAT IS NOT AN OVERSIGHT =========================

	`DriveConfig.AutoThrottle` is 1: the car drives itself forward the whole time and there is no
	"press to go". R2 is a BOOST on top of that cruise (`DriveConfig.AllowBoost`,
	`BoostSpeedScale`), so BOOST is what the row says. A row reading "ACCELERATE" would have a
	console player holding R2 from the line wondering why it changed so little.

	=== AND NEITHER IS EXIT ====================================================================

	`DriveConfig.ExitKeys` gives Y to the driver's seat, and `DriveController._holdSeat` latches the
	kit's own exit button hidden and swallows the key for the whole race so that nobody can climb
	out mid-run. Advertising a button that is deliberately dead would be advertising a bug. ]]
LegendConfig.Driving = {
	{
		id = "Steer",
		label = "STEER",
		--- Mirrored from the place-side `Keymap` — see the header. Thumbstick1 is the left stick,
		--- which is also the stick the engine drives a UI selection with; that collision is why the
		--- gamepad focus key stands down for the whole race (`GamepadConfig`).
		keys = { Enum.KeyCode.A, Enum.KeyCode.Thumbstick1 },
		keyboard = "A / D",
	},
	{
		id = "Boost",
		label = "BOOST",
		keys = { Enum.KeyCode.W, Enum.KeyCode.ButtonR2 },
		keyboard = "W",
	},
	{
		id = "Brake",
		label = "BRAKE",
		keys = { Enum.KeyCode.S, Enum.KeyCode.ButtonL2 },
		keyboard = "S",
	},
	{
		--[[ The indicators. Off the binding (`TurnSignalConfig.Keys`) like the nitro row, and the
			caption names both sides the way the steer row does, so a rebind redraws this without
			anyone remembering to. ]]
		id = "Signal",
		label = "SIGNAL",
		keys = TurnSignalConfig.Keys.Left,
		keyboard = TurnSignalConfig.Keys.Left[1].Name .. " / " .. TurnSignalConfig.Keys.Right[1].Name,
	},
	{
		--- Straight off the binding, so a retuned nitro key redraws this row without anyone
		--- remembering to. Today: LeftShift and the left bumper.
		id = "Nitro",
		label = "NITRO",
		keys = NitroConfig.Keys,
		keyboard = "SHIFT",
	},
	{
		--[[ ONE ROW FOR TWO VERBS, and they are never both available: you bail from the seat and
			you steal out of the air. It is the same bargain the HUD's own action button already
			makes — `DrivingHud.Controls.Jump` shows JUMP seated and STEAL airborne, swapped off
			`StealController:canSteal()` — so the legend and the button say the same thing at the
			same time because they are asking the same question.

			The row is seeded with the bail and `DrivingHudController` swaps it, which is why both
			halves are written out here rather than one being derived. ]]
		id = "Action",
		label = "BAIL",
		keys = StealConfig.BailKeys,
		keyboard = "SPACE",
	},
	{
		--[[ First person (2026-10-14, the owner: "add V to switch camera"). Off the binding, like the
			nitro row: V on a keyboard, the right stick's click on a pad (`FirstPerson.GamepadKey`). ]]
		id = "Camera",
		label = "CAMERA",
		keys = { CameraConfig.FirstPerson.ToggleKey, CameraConfig.FirstPerson.GamepadKey },
		keyboard = CameraConfig.FirstPerson.ToggleKey.Name,
	},
}

--- The other half of that row, applied by `DrivingHudController._syncLegendAction` the moment a
--- steal becomes possible. Same shape as an entry above, minus the `id` it is being written onto.
LegendConfig.DrivingSteal = {
	label = "STEAL",
	keys = StealConfig.Prompt.Keys,
	keyboard = "E",
}

--[[ === KEYCAPS: THE KEYBOARD HALF ===========================================================

	Only ever drawn when `ShowFor.Keyboard` is on, which today it is not — so this is the paint for
	a switch rather than for anything on screen. It is here and it is finished because the module is
	meant to be reused, and the lobby legend this file's header describes is a keyboard legend as
	much as a pad one.

	The cap is `StealController`'s own prompt keycap in a rectangle: the kit's accent fill with the
	letter knocked out of it in the panel's own navy, which is the one keycap shape this game
	already has.

	LEFT-ALIGNED RATHER THAN CENTRED ON THE GLYPH COLUMN, because it is much wider than that column
	and centring it on the same axis pushes its left edge off the row. It gets its own left inset
	and its own label edge (`Row.Label.LeftKeyboard`) instead. ]]
LegendConfig.Cap = {
	Color = Color3.fromRGB(238, 242, 255),
	TextColor = Color3.fromRGB(20, 27, 45),
	--- All four are fractions of the ROW: where the cap's left edge sits, how far across it runs,
	--- and how tall it is.
	Left = 0.03,
	Width = 0.30,
	Height = 0.68,

	--[[ ...AND HOW FAR A ONE-CHARACTER CAP RUNS INSTEAD, which is the reference's own arrangement
		(Dylan, 2026-09-17): W, S, A and D are squarish keys and SHIFT and SPACE are wide ones, the
		way they are on the keyboard being described.

		A single width for both was legible and read as six identical buttons with different letters
		printed on them — the cap stopped saying anything about the key. It is the LEFT edge that is
		shared, not the right, so the verb column still lines up and only the cap changes shape;
		`Row.Label.LeftKeyboard` is unaffected and stays measured against the WIDE cap, because the
		verbs have to agree with each other and not with whichever key is on their own row.

		Not literally square, and deliberately: a true square resolved against the row's height
		comes out at about a quarter of this and reads as a tick box rather than a key. This is the
		proportion a keycap actually has. ]]
	NarrowWidth = 0.15,
	--- How many characters still count as a narrow cap. One, so `A / D` (which is one row standing
	--- for two keys) keeps the wide cap it needs.
	NarrowUpTo = 1,
	--- Fraction of the cap's own HEIGHT, since `UICorner`'s scale is taken against the shorter side
	--- — so a wide cap and a narrow one wear the same curve.
	CornerRadius = 0.28,
}

--[[ Under everything the player has to ANSWER — the wreck banner, the revive question, the results
	— and under the getaway countdown card's 890, which is news where this is reference. Above the
	driving HUD's own 895 is deliberately NOT where this goes: it overlaps the pedals' corner on a
	touch device, and if a legend is ever turned on there it must lose that argument. ]]
LegendConfig.DisplayOrder = 888

return LegendConfig
