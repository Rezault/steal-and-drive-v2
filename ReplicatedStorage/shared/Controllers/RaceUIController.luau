--[[
	RaceUIController  (client)
	--------------------------
	The little transition/loading screen shown while entering a race. Clicking the "EnterRace"
	tag kicks off a short but perceptible chain on the server — clone the car, freeze it, seat
	the player, build the client road, hand ownership over, deploy the driver controls — so we
	cover that gap with a fade so the player can see the transition is happening.

	Driven by RaceService's remotes:
	  - RaceEntering  → raise the fade (black overlay + spinner + label) immediately.
	  - RaceLive      → the car is live and drivable → drop the fade.
	  - RaceReturning → raise it again on the way out of a wreck, so the teleport back to
	                    the lobby spawn happens off-screen. RaceLive follows and drops it.
	  - RaceEnd       → safety: drop the fade if it's somehow still up when a race ends.
	  - RaceAborted   → the entry gave up on us: the road never got built in time and the server
	                    has bounced us home rather than release the car into an empty world.

	A local safety timeout also drops the fade if RaceLive never arrives, so a hiccup on the
	server can never leave the player stuck behind a black screen.

	=== ON THE WAY IN, THE FADE IS A LOADING SCREEN =============================================

	The entry is not one wait, it is four — the server clones and rigs the car, the client builds its
	local road, the car and the world around it stream in, and the driving controls deploy — and on a
	phone the middle two are seconds, not frames. `THE LOADING BAR` below is those four steps drawn as
	a track with the same car glyph the results screen drives along its ladder, because they are the
	same picture of the same idea: how far along something is.

	IT IS THE OTHER HALF OF THE ENTRY FAIL-SAFE FIX. `RaceService._abortEntry` (read its note) stopped
	the server unanchoring a car into a world that had not loaded yet, and paid for that with a wait
	that is now allowed to run to `RaceConfig.EnterReadyTimeout` — ten seconds on the worst device we
	ship to. Ten seconds of a black screen and a spinner is indistinguishable from a hang, which is
	the thing players report as "it froze" and then close the game over. So the screen now says which
	of the four steps it is on, and shows a bar that only ever moves forward.

	NOTHING ON IT IS INVENTED. Every step boundary is a real event (`setLoadPhase`, pushed by
	`RoadController` as it reaches them) and the bar never crosses the step it is on — see
	`_loadTick`, which is careful about the one thing a loading bar must not do.

	AND IT ONLY APPEARS IF THE LOAD IS SLOW ENOUGH TO NEED IT (`LOAD_REVEAL`). A desktop client is
	driving about three quarters of a second after the click; a progress bar that flashed up and
	vanished inside that would make a fast entry feel slower than it is.

	THE RETURN FADE IS ALSO THE RESULTS SCREEN, and it is here rather than in a screen of its own
	because it is already the one moment a player is looking at nothing else. `RewardService` settles
	the run the instant it ends and fires `RunSettled` — well before `RaceReturning` raises this fade
	— so the numbers are in hand by the time there is somewhere to put them. What the player sees on
	the way home is what the run was worth, on the same overlay that is already covering the teleport.

	Deliberately text on the existing overlay rather than a new authored screen: the cash HUD is
	hidden during a race (`GarageConfig.Hud.HideDuringRace`), so without this the payout would land
	on a counter nobody was looking at, and the one beat where it is worth reading would show nothing.

	AND IT IS A BEAT, not a print. Once the fade has landed — and not before, see `BEAT_START` — the
	results are staged over about a second and a half: the bar wipes open, the payout counts up to
	itself and lands, the distance slides in under it, the near-miss tally follows it (the one line here
	that is skill rather than mileage — `NearMissConfig`, which also counts the cars you rubbed), and a
	level-up (rare, and the only line you had to bank a run to earn) punches in last. Then the screen holds for `RESULTS_HOLD_TIME` (or
	`BANK_HOLD_TIME`, when there's a car on it) so the finished numbers can be read rather than
	glimpsed.
	The whole effect is timing and a few percent of travel: this is the end of a two-minute run, not
	the end of a campaign, and it has to survive being seen thirty times an hour.

	=== AND ON A GETAWAY, THE CAR ITSELF =======================================================

	A banked run puts the stolen car above the headline, turning on the spot in a `ViewportFrame`
	over a slowly counter-turning sunburst. It is the one screen in the loop that answers "what did I
	just get?" with the thing itself rather than with its name, and it is the reason the headline
	reads STOLEN rather than "GOT AWAY" — the sentence is finished by the picture under it.

	THE CAR IS HANDED IN, NOT LOOKED UP. `GetawayController._bank` calls `setTrophy` at the instant
	the truck takes the car, which is the last moment the thing exists: `RaceService.bankRun` cuts the
	controls immediately and destroys the car a few seconds later, well before this screen goes up. So
	the model shown here is a stripped, anchored, re-centred CLONE of the live car's own `Body` —
	which means it carries the exact dress and the exact paint the player drove, with nothing having
	to be told what either was. There is no server round trip and no roster lookup, and there could
	not be one: `Workspace.CarSystem` is not streamed to clients at all.

	=== AND ON A WRECK, WHAT IS LEFT OF IT =====================================================

	A wreck used to get no car, on purpose: there was nothing to show, and the empty half of the
	screen was what the two endings were supposed to feel different by. The bust took most of that
	argument apart and this finishes it. The difference between two endings was never that one of
	them has a picture. It is what the picture is OF. A prize turns on a plinth under a burst of
	light; a wreck lies still in the dark with smoke coming off it.

	IT IS THE PLAYER'S OWN CAR, caught the way the trophy is caught. `ObstacleController._onWrecked`
	hands it in at the instant the run ends, on the same line that grows the plume on the real car,
	so the screen shows a wreck for exactly the endings the WORLD showed a wreck for and the two
	tests can never drift apart. Then it is DRESSED: dropped onto a hard cant, its nose folded in,
	its front wheels knocked under, and lit cold instead of warm. `THE WRECK` argues every one of
	those numbers, including the one that stops the car rolling far enough to show a floorpan these
	bodies do not have.

	AND THE PLUME IS DRAWN ON THE SCREEN RATHER THAN IN THE BOX, because a `ViewportFrame` renders
	no particles at all: no smoke, no fire, no sparks. That is the hard limit on this shot. So the
	smoke is a handful of `ImageLabel`s rising in front of the frame, on Roblox's own smoke texture,
	which is literally the same drawing the `Smoke` out on the road was made of. See `THE PLUME`.

	=== AND ON A BUST, THE LIGHTS ARE STILL GOING ==============================================

	A police bust is a wreck on every wire and is not one, and for a while the whole of that
	difference was one word. It now arrives on a screen with red and blue firing across it, easing
	off as the payout comes up so the numbers stay readable — the same lights the cruisers were
	running ten seconds earlier, on the same colours the chase vignette used, because they are
	supposed to be the same lights. `THE BUST LIGHTS` below has the construction and
	`PoliceConfig.Hud.Bust` has every number in it.

	AND THE CRUISER ITSELF STANDS IN THE SLOT THE STOLEN CAR WOULD HAVE. Same box, same viewport,
	same camera — held still at eye level rather than turning on a plinth, with no reward burst
	behind it, and with its own light bar flashing off the same clock as the wash at the edges of
	the frame. `THE CRUISER` is where the whole of that difference is argued and `_showBustCar`
	builds it. Three endings, one slot, and what is standing in it is the whole of what each one
	means.

	=== AND ON BOTH, HOW FAR UP THE LADDER IT GOT =============================================

	The divider between the headline and the numbers is a PROGRESS BAR: one tick per car in the
	world, and the car glyph driving along it to the rung the run reached. It is drawn for a wreck
	too — the run happened either way — and it measures TILES rather than metres, because that is the
	unit the game is actually built in. See `THE LADDER BAR` below for why the top rung is 100%.

	=== AND IT OFFERS ANOTHER ONE ==============================================================

	RACE AGAIN, on a kit pill under the numbers, in the world and the car the run was just driven in.
	It is the last thing the beat puts on the screen and it stands for `RaceConfig.Replay.Window`
	before the screen lifts onto the lobby the way it always did — a clock drawn as a drain along the
	bottom of the pill, never as a digit, which is the language the one other screen in this game
	that asks a question under time already speaks (`ReviveController`).

	IT DOES NOT MAKE THIS SCREEN MODAL. Doing nothing is still the way home and still costs no
	presses; what the button removes is the four presses and two screens it used to take to repeat a
	run the player had just decided they wanted to repeat. That is also why it can afford to be on a
	screen somebody sees thirty times an hour.

	AND A PRESS NEVER LIFTS THE BLACK. `_playReplay` takes the results off the overlay and holds the
	overlay itself, so the entry's own loading screen arrives on a screen that was already opaque and
	two runs in a row never flash the lobby between them. `REPLAY_PILL` has the drawing, `_playReplay`
	has the hand-over, and `RaceConfig.Replay` has both numbers.

	=== WITH THE NEW UI, THE RESULTS ARE READ ON A KIT PANEL ==================================

	With `UIRoot.isNewUI()` the results stop being type laid straight on the black and become the
	Cartoony Kit's `MatchLeaderboardUI`, authored by `BuildRaceResultsV2` on the hidden
	`MainUIV2.Screens` shelf and cloned onto this overlay. The headline goes in its header, the ladder
	in its pill strip, the car in a showcase card and the numbers in receipt rows; the fade, the
	spinner, the loading screen and the bust lights are untouched and are still this overlay's.
	`THE KIT PANEL` below has the rest. With the flag off, or `NewUIConfig.KitRaceResults` off (the
	shipping value), none of it is built and nothing above changes.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local AudioConfig = require(ReplicatedStorage.shared.Configs.AudioConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local NearMissConfig = require(ReplicatedStorage.shared.Configs.NearMissConfig)
--- For the one ending that names itself differently on this screen. See `_headline`.
local PoliceConfig = require(ReplicatedStorage.shared.Configs.PoliceConfig)
--- For the two events this screen tells anybody else about, `RevealedEvent` (an entry lifting) and
--- `ReturnedEvent` (everything else landing back in the lobby). Both are published in `_hide`. And,
--- since 2026-09-19, for the third one it SENDS: `ReplayEvent`, the RACE AGAIN press. See `Replay`.
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
--- For RACE AGAIN's controller binding: the modal flag the button raises while it is offered, so
--- the rail's own ButtonA stands down for the length of it. See `_bindReplayPad`.
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
--- Which UI is in use, and whether the results take the kit panel on it. See `THE KIT PANEL`.
local NewUIConfig = require(ReplicatedStorage.shared.Configs.NewUIConfig)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local RaceUIController = Shard.new("RaceUIController")

-- === Look & feel ============================================================
--[[ EVERY SIZE AND POSITION ON THIS SCREEN IS A SCALE, and every label is TextScaled.

	Nothing here is authored in the place — the whole screen is built below — so there is no PSD
	geometry to honour and no reason to pin anything to a pixel. It has to read the same on a phone
	held in portrait and on a 4K monitor, and the results beat is the one moment in the loop when
	the player is looking at nothing else.

	The one pixel number left is the spinner ring's UIStroke thickness, which has no scale form at
	all; it is driven off the viewport in the spin loop instead. ]]
local FADE_IN_TIME = 0.35 -- seconds to fade to black once entry begins
local FADE_OUT_TIME = 0.5 -- seconds to reveal the game once the car is live
--[[ Keep the screen up at least this long, so even an instant entry reads as a transition rather
	than a flicker. Raised from 0.4: with the world-ready gate below, a slow entry is now covered
	properly, and 0.4 was short enough that a fast one still flashed the whole screen up and off
	inside half a second — which looks like a bug in the screen rather than a quick load. ]]
local MIN_HOLD_TIME = 1

--[[ ...and this long when there are RESULTS on it. The beat below finishes at about 1.5s, so this
	leaves the finished numbers standing for a beat and a half more — long enough to read twice,
	short enough that it never becomes a screen you are waiting out.

	A FLOOR, NOT A TIMER. The fade still comes down on `RaceLive` and not before, so this can only
	ever hold a screen that was already up; it can't strand one that the server never released. ]]
local RESULTS_HOLD_TIME = 3.2

--[[ ...and longer again when the run BANKED, because that screen has something on it the crash
	screen hasn't: the car itself, turning. A wreck screen is a number and a headline and is read in
	one glance, but the trophy is the payoff for the whole run and wants looking at rather than
	noting. The extra two seconds are for the car, not for the numbers. ]]
local BANK_HOLD_TIME = RESULTS_HOLD_TIME + 2
local SAFETY_TIMEOUT = 12 -- drop the fade no matter what after this long
local OVERLAY_COLOR = Color3.fromRGB(8, 10, 14)

--[[ THE ENTRY BACKDROP: the road you are about to drive, behind the loading screen that covers you
	being put on it.

	IT IS THE SAME PICTURE THE TELEPORT CARD USES (`UIAssets.worldThumb`, keyed by map folder name
	via `WorldConfig.mapFor`) and deliberately not a new one. The player chose this world off that
	card a second ago; showing them the same photograph while it loads is what makes the entry read
	as going somewhere rather than as a pause. It also means a new world needs no new art here — it
	inherits the shot its card already has, and a map with no shot yet falls back to the same
	placeholder the card falls back to.

	ENTRY ONLY, NOT RESULTS. The results screen already has a subject — the car you banked, turning
	on a sunburst — and a photograph of a road behind that is two focal points fighting. `_show`
	clears it for anything that is not an entry.

	CROPPED, BECAUSE THE SOURCE IS PORTRAIT. The shots are 433x620 for a card slot; a screen is
	landscape. `Crop` fills the frame from the centre and loses the top and bottom, which is the
	right half to lose — the recipe in `UIAssets.Worlds` composes for the top 60% and leaves empty
	foreground road at the bottom.

	DIMMED TWICE OVER, and it needs to be. `Tint` multiplies the texture down and `Alpha` lets the
	overlay's near-black through it, because everything this screen exists to say — the destination,
	the step it is on, the bar — is text laid straight over this. A backdrop that competes with them
	has taken the screen back off the thing it is for. ]]
local BACKDROP_TINT = Color3.fromRGB(120, 128, 142)
local BACKDROP_ALPHA = 0.35
local ACCENT_COLOR = Color3.fromRGB(255, 255, 255)
local ENTER_LABEL = "Entering race…"
local RETURN_LABEL = "Heading back…"

--[[ What the return screen says instead, once there is a result to name. "Heading back…" is what the
	game is DOING; these are what just happened, which is the only one of the two worth a headline.

	"STOLEN" rather than "GOT AWAY" because the car is now ON this screen, turning above the word:
	the headline no longer has to carry the whole sentence, so it can be the one word that names what
	the picture is. It is also the verb the rest of the game is written in — the mechanic is the
	steal, and the truck is only how you keep it. ]]
local BANK_HEADLINE = "STOLEN"
local CRASH_HEADLINE = "WRECKED"
--[[ ...and the one ending that is a crash on every wire but this one. A police bust
	(`PoliceConfig.Cause`) settles exactly as a wreck does, pays exactly what a wreck pays and is
	drawn on exactly this screen; what it is not is a car that came apart, and calling it WRECKED
	over an undamaged car reads as the results screen not having noticed what just happened.

	The word is taken from `PoliceConfig` rather than typed, because the WRECKED banner during the
	beat says the same word and the two must never be able to disagree about it. ]]
local BUST_HEADLINE = PoliceConfig.BustedWord

-- The results lines under the headline. Green for a getaway, amber for a wreck — the two endings
-- pay differently (RewardConfig.Crash) and the colour is the fastest way to say which one this was.
local PAYOUT_COLOR = Color3.fromRGB(126, 217, 87)
local CRASH_COLOR = Color3.fromRGB(240, 178, 74)

--[[ TextScaled WRAPS RATHER THAN SHRINKS when a line is too wide for its box — it would sooner
	break "kept 25%" onto a second line than pick a smaller font. A non-breaking space is what
	actually stops it, so every space inside a results line is this one.

	DO NOT REACH FOR `TextWrapped = false` INSTEAD. It does not merely fail to help: writing it
	silently clears `TextScaled` (the two are one property under the hood), so the label drops to
	the default TextSize of 8 and the whole screen renders at a tenth of its intended size while
	every scale number in this file still reads correct. That is what it looks like when it
	happens, and this is the only warning you get. ]]
local NBSP = utf8.char(0xA0)
local DOT = NBSP .. NBSP .. "·" .. NBSP .. NBSP -- the separator on the crash line
--[[ THE 2X CASH PASS, SAID ON THE PAYOUT (2026-10-15, the owner: "at the end of a run make it obvious
	that the cash is being doubled if they own that gamepass"). The payout a pass owner sees IS the
	doubled figure (`RewardService` doubles it before sending), and a number that size with nothing
	on screen explaining it hides the one thing the purchase bought. So both results paths say so:
	"· 2x CASH" on the payout line, and on the kit panel a gold badge over the payout row as well.
	Only on a payout that exists (a "No payout" is not doubled into anything).

	ONE TABLE, NOT FOUR LOCALS, AND THAT IS LOAD-BEARING: this module's top level sits at Luau's
	200-local ceiling. The first cut added `PassConfig`, the text, the colour and the check as four
	locals, pushed it over, and the module failed to COMPILE, so `RaceUIController` never registered
	and runs began with no loading screen (2026-10-15). Add to this table, never a new local here. ]]
local DOUBLE = {
	text = "2x" .. NBSP .. "CASH",
	gold = Color3.fromRGB(255, 210, 60),
	--- Owns the pass, off the attribute `PassService` publishes (`PassConfig.ownedAttribute`).
	owns = function(): boolean
		local PassConfig = require(game:GetService("ReplicatedStorage").shared.Configs.PassConfig)
		return Players.LocalPlayer:GetAttribute(PassConfig.ownedAttribute("CashDouble")) == true
	end,
}

--- The heat bonus's stamp on the payout row (`_stampHeat`, `PoliceConfig.Heat`). `%s` is the multiplier.
local HEAT_PILL = {
	text = "★" .. NBSP .. "HEAT" .. NBSP .. "x%s",
	colour = Color3.fromRGB(235, 60, 60),
	ink = Color3.fromRGB(70, 0, 0),
	rotation = -8,
	from = 2.6, -- the stamp's size before it lands, as a scale of its resting size
	stampTime = 0.16,
	delay = 0.25, -- after the first count, before the stamp
	countTime = 0.6, -- the climb from the run's figure to the banked one
}

--- ...and the same treatment as a function, for the lines that are written somewhere else (the
--- loading copy below, a world's name) rather than assembled here.
local function oneLine(text: string): string
	return (string.gsub(text, " ", NBSP))
end

--[[ Where the results sit, all in fractions of the screen. `height` is what sets the font size,
	because a TextScaled label fills its box; `rest` is the transparency the line settles at, which
	is how the distance reads as the receipt under the payout rather than as a second headline. ]]
local RESULTS_TOP = 0.575 -- top edge of the first line; the block grows downward from here
local RESULTS_GAP = 0.014 -- between lines
local GEOMETRY = {
	cash = { width = 0.66, height = 0.058, rest = 0 },
	distance = { width = 0.46, height = 0.026, rest = 0.35 },
	--[[ The near-miss tally. Same HEIGHT as the distance above it, because it is the same KIND of line
		— a receipt for part of the number above — and one of them reading louder than the other would say
		the game valued them differently. Wider, though: it can carry two counts and a figure
		("7 near misses · 3 rubs  +$78") where the distance carries four words. ]]
	bonus = { width = 0.62, height = 0.026, rest = 0.35 },
	level = { width = 0.60, height = 0.034, rest = 0 },

	--[[ The two lines the LOADING screen owns, sized and shaped like the receipts above them so the
		two screens read as one family. They are in this table — and therefore built, reset and faded
		with everything else — but deliberately NOT in `ORDER`, which is the results stack: they are
		positioned by `_paintLoading` instead, and a results screen leaves them where every other paint
		leaves an unused line, which is invisible.

		Lighter type than the results lines, both of them, and that is the whole difference: a results
		line is a figure you earned and these are a caption and a hint. `_build` reads `font`.

		`minText` is a pixel floor (2026-10-06, Leaf on a phone: "all this feels a bit small to
		players on mobile"). A height of 0.024 is 26 px on a 1080p monitor and 9 px on a landscape
		phone, so the floor never binds on a desktop and lifts a phone to something readable. ]]
	status = { width = 0.62, height = 0.024, rest = 0.2, font = Enum.Font.GothamMedium, minText = 15 },
	tip = { width = 0.84, height = 0.021, rest = 0.5, font = Enum.Font.GothamMedium, minText = 13 },
}
--[[ Reading order, and therefore stacking order: what you earned, then the two things that made it,
	then what it bought. Distance comes before the near misses because it is the floor under every run
	and they are the skill on top — and because a run with no near misses in it must not leave a hole
	between the payout and its own distance. ]]
local ORDER = { "cash", "distance", "bonus", "level" }

--[[ THE BEAT. Staged rather than simultaneous, because the ORDER is the reading order: the payout
	lands, the distance explains it, and the level — which is rare, and the only line here you had
	to earn twice — arrives last and on its own. Nothing moves more than a few percent of the screen
	and nothing overshoots by more than a tenth; the whole effect is timing, not travel.

	NOTHING STARTS UNTIL THE SCREEN IS ACTUALLY BLACK, which is what `BEAT_START` is for and is worth
	spelling out, because the beat used to open the instant `_show` was called — i.e. on top of the
	`FADE_IN_TIME` fade, while the race was still showing through a half-transparent overlay. Every
	move that opens the beat was lost in there. The wipe below is the clearest case: 0.3s of
	Quad-out travel is 90% done a tenth of a second before the overlay finishes going opaque, so the
	one thing the player could actually see was a bar already at full width — the animation played,
	nobody ever watched it. The trophy's landing was going the same way. Offsetting the whole beat
	rather than re-timing the steps against each other keeps the ORDER, which is the part that was
	right all along.

	Numbers are seconds from the moment the fade lands. ]]
local BEAT_START = FADE_IN_TIME
local BEAT_TROPHY = BEAT_START + 0.05 -- the car lands first: it is the answer, and the numbers are the receipt
local BEAT_RULE = BEAT_START + 0.10 -- the bar wipes open, and the spinner bows out
local RULE_WIPE = 0.3 -- how long the track takes to open. See `BEAT_LADDER`: the car waits on it.
--[[ The car sets off along the bar the moment the track under it is fully open, never before: a car
	driving on a road still being laid reads as a timing bug even when it is deliberate. Its 0.58s of
	travel then lands ~0.98 after the black — a beat clear of the level-up. ]]
local BEAT_LADDER = BEAT_RULE + RULE_WIPE
local BEAT_CASH = BEAT_START + 0.18
local COUNT_TIME = 0.75 -- how long the payout takes to count up to itself
local BEAT_DISTANCE = BEAT_START + 0.65
--[[ The near-miss tally arrives a beat after the distance and slides in the same way — two receipts,
	one after the other, under a total that is still counting up to include them both.
	`BEAT_LEVEL` moved out to keep its old distance from whatever is above it: the level-up is the one
	line here that has to land on its own, and 0.19s after another line arriving is not on its own. ]]
local BEAT_BONUS = BEAT_START + 0.86
--[[ …and on a crash, the moment the split takes its share out of that tally, measured from when the
	line lands rather than from the start of the screen.

	0.7 is the 0.3s slide plus 0.4s of stillness, and the stillness is the point: the line has to be
	READ at the full figure before it moves, or the drop is just a number that was never there. Long
	enough for that, short enough that the count still finishes inside `RESULTS_HOLD_TIME` with room
	to read what it landed on (0.86 + 0.7 + 0.55 = 2.11 of 3.2).

	It cannot collide with the level-up at `BEAT_LEVEL`, and not by luck: a level-up is only awarded
	on a run you BANKED and a countdown only happens on one you crashed, so the two are mutually
	exclusive by construction. ]]
local BONUS_DROP_DELAY = 0.7
local BONUS_DROP_TIME = 0.55 -- slower than it looks: eased out, so most of the fall is in the first third
local BEAT_LEVEL = BEAT_START + 1.25

--[[ === RACE AGAIN: the button that ends the trip home before it starts =======================

	The results screen is the last thing between a finished run and the lobby, and for a player who
	liked the run it just reported it is also four presses and two screens short of letting them have
	another one. This is that trip as one button: same world, same car, straight back out.

	IT IS AN OFFER, NOT A GATE. Nothing about the screen's timing changes for a player who ignores it
	— the hold gets longer (see `REPLAY_WINDOW` below) and then the screen lifts onto the lobby the
	way it always has. That is the whole reason it can afford to be on a screen the player sees thirty
	times an hour: the default answer is still "do nothing", and it costs nothing to give.

	WHICH IS WHY IT CARRIES A CLOCK, drawn the way the one screen in this game that already asks a
	question under time draws its own (`ReviveController`, "THE CLOCK IS DRAWN, NOT COUNTED"): a strip
	along the bottom of the pill's face whose WIDTH is the fraction of the offer left, and no digit
	anywhere. Without it the button is a control that vanishes for no stated reason, which reads as
	the screen having taken something away. With it, the button is visibly closing and the player is
	never surprised by it going.

	AND IT IS THE KIT'S PILL IN THE KIT'S ACTION BLUE, which is the same face and the same colour
	PLAY wears in the lobby, because it is doing PLAY's job. The results lines above it are green or
	amber depending on how the run ended; the button deliberately takes neither — what it does next
	is the same whichever ending is being reported, and a button that changed colour with the news
	would read as being about the news.

	THE PRESS DOES NOT LIFT THE SCREEN. See `_playReplay`: the black is held and the entry's own
	loading screen takes it over, so two runs in a row never flash the lobby between them.

	NOT DRAWN ON THE KIT PANEL (`NewUIConfig.KitRaceResults`). That panel is the kit's
	`MatchLeaderboardUI` and it owns the middle of the screen including the room this button stands
	in; it needs a slot of its own authored in `BuildRaceResultsV2` rather than a pill dropped on top
	of it, and the shipping screen is the old one. `_replayable` is what fences that. ]]

--- Blue: the kit's action colour, and PLAY's. See the block above for why it is not the run's.
local REPLAY_PILL = UIAssets.Pill.Blue
local REPLAY_PILL_ASPECT = UIAssets.Size.Pill.X / UIAssets.Size.Pill.Y

--[[ The pill is authored as a HEIGHT with a WIDTH it may not exceed, and `_layoutReplay` takes
	whichever of the two comes out smaller — the same construction, and the same argument, as
	`ReviveController`'s two answers: the height is what makes a button the same physical size to a
	thumb on every screen, and the cap is what stops the width a height implies running off both sides
	of a phone held upright.

	SHORTER THAN THE REVIVE OFFER'S 0.155, because it is not asking for money and it is not the only
	thing on its screen. It is about the height of the two receipt lines and the gap between them put
	together, which is roughly what a secondary action should weigh against a total. ]]
local REPLAY_HEIGHT = 0.105
local REPLAY_WIDTH_MAX = 0.46

--[[ Hung from its BOTTOM EDGE rather than centred on a Y, for the reason the revive screen hangs
	its own block that way: the pill changes height with the viewport's aspect, and the edge a thumb
	cannot reach past is the one worth pinning.

	The deepest the results stack ever reaches is 0.761 (`RESULTS_TOP` plus four lines and their
	gaps), so at 16:9 this leaves about three percent of the screen between the last receipt and the
	top of the button. It clears by more on anything wider and the cap has taken the pill shorter by
	the time it would not. ]]
local REPLAY_BOTTOM = 0.90

--- Of the button, inside the art's own margins, and on the pill's FACE rather than its centre —
--- the drawing has a lip along the bottom. Both numbers are `ReviveController`'s, which solved the
--- same two words into the same shape.
local REPLAY_CAPTION_SIZE = UDim2.fromScale(0.74, 0.42)
local REPLAY_CAPTION_Y = 0.44

--- The hover nudge `Components/Button` puts on every tagged button, tuned down from its 1.05
--- default because the art already carries a hover of its own; and the press dip on top of it,
--- which is the one thing the art cannot do fast enough for a thumb.
local REPLAY_HOVER_SCALE = 1.03
local REPLAY_PRESS_SCALE = 0.97

--[[ The drain, and every number in it is `ReviveController`'s. Two screens a second and a half
	apart should not disagree about what a closing offer looks like, and the lane is inset rather than
	clipped for the reason that file gives: the pill's rounded caps are pixels, not geometry, so a bar
	run to the full width would poke over the curve. ]]
local REPLAY_DRAIN_WIDTH = 0.78 -- of the button, centred: clear of both cap curves
local REPLAY_DRAIN_HEIGHT = 0.075
local REPLAY_DRAIN_Y = 0.755 -- on the face, above the lip the pressed art drops into
local REPLAY_DRAIN_REST = 0.25
--- The lane the drain empties along, in the kit's card navy. Same colour the revive button's is.
local REPLAY_TRACK_COLOR = Color3.fromRGB(40, 51, 75)

--[[ LAST ON THE SCREEN, AND A BEAT CLEAR OF THE LINE ABOVE IT. `BEAT_LEVEL` is the one line here
	that has to land on its own, and a button sliding up underneath it while it is still settling
	would be exactly the crowding that beat is spaced to avoid. A quarter of a second is the same gap
	`BONUS_DROP_DELAY` uses for "read this before it moves".

	It is also the right order for a different reason: the button is what the player does ABOUT the
	screen, and it should not arrive before the screen has finished saying what it is about. ]]
local BEAT_REPLAY = BEAT_LEVEL + 0.25
local REPLAY_IN = 0.3 -- it slides up into place, the same move and the same time the receipts use
--- ...and how fast the results leave when it is pressed. Quicker than they arrived, because
--- nobody is reading them any more: the thing the player is waiting on is the next run.
local REPLAY_OUT = 0.22
local REPLAY_RISE = 0.022 -- ...from this far below, in screen scale. A nudge, like everything here.

--[[ How long the offer stands once it has arrived, and therefore how long the whole screen now
	holds: `_show` books `BEAT_REPLAY + REPLAY_WINDOW` as a floor, which is 5.85s against the 3.2s a
	wreck used to get and the 5.2s a bank did. `RaceConfig.Replay.Window` is where that is argued.

	THE DRAIN IS DRAWN FROM THIS, not from the hold `_hide` works out, and the two are the same
	number by construction rather than by agreement — `_hide` takes whichever of its own hold and the
	booked floor is further off, and this floor is further off than either. ]]
local REPLAY_WINDOW = RaceConfig.Replay.Window
local REPLAY_HOLD = BEAT_REPLAY + REPLAY_WINDOW

--[[ "RACE AGAIN", and the space in it is the same non-breaking one every other line on this screen
	uses. `TextScaled` WRAPS RATHER THAN SHRINKS (see `NBSP`'s own block above), and "RACE" over
	"AGAIN" inside a pill 3.89 times as wide as it is tall is the failure that looks like a font bug.

	TWO WORDS, IMPERATIVE, AND NOT "PLAY AGAIN". The verb this game is written in is the race: you
	enter a race, you wreck out of one, the screen above this button reports one. "Play" is what the
	lobby button says because from the lobby there is nothing else it could mean. ]]
local REPLAY_LABEL = "RACE" .. NBSP .. "AGAIN"
--- Ubuntu Bold, the kit's face — this is the one label on the screen that belongs to the kit's art
--- rather than to the screen's own Gotham type, because it is sitting on a kit button.
local REPLAY_FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--[[ === THE CONTROLLER'S ANSWER ==============================================================

	A, BOUND FOR AS LONG AS THE OFFER STANDS, and it is not a convenience: `Components/GamepadNav`
	only ever navigates inside `MainUI`, and this button is on a ScreenGui of its own, so without a
	binding a pad player cannot reach it AT ALL. The badge beside the pill is what says so.

	NO SELECTION IS SEEDED, for the reason `ReviveController` gives at its own pair: there is one
	answer, it never moves, and a clock is running. Binding the button outright is the same press
	with the step removed.

	WHICH IS WHY THE MODAL FLAG GOES UP WITH IT. `RaceEnd` has already put the rail back by the time
	the button lands (it fires at the top of the results hold, seconds before the screen moves), so
	the lobby's own navigation is live underneath this — and its highlight owns ButtonA. The
	attribute is what stops the two owning the same press; it comes down with the button.

	ABOVE `StealConfig.BindPriority`'s High + 500 on the same reasoning the revive screen is: nothing
	should still hold the bail by the time a run has finished being totalled up, and this is not the
	screen that wants to find out otherwise. It sits a step UNDER the revive question's High + 600,
	which cannot be live at the same time as this anyway — that screen is answered before this one is
	drawn — and the order is written down so a future overlap resolves the way a reader would guess. ]]
local PAD_REPLAY = "ResultsPadReplay"
local PAD_REPLAY_PRIORITY = Enum.ContextActionPriority.High.Value + 550
--- The gap between the pill's left edge and its badge, in screen scale. `ReviveController.ICON_GAP`
--- is the same number against the same art, and `_layoutReplay` turns it into a position.
local REPLAY_ICON_GAP = 0.02

--- Pills are addressed by id in `UIAssets` and wanted as urls here, three times per state.
local function pillAsset(id: number): string
	return "rbxassetid://" .. id
end

--[[ === THE LADDER BAR: how far up the tier ladder this run got ================================

	What used to be a plain divider is the run's PROGRESS THROUGH THE LADDER: a track with one tick
	per rung, a fill, and the car glyph riding it to the rung the run reached. Full width means the
	top car of the world was on the road; a third of the way along means you were still among the
	tier-3s when it ended.

	IT MEASURES TILES, NOT METRES, AND THAT IS THE WHOLE REASON IT IS WORTH DRAWING. Distance is
	already on this screen and reads as a number you can't place; the ladder is the same fact in the
	unit the game is actually built in — `TrafficConfig.Bands` unlocks each rung at a `FromTile`, so
	the top rung's tile IS 100%, and every tick is a car that came onto the road. The line above says
	how far you drove; this says what you got to see, and what you didn't.

	IT IS DRAWN FOR A WRECK TOO. The run happened either way, and on the ending that pays a quarter it
	is the one line on the screen that says the run was still worth something.

	Nothing here is fatal if it can't be worked out: with no segment length or no ladder in hand the
	whole thing degrades to the hairline divider it replaced, which is what `_planLadder` returning
	nil means downstream. ]]
local RULE_Y = 0.556 -- the bar, between the headline and the results. Low enough to leave the car room to stand on it.
local RULE_WIDTH = 0.28
local RULE_HEIGHT = 0.0045 -- the bare divider's thickness, and the track's when there is no ladder
local RULE_REST = 0.55

local TRACK_HEIGHT = 0.0075 -- the bar proper, thick enough to be a track rather than a rule
local TRACK_REST = 0.72 -- the unfilled remainder: present, but plainly not yet yours
local FILL_REST = 0.1

--[[ The rungs, as ticks across the track. A tick is a car joining the road, so they are drawn for
	EVERY rung including ones the run never reached — an empty stretch of track with three ticks left
	on it is the screen saying what is still up there, which a fill on its own cannot. ]]
local TICK_WIDTH = 0.0022 -- of the SCREEN, so a tick is the same weight whatever the ladder's length
local TICK_HEIGHT = 2.1 -- of the track's height, so they stand a little proud of it
local TICK_REACHED = 0.15 -- transparency of a rung the run got to...
local TICK_AHEAD = 0.72 -- ...and of one it did not

--[[ The car riding the track. Sized off its own height and held to the drawn glyph's aspect, so it
	is never squashed; `UIAssets.ResultsSize` is where that aspect comes from.

	IT SITS ON THE BAR RATHER THAN ON IT. Anchored at its own bottom edge against the track's TOP,
	so the wheels rest on the road — centred on the track instead, the line runs straight through
	the car's middle and it reads as a sliced sprite rather than as a car driving. ]]
local MARKER_HEIGHT = 0.03
local MARKER_Y = RULE_Y - TRACK_HEIGHT / 2
local MARKER_TRAVEL = 0.58 -- seconds from the start line to wherever the run ended

local SPINNER_Y = 0.40
local SPINNER_SIZE = 0.075 -- a square, held square by a UIAspectRatioConstraint
local SPINNER_THICKNESS = 0.005 -- of the viewport's height, resolved per frame in the spin loop
local HEADLINE_Y = 0.492
local HEADLINE_SIZE = UDim2.fromScale(0.8, 0.045)

--[[ === THE TROPHY: the stolen car, turning, over a sunburst ==================================

	It stands where the SPINNER stands, and takes its place rather than sitting beside it — a ring
	still turning next to a finished car would say "wait" at the exact moment there is nothing left
	to wait for, which is the same argument `_playResults` already makes for fading the ring out.

	SQUARE, AND SIZED OFF THE SHORTER SIDE, exactly like the spinner: `UIAspectRatioConstraint`
	defaults to fitting inside the authored box, so a square box in screen scales resolves to
	`TROPHY_SIZE x min(viewport)`. That is what keeps the car the same fraction of the view on a
	phone held in portrait and on a 4K monitor, and it is what lets the burst be sized as a plain
	multiple of it below and stay round. ]]
local TROPHY_Y = 0.30
local TROPHY_SIZE = 0.34
local TROPHY_RISE = 0.93 -- it lands from this fraction of its size, Back-eased. Restrained on purpose.

--[[ The burst, drawn rather than exported (`assets/ui/results/make_sunburst.py`, and see UIAssets).

	WHITE, and it was gold first. Gold is the kit's reward colour, but on this screen it made the
	burst a subject: a saturated hue behind a car that is itself painted a saturated hue left two
	things competing to be looked at, and the car lost about half the time (a red Supra inside a gold
	fan reads as one warm blob). White has no hue to compete with, so whatever colour the stolen car
	happens to be is the only colour in the top half of the screen — which is the correct thing for a
	screen whose whole job is to show you that car. It also stops the burst reading as a second
	payout next to the green cash line. ]]
local SUNBURST_SCALE = 1.32 -- of the trophy box, so it overspills the car and fades out just short of the headline
local SUNBURST_COLOR = Color3.fromRGB(255, 255, 255)
local SUNBURST_REST = 0.72 -- dimmer than the gold was: white on near-black carries much further
local SUNBURST_SPIN = -11 -- degrees/second, and NEGATIVE — see below

--[[ The car turns one way and the burst the other, which is the whole reason there are two numbers
	here instead of one. Turned together they read as a single flat sticker rotating; turned against
	each other the car reads as an object standing in front of something, and the parallax does the
	work a drop shadow would otherwise have to. The burst is also much the slower of the two: it is
	the backdrop, and a fast one turns a car being admired into a hazard light. ]]
local CAR_SPIN = 34 -- degrees/second about the car's own vertical axis
local CAR_PITCH = 15 -- degrees the camera sits above it: enough to read the roof, not a plan view
local CAR_YAW = 215 -- where the turn starts. 180 is nose-on, so this opens on a three-quarter front.
local CAR_FOV = 30 -- narrow, because a wide lens on a 20-stud car bends it into a caricature
local TROPHY_BUILD_BUDGET = 5 -- visual parts cloned/recentred per frame during the getaway hold
local RESULTS_PREP_DELAY = 0.35 -- let the trophy copy finish first, then prepare the cheap 2D layer
--[[ Under 1 because the fit below is computed for a BOX and a car is not one. The worst-case width a
	rotating 21x9.8 rectangle presents is its diagonal, but a car's corners are cut away, so framing
	honestly to the box leaves a tenth of the frame permanently empty and the car reading small inside
	its own burst. This is the amount of that slack worth taking back. ]]
local CAR_MARGIN = 0.94

--[[ === THE CRUISER: what a bust puts in the slot a getaway puts the stolen car in ===========

	The same box, the same viewport and the same camera, and everything about how it is FRAMED is
	different — because the two shots are opposite sentences. A getaway shows you a thing you now
	own. A bust shows you the thing that took it off you.

	IT DOES NOT TURN, and that is the first and biggest of the differences. A slow turntable is the
	language of a prize on a plinth: it exists so you can look at every side of something that is
	yours. Spinning the car that just arrested you says the game thinks you won it. So the cruiser
	is held at one angle and the only thing moving on it is its light bar, which is plenty — see
	`_stepLights`, which drives those lamps off the same clock as the wash at the screen's edges.

	AND IT IS SHOT AT EYE LEVEL RATHER THAN FROM ABOVE. `CAR_PITCH` looks 15 degrees DOWN at the
	stolen car, which is how you look at something on a table; four degrees is level with a car that
	has pulled up in front of you. Small number, most of the work.

	IT IS FOUR AND NOT MINUS FOUR, AND THAT WAS DECIDED BY A PHOTOGRAPH. Looking UP at it is the
	better idea and this art will not take it: the cruiser is one stylised MeshPart with no modelled
	underside, so a camera below the sill fills the bottom of the frame with a flat dark plane where
	a floorpan should be. Level is as low as this model goes, and a cruiser mesh with a belly on it
	could have the negative back.

	THERE IS NO SUNBURST BEHIND IT EITHER. The burst is the kit's reward flourish and a bust is not
	a reward; the flashing is the backdrop this shot already has. `_playResults` is where that is
	held off.

	`Margin` is far tighter than the banked car's for a plain geometric reason: `_frameDistance`
	reserves the worst case over a FULL TURN — the footprint's diagonal, 14.5 studs on a cruiser
	that is only 5.5 wide — because a turning car must not swell and shrink. Nothing here turns, so
	most of that is room the car never uses, and framing honestly to it leaves the cruiser stranded
	in the middle of its own box. This is the fraction a photograph says is actually needed at
	`BUST_CAR_YAW`: a number to re-measure rather than to reason about, if the model ever changes.

	AND IT IS NOT AS TIGHT AS IT LOOKS LIKE IT COULD BE, because a `ViewportFrame` CLIPS and the
	first pass at this got sheared. 0.63 put the nose a few pixels PAST the right-hand edge of the
	box, which reads as a rendering fault rather than as a crop.

	THE REASON IT OVERHANGS ON ONE SIDE IS PERSPECTIVE, and it is worth spelling out because the
	instinct is that a centred car cannot. The car is centred on its BOUNDING BOX and the camera
	looks at that centre, so a symmetric box projects symmetrically — but a car seen at
	three-quarters is not a symmetric silhouette, and at this framing the end nearest the lens is a
	third closer to it than the end away. That end projects larger. Measured off a still taken from
	far enough back to clip nothing, the silhouette sits about 4% of the box right of its centre and
	every pixel of the overhang is on that side.

	IT WAS ALSO MEASURED THAT WAY RATHER THAN COMPUTED, and it had to be. `_frameDistance` works on
	part BOXES, and a `MeshPart`'s box is not its mesh: the corners of this one — the roof's, the
	bumper's at full height and width — are empty air the car never reaches. Fitting honestly to
	them wants a distance near 50 and draws a cruiser lost in the middle of its own frame. The
	number below leaves about a seventh of the box clear on the near side, which is enough to read
	as a deliberate crop. ]]
local BUST_CAR_YAW = 157 -- three-quarter front: enough angle to read the length, enough nose to face you
local BUST_CAR_PITCH = 4 -- all but level. See above for why it is not the negative it wants to be.
local BUST_CAR_MARGIN = 0.76

--[[ === THE WRECK: your own car, and what is left of it ======================================

	The third thing this one slot can hold, and the only one of the three that is not shown to you
	intact. A getaway shows a car you now own. A bust shows the car that took it off you. This shows
	the car you had, in the state you left it in.

	NONE OF THE DAMAGE IS DAMAGE THE CAR TOOK. Roblox does not deform a mesh, so what is on this
	screen is a POSE: the same parts the player was driving, moved. That is worth saying out loud
	before tuning any of it, because it sets what the numbers can and cannot buy.

	THE OBVIOUS VERSION OF THIS SHOT IS A CAR ON ITS ROOF, AND THE ART WILL NOT TAKE IT. These
	bodies are open shells with no modelled underside, which is the same fact that makes
	`DoubleSided` load-bearing on every import. Rendered against the reference body: at 35 degrees
	the sill along the bottom of the car goes flat and dark, and by 55 a featureless plane fills a
	third of the frame where a floorpan should be. It stops reading as a wreck and starts reading as
	a rendering fault. `WRECK_ROLL` is therefore a cant rather than a flip, far enough over that the
	car is plainly not standing on its wheels and well short of where the geometry runs out. It is
	the same shape of limit `BUST_CAR_PITCH` is under, for the same reason, and a body with a
	floorpan on it could have the rest.

	THE CAMERA IS ON THE SIDE THE ROOF LEANS AWAY FROM, and that pairing IS the shot rather than a
	detail of it. The roll tips the car so its roof falls away from the lens and its flank swings
	round to face it, which is what puts the length of the car and the folded end in frame together.
	Flip the sign of `WRECK_ROLL` and you get the opposite picture, and it was the first pass at
	this: shot from the roof side, a wreck reads as a clean plan view of an undamaged car. So
	`WRECK_ROLL` and `WRECK_CAR_YAW` are one decision made twice. Change either and re-check the
	other.

	THE CRUMPLE IS FRONT-WEIGHTED AND APPLIED PER PART, and how much it shows depends on how the
	pack was cut. These Blender exports split either by MATERIAL (the reference body: one
	`body_paint` part carrying the whole shell) or by COMPONENT (a part per panel). On a
	material-split body the shell is one part sitting mid-car, so it barely moves, and what folds is
	the bumper, the lights and the plate, which are separate parts at the nose. That is the right
	picture for the wrong reason and it is worth keeping either way: a shell that buckled would need
	a second mesh rather than a transform, and a nose full of shoved-in hardware is what this shot
	wants regardless.

	NOTHING HERE IS FATAL IF IT CANNOT BE WORKED OUT. No wheel groups means no wheels splayed, and
	the shot is the cant and the crumple, which is the same graceful nothing `_planLadder` degrades
	to when there is no ladder to draw. ]]
local WRECK_CAR_YAW = 148 -- three-quarter front, from the side the roof leans away from. See above.
local WRECK_CAR_PITCH = 9 -- looking down on it, which is how you look at something on the ground
local WRECK_CAR_MARGIN = 0.8 -- as with the cruiser, a number to re-measure rather than to reason about
local WRECK_ROLL = 22 -- degrees over onto its left. The ceiling on this is the argument above.
local WRECK_NOSE_DOWN = 10 -- ...and down at the front, which is the end that took the hit

--[[ The fold. `From` is where along the car it starts (0 is the middle of the car, 1 the very tip of
	the nose) and everything past it is weighted by the SQUARE of how far past, so the damage
	concentrates at the front rather than spreading evenly down a car that only hit one thing. ]]
local WRECK_CRUSH_FROM = 0.18
local WRECK_CRUSH_DEPTH = 2.8 -- studs the nose is driven back into the car, at its worst
local WRECK_CRUSH_DROP = 0.8 -- ...and down, so the front end sits into itself rather than sliding back
local WRECK_CRUSH_TWIST = 13 -- degrees a panel is knocked out of true, at its worst
local WRECK_CRUSH_SCATTER = 0.5 -- studs of sideways knock, so the fold is never symmetrical

--[[ The front wheels, tucked under a corner that has collapsed.

	A WHEEL IS MOVED AS A GROUP, ABOUT ITS OWN CENTRE. `FL`/`FR`/`RL`/`RR` is the rigged bodies'
	own grouping (see the naming contract in `Modules/CarPaint`), and it is what makes this possible
	at all: a rim, a cap and a tyre each cambered about their own middles do not lean, they come
	apart into three rings at three angles.

	ALL 65 RIGGED BODIES IN `Workspace.CarSystem` GROUP THEM THIS WAY (counted 2026-09-03, no
	exceptions), so the fallback is a safety net rather than a live case: a body that did not would
	find no groups and get the cant and the crumple on their own. ]]
local WRECK_WHEELS = { FL = true, FR = true, RL = true, RR = true }
local WRECK_WHEEL_CAMBER = 34 -- degrees the top of the wheel tucks IN. Negative camber, taken too far.
local WRECK_WHEEL_SINK = 0.8 -- studs it drops into the arch, the suspension having given up


-- Lighting for the viewport, which has no relationship to the world's. Lifted ambient because the
-- alternative is a black silhouette: there is no sky and no bounce in a ViewportFrame, so anything
-- the key light misses is exactly as dark as it is left.
local CAR_AMBIENT = Color3.fromRGB(120, 126, 140)
local CAR_LIGHT = Color3.fromRGB(255, 250, 236)
local CAR_LIGHT_DIR = Vector3.new(-0.4, -1, -0.55).Unit

--[[ ...and the wreck is lit differently, which is the cheapest of the three shots' differences and
	does more work than any of the geometry. The trophy's key is warm and lifted because it is a
	showroom light on something being admired. This one is cold, dimmer, and comes from the other
	side, so the same car in the same box reads as a thing lying in the dark rather than a thing on
	a stand.

	IT IS ALSO THE ONLY WAY TO SAY "THIS PAINT IS NOT WHAT IT WAS" WITHOUT DESTROYING THE PAINT. The
	colour of these bodies is a TEXTURE rather than a `Color` (`Modules/CarPaint` has the long
	version), so sooting a panel down means clearing that texture, which throws away the one thing
	this shot exists to show. Light costs nothing and takes nothing away. ]]
local WRECK_AMBIENT = Color3.fromRGB(74, 78, 92)
local WRECK_LIGHT = Color3.fromRGB(186, 196, 216)
local WRECK_LIGHT_DIR = Vector3.new(0.35, -1, -0.25).Unit


--[[ Sounds for the two beats worth hearing. A blank id is a no-op, so either can be taken out with
	"". The payout is the same clip the garage's collect plays (`SoundService.CashCollect`), so money
	sounds like money everywhere; the level-up is a bright hit that is over in half a second, the
	flash that beat asks for. ]]
local PAYOUT_SOUND_ID = "rbxassetid://10066947742"
local LEVEL_SOUND_ID = "rbxassetid://134821092416328"

--[[ === THE LOADING BAR: the four steps of an entry ===========================================

	Same track, same ticks, same car glyph as the ladder bar above — one set of widgets, painted
	twice, because "how far along is this" is one picture and the game should only draw it one way.
	The ticks here are the STEPS rather than the rungs, and the fill is what has been done rather
	than what was driven.

	IT IS WHITE, and the results bar is green or amber. That is the only thing separating the two at
	a glance and it is deliberate: green and amber are the two ENDINGS (`PAYOUT_COLOR`,
	`CRASH_COLOR`), and a loading bar in either of them would be the screen announcing a result for a
	run that has not started. White is the same argument the sunburst makes a few constants up. ]]
local LOAD_COLOR = ACCENT_COLOR

-- What the headline says when the destination can't be named at all — a world whose config has no
-- map and no name. `_setDestination` normally puts the place itself here.
local ENTER_HEADLINE = "ENTERING RACE"

--[[ THE FOUR STEPS, in the order an entry reaches them, and the fraction of the bar each one owns.

	`to` is the step's ceiling — where the bar stands once that step is DONE — and the bar may not
	cross it while the step is still running (see `_loadTick`). So the ceilings are a claim about how
	long each step takes RELATIVE to the others and nothing more: getting one wrong makes the bar
	move at the wrong speed, it can never make it lie.

	Weighted off where the time actually goes on the device that needs this screen at all. The two
	client-side steps in the middle are much the biggest — the road is nine ~900-part tiles cloned in
	one go (`RaceConfig.DesiredSegmentCount`), and the stream is the step that puts Roblox's own
	"Gameplay Paused" dialog on a phone. The two server steps either side of them are frames.

	`tau` is how fast the bar approaches that ceiling: the seconds it takes to close about two thirds
	of whatever is left.

	AND IT IS SIZED OFF THE WORST CASE, NOT THE USUAL ONE, which is the opposite of the instinct and
	the whole reason these numbers were re-tuned. Measured with the road build stalled to the
	timeout, the first pass (tau 0.9 on a step that then took ten seconds) had the bar reach 0.519
	and sit there: from 5.5s to 10s it moved by one thousandth, which on a 341px bar is nothing at
	all. A bar that stops is worse than no bar — it says the game has hung, which is precisely the
	conclusion this screen exists to prevent, and it says it to the one player slow enough to see it.

	So the two client-side steps are paced to still be crawling at `RaceConfig.EnterReadyTimeout`,
	which is as long as this screen can ever be up. Same measurement, tau 3.5: 0.438 at five seconds
	and 0.501 at ten, i.e. still a good twenty pixels of travel over the stretch that used to be
	frozen. The cost is that a fast step hands over with the bar well short of its ceiling — which is
	what the snap in `setLoadPhase` is for. ]]
--[[ A FIFTH STEP WAS ADDED, and it is the one that made this screen honest again.

	`road` used to mean "the whole ring is cloned", because `_buildRoad` did that in one frame. It
	is now spread over a couple of seconds (`RoadController._startBuild`), and only the FIRST tile
	— the ground the ack needs — is down when `road` hands over. So the screen was reaching `live`,
	dropping, and revealing eight tiles still assembling: the entry was reported finished about two
	seconds before the world it was loading actually existed.

	`world` is that remainder, and it is gated on `RoadController:isWorldReady()` rather than on a
	timer, so it lasts exactly as long as the machine takes.

	IT SITS BEFORE `live`, AND THAT ORDER IS THE FIX RATHER THAN A DETAIL. `live` is the ack, and the
	ack unanchors the car — so a road still being laid at that point is a car already driving down
	it, behind a screen the player cannot see past. `RoadController` now waits for the ring before
	acking, so the true sequence really is "road finished, THEN engine starts", and these two are in
	the order the player experiences them. Putting `world` after `live` would also break the bar:
	`setLoadPhase` ignores any step whose index is not greater than the current one. ]]
local LOAD_PHASES = {
	{ key = "enter", label = "Getting your car ready…", to = 0.15, tau = 0.8 },
	{ key = "road", label = "Building the road…", to = 0.42, tau = 3.5 },
	{ key = "stream", label = "Loading the world in…", to = 0.68, tau = 4.5 },
	{ key = "world", label = "Laying the road ahead…", to = 0.88, tau = 2 },
	{ key = "live", label = "Starting the engine…", to = 0.97, tau = 1 },
}
local LOAD_DONE_LABEL = "Ready"
-- How hard the car chases a step that has just finished under it — see the floor in `setLoadPhase`.
-- Quick enough to read as catching up, slow enough to still be a car driving.
local LOAD_CATCHUP_TAU = 0.22

--[[ Two derived tables, so the phases stay one editable list. `LOAD_MARKS` is the ticks: the start
	line, then a tick where each step hands over, then the finish. The last step gets no tick of its
	own — it ends at the end of the track, which is already drawn. ]]
local LOAD_INDEX: { [string]: number } = {}
local LOAD_MARKS = { 0 }
for index, phase in LOAD_PHASES do
	LOAD_INDEX[phase.key] = index
	LOAD_MARKS[index + 1] = if index < #LOAD_PHASES then phase.to else 1
end

--[[ How long an entry has to be taking before the bar is worth drawing at all.

	A desktop client is driving inside a second, and a progress bar that appeared and completed
	inside that would make a fast entry feel SLOWER than it is — there is a whole genre of loading
	screen that exists only to be seen. So nothing but the fade, the spinner and the headline shows
	until here, and the screen a fast player sees is exactly the screen they saw before this feature
	existed.

	0.45 sits just past the fade landing (`FADE_IN_TIME` + the wipe), so the bar is never opening
	over an overlay that is still going black — the same argument `BEAT_START` makes for the results
	beat, and the same failure if it is ignored. ]]
local LOAD_REVEAL = 0.45
local LOAD_LAND = 0.4 -- ...and how long the screen then holds once it goes live, so the bar can arrive
local LOAD_LAND_TAU = 0.12 -- the bar's approach for that last run to 100%: fast, but still an approach

--[[ What the screen says when the entry gives up (`RaceService._abortEntry`), and how long it says
	it for.

	THIS IS THE ONE CASE THE PLAYER CANNOT WORK OUT FOR THEMSELVES. Every other way this screen ends
	puts them in a car. This one puts them back in the lobby holding nothing, and without a line
	saying why, the game has silently eaten a press of Play — which reads as the button being broken
	and gets pressed again immediately, on the same device that just failed to load in ten seconds.

	The hold is long by this screen's standards because it is text nobody is expecting to read, and
	it is measured from the ABORT rather than from the show (see `_holdFor`) — by the time this
	arrives the screen has been up for `RaceConfig.EnterReadyTimeout`, so every hold measured the
	usual way has long since elapsed. ]]
local ABORT_LABEL = "Couldn't load the world in time"
local ABORT_HINT = "You're back at the lobby. Try again"
local ABORT_HOLD = 2.6

--[[ Something to read while it loads, and the reason the tip line exists at all: on the device this
	screen was written for, this is up to ten seconds of the player's attention with nothing else in
	it.

	EVERY ONE IS SOMETHING THE GAME ACTUALLY DOES, and several restate the tutorial's own lessons
	(`TutorialConfig.Steps`) so a player who was taught it there meets the same idea here rather than
	a second, differently-phrased description of one mechanic. They are deliberately not copied
	verbatim: the tutorial's copy names a KEY, which differs by device and is filled in at draw time,
	and a loading screen has no player in front of it to know which. The crash split is formatted
	from `RewardConfig` rather than typed, because it is a number that has already been tuned twice.

	It sits low, well under the bar: it is the least important thing on the screen and the only one
	that is not about the race that is loading. ]]
local TIP_Y = 0.86
local TIPS = {
	"The gas is automatic. You just steer",
	"Pull alongside a car and JUMP to steal it",
	"Drive into the truck to keep your car",
	"Near misses pay. Cut it close",
	"Obstacles cost HP, so thread the gaps",
	string.format("Crash and you still keep %d%% of the run", math.round(RewardConfig.Crash.CashFraction * 100)),
	"Parked cars earn cash while you drive",
}

--[[ === THE BUST LIGHTS: the one ending that is still flashing when the numbers come up =======

	A police bust settles as a wreck, pays what a wreck pays and lands on this screen — and until
	now the only thing separating it from a wreck was one word (`BUST_HEADLINE`). This is the rest
	of it: red and blue firing across the black while the payout comes up, so the screen reports
	what actually happened rather than naming it.

	IT IS DRAWN ON THE HALF OF THE SCREEN A BUST LEFT EMPTY. A getaway put the stolen car above the
	headline, a bust had nothing to put there, and that emptiness was the difference the two endings
	were supposed to feel by. The lights took it and made it the point instead of leaving it a gap.
	Both of the other endings have since filled that half (`THE CRUISER`, `THE WRECK`), so the
	lights are no longer what a bust has instead of a picture. They are the room its picture is
	standing in.

	THREE ELEMENTS AND ONLY ONE OF THEM IS THE COLOUR YOU NOTICE. A band at each edge — each falling
	off inward through a `UIGradient` so it reads as light spilling in from off screen rather than as
	a coloured border — and behind them a wash across the whole frame that takes whichever colour is
	currently lit. The wash is the element that turns two bars into a room with something flashing
	in it, and it is kept to about a tenth of a screen's worth of tint for exactly that reason;
	`PoliceConfig.Hud.Bust.Flood` has the long version.

	BLUE IS ON THE LEFT AND RED ON THE RIGHT, WHICH IS NOT ARBITRARY AND IS NOT THE OBVIOUS WAY
	ROUND. It is the arrangement of the light bar on the cruiser standing between them. The mesh is
	painted red on its own left and blue on its own right (`PoliceConfig.Cruisers.Bar`), and a car
	FACING you presents its left on your right — so from the one angle this screen ever shows it,
	red is on the right of the frame. Drawn the other way the wash and the bar flash opposite sides
	on the same beat, which nobody could name but which is the difference between one light bar and
	two arguing ones.

	THE PATTERN AND THE CLOCK ARE NOT HERE. `PoliceConfig.bustFlash` owns both, because this is the
	third place in the game that flashes red and blue (the cruisers' own light bars and the chase
	vignette are the other two) and three files inventing three timings is three lights that
	disagree about being the same lights. The colours come off `Hud.Vignette` for the same reason.

	UNDER EVERYTHING, at `ZIndex` 0. The words and the numbers are what this screen is for; the
	lights are what it is happening in. ]]
function RaceUIController._buildLights(self, overlay: Frame)
	local cfg = PoliceConfig.Hud.Bust
	if not cfg.Enabled then
		return
	end
	local tint = PoliceConfig.Hud.Vignette

	local holder = Instance.new("Frame")
	holder.Name = "BustLights"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ZIndex = 0
	holder.Parent = overlay

	--- The wash. One frame recoloured on the flash rather than a red one and a blue one stacked:
	--- only ever one side is lit, so the second frame would be a full-screen quad drawn invisible
	--- every frame of a beat that runs on phones.
	local flood = Instance.new("Frame")
	flood.Name = "Flood"
	flood.Size = UDim2.fromScale(1, 1)
	flood.BackgroundColor3 = tint.Red
	flood.BackgroundTransparency = 1
	flood.BorderSizePixel = 0
	flood.ZIndex = 0
	flood.Parent = holder

	--[[ Opaque at the screen edge and gone before the middle — the chase vignette's own falloff,
		copied deliberately rather than shared, because these two washes are allowed to be tuned
		apart (that one is drawn over a road being driven on and this one over nothing at all).

		ONLY THE TRANSPARENCY MOVES. A `UIGradient` MULTIPLIES the fill colour, so a ramp that
		darkened toward one end would take the red straight out of a red tint. ]]
	local falloff = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.45, 0.62),
		NumberSequenceKeypoint.new(1, 1),
	})

	--[[ `rot` IS THE DIRECTION THE RAMP RUNS, and it has to run INTO the screen from that band's
		own edge: a `UIGradient` puts its offset 0 at the side its rotation points away from, and
		Rotation 0 is left-to-right. Get it backwards and the bands draw solid along their INNER
		edges, which renders as two slabs across the middle of the screen. ]]
	local bands = {}
	for _, side in {
		{ name = "Left", anchor = Vector2.new(0, 0.5), rot = 0, red = false },
		{ name = "Right", anchor = Vector2.new(1, 0.5), rot = 180, red = true },
	} do
		local band = Instance.new("Frame")
		band.Name = side.name
		band.AnchorPoint = side.anchor
		band.Position = UDim2.fromScale(side.anchor.X, side.anchor.Y)
		band.Size = UDim2.fromScale(cfg.Reach, 1)
		band.BackgroundColor3 = if side.red then tint.Red else tint.Blue
		band.BackgroundTransparency = 1
		band.BorderSizePixel = 0
		band.ZIndex = 1
		band.Parent = holder

		local ramp = Instance.new("UIGradient")
		ramp.Rotation = side.rot
		ramp.Transparency = falloff
		ramp.Parent = band

		table.insert(bands, { frame = band, red = side.red })
	end

	self._bustFlood = flood
	self._bustBands = bands
end

--- One frame of the wash at one strength. A file local rather than a closure inside the step
--- below, which runs every rendered frame of every bust screen; and clamped, so a `Gain` that
--- pushes a side past what an alpha can express saturates instead of wrapping a transparency
--- negative.
local function paint(frame: Frame, lit: number, scale: number)
	frame.BackgroundTransparency = 1 - math.clamp(lit * scale, 0, 1)
end

--- Put the lights out. Called by every `_show`, so a screen that is not a bust can never inherit
--- the last one's — the same argument `_paintPayout` makes for resetting the lines it is about to
--- draw on, and the same reason it is done by whoever is about to use them.
function RaceUIController._clearLights(self)
	if not self._bustBands then
		return
	end
	for _, band in self._bustBands do
		band.frame.BackgroundTransparency = 1
	end
	self._bustFlood.BackgroundTransparency = 1
end

--[[ One frame of them. `t` is seconds since the screen went black and `alpha` is the screen's own
	fade, so the lights arrive with the overlay and leave with it and cannot be stranded on a
	screen that is going away.

	WRITTEN EVERY FRAME RATHER THAN TWEENED, and it has to be: the pattern is a strobe with hard
	gaps in it (`PoliceConfig.Hud.Bust`), which is a dozen tweens a second per band, all of them
	fighting each other and every one of them a stale callback waiting to happen the moment a new
	race is entered over the top of this one. Two transparency writes off the loop this screen is
	already running is cheaper than one of those tweens.

	IT DOES NOT BAIL ON A MISSING WIDGET, and it used to. The lamps on the cruiser and the wash at
	the edges are built by two different things — one by `_showBustCar` when there is a template to
	clone, one by `_buildLights` when the effect is switched on — and either can be absent while the
	other is there. An early return on one of them silently stopped painting the other. ]]
function RaceUIController._stepLights(self, t: number, alpha: number)
	local bands = self._bustBands or {}
	local cfg = PoliceConfig.Hud.Bust
	local red, blue = PoliceConfig.bustFlash(t)

	--[[ THE CRUISER'S OWN LIGHT BAR IS PAINTED FROM THE SAME TWO NUMBERS, one line above the point
		where they stop being physical. That is the whole reason it is done here and not in a loop of
		its own: the lamps in the middle of the screen and the wash at its edges are one light bar,
		and two clocks — however carefully written — is two clocks that can beat against each other.

		BEFORE `Gain` AND BEFORE `alpha`, both deliberately. `Gain` is a correction for what a screen
		tint does over near-black and a neon part is not a screen tint; the viewport's own fade
		already carries the whole car in and out, so a second one applied to the lamps inside it
		would just make them lag it. An unlit lamp goes to `OffTransparency` rather than to nothing,
		because an unlit bar lamp on a real car is still a coloured lens. ]]
	for _, lamp in self._bustLamps or {} do
		lamp.part.Transparency = PoliceConfig.Cruisers.Bar.OffTransparency * (1 - (if lamp.red then red else blue))
	end

	--- `Gain` is the luminance correction, not a brightness preference — see its note. It is folded
	--- in here rather than in `bustFlash` so that stays an honest 0..1 pattern.
	red, blue = red * alpha * cfg.Gain.Red, blue * alpha * cfg.Gain.Blue

	for _, band in bands do
		paint(band.frame, if band.red then red else blue, cfg.Max)
	end

	--- The wash follows whichever lamp is up. The tie is red and it is never seen: both sides are
	--- zero in the dark gaps, and the colour of a wash at zero alpha is not a colour.
	local flood = self._bustFlood
	if flood then
		local tint = PoliceConfig.Hud.Vignette
		flood.BackgroundColor3 = if red >= blue then tint.Red else tint.Blue
		paint(flood, math.max(red, blue), cfg.Flood)
	end
end

--[[ === THE PLUME: the one thing the box cannot draw =========================================

	A `ViewportFrame` RENDERS NO PARTICLES. Not smoke, not fire, not sparks, and not the `Smoke`
	this same car was trailing down the road four seconds earlier. A viewport draws parts and
	nothing else, which is the same limit that leaves `_showBustCar` building a light bar out of
	Neon because a `PointLight` inside one throws nothing. So the plume on this screen is not in the
	shot at all: it is a handful of `ImageLabel`s in front of the viewport, rising out of the top of
	it and off the frame.

	IT IS ROBLOX'S OWN SMOKE TEXTURE, and that is why this needed no upload and no new art.
	`rbxasset://textures/particles/smoke_main.dds` is the image the `Smoke` class is made of. The
	engine ships it, every client already has it, and it is the same drawing the car was smoking
	with a moment ago. Nothing else available here would let a screen effect and a world effect be
	the same effect rather than two things that resemble each other.

	IT IS LIGHTER THAN THE PLUME IN THE WORLD, WHICH IS NOT AN INCONSISTENCY. `ObstacleController`
	smokes the car in near-black (38, 38, 42) because that plume is drawn over a lit road under a
	bright sky. This one is drawn over an overlay that is very nearly black, where a near-black
	plume is not a subtle plume, it is no plume at all. Smoke reads by contrast with whatever it is
	in front of, and the two grounds here are opposite. Same substance, opposite sign.

	WRITTEN EVERY FRAME RATHER THAN TWEENED, for the reasons `_stepLights` gives. The pattern is a
	loop with a life in it, seven of them out of phase, which is thirty-odd tweens a second and every
	one of them a stale callback waiting for the next entry to land on top of it. There is no
	per-puff state either: a puff's whole life is a function of the clock and its own phase, so
	nothing can be caught half-played.

	IN FRONT OF THE CAR AND BEHIND THE WORDS. The puffs sit inside the trophy box at `ZIndex` 3,
	over the viewport at 2, and the box itself is a sibling of the text at 1, so the whole plume
	still draws under the headline and the numbers. Smoke across the payout would be the decoration
	eating the screen it is decorating. ]]
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SMOKE_PUFFS = 7
local SMOKE_PERIOD = 2.6 -- seconds from a puff leaving the car to it fading out above the frame
local SMOKE_FROM = Vector2.new(0.68, 0.7) -- where it leaves, in the BOX's own scales. Set by eye.
local SMOKE_RISE = 1.2 -- box heights it climbs over one life
local SMOKE_DRIFT = 0.15 -- ...and how far it wanders sideways on the way up
local SMOKE_SIZE = NumberRange.new(0.4, 1.05) -- of the box, growing as it goes, because smoke expands
local SMOKE_COLOR = Color3.fromRGB(120, 124, 138)
local SMOKE_OPACITY = 0.5 -- the most any ONE puff is ever worth. Seven of them overlap.
local SMOKE_SPIN = 70 -- degrees a puff turns over its life, so no two of them show the same blob
--- The shape of a life: in fast, out slow. That is what makes a puff read as expanding into nothing
--- rather than as a sprite being faded down.
local SMOKE_IN = 0.16
local SMOKE_OUT = 1.4

--[[ Build the puffs once, into the trophy box, and leave them invisible.

	SIZED AND POSITIONED IN THE BOX'S SCALES rather than the screen's, so the plume lands with the
	car, scales with it on every device the box scales on, and the one number here that had to be
	decided by eye (`SMOKE_FROM`) is measured against the thing it is supposed to be coming out of.

	The per-puff randomness is rolled HERE rather than once per life. A puff whose sway changed
	every time round would read as a flicker rather than as a plume. ]]
local function buildPuffs(parent: GuiObject): { any }
	local rng = Random.new()
	local puffs = {}
	for index = 1, SMOKE_PUFFS do
		local image = Instance.new("ImageLabel")
		image.Name = "Puff" .. index
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(SMOKE_FROM.X, SMOKE_FROM.Y)
		image.Size = UDim2.fromScale(SMOKE_SIZE.Min, SMOKE_SIZE.Min)
		image.BackgroundTransparency = 1
		image.Image = SMOKE_TEXTURE
		image.ImageColor3 = SMOKE_COLOR
		image.ImageTransparency = 1
		image.ZIndex = 3
		image.Parent = parent

		table.insert(puffs, {
			image = image,
			--- Evenly spaced and then nudged: seven puffs exactly a seventh apart pulse rather than pour.
			phase = (index - 1) / SMOKE_PUFFS + rng:NextNumber(-0.05, 0.05),
			sway = rng:NextNumber(0.55, 1) * (if index % 2 == 0 then 1 else -1),
			spin = rng:NextNumber(-1, 1),
			scale = rng:NextNumber(0.85, 1.2),
		})
	end
	return puffs
end

local function clearPuffs(puffs: { any }?)
	for _, puff in puffs or {} do
		puff.image.ImageTransparency = 1
	end
end

--[[ One frame of a plume. `t` is seconds since the car landed and `alpha` is the screen's own fade.

	NOTHING IS BORN AND NOTHING RETIRES. A puff's position in its life is `t` and its own phase,
	modulo one, so the plume is already going the moment the screen appears. That is the correct
	reading rather than a shortcut: the car has been smoking since the wreck, and a plume that
	started empty and built up would be the screen claiming the fire began when the numbers did. ]]
local function stepPuffs(puffs: { any }?, t: number, alpha: number)
	if not puffs then
		return
	end
	if t <= 0 or alpha <= 0 then
		clearPuffs(puffs)
		return
	end
	local age = t / SMOKE_PERIOD
	for _, puff in puffs do
		local u = (age + puff.phase) % 1
		local image = puff.image
		--- A half sine rather than a full one, so a puff leans away and keeps leaning instead of
		--- swinging back through the middle like something hanging on a string.
		image.Position = UDim2.fromScale(
			SMOKE_FROM.X + math.sin(u * math.pi) * SMOKE_DRIFT * puff.sway,
			SMOKE_FROM.Y - u * SMOKE_RISE
		)
		local size = (SMOKE_SIZE.Min + (SMOKE_SIZE.Max - SMOKE_SIZE.Min) * u) * puff.scale
		image.Size = UDim2.fromScale(size, size)
		image.Rotation = puff.spin * SMOKE_SPIN * u
		--- Clamped, because `SMOKE_OPACITY` is what one puff is worth and the frame where all seven
		--- of them overlap is not the place to discover that a transparency went negative.
		local life = math.min(u / SMOKE_IN, 1) * (1 - u) ^ SMOKE_OUT
		image.ImageTransparency = 1 - math.clamp(life * SMOKE_OPACITY * alpha, 0, 1)
	end
end

--- The trophy box's own plume. `buildPuffs` is shared with `buildWreckShot`, which smokes the same
--- car on the revive panel.
function RaceUIController._buildSmoke(self, trophy: Frame)
	self._smokePuffs = buildPuffs(trophy)
end

--- Put the plume out. Called by every `_show` for the reason `_clearLights` is: a wreck two runs ago
--- must not still be smoking behind an entry screen.
function RaceUIController._clearSmoke(self)
	clearPuffs(self._smokePuffs)
end

--- One frame of the trophy box's plume; `stepPuffs` has the argument. `alpha` is read off the
--- overlay for the reason `_stepLights` reads it there.
function RaceUIController._stepSmoke(self, t: number, alpha: number)
	stepPuffs(self._smokePuffs, t, alpha)
end


function RaceUIController._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RaceTransition"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = OVERLAY_COLOR
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	--[[ The world photograph, and it goes in before the lights for the same reason they go in before
		everything else: with `ZIndexBehavior.Sibling` two siblings on the SAME `ZIndex` fall back to
		child order, and both of these sit on 0. Built first = drawn first = furthest back, which is
		where a backdrop belongs and where the bust lights need it to be. ]]
	local backdrop = Instance.new("ImageLabel")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 0
	--- Portrait source into a landscape frame; see `BACKDROP_TINT`.
	backdrop.ScaleType = Enum.ScaleType.Crop
	backdrop.ImageColor3 = BACKDROP_TINT
	--- Starts invisible and STAYS invisible until an entry asks for it: `_paintLoading` is the only
	--- thing that ever sets an image here, so a results screen inherits nothing from the entry
	--- before it.
	backdrop.ImageTransparency = 1
	backdrop.Visible = false
	backdrop.Parent = overlay
	self._backdrop = backdrop

	--- First, so the rest of the screen is built on top of it. `ZIndex` is what actually settles
	--- the order (see the note there), but a reader should not have to know that to see it.
	self:_buildLights(overlay)

	-- Spinner: a ring whose gradient sweeps from transparent to solid, spun continuously. Sized off
	-- the screen's SHORTER side (the aspect constraint takes the smaller of the two scales), so it
	-- stays a circle and stays the same fraction of the view in portrait and in landscape.
	local spinner = Instance.new("Frame")
	spinner.Name = "Spinner"
	spinner.AnchorPoint = Vector2.new(0.5, 0.5)
	spinner.Position = UDim2.fromScale(0.5, SPINNER_Y)
	spinner.Size = UDim2.fromScale(SPINNER_SIZE, SPINNER_SIZE)
	spinner.BackgroundColor3 = ACCENT_COLOR
	spinner.BackgroundTransparency = 1
	spinner.Parent = overlay

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = spinner

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = spinner

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4 -- replaced from the viewport every frame it spins; see _show
	stroke.Color = ACCENT_COLOR
	stroke.Transparency = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = spinner

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.75),
		NumberSequenceKeypoint.new(1, 0),
	})
	gradient.Parent = stroke

	--[[ The trophy: a square box holding an over-sized burst and, in front of it, the car.

		EVERY OTHER ELEMENT ON THIS SCREEN IS PUSHED TO `ZIndex` 2 BECAUSE OF THIS ONE. The burst is
		1.5x its box, so it reaches up past the headline; with `ZIndexBehavior.Sibling` a whole subtree
		draws under a sibling of a higher ZIndex, so lifting the four text elements once here is what
		keeps the words in front of the rays without having to shrink the art to avoid them. ]]
	local trophy = Instance.new("Frame")
	trophy.Name = "Trophy"
	trophy.AnchorPoint = Vector2.new(0.5, 0.5)
	trophy.Position = UDim2.fromScale(0.5, TROPHY_Y)
	trophy.Size = UDim2.fromScale(TROPHY_SIZE, TROPHY_SIZE)
	trophy.BackgroundTransparency = 1
	trophy.Visible = false
	trophy.ZIndex = 1
	trophy.Parent = overlay

	local trophyAspect = Instance.new("UIAspectRatioConstraint")
	trophyAspect.AspectRatio = 1
	trophyAspect.Parent = trophy

	local burst = Instance.new("ImageLabel")
	burst.Name = "Sunburst"
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromScale(SUNBURST_SCALE, SUNBURST_SCALE)
	burst.BackgroundTransparency = 1
	burst.Image = UIAssets.url(UIAssets.Results.Sunburst)
	burst.ImageColor3 = SUNBURST_COLOR
	burst.ImageTransparency = 1
	burst.ZIndex = 1
	burst.Parent = trophy

	--[[ The car. `ImageTransparency` is the fade — on a ViewportFrame it is the RENDERED SCENE's
		transparency, so one tween takes the whole car up and down and nothing has to walk 38 parts.

		No `WorldModel`: nothing in here is simulated, jointed or lit by anything but the three
		properties below, and a WorldModel would only add a physics-capable container for a model whose
		every part arrives anchored. ]]
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Car"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	--[[ NEVER DRAWN — the transparency above is 1 and stays there. It is the colour the car's own
		EDGES come out, because a ViewportFrame composites its render against `BackgroundColor3`
		BEFORE that transparency is applied: every pixel the car partly covers is part car and part
		this, whatever the transparency says. Left at the `(163, 162, 165)` `Instance.new` hands out,
		that is a light outline traced round the car. `Modules/CarViewport` has the long version.

		`OVERLAY_COLOR` is what the car is actually standing on by the time the trophy appears — the
		overlay is opaque behind it, and the sunburst in between is dim enough to leave it. ]]
	viewport.BackgroundColor3 = OVERLAY_COLOR
	viewport.BorderSizePixel = 0
	viewport.ImageTransparency = 1
	viewport.Ambient = CAR_AMBIENT
	viewport.LightColor = CAR_LIGHT
	viewport.LightDirection = CAR_LIGHT_DIR
	viewport.ZIndex = 2
	viewport.Parent = trophy

	local camera = Instance.new("Camera")
	camera.FieldOfView = CAR_FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	--- ...and the plume in front of it, which is not inside the shot because it cannot be. The box
	--- is its parent so the smoke lands with the car and scales with it. See `THE PLUME`.
	self:_buildSmoke(trophy)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, HEADLINE_Y)
	label.Size = HEADLINE_SIZE
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = ENTER_LABEL
	label.TextColor3 = ACCENT_COLOR
	label.TextTransparency = 1
	label.TextScaled = true
	label.ZIndex = 2
	label.Parent = overlay
	--- The headline's phone floor, for the reason `GEOMETRY.status.minText` gives: 0.045 of a phone's
	--- height is about 17 px. 24 never binds on a desktop and still clears the bar's car below it.
	local headlineFloor = Instance.new("UITextSizeConstraint")
	headlineFloor.MinTextSize = 24
	headlineFloor.Parent = label

	--[[ The bar. It was a hairline divider first and it still IS one whenever the ladder can't be
		worked out, which is why the track keeps the name `Rule` and keeps being wiped open from the
		centre: that wipe is what turns "the screen went black" into "something is being totalled up",
		and it takes the run's colour, so it has said which ending this was before a single number has
		finished counting.

		FOUR SIBLINGS, NOT A NESTED GROUP, and all four positioned in SCREEN scales. The track is the
		only one of them that gets its width animated, so parenting the rest to it would drag the car
		and the ticks through the wipe as well — the car would grow out of the middle of the bar rather
		than drive along it. Flat siblings cost one shared `left` term and nothing else. ]]
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0.5, 0.5)
	rule.Position = UDim2.fromScale(0.5, RULE_Y)
	rule.Size = UDim2.fromScale(0, RULE_HEIGHT)
	rule.BackgroundColor3 = PAYOUT_COLOR
	rule.BackgroundTransparency = 1
	rule.BorderSizePixel = 0
	rule.ZIndex = 2
	rule.Parent = overlay

	local ruleCorner = Instance.new("UICorner")
	ruleCorner.CornerRadius = UDim.new(1, 0)
	ruleCorner.Parent = rule

	-- What the run actually covered, growing from the left-hand end. Anchored to that end rather than
	-- centred, because it is a distance travelled and distances have a start line.
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0.5 - RULE_WIDTH / 2, RULE_Y)
	fill.Size = UDim2.fromScale(0, TRACK_HEIGHT)
	fill.BackgroundColor3 = PAYOUT_COLOR
	fill.BackgroundTransparency = 1
	fill.BorderSizePixel = 0
	fill.Visible = false
	fill.ZIndex = 3
	fill.Parent = overlay

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	-- The rungs live in a container of their own because there is one per car in the world and the
	-- world can change between runs: clearing a container is one loop, and it keeps a stale eight-tick
	-- ladder from surviving a teleport into a world with ten.
	local ticks = Instance.new("Frame")
	ticks.Name = "Ticks"
	ticks.AnchorPoint = Vector2.new(0.5, 0.5)
	ticks.Position = UDim2.fromScale(0.5, RULE_Y)
	ticks.Size = UDim2.fromScale(RULE_WIDTH, TRACK_HEIGHT * TICK_HEIGHT)
	ticks.BackgroundTransparency = 1
	ticks.Visible = false
	ticks.ZIndex = 4
	ticks.Parent = overlay

	local marker = Instance.new("ImageLabel")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 1)
	marker.Position = UDim2.fromScale(0.5 - RULE_WIDTH / 2, MARKER_Y)
	--[[ Full width on purpose. `UIAspectRatioConstraint` fits the element INSIDE its authored box, so
		the height is what binds here and the zero-width form would collapse the whole thing to 0x0 —
		which renders as nothing at all and reads exactly like a missing image. ]]
	marker.Size = UDim2.fromScale(1, MARKER_HEIGHT)
	marker.BackgroundTransparency = 1
	marker.Image = UIAssets.url(UIAssets.Results.CarMarker)
	marker.ImageTransparency = 1
	marker.Visible = false
	marker.ZIndex = 5
	marker.Parent = overlay

	local markerAspect = Instance.new("UIAspectRatioConstraint")
	markerAspect.AspectRatio = UIAssets.ResultsSize.CarMarker.X / UIAssets.ResultsSize.CarMarker.Y
	markerAspect.Parent = marker

	--[[ The results, ONE LABEL PER LINE rather than one label of three lines.

		They are stacked by hand at paint time (`_paintPayout`) instead of by a UIListLayout, and
		that is the whole reason for the split: the beat animates each line's size and position
		separately — a punch, a slide — and a layout that owns those properties would fight every
		one of them. Stacking three known boxes is four lines of arithmetic; fighting a layout is
		not. It also lets the distance line rest dimmer and smaller than the payout above it, which
		a single label could only do with rich text. ]]
	local lines = {}
	for name, geom in GEOMETRY do
		local line = Instance.new("TextLabel")
		line.Name = name:sub(1, 1):upper() .. name:sub(2)
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale(0.5, RESULTS_TOP)
		line.Size = UDim2.fromScale(geom.width, geom.height)
		line.BackgroundTransparency = 1
		line.Font = geom.font or Enum.Font.GothamBold
		line.Text = ""
		line.TextColor3 = PAYOUT_COLOR
		line.TextTransparency = 1
		line.TextScaled = true
		line.Visible = false
		line.ZIndex = 2
		line.Parent = overlay
		if geom.minText then
			local floor = Instance.new("UITextSizeConstraint")
			floor.MinTextSize = geom.minText
			floor.Parent = line
		end
		lines[name] = line
	end

	self:_buildReplay(overlay)

	--[[ A LIFTED SCREEN SWITCHES ITSELF BACK OFF, whoever switched it on (2026-09-30).

		The NEW BEST cutscene (`ShowcaseController`) plays off this screen's lift, so it sweeps every
		ScreenGui off while this one is still fading, records it as wanted, and switches it back on when
		the stage ends. By then the fade has finished and written its own `false` onto a screen that was
		already forced off, which fires nothing, so the restore puts a finished screen back up: an overlay
		faded to nothing with RACE AGAIN still `Visible` and `Active` at DisplayOrder 1000, over PLAY.
		Every first bank is a new best, so every new player's first press of Play after it did nothing.
		`BuyerController._keepClosedShut` is the same guard for the same trap.

		`_show` sets `_visible` BEFORE it enables the screen, and is the only writer of `true` here, so a
		real show is never undone. The fade itself runs with `_visible` already false, but it only ever
		leaves `Enabled` where it is, so it is not a change this hears. ]]
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled and not self._visible then
			gui.Enabled = false
		end
	end)

	self._gui = gui
	self._overlay = overlay
	self._spinner = spinner
	self._stroke = stroke
	self._label = label
	self._rule = rule
	self._fill = fill
	self._ticks = ticks
	self._marker = marker
	self._lines = lines
	self._trophy = trophy
	self._burst = burst
	self._viewport = viewport
	self._camera = camera

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui.Parent = playerGui

	--[[ AFTER THE PARENTING, because that is the first moment the ScreenGui has a size to measure,
		and the RACE AGAIN pill is the one element here whose box has to be solved against it. A phone
		rotated, a window dragged wider and the device emulator switched mid-playtest all arrive as a
		change to that size; everything else on this screen is authored in scales and rides it out. ]]
	self:_layoutReplay()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layoutReplay()
	end)
end

--[[ RACE AGAIN: the pill, its caption and its clock. See the block at `REPLAY_PILL` for what it
	is for and why it is drawn the way it is; this is only the construction.

	THE SLOT IS NOT DECORATION. Only ONE `UIScale` on an instance takes effect, and `Components/
	Button` claims the button's own the moment the `UIButton` tag lands — so a press dip written
	there would be fighting the hover for one channel, and `_layoutReplay` rewriting the size under
	both of them would win every argument. The SLOT holds the position, the size and the dip; the
	BUTTON fills it at 1x1 and keeps its scale channel free. `ReviveController`'s own pair carries
	the long version of the same finding.

	ZINDEX 6 puts it over every other element on this overlay — the ladder's marker at 5 is the
	highest of them. That matters for nothing it overlaps today and matters the first time somebody
	moves a line down or lengthens the bar: a button underneath the furniture is a button that stops
	taking presses, and it fails silently. ]]
function RaceUIController._buildReplay(self, overlay: Frame)
	local slot = Instance.new("Frame")
	slot.Name = "ReplaySlot"
	slot.AnchorPoint = Vector2.new(0.5, 0.5)
	slot.Size = UDim2.fromScale(REPLAY_WIDTH_MAX, REPLAY_HEIGHT) -- ...until `_layoutReplay` runs
	slot.Position = UDim2.fromScale(0.5, REPLAY_BOTTOM - REPLAY_HEIGHT / 2)
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.Visible = false
	slot.ZIndex = 6
	slot.Parent = overlay

	local scale = Instance.new("UIScale")
	scale.Parent = slot

	local button = Instance.new("ImageButton")
	button.Name = "RaceAgain"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.AutoButtonColor = false -- the art is the press; Roblox's automatic darkening is not
	button.Image = pillAsset(REPLAY_PILL.Idle)
	button.HoverImage = pillAsset(REPLAY_PILL.Hover)
	button.PressedImage = pillAsset(REPLAY_PILL.Pressed)
	button.ImageTransparency = 1
	--[[ STRETCHED, NEVER SLICED. `UIAssets`' own block on this is unambiguous: a pill is only ever
		drawn at the art's 3.89:1, and slicing one pins the corner curves at texture pixels while the
		middle band takes all the shrink — which reads as a lozenge rather than as the drawing. ]]
	button.ScaleType = Enum.ScaleType.Stretch
	button.ZIndex = 6
	button.Parent = slot

	--- Its own label rather than the button's `Text`, because the button is an image and its text
	--- would sit under the drain. Ubuntu Bold is the kit's face; `ACCENT_COLOR` is this screen's white.
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0.5, 0.5)
	caption.Position = UDim2.fromScale(0.5, REPLAY_CAPTION_Y)
	caption.Size = REPLAY_CAPTION_SIZE
	caption.BackgroundTransparency = 1
	caption.FontFace = REPLAY_FONT
	caption.Text = REPLAY_LABEL
	caption.TextColor3 = ACCENT_COLOR
	caption.TextTransparency = 1
	caption.TextScaled = true
	caption.ZIndex = 7
	caption.Parent = button

	local track = Instance.new("Frame")
	track.Name = "DrainTrack"
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, REPLAY_DRAIN_Y)
	track.Size = UDim2.fromScale(REPLAY_DRAIN_WIDTH, REPLAY_DRAIN_HEIGHT)
	track.BackgroundColor3 = REPLAY_TRACK_COLOR
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	track.ZIndex = 7
	track.Parent = button

	--- Anchored to the LEFT end rather than centred, for the reason the revive button's is: time runs
	--- out from one side, and a bar closing in from both ends reads as a thing being loaded.
	local drain = Instance.new("Frame")
	drain.Name = "Drain"
	drain.AnchorPoint = Vector2.new(0, 0.5)
	drain.Position = UDim2.fromScale(0, 0.5)
	drain.Size = UDim2.fromScale(1, 1)
	drain.BackgroundColor3 = ACCENT_COLOR
	drain.BackgroundTransparency = 1
	drain.BorderSizePixel = 0
	drain.ZIndex = 8
	drain.Parent = track

	self._replaySlot = slot
	self._replayScale = scale
	self._replayButton = button
	self._replayCaption = caption
	self._replayTrack = track
	self._replayDrain = drain

	--[[ The dip, on the slot for the reason the slot exists at all — and lifted from three places
		because only the press can name its button. A release arrives from a pointer that left, a mouse
		let go over the button, or a finger lifted anywhere at all, and a touch drag does not reliably
		report the second or the third. Left to `MouseButton1Up` alone the dip sticks at 97% for the
		rest of the screen. `ReviveController._wire` has the long version. ]]
	local function lift()
		scale.Scale = 1
	end
	button.MouseButton1Down:Connect(function()
		if not self._replayLocked then
			scale.Scale = REPLAY_PRESS_SCALE
		end
	end)
	button.MouseButton1Up:Connect(lift)
	button.MouseLeave:Connect(lift)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			scale.Scale ~= 1
			and (
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			lift()
		end
	end)
	button.Activated:Connect(function()
		self:_pressReplay()
	end)

	--[[ A `UIButton` like every other pressable thing in this game (`Components/Button`), which is
		what gives it the hover nudge and the click sound — including the sounds that do not exist yet,
		since `SoundController` no-ops on an empty group and starts working the day one is dropped in.

		IT CARRIES NEITHER A `Page` NOR AN `Action` ATTRIBUTE, deliberately. What this press MEANS
		depends on whether the offer is still open, which is state the UI layer knows nothing about, so
		`Activated` above owns it and the tag brings only the furniture. Same bargain the revive
		screen's two answers strike, and for the same reason. ]]
	button:SetAttribute("Scale", REPLAY_HOVER_SCALE)
	CollectionService:AddTag(button, "UIButton")
end

--[[ Solve the pill's box against the viewport, and stand it on `REPLAY_BOTTOM`.

	EVERY OTHER ELEMENT ON THIS SCREEN IS AUTHORED IN SCREEN SCALES AND NEEDS NO SUCH PASS, which is
	the header's whole boast about this file. The pill is the one thing on it with an aspect the ART
	owns rather than the layout: asked to fill a box of the wrong shape it does not letterbox, it
	SMEARS — `ReviveController`'s `PILL` block found the same thing at 9:1 and wrote down what it
	looked like.

	Run on every `AbsoluteSize` change, so a rotated phone, a dragged window and the device emulator
	all move it. ]]
function RaceUIController._layoutReplay(self)
	local slot = self._replaySlot
	if not (slot and self._gui) then
		return
	end
	local view = self._gui.AbsoluteSize
	if view.X <= 0 or view.Y <= 0 then
		return
	end
	-- Width implied by the authored height, then capped, then the height read back off whichever of
	-- the two won. `ReviveController.pillSize` is the same three lines, against the same art.
	local ratio = view.X / view.Y
	local width = math.min(REPLAY_WIDTH_MAX, REPLAY_HEIGHT * REPLAY_PILL_ASPECT / ratio)
	local height = width * ratio / REPLAY_PILL_ASPECT

	slot.Size = UDim2.fromScale(width, height)
	--[[ Latched, because the entrance slides the slot up INTO this and the slide is measured off it.
		A resize mid-slide must not snap the button to a home the tween is no longer heading for, so the
		position is only written when nothing is animating it. ]]
	self._replayHome = UDim2.fromScale(0.5, REPLAY_BOTTOM - height / 2)
	if not self._replaySliding then
		slot.Position = self._replayHome
	end

	--- ...and the controller badge with it, one gap outside the pill's left edge, exactly where the
	--- revive screen puts its own two. Written straight onto a badge that already exists, so a resize
	--- with the button up moves the glyph with the thing it points at.
	self._replayIconAt = UDim2.fromScale(0.5 - width / 2 - REPLAY_ICON_GAP, self._replayHome.Y.Scale)
	local icon = GamepadInput.getIcon(PAD_REPLAY)
	if icon then
		icon.Position = self._replayIconAt
	end
end

--[[ The controller binding, raised with the offer and dropped with it. `REPLAY_PILL`'s own block
	has the whole argument; the short version is that a pad cannot reach this button any other way,
	and that the lobby's navigation is live underneath the screen by now and owns the same press.

	THE BADGE IS PARENTED TO THE OVERLAY rather than to the pill, so it does not ride the hover swell
	and the press dip — a glyph that moved with the button would read as part of the face. Its ZIndex
	is written after the bind because `GamepadInput` has no opinion about one, and everything on this
	overlay that matters is above the default. ]]
function RaceUIController._bindReplayPad(self, on: boolean)
	--[[ A take-down with nothing of ours up is a no-op, and it has to be: `_show` calls this on
		every screen it raises, including the entries that never offer a replay, and the modal flag is
		shared with every other screen that owns the face (`GamepadConfig.ModalAttribute`). Clearing a
		flag somebody else raised would hand their B button back to the rail underneath them. ]]
	if not (on or GamepadInput.isBound(PAD_REPLAY)) then
		return
	end
	GamepadInput.setModal("RaceUIController", on)
	if not on then
		GamepadInput.unbind(PAD_REPLAY)
		return
	end
	local icon = GamepadInput.bind({
		actionName = PAD_REPLAY,
		keyCode = Enum.KeyCode.ButtonA,
		callback = function()
			self:_pressReplay()
		end,
		parent = self._overlay,
		iconPosition = self._replayIconAt,
		iconAnchor = Vector2.new(1, 0.5),
		priority = PAD_REPLAY_PRIORITY,
	})
	--[[ ...and it comes up WITH the button rather than snapping on in front of it. `createIcon`
		hands back a finished badge at full opacity, which on a screen where everything else fades
		would be the one element that did not respect the entrance. `_raiseReplay` fades it from
		here. Its ZIndex is the module's own 10 and is left alone: that is already over everything
		this overlay draws. ]]
	if icon then
		icon.ImageTransparency = 1
		icon.BackgroundTransparency = 1
		local stroke = icon:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Transparency = 1
		end
	end
end

--- The badge, read back off the binding rather than kept in a field: `GamepadInput.unbind` destroys
--- it, so the module is the only thing that can honestly answer whether it still exists.
--- `ReviveController._padIcons` is the same three lines for the same reason.
function RaceUIController._replayIcon(self): ImageLabel?
	local icon = GamepadInput.getIcon(PAD_REPLAY)
	return if icon and icon.Parent then icon else nil
end

--- Fade the badge with the button it belongs to. It is a filled disc, so its background goes with
--- the image rather than being left as a solid dot behind a fading glyph.
function RaceUIController._fadeReplayIcon(self, time: number, visible: boolean)
	local icon = self:_replayIcon()
	if not icon then
		return
	end
	local transparency = if visible then 0 else 1
	self:_tween(icon, time, { ImageTransparency = transparency, BackgroundTransparency = transparency })
	local stroke = icon:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		self:_tween(stroke, time, { Transparency = transparency })
	end
end

--[[ Take the offer's binding down, and let the badge LEAVE WITH THE BUTTON rather than vanishing
	in front of it.

	`GamepadInput.unbind` destroys the icon, which is the whole reason this is three lines rather than
	one: unbinding first and fading afterwards fades nothing, and a badge that snapped off a pill that
	was still fading would be the one element on this screen that did not respect the exit.

	THE BINDING OUTLIVING THE OFFER BY A FIFTH OF A SECOND COSTS NOTHING. `_pressReplay` answers to
	`_replayable`, and every caller here drops that BEFORE calling this — so what is left alive is a
	ContextAction that sinks ButtonA and then does nothing with it, for exactly as long as the badge
	takes to fade. Fenced on the screen's token so a screen that arrived in the meantime, and bound
	its own, cannot have it torn down underneath it. ]]
function RaceUIController._dropReplayPad(self, fade: number)
	if not GamepadInput.isBound(PAD_REPLAY) then
		return
	end
	self:_fadeReplayIcon(fade, false)
	local token = self._token
	task.delay(fade, function()
		if self._token == token then
			self:_bindReplayPad(false)
		end
	end)
end

--[[ Put the button back the way `_build` left it. Called from `_show`, unconditionally, on the same
	reasoning `_paintPayout`'s own reset is written out on: these widgets carry animation state — a
	position mid-slide, a dip mid-press, a drain part-emptied — and a screen that took over from one
	that was still animating would inherit all of it. Resetting in the thing that is ABOUT to use
	them is the only moment it is certainly safe. ]]
function RaceUIController._resetReplay(self)
	self._replayLocked = false
	self._replayUntil = nil
	self._replaySliding = false
	self:_bindReplayPad(false)

	local slot = self._replaySlot
	if not slot then
		return
	end
	slot.Visible = false
	self._replayScale.Scale = 1
	self._replayButton.ImageTransparency = 1
	self._replayCaption.TextTransparency = 1
	self._replayTrack.BackgroundTransparency = 1
	self._replayDrain.BackgroundTransparency = 1
	self._replayDrain.Size = UDim2.fromScale(1, 1)
	if self._replayHome then
		slot.Position = self._replayHome
	end
end

--[[ The offer arriving, last in the beat. It slides up into place exactly the way the two receipt
	lines do — same move, same time — because it is arriving on the same screen and a different
	entrance would read as a different kind of object.

	THE DEADLINE IS DERIVED FROM `_shownAt`, NOT FROM NOW, and that is the point of the line rather
	than pedantry: `_show` books `REPLAY_HOLD` against the same instant, so the bar and the screen's
	own hold are one number seen twice rather than two numbers that agree. A `task.delay` that ran a
	frame late would otherwise leave the drain finishing after the screen had started to fade. ]]
function RaceUIController._raiseReplay(self)
	local slot = self._replaySlot
	if not (slot and self._replayable) then
		return
	end
	--- The home is solved here rather than trusted from build time: the viewport can have changed
	--- since, and this is the last moment before the move that is measured off it.
	self:_layoutReplay()
	--- ...and it can still come back with nothing, on the one frame a viewport reports 0x0 (a window
	--- being restored, a device emulator switching). The offer is worth more than the slide, so the
	--- button stands where `_build` put it and arrives without one.
	local home = self._replayHome or slot.Position

	self._replayUntil = (self._shownAt or os.clock()) + REPLAY_HOLD
	slot.Position = home + UDim2.fromScale(0, REPLAY_RISE)
	slot.Visible = true
	self._replaySliding = true

	local slide = self:_tween(slot, REPLAY_IN, { Position = home })
	slide.Completed:Once(function()
		self._replaySliding = false
	end)
	self:_tween(self._replayButton, REPLAY_IN, { ImageTransparency = 0 })
	self:_tween(self._replayCaption, REPLAY_IN, { TextTransparency = 0 })
	self:_tween(self._replayTrack, REPLAY_IN, { BackgroundTransparency = REPLAY_DRAIN_REST })
	self:_tween(self._replayDrain, REPLAY_IN, { BackgroundTransparency = 0 })

	self:_bindReplayPad(true)
	self:_fadeReplayIcon(REPLAY_IN, true)
end

--[[ The clock, redrawn every frame off the deadline rather than tweened down from full.

	A TWEEN WOULD BE A SECOND ACCOUNT OF THE SAME FACT and the two could disagree — the screen's hold
	is the deadline, and a bar that had been animating independently of it since the button landed
	would be right only as long as nothing interrupted either. The width IS the fraction remaining,
	which is the same rule `ReviveController` draws its own drain by.

	AND IT LOCKS AT ZERO. The screen is already fading by then, but the fade takes half a second and a
	pill you can still see is a pill a thumb will still land on; a press that arrived after the offer
	closed would be a press the server answers with nothing. ]]
function RaceUIController._stepReplayDrain(self)
	local until_ = self._replayUntil
	if not (until_ and self._replayDrain) then
		return
	end
	local left = math.clamp((until_ - os.clock()) / REPLAY_WINDOW, 0, 1)
	self._replayDrain.Size = UDim2.fromScale(left, 1)
	if left <= 0 then
		self._replayLocked = true
	end
end

--[[ The press. It is the only thing on this screen that does anything, and it does exactly two:
	hand the screen over to the entry that is about to arrive, and ask for that entry.

	IN THAT ORDER, AND THE ORDER IS LOAD-BEARING. `Dispatcher:Publish` runs its subscribers on THIS
	thread, so a subscriber that threw would take everything after it with it — and everything after
	it is the screen letting go of the results and the fence that stops the black being held forever.
	`_hide` publishes its own two events last for the same reason, and says so.

	THE LOCK IS ON THE PRESS, not on the answer coming back. There is a round trip between here and
	`RaceEntering`, and a player who wanted another run will press a button that still looks live as
	many times as it lets them. A second press does nothing the first did not already ask for, and
	`RaceConfig.EnterRequestCooldown` would eat it at the far end anyway — but a button that visibly
	stops asking is the difference between "sent" and "did that work?". ]]
function RaceUIController._pressReplay(self)
	if self._replayLocked or not (self._replayable and self._visible) then
		return
	end
	self._replayLocked = true
	self._replayScale.Scale = 1

	self:_playReplay()
	Dispatcher:Publish(RaceConfig.ReplayEvent)
end

--[[ Hand the screen over: take the results off it, and LEAVE THE BLACK WHERE IT IS.

	THIS IS THE WHOLE REASON A REPLAY READS AS "AGAIN" RATHER THAN AS TWO SEPARATE TRIPS. The
	ordinary way out of here is `_hide`, which fades the overlay off onto the lobby — and a replay
	that went through it would show the player their own plot for about eight tenths of a second
	between one run and the next, then black it out again. The player never goes home on a replay, so
	the screen never lifts: the results fade off the overlay, the spinner comes back up because
	something is genuinely being waited for again, and `_show` paints the entry's own loading screen
	straight onto the black that is already there.

	THE TOKEN IS TURNED OVER HERE, which is what cancels the drop `_hide` has almost certainly
	already scheduled — `RaceLive` lands about half a second into this screen and books the hold from
	there, so by the time anything can be pressed there is a `task.delay` in flight with this screen's
	name on it. Bumping the token makes it bail. `_hide` then refuses to schedule another while
	`_replaying` stands, so the late arrival of `RaceLive` cannot do it either.

	AND THE FENCE UNDER IT. Holding the black means holding it for something that might never come:
	the server can refuse an entry (a world this player has not earned, a cooldown, a race they are
	somehow already in) and it refuses silently by design. `RaceConfig.Replay.Timeout` is how long
	that is given before the screen gives up and goes home the ordinary way, and its note is where
	the number is argued. ]]
function RaceUIController._playReplay(self)
	self._replaying = true
	self._replayUntil = nil
	self._replayable = false
	--- Every hold this screen had booked for itself goes with the results it was booked for.
	self._holdUntil = nil

	local token = (self._token or 0) + 1
	self._token = token
	--- After the token turns over, so the delayed unbind inside is fenced on THIS screen rather than
	--- on the one it is replacing. `_replayable` is already false, so the offer is shut either way.
	self:_dropReplayPad(REPLAY_OUT)

	--- The furniture, on the half-fade `_hide` uses for the same widgets: it is being cleared off a
	--- screen that is staying, not taken down with one that is going.
	self:_tween(self._rule, REPLAY_OUT, { BackgroundTransparency = 1 })
	self:_tween(self._fill, REPLAY_OUT, { BackgroundTransparency = 1 })
	self:_tween(self._marker, REPLAY_OUT, { ImageTransparency = 1 })
	for _, tick in self._tickList or {} do
		self:_tween(tick, REPLAY_OUT, { BackgroundTransparency = 1 })
	end
	self:_tween(self._burst, REPLAY_OUT, { ImageTransparency = 1 })
	self:_tween(self._viewport, REPLAY_OUT, { ImageTransparency = 1 })
	for _, line in self._lines do
		self:_tween(line, REPLAY_OUT, { TextTransparency = 1 })
	end
	self:_tween(self._replayButton, REPLAY_OUT, { ImageTransparency = 1 })
	self:_tween(self._replayCaption, REPLAY_OUT, { TextTransparency = 1 })
	self:_tween(self._replayTrack, REPLAY_OUT, { BackgroundTransparency = 1 })
	self:_tween(self._replayDrain, REPLAY_OUT, { BackgroundTransparency = 1 })

	--[[ ...and the two effects that are painted per frame rather than tweened, which is why they are
		CLEARED rather than faded. Both read their own alpha off the overlay's transparency, and the
		overlay is not going anywhere — so a wreck left smoking here would go on smoking behind the
		loading bar of the next run. ]]
	self._bustedScreen = false
	self._wreckedScreen = false
	self:_clearSmoke()
	self:_clearLights()

	--[[ The headline stops being the news and becomes what the game is doing, cross-faded rather
		than swapped: the word is the largest thing on the screen and a straight cut of it is the one
		move here the player would actually catch. ]]
	local fade = self:_tween(self._label, REPLAY_OUT, { TextTransparency = 1 })
	fade.Completed:Once(function()
		if self._token ~= token or not self._replaying then
			return
		end
		self._label.Text = ENTER_LABEL
		self:_tween(self._label, REPLAY_OUT, { TextTransparency = 0.1 })
		--- ...and the ring turns again, because this screen is waiting on something once more. It was
		--- put out by `BEAT_RULE` the moment there was a finished total on here instead.
		self:_tween(self._stroke, REPLAY_OUT, { Transparency = 0 })
	end)

	self:_fenceReplay(token, RaceConfig.Replay.Timeout)
end

--[[ The fence under a held black: if no race has taken the screen `seconds` from now, give up and go
	home the ordinary way. Shared by the RACE AGAIN press and the one-screen wreck's own replay. ]]
function RaceUIController._fenceReplay(self, token: number, seconds: number)
	task.delay(seconds, function()
		if self._token ~= token or not self._replaying then
			return -- the entry arrived and took the screen; this is not ours any more
		end
		self.log:warn("A race again was asked for but no race arrived; putting the player back in the lobby.")
		self._replaying = false
		self._hiding = false
		self:_hide(true)
	end)
end

-- Keep tweens from fighting: each show/hide takes a fresh token; stale callbacks bail.
function RaceUIController._tween(self, inst, time, props, style: Enum.EasingStyle?)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(inst, info, props)
	table.insert(self._tweens, tween)
	tween:Play()
	return tween
end

--[[ Stop everything still moving. THE TOKEN IS NOT ENOUGH ON ITS OWN: it fences the code that
	*starts* a tween, but a tween already in flight goes on writing its property every frame no
	matter what anyone else does with it. So a results beat interrupted inside its first half second
	— a new race entered off the back of the last one — would have its divider tween finish over the
	top of the reset that was supposed to clear it, and leave a coloured hairline lying across the
	entering screen. Cancelled here, then overwritten by the repaint that follows. ]]
function RaceUIController._cancelTweens(self)
	for _, tween in self._tweens do
		tween:Cancel()
	end
	table.clear(self._tweens)
end

-- === The trophy car =========================================================

local BODY_FOLDER = "Body" -- the child of a rigged car holding the visual dress (CarBody)
local HULL_NAME = "HitBox" -- ...which also holds the chassis's own invisible hull, and that is not dress

--[[ Everything in a cloned dress that can tie one of its parts to a part outside it.

	THE FOUR CLASSES ARE NOT ONE FAMILY, which is why this is a list rather than an `IsA` or two:
	`WeldConstraint` and `NoCollisionConstraint` descend from `Instance` DIRECTLY and are neither
	`JointInstance` nor `Constraint`, whatever their names suggest. `WeldConstraint` is the one class
	that matters here — it is what every panel of a redressed body is held to `Chassis.RedressMount`
	with — so the obvious two-clause test would walk straight past the only one worth catching.

	Cloned, those welds still point at the LIVE car's chassis (Roblox only remaps references that land
	inside the cloned subtree), so the copy arrives joined to a car that is about to be destroyed under
	it. Same list, same reason, as `GarageService.tiesToAnotherPart`. ]]
local function tiesToAnotherPart(inst: Instance): boolean
	return inst:IsA("JointInstance")
		or inst:IsA("Constraint")
		or inst:IsA("WeldConstraint")
		or inst:IsA("NoCollisionConstraint")
end

-- Half-extents of a box along the axes of the frame it is measured in — the conservative enclosing
-- box for a rotated part, which is the right way to be wrong about something you are framing a shot
-- around. Same composition GetawayController bounds the truck's load zone with.
local function projectHalf(cf: CFrame, size: Vector3): Vector3
	local h = size * 0.5
	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	return Vector3.new(
		math.abs(x.X) * h.X + math.abs(y.X) * h.Y + math.abs(z.X) * h.Z,
		math.abs(x.Y) * h.X + math.abs(y.Y) * h.Y + math.abs(z.Y) * h.Z,
		math.abs(x.Z) * h.X + math.abs(y.Z) * h.Y + math.abs(z.Z) * h.Z
	)
end

--[[ Strip a cloned dress down to inert parts and re-express every one of them in `frame`.

	ONE COPY FOR THREE SHOTS. The trophy, the cruiser and the wreck are the same operation on the
	same kind of thing, a model about to be parented under `PlayerGui` and looked at by a camera,
	and the only thing that differs between them is the frame everything is measured in.

	WHAT GOES: anything that can tie a part to a part OUTSIDE the clone (see `tiesToAnotherPart`,
	because a cloned weld still points at the live car it was taken from), plus scripts and sounds,
	because this ends up under `PlayerGui` where a `LocalScript` would actually run and a `Sound`
	would actually play. Nothing else in a dress can act on its own: a ViewportFrame renders no
	particles, beams or lights, which is the whole reason `THE PLUME` exists. ]]
local function stripDress(clone: Instance, frame: CFrame): { [BasePart]: CFrame }
	local offsets: { [BasePart]: CFrame } = {}
	for _, descendant in clone:GetDescendants() do
		if tiesToAnotherPart(descendant) or descendant:IsA("LuaSourceContainer") or descendant:IsA("Sound") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			offsets[descendant] = frame * descendant.CFrame
		end
	end
	return offsets
end

--[[ The box a set of placed parts fills, in whatever frame they were placed in. `nil, nil` for a
	dress of no parts at all, which is nothing to show and nothing to frame a camera on.

	SEPARATE FROM THE STRIP ABOVE BECAUSE THE WRECK MEASURES TWICE: once standing up, to find out
	where its own nose is, and again once it has been folded and rolled, because a car that has gone
	over no longer fills the box it was measured in. ]]
local function boundsOf(offsets: { [BasePart]: CFrame }): (Vector3?, Vector3?)
	local low: Vector3?, high: Vector3? = nil, nil
	for part, offset in offsets do
		local half = projectHalf(offset, part.Size)
		low = if low then low:Min(offset.Position - half) else offset.Position - half
		high = if high then high:Max(offset.Position + half) else offset.Position + half
	end
	return low, high
end


-- Drop the car and put the frame back the way `_build` left it. Safe before `_build` and safe twice.
function RaceUIController._clearTrophy(self)
	self._trophyBuildToken = (self._trophyBuildToken or 0) + 1
	if self._trophyCar then
		self._trophyCar:Destroy()
		self._trophyCar = nil
	end
	self._trophyDistance = nil
	self._trophyPitch = nil
	self._bustLamps = nil
	self._slotWreck = false
	if self._trophy then
		self._trophy.Visible = false
		--- `_trophyRest` is `TROPHY_SIZE` on the overlay and the authored box on the kit panel.
		self._trophy.Size = UDim2.fromScale(self._trophyRest, self._trophyRest)
		self._burst.ImageTransparency = 1
		self._viewport.ImageTransparency = 1
		--- ...and the key light goes back to the trophy's, which is what this frame was built
		--- with. Put back by whoever has FINISHED with it rather than set by whoever is about to
		--- use it, so a wreck can never leave its cold light on the next getaway's car.
		self._viewport.Ambient = CAR_AMBIENT
		self._viewport.LightColor = CAR_LIGHT
		self._viewport.LightDirection = CAR_LIGHT_DIR
	end
end

--[[ How far back the camera has to sit to hold a box of `size` inside the frame.

	FRAMED OFF THE WORST CASE OVER THE WHOLE TURN, not off what happens to be facing us. A car is
	nearly twice as long as it is wide, so a distance fitted to the current angle would have the car
	swelling and shrinking as it came broadside — which reads as the camera lurching, and is the one
	failure a turntable shot must not have. The horizontal term is therefore the diagonal of the
	footprint (the largest half-width ANY yaw can present) and the vertical term is the height plus
	what the camera's own tilt folds of that footprint into the vertical.

	The viewport is square, so one FOV covers both axes and the larger of the two needs wins.

	THE PITCH AND THE MARGIN ARE ARGUMENTS because the two shots this slot holds do not share them
	(see `THE CRUISER`), and the pitch is used through `abs`: a camera six degrees BELOW a car folds
	exactly as much of its footprint into the vertical as one six degrees above it, and a signed
	term would quietly frame the low shot as though the car were flatter than it is. ]]
function RaceUIController._frameDistance(self, size: Vector3, pitchDeg: number, margin: number): number
	local horizontal = math.sqrt(size.X * size.X + size.Z * size.Z) / 2
	local pitch = math.rad(pitchDeg)
	local vertical = size.Y / 2 * math.cos(pitch) + horizontal * math.abs(math.sin(pitch))
	return math.max(horizontal, vertical) / math.tan(math.rad(CAR_FOV) / 2) * margin
end

--[[ Point the viewport camera at the car for this frame.

	THE CAMERA ORBITS; THE CAR NEVER MOVES. That is not a preference — the clone has no PrimaryPart,
	so its pivot is its own bounding-box centre, and `Model:PivotTo` preserves each child's offset
	rather than resetting it. Re-posing a model that way every frame therefore COMPOUNDS: the pivot
	is re-derived from geometry that the last write already turned, and the car winds itself up.
	One camera CFrame per frame has no state at all, and looks identical. ]]
function RaceUIController._aimTrophy(self)
	local camera, distance = self._camera, self._trophyDistance
	if not (camera and distance) then
		return
	end
	local yaw, pitch = math.rad(self._carAngle or CAR_YAW), math.rad(self._trophyPitch or CAR_PITCH)
	local eye = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
	camera.CFrame = CFrame.lookAt(eye * distance, Vector3.zero)
end

--[[ Public (GetawayController): this is the car that just got away — show it on the results screen.

	CALLED AT THE BANK, which is several seconds before there is a screen to put it on, and that is
	the point: the bank is the last moment the car exists. `RaceService.bankRun` cuts the controls on
	the same frame and destroys the car once the return fade has run, so a results screen that went
	looking for it would find nothing every time.

	WHAT IS TAKEN IS THE DRESS, NOT THE CAR. `Body/` is the whole of what a car looks like (the
	chassis under it is shared by every car in the game and invisible), so a stripped clone of it is
	the cheapest complete likeness available — and because it is a clone of the thing the player was
	just driving, it carries that car's exact meshes and exact paint with nothing having to be looked
	up, asked for, or replicated. The `HitBox` is dropped because it is the chassis's invisible hull
	rather than bodywork, and leaving it in would frame the shot around a box the player cannot see.

	SCRIPTS AND SOUNDS GO TOO. This ends up parented under `PlayerGui`, where a `LocalScript` that
	came along for the ride would actually run and a `Sound` would actually play. Nothing else in a
	dress can act on its own — a ViewportFrame renders no particles, beams or lights — so those two
	are the whole list.

	Everything is re-expressed in the car's own frame and re-centred on its bounding box, so the
	turntable below can be pure trigonometry against the origin. ]]
--- PUBLIC (`TestEngineController`): is the entry's loading screen up? The car is already built and
--- the driver seated under it, so anything that sounds off the seat has to ask.
function RaceUIController.isLoading(self): boolean
	return self._loading == true and self._visible == true
end

function RaceUIController.setTrophy(self, car: Model?)
	self:_clearTrophy()
	local buildToken = self._trophyBuildToken
	if not self._gui then
		self:_build()
	end
	if not (car and car.Parent) then
		return
	end
	local body = car:FindFirstChild(BODY_FOLDER)
	if not body then
		self.log:warn("The banked car has no Body folder, so the results screen has no car to show.")
		return
	end

	-- Capture immutable source poses now, while the live car still exists. The expensive clones and
	-- property writes are spread through the truck's hold instead of sharing the entry frame.
	local inverse = car:GetPivot():Inverse()
	local sources = {}
	for _, source in body:GetDescendants() do
		if source:IsA("BasePart") and source.Name ~= HULL_NAME then
			table.insert(sources, { source = source, offset = inverse * source.CFrame })
		end
	end

	task.spawn(function()
		local clone = Instance.new("Model")
		clone.Name = "TrophyCar"
		local parts = {}
		local low: Vector3?, high: Vector3? = nil, nil

		for index, record in sources do
			if self._trophyBuildToken ~= buildToken then
				clone:Destroy()
				return
			end

			local copy = record.source:Clone()
			for _, descendant in copy:GetDescendants() do
				if tiesToAnotherPart(descendant) or descendant:IsA("LuaSourceContainer") or descendant:IsA("Sound") then
					descendant:Destroy()
				end
			end
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.CastShadow = false
			copy.CFrame = record.offset
			copy.Parent = clone
			table.insert(parts, { part = copy, offset = record.offset })

			local half = projectHalf(record.offset, copy.Size)
			low = if low then low:Min(record.offset.Position - half) else record.offset.Position - half
			high = if high then high:Max(record.offset.Position + half) else record.offset.Position + half

			if index % TROPHY_BUILD_BUDGET == 0 then
				task.wait()
			end
		end

		if not (low and high) then
			clone:Destroy()
			return
		end
		local centre = (low + high) / 2
		for index, record in parts do
			record.part.CFrame = CFrame.new(-centre) * record.offset
			if index % TROPHY_BUILD_BUDGET == 0 then
				task.wait()
			end
		end

		if self._trophyBuildToken ~= buildToken then
			clone:Destroy()
			return
		end
		clone.Parent = self._viewport
		self._trophyCar = clone
		self._trophyPitch = CAR_PITCH
		self._trophyDistance = self:_frameDistance(high - low, CAR_PITCH, CAR_MARGIN)
		self._carAngle = CAR_YAW
		self._burstAngle = 0
		self:_aimTrophy()
	end)
end

--[[ ...and the other thing this slot can hold: the cruiser that just took the car back.

	IT IS LOOKED UP RATHER THAN HANDED IN, which is the opposite of `setTrophy` above and is right
	for the opposite reason. The stolen car has to be handed in because it is about to be destroyed
	and there is exactly one of it; the cruiser is a published template that never changes and is
	sitting in `ReplicatedStorage` for the whole session (`PoliceService` puts it there so every
	client has something cheap to clone). There is nothing to catch and no moment to catch it in.

	Found by `PoliceConfig`'s own names, exactly the way `PoliceController` finds it, rather than by
	asking that controller for it: this runs seconds after a chase has finished, so the folder is
	long since published, and a lookup has no boot-order question in it at all (`Shard.start` does
	not order controllers against each other).

	A MISSING TEMPLATE IS NOT AN ERROR. Police can be switched off, and a place that never published
	the models runs races without a chase — in which case no bust can happen either. This answers
	false and the screen is the word and the lights, which is exactly the screen that shipped before
	the car was on it.

	It reuses `_trophyCar`, so the whole teardown, the fade and the reset it already has apply to it
	unchanged; the only thing held apart is the pose. ]]
function RaceUIController._showBustCar(self): boolean
	self:_clearTrophy()
	local cruiser = self:_buildCruiser()
	if not cruiser then
		return false
	end
	cruiser.model.Parent = self._viewport
	self._trophyCar = cruiser.model
	self._bustLamps = cruiser.lamps
	self._trophyPitch = BUST_CAR_PITCH
	self._trophyDistance = cruiser.distance
	--- Set once and never advanced: the cruiser is held, not turned. See `THE CRUISER`.
	self._carAngle = BUST_CAR_YAW
	self:_aimTrophy()
	return true
end

--[[ The cruiser and its light bar, centred on the origin and framed, parented nowhere. Answers
	`{ model, lamps, distance }`, or nil when there is no cruiser to show. Split out of `_showBustCar`
	so the end panel (`buildEndShot`) can stand one in its own box. ]]
function RaceUIController._buildCruiser(self)
	if not PoliceConfig.Hud.Bust.Enabled then
		return nil
	end

	local folder = ReplicatedStorage:FindFirstChild(PoliceConfig.TemplateFolderName)
	local template = folder and folder:FindFirstChild(PoliceConfig.TemplateNames.Car)
	if not (template and template:IsA("Model")) then
		return nil
	end

	local clone = template:Clone()
	clone.Name = "BustCar"
	local root = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		clone:Destroy()
		return nil
	end

	--[[ THE LIGHT BAR, built before the measuring below so it is framed as part of the car rather
		than left hanging outside the shot. Same offsets, same colours and same sides as the lamps
		on a cruiser in a live chase (`PoliceController._buildBar`), because it IS that light bar:
		red on the mesh's -Z half and blue on its +Z, which is how the mesh is painted.

		NO `PointLight` TO GO WITH THEM, and not as an oversight: a `ViewportFrame` renders no
		lights at all, so the spill a cruiser throws on the road has nowhere to land here. What
		does survive is `Neon`, which is what the lamps read by. ]]
	local bar = PoliceConfig.Cruisers.Bar
	local lamps = {}
	for _, side in { { sign = -1, colour = bar.Red, red = true }, { sign = 1, colour = bar.Blue, red = false } } do
		local lamp = Instance.new("Part")
		lamp.Name = if side.red then "LampRed" else "LampBlue"
		lamp.Size = bar.Size
		lamp.CFrame = root.CFrame * CFrame.new(bar.X, bar.Y, bar.Z * side.sign)
		lamp.Material = Enum.Material.Neon
		lamp.Color = side.colour
		--- Built UNLIT, because `Instance.new` hands out a transparency of zero and `_stepLights`
		--- does not run until the next rendered frame: left at the default, both lamps are at full
		--- brightness for exactly one frame of a light bar that is meant to alternate.
		lamp.Transparency = bar.OffTransparency
		lamp.Parent = clone
		table.insert(lamps, { part = lamp, red = side.red })
	end

	--[[ Re-expressed into the ROOT's frame and then turned to face the camera's convention, which is
		the one piece of art knowledge in here and is a rotation rather than a guess: this mesh has
		its nose along its part's local +X (`PoliceConfig.Cruisers.NoseYawDeg`, measured by rendering
		it head on), and every angle on this screen is written as though a car's nose were -Z. Same
		correction `PoliceController` applies to put a cruiser's nose down the road.

		Everything after that is `setTrophy`'s own treatment, for its own reasons: anchored and
		inert because this ends up under `PlayerGui`, and re-centred on its bounding box so the
		camera below can be pure trigonometry against the origin. ]]
	local base = root.CFrame
	local nose = CFrame.Angles(0, math.rad(PoliceConfig.Cruisers.NoseYawDeg), 0)
	local offsets = stripDress(clone, nose * base:Inverse())
	local low, high = boundsOf(offsets)
	if not (low and high) then
		clone:Destroy()
		return nil
	end

	local centre = (low + high) / 2
	for part, offset in offsets do
		part.CFrame = CFrame.new(-centre) * offset
	end

	return { model = clone, lamps = lamps, distance = self:_frameDistance(high - low, BUST_CAR_PITCH, BUST_CAR_MARGIN) }
end

--[[ Fold the car up. Everything here happens in the CAR'S OWN FRAME, where the nose is local -Z,
	the roof is +Y and +X is the driver's right. That is the convention every angle on this screen is
	written in and the reason `CAR_YAW` can say that 180 is nose-on.

	TWO PASSES OVER ONE SET OF OFFSETS, AND THE ORDER IS THE POINT. The crumple is worked out against
	a car that is standing up, because "how far forward does this panel sit" is a question about a
	car rather than about a wreck. The cant goes on afterwards, over the whole result, because it is
	the ground doing that rather than the crash. Done the other way round the fold is measured along
	a tilted axis and the nose is driven into the floor instead of into the engine bay.

	RANDOM PER WRECK AND FIXED WITHIN ONE. Two wrecks should not be the same photograph and one
	wreck must not shimmer, so the rolls happen once, here, and are baked into the CFrames. ]]
function RaceUIController._mangle(self, offsets: { [BasePart]: CFrame }, low: Vector3, high: Vector3)
	local rng = Random.new()
	local halfLength = math.max((high.Z - low.Z) / 2, 0.001)

	--[[ The wheels first, and as GROUPS. Gathered by walking UP from each part rather than down from
		the model, because a dress nests them (`FL/tire`, `FL/LF_wheel_cap_body`) and the group is
		the only thing that knows those three parts are one wheel. See `WRECK_WHEELS`. ]]
	local groups: { [Instance]: { BasePart } } = {}
	for part in offsets do
		local node: Instance? = part.Parent
		while node do
			if node:IsA("Model") and WRECK_WHEELS[node.Name] then
				local bucket = groups[node]
				if bucket then
					table.insert(bucket, part)
				else
					groups[node] = { part }
				end
				break
			end
			node = node.Parent
		end
	end

	local wheeled: { [BasePart]: boolean } = {}
	for _, parts in groups do
		local centre = Vector3.zero
		for _, part in parts do
			centre += offsets[part].Position
		end
		centre /= #parts
		--- Front wheels only. The fold is at the nose and so is the damage; a rear corner that had
		--- collapsed too would say the car was hit twice.
		if centre.Z >= 0 then
			continue
		end
		--[[ The top of the wheel tucks INWARD, which is what a corner looks like once the
			suspension has folded. The sign is which side of the car it is on: one rotation about the
			LENGTH of the car leans the two sides opposite ways, so both wheels want the same
			magnitude and opposite signs to lean the same way relative to the body. ]]
		local side = if centre.X >= 0 then 1 else -1
		local knock = CFrame.new(centre + Vector3.new(0, -WRECK_WHEEL_SINK, 0))
			* CFrame.Angles(0, 0, math.rad(WRECK_WHEEL_CAMBER * side))
			* CFrame.new(-centre)
		for _, part in parts do
			offsets[part] = knock * offsets[part]
			wheeled[part] = true
		end
	end

	--- Then the nose. Wheels are skipped because they have just had their own treatment, and a
	--- cambered wheel shoved backwards as well would climb out through the arch.
	for part, offset in offsets do
		if wheeled[part] then
			continue
		end
		local position = offset.Position
		--- 0 behind the crush line and 1 at the very tip, squared below so the fold gathers at the
		--- nose rather than spreading evenly down a car that only hit one thing.
		local reach = math.clamp((-position.Z / halfLength - WRECK_CRUSH_FROM) / (1 - WRECK_CRUSH_FROM), 0, 1)
		if reach <= 0 then
			continue
		end
		local weight = reach * reach
		local shove = Vector3.new(
			rng:NextNumber(-1, 1) * WRECK_CRUSH_SCATTER * reach,
			-WRECK_CRUSH_DROP * weight,
			WRECK_CRUSH_DEPTH * weight
		)
		local twist = CFrame.Angles(
			math.rad(rng:NextNumber(-1, 1) * WRECK_CRUSH_TWIST * reach),
			math.rad(rng:NextNumber(-1, 1) * WRECK_CRUSH_TWIST * reach),
			math.rad(rng:NextNumber(-1, 1) * WRECK_CRUSH_TWIST * reach)
		)
		--- Turned about the panel's OWN middle, so a knocked panel twists where it sits instead of
		--- swinging round the centre of the car like a door.
		offsets[part] = CFrame.new(position + shove) * twist * (offset - position)
	end

	--- ...and then the ground, over everything including the wheels, because this is the car having
	--- gone over rather than any part of it having moved.
	local cant = CFrame.Angles(math.rad(-WRECK_NOSE_DOWN), 0, 0) * CFrame.Angles(0, 0, math.rad(WRECK_ROLL))
	for part, offset in offsets do
		offsets[part] = cant * offset
	end
end

--[[ Fold a stripped dress up, frame a camera on what is left, and stand it in the slot. Answers
	whether there was anything to stand there.

	`frame` IS WHAT THE PARTS ARE MEASURED AGAINST and it is the only thing the two callers disagree
	about: a live car hands in its own pivot, and the admin preview hands in a published traffic
	shell's `Root`. Both put the nose down local -Z, which is the whole of what `_mangle` needs. ]]
function RaceUIController._wreckFrom(self, clone: Model, frame: CFrame): boolean
	local offsets = stripDress(clone, frame)
	local low, high = boundsOf(offsets)
	if not (low and high) then
		clone:Destroy()
		return false
	end

	self:_mangle(offsets, low, high)

	--[[ Measured AGAIN, and centred on what the car has become rather than on what it was. The cant
		moves the silhouette by more than the crumple does, since a body rolled twenty degrees is
		taller and narrower than the one measured a moment ago, and a camera framed on the old box
		leaves the wreck sitting low and off-centre with air above it. ]]
	local folded, foldedHigh = boundsOf(offsets)
	if not (folded and foldedHigh) then
		clone:Destroy()
		return false
	end
	local centre = (folded + foldedHigh) / 2
	for part, offset in offsets do
		part.CFrame = CFrame.new(-centre) * offset
	end

	clone.Parent = self._viewport
	self._trophyCar = clone
	self._slotWreck = true
	self._trophyPitch = WRECK_CAR_PITCH
	self._trophyDistance = self:_frameDistance(foldedHigh - folded, WRECK_CAR_PITCH, WRECK_CAR_MARGIN)
	--- Set once and never advanced. A wreck is not a prize and does not turn, which is the argument
	--- `THE CRUISER` makes at length and this shot inherits whole.
	self._carAngle = WRECK_CAR_YAW
	self:_aimTrophy()

	--- Its own key light, and this is the line where the three shots stop sharing one. See
	--- `WRECK_AMBIENT`; `_clearTrophy` is what puts it back.
	local viewport = self._viewport
	viewport.Ambient = WRECK_AMBIENT
	viewport.LightColor = WRECK_LIGHT
	viewport.LightDirection = WRECK_LIGHT_DIR
	return true
end

--[[ Public (ObstacleController): this is the car the run ended in, so show what is left of it.

	CALLED AT THE WRECK, on the same line of `_onWrecked` that grows the plume on the real car, and
	that placement is a contract rather than a convenience. `_onWrecked` has already decided which
	endings have a car worth looking at: a bail whiffed onto the tarmac and a fall out of the world
	do not, and a police bust has a car but has the cruiser to show instead. Handing it in from there
	means the screen and the world can never disagree about whether there was a wreck to see.

	IT IS ALSO THE LAST MOMENT THE CAR EXISTS, exactly as the bank is for `setTrophy`: `RaceService`
	teleports the player home behind the return fade and destroys the car on the way, seconds before
	the screen that wants it goes up. What is taken is the DRESS rather than the car, for the reasons
	that function gives at length, and it carries the exact body and the exact paint the player was
	driving with nothing having to be looked up or asked for.

	IT REUSES `_trophyCar`, so the teardown, the fade, the framing and the reset all apply to it
	unchanged. `_slotWreck` is the one thing held apart, because `_show` has to know which of the
	three things the slot is holding before it can decide what to draw around it. ]]
function RaceUIController.setWreck(self, car: Model?)
	self:_clearTrophy()
	if not self._gui then
		self:_build()
	end
	if not (car and car.Parent) then
		return
	end
	local body = car:FindFirstChild(BODY_FOLDER)
	if not body then
		self.log:warn("The wrecked car has no Body folder, so the results screen has no car to show.")
		return
	end

	local clone = body:Clone()
	clone.Name = "WreckCar"
	local hull = clone:FindFirstChild(HULL_NAME, true)
	if hull then
		hull:Destroy() -- the chassis's invisible hull rather than bodywork. See `setTrophy`.
	end
	self:_wreckFrom(clone, car:GetPivot():Inverse())
end

--[[ Public (ObstacleController): they paid to carry on, so there is no wreck to show.

	THE EXACT INVERSE OF THE HAND-IN ABOVE, AND IT HAS TO EXIST. `RaceService.reviveRace` states the
	rule this is an instance of: a `RaceWrecked` reaction with no `RaceRevived` inverse is a reaction
	that stays switched on for the rest of the run. Left in place, this one is a wreck of the car
	they are still driving, sitting in the slot waiting to be shown on whatever ends the run next. ]]
function RaceUIController.clearWreck(self)
	if self._slotWreck then
		self:_clearTrophy()
	end
end

--[[ Public (ReviveController): the wreck caught by `setWreck`, as a shot of its own in `parent`.

	THE ONE-SCREEN WRECK (`NewUIConfig.WreckPanel`) shows the car on the revive panel, seconds before
	this screen would have, and this screen is then skipped. So the panel borrows the shot rather than
	building a second likeness: a COPY of the folded dress in a ViewportFrame of its own, framed by the
	numbers `_wreckFrom` already worked out, under the wreck's own light, with the same plume. The
	trophy slot keeps its copy, so a fallback to this screen (a server timeout the client never
	answered) still has the car.

	`options.backdrop` is what the shot stands on, for the edge reason `viewport.BackgroundColor3`
	gives in `_build`.

	`options.smoke`, `options.strength` and `options.layers` re-pitch the same plume for what it is
	drawn over. On the black overlay a puff at full weight is plenty; over the kit's bright panel and a
	lit sky the texture's own alpha is so low that even an opaque puff barely registers (measured:
	fully opaque and tinted red, it was a faint pink smudge). So each puff is drawn `layers` times,
	stacked and turned so no two copies show the same blob, which compounds the alpha the way the
	seven overlapping puffs already do on black. Same texture, same motion, same look. Answers nil when there is
	no wreck to show (a bail on the tarmac, a fall); otherwise a handle whose `step(t)` drives the
	smoke and whose `destroy()` takes everything away. ]]
function RaceUIController.buildWreckShot(
	self,
	parent: GuiObject,
	options: { backdrop: Color3, smoke: Color3?, strength: number?, layers: number? }
)
	local car, distance = self._trophyCar, self._trophyDistance
	if not (self._slotWreck and car and distance) then
		return nil
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "WreckShot"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.BackgroundColor3 = options.backdrop
	viewport.BorderSizePixel = 0
	viewport.Ambient = WRECK_AMBIENT
	viewport.LightColor = WRECK_LIGHT
	viewport.LightDirection = WRECK_LIGHT_DIR
	viewport.ZIndex = 2

	local camera = Instance.new("Camera")
	camera.FieldOfView = CAR_FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	-- Held still, like the slot's own wreck. `_aimTrophy` has the orbit; this is one frame of it.
	local yaw, pitch = math.rad(WRECK_CAR_YAW), math.rad(self._trophyPitch or WRECK_CAR_PITCH)
	local eye = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
	camera.CFrame = CFrame.lookAt(eye * distance, Vector3.zero)

	car:Clone().Parent = viewport
	viewport.Parent = parent
	local puffs = buildPuffs(parent)
	-- The extra copies ride inside their puff, so its position, growth and spin carry them.
	local copies = {}
	for _, puff in puffs do
		local image = puff.image
		if options.smoke then
			image.ImageColor3 = options.smoke
		end
		for layer = 2, options.layers or 1 do
			local copy = Instance.new("ImageLabel")
			copy.Name = "Layer"
			copy.BackgroundTransparency = 1
			copy.Size = UDim2.fromScale(1, 1)
			copy.Image = image.Image
			copy.ImageColor3 = image.ImageColor3
			copy.ImageTransparency = 1
			copy.Rotation = (layer - 1) * 73
			copy.ZIndex = image.ZIndex
			copy.Parent = image
			table.insert(copies, { from = image, copy = copy })
		end
	end

	return {
		step = function(t: number)
			stepPuffs(puffs, t, options.strength or 1)
			for _, pair in copies do
				pair.copy.ImageTransparency = pair.from.ImageTransparency
			end
		end,
		destroy = function()
			viewport:Destroy()
			for _, puff in puffs do
				puff.image:Destroy()
			end
		end,
	}
end

--- Public (ReviveController): the ladder bar's plan for a run of `studs`, measured against the road
--- that is still standing under the wreck. `_planLadder` has the arithmetic; nil means "no bar".
function RaceUIController.planLadder(self, studs: number)
	self:_latchRoad()
	return self:_planLadder(studs)
end

--- Public (ReviveController): the last `RunSettled` and `CarLeveled`, which the end panel reports.
function RaceUIController.lastRun(self)
	return self._summary, self._leveled
end

--[[ The end panel's shot helpers and numbers, in one table: this file is at Luau's ceiling of
	200 locals in one scope, so anything new at the top level goes in here. ]]
local EndShot = {}

--[[ === THE END PANEL'S SHOT =================================================================

	Public (ReviveController): the picture in the corner of the end panel, for whichever ending this
	is. `options.ending` is "bank" or "wreck", `options.cause` is the wreck's cause, and the rest is
	`buildWreckShot`'s. Answers a `{ step(t), destroy() }` handle, or nil for nothing to show.

	  • A GETAWAY is the car you kept, turning on the sunburst, which is the old results screen's
	    trophy in a box of its own.
	  • A BUST is the cruiser, its light bar running.
	  • A WRECK with a car caught by `setWreck` is that wreck, smoking (`buildWreckShot`).
	  • ANY OTHER ENDING is you: a bad landing is the flight avatar exactly as it fell, and anything
	    else with no car to show (a fall) is your character, laid out by `EndShot.Sprawl`. ]]
function RaceUIController.buildEndShot(
	self,
	parent: GuiObject,
	options: { ending: string, cause: string?, backdrop: Color3, smoke: Color3?, strength: number?, layers: number? }
)
	if options.ending == "bank" then
		return self:_bankShot(parent, options)
	end
	if options.cause == PoliceConfig.Cause then
		return self:_bustShot(parent, options)
	end
	if self._slotWreck then
		return self:buildWreckShot(parent, options)
	end
	return self:_riderShot(parent, options)
end

-- A box of its own for a shot: the viewport, its camera, and the key light it is lit by.
function EndShot.box(parent: GuiObject, name: string, backdrop: Color3, ambient: Color3, light: Color3, direction: Vector3): (ViewportFrame, Camera)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = name
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.BackgroundColor3 = backdrop
	viewport.BorderSizePixel = 0
	viewport.Ambient = ambient
	viewport.LightColor = light
	viewport.LightDirection = direction
	viewport.ZIndex = 2
	local camera = Instance.new("Camera")
	camera.FieldOfView = CAR_FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = parent
	return viewport, camera
end

-- `_aimTrophy`'s orbit, as one write: a camera `distance` out at `yaw`/`pitch`, on the origin.
function EndShot.orbit(camera: Camera, yawDeg: number, pitchDeg: number, distance: number)
	local yaw, pitch = math.rad(yawDeg), math.rad(pitchDeg)
	local eye = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
	camera.CFrame = CFrame.lookAt(eye * distance, Vector3.zero)
end

--[[ How much of the end panel's box the sunburst fills behind the getaway car, and how far it fades
	in. Bigger than the box so the rays run off its edges, and fainter than on the black because
	white rays over the kit's blue carry further. ]]
EndShot.BurstScale = 1.25
EndShot.BurstRest = 0.6
--[[ The trophy's framing is for the old screen's square box and a car turning through its widest
	angle; the panel's box is wider than tall and sits on the corner, so the camera comes in closer. ]]
EndShot.BankCloser = 0.8

function RaceUIController._bankShot(self, parent: GuiObject, options)
	local car, distance = self._trophyCar, self._trophyDistance
	if not (car and distance) or self._slotWreck or self._bustLamps then
		return nil
	end
	distance *= EndShot.BankCloser
	local burst = Instance.new("ImageLabel")
	burst.Name = "Sunburst"
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromScale(EndShot.BurstScale, EndShot.BurstScale)
	burst.BackgroundTransparency = 1
	burst.Image = UIAssets.url(UIAssets.Results.Sunburst)
	burst.ImageColor3 = SUNBURST_COLOR
	burst.ImageTransparency = EndShot.BurstRest
	burst.ZIndex = 1
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = burst
	burst.Parent = parent

	local viewport, camera = EndShot.box(parent, "BankShot", options.backdrop, CAR_AMBIENT, CAR_LIGHT, CAR_LIGHT_DIR)
	car:Clone().Parent = viewport
	local pitch = self._trophyPitch or CAR_PITCH
	EndShot.orbit(camera, CAR_YAW, pitch, distance)
	return {
		step = function(t: number)
			EndShot.orbit(camera, CAR_YAW + t * CAR_SPIN, pitch, distance)
			burst.Rotation = (t * SUNBURST_SPIN) % 360
		end,
		destroy = function()
			viewport:Destroy()
			burst:Destroy()
		end,
	}
end

function RaceUIController._bustShot(self, parent: GuiObject, options)
	local cruiser = self:_buildCruiser()
	if not cruiser then
		return nil
	end
	local viewport, camera = EndShot.box(parent, "BustShot", options.backdrop, CAR_AMBIENT, CAR_LIGHT, CAR_LIGHT_DIR)
	cruiser.model.Parent = viewport
	EndShot.orbit(camera, BUST_CAR_YAW, BUST_CAR_PITCH, cruiser.distance)
	local off = PoliceConfig.Cruisers.Bar.OffTransparency
	local glowCfg = PoliceConfig.Hud.Bust.PanelGlow
	local glows = {}
	if glowCfg and glowCfg.Enabled then
		for _, lamp in cruiser.lamps do
			table.insert(glows, { lamp = lamp, blob = EndShot.glow(parent, lamp.part.Color, glowCfg.Size) })
		end
	end
	return {
		-- The bar, on the bust screen's own pattern (`_stepLights` paints the same two numbers).
		step = function(t: number)
			local red, blue = PoliceConfig.bustFlash(t)
			for _, lamp in cruiser.lamps do
				lamp.part.Transparency = off * (1 - (if lamp.red then red else blue))
			end
			--- The blooms sit on the lamps as the box draws them, which needs the box's real size,
			--- so they are placed on the first frame it has one (the car and camera never move).
			local size = viewport.AbsoluteSize
			for _, glow in glows do
				if not glow.placed and size.Y > 0 then
					glow.blob.Position = EndShot.project(camera, size, glow.lamp.part.Position)
					glow.placed = true
				end
				--- `Gain` for the same reason the old screen's wash takes it: the blue reads at half the red.
				local gain = PoliceConfig.Hud.Bust.Gain
				local lit = if glow.lamp.red then red * gain.Red else blue * gain.Blue
				glow.blob.GroupTransparency = 1 - math.clamp(lit * glowCfg.Max, 0, 1)
			end
		end,
		destroy = function()
			viewport:Destroy()
			for _, glow in glows do
				glow.blob:Destroy()
			end
		end,
	}
end

--[[ A soft round bloom of `colour`, `size` of its parent's height across, drawn over a viewport,
	because a viewport renders no lights (`_buildCruiser`). There is no soft-disc texture to hand, so
	it is two linear fades multiplied: a horizontal one on the white fill and a vertical one on the
	CanvasGroup holding it, tinted by `GroupColor3`. Starts dark; `GroupTransparency` is the dial. ]]
EndShot.GlowFade = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.1, 0.95),
	NumberSequenceKeypoint.new(0.2, 0.8),
	NumberSequenceKeypoint.new(0.3, 0.55),
	NumberSequenceKeypoint.new(0.4, 0.2),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.6, 0.2),
	NumberSequenceKeypoint.new(0.7, 0.55),
	NumberSequenceKeypoint.new(0.8, 0.8),
	NumberSequenceKeypoint.new(0.9, 0.95),
	NumberSequenceKeypoint.new(1, 1),
})

function EndShot.glow(parent: GuiObject, colour: Color3, size: number): CanvasGroup
	local group = Instance.new("CanvasGroup")
	group.Name = "LampGlow"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.5)
	group.Size = UDim2.fromScale(size, size)
	group.SizeConstraint = Enum.SizeConstraint.RelativeYY
	group.BackgroundTransparency = 1
	group.GroupColor3 = colour
	group.GroupTransparency = 1
	group.ZIndex = 3
	local vertical = Instance.new("UIGradient")
	vertical.Rotation = 90
	vertical.Transparency = EndShot.GlowFade
	vertical.Parent = group
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	local horizontal = Instance.new("UIGradient")
	horizontal.Transparency = EndShot.GlowFade
	horizontal.Parent = fill
	fill.Parent = group
	group.Parent = parent
	return group
end

-- Where a point in a shot's viewport lands in the box, as a scale position the box's children use.
function EndShot.project(camera: Camera, size: Vector2, point: Vector3): UDim2
	local p = camera.CFrame:PointToObjectSpace(point)
	local depth = math.max(-p.Z, 1e-3)
	local half = math.tan(math.rad(camera.FieldOfView) / 2)
	local x = p.X / depth / (half * size.X / size.Y)
	local y = p.Y / depth / half
	return UDim2.fromScale(0.5 + x / 2, 0.5 - y / 2)
end

--[[ === THE RIDER: a ragdoll in the box ======================================================

	A BAD LANDING HAS A REAL ONE. `StealController` keeps the flight avatar lying where it hit the
	tarmac until the race is torn down (`downedAvatar`), so the shot is a still of it, the pose the
	player just watched it fall into. Its joints are ball sockets by then, so the clone is simply its
	parts where they lie.

	ANY OTHER ENDING WITH NO CAR TO SHOW (a fall out of the world) has no ragdoll, so it gets the
	character laid out on its back by hand: `EndShot.Sprawl` bends each R15 joint (an R6 rig keeps its
	pose), and `EndShot.solveRig` walks the joints from the root to put every part where those bends say.

	Either way the body is turned to lie ACROSS the box, head to the right, and looked down on, which
	is how you look at somebody on the ground. ]]
EndShot.RiderPitch = 52 -- degrees the camera looks down on the body
EndShot.RiderMargin = 0.95
EndShot.RiderAmbient = Color3.fromRGB(150, 154, 168)
EndShot.Sprawl = {
	Neck = CFrame.Angles(0, math.rad(35), math.rad(12)),
	Waist = CFrame.Angles(0, 0, math.rad(7)),
	LeftShoulder = CFrame.Angles(math.rad(-15), 0, math.rad(-105)),
	RightShoulder = CFrame.Angles(math.rad(25), 0, math.rad(70)),
	LeftElbow = CFrame.Angles(math.rad(45), 0, 0),
	RightElbow = CFrame.Angles(math.rad(25), 0, 0),
	LeftHip = CFrame.Angles(math.rad(12), 0, math.rad(-24)),
	RightHip = CFrame.Angles(math.rad(-30), 0, math.rad(18)),
	LeftKnee = CFrame.Angles(math.rad(-18), 0, 0),
	RightKnee = CFrame.Angles(math.rad(-60), 0, 0),
}

--[[ A copy of a rig that is safe to put under PlayerGui: no scripts, no sounds, no name or health
	bar. Its joints are KEPT, because a pose is solved off them (`EndShot.solveRig`); the caller
	strips them once the parts are placed. ]]
function EndShot.stillCopy(source: Model): Model?
	local archivable = source.Archivable
	source.Archivable = true
	local ok, clone = pcall(function()
		return source:Clone()
	end)
	source.Archivable = archivable
	if not (ok and clone) then
		return nil
	end
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("Sound") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			descendant.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	return clone
end

--[[ Place every part of a rig off its joints, from `root` outwards, bending each joint named in
	`poses`. A ViewportFrame solves no joints itself, so this is what a pose is in one.

	TWO KINDS OF RIG. An older one hangs off `Motor6D`s and `Weld`s (C0 and C1); the avatar joint
	upgrade this game's characters have hangs off `AnimationConstraint`s and `RigidConstraint`s
	between two attachments. Both reduce to the same thing: a frame on each part, and a bend between
	them. The rigid ones (welds, accessories) never bend, which is what carries the hats and hair. ]]
function EndShot.solveRig(model: Model, root: BasePart, poses: { [string]: CFrame })
	local edges = {}
	for _, joint in model:GetDescendants() do
		if (joint:IsA("Motor6D") or joint:IsA("Weld")) and joint.Part0 and joint.Part1 then
			table.insert(edges, { a = joint.Part0, b = joint.Part1, c0 = joint.C0, c1 = joint.C1, bends = joint:IsA("Motor6D"), name = joint.Name })
		elseif joint:IsA("AnimationConstraint") or joint:IsA("RigidConstraint") then
			local at0, at1 = joint.Attachment0, joint.Attachment1
			local a, b = at0 and at0.Parent, at1 and at1.Parent
			if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
				table.insert(edges, { a = a, b = b, c0 = at0.CFrame, c1 = at1.CFrame, bends = joint:IsA("AnimationConstraint"), name = joint.Name })
			end
		end
	end
	local placed = { [root] = true }
	local moved = true
	while moved do
		moved = false
		for _, edge in edges do
			local a, b = edge.a, edge.b
			local pose = (edge.bends and poses[edge.name]) or CFrame.identity
			if placed[a] and not placed[b] then
				b.CFrame = a.CFrame * edge.c0 * pose * edge.c1:Inverse()
				placed[b] = true
				moved = true
			elseif placed[b] and not placed[a] then
				a.CFrame = b.CFrame * edge.c1 * pose:Inverse() * edge.c0:Inverse()
				placed[a] = true
				moved = true
			end
		end
	end
end

function RaceUIController._riderShot(self, parent: GuiObject, options)
	local steal = Shard.get("StealController")
	local fallen = steal and steal.downedAvatar and steal:downedAvatar()
	local source = fallen or Players.LocalPlayer.Character
	if not source then
		return nil
	end
	local clone = EndShot.stillCopy(source)
	if not clone then
		return nil
	end
	local torso = clone:FindFirstChild("UpperTorso") or clone:FindFirstChild("Torso")
	local root = clone:FindFirstChild("HumanoidRootPart")
	if not (torso and torso:IsA("BasePart")) then
		clone:Destroy()
		return nil
	end

	--[[ Laid out by hand when it is not already a ragdoll: on its back at the origin, then bent. The
		root goes face up first, so the bends are in the body's own frame whichever way it lies. ]]
	if not fallen and root and root:IsA("BasePart") then
		root.CFrame = CFrame.Angles(math.rad(90), 0, 0)
		EndShot.solveRig(clone, root, EndShot.Sprawl)
	end
	for _, joint in clone:GetDescendants() do
		if joint:IsA("JointInstance") or joint:IsA("Constraint") then
			joint:Destroy()
		end
	end
	-- The root is an invisible box round the hips and would frame the shot on nothing.
	if root then
		root:Destroy()
	end

	-- Head to the right: turn about the vertical so the torso's own up runs along +X.
	local along = torso.CFrame.UpVector * Vector3.new(1, 0, 1)
	if along.Magnitude > 0.05 then
		local yaw = math.atan2(-along.Z, along.X)
		clone:PivotTo(CFrame.Angles(0, -yaw, 0) * clone:GetPivot())
	end
	local box, size = clone:GetBoundingBox()
	clone:PivotTo(CFrame.new(-box.Position) * clone:GetPivot())

	local viewport, camera = EndShot.box(parent, "RiderShot", options.backdrop, EndShot.RiderAmbient, CAR_LIGHT, CAR_LIGHT_DIR)
	clone.Parent = viewport
	--[[ Framed on the box as the camera sees it: its length across, its depth folded into the height by
		the pitch. The viewport is the slot's shape, wider than tall, so the width gets the aspect. ]]
	local pitch = math.rad(EndShot.RiderPitch)
	local tanHalf = math.tan(math.rad(CAR_FOV) / 2)
	local aspect = if parent.AbsoluteSize.Y > 0 then parent.AbsoluteSize.X / parent.AbsoluteSize.Y else 1.35
	local halfWide = size.X / 2
	local halfTall = (size.Z * math.sin(pitch) + size.Y * math.cos(pitch)) / 2
	local distance = math.max(halfTall / tanHalf, halfWide / (tanHalf * aspect)) * EndShot.RiderMargin
	EndShot.orbit(camera, 0, EndShot.RiderPitch, distance)
	return {
		step = function() end,
		destroy = function()
			viewport:Destroy()
		end,
	}
end


-- === The ladder bar =========================================================

--[[ Everything this screen needs to know about the road, latched off `RoadController` whenever there
	is a road to ask.

	IT IS READ HERE AND NOWHERE ELSE BECAUSE OF WHEN THIS SCREEN RUNS. `RaceReturning` arrives while
	the local road is still up — `RaceService` only tears it down a fade later, on `RaceEnd` — so the
	one moment the results screen goes up is also the last moment the road can be measured. Latched
	rather than read fresh, so a screen raised after the teardown (or by the safety timeout) still has
	the numbers the run was actually driven with.

	The SEGMENT LENGTH is a property of the one authored `RoadSegment` and never changes; the WORLD
	does, every time the player teleports, which is why this re-latches instead of caching once. ]]
function RaceUIController._latchRoad(self)
	local road = Shard.get("RoadController")
	local info = road and road:getRoadInfo()
	if info and type(info.segmentLength) == "number" and info.segmentLength > 0 then
		self._roadFacts = { segmentLength = info.segmentLength, world = info.world }
	end
end

--[[ Where this run got to on the ladder, as fractions of the bar. nil when it can't be worked out,
	and that nil is the whole error path: the bar falls back to being the hairline divider it used to
	be rather than drawing a progress that is a guess.

	TILES ARE THE UNIT. `TrafficConfig` unlocks each rung at a `FromTile` and `RoadController` lays
	every tile out one `segmentLength` apart from the start of the run, so "how far did I drive" and
	"which cars had joined the road" are the same axis and the conversion is one division. That is
	also why 100% is the TOP RUNG's tile and not some invented race length: there is no finish line in
	this game, so the only honest full-scale is the point past which the road has nothing new to show
	you.

	`RewardService`'s studs are forward travel with rebases discarded, so this reads a stud or two
	short over a long run — which is the right direction to be wrong in on a bar you can fill. ]]
function RaceUIController._planLadder(self, studs: number)
 local road = self._roadFacts
 if not road or type(road.segmentLength) ~= "number" or road.segmentLength <= 0 then return nil end
 local top = TrafficConfig.topTileFor(road.world)
 if not top then return nil end
 -- Distance increases rare-car odds; ticks are road sections, not car unlocks.
 local tile = math.max(0, studs / road.segmentLength)
 local marks = table.create(top + 1)
 for index = 1, top + 1 do marks[index] = (index - 1) / top end
 return {
  progress = math.clamp(tile / top, 0, 1),
  marks = marks,
  reached = math.min(math.floor(tile) + 1, #marks),
 }
end

--[[ Draw the bar for the plan in hand — the ticks and the resting geometry, not the animation.

	The ticks are rebuilt rather than pooled: it is one Frame per car in the world, a dozen at most,
	once per run, on a screen that is already fading in. Pooling them would buy nothing and would need
	its own answer for a world whose ladder is a different length from the last one's. ]]
function RaceUIController._paintLadder(self, plan, color: Color3)
	for _, tick in self._ticks:GetChildren() do
		tick:Destroy()
	end
	-- Emptied alongside the instances, not just left holding them: `_hide` tweens this list, and a
	-- destroyed frame in it is a tween that runs and does nothing on every fade for the rest of the
	-- session.
	self._tickList = {}
	self._fill.Visible = false
	self._fill.Size = UDim2.fromScale(0, TRACK_HEIGHT)
	self._fill.BackgroundTransparency = 1
	self._ticks.Visible = false
	self._marker.Visible = false
	self._marker.ImageTransparency = 1
	self._marker.Position = UDim2.fromScale(0.5 - RULE_WIDTH / 2, MARKER_Y)

	if not plan then
		self._rule.Size = UDim2.fromScale(0, RULE_HEIGHT) -- the plain divider, as before
		return
	end
	self._rule.Size = UDim2.fromScale(0, TRACK_HEIGHT)

	--[[ Kept in an array as well as parented, because `_playLadder` needs them in RUNG ORDER and
		`GetChildren` does not promise the order they were made in. The alternative — parsing the rung
		back out of the instance name — is a string round trip to recover something we are holding. ]]
	local built = table.create(#plan.marks)
	for index, at in plan.marks do
		local tick = Instance.new("Frame")
		tick.Name = "Tick" .. index
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		-- Ticks are positioned in the CONTAINER's scale, which spans exactly the track, so a mark of
		-- 0 lands on the start line and one of 1 on the far end with no arithmetic either side.
		tick.Position = UDim2.fromScale(at, 0.5)
		tick.Size = UDim2.new(TICK_WIDTH / RULE_WIDTH, 0, 1, 0)
		tick.BackgroundColor3 = color
		tick.BackgroundTransparency = 1
		tick.BorderSizePixel = 0
		tick.Parent = self._ticks
		built[index] = tick
	end
	self._tickList = built

	self._fill.BackgroundColor3 = color
	self._marker.ImageColor3 = color
	self._fill.Visible = true
	self._ticks.Visible = true
	self._marker.Visible = true
end

--[[ Drive the car along the bar, and light the rungs it passes.

	THE FILL AND THE CAR ARE ONE MOVE at the same easing, so the car is always at the head of what it
	has filled in — the fill reads as its wake rather than as a second thing happening. It sets off
	only once the track has finished opening under it (`BEAT_LADDER` against the wipe in `_playResults`),
	because a car driving on a road that is still being laid looks like a timing bug even when it is
	deliberate.

	Every tick fades in at once rather than lighting as the car passes it. Sequencing them would be a
	stack of nested delays to say what the car's own position already says, and a rung AHEAD of the
	car has to be visible while the car is still short of it — that is the entire reason the unreached
	ones are drawn at all. What separates them is only how bright they settle. ]]
function RaceUIController._playLadder(self, plan)
	local left = 0.5 - RULE_WIDTH / 2
	self:_tween(self._fill, MARKER_TRAVEL, { Size = UDim2.fromScale(RULE_WIDTH * plan.progress, TRACK_HEIGHT) })
	self:_tween(self._fill, 0.2, { BackgroundTransparency = FILL_REST })
	self:_tween(self._marker, MARKER_TRAVEL, { Position = UDim2.fromScale(left + RULE_WIDTH * plan.progress, MARKER_Y) })
	self:_tween(self._marker, 0.2, { ImageTransparency = 0 })
	for index, tick in self._tickList do
		self:_tween(tick, 0.3, { BackgroundTransparency = if index <= plan.reached then TICK_REACHED else TICK_AHEAD })
	end
end

-- === The loading screen =====================================================

--[[ Name the place we are going, as the headline: "CITY", "DESERT".

	This screen's version of the one loud word the results screen ends on, and the same argument for
	it — the headline is where you say WHAT this is, and "Entering race…" only says that something is
	happening, which the fade and the spinner have already said twice.

	IT IS READ TWICE, and the second read is the one to trust. At `RaceEntering` all the client has is
	the replicated world attribute, and that is genuinely racy: the server writes it in `setWorld` a
	few lines before it fires this, and a property and a remote have no ordering promise between them
	— so a player who just teleported can catch the previous world's name for a frame or two. The
	authoritative answer arrives with `RaceStart`, which carries the world the road is actually being
	built from, and `RoadController` hands it straight back here. Rewriting a label that is still
	fading in costs nothing; showing the wrong destination for a whole entry would be a lie the player
	can check. ]]
function RaceUIController._setDestination(self, world: unknown)
	if not self._label then
		return
	end
	local name = WorldConfig.displayName(world)
	self._label.Text = if name ~= "" then oneLine(string.upper(name)) else ENTER_HEADLINE

	--[[ ...and the picture of it, from the same one answer. Both halves of "where am I going" are
		set here rather than in two places, so the headline and the backdrop can never disagree —
		which they would the first time somebody moved a ladder onto a different road and updated
		only one of them.

		`setLoadPhase` calls this again with the world the SERVER sent, which is the authoritative
		one; the first call is off the player attribute and is a guess made a beat earlier. Setting
		`Image` to what it already holds is a no-op, so the common case (the guess was right) costs
		nothing and does not restart the fade. ]]
	local backdrop = self._backdrop
	if not (backdrop and self._loading) then
		return
	end
	local image = "rbxassetid://" .. UIAssets.worldThumb(WorldConfig.mapFor(world))
	if backdrop.Image ~= image then
		backdrop.Image = image
	end
	backdrop.Visible = true
end

--- One tip, never the same one twice running — this screen is up every time a player presses Play,
--- and the same line twice reads as a bug in the shuffle rather than as chance.
function RaceUIController._pickTip(self): string
	if #TIPS == 0 then
		return ""
	end
	local index = math.random(#TIPS)
	if #TIPS > 1 and index == self._lastTip then
		index = index % #TIPS + 1
	end
	self._lastTip = index
	return TIPS[index]
end

--[[ Set the loading screen up — the resting state of it, not the animation.

	The bar is BUILT AND THEN HIDDEN rather than skipped, so `_playLoading` has nothing left to do
	but reveal it: the entry it is drawn for may be over before the reveal is due, and the cheap half
	of the work (four Frames and two labels) is the half that would otherwise have to happen on the
	frame the player is already waiting on. ]]
function RaceUIController._paintLoading(self)
	local lines = self._lines
	if not lines then
		return
	end

	self._loading = true
	self._aborted = false
	self._loadRevealed = false
	self._loadIndex = 1
	self._loadShown = 0
	self._loadFloor = 0
	self._loadTarget = LOAD_PHASES[1].to
	self._loadTau = LOAD_PHASES[1].tau
	self._litTicks = {}

	self:_setDestination(Players.LocalPlayer:GetAttribute(WorldConfig.WorldAttribute))

	--[[ The same widgets the ladder rides on, with the steps as its ticks. `_paintLadder` leaves the
		track closed and every part of it transparent, which is exactly the state to reveal from.

		The track's own colour is set HERE and not in there, for the same reason `_paintPayout` sets
		it: `_paintLadder` colours the fill, the ticks and the car, but the rule is the one piece that
		is drawn with or without a ladder, so it belongs to whoever is painting the screen. Left to
		itself it would still be carrying the last run's green or amber. ]]
	self._rule.BackgroundColor3 = LOAD_COLOR
	self:_paintLadder({ marks = LOAD_MARKS }, LOAD_COLOR)
	self._fill.Visible = false
	self._ticks.Visible = false
	self._marker.Visible = false

	local status, tip = lines.status, lines.tip
	-- The status line's TOP edge lands where the payout's does, so the two screens put their first
	-- line of text in the same place and the transition between them has nothing jumping.
	status.Position = UDim2.fromScale(0.5, RESULTS_TOP + GEOMETRY.status.height / 2)
	status.Text = oneLine(LOAD_PHASES[1].label)
	status.TextColor3 = LOAD_COLOR
	status.TextTransparency = 1
	status.Visible = false

	tip.Position = UDim2.fromScale(0.5, TIP_Y)
	tip.Text = oneLine(self:_pickTip())
	tip.TextColor3 = LOAD_COLOR
	tip.TextTransparency = 1
	tip.Visible = false
end

--[[ Put the bar on screen, once the entry has taken long enough to deserve one (`LOAD_REVEAL`).

	IN TWO BEATS, AND THE SECOND ONE IS NOT A FLOURISH. The track wipes open from the centre first
	and only then do the fill, the ticks and the car fade in, because all three of those are drawn in
	the track's FINAL geometry — the car sits at the left-hand end and the end ticks are at the very
	ends — so revealing them together paints a car and two ticks hanging in the black either side of
	a bar that has not opened out to them yet. Same wipe, same reason, as the results screen. ]]
function RaceUIController._playLoading(self, token: number)
	local function beat(delay: number, step: () -> ())
		task.delay(delay, function()
			if self._token == token and self._visible and not self._hiding and self._loading then
				step()
			end
		end)
	end

	beat(LOAD_REVEAL, function()
		self._loadRevealed = true
		local lines = self._lines
		lines.status.Visible = true
		lines.tip.Visible = true
		self:_tween(self._rule, RULE_WIPE, {
			Size = UDim2.fromScale(RULE_WIDTH, TRACK_HEIGHT),
			BackgroundTransparency = TRACK_REST,
		})
		self:_tween(lines.status, 0.25, { TextTransparency = GEOMETRY.status.rest })
		self:_tween(lines.tip, 0.35, { TextTransparency = GEOMETRY.tip.rest })
	end)

	beat(LOAD_REVEAL + RULE_WIPE, function()
		self._fill.Visible = true
		self._ticks.Visible = true
		self._marker.Visible = true
		self:_tween(self._fill, 0.25, { BackgroundTransparency = FILL_REST })
		self:_tween(self._marker, 0.25, { ImageTransparency = 0 })
		for _, tick in self._tickList do
			self:_tween(tick, 0.3, { BackgroundTransparency = TICK_AHEAD })
		end
	end)
end

--[[ Advance the bar. Runs every frame from the spin loop for as long as a loading screen is up.

	IT APPROACHES THE CURRENT STEP'S CEILING AND NEVER ARRIVES, which is the one property a loading
	bar has to have: it is always moving — so the screen never looks hung, which is the entire reason
	it is here — and it can never say a step is done before the step says so. Each frame closes a
	fixed fraction of what is left, so the motion decays: brisk when a step has just started, a crawl
	if that step is overrunning, which is exactly the shape of "still working" a player can read.

	`1 - exp(-dt/tau)` and not `dt/tau`, so the rate is per second rather than per frame. This screen
	is up precisely when frames are being dropped, and a per-frame rate would have the bar crawl on
	the phone that needs it and sprint on the desktop that doesn't.

	IT DRAWS EVEN WHILE HIDDEN, on purpose. Writing a Position to an invisible frame costs nothing,
	and it means the reveal has one less thing to get right — whenever the bar comes up, it is
	already showing where the entry has actually got to. Only the TICKS wait, because lighting one is
	a tween and a tween fired before the reveal would be fighting the reveal's own. ]]
function RaceUIController._loadTick(self, dt: number)
	local target = self._loadTarget or 0
	local shown = self._loadShown or 0
	if shown < target then
		-- Still short of the last finished step's mark? Then this is the catch-up, and it is brisk:
		-- see the floor in `setLoadPhase`. Above it, the step's own pace takes back over.
		local tau = if shown < (self._loadFloor or 0) then LOAD_CATCHUP_TAU else (self._loadTau or 1)
		shown = math.min(target, shown + (target - shown) * (1 - math.exp(-dt / tau)))
		self._loadShown = shown
	end

	local left = 0.5 - RULE_WIDTH / 2
	self._fill.Size = UDim2.fromScale(RULE_WIDTH * shown, TRACK_HEIGHT)
	self._marker.Position = UDim2.fromScale(left + RULE_WIDTH * shown, MARKER_Y)

	if not self._loadRevealed then
		return
	end
	for index, tick in self._tickList do
		if not self._litTicks[index] and shown >= (LOAD_MARKS[index] or 1) then
			self._litTicks[index] = true
			self:_tween(tick, 0.25, { BackgroundTransparency = TICK_REACHED })
		end
	end
end

--[[ Public (RoadController): the entry has reached `key` — one of `LOAD_PHASES`.

	PUSHED FROM THE THING THAT REACHED IT rather than polled from here, because half of these are
	events with no state behind them to poll: "the road build has started" is true for the length of
	one synchronous function call, and a screen watching for the road folder to appear would only
	ever see the far side of it. The same argument, and the same shape, as `setTrophy`.

	The bar only ever goes forward. A step arriving out of order — a stale push from an entry that
	has already been abandoned, most likely — is dropped rather than allowed to walk the car
	backwards down a bar the player is watching. ]]
function RaceUIController.setLoadPhase(self, key: string, world: unknown)
	local index = LOAD_INDEX[key]
	if not (index and self._loading and not self._aborted) then
		return
	end
	if world ~= nil then
		self:_setDestination(world)
	end
	if index <= (self._loadIndex or 0) then
		return
	end
	self._loadIndex = index

	--[[ A STEP FINISHING IS THE ONE THING ON THIS SCREEN WORTH A LURCH, so the mark of the step that
		just ended becomes a FLOOR the bar hurries up to before it goes back to creeping.

		It is what makes the ticks mean anything. The creep is deliberately paced for a step that
		overruns (see `LOAD_PHASES`), so a step that finishes QUICKLY leaves the bar well short of its
		own boundary — and without this the car would drift past that tick a second or two later, in
		the middle of the next step, saying nothing about either. With it, passing a tick is always
		the same event: that step is done. Which is the only claim on this bar the player can check
		for themselves, because they can see the thing it is waiting for arrive.

		A FLOOR AND NOT A SNAP, because the marker is a car. Jumping it forward 40 pixels between two
		frames reads as the sprite being repositioned; `_loadTick` drives it up there in a quarter of
		a second instead, which reads as the car it is drawn as. Never backwards, and off the PREVIOUS
		step's ceiling rather than this one's: what is earned is everything up to here, and none of
		the step that is only now starting. ]]
	local previous = LOAD_PHASES[index - 1]
	self._loadFloor = if previous then math.max(self._loadFloor or 0, previous.to) else 0

	local phase = LOAD_PHASES[index]
	self._loadTarget, self._loadTau = phase.to, phase.tau
	local status = self._lines and self._lines.status
	if status then
		status.Text = oneLine(phase.label)
	end
end

--[[ The car is live: run the bar out to the end and let it be seen getting there.

	The last step's ceiling is short of 1 like every other step's, so this is the one moment the bar
	is allowed to complete — and it is the moment it has genuinely completed. The hold is what makes
	that visible at all: `_hide` is called on the same event, and without a floor under it a slow
	entry (the only kind that ever shows this bar) would drop the screen the instant the car arrived,
	with the car still three quarters of the way along its own track. ]]
function RaceUIController._finishLoad(self)
	if not self._loading or self._aborted then
		return
	end
	self._loadIndex = #LOAD_PHASES + 1
	self._loadTarget, self._loadTau = 1, LOAD_LAND_TAU
	local status = self._lines and self._lines.status
	if status then
		status.Text = LOAD_DONE_LABEL
	end
	if self._loadRevealed then
		self:_holdFor(LOAD_LAND)
	end
end

--[[ Keep the screen up for `seconds` MORE, whatever hold `_hide` works out for itself.

	`_hide` measures its holds from the moment the screen went up, which is right for a results beat
	that starts then and useless for anything that happens later: by the time an entry aborts, the
	screen has been up for `RaceConfig.EnterReadyTimeout` and every hold measured that way expired
	seconds ago. So a late beat books its own floor here and `_hide` takes whichever of the two is
	further off. ]]
function RaceUIController._holdFor(self, seconds: number)
	self._holdUntil = math.max(self._holdUntil or 0, os.clock() + seconds)
end

--[[ The entry gave up: `RaceService._abortEntry` could not get our road built inside
	`RaceConfig.EnterReadyTimeout` and has put us back in the lobby instead of releasing a car into a
	world that isn't there yet (read its note — the alternative used to kill people).

	SO THE SCREEN HAS TO SAY SO, and this is the only state on it that is not a step. The bar stops
	dead where it got to rather than completing, everything on it turns the crash colour, and the
	spinner goes out: whatever this screen is now, it is not still waiting for something. The one
	beat this screen owes the player is the sentence, so it books a hold long enough to read it —
	`RaceLive` is a few hundred milliseconds behind this and drops the screen otherwise. ]]
function RaceUIController._onAborted(self)
	if not (self._loading and self._visible) then
		return -- the screen is already down, or was never a loading screen; nothing to say it on
	end
	self._aborted = true
	self._loadTarget = self._loadShown or 0 -- it stopped here. It did not finish.

	local lines = self._lines
	lines.status.Text = oneLine(ABORT_LABEL)
	lines.tip.Text = oneLine(ABORT_HINT)
	--[[ An abort can only land at the timeout, which is many times `LOAD_REVEAL`, so in practice the
		bar is always up by now. If it somehow isn't, the two lines still go up on their own: the
		message is the point of this and a bar is not worth revealing to stop it. ]]
	if not self._loadRevealed then
		lines.status.Visible = true
		lines.tip.Visible = true
		self:_tween(lines.status, 0.2, { TextTransparency = GEOMETRY.status.rest })
		self:_tween(lines.tip, 0.2, { TextTransparency = GEOMETRY.tip.rest })
	end

	self:_tween(lines.status, 0.25, { TextColor3 = CRASH_COLOR })
	self:_tween(lines.tip, 0.25, { TextColor3 = CRASH_COLOR })
	self:_tween(self._rule, 0.25, { BackgroundColor3 = CRASH_COLOR })
	self:_tween(self._fill, 0.25, { BackgroundColor3 = CRASH_COLOR })
	self:_tween(self._marker, 0.25, { ImageColor3 = CRASH_COLOR })
	for _, tick in self._tickList do
		self:_tween(tick, 0.25, { BackgroundColor3 = CRASH_COLOR })
	end
	self:_tween(self._stroke, 0.3, { Transparency = 1 })
	self:_holdFor(ABORT_HOLD)
end

--[[ The headline once there is a result to name, and nil when there isn't (an entry, or a level-up
	with no summary behind it). The caller falls back to what the game is doing.

	THE CAUSE IS NOT ON THE SUMMARY, and it cannot be: `RunSettled` carries what the run was WORTH,
	which is a question with the same answer however the run ended, and the reason it ended arrives
	on a different remote (`RaceWrecked`). Roblox only promises ordering within one remote, so the
	two are held apart and read together here, which is exactly the treatment `CarLeveled` gets a few
	lines above and for exactly the same reason.

	`_wreckCause` is therefore the last wreck this client was told about. It is overwritten by every
	wreck, including one with no cause at all, and cleared at the start of the next entry, so the
	only way it can be stale is a run that ended without a wreck, and that run banked, which is
	answered on the line above without ever consulting it. ]]
function RaceUIController._headline(self): string?
	local summary = self._summary
	if not summary then
		return nil
	end
	if summary.banked then
		return BANK_HEADLINE
	end
	return if self._wreckCause == PoliceConfig.Cause then BUST_HEADLINE else CRASH_HEADLINE
end

--[[ Work out what the last `RunSettled` has to say, write it into the lines, and answer whether
	there is anything to show.

	Three lines at most: what the run paid, how far it got, and — only when it happened — the car
	that levelled. A wreck names its own split rather than just showing a smaller number, because
	"+$107" on its own reads as the run having been worth less, not as three quarters of it having
	been lost; the whole point of `RewardConfig.Crash.CashFraction` is that the player can feel the
	difference.

	A run that paid nothing still gets a line. Being told you earned nothing is information; being
	shown a blank screen is a bug the player then has to test for themselves.

	EVERYTHING IS RESET FIRST, unconditionally. The lines carry animation state — a size mid-punch,
	a position mid-slide — and a run that ends while the last one is still on screen would otherwise
	inherit it. Resetting here rather than in `_hide` means the stale state is cleared by whoever is
	about to use it, which is the only moment it is certainly safe to clear. ]]
function RaceUIController._paintPayout(self): boolean
	local lines = self._lines
	if not lines then
		return false
	end

	for name, line in lines do
		local geom = GEOMETRY[name]
		line.Visible = false
		line.Text = ""
		line.TextTransparency = 1
		line.Size = UDim2.fromScale(geom.width, geom.height)
	end
	self._rule.Size = UDim2.fromScale(0, RULE_HEIGHT)
	self._rule.BackgroundTransparency = 1
	self._plan = nil
	self._ladder = nil
	self:_paintLadder(nil, PAYOUT_COLOR) -- clears the bar; repainted below once there is a run to draw

	local summary, leveled = self._summary, self._leveled
	--- The kit panel paints its own rows off the same two facts. The reset above still ran, because
	--- the overlay's bar is the loading screen's too.
	if self._panel then
		return self:_paintPanel(summary, leveled)
	end
	if not (summary or leveled) then
		return false
	end

	--[[ WHAT each line says, decided in one place and applied in the next. The beat needs to know
		more about the payout line than its text — it counts up to a number — so the plan carries
		the number too, and the animation never has to parse a label back into one. ]]
	local plan = {}
	if summary then
		-- The split rides on the payout line rather than getting one of its own: it is a caveat on
		-- that number, and a line of its own would read as a second thing you earned.
		--[[ THE CAVEAT ON THE PAYOUT LINE, and there are now two things it can be.

			A CRASH names its split, for the reason below. A BANK names its MUTATION, if the car had
			one — and that is not decoration: a mutated bank pays up to five times what the same run
			would otherwise have paid, and a number that size with nothing on screen explaining it
			reads as a bug rather than as a jackpot. The player has to be able to connect it to the
			car they chased through the storm.

			They cannot both apply. A wreck awards no car, so there is nothing for a mutation to be
			on (`RewardService.settleRun`) — which is why this is a branch and not two suffixes. ]]
		local suffix
		if not summary.banked then
			suffix = string.format("%skept%s%d%%", DOT, NBSP, math.round(RewardConfig.Crash.CashFraction * 100))
		elseif summary.mutation and WeatherConfig.multiplierOf(summary.mutation) > 1 then
			suffix = string.format(
				"%s%s%s%s",
				DOT,
				WeatherConfig.nameOf(summary.mutation),
				NBSP,
				WeatherConfig.formatMultiplier(WeatherConfig.multiplierOf(summary.mutation))
			)
		else
			suffix = ""
		end
		if summary.cash > 0 then
			--- The 2x Cash pass, said (header note at `DOUBLE.text`).
			if DOUBLE.owns() then
				suffix ..= DOT .. DOUBLE.text
			end
			plan.cash = { text = "+" .. GarageConfig.formatCash(summary.cash) .. suffix, count = summary.cash, suffix = suffix }
		else
			plan.cash = { text = "No" .. NBSP .. "payout" .. suffix }
		end

		--[[ How far it went, which is WHERE THE CASH CAME FROM — distance is the whole of the
			payout (`RewardConfig.Distance`), so the two belong on the same screen or the number
			above reads as arbitrary. It rests dimmer and smaller than the payout: it is the
			receipt, not the headline, and on a crash it is the one figure the run earned outright. ]]
		local distance = RewardConfig.formatDistance(summary.studs)
		if distance then
			plan.distance = { text = distance .. NBSP .. "driven" }
		end

		--[[ …and what the driving itself paid, which is the other half of the same explanation.
			`NearMissConfig` (and RewardService, which fences it) is the authority on both numbers: the
			toasts during the run were the client's own pricing, and this is what actually banked.

			The line is absent, not zeroed, for a run with no near misses in it — which is most runs
			early on, and which is the difference between a screen that says "you did not do this" and
			one that says "this exists and you got none of it". The tally alone would be the second
			thing; a tally the player has just watched land twelve times is the first.

			Rubs are counted BESIDE the near misses rather than folded in with them, because trading paint
			is the one you did not quite make and a line claiming twelve near misses when three of them
			were contact would be the screen flattering the player. `tallyLabel` owns the wording.

			THE SPLIT IS NAMED HERE TOO, AND THAT IS NOT REDUNDANT WITH THE PAYOUT LINE ABOVE. This is the
			one line on the screen the player has already seen the arithmetic for: every near miss in the
			tally showed its own "+$18" toast as it landed (NearMissController prices them client-side from
			the same `NearMissConfig`, so the toasts and this number come from identical maths). Fifteen
			toasts summing to $276 and then a line reading "15 near misses  +$69" is the screen reporting a
			DIFFERENT TOTAL for events the player just watched pay — measured in a playtest, and the most
			likely thing behind the "cash earned during a race isn't there after the race" report.

			The caveat on the payout line does not cover this, because a player reads it as a caveat on
			THAT number. So the same suffix rides here, on the only other line that carries a figure the
			crash split moved. On a getaway `suffix` is "" and this reads exactly as it always did.

			AND ON A CRASH THE LINE IS ANIMATED, which is the other half of the same answer. A caveat
			explains the gap; it does not close it, and the toasts are still the louder memory. So the
			line LANDS on what the run earned — the figure the player watched accumulate — and then
			counts down to what it kept, with the caveat arriving as it falls. Same information, but it
			shows up at the moment it becomes true, and the drop reads as the crash costing you
			something rather than as the screen disagreeing with itself. The toasts are left alone:
			they are correct for the ending the player is driving toward, and taxing every one of them
			to pre-explain a wreck that has not happened is the wrong place to spend it. ]]
		local tally = NearMissConfig.tallyLabel(summary.nearMisses, summary.rubs)
		if tally and summary.bonus > 0 then
			-- Built from an amount rather than baked, because the animation needs the same line at a
			-- different number every frame. NBSP-joined throughout for the reason `suffix` is.
			local function label(amount: number, tail: string): string
				return (string.gsub(tally .. "  +" .. GarageConfig.formatCash(amount), " ", NBSP)) .. tail
			end
			plan.bonus = { text = label(summary.bonus, suffix) }
			--[[ The caveat is deliberately NOT on the resting text of an animated line: for the beat
				before the drop the line is claiming the full figure, and "kept 25%" next to a number
				that is 100% of itself is the one arrangement here that would be actively wrong. It
				arrives with the first frame of the count. ]]
			if summary.bonusEarned > summary.bonus then
				plan.bonus.text = label(summary.bonusEarned, "")
				plan.bonus.from = summary.bonusEarned
				plan.bonus.count = summary.bonus
				plan.bonus.label = label
				plan.bonus.suffix = suffix
			end
		end
	end
	if leveled then
		plan.level = { text = (string.gsub(string.format("%s reached Level %d", GarageConfig.displayName(tostring(leveled.body)), leveled.level), " ", NBSP)) }
	end

	--[[ Stack whatever survived, from the top down. Positions are computed rather than authored so
		that a missing line closes its own gap — a level-up with no distance under it can only
		happen to a run that banked without moving, but a layout that leaves a hole for it is a
		layout that will leave one for the next case nobody thought of either. ]]
	local color = if summary and not summary.banked then CRASH_COLOR else PAYOUT_COLOR
	self._rule.BackgroundColor3 = color

	-- The bar, in the ending's colour like everything else here. A run with no summary has no
	-- distance to plot, so it keeps the plain divider — a level-up alone cannot draw a ladder.
	if summary then
		self._ladder = self:_planLadder(summary.studs)
		self:_paintLadder(self._ladder, color)
	end

	local cursor, shown = RESULTS_TOP, false
	for _, name in ORDER do
		local entry = plan[name]
		if entry then
			local line, geom = lines[name], GEOMETRY[name]
			line.Text = entry.text
			line.TextColor3 = color
			line.Position = UDim2.fromScale(0.5, cursor + geom.height / 2)
			line.Visible = true
			cursor += geom.height + RESULTS_GAP
			shown = true
		end
	end

	self._plan = plan
	return shown
end

--[[ Prepare the static results layer while the truck is still doing its closing beat. `RunSettled`
	arrives at the start of that hold, whereas `RaceReturning` does not raise the screen until more
	than two seconds later. Building the ladder ticks and laying out the labels on that later frame
	made the fade pay for work whose answer had already been known for the whole hold.

	The token matters because `RunSettled` and `CarLeveled` are separate remotes with no ordering
	promise. Either can replace the pending preparation; only the newest snapshot may paint. `_show`
	also turns the token over, preventing a late callback from resetting widgets under an animation. ]]
function RaceUIController._queueResultsPreparation(self)
	self._resultPrepareToken = (self._resultPrepareToken or 0) + 1
	local token = self._resultPrepareToken
	self._resultsPrepared = false

	task.delay(RESULTS_PREP_DELAY, function()
		if self._resultPrepareToken ~= token or self._visible or not (self._summary or self._leveled) then
			return
		end
		self:_latchRoad()
		self._preparedHasResults = self:_paintPayout()
		self._resultsPrepared = true
	end)
end

-- One sound, one beat. Blank ids are a no-op rather than a broken Sound (see the constants), and
-- the instance is temporary because this screen may be up twice a minute for an hour. It joins the
-- SFX master group so the settings slider reaches it: SoundController only adopts ungrouped Sounds
-- in the Workspace, and this one lives in PlayerGui.
function RaceUIController._playSound(self, id: string)
	if id == "" or not self._gui then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	local master = SoundService:FindFirstChild(AudioConfig.Sfx.GroupName)
	if master and master:IsA("SoundGroup") then
		sound.SoundGroup = master
	end
	sound.Parent = self._gui
	sound:Play()
	Debris:AddItem(sound, 8) -- Ended never fires for an id that failed to load
end

--[[ A punch: the line snaps a little larger, then settles. On a TextScaled label the BOX is the
	font size, so growing the box reads as the text itself flexing — no UIScale, no second instance,
	and nothing to undo if the screen is torn down mid-tween (the next paint resets the size). ]]
function RaceUIController._punch(self, line: TextLabel, geom, amount: number, token: number)
	local up = self:_tween(line, 0.09, { Size = UDim2.fromScale(geom.width * amount, geom.height * amount) })
	up.Completed:Once(function()
		if self._token == token then
			self:_tween(line, 0.2, { Size = UDim2.fromScale(geom.width, geom.height) })
		end
	end)
end

--[[ The payout, counting up to itself.

	THE FINAL VALUE IS WRITTEN FIRST and the count overwrites it, which is backwards until you
	notice that this runs on RenderStepped: a client whose renderer never ticks (a minimised Studio
	window is the one that bites in testing) would otherwise sit on a zero for the whole beat and
	report the wrong payout. Written this way the animation is the thing that can fail to happen,
	not the number.

	Eased out hard — most of the count is over in the first third of it — because a linear counter
	reads as a progress bar, and this is meant to read as a total landing. ]]
function RaceUIController._countUp(self, line: TextLabel, entry, token: number)
	line.Text = entry.text
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if self._token ~= token then
			connection:Disconnect()
			return
		end
		local t = math.min(1, (os.clock() - started) / COUNT_TIME)
		local eased = 1 - (1 - t) ^ 3
		line.Text = "+" .. GarageConfig.formatCash(math.floor(entry.count * eased + 0.5)) .. entry.suffix
		if t >= 1 then
			connection:Disconnect()
			self._countConn = nil
			self:_punch(line, GEOMETRY.cash, 1.1, token)
		end
	end)
	self._countConn = connection
end

--[[ The crash split, shown happening instead of asserted.

	Same machinery as `_countUp` and the same easing, pointed the other way: the line is already
	showing what the run earned, and this takes it down to what it kept while the `kept 25%` caveat
	arrives underneath the fall. The eased-out curve does most of the drop immediately, which is what
	makes it read as something being TAKEN rather than as a number being scrubbed.

	THE FINAL VALUE IS WRITTEN FIRST, for the same reason `_countUp` does it and with more riding on
	it here. A client whose renderer never ticks (a minimised Studio window, which is exactly the case
	that bites in testing) runs none of these frames — and the value it would be left sitting on is
	the PRE-SPLIT one, a screen reporting four times the money that was actually paid. Written this
	way the animation is what can fail to happen, and the failure lands on the true number.

	No punch at the end, unlike the payout. This is a receipt, and a receipt that flexes when it
	finishes is asking for attention it has not earned — the drop is the whole of the emphasis. ]]
function RaceUIController._countDown(self, line: TextLabel, entry, token: number)
	local from, to = entry.from, entry.count
	line.Text = entry.label(to, entry.suffix)
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if self._token ~= token then
			connection:Disconnect()
			return
		end
		local t = math.min(1, (os.clock() - started) / BONUS_DROP_TIME)
		local eased = 1 - (1 - t) ^ 3
		line.Text = entry.label(math.floor(from + (to - from) * eased + 0.5), entry.suffix)
		if t >= 1 then
			connection:Disconnect()
			self._dropConn = nil
		end
	end)
	-- Its own handle rather than sharing `_countConn`: the payout is still counting up while this
	-- waits to start, and one field for both would leave whichever finished second unstoppable.
	self._dropConn = connection
end

--[[ The beat itself: what happens, and when.

	Every step is fenced by the show token AND by `_visible`, so a run that ends while this one is
	still playing takes the screen over cleanly and a fade that has already started coming down is
	never written over by a step that was scheduled before it. ]]
function RaceUIController._playResults(self, token: number)
	if self._panel then
		self:_playPanel(token)
		return
	end
	local plan, lines = self._plan, self._lines
	if not plan then
		return
	end

	local function beat(delay: number, step: () -> ())
		task.delay(delay, function()
			if self._token == token and self._visible then
				step()
			end
		end)
	end

	--[[ The car lands before anything else does, because it is the ANSWER and every line below it is
		the receipt. It arrives a touch small and settles — Back-eased, so it overshoots a hair — while
		the burst behind it fades up more slowly, which is what makes the two read as separate objects
		at separate depths rather than as one badge appearing. ]]
	beat(BEAT_TROPHY, function()
		if not self._trophy.Visible then
			return
		end
		self:_tween(self._trophy, 0.45, { Size = UDim2.fromScale(TROPHY_SIZE, TROPHY_SIZE) }, Enum.EasingStyle.Back)
		self:_tween(self._viewport, 0.3, { ImageTransparency = 0 })
		--- ...and the burst is the REWARD flourish, so it is held off the ending that is not one. A
		--- gold fan behind the car that just arrested you says the game thinks you won it.
		if self._bankedScreen then
			self:_tween(self._burst, 0.55, { ImageTransparency = SUNBURST_REST })
		end
	end)

	--[[ The track wipes open from the centre out, and this is the move the whole screen is built
		around: it is what turns "the screen went black" into "something is being totalled up", it
		carries the run's colour, and the car cannot set off until it lands. Kept to `RULE_WIPE`
		rather than anything more luxurious for one reason — the car has to wait for it (see
		`BEAT_LADDER`), and every tenth spent laying the road is a tenth the car spends parked on the
		start line while the payout above is already counting. What it must NOT do is play under the
		fade, which is `BEAT_START`'s job. ]]
	local ladder = self._ladder
	beat(BEAT_RULE, function()
		local height = if ladder then TRACK_HEIGHT else RULE_HEIGHT
		local rest = if ladder then TRACK_REST else RULE_REST
		self:_tween(self._rule, RULE_WIPE, { Size = UDim2.fromScale(RULE_WIDTH, height), BackgroundTransparency = rest })
		-- The spinner has done its job by now: this stopped being a loading screen the moment there
		-- was something on it worth reading, and a ring still turning over a finished total is the
		-- one thing here that would say "wait" when nothing is being waited for.
		self:_tween(self._stroke, RULE_WIPE, { Transparency = 1 })
	end)

	-- ...and once it is open, the car drives the run again.
	if ladder then
		beat(BEAT_LADDER, function()
			self:_playLadder(ladder)
		end)
	end

	beat(BEAT_CASH, function()
		local entry = plan.cash
		if not entry then
			return
		end
		self:_tween(lines.cash, 0.18, { TextTransparency = GEOMETRY.cash.rest })
		self:_playSound(PAYOUT_SOUND_ID)
		if entry.count then
			self:_countUp(lines.cash, entry, token)
		else
			beat(0.2, function()
				self:_punch(lines.cash, GEOMETRY.cash, 1.1, token)
			end)
		end
	end)

	--[[ The two receipts slide up into place rather than just appearing, which is the whole of their
		animation: they are the smallest lines on the screen and they should arrive like footnotes.
		One helper for both because they are the same move — the only thing that differs is when. ]]
	local function slide(name: string)
		local entry = plan[name]
		if not entry then
			return
		end
		local line = lines[name]
		local target = line.Position
		line.Position = target + UDim2.fromScale(0, 0.018)
		self:_tween(line, 0.3, { TextTransparency = GEOMETRY[name].rest, Position = target })
	end

	beat(BEAT_DISTANCE, function()
		slide("distance")
	end)
	beat(BEAT_BONUS, function()
		slide("bonus")
		-- …and, on a crash, the split takes its share out of it once it has been read. Nested so the
		-- delay is measured from the line landing rather than from the start of the screen.
		local entry = plan.bonus
		if entry and entry.from then
			beat(BONUS_DROP_DELAY, function()
				self:_countDown(lines.bonus, entry, token)
			end)
		end
	end)

	--[[ The level-up, and the ONE moment on this screen that gets the loud version: it is rare, it
		is the only line here you had to bank a run to see, and it is the reward the whole crash
		split is arguing about. It arrives over-sized and white and settles into the payout colour —
		a flash rather than a flourish, and still under half a second. ]]
	beat(BEAT_LEVEL, function()
		if not plan.level then
			return
		end
		local line, geom = lines.level, GEOMETRY.level
		line.TextColor3 = ACCENT_COLOR
		line.Size = UDim2.fromScale(geom.width * 1.3, geom.height * 1.3)
		self:_playSound(LEVEL_SOUND_ID)
		-- Back-eased, so it undershoots a hair on the way in and settles. The only easing on this
		-- screen that isn't a plain Quad, and the only line that has earned one.
		self:_tween(line, 0.42, { Size = UDim2.fromScale(geom.width, geom.height) }, Enum.EasingStyle.Back)
		self:_tween(line, 0.16, { TextTransparency = geom.rest })
		self:_tween(line, 0.5, { TextColor3 = PAYOUT_COLOR })
	end)

	--[[ ...and LAST, a quarter of a second behind the line above, the one thing on this screen the
		player can act on. `BEAT_REPLAY`'s own block argues the gap; `_raiseReplay` is the move, and it
		is a no-op on every screen that is not offering a replay. ]]
	beat(BEAT_REPLAY, function()
		self:_raiseReplay()
	end)
end

-- === The kit panel (the new UI) =============================================

--[[ === THE KIT PANEL: the same results, read on the Cartoony Kit's leaderboard ================

	Only ever built with `UIRoot.isNewUI()` and `NewUIConfig.KitRaceResults`. `BuildRaceResultsV2` has
	the whole mapping from the kit's frame; what matters here is which of this file's widgets it
	replaces and which it does not.

	IT REPLACES THE RESULTS AND NOTHING ELSE. The overlay, the backdrop, the spinner, the loading
	bar, the loading screen's two lines and the bust lights are all still built by `_build` and still
	driven exactly as before, because they are the fade and not the results. The overlay's headline,
	rule and receipt lines are simply never painted for a results screen once the panel exists.

	THE TROPHY SLOT MOVES IN WHOLE. `_buildPanel` points `_trophy`, `_burst`, `_viewport` and
	`_camera` at the panel's showcase card and grows the plume there, so `setTrophy`, `setWreck`,
	`_showBustCar`, `_wreckFrom`, `_aimTrophy` and the spin loop drive the car in the card without a
	line of them changing. The one number they could not share is the box's landed size, which is
	`_trophyRest`.

	THE BEAT IS THE SAME BEAT. The panel waits for the black like everything else (`BEAT_START`),
	swells in the way a kit page opens, and then the car lands, the car glyph drives the ladder, and
	the receipts arrive in the shipping screen's reading order at the shipping screen's times, with
	the same payout count, the same crash split counted down on the near misses and the same two
	sounds. A receipt POPS rather than slides, because a kit card is a card and not a line of type.

	THE TWO ENDINGS ARE THE ARTIST'S TWO TEAM COLOURS: blue for a car you kept, red for a crash or a
	bust, read off the template's attributes rather than typed here. `BuildRaceResultsV2` argues it. ]]
local PANEL_SHELF = "Screens"
local PANEL_TEMPLATE = "RaceResults"
local PANEL_WAIT = 10
--- Above everything else on the overlay, which tops out at the marker's 5.
local PANEL_Z = 6

--- The kit pages' own open and close (`UIController`): a swell from nine tenths, and a quick settle.
local PANEL_START_SCALE = 0.9
local PANEL_OPEN_TIME = 0.25
local PANEL_CLOSE_TIME = 0.15

local ROW_POP_TIME = 0.25
--- The level row's pop is the long Back the shipping level line took, for the reason it took it.
local LEVEL_POP_TIME = 0.42
local ROW_PUNCH = 1.06

--- A tick is a thin upright in the kit's outline navy: the fill carries the ending, the marks do not.
local PANEL_TICK_WIDTH = 0.006 -- of the track
local PANEL_TICK_COLOR = Color3.fromRGB(2, 30, 56)

--- The rows, in `ORDER`, with the names `BuildRaceResultsV2` gives their cards.
local PANEL_ROWS = { cash = "Cash", distance = "Distance", bonus = "Bonus", level = "Level" }

--- A colour part of the way along a ramp: the viewport's edge colour is the card's middle.
local function rampAt(ramp: ColorSequence, t: number): Color3
	local keys = ramp.Keypoints
	for index = 2, #keys do
		local a, b = keys[index - 1], keys[index]
		if t <= b.Time then
			local span = b.Time - a.Time
			return a.Value:Lerp(b.Value, if span > 0 then (t - a.Time) / span else 0)
		end
	end
	return keys[#keys].Value
end

--[[ Find the template and build the panel from it. Every step of the wait is bounded, and a place
	that never ran the build command says so and keeps the shipping results.

	IF A SCREEN IS UP WHEN THE TEMPLATE ARRIVES, THE BUILD WAITS FOR IT TO COME DOWN. Moving the
	trophy slot under a screen that is showing a car would move the car out of its box mid-beat. ]]
function RaceUIController._awaitPanel(self)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", PANEL_WAIT)
	local root = playerGui and UIRoot.wait(playerGui :: PlayerGui, PANEL_WAIT)
	local shelf = root and root:WaitForChild(PANEL_SHELF, PANEL_WAIT)
	local template = shelf and shelf:WaitForChild(PANEL_TEMPLATE, PANEL_WAIT)
	if not (template and template:IsA("GuiObject")) then
		self.log:warn(
			string.format(
				"Waited %ds for MainUIV2.%s.%s and it did not arrive; race results stay on the old overlay. Run BuildRaceResultsV2.",
				PANEL_WAIT,
				PANEL_SHELF,
				PANEL_TEMPLATE
			)
		)
		return
	end
	while self._visible or self._trophyCar do
		task.wait(0.5)
	end
	self:_buildPanel(template)
end

--[[ Clone the template onto the overlay and bind it. Leaves nothing behind and changes nothing if the
	template is not the shape `BuildRaceResultsV2` makes. ]]
function RaceUIController._buildPanel(self, template: GuiObject)
	local panel = template:Clone()
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	require(script.Parent.UIController.KitPage).scaleTextCaps(panel)
	local main = panel:FindFirstChild("Main")
	local header = panel:FindFirstChild("Header")
	local ladder = main and main:FindFirstChild("Ladder")
	local track = ladder and ladder:FindFirstChild("Track")
	local showcase = main and main:FindFirstChild("Showcase")
	local card = showcase and showcase:FindFirstChild("Card")
	local trophy = card and card:FindFirstChild("Trophy")
	local receipts = main and main:FindFirstChild("Receipts")
	local parts = {
		title = header and header:FindFirstChild("Title"),
		ladder = ladder,
		track = track,
		fill = track and track:FindFirstChild("Fill"),
		ticks = ladder and ladder:FindFirstChild("Ticks"),
		marker = ladder and ladder:FindFirstChild("Marker"),
		showcase = showcase,
		card = card,
		trophy = trophy,
		--- In the card's `BG` group, which clips a turning image where `ClipsDescendants` cannot.
		burst = (card and card:FindFirstChild("BG") and card.BG:FindFirstChild("Sunburst")) or (trophy and trophy:FindFirstChild("Sunburst")),
		viewport = trophy and trophy:FindFirstChildOfClass("ViewportFrame"),
		receipts = receipts,
	}
	local function reject(what: string)
		self.log:warn(string.format("MainUIV2.%s.%s has no %s; race results stay on the old overlay. Re-run BuildRaceResultsV2.", PANEL_SHELF, PANEL_TEMPLATE, what))
		panel:Destroy()
	end
	-- By a list of names rather than over the table: a lookup that came back nil is not a key in it.
	for _, name in { "title", "ladder", "track", "fill", "ticks", "marker", "showcase", "card", "trophy", "burst", "viewport", "receipts" } do
		if not parts[name] then
			reject("`" .. name .. "`")
			return
		end
	end

	local rows = {}
	for key, name in PANEL_ROWS do
		local row = receipts:FindFirstChild(name)
		local lines = row and row:FindFirstChild("Text")
		local figure = lines and lines:FindFirstChild("Figure")
		local caption = lines and lines:FindFirstChild("Caption")
		if not (figure and caption) then
			reject(string.format("`Receipts.%s.Text.Figure/Caption`", name))
			return
		end
		--- The row's pop, and its punch after that. Rows are not buttons, so this is the only UIScale on them.
		local scale = Instance.new("UIScale")
		scale.Name = "PopScale"
		scale.Scale = 0
		scale.Parent = row
		rows[key] = { row = row, figure = figure, caption = caption, ramp = row:FindFirstChildOfClass("UIGradient"), scale = scale }
	end

	local function sequence(name: string, fallback: Color3): ColorSequence
		local value = panel:GetAttribute(name)
		return if typeof(value) == "ColorSequence" then value else ColorSequence.new(fallback)
	end
	local function colour(name: string, fallback: Color3): Color3
		local value = panel:GetAttribute(name)
		return if typeof(value) == "Color3" then value else fallback
	end

	local openScale = Instance.new("UIScale")
	openScale.Name = "OpenScale"
	openScale.Scale = PANEL_START_SCALE
	openScale.Parent = panel

	--[[ The car's box, dressed the way `_build` dresses the overlay's: a camera, the showroom light,
		and a burst that starts dark. The edge colour is set per ending in `_paintPanel`, because a
		viewport composites its render against `BackgroundColor3` and the card behind it changes. ]]
	local viewport = parts.viewport :: ViewportFrame
	viewport.BackgroundTransparency = 1
	viewport.ImageTransparency = 1
	viewport.Ambient = CAR_AMBIENT
	viewport.LightColor = CAR_LIGHT
	viewport.LightDirection = CAR_LIGHT_DIR
	local camera = Instance.new("Camera")
	camera.FieldOfView = CAR_FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local burst = parts.burst :: ImageLabel
	burst.Image = UIAssets.url(UIAssets.Results.Sunburst)
	burst.ImageColor3 = SUNBURST_COLOR
	burst.ImageTransparency = 1

	local marker = parts.marker :: ImageLabel
	marker.Image = UIAssets.url(UIAssets.Results.CarMarker)

	parts.trophy.Visible = false

	panel.Visible = false
	panel.ZIndex = PANEL_Z
	panel.Parent = self._overlay

	-- The overlay's own trophy box has nothing in it at boot, and nothing will look for it again.
	local overlayTrophy = self._trophy

	self._panel = panel
	self._panelScale = openScale
	self._panelTitle = parts.title
	self._panelLadder = {
		frame = parts.ladder,
		track = parts.track,
		fill = parts.fill,
		fillRamp = parts.fill:FindFirstChildOfClass("UIGradient"),
		ticks = parts.ticks,
		marker = marker,
		markerY = marker.Position.Y,
	}
	self._panelTicks = {}
	self._panelShowcase = parts.showcase
	self._panelCardRamp = parts.card:FindFirstChildOfClass("UIGradient")
	self._panelReceipts = parts.receipts
	self._panelReceiptsAt = parts.receipts.Position
	self._panelRows = rows
	self._panelColours = {
		bank = sequence("BankColor", PAYOUT_COLOR),
		crash = sequence("CrashColor", CRASH_COLOR),
		bankTint = colour("BankTint", PAYOUT_COLOR),
		crashTint = colour("CrashTint", CRASH_COLOR),
	}

	self._trophy = parts.trophy
	self._burst = burst
	self._viewport = viewport
	self._camera = camera
	self._trophyRest = parts.trophy.Size.X.Scale
	--- The puffs go in the card's `Plume` group when it has one, which clips a turning puff to the card.
	local plume = parts.card:FindFirstChild("Plume")
	self:_buildSmoke(plume and plume:FindFirstChild("Box") or parts.trophy)

	if overlayTrophy and overlayTrophy ~= parts.trophy then
		overlayTrophy:Destroy()
	end
end

--[[ `_paintPayout`'s job for the panel: work out what the last `RunSettled` says, write it into the
	rows and the ladder, and answer whether there is anything to show. Everything is reset first, for
	the reason `_paintPayout` gives.

	THE WORDS ARE SPLIT, figure over caption, where the shipping screen writes one line. The kit's card
	has a big line and a small one, so the number goes big and what it is goes small: `+$1,234` over
	`Payout · kept 25%`. Every figure and every caveat is the shipping screen's own. ]]
function RaceUIController._paintPanel(self, summary, leveled): boolean
	local rows = self._panelRows
	self._panelScale.Scale = PANEL_START_SCALE
	for _, row in rows do
		row.row.Visible = false
		row.scale.Scale = 0
		row.figure.Text = ""
		row.caption.Text = ""
	end
	self._plan = nil
	self._ladder = nil
	self:_paintPanelLadder(nil)

	if not (summary or leveled) then
		return false
	end

	local crashed = summary ~= nil and not summary.banked
	local colours = self._panelColours
	local ramp = if crashed then colours.crash else colours.bank
	for _, row in rows do
		if row.ramp then
			row.ramp.Color = ramp
		end
	end
	if self._panelCardRamp then
		self._panelCardRamp.Color = ramp
	end
	self._viewport.BackgroundColor3 = rampAt(ramp, 0.5)

	local function cash(amount: number): string
		return "+" .. GarageConfig.formatCash(amount)
	end

	local plan = {}
	if summary then
		-- The same caveat the shipping payout line carries, for the same two reasons (see `_paintPayout`).
		local suffix = ""
		if crashed then
			suffix = string.format("%skept%s%d%%", DOT, NBSP, math.round(RewardConfig.Crash.CashFraction * 100))
		elseif summary.mutation and WeatherConfig.multiplierOf(summary.mutation) > 1 then
			suffix = string.format(
				"%s%s%s%s",
				DOT,
				WeatherConfig.nameOf(summary.mutation),
				NBSP,
				WeatherConfig.formatMultiplier(WeatherConfig.multiplierOf(summary.mutation))
			)
		end

		--- The 2x Cash pass, said on the caption too (header note at `DOUBLE.text`); the badge is below.
		local doubled = summary.cash > 0 and DOUBLE.owns()
		plan.cash = if summary.cash > 0
			then { figure = cash(summary.cash), caption = "Payout" .. suffix .. (if doubled then DOT .. DOUBLE.text else ""), count = summary.cash }
			else { figure = "No" .. NBSP .. "payout", caption = "Payout" .. suffix }
		plan.doubled = doubled
		--[[ THE HEAT BONUS, shown happening (2026-10-19): the count lands on what the run paid before
			it, the HEAT pill stamps onto the row, and the figure climbs to what was banked
			(`_playPanel`). `cash` already includes it, so the run's own figure is worked back out. ]]
		if plan.cash.count and summary.banked and summary.heat > 1 then
			plan.cash.base = math.round(summary.cash / summary.heat)
			plan.cash.heat = summary.heat
		end

		local distance = RewardConfig.formatDistance(summary.studs)
		if distance then
			plan.distance = { figure = distance, caption = "Driven" }
		end

		-- The near misses, and on a crash the drop from what they earned to what they kept.
		local tally = NearMissConfig.tallyLabel(summary.nearMisses, summary.rubs)
		if tally and summary.bonus > 0 then
			plan.bonus = { figure = cash(summary.bonus), caption = oneLine(tally) .. suffix }
			if summary.bonusEarned > summary.bonus then
				plan.bonus.figure = cash(summary.bonusEarned)
				plan.bonus.caption = oneLine(tally)
				plan.bonus.from = summary.bonusEarned
				plan.bonus.count = summary.bonus
				plan.bonus.dropCaption = oneLine(tally) .. suffix
			end
		end
	end
	if leveled then
		plan.level = { figure = oneLine(string.format("Level %d", leveled.level)), caption = oneLine(GarageConfig.displayName(tostring(leveled.body))) }
	end

	local shown = false
	for key, entry in plan do
		local row = rows[key]
		if not (row and type(entry) == "table" and entry.figure) then
			continue -- `doubled` rides on the plan beside the rows
		end
		row.figure.Text = entry.figure
		row.caption.Text = entry.caption
		row.row.Visible = true
		shown = true
	end
	self:_paintDoubleBadge(rows.cash, plan.doubled == true)
	if self._heatPill then
		self._heatPill.Visible = false -- stamped by `_playPanel` when this run has one
	end

	if summary then
		self._ladder = self:_planLadder(summary.studs)
		self:_paintPanelLadder(self._ladder, ramp, if crashed then colours.crashTint else colours.bankTint)
	end

	self._plan = plan
	return shown
end

--[[ The HEAT pill (`HEAT_PILL`), stamped onto the payout row: big and clear, then down onto the row's
	top edge with a jolt of the row, the way a rubber stamp lands. Built once, inside the row. ]]
function RaceUIController._stampHeat(self, row, heat: number, token: number)
	if not (row and row.row) then
		return
	end
	local pill = self._heatPill
	if not pill or pill.Parent ~= row.row then
		if pill then
			pill:Destroy()
		end
		pill = Instance.new("TextLabel")
		pill.Name = "HeatPill"
		pill.AnchorPoint = Vector2.new(1, 0.5)
		pill.Position = UDim2.fromScale(1.02, 0.02)
		pill.Size = UDim2.fromScale(0.36, 0.5)
		pill.Rotation = HEAT_PILL.rotation
		pill.BackgroundColor3 = HEAT_PILL.colour
		pill.Font = Enum.Font.FredokaOne
		pill.TextScaled = true
		pill.TextColor3 = Color3.new(1, 1, 1)
		pill.ZIndex = (row.figure and row.figure.ZIndex or 1) + 2
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = pill
		local rim = Instance.new("UIStroke")
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rim.Color = HEAT_PILL.ink
		rim.Thickness = 2
		rim.Parent = pill
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.08, 0)
		pad.PaddingRight = UDim.new(0.08, 0)
		pad.Parent = pill
		local scale = Instance.new("UIScale")
		scale.Parent = pill
		pill.Parent = row.row
		self._heatPill = pill
	end
	local text = string.format("%.2f", heat):gsub("0+$", ""):gsub("%.$", "")
	pill.Text = string.format(HEAT_PILL.text, text)
	pill.Visible = true
	local scale = pill:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = HEAT_PILL.from
	local land = self:_tween(scale, HEAT_PILL.stampTime, { Scale = 1 }, Enum.EasingStyle.Quad)
	land.Completed:Once(function()
		if self._token == token then
			self:_punchRow("cash", token)
		end
	end)
end

--[[ The gold 2x CASH badge on the payout row (header note at `DOUBLE.text`). Built once, on first
	need, inside the row so it rides the row's own reveal and scale; hidden on every other paint. ]]
function RaceUIController._paintDoubleBadge(self, row, shown: boolean)
	local badge = self._doubleBadge
	if not shown then
		if badge then
			badge.Visible = false
		end
		return
	end
	if not (row and row.row) then
		return
	end
	if not badge or badge.Parent ~= row.row then
		if badge then
			badge:Destroy()
		end
		badge = Instance.new("TextLabel")
		badge.Name = "DoubleCash"
		badge.AnchorPoint = Vector2.new(1, 0.5)
		badge.Position = UDim2.fromScale(0.98, 0.5)
		badge.Size = UDim2.fromScale(0.3, 0.55)
		badge.BackgroundColor3 = DOUBLE.gold
		badge.Font = Enum.Font.FredokaOne
		badge.TextScaled = true
		badge.Text = DOUBLE.text
		badge.TextColor3 = Color3.fromRGB(70, 35, 0)
		badge.ZIndex = (row.figure and row.figure.ZIndex or 1) + 1
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = badge
		local rim = Instance.new("UIStroke")
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rim.Color = Color3.fromRGB(70, 35, 0)
		rim.Thickness = 2
		rim.Parent = badge
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.1, 0)
		pad.PaddingRight = UDim.new(0.1, 0)
		pad.Parent = badge
		badge.Parent = row.row
		self._doubleBadge = badge
	end
	badge.Visible = true
end

--[[ The ladder's resting state: ticks laid, fill empty, car on the start line. With no plan the
	whole strip goes, which is the panel's version of the shipping bar falling back to a hairline. ]]
function RaceUIController._paintPanelLadder(self, plan, ramp: ColorSequence?, tint: Color3?)
	local ladder = self._panelLadder
	for _, tick in self._panelTicks do
		tick:Destroy()
	end
	self._panelTicks = {}

	local track = ladder.track
	local left = track.Position.X.Scale - track.AnchorPoint.X * track.Size.X.Scale
	ladder.fill.Visible = false -- a pill squeezed to nothing still draws its own rim (the Quest note)
	ladder.fill.Size = UDim2.fromScale(0, 1)
	ladder.marker.Position = UDim2.new(UDim.new(left, 0), ladder.markerY)
	ladder.frame.Visible = plan ~= nil
	if not plan then
		return
	end

	if ladder.fillRamp and ramp then
		ladder.fillRamp.Color = ramp
	end
	--- The glyph's tint IS the ending, exactly as on the shipping bar.
	ladder.marker.ImageColor3 = tint or PAYOUT_COLOR

	for index, at in plan.marks do
		local tick = Instance.new("Frame")
		tick.Name = "Tick" .. index
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.fromScale(at, 0.5)
		tick.Size = UDim2.fromScale(PANEL_TICK_WIDTH, 1)
		tick.BackgroundColor3 = PANEL_TICK_COLOR
		tick.BackgroundTransparency = TICK_AHEAD
		tick.BorderSizePixel = 0
		tick.Parent = ladder.ticks
		self._panelTicks[index] = tick
	end
end

--- Drive the car glyph along the ladder, the fill as its wake, and light the rungs it reached.
function RaceUIController._playPanelLadder(self, plan)
	local ladder = self._panelLadder
	local track = ladder.track
	local left = track.Position.X.Scale - track.AnchorPoint.X * track.Size.X.Scale
	if plan.progress > 0 then
		ladder.fill.Visible = true
		self:_tween(ladder.fill, MARKER_TRAVEL, { Size = UDim2.fromScale(plan.progress, 1) })
	end
	self:_tween(ladder.marker, MARKER_TRAVEL, {
		Position = UDim2.new(UDim.new(left + track.Size.X.Scale * plan.progress, 0), ladder.markerY),
	})
	for index, tick in self._panelTicks do
		self:_tween(tick, 0.3, { BackgroundTransparency = if index <= plan.reached then TICK_REACHED else TICK_AHEAD })
	end
end

--[[ A figure counting to its value, up or down. `_countUp` and `_countDown`'s shared shape for the
	panel, including the part that matters: THE FINAL VALUE IS WRITTEN FIRST, so a client whose
	renderer never ticks is left on the true number. `field` is which of the two handles `_show`
	disconnects this under. ]]
function RaceUIController._countPanel(self, label: TextLabel, from: number, to: number, duration: number, token: number, field: string, done: (() -> ())?)
	label.Text = "+" .. GarageConfig.formatCash(to)
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if self._token ~= token then
			connection:Disconnect()
			return
		end
		local t = math.min(1, (os.clock() - started) / duration)
		local eased = 1 - (1 - t) ^ 3
		label.Text = "+" .. GarageConfig.formatCash(math.floor(from + (to - from) * eased + 0.5))
		if t >= 1 then
			connection:Disconnect()
			self[field] = nil
			if done then
				done()
			end
		end
	end)
	self[field] = connection
end

--- The payout landing: the whole card flexes, for the reason `_punch` flexes the shipping line.
function RaceUIController._punchRow(self, key: string, token: number)
	local scale = self._panelRows[key].scale
	local up = self:_tween(scale, 0.09, { Scale = ROW_PUNCH })
	up.Completed:Once(function()
		if self._token == token then
			self:_tween(scale, 0.2, { Scale = 1 })
		end
	end)
end

--[[ `_playResults` for the panel. The same beats, fenced the same way. ]]
function RaceUIController._playPanel(self, token: number)
	local plan, rows = self._plan, self._panelRows
	if not plan then
		return
	end

	local function beat(delay: number, step: () -> ())
		task.delay(delay, function()
			if self._token == token and self._visible then
				step()
			end
		end)
	end

	local function pop(key: string, time: number)
		return self:_tween(rows[key].scale, time, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	-- The panel, once the black has landed: nothing on it should open under a race still showing.
	beat(BEAT_START, function()
		self._panel.Visible = true
		self._panelScale.Scale = PANEL_START_SCALE
		self:_tween(self._panelScale, PANEL_OPEN_TIME, { Scale = 1 }, Enum.EasingStyle.Back)
	end)

	-- The car lands in its card, exactly as it lands on the overlay. See `_playResults`.
	beat(BEAT_TROPHY, function()
		if not self._trophy.Visible then
			return
		end
		self:_tween(self._trophy, 0.45, { Size = UDim2.fromScale(self._trophyRest, self._trophyRest) }, Enum.EasingStyle.Back)
		self:_tween(self._viewport, 0.3, { ImageTransparency = 0 })
		if self._bankedScreen then
			self:_tween(self._burst, 0.55, { ImageTransparency = SUNBURST_REST })
		end
	end)

	local ladder = self._ladder
	if ladder then
		beat(BEAT_LADDER, function()
			self:_playPanelLadder(ladder)
		end)
	end

	beat(BEAT_CASH, function()
		local entry = plan.cash
		if not entry then
			return
		end
		pop("cash", ROW_POP_TIME)
		self:_playSound(PAYOUT_SOUND_ID)
		if entry.base then
			--[[ Two counts with the stamp between. The second is started off a TIMER, not the first
				count's finish: that finish runs on RenderStepped, and a renderer that never ticks must
				still end on the paid figure (`_countUp`'s note), which the second count writes first. ]]
			self:_countPanel(rows.cash.figure, 0, entry.base, COUNT_TIME, token, "_countConn")
			beat(COUNT_TIME + HEAT_PILL.delay, function()
				self:_stampHeat(rows.cash, entry.heat, token)
				self:_playSound(PAYOUT_SOUND_ID)
				self:_countPanel(rows.cash.figure, entry.base, entry.count, HEAT_PILL.countTime, token, "_countConn", function()
					self:_punchRow("cash", token)
				end)
			end)
		elseif entry.count then
			self:_countPanel(rows.cash.figure, 0, entry.count, COUNT_TIME, token, "_countConn", function()
				self:_punchRow("cash", token)
			end)
		else
			beat(ROW_POP_TIME, function()
				self:_punchRow("cash", token)
			end)
		end
	end)

	beat(BEAT_DISTANCE, function()
		if plan.distance then
			pop("distance", ROW_POP_TIME)
		end
	end)

	beat(BEAT_BONUS, function()
		local entry = plan.bonus
		if not entry then
			return
		end
		pop("bonus", ROW_POP_TIME)
		-- On a crash, the split takes its share once the full figure has been read; see `BONUS_DROP_DELAY`.
		if entry.from then
			beat(BONUS_DROP_DELAY, function()
				rows.bonus.caption.Text = entry.dropCaption
				self:_countPanel(rows.bonus.figure, entry.from, entry.count, BONUS_DROP_TIME, token, "_dropConn")
			end)
		end
	end)

	beat(BEAT_LEVEL, function()
		if not plan.level then
			return
		end
		self:_playSound(LEVEL_SOUND_ID)
		pop("level", LEVEL_POP_TIME)
	end)
end

--[[ Close the showcase when there is no car in it (a bail on the tarmac, a fall out of the world, a
	level-up with no run behind it), and centre the receipts in the room it leaves. An empty
	coloured card beside the numbers would read as a picture that failed to load. ]]
function RaceUIController._layoutPanel(self, showCar: boolean)
	self._panelShowcase.Visible = showCar
	local at = self._panelReceiptsAt
	self._panelReceipts.Position = if showCar then at else UDim2.new(UDim.new(0.5, 0), at.Y)
end

--[[ The panel's exit, the kit pages' close, on the same half-fade the overlay's furniture takes.
	Hidden once it lands, fenced on the hide's token so a screen raised over the tail keeps it. ]]
function RaceUIController._lowerPanel(self, token: number)
	if not self._panel.Visible then
		return
	end
	local tween = self:_tween(self._panelScale, PANEL_CLOSE_TIME, { Scale = PANEL_START_SCALE })
	tween.Completed:Once(function()
		if self._token == token and not self._visible then
			self._panel.Visible = false
		end
	end)
end

--[[ Raise the screen. `loading` is the entry — the one direction that has steps worth drawing (see
	`THE LOADING BAR`); the way home is either a results beat or a plain fade. ]]
function RaceUIController._show(self, label: string?, loading: boolean?)
	if not self._gui then
		self:_build()
	end
	local resultsPrepared = self._resultsPrepared == true
	--[[ THE ONE-SCREEN WRECK HAS ALREADY REPORTED THIS RUN (`NewUIConfig.WreckPanel`). The revive
		panel drew the money, the bar and the car, and was answered: END RUN wants the plain fade home,
		and a countdown that ran out wants the next race. So the summary it would have drawn is dropped
		before anything paints it, which makes this an ordinary no-results screen (the word and the
		ring), and `"replay"` holds the black for the entry below. Read once and cleared, so it can only
		ever apply to the return it was published for. ]]
	local afterPanel = self._afterPanel
	self._afterPanel = nil
	if afterPanel then
		self._summary = nil
		self._leveled = nil
		resultsPrepared = false
		label = if afterPanel == "replay" then ENTER_LABEL else RETURN_LABEL
	end
	self._resultPrepareToken = (self._resultPrepareToken or 0) + 1
	self._resultsPrepared = false
	self._visible = true
	self._hiding = false -- this screen takes over from whatever was on its way out
	self._shownAt = os.clock()
	--[[ Every late hold booked against the LAST screen goes with it. `_holdUntil` is an absolute
		time, so an abort message that was still owed half a second when the player pressed Play
		again would otherwise sit on the entry screen that replaced it. ]]
	self._holdUntil = nil
	--[[ ...and the RACE AGAIN offer with it. If this show is the one a replay press was waiting for
		(`_playReplay` held the black open for exactly this), that hand-over is finished the moment
		this screen starts painting; if it is anything else, the offer belonged to a run that is over.
		Either way the button goes back to the state `_build` left it in. ]]
	self._replaying = false
	self:_resetReplay()
	self._loading = false -- `_paintLoading` turns this back on for an entry
	self._loadRevealed = false
	--- ...and the backdrop with it, for the same reason and in the same beat: it belongs to an entry
	--- only (see `BACKDROP_TINT`), and clearing it here means every other kind of screen starts from
	--- a clean overlay rather than inheriting a road from the last one.
	if self._backdrop then
		self._backdrop.Visible = false
		self._backdrop.ImageTransparency = 1
	end
	self._aborted = false
	local token = (self._token or 0) + 1
	self._token = token

	--[[ Clear the last screen off this one before painting. The token goes first, so that anything
		woken by a cancellation (a punch waiting on Completed) already sees itself as stale; then
		the tweens, then the count — whose own token check would catch it a frame later, and a frame
		later is one frame of the last run's money on this run's screen. ]]
	self:_cancelTweens()
	if self._countConn then
		self._countConn:Disconnect()
		self._countConn = nil
	end
	-- The bonus line's drop, on the same terms and for the same reason. It outlives the payout count
	-- by well over a second, so it is the one MORE likely to still be running when a screen is taken
	-- over — a fast re-entry would otherwise tick the last run's split down over this run's tally.
	if self._dropConn then
		self._dropConn:Disconnect()
		self._dropConn = nil
	end

	-- The kit panel comes down with whatever screen this one takes over; `_playPanel` raises it
	-- again once the fade has landed, if there is anything on it.
	if self._panel then
		self._panel.Visible = false
	end

	-- Measure the road BEFORE painting anything, because `_paintPayout` plots the ladder against it
	-- and this is the last moment the road is still standing (see `_latchRoad`).
	local hasResults
	if resultsPrepared then
		hasResults = self._preparedHasResults == true
	else
		self:_latchRoad()
		hasResults = self:_paintPayout()
	end
	self._hasResults = hasResults
	--[[ WHETHER THIS SCREEN OFFERS ANOTHER RUN, decided once, here, because everything downstream
		of it reads the answer rather than working it out again: the beat that raises the button, the
		drain that empties under it, the press that locks it.

		THREE THINGS HAVE TO BE TRUE. There has to be a result to offer it on — an entry screen is the
		player already going somewhere, and an aborted entry (`_onAborted`) is the game telling them it
		could not, which is the last moment to ask for a second helping of it. The kit panel has to be
		absent, for the reason `REPLAY_PILL`'s block gives: that panel owns the room this button stands
		in and wants a slot of its own authored in `BuildRaceResultsV2` rather than a pill on top of
		it. And the feature has to be switched on.

		THE HOLD IS BOOKED HERE AND NOWHERE ELSE. `_hide` measures its own holds from this instant and
		takes whichever of them and `_holdUntil` is further off, so booking the floor is the whole of
		what makes the screen stand long enough to be answered — and `REPLAY_HOLD` is longer than both
		the wreck hold and the bank hold, so it is the one that wins whenever it is booked at all. ]]
	self._replayable = RaceConfig.Replay.Enabled and hasResults and self._panel == nil
	if self._replayable then
		self:_holdFor(REPLAY_HOLD)
	end
	local headline = if hasResults then self:_headline() else nil
	self._label.Text = headline or label or ENTER_LABEL

	--[[ THE LIGHTS COME UP EXACTLY WHEN THE WORD DOES, which is why this is read off the headline
		rather than worked out again from `_wreckCause`. They are the same statement made twice —
		one in type and one in light — and a second derivation of "was this a bust" is a second
		thing that can end up answering differently from the first.

		Cleared unconditionally either way: a bust two runs ago must not still be flashing behind an
		entry screen. See `_clearLights`. ]]
	self:_clearLights()
	self._bustedScreen = headline == BUST_HEADLINE
	--- ...and the plume goes out on the same terms and for the same reason. A wreck two runs ago
	--- must not still be smoking behind an entry screen. See `_clearSmoke`.
	self:_clearSmoke()

	--[[ ...and then the entry screen names where it is going instead. After the paint above rather
		than instead of it, because `_paintPayout` is also the reset — it is what clears the last
		run's bar and lines off the widgets this is about to draw its own bar on.

		`hasResults` cannot be true for an entry (`_onEntering` drops the summary first), so the two
		are exclusive by construction; the test is here so that a summary arriving from somewhere
		unexpected can only cost the loading bar, never fight it for the same instances. ]]
	if loading and not hasResults then
		self:_paintLoading()
	end

	--[[ THE TROPHY AND THE SPINNER ARE THE SAME SLOT, so exactly one of them ever comes up. A car is
		only shown on the screen that has both a car in hand and a run that BANKED — a wreck can carry a
		stale trophy from the getaway two runs ago, and a getaway whose dress could not be cloned
		carries none, so neither the summary nor the model can be trusted on its own. ]]
	local summary = self._summary
	local banked = hasResults and self._trophyCar ~= nil and summary ~= nil and summary.banked

	--[[ ...and a BUST fills the same slot with the cruiser instead, which is why this is built here
		rather than handed in: there is nothing to catch, the template is always in hand, and doing it
		at show time is what keeps a stale banked car from ever being mistaken for one (`_showBustCar`
		clears the slot before it fills it, and answers false if it cannot).

		A bust can therefore be the ONE case where `_trophyCar` is set on a run that did not bank,
		which is precisely why the test above is `banked` and not `_trophyCar ~= nil`. ]]
	local showTrophy = banked
	if self._bustedScreen then
		showTrophy = self:_showBustCar()
	elseif hasResults and not banked then
		--[[ ...and the third thing this slot can hold: the car the run ended IN, caught at the wreck
			(`setWreck`) rather than built here. Unlike the cruiser there is exactly one of it and it
			was destroyed seconds ago, so there is nothing to build and nothing to look up.

			`_slotWreck` is false for every ending that had no car worth catching, which is a bail
			face down on the tarmac and a fall out of the world. Those still draw the screen that
			shipped before any of this: the word, the bar and the numbers. ]]
		showTrophy = self._slotWreck
	end
	--[[ Latched HERE rather than read off `_summary` in `_hide`, for the same reason `_hasResults` is:
		what the hold is owed depends on what this screen was PAINTED as, and `_onEntering` clears the
		summary the moment a new run starts. Read late, a bank whose screen was still up when the
		player re-entered would fall back to the short hold. ]]
	self._bankedScreen = banked
	--[[ ...and the same latch for the plume, which is the wreck's answer to the bust's lights. Read
		off what this screen was PAINTED as rather than worked out again from the summary, which is
		`_bankedScreen`'s argument exactly: two derivations of "was this a wreck" is two things that
		can end up answering differently. A bust and a wreck are exclusive by construction, so the
		two effects can never both be running. ]]
	self._wreckedScreen = showTrophy and not banked and not self._bustedScreen
	self._trophy.Visible = showTrophy
	if showTrophy then
		self._trophy.Size = UDim2.fromScale(self._trophyRest * TROPHY_RISE, self._trophyRest * TROPHY_RISE)
		self._stroke.Transparency = 1 -- no ring under the car, and no fade-in for one either
	end
	--[[ ON THE KIT PANEL THE HEADLINE IS THE PANEL'S TITLE, and the overlay's own line and ring stay
		dark under it: the panel covers the middle of the screen where both are drawn, and a ring
		turning behind a finished total is the "wait" `_playResults` argues against. The panel closes
		up round a showcase with nothing in it. ]]
	local panelResults = hasResults and self._panel ~= nil
	if panelResults then
		self._panelTitle.Text = headline or label or RETURN_LABEL
		self:_layoutPanel(showTrophy)
	end

	self._gui.Enabled = true
	self:_tween(self._overlay, FADE_IN_TIME, { BackgroundTransparency = 0 })
	--- On the overlay's own fade and its own clock, so the road arrives WITH the black rather than
	--- appearing on top of it a moment later — which would read as a second transition inside the
	--- first. `_paintLoading` has already set the image and made it visible by the time this runs.
	if self._backdrop.Visible then
		self:_tween(self._backdrop, FADE_IN_TIME, { ImageTransparency = BACKDROP_ALPHA })
	end
	if panelResults then
		self:_tween(self._stroke, FADE_IN_TIME, { Transparency = 1 })
		self:_tween(self._label, FADE_IN_TIME, { TextTransparency = 1 })
	else
		if not showTrophy then
			self:_tween(self._stroke, FADE_IN_TIME, { Transparency = 0 })
		end
		self:_tween(self._label, FADE_IN_TIME, { TextTransparency = 0.1 })
	end
	if hasResults then
		self:_playResults(token)
	elseif self._loading then
		self:_playLoading(token)
	end

	-- Spin the ring (or the car) while visible. The stroke is resolved from the viewport here rather
	-- than set once at build time because it is the screen's only pixel measurement (see the header)
	-- and because the viewport can change under it — a rotated phone, a resized window.
	if not self._spinConn then
		self._spinConn = RunService.RenderStepped:Connect(function(dt)
			local camera = workspace.CurrentCamera
			if self._spinner then
				self._spinner.Rotation = (self._spinner.Rotation + dt * 320) % 360
			end
			if self._stroke and camera then
				self._stroke.Thickness = math.max(2, camera.ViewportSize.Y * SPINNER_THICKNESS)
			end
			-- The loading bar rides this loop for the same reason the spinner does: it is a per-frame
			-- approach rather than a tween (see `_loadTick`), and this is the frame loop the screen
			-- already owns and already tears down when it goes.
			if self._loading then
				self:_loadTick(dt)
			end
			--[[ The bust lights, on the same loop and for the same reason the loading bar is: it is
				a per-frame pattern rather than a tween, and this is the frame loop that is already
				torn down when the screen goes.

				THE FADE IS READ OFF THE OVERLAY rather than tracked separately. The overlay's own
				transparency IS this screen's fade in both directions, so taking the lights' alpha
				from it means they cannot come up over a race that is still showing through on the
				way in, and cannot be left burning on the way out. ]]
			if self._bustedScreen then
				local since = os.clock() - (self._shownAt or 0) - BEAT_START
				self:_stepLights(since, 1 - self._overlay.BackgroundTransparency)
			end
			--[[ ...and the plume, on the same loop, off the same overlay, for every reason the
				lights above are. It is measured from `BEAT_TROPHY` rather than from `BEAT_START`
				because it is the CAR's smoke: there is nothing for it to be coming out of until the
				car has landed. ]]
			if self._wreckedScreen then
				local burning = os.clock() - (self._shownAt or 0) - BEAT_TROPHY
				self:_stepSmoke(burning, 1 - self._overlay.BackgroundTransparency)
			end
			--[[ The RACE AGAIN clock, on the same loop and for the same reason the two above are: it
				is a per-frame redraw off a deadline rather than a tween, and this is the frame loop
				this screen already owns and already tears down when it goes. `_stepReplayDrain` bails
				on its own when there is no offer standing. ]]
			self:_stepReplayDrain()
			if self._trophy and self._trophy.Visible then
				--- The turntable and its backdrop belong to the prize. A bust holds its angle and
				--- lets the light bar do the moving; see `THE CRUISER`.
				if self._bankedScreen then
					self._burstAngle = ((self._burstAngle or 0) + dt * SUNBURST_SPIN) % 360
					self._burst.Rotation = self._burstAngle
					self._carAngle = ((self._carAngle or CAR_YAW) + dt * CAR_SPIN) % 360
				end
				self:_aimTrophy()
			end
		end)
	end

	-- Safety: never let the fade stick if RaceLive never comes.
	task.delay(SAFETY_TIMEOUT, function()
		if self._token == token and self._visible then
			self:_hide()
		end
	end)

	--[[ ...and the countdown that ran out on the revive panel: the screen goes straight to "Entering
		race" and STAYS black, exactly as a RACE AGAIN press leaves it (`_playReplay`), so the next run's
		loading screen lands on it with no lobby in between. `RaceEntryController` queues the request
		until `RaceEnd`, so asking now is safe. The fence counts from here rather than from a press,
		which is the return fade earlier, so it gets that fade added on. ]]
	if afterPanel == "replay" then
		self._replaying = true
		self:_fenceReplay(token, RaceConfig.Replay.Timeout + RaceConfig.ReturnFadeTime)
		Dispatcher:Publish(RaceConfig.ReplayEvent)
	end
end

--[[ Drop the screen — after it has been up long enough to have been worth putting up.

	`MIN_HOLD_TIME` on the way in, so even an instant entry reads as a deliberate transition, and
	`RESULTS_HOLD_TIME` on the way out, so the beat gets to finish and the numbers get to be read.

	THE TOKEN DOES NOT TURN OVER UNTIL THE HOLD IS DONE, and that is the part to be careful with:
	the results beat is fenced on the SHOW's token, and `RaceLive` — which is what calls this —
	usually lands about a second into it. Bumping the token here (which is what this used to do
	first thing) would cancel the animation exactly when it was getting going. A `_hiding` flag
	covers what the bump used to: a second call during the hold, and the safety timeout.

	`immediate` DROPS THE HOLD ENTIRELY, and there is exactly one caller that passes it: the fence
	under a replay that was never answered (`_playReplay`). The hold exists so a beat can be read,
	and by then the beat has been read, faded off and given up on. Nothing else should pass it —
	a screen that skipped its own hold would be a screen nobody got to see. ]]
function RaceUIController._hide(self, immediate: boolean?)
	if not (self._gui and self._visible) or self._hiding then
		return
	end
	--[[ A REPLAY HAS TAKEN THE SCREEN, so there is nothing here to drop: the black is being held
		open for the entry that was just asked for (`_playReplay`) and the player is not going home.
		This catches the `RaceLive` that lands AFTER a press — `leaveRace` fires it about half a
		second into the screen, but a slow one, or the safety timeout, would otherwise fade the
		overlay off a player who is on their way back out. The fence in `_playReplay` is what clears
		the flag if the entry never comes, and it calls back in here itself. ]]
	if self._replaying then
		return
	end
	self._hiding = true

	local hold = if self._hasResults
		then (if self._bankedScreen then BANK_HOLD_TIME else RESULTS_HOLD_TIME)
		else MIN_HOLD_TIME
	local wait = math.max(0, hold - (os.clock() - (self._shownAt or 0)))
	-- ...and whatever a late beat booked for itself, which the hold above cannot express because it
	-- is measured from the show and they are not. See `_holdFor`. A RACE AGAIN offer is booked this
	-- way too, and it is the longest floor any screen here books.
	if self._holdUntil then
		wait = math.max(wait, self._holdUntil - os.clock())
	end
	if immediate then
		wait = 0
	end
	local shownToken = self._token

	task.delay(wait, function()
		if self._token ~= shownToken or not self._hiding then
			return -- a new entry started; let it own the screen
		end
		self._visible = false
		self._hiding = false
		--- Read before the line below clears it: a loading screen that did not abort is an entry
		--- lifting off its road, and that is the one lift anybody else is told about.
		local revealing = self._loading and not self._aborted
		-- The bar stops being drawn the moment the screen starts leaving. Mostly it would just be
		-- work nobody can see, but not entirely: a tick lighting up (which is a tween) during the
		-- fade-out would be tweening one of the properties the fade below is already tweening.
		self._loading = false
		local token = (self._token or 0) + 1
		self._token = token

		self:_tween(self._stroke, FADE_OUT_TIME * 0.5, { Transparency = 1 })
		self:_tween(self._label, FADE_OUT_TIME * 0.5, { TextTransparency = 1 })
		self:_tween(self._rule, FADE_OUT_TIME * 0.5, { BackgroundTransparency = 1 })
		self:_tween(self._fill, FADE_OUT_TIME * 0.5, { BackgroundTransparency = 1 })
		self:_tween(self._marker, FADE_OUT_TIME * 0.5, { ImageTransparency = 1 })
		for _, tick in self._tickList or {} do
			self:_tween(tick, FADE_OUT_TIME * 0.5, { BackgroundTransparency = 1 })
		end
		self:_tween(self._burst, FADE_OUT_TIME * 0.5, { ImageTransparency = 1 })
		self:_tween(self._viewport, FADE_OUT_TIME * 0.5, { ImageTransparency = 1 })
		for _, line in self._lines do
			self:_tween(line, FADE_OUT_TIME * 0.5, { TextTransparency = 1 })
		end
		--[[ ...and the offer, on the same half-fade as the rest of the furniture. `_replayable` is
			dropped FIRST and it is what actually closes the offer — every press, from a thumb or from
			a pad, reads it — so nothing can start a race off a button that has visibly gone. See
			`_dropReplayPad` for why the binding is allowed to outlive it by the length of the fade. ]]
		self._replayable = false
		self._replayUntil = nil
		self:_dropReplayPad(FADE_OUT_TIME * 0.5)
		self:_tween(self._replayButton, FADE_OUT_TIME * 0.5, { ImageTransparency = 1 })
		self:_tween(self._replayCaption, FADE_OUT_TIME * 0.5, { TextTransparency = 1 })
		self:_tween(self._replayTrack, FADE_OUT_TIME * 0.5, { BackgroundTransparency = 1 })
		self:_tween(self._replayDrain, FADE_OUT_TIME * 0.5, { BackgroundTransparency = 1 })
		if self._panel then
			self:_lowerPanel(token)
		end
		--[[ The backdrop goes out on the FULL fade, not the half the widgets above use.

			Those are furniture being cleared off the screen before it lifts; this one IS the screen.
			Clearing it early would uncover the world underneath while the overlay was still black —
			the exact "watching it render in" this was added to hide, arrived at from the other
			side. ]]
		if self._backdrop.Visible then
			self:_tween(self._backdrop, FADE_OUT_TIME, { ImageTransparency = 1 })
		end
		local tween = self:_tween(self._overlay, FADE_OUT_TIME, { BackgroundTransparency = 1 })
		tween.Completed:Once(function()
			if self._token == token and not self._visible then
				self._gui.Enabled = false
				if self._spinConn then
					self._spinConn:Disconnect()
					self._spinConn = nil
				end
				-- The car has been seen; drop it here rather than at the next entry, so a copy of
				-- ~40 MeshParts isn't sitting under PlayerGui for however long the player spends in
				-- the lobby. A new bank builds a new one.
				self:_clearTrophy()
				--[[ ...and the lights, which the fade above has already taken to nothing but only
					BY ARITHMETIC: they are painted from the overlay's own transparency every frame
					(see `_stepLights`), and the frame this callback lands on is not promised to be
					after the render step that saw the overlay finish. A hundredth of an alpha left
					on a disabled `ScreenGui` is invisible and stays invisible, right up until
					something re-enables the screen without repainting them. ]]
				self._bustedScreen = false
				self._wreckedScreen = false
				self:_clearSmoke()
				self:_clearLights()

				--[[ ...and the other half of the pair below: a screen that was not an entry has
					just finished lifting, so the player is stood in the lobby with nothing over
					them (`RaceConfig.ReturnedEvent`). The carry hint waits for this rather than for
					`RaceEnd`, which lands while the results are still up.

					LAST IN THIS CALLBACK, and for the same reason the reveal is last in the block
					below: `Dispatcher:Publish` runs its subscribers on this thread, and one that
					threw higher up would leave the screen enabled behind a finished fade. ]]
				if not revealing then
					Dispatcher:Publish(RaceConfig.ReturnedEvent)
				end
			end
		end)

		--[[ Told as the fade STARTS rather than when it lands, because this is the moment the road
			starts showing through, and the soundtrack crossfades on it (`RaceConfig.RevealedEvent`).

			LAST, AFTER EVERY TWEEN ABOVE IS RUNNING. `Dispatcher:Publish` runs its subscribers on
			this thread, so one that threw anywhere earlier would take the rest of the fade with it
			and leave the player behind a black screen. Down here it cannot. ]]
		if revealing then
			Dispatcher:Publish(RaceConfig.RevealedEvent)
		else
			-- The same moment for every other screen, for anything that must cover the lobby before
			-- it shows through (`RaceConfig.LiftingEvent`). Last for the same reason as the reveal.
			Dispatcher:Publish(RaceConfig.LiftingEvent)
		end
	end)
end

function RaceUIController._onEntering(self)
	-- A new run: last run's result stops being true the moment this one starts. The trophy goes with
	-- them — the fade normally drops it, but an entry can also arrive over a results screen that
	-- never got to finish, and a car from the run before last on THIS screen would be a lie.
	self._summary, self._leveled = nil, nil
	-- ...and an answer from the revive panel that no return ever came for. It belongs to that run.
	self._afterPanel = nil
	self._resultPrepareToken = (self._resultPrepareToken or 0) + 1
	self._resultsPrepared = false
	self:_clearTrophy()
	self:_show(nil, true)
end

--[[ The server says the car is live, so the screen can go.

	NO WORLD-READINESS CHECK HERE, and it is worth saying why not, because there was one briefly and
	it was the wrong shape. Holding the SCREEN until the road finished did not stop the car driving
	— the ack had already released it — so all it bought was a longer stretch of the player being
	unable to see the road they were already on. The gate belongs on the ack, and that is where it
	is now: `RoadController` will not fire `RaceReady` until `isWorldReady()`, so by the time this
	runs the road is up by construction and there is nothing left to wait for.

	Keeping a second copy of the test here would also have been a liability rather than a backstop:
	the server fires `RaceLive` on paths that have no road at all (an entry with nothing to enter),
	and a wait that could not be satisfied would sit on those for its whole timeout. ]]
function RaceUIController._onLive(self)
	-- Land the bar before dropping the screen, and not after: `_finishLoad` books the hold that
	-- gives the car time to reach the end of its own track, and `_hide` reads that hold on the very
	-- next line.
	self:_finishLoad()
	self:_hide()
end

--[[ Public (AdminPanelController): put the busted screen up out of nowhere, so it can be looked at.

	THE WHOLE POINT IS THAT IT IS NOT A SHORTCUT PAST THE SCREEN. It sets the two facts a real bust
	arrives with — a settled run that did not bank, and a wreck whose cause is the police — and then
	calls the same `_show`/`_hide` pair the remotes call, in the same order, with nothing else
	changed. Everything downstream of that is the real thing: the headline picks itself, the cruiser
	is built and framed, the lights run their envelope, and the hold and the fade are the ones a real
	bust gets, because `_hide` measures its wait from the show rather than from being called.

	The panel's "Bust me" is the other test and they are not the same test: that one really arrests
	you, which needs a live chase, a live race and about four minutes of driving to reach. This is
	for the twentieth time you want to look at the beat.

	THE NUMBERS ARE A FIXTURE AND THE STATE IS PUT BACK. A real summary is whatever the last run was
	worth, and borrowing it would make the preview say something different every time it was pressed
	— which is the opposite of what a thing you are staring at repeatedly should do. Everything it
	overwrites is stashed and restored on the same frame: `_show` is the only reader of any of it, so
	by the time this returns there is nothing left to put back, and a preview pressed in the middle
	of a live run cannot corrupt that run's own results.

	THE LADDER BAR WILL BE A PLAIN DIVIDER in the lobby, and that is honest rather than broken:
	`_latchRoad` has no road to measure there, which is exactly the degradation `_planLadder`
	returning nil is for. Press it on the way home from a real run and the ladder draws. ]]
function RaceUIController.debugBustScreen(self): boolean
	if not self._gui then
		self:_build()
	end

	local summary, leveled, cause = self._summary, self._leveled, self._wreckCause
	self._summary = {
		cash = 412,
		studs = 9140,
		banked = false,
		bonus = 78,
		nearMisses = 7,
		rubs = 3,
		bonusEarned = 312,
	}
	self._leveled = nil
	self._wreckCause = PoliceConfig.Cause

	self:_show(RETURN_LABEL)
	--- Immediately, and it is not a mistake: `_hide` holds for `RESULTS_HOLD_TIME` measured from the
	--- show, so calling it now books exactly the wait a real bust gets when `RaceLive` lands a second
	--- into the beat. Pressing the button again simply takes the screen over; the old hold is fenced
	--- on the token it was booked under and drops itself.
	self:_hide()

	self._summary, self._leveled, self._wreckCause = summary, leveled, cause
	return true
end

--[[ Public (AdminPanelController): put the WRECKED screen up out of nowhere, the same way.

	Everything `debugBustScreen` argues above applies here unchanged: a fixture rather than the last
	run's numbers, the state stashed and put back on the same frame, and the same `_show`/`_hide`
	pair the remotes call rather than a shortcut past either.

	THE ONE DIFFERENCE IS THAT IT NEEDS A CAR AND THERE ISN'T ONE. A real wreck screen shows the car
	the player was driving, handed in at the wreck; pressed in the lobby there is no race, no car,
	and `Workspace.CarSystem` is not replicated to clients at all. So it borrows a published traffic
	shell instead. `TrafficService` puts one stripped body per ownable car into `ReplicatedStorage`
	at startup and they are on every client already, which is the same source every car-in-a-box in
	this game draws from (`Modules/CarViewport`). The pose, the fold, the light and the plume are
	all the real ones. Only the car is a stand-in, and it is a stand-in for a car this game can
	genuinely put you in.

	THE SHELL IS PICKED BY NAME RATHER THAN BY WHATEVER IS FIRST IN THE FOLDER, for the reason the
	numbers are a fixture: a preview you press twenty times while tuning a shot must show the same
	thing twenty times. ]]
function RaceUIController.debugWreckScreen(self): boolean
	if not self._gui then
		self:_build()
	end

	local folder = ReplicatedStorage:FindFirstChild(TrafficConfig.TemplateFolderName)
	local name = TrafficConfig.Bodies[1]
	local template = folder and name and folder:FindFirstChild(name)
	if not (template and template:IsA("Model")) then
		return false
	end

	self:_clearTrophy()
	local clone = template:Clone()
	clone.Name = "WreckCar"
	--[[ The shell's own two structural parts (`TrafficService._buildShell`, and the same two
		`Modules/CarViewport` drops). Both are invisible and neither is bodywork; the hull in
		particular would frame the shot around a volume nobody can see, exactly as `HitBox` would on
		a live dress. `Root` is kept until it has been measured against and dropped after. ]]
	local root = clone.PrimaryPart or clone:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then
		clone:Destroy()
		return false
	end
	local frame = root.CFrame:Inverse()
	local hit = clone:FindFirstChild("Hit", true)
	if hit then
		hit:Destroy()
	end
	root:Destroy()
	if not self:_wreckFrom(clone, frame) then
		return false
	end

	local summary, leveled, cause = self._summary, self._leveled, self._wreckCause
	self._summary = {
		cash = 137,
		studs = 5420,
		banked = false,
		bonus = 24,
		nearMisses = 4,
		rubs = 2,
		bonusEarned = 96,
	}
	self._leveled = nil
	--- No cause at all, which is the ordinary death: HP gone. That is the ending this screen is for,
	--- and it is what makes `_headline` pick WRECKED over the police's word.
	self._wreckCause = nil

	self:_show(RETURN_LABEL)
	self:_hide()

	self._summary, self._leveled, self._wreckCause = summary, leveled, cause
	return true
end


RaceUIController:withRemoteEvents({
	{
		--[[ The run's payout, from RewardService. It lands the moment the run ends — the instant HP
			hits zero, or the instant the truck takes the car — which is a beat or two BEFORE
			`RaceReturning` raises the fade this is drawn on. Stored rather than shown, and shown
			when there is a screen to show it on. ]]
		RunSettled = function(
			cash: number,
			studs: number,
			banked: boolean,
			bonus: number,
			misses: number,
			rubs: number,
			bonusEarned: number,
			mutation: string?,
			heat: number?
		)
			RaceUIController._summary = {
				cash = if type(cash) == "number" then cash else 0,
				studs = if type(studs) == "number" then studs else 0,
				banked = banked == true,
				--[[ The near-miss tally, as the SERVER settled it — deliberately not as the toasts
					priced it during the run. NearMissController's header says why the two are allowed to
					be separate code paths at all; this is the half that is authoritative. ]]
				bonus = if type(bonus) == "number" then bonus else 0,
				nearMisses = if type(misses) == "number" then misses else 0,
				rubs = if type(rubs) == "number" then rubs else 0,
				--[[ …and the same bonus before the crash split, which the bonus line counts down FROM.
					RewardService sends 0 for every run that has no drop to draw, so this needs no test
					of its own beyond "is it bigger than what was kept". ]]
				bonusEarned = if type(bonusEarned) == "number" then bonusEarned else 0,
				--[[ The weather that was on the car, which is what multiplied everything above it
					(`WeatherConfig`). Sanitised on the way in like everything else off this wire: an
					unknown key becomes nil, so a client one deploy behind a server draws an ordinary
					payout rather than naming a mutation it has never heard of. ]]
				mutation = WeatherConfig.sanitize(mutation),
				--- The heat multiplier the bank paid (`PoliceConfig.Heat`), already inside `cash`; 1 for none.
				heat = if type(heat) == "number" and heat >= 1 and heat < 100 then heat else 1,
			}
			RaceUIController:_queueResultsPreparation()
		end,
		--[[ The other half, and it is kept SEPARATE from the summary above rather than merged into
			it. The two are different RemoteEvents, and Roblox only promises ordering within one — so
			a level-up that happened to arrive first would find no summary to attach itself to and be
			silently dropped. Held on its own, both are simply drawn by whichever fade comes next. ]]
		CarLeveled = function(body: string, level: number)
			RaceUIController._leveled = { body = body, level = level }
			RaceUIController:_queueResultsPreparation()
		end,

		--[[ WHY a run ended, held apart from what it was worth. See `_headline`, which is the only
			thing that reads it: the two facts arrive on two remotes and cannot be relied on to
			arrive in order, so neither is merged into the other. ]]
		RaceWrecked = function(cause)
			RaceUIController._wreckCause = cause
		end,

		RaceEntering = function()
			--- Cleared here rather than on the screen that draws it, because this is the first
			--- moment of the NEXT run and therefore the last moment the previous one's reason is
			--- certainly finished with.
			RaceUIController._wreckCause = nil
			RaceUIController:_onEntering()
		end,
		--[[ The entry ran out of time and the server has sent us home rather than release the car
			into a world that never finished loading (`RaceService._abortEntry`). `RaceLive` follows
			a few hundred milliseconds behind it and drops the screen, so this has to be what puts
			the reason on it before that happens. ]]
		RaceAborted = function()
			RaceUIController:_onAborted()
		end,
		-- Wrecked out: same fade, different reason. RaceService teleports us back to spawn
		-- behind it and then fires RaceLive, which drops it again.
		RaceReturning = function()
			RaceUIController:_show(RETURN_LABEL)
		end,
		RaceLive = function()
			RaceUIController:_onLive()
		end,
		RaceEnd = function()
			RaceUIController:_onLive()
		end,
	},
})

RaceUIController:withLifecycle({
	init = function(self)
		self._visible = false
		self._hiding = false
		self._token = 0
		self._tweens = {}
		self._tickList = {}
		self._loading = false
		self._loadShown = 0
		self._wreckCause = nil -- the cause of the last wreck; see `_headline`
		self._bustedScreen = false -- whether the screen currently up is a bust; see `_stepLights`
		self._wreckedScreen = false -- ...and whether it is a wreck; see `_stepSmoke`
		self._slotWreck = false -- whether the car in the trophy slot is a wreck; see `setWreck`
		self._litTicks = {}
		self._carAngle = CAR_YAW
		self._burstAngle = 0
		self._trophyRest = TROPHY_SIZE -- the trophy box's landed size; the kit panel's is its own
		self._trophyBuildToken = 0
		self._resultPrepareToken = 0
		self._resultsPrepared = false
		self._preparedHasResults = false
		-- === RACE AGAIN (see `REPLAY_PILL`) ===
		self._replayable = false -- whether the screen now up is offering another run
		self._replayLocked = true -- ...and whether the press has been spent, or the clock has run out
		self._replaying = false -- a press is being answered: the black is held for the entry. `_playReplay`
		self._replayUntil = nil -- when the offer closes; the drain's width IS what is left of it
		self._replaySliding = false -- the entrance owns the slot's position while this stands
		self._replayHome = nil -- where `_layoutReplay` last solved the pill to
		self._replayIconAt = nil -- ...and where the controller badge stands beside it
		self._afterPanel = nil -- "home" or "replay" once the one-screen wreck is answered; see `_show`
	end,

	start = function(self)
		self:_build()

		--- The one-screen wreck's answer, for the return that follows it. See `_show`.
		Dispatcher:Subscribe(RaceConfig.WreckAnsweredEvent, function(answer: string)
			self._afterPanel = if answer == "replay" or answer == "home" then answer else nil
		end)

		--[[ The new UI's results panel waits for its template on a thread of its own: `MainUIV2`
			arrives with the character, after this starts, and `start` is the boot barrier. Until it
			is built, a results screen draws on the overlay exactly as the shipping one does.
			`NewUIConfig.KitRaceResults` off keeps the shipping results on either UI. ]]
		if UIRoot.isNewUI() and NewUIConfig.KitRaceResults then
			task.spawn(function()
				self:_awaitPanel()
			end)
		end

		--[[ Warm the world shots, because a backdrop that arrives late is worse than none.

			`ImageLabel.Image` fetches on first use, and the first use is the frame an entry begins —
			so without this the screen the player sees is a black overlay that a photograph drops
			onto a moment later. That is a flash of exactly the "something is still loading" this
			screen exists to hide, and it would land on every world's FIRST entry of a session,
			which is the entry most likely to be someone's first impression.

			DETACHED AND UNPRIORITISED. `PreloadAsync` yields per asset and would otherwise hold up
			`start` behind a web call for a screen nobody has asked for yet; spawned, it fills in
			during the lobby, which is minutes of idle time before the first Play press. Wrapped
			because a decal id that fails to resolve throws, and a warm cache is an optimisation —
			losing it should cost the fade its smoothness, never the race its start.

			Five ids, ~433x620 each. `worldThumb`'s placeholder is already on the Teleport card, so
			it is warm by the time anyone reaches a fallback. ]]
		task.spawn(function()
			local images = {}
			for _, id in UIAssets.Worlds do
				local label = Instance.new("ImageLabel")
				label.Image = "rbxassetid://" .. id
				table.insert(images, label)
			end
			pcall(function()
				ContentProvider:PreloadAsync(images)
			end)
			for _, label in images do
				label:Destroy()
			end
		end)
	end,
})

return RaceUIController
