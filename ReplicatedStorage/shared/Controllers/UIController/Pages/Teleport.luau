--[[
	Teleport page  (client)
	-----------------------
	The world-select screen: one card per world in `WorldConfig`, each a thumbnail with a PLAY
	button under it. Pressing one starts a run in that world — which road you drive and which
	ladder of cars drives past you (see `WorldConfig`).

	IT IS THE SECOND HALF OF THE PLAY BUTTON. The HUD's Play opens this and a card starts the race,
	so playing is "press Play, pick where" (boss's call; `RaceConfig.PlayOpensWorldSelect` is the
	switch back). Two consequences for this file: the world you are ALREADY in is an ordinary
	pressable card rather than a dead one saying CURRENT — it is the world most players will pick
	most of the time — and there is no longer any such thing as pressing a card and staying in the
	lobby. The name "Teleport" is the screen's authored name in the place and its module name here;
	both are historical and left alone (`WorldConfig.PageName` is the one string that has to match).

	SEVEN THINGS TO KNOW.

	1. THE AUTHORED CARDS ARE A LAYOUT SAMPLE, NOT THE LIST — the same arrangement as the Index
	   page's slots and the Dealership's two cards. `Card1` is cloned once per world and `Cards` is
	   emptied, so adding a fifth world is an edit to `WorldConfig` and nothing else. Position, size
	   and the gap between cards are all MEASURED off the samples rather than typed in here, so
	   nudging Card1 in the Explorer moves the real row.

	2. THE ARTIST DREW THREE AND THERE ARE FIVE WORLDS, so THE ROW IS A CAROUSEL: three cards at the
	   size they were drawn, an arrow disc outside each end of the panel, and the rest of the worlds
	   one press away. `_fitPage` has the identity that decides the panel's aspect and `_slideTo` is
	   the movement.

	   THIS IS THE SECOND ANSWER TO THAT QUESTION AND THE THIRD SHAPE THIS ROW HAS HAD, so both
	   discarded ones are worth keeping written down — each was fixing what the one before it broke.

	     • SCALE THE ROW DOWN TO FIT (until 2026-08-28). Four cards at 75%. A uniform scale takes the
	       HEIGHT with it, so the row shrank away from a panel that did not: 27% of the panel empty
	       above and below, thumbnails at about 106x152 real pixels, on the one screen whose entire
	       job is showing you a picture of somewhere.

	     • WIDEN THE PANEL PER WORLD (2026-08-28, most of a day). Cards keep their authored size and
	       the panel stretches to take them, which fixed the size complaint completely and does not
	       survive a fifth world: the panel's aspect is `authored * span`, so it went 1.62 -> 2.15 at
	       four and wants 2.68 at five. Past about 2.4 the `UIAspectRatioConstraint`'s width binds
	       before its height on a 16:9 screen and the whole page scales down together — i.e. it
	       silently turns back into the first answer, at the fifth world instead of the fourth, and
	       every world after that makes it worse.

	   A CAROUSEL IS THE ONLY ONE OF THE THREE THAT DOES NOT GET WORSE WITH WORLD SIX. The panel is
	   sized for `VISIBLE_CARDS` and nothing else, so its aspect is the artist's own 1.62 and a card
	   is 314x523 real pixels at every world count there will ever be. What a new world costs is one
	   more press, which is the only thing here that is allowed to grow.

	   THE THREE CARDS LAND EXACTLY WHERE THEY WERE AUTHORED. That is not a special case in the code,
	   it is the formula agreeing with the drawing to four decimal places, and it is the check that
	   says this is reading the mockup rather than replacing it.

	   THE ARROWS SIT OUTSIDE THE PANEL, NOT IN IT (2026-09-14, the boss's card: "arrows should not
	   take up this much space on the menu"). They used to live in a gutter the panel was widened by,
	   which cost 23% of the panel's width for two discs and left the cards marooned in the middle
	   of a stretched frame. Now they hang off the panel's ends and take no room on it at all; what
	   they cost instead is width on the SCREEN, and `_reserveArrowRoom` is where that is paid.

	   THE ARROWS ARE THE DRIVING HUD'S STEER ARROWS. See `UIAssets.Arrow` for why reusing them is
	   free rather than lazy, and why the argument that kept a third arrow off the driving HUD does
	   not reach a lobby menu.

	3. NOTHING HERE DECIDES ANYTHING. A press publishes `TeleportToWorld` on Dispatcher and stops;
	   `WorldController` carries it to `RaceEntryController` and the server owns every guard. This
	   page does not repaint optimistically either — it redraws when the player attribute changes,
	   which is the server's actual answer, so it cannot show you standing in a world you were
	   refused. It does not close itself on a press either: `RaceEntryController` shuts it on
	   `RaceStart`, so a refused press leaves the screen up to pick again.

	4. THE THUMBNAILS ARE PICTURES OF THE ROADS as of 2026-08-28, and they are looked up BY MAP
	   rather than by world index — `UIAssets.Worlds`, keyed by the same folder name `WorldConfig`
	   binds a ladder to, so moving a ladder onto a different road moves its picture with it. The
	   artist's flat white placeholder is still the fallback and still the right answer for a map
	   nobody has photographed. `UIAssets.Worlds` carries the recipe for taking a replacement.

	   WHAT THIS CARD COVERS UP is worth knowing before re-shooting one (measured 2026-09-14): the
	   band of cars covers 63-78% of the thumbnail and the PLAY button 79-96%, always, and the
	   weather pill lands across 45-61% while an event is running. So a shot has to say which world
	   it is in its top 60%, and does best to say it in its top 45%.

	5. THE CARD CARRIES ITS WORLD AS AN ATTRIBUTE (`WorldConfig.WorldAttribute`), which is what lets
	   one action handler serve every card. That contract was written down by the half of this that
	   built the art, and it is unchanged.

	6. WORLDS ARE BOUGHT NOW, and it cost this page no new art. The one authored button says PLAY,
	   a PRICE, a REQUIREMENT ("DESERT 100%") or CONFIRM? depending on what the press would do, and
	   `WorldController` decides which of those four it is — so the second press on a price is the
	   confirm, and the kit never needed a dialog. `WorldConfig`'s "Earning a world" has the rule.

	7. EVERY CARD SHOWS WHAT ITS ROAD CAN GIVE YOU, AND IN ITS WORLD'S COLOUR (2026-09-14). A band
	   across the foot of the picture drifts through every car that world spawns, each with this
	   player's odds of it; and the card and its picture each wear a rim in the world's colour, off
	   the boss's mockup. "THE WORLD'S COLOUR ROUND ITS CARD" and "THE CARS A WORLD CAN GIVE YOU"
	   below have both, and `TrafficConfig.chancesFor` is where the numbers come from.

	HOUSE RULE: no wiki-style double-bracket links in this comment — the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UIControllerTypes = require(script.Parent.Parent.UIControllerTypes)
local UIGeom = require(script.Parent.Parent.UIGeom)
local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local PassConfig = require(ReplicatedStorage.shared.Configs.PassConfig)
local IndexRewardConfig = require(ReplicatedStorage.shared.Configs.IndexRewardConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)

local PAGE_NAME = "Teleport"

--[[ Where the artist's own numbers are banked once they have been read, so that a rebuilt page
	measures the DRAWING rather than this file's last edit of it.

	Four of them, because three things here are written IN PLACE rather than rebuilt from scratch: the
	page's aspect (`_fitPage`), its width box (`_reserveArrowRoom`) and the close button's width and
	inset (`_pinClose`). Everything else a build touches is cloned fresh from `Row.sample`, which was
	taken before any of this ran, so a second build re-derives it from the drawing and cannot
	compound. These four would. ]]
local AUTHORED_ASPECT = "AuthoredAspect"
local AUTHORED_PAGE_WIDTH = "AuthoredPageWidth"
local AUTHORED_CLOSE_WIDTH = "AuthoredWidth"
local AUTHORED_CLOSE_INSET = "AuthoredInset"

--[[ ...and four more since the row became a carousel, on `Cards`. The card row is now MOVED into a
	clipping track rather than laid out where it was drawn, so every one of these is a measurement a
	rebuild could no longer take: a card inside the track carries the artist's SIZE and the track's
	position, and the samples the first build read them off are long destroyed. Banked once, read
	back forever, exactly like the four above. ]]
local AUTHORED_CARD_WIDTH = "AuthoredCardWidth"
local AUTHORED_CARD_GAP = "AuthoredCardGap"
local AUTHORED_CARD_MARGIN = "AuthoredCardMargin"
local AUTHORED_CARD_TOP = "AuthoredCardTop"
--[[ The HEIGHT is banked for a sharper version of the same reason and is the one that was missed
	first time: a card on the track is `{1, 0}` tall, because the track IS the band and a card fills
	it. So a rebuild that measured it read the artist's 0.8359 as 1, which does not look like a
	measurement bug — it looks like the viewport and both arrows having grown to fill the panel. ]]
local AUTHORED_CARD_HEIGHT = "AuthoredCardHeight"

-- Non-breaking spaces: TextScaled would rather wrap "FOREST MOUNTAINS" onto a second line than
-- shrink it, and on a card this narrow that is most of the caption gone.
local function oneLine(text: string): string
	return (string.gsub(string.upper(text), "%s+", "\u{00A0}"))
end

local GO = "PLAY"
local RACING = "IN\u{00A0}A\u{00A0}RACE"
local CONFIRM = "CONFIRM?"

-- How far a card that can't be pressed fades. Enough to read as unavailable next to a live one,
-- not so far that you can't see which world it is.
local DIM = 0.5

--[[ === THE CAROUSEL ========================================================================

	`VISIBLE_CARDS` is THE ARTIST'S OWN THREE, and it is the number the whole page is sized from
	(header note 2). Raising it does not break anything, it just widens the panel: four would ask
	for an aspect of 2.15, closing on the ~2.4 where a 16:9 screen starts binding on width and the
	whole page scales down, so three is the drawn count and the safe one.

	The two arrow numbers are fractions of A CARD rather than of the page, so the discs keep their
	proportion to the row whatever `VISIBLE_CARDS` becomes. At the shipped values the disc renders
	about 94px across against a 314px card on a 1080p screen, a quarter of the thing it pages and
	comfortably over the ~44px a thumb needs. `ARROW_GAP_OF_ARROW` is the clear air between a disc
	and the panel it sits beside, as a fraction of the disc.

	`SLIDE_TIME` is short enough that a double press does not feel queued and long enough to read as
	one row moving rather than three cards being swapped. Quart-out because the row should arrive
	settled: the interesting half of a carousel move is the end of it, where the new card lands. ]]
local VISIBLE_CARDS = 3
local ARROW_OF_CARD = 0.30
local ARROW_GAP_OF_ARROW = 0.15
local SLIDE_TIME = 0.28
local SLIDE_STYLE = TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

--- How far an arrow at the end of the row fades. Further than a dead CARD (`DIM`), because a card
--- that cannot be pressed is still showing you a world and an arrow pointing at nothing is not.
local ARROW_DIM = 0.65

--[[ How far a drag has to travel, in PAGES, before the release pages instead of snapping back.
	Well under the half a page that rounding to nearest would ask for, which is the whole reason it
	is here: a flick on a phone is a short fast movement, and a carousel that only pages when you
	have dragged a card and a half across the screen reads as one that ignores you. ]]
local FLICK_PAGES = 0.18

--- Names this page builds into `Cards` itself, so a rebuild can tell the authored samples (which
--- are what `_measure` wants) from the row it left behind last time.
local VIEWPORT_NAME = "Viewport"
local TRACK_NAME = "Track"
local ARROW_NAMES = { Left = "ArrowLeft", Right = "ArrowRight" }

--[[ What the button says, from `WorldController:cardState`. The page owns the WORDS and the
	controller owns the STATE, which is the split that lets the price be reworded without touching
	the thing that decides whether it is offered.

	A LOCKED CARD NAMES WHAT IT WANTS rather than saying LOCKED, which is what the string that used
	to be here said and what it cost: "LOCKED" tells a player they cannot go and nothing else, while
	the road it wants finishing is the whole prerequisite on the button.

	=== IT SHOWS YOUR PROGRESS, AND IT USES THE SHORT NAME — 2026-08-28 ========================

	It used to read "FOREST MOUNTAINS 100%", and that one string had both of this page's typography
	problems in it. Twenty-one characters across a label this narrow is about 13px of type next to
	PLAY's 21px on the card beside it, so a row of four buttons read as four different designs; and
	the number in it was the REQUIREMENT, which is the same 100% on every locked card for the life of
	the save and tells a player nothing they did not already know.

	The number is now `state.progress`, which `cardState` has always returned and this page has never
	drawn, so the button MOVES as you drive: "DESERT 62%" is worth glancing at again, and it says how
	far off you are rather than restating the rule. And the name is `WorldConfig.shortName`, which is
	"Mountains" for the one world whose real name does not fit — that alone is the difference between
	13px and 21px, and it puts every button in this row at the same size.

	TWO LINES WAS TRIED HERE AND IS WRONG, which is worth writing down because it is the obvious idea.
	The `Label` is 115x21 REAL PIXELS — the artist insets it to about half the button's height, so the
	face's bevel is not written over — and a box that wide and that shallow is the one shape a second
	line cannot help: splitting "DESERT 0%" across two lines took it from 12px to 10px. Long strings
	in a short wide box want to be SHORTER, not stacked.

	THE REQUIREMENT IS ONLY SPELLED OUT WHEN IT IS NOT 100%. `RequirePrevious` is a fraction in the
	config precisely so it can be softened to 0.9 without a code change, and on that day "62%" alone
	would be a lie by omission — so it becomes "62% / 90%" and says both. At the value the game
	actually ships, finishing the road is the rule and the bare number is the honest short form. ]]
local function labelFor(state): string
	if state.label == "racing" then
		return RACING
	elseif state.label == "confirm" then
		return CONFIRM
	elseif state.label == "buy" then
		return oneLine(GarageConfig.formatCash(state.cost))
	elseif state.label == "needs" then
		local required = state.required or 1
		local progress = math.clamp(state.progress or 0, 0, required)
		--- Floored, both of them: a card that says 100% while the button is still dead is worse than
		--- one that says 99% for a few hundred studs longer.
		local reached = string.format("%d%%", math.floor(progress * 100))
		local target = if required < 1 then string.format("%s / %d%%", reached, math.floor(required * 100)) else reached
		return oneLine(string.format("%s %s", state.previousShort or state.previousName or "?", target))
	end
	return GO
end

local Page = {}
Page.__index = Page

function Page.new(UIController: UIControllerTypes.UIController)
	local self = setmetatable({}, Page)
	self.UIController = UIController
	self.Player = UIController.Player or Players.LocalPlayer

	local mainUI = UIController.PlayerGui:WaitForChild("MainUI")
	self.PageUI = mainUI:WaitForChild("Pages"):WaitForChild(PAGE_NAME)
	self.Cards = self.PageUI:WaitForChild("Cards")

	-- A LOCAL, never `self.Close`: the controller treats a `Close` field on a page as that page's
	-- custom close ROUTINE and calls it, so parking the button there makes closing throw.
	local close = self.PageUI:WaitForChild("Close")
	close.MouseButton1Click:Connect(function()
		self.UIController:closePage(PAGE_NAME)
	end)

	return self
end

--[[ === THE ROW FILLS THE PANEL; THE PANEL WIDENS TO SUIT ====================================

	Measure the authored row before anything is destroyed: where the first card sits, how big it is,
	the gap to the next one, and the aspect of the page they were drawn on. Two samples are enough
	for the gap; one is enough for the rest, and a page authored with a single card falls back to a
	gap proportional to the card.

	THE AUTHORED PAGE ASPECT IS PARKED IN AN ATTRIBUTE the first time it is read, because this file
	WRITES that aspect (see `_fitPage`) and a page rebuilt after the first build would otherwise
	measure its own widening and compound it. The attribute is the artist's number; the constraint
	is whatever the current world count asked for. ]]
function Page._measure(self)
	--[[ THE SAMPLES ARE THE ARTIST'S CARDS AND NOTHING THIS FILE BUILT. On a first build `Cards`
		holds exactly the three drawn ones; on a REBUILD it holds a clipping viewport and two arrows
		instead, and the real cards have moved inside the track. Reading those three as a row would
		measure a page-wide frame as "card 1" and put the whole layout on a fiction, so the built
		names are skipped by name and the track is where the second pass looks. ]]
	local built = { [VIEWPORT_NAME] = true, [ARROW_NAMES.Left] = true, [ARROW_NAMES.Right] = true }
	local source = self.Cards
	local track = self.Cards:FindFirstChild(VIEWPORT_NAME)
	track = track and track:FindFirstChild(TRACK_NAME)

	local samples = {}
	for _, child in source:GetChildren() do
		if child:IsA("GuiObject") and not built[child.Name] then
			table.insert(samples, child)
		end
	end
	--[[ A rebuild finds none of the above, and the cards it built last time are the only record of
		the drawing left. They are clones of the sample and they are the same SIZE, but they sit in
		the track's coordinates rather than the page's — so only the shape is taken from them and
		the row's position and gap come from the banked authored numbers below. ]]
	local rebuilt = #samples == 0 and track ~= nil
	if rebuilt then
		for _, child in track:GetChildren() do
			if child:IsA("GuiObject") then
				table.insert(samples, child)
			end
		end
	end
	table.sort(samples, function(a, b)
		return UIGeom.left(a) < UIGeom.left(b)
	end)

	local first = samples[1]
	if not first then
		return nil
	end

	-- Edges, not raw Position: the samples are centre-anchored like the rest of the kit, so their
	-- Position is a centre. See UIGeom.
	local firstLeft = UIGeom.left(first)

	local shape = self.PageUI:FindFirstChildOfClass("UIAspectRatioConstraint")
	local authored = self.PageUI:GetAttribute(AUTHORED_ASPECT) or (shape and shape.AspectRatio)
	if shape and authored then
		self.PageUI:SetAttribute(AUTHORED_ASPECT, authored)
	end

	--[[ Banked on `Cards` the first time they are read, for the reason the aspect above is: this
		file MOVES the cards it measured, so a rebuild that re-derived the row off them would be
		measuring its own last answer. The three numbers are the artist's and never change. ]]
	local function bank(key: string, value: number): number
		local stored = self.Cards:GetAttribute(key)
		if type(stored) ~= "number" then
			stored = value
			self.Cards:SetAttribute(key, stored)
		end
		return stored
	end

	local width = bank(AUTHORED_CARD_WIDTH, first.Size.X.Scale)
	local gap = bank(
		AUTHORED_CARD_GAP,
		if samples[2] then UIGeom.left(samples[2]) - firstLeft - width else width * 0.05
	)
	--- The one measurement a rebuild cannot take off a moved card: inside the track a card's left
	--- edge is its slot, not its margin. Banked on the first pass and read back on every later one.
	local margin = bank(AUTHORED_CARD_MARGIN, firstLeft)
	local top = bank(AUTHORED_CARD_TOP, UIGeom.top(first))
	local height = bank(AUTHORED_CARD_HEIGHT, first.Size.Y.Scale)
	return {
		-- A DETACHED copy, kept for the life of the page. The authored samples are destroyed once
		-- the real cards exist, and a destroyed instance cannot be cloned — so holding the original
		-- would make this page buildable exactly once, which is a fine thing to be until the day
		-- something wants to rebuild the row.
		sample = first:Clone(),
		width = width,
		height = height,
		gap = gap,
		margin = margin,
		-- The top of the band the artist drew the cards in. The row fills that band at every world
		-- count now, so the cards no longer need a centre line to hang from.
		top = top,
		shape = shape,
		aspect = authored,
	}
end

--[[ SIZE THE PANEL FOR THE ROW IT SHOWS AT ONCE, and return the factor every horizontal
	measurement on this page has to be multiplied by afterwards.

	=== ONE IDENTITY, AND IT IS THE ARTIST'S OWN ==============================================

	The row is `2*margin + visible*width + (visible-1)*gap` wide and has to come to exactly 1, and
	every one of those terms is a fraction of the page's width, so

	    aspect = authoredAspect * (2*margin + visible*width + (visible-1)*gap)

	measured on the authored page. Feed it the artist's own three and the bracket comes to 1.0006:
	it reproduces the page they drew to within a rounding error, which is the check that says the
	formula is reading their intent rather than inventing one.

	WHAT CHANGED ON 2026-08-28 IS ONLY WHAT GOES IN `visible`. It used to be the world count, which
	is the widen-per-world answer header note 2 retired: at five worlds it asks for an aspect of
	2.68, and past about 2.4 the constraint's own `FitWithinMaxSize` starts binding on WIDTH on a
	16:9 screen, which scales the whole page down and quietly reinstates the very problem the widen
	was built to fix. Now it is `VISIBLE_CARDS`, so the bracket is a constant however many worlds
	the config grows to.

	THE ARROWS ARE NOT IN IT. Until 2026-09-14 the bracket carried a gutter either side for the
	discs, which stretched `Teleport.Panel` 23% wider at five worlds. They hang outside the panel now
	(header note 2), so `arrows` only decides whether the page reserves screen width for them; see
	`_reserveArrowRoom`.

	THE CARDS COME OUT 314x523 REAL PIXELS on a 1080p screen, against 178x300 under the widen at four
	worlds and 133x225 under the scale-to-fit before it, and unlike either of those that is the same
	number at six worlds and at sixty. ]]
function Page._fitPage(self, visible: number, arrows: boolean): number
	local row = self.Row
	if not row or not row.shape or not row.aspect then
		return 1
	end

	local span = 2 * row.margin + visible * row.width + (visible - 1) * row.gap
	if span <= 1e-6 then
		return 1
	end

	row.visible = visible
	row.shape.AspectRatio = row.aspect * span
	-- Every horizontal SCALE measurement taken off the authored page is now this much smaller,
	-- because the page it was a fraction of just got that much wider.
	local squeeze = 1 / span
	self:_reserveArrowRoom(if arrows then row.width * ARROW_OF_CARD * (1 + ARROW_GAP_OF_ARROW) * squeeze else 0)
	return squeeze
end

--[[ === THE ARROWS' SCREEN WIDTH ==============================================================

	A disc outside the panel is only outside the panel if there is screen out there to draw it on.
	On every landscape screen there is: the page is 58% of the screen's height and the 1.62 aspect
	binds on height, so the panel is about half a 16:9 screen wide with a quarter of it spare either
	side. It stops being true on a screen narrower than about 1.14:1, where the panel's authored
	full-width box binds first and the discs would be drawn off both edges.

	So the page's WIDTH BOX is pulled in by what the discs need, `reach` being one disc plus its gap
	as a fraction of the panel's width. Where height binds (every landscape screen) this changes
	nothing at all, because the box was never the thing limiting the panel; where width binds it
	gives up exactly enough panel for both discs to land on screen.

	The authored width is banked the first time (`AUTHORED_PAGE_WIDTH`), for the reason every other
	number on this page is: this writes the property it would otherwise be reading. ]]
function Page._reserveArrowRoom(self, reach: number)
	local page = self.PageUI
	local authored = page:GetAttribute(AUTHORED_PAGE_WIDTH)
	if type(authored) ~= "number" then
		authored = page.Size.X.Scale
		page:SetAttribute(AUTHORED_PAGE_WIDTH, authored)
	end
	page.Size = UDim2.new(authored / (1 + 2 * reach), page.Size.X.Offset, page.Size.Y.Scale, page.Size.Y.Offset)
end

--[[ `Close` is the one authored child a widening panel would deform: it is a square 700x700 texture
	sized in scale, so a page 33% wider draws it 33% wider than it is tall. Its width and its
	distance from the right edge are both pulled in by the same factor, which keeps it the same
	number of PIXELS square and the same number of pixels off the corner — the two things that are
	actually true about a piece of window chrome.

	The title bar needs none of this. It is drawn as a bar and it is meant to span the panel, so
	spanning a wider one is the right answer rather than a distortion, and "WORLDS" inside it is
	bound by the bar's unchanged HEIGHT. ]]
function Page._pinClose(self, squeeze: number)
	local close = self.PageUI:FindFirstChild("Close")
	if not close or not close:IsA("GuiObject") then
		return
	end

	--[[ BOTH of the artist's numbers are banked, and neither is ever re-derived from the live
		instance afterwards — that is the whole of what makes this safe to run twice. Deriving the
		inset from a button this function has already moved would measure its own last answer, and
		the button would walk in from the corner a little further on every build. ]]
	local width = close:GetAttribute(AUTHORED_CLOSE_WIDTH) or close.Size.X.Scale
	local inset = close:GetAttribute(AUTHORED_CLOSE_INSET) or (1 - UIGeom.right(close))
	close:SetAttribute(AUTHORED_CLOSE_WIDTH, width)
	close:SetAttribute(AUTHORED_CLOSE_INSET, inset)

	-- Vertically nothing moves, so the button's own top is the answer at any page aspect.
	local top = UIGeom.top(close)
	local pinned = width * squeeze
	close.Size = UDim2.fromScale(pinned, close.Size.Y.Scale)
	UIGeom.place(close, 1 - inset * squeeze - pinned, top)
end

--[[ === THE TRACK, AND WHY THE CARDS ARE MEASURED IN ITS UNITS AND NOT THE PAGE'S =============

	`Viewport` is a clipping window over exactly the band the artist drew the three cards in, and
	`Track` is the strip of every world that slides behind it. Both are built here rather than
	authored, for the reason the weather pill is: they are the mechanism, not the drawing.

	EVERY CARD IS SIZED AS A FRACTION OF THE VIEWPORT, which is the whole trick and is worth being
	explicit about because it looks like a change of units for its own sake. The viewport is
	`visible*w + (visible-1)*g` of the authored page wide; a card is `w`. So a card is `w / rowSpan`
	of the viewport, and `rowSpan * squeeze * (w / rowSpan) = w * squeeze` of the PAGE — the same
	number the old `_place` wrote directly. The card lands on the identical pixel either way.

	What the change buys is that sliding the row is now one write. The track carries every card at a
	fixed offset from its neighbour, so `_slideTo` moves the track and nothing else has to be
	recomputed — no per-card position, no per-frame layout, and the cards keep working out their own
	text caps and badge geometry off a size that never moves. ]]
function Page._buildTrack(self, squeeze: number)
	local row = self.Row
	local rowSpan = row.visible * row.width + (row.visible - 1) * row.gap

	local viewport = self.Cards:FindFirstChild(VIEWPORT_NAME)
	if not (viewport and viewport:IsA("Frame")) then
		if viewport then
			viewport:Destroy()
		end
		viewport = Instance.new("Frame")
		viewport.Name = VIEWPORT_NAME
		viewport.BackgroundTransparency = 1
		viewport.BorderSizePixel = 0
		--- The window the row is seen through. Without this the cards either side of the visible
		--- three would draw over the panel's margins and out past its keyline.
		viewport.ClipsDescendants = true
		--- So the frame itself receives the press that starts a drag. It sinks input the cards'
		--- own buttons never see, because a child is asked before its parent.
		viewport.Active = true
		viewport.Parent = self.Cards
	end
	viewport.ZIndex = self.Cards.ZIndex
	viewport.Size = UDim2.fromScale(rowSpan * squeeze, row.height)
	UIGeom.place(viewport, row.margin * squeeze, row.top)

	local track = viewport:FindFirstChild(TRACK_NAME)
	if not (track and track:IsA("Frame")) then
		if track then
			track:Destroy()
		end
		track = Instance.new("Frame")
		track.Name = TRACK_NAME
		track.BackgroundTransparency = 1
		track.BorderSizePixel = 0
		track.Parent = viewport
	end
	--- ANCHORED TOP-LEFT, unlike everything else in this kit (see UIGeom's note on the house
	--- convention). The track is not a thing on the page, it is an origin the cards hang off, and a
	--- centre anchor would make "move it one card left" depend on how many cards there are.
	track.AnchorPoint = Vector2.new(0, 0)
	track.Size = UDim2.fromScale(1, 1)
	track.ZIndex = viewport.ZIndex

	self.Viewport = viewport
	self.Track = track
	-- One card and one gap, as fractions of the VIEWPORT: the distance the track moves per press.
	self.CardWidth = row.width / rowSpan
	self.Step = (row.width + row.gap) / rowSpan
	return viewport, track
end

--- Where card `index` goes on the track. Cards are dealt from the track's left edge, so this is the
--- only place the row's own geometry is written and it takes no account of the scroll at all.
function Page._place(self, card: GuiObject, index: number)
	card.AnchorPoint = Vector2.new(0, 0)
	card.Size = UDim2.fromScale(self.CardWidth, 1)
	card.Position = UDim2.fromScale((index - 1) * self.Step, 0)
end

--[[ === THE TWO ARROWS =====================================================================

	A disc off each end of the panel, pointing at the half of the row you cannot see. They are
	the driving HUD's own steer arrows — `UIAssets.Arrow` has the whole account of why that is a
	reuse and not a shortcut — so all three states come drawn and the press lifts and sinks like
	every other button in this kit.

	THEY ONLY EXIST WHEN THERE IS SOMEWHERE TO GO. At three worlds or fewer the row is the whole
	list and these are destroyed rather than hidden: an arrow parked invisibly off the side of the
	panel is a thing to trip over later.

	SIBLINGS OF THE VIEWPORT AND NOT CHILDREN OF IT, which is the one placement rule here. The
	viewport clips, and an arrow inside it would be cut in half by the very window it is there to
	scroll.

	OUTSIDE THE PANEL, a gap clear of its edge, and vertically on the middle of the cards they page.
	Nothing up the tree clips, so a button hanging past `Cards`' edge draws and takes presses like
	any other, and `UIController`'s open tween is a `UIScale` on the page, which scales the discs
	with the panel rather than leaving them behind. The panel's own margin beside the first card is
	about 21px on a 1080p screen, so a disc even half over the edge would sit on a card.

	SIZED OFF THE CARD, so the disc keeps its proportion to the thing it pages at any world count,
	and held at the art's own 348:340 by a constraint driven from the WIDTH, which is the axis the
	placement is measured in, so it is the one that must be exact and the height follows. ]]
function Page._buildArrows(self, squeeze: number)
	local row = self.Row
	self.Arrows = {}

	local width = row.width * ARROW_OF_CARD * squeeze
	--- Negative: the disc's centre is out past the panel's left edge by half a disc and a gap.
	local centre = -width * (0.5 + ARROW_GAP_OF_ARROW)

	for side, name in ARROW_NAMES do
		local button = self.Cards:FindFirstChild(name)
		if (self.Pages or 0) <= 0 then
			if button then
				button:Destroy()
			end
			continue
		end

		if not (button and button:IsA("ImageButton")) then
			if button then
				button:Destroy()
			end
			button = Instance.new("ImageButton")
			button.Name = name
			button.BackgroundTransparency = 1
			button.BorderSizePixel = 0
			--- Or Roblox's built-in press tint fights the artist's own pressed face — the trap
			--- written up on `UIAssets`' sizing note, which has cost this repo an afternoon.
			button.AutoButtonColor = false
			button.ScaleType = Enum.ScaleType.Stretch

			local art = UIAssets.Arrow[side]
			button.Image = UIAssets.url(art.Idle)
			button.HoverImage = UIAssets.url(art.Hover)
			button.PressedImage = UIAssets.url(art.Pressed)

			local shape = Instance.new("UIAspectRatioConstraint")
			shape.AspectRatio = UIAssets.ArrowSize.X / UIAssets.ArrowSize.Y
			shape.DominantAxis = Enum.DominantAxis.Width
			shape.AspectType = Enum.AspectType.ScaleWithParentSize
			shape.Parent = button

			local direction = if side == "Left" then -1 else 1
			button.MouseButton1Click:Connect(function()
				self:_page(direction)
			end)
			button.Parent = self.Cards
		end

		--- Over the cards, because a tie on ZIndex is settled by tree order and that is not
		--- something to leave to the build sequence.
		button.ZIndex = self.Cards.ZIndex + 2
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		--- The Y is written and then ignored: the constraint above derives the height from the
		--- width. It is a real number rather than 0 so the button is never a zero-area box for the
		--- frame before the constraint resolves.
		button.Size = UDim2.fromScale(width, row.height)
		button.Position = UDim2.fromScale(
			if side == "Left" then centre else 1 - centre,
			row.top + row.height * 0.5
		)
		self.Arrows[side] = button
	end

	if self.Viewport then
		self:_bindDrag(self.Viewport)
	end
	self:_paintArrows()
end

--[[ An arrow pointing at nothing fades and stops answering.

	FURTHER THAN A DEAD CARD FADES, and that difference is deliberate. A card you cannot press is
	still doing its job — it is showing you a world and what it would take to get there — so it stays
	readable. An arrow at the end of the row has nothing left to say, and the only useful thing it
	can tell you is that this is the end of the list. ]]
function Page._paintArrows(self)
	if not self.Arrows then
		return
	end
	local offset, pages = self.Offset or 0, self.Pages or 0
	for side, button in self.Arrows do
		--- Against an epsilon, not against equality: the offset is a float while a drag is in
		--- flight, and an arrow that flickers as the row settles onto its page reads as a bug.
		local live = if side == "Left" then offset > 1e-3 else offset < pages - 1e-3
		button.Active = live
		button.ImageTransparency = if live then 0 else ARROW_DIM
	end
end

--[[ Move the row to `offset`, measured in PAGES from the left — one page being one card and one
	gap. Fractional on purpose: a drag drives this with whatever the finger is doing, and the snap
	back to a whole number happens on release rather than per frame.

	`immediate` is for the two places a tween would be wrong: the first build (a row that slides
	into place on open reads as one that has not finished loading) and every frame of a drag (the
	row has to be under the finger, not chasing it). ]]
function Page._slideTo(self, offset: number, immediate: boolean?)
	local track = self.Track
	if not track then
		return
	end

	local clamped = math.clamp(offset, 0, self.Pages or 0)
	self.Offset = clamped
	local target = UDim2.fromScale(-clamped * (self.Step or 0), 0)

	--- Cancelled and not left to finish: two presses in quick succession should be two pages, and
	--- a live tween writing `Position` behind a newer one is the row visibly changing its mind.
	if self._slide then
		self._slide:Cancel()
		self._slide = nil
	end
	if immediate then
		track.Position = target
	else
		self._slide = TweenService:Create(track, SLIDE_STYLE, { Position = target })
		self._slide:Play()
	end

	self:_paintArrows()
end

--- One press of an arrow, or one notch of the wheel. Rounds off the current offset first so a
--- press mid-drag lands on a whole page rather than carrying the drag's remainder with it.
function Page._page(self, direction: number)
	self:_slideTo(math.floor((self.Offset or 0) + 0.5) + direction)
end

--[[ Bring world `index` into the visible run, moving as little as possible: a world already on
	screen does not move the row at all.

	IT IS WHAT THE SCREEN OPENS ON. The Play button asks "where do you want to go", and the honest
	first answer is the road you are already on — so the carousel opens showing the player's own
	world rather than always at the left end, which at five worlds would hide two of them behind a
	press the player has no reason to expect. ]]
function Page._focus(self, index: number, immediate: boolean?)
	local visible = self.Row and self.Row.visible or VISIBLE_CARDS
	local offset = self.Offset or 0
	if index - 1 < offset then
		offset = index - 1
	elseif index > offset + visible then
		offset = index - visible
	end
	self:_slideTo(math.floor(offset + 0.5), immediate)
end

--[[ === DRAGGING THE ROW, AND WHY IT IS NOT OPTIONAL ==========================================

	A carousel a phone cannot swipe is a carousel most of this game's players cannot use, and the
	arrows do not cover it on their own: they are a 94px disc off the panel's end, and the thing under the
	thumb is a 314px card.

	THE DRAG STARTS ON THE VIEWPORT, WHICH IS WHY IT CANNOT EAT A PRESS. A child is offered input
	before its parent, so a touch that begins on a card's PLAY button never reaches this and a swipe
	that begins anywhere else on the card does. The two gestures cannot both fire from one touch,
	and neither has to know about the other.

	MOVEMENT AND RELEASE COME FROM `UserInputService` RATHER THAN THE FRAME, because a swipe that
	leaves the panel is still a swipe — a drag tracked on the frame's own `InputEnded` would stick
	on any gesture that ran off the edge, which on a five-card row is most of them.

	THE WHEEL IS HERE TOO, and it is one notch per page rather than proportional: this row moves in
	whole cards and a wheel that could leave it between two would need a snap of its own. ]]
function Page._bindDrag(self, viewport: Frame)
	if self._dragBound then
		return
	end
	self._dragBound = true

	local dragging = false
	local startX, startOffset = 0, 0

	--[[ SNAP TO THE NEAREST PAGE, except when the gesture was decisive and rounding would put the
		row back where it started — that is the flick, and without it a short fast swipe (which is
		what a swipe on a phone IS) reads as the screen ignoring you. A long drag needs no special
		case: it has already passed the halfway mark that rounding uses. ]]
	local function release()
		if not dragging then
			return
		end
		dragging = false
		local offset = self.Offset or 0
		local nearest = math.floor(offset + 0.5)
		local travelled = offset - startOffset
		if nearest == startOffset and math.abs(travelled) >= FLICK_PAGES then
			nearest = startOffset + (if travelled > 0 then 1 else -1)
		end
		self:_slideTo(nearest)
	end

	viewport.InputBegan:Connect(function(input)
		if (self.Pages or 0) <= 0 then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		dragging = true
		startX = input.Position.X
		startOffset = self.Offset or 0
	end)

	viewport.InputChanged:Connect(function(input)
		if (self.Pages or 0) <= 0 or input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		--- Wheel UP goes back down the list, which is the direction the CONTENT moves rather than
		--- the direction the row does. Same convention every horizontal shelf on the web uses.
		self:_page(if input.Position.Z > 0 then -1 else 1)
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local width = viewport.AbsoluteSize.X
		if width <= 0 or (self.Step or 0) <= 0 then
			return
		end
		--- Pixels the finger has moved, in pages. The row goes the OTHER way: dragging right pulls
		--- the earlier cards back into view, which is the offset going down.
		local moved = (input.Position.X - startX) / width / self.Step
		self:_slideTo(startOffset - moved, true)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			release()
		end
	end)
end

--[[ === THE WORLD'S COLOUR ROUND ITS CARD ====================================================

	The boss's mockup of this screen (2026-09-14) frames every card in its world's colour, blue for
	the city, gold for the desert, green for the mountains, with a second and thinner rim of the same
	colour round the picture and the card's own navy showing between the two. This is that.

	KEYED BY MAP, like `UIAssets.Worlds` and for the reason given there: a colour is a fact about the
	road, so moving a ladder onto another road moves the colour along with the picture. A map with no
	entry gets the kit's own blue. The first three are the mockup's, flattened to one value each (it
	paints them with a highlight down the edge); the last two are this file's picks for worlds the
	mockup never drew.

	THE RIMS ARE INSET FRAMES CARRYING AN ORDINARY STROKE, not a stroke on the card. A card sits in
	the carousel's clipping viewport and is exactly as tall as it, so anything drawn OUTSIDE a card
	is cut off top and bottom, and `UIStroke.BorderStrokePosition`, which would draw it inside, is
	a Studio beta that a player's client cannot be assumed to have. A frame inset by the stroke's
	own thickness puts a plain outer stroke exactly on the outermost pixels of the thing it rims.
	Stroke thickness is in pixels, so `_fitRims` redoes both off the card's width on every resize.

	THE PICTURE MOVES IN TO MAKE ROOM, which is the one edit to the artist's card: it used to run to
	within three pixels of the card's edge, where a rim of its own would have merged with the card's
	into one thick band. It is inset by the card's rim plus a gap now, on both sides and the bottom,
	and set to `Crop` so the slightly narrower box trims the picture rather than squeezing it. ]]
local ACCENTS = {
	City = Color3.fromRGB(28, 140, 255),
	Desert = Color3.fromRGB(255, 166, 38),
	["Forest Mountains"] = Color3.fromRGB(46, 214, 104),
	Arctic = Color3.fromRGB(125, 222, 255),
	FuturisticCity = Color3.fromRGB(196, 92, 255),
}
local ACCENT_FALLBACK = Color3.fromRGB(0, 102, 255)

local CARD_RIM_NAME = "CardRim"
local THUMB_RIM_NAME = "ThumbRim"
--- Fractions of the card's WIDTH, all three, so the rims and the gap between them come out the
--- same number of pixels on every side of the card. About 5, 3 and 4px on a 1080p screen.
local CARD_RIM = 0.016
local THUMB_RIM = 0.009
local THUMB_GAP = 0.013

--[[ === THE CARS A WORLD CAN GIVE YOU, AND THE ODDS OF EACH ===================================

	A band across the foot of each card's picture, just above the button: every car that world's
	road can put in front of you, with the chance that any one car on it is that one. The boss's
	card pointed at a shop in another game that does this for a crate, a row of small pictures under
	the item with a percentage under each, drifting sideways so a long list fits a short band.

	THE NUMBERS ARE THE ROLL. `TrafficConfig.chancesFor` reads the weights `_pickTier` rolls a spawn
	with, the variant split `_pickBody` uses and THIS PLAYER'S LUCK (both upgrade ladders and the
	Lucky Roads pass), so buying luck makes the top of every ladder likelier here exactly as much as
	it does on the road. They are the odds of the whole road, once every rung is unlocked; the top
	car cannot turn up in the first stretch of a run at all, and the band is not trying to say how
	soon it can.

	IN LADDER ORDER, worst to best, so it reads left to right as common to rare, and each number is in
	its rarity's colour (`Modules/CarRarity`), the ramp the collection screen prints.

	THE PICTURES ARE LIVE CARS, and most of the code below is about keeping that cheap. Each is a
	`Modules/CarViewport`, a real 25-mesh model in a ViewportFrame, and the five worlds hold 43 cars
	between them. So a cell only has a car in it while it is inside its band on a card that is on
	screen with the page open: about five per card, fifteen on the page. `CarViewportGrid` is the
	same rule for the collection screen, turned on its side. Builds are rationed per frame and a car
	is built half a cell before it drifts into view, so nothing is ever seen arriving. ]]
local STRIP_NAME = "Chances"
--- Card fractions. The button's top edge is 0.812 on the authored card, so the band stops just
--- above it; 0.125 of a 523px card is 65px, room for a car and a line of type under it.
local STRIP_BOTTOM = 0.8
local STRIP_HEIGHT = 0.125
--- Clear air between the top of the band and the weather pill, which now sits on top of it.
local STRIP_CLEARANCE = 0.012
--- One cell as a fraction of the band's width: a little over four cars in view at once.
local CELL_OF_STRIP = 0.235
--[[ Inside a cell, as fractions of its height: the car, and under it the chance. The number gets
	more than a third because it is the half of the cell a player has to READ, and on a phone the
	whole band is about 24pt tall. The car loses nothing by it: at the house three-quarter pose a car
	is about twice as wide as it is tall, so in a box this shape it is fitted by its width and the
	height it gave up was air. ]]
local CELL_CAR = 0.6
local CELL_TEXT = 0.36
--- Cells per second. Slow enough to read a number as it goes past; a car takes about eight
--- seconds to cross.
local STRIP_SPEED = 0.5
--- Car pictures built per frame, across every band on the page. `CarViewportGrid`'s number.
local STRIP_BUILD_BUDGET = 2
--- The kit's outline navy, at 80% over the picture. It is also every car's BACKDROP (see
--- `CarViewport`), which keeps the one-pixel ViewportFrame fringe from outlining the cars.
local STRIP_COLOUR = Color3.fromRGB(21, 29, 45)
local STRIP_TRANSPARENCY = 0.2

--[[ THE WEATHER BADGE on a world card: a kit pill in the event's colour, with the event's glyph on
	its left end and the mutation's multiplier beside it.

	THIS IS THE WHOLE REASON WEATHER IS PER WORLD. An event a player cannot see from the screen where
	they choose where to go is an event most players will never deliberately attend. It used to be a
	chat line as well, fired at everybody for every world; that is gone (`WeatherConfig.StartedEvent`
	has the argument) and a notice now goes only to the players in the world it is about, which makes
	this badge the ONLY thing that answers "where is the storm" — and the right thing to be, because
	it is still true two minutes later when they press Play, and a chat line is true for six seconds.

	=== WHY AN ICON AND NOT THE WORDS ==========================================================

	It said "SANDSTORM x2" across the foot of the thumbnail before, and that strip had two problems
	that are really the same problem: four cards' worth of small type is a paragraph on a screen
	whose whole job is a glance, and `TextScaled` on a strip that shallow was one long event name
	away from being clipped (this repo has paid for that before — see the `TextWrapped` note that
	used to live here). An icon reads at a distance, in any language, at any card scale.

	The MULTIPLIER survives as type because it is the half that cannot be drawn: the icon says what
	is happening and the number says what it is worth, and a badge with only the picture would be
	atmosphere on a menu. It is small, under the plate, and it is the only text here.

	=== WHERE IT SITS ==========================================================================

	A PILL ACROSS THE FOOT OF THE THUMBNAIL, which is where the text strip was, and it is there for
	the reasons that strip found by trial. Not over the BUTTON, which is the one part of the card the
	player is aiming at: a badge there is both a mis-click target and a thing covering the price they
	are saving toward. Not at the TOP either, which is where a corner badge wants to go and where
	this was tried: the card's `PlaceName` lives there, so the badge hid the name of the very world
	it was telling you to go to.

	So the shape changed and the address did not. What is inside it is the whole edit: an icon where
	two words used to be, and the multiplier beside it rather than under it.

	=== AND THE PLATE BECAME A KIT PILL — 2026-08-28 ============================================

	It was a `Frame` with a `UICorner` at half its height, a white `UIStroke` and a background set to
	`event.Color`, which is a rounded-rect-and-neon plate of exactly the kind the notice card, the
	forecourt sign and the customer bubble were each rebuilt out of. Sitting on the artist's own
	world card it was the one element on this page not made of the kit.

	The white rim went with it and is not missed: it existed because two of the six event colours are
	pale and dissolved into a pale thumbnail, and the kit's pill carries its own painted border and
	gloss, so the plate separates from whatever is behind it without being outlined. What it costs is
	the ability to be an arbitrary colour — `WeatherConfig.NoticePills` maps each event to the nearest
	of the kit's seven faces instead, which is the same table the badge over the car reads, so one
	storm is one colour wherever the player meets it. (The lobby notice wore one too until
	2026-09-15; on a toast with nothing to press, the kit's button shape read as a button.)

	NO SLOT WELL UNDER THE GLYPH, unlike those other two surfaces. At four worlds this pill is about
	104x27 real pixels; a well inside that leaves the number seven pixels tall. The pill is the seat
	at this size, which is the HUD cash plaque's own construction, and every weather glyph carries
	the kit's navy keyline so it reads on the pale faces too.

	Built once per card and then only shown, hidden and re-pointed — the same reuse rule
	`Modules/CarMutation` follows, for a milder version of the same reason: `_repaint` runs on every
	publish of the world state, and rebuilding a frame per card per publish is garbage for nothing. ]]
local BADGE_NAME = "WeatherFlag"

--- Ubuntu Bold, the kit's face. `Enum.Font.Ubuntu` is NOT this — that enum resolves to Ubuntu
--- REGULAR, which is what this badge was set in until 2026-08-28. See `WeatherController`'s note.
local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--[[ The pill's size and where its bottom edge sits, both as a fraction of the CARD — so it follows
	the row's rescale for four worlds without a second measurement (see note 2 in the header for why
	the cards shrink at all).

	ITS BOTTOM IS THE TOP OF THE CAR BAND, less a little clearance. It used to be 0.785, the last
	clear line above the PLAY button; since 2026-09-14 the band of cars and their odds lives on that
	line, so the pill stacks on top of it instead.

	THE WIDTH WENT UP (0.68 -> 0.86) WHEN THE PLATE BECAME A KIT PILL, and it is not a taste change.
	A `UICorner` lozenge can be any shape; the kit's pill is a drawing at 463x119, and stretching it
	off that aspect fattens its ends into the lozenge `UIAssets.Slice` warns about. So the flag is
	held at 3.891:1 by a constraint, and the only way to keep the height the artist's strip had is to
	give it the width that aspect asks for. At four worlds on a 1230px viewport that is 104x27px —
	which is where the type size below was measured. ]]
local BADGE_WIDTH = 0.86
local BADGE_HEIGHT = 0.135
local BADGE_BOTTOM = STRIP_BOTTOM - STRIP_HEIGHT - STRIP_CLEARANCE

--[[ Inside the pill: where the glyph sits, how much of the pill's height it takes, and where the
	number starts. Fractions of the PILL, so they survive the card rescale untouched.

	`CENTRE` is 0.47 and not 0.5 for the reason every caption on a kit pill uses that number: the
	artist's face sits slightly high in its own canvas, so type centred on the BOX reads low against
	the FACE. Same hair of offset as the badge over the car. ]]
local BADGE_ICON_X = 0.07
local BADGE_ICON_HEIGHT = 0.66
local BADGE_TEXT_X = 0.29
local BADGE_CENTRE = 0.47

local function ensureBadge(card: GuiObject): ImageLabel?
	local existing = card:FindFirstChild(BADGE_NAME)
	if existing and existing:IsA("ImageLabel") then
		return existing
	end
	--- A leftover from the build before this one — a `Frame` with a `UICorner` — is thrown away
	--- rather than reused, so a hot-reloaded page does not keep the old plate under the new art.
	if existing then
		existing:Destroy()
	end

	--[[ THE PLATE IS A KIT PILL, painted by `paintBadge`. `Stretch` with the art's own 3.891:1 held
		by the constraint below and never `Slice` — a 9-sliced pill holds its corners at 1:1 texture
		pixels and comes out a fat lozenge at any size but the art's, which is the single most
		repeated mistake in this kit (`UIAssets.Slice`). ]]
	local badge = Instance.new("ImageLabel")
	badge.Name = BADGE_NAME
	badge.AnchorPoint = Vector2.new(0.5, 1)
	badge.Position = UDim2.fromScale(0.5, BADGE_BOTTOM)
	badge.Size = UDim2.fromScale(BADGE_WIDTH, BADGE_HEIGHT)
	badge.ScaleType = Enum.ScaleType.Stretch
	badge.BackgroundTransparency = 1
	badge.BorderSizePixel = 0
	badge.ZIndex = (card.ZIndex or 1) + 3
	badge.Visible = false

	--[[ `FitWithinMaxSize`, not `ScaleWithParentSize`, and this is the one place on the card where
		that matters: the two constants above are a BOX the pill is allowed to occupy rather than a
		size it must take, so the pill fits itself inside whichever of the two binds. They are picked
		so the width binds (see their note), but a card row that rescales for four worlds must not be
		able to push the pill off its own aspect. ]]
	local shape = Instance.new("UIAspectRatioConstraint")
	shape.AspectRatio = UIAssets.Size.Pill.X / UIAssets.Size.Pill.Y
	shape.DominantAxis = Enum.DominantAxis.Width
	shape.AspectType = Enum.AspectType.FitWithinMaxSize
	shape.Parent = badge

	--[[ The glyph, sitting on the pill's face at its left end — the construction the HUD's own cash
		plaque uses, which is a banknote on a plate with the number beside it. It gets no well here,
		unlike the notice card's and the badge over the car's: at four worlds this pill is about
		104x27 real pixels, and a slot square inside that leaves the number seven pixels tall. The
		pill IS the seat at this size, and every glyph carries the kit's own navy keyline so it reads
		on the pale faces as well as the dark ones. ]]
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(BADGE_ICON_X, BADGE_CENTRE)
	--[[ Square off the pill's HEIGHT, and note the box is real rather than zero-width: the default
		`AspectType` FITS the element inside its authored size, so `UDim2.fromScale(0, 0.72)` would
		collapse this to nothing rather than resolve to the aspect. That trap is written up on
		`UIAssets`' sizing note and has cost this repo an afternoon before. ]]
	icon.Size = UDim2.fromScale(0.2, BADGE_ICON_HEIGHT)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = badge.ZIndex + 1
	icon.Parent = badge

	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.DominantAxis = Enum.DominantAxis.Height
	square.AspectType = Enum.AspectType.ScaleWithParentSize
	square.Parent = icon

	local price = Instance.new("TextLabel")
	price.Name = "Multiplier"
	price.AnchorPoint = Vector2.new(0, 0.5)
	price.Position = UDim2.fromScale(BADGE_TEXT_X, BADGE_CENTRE)
	price.Size = UDim2.fromScale(1 - BADGE_TEXT_X - BADGE_ICON_X, 0.46)
	price.BackgroundTransparency = 1
	price.BorderSizePixel = 0
	--- Ubuntu BOLD, the kit's face. `Enum.Font.Ubuntu` is Ubuntu REGULAR and is what this asked for
	--- until 2026-08-28 — measured at 304 against 319 `TextBounds` on one string, so it is a real
	--- difference and not a rounding one. Written to `FontFace`, never to `Font`.
	price.FontFace = FONT
	price.TextScaled = true
	--- Colour is a property of the PILL, not of the label: white is 1.5:1 on the three pale faces
	--- (Silver, Orange, Sky), so those take the kit's outline navy. `paintBadge` writes it from
	--- `WeatherConfig.noticePill`, the same table the car badge reads.
	price.TextXAlignment = Enum.TextXAlignment.Center
	--[[ NO `UITextSizeConstraint`, AND NO `TextWrapped` WRITE EITHER, which between them are the two
		ways this label has been got wrong before.

		`TextWrapped = false` is the obvious way to stop `TextScaled` breaking a caption onto a second
		line, and it silently CLEARS `TextScaled`: the label drops to the default `TextSize` of 8 and
		renders unreadably small with nothing anywhere warning. A `MaxTextSize` ceiling was the fix
		that worked, and it is no longer needed, because EVERY string this label can hold is now
		unbreakable — `paintBadge` builds the fallback out of `oneLine` and a non-breaking join, so
		there is no space in it for a break to land on. `TextScaled` can only shrink it.

		Dropping the ceiling is a fix rather than a tidy-up. A cap is in PIXELS and this pill is sized
		in scale, so the old 22 bound on a large viewport and nowhere else: the number stopped growing
		while the plate under it kept going, which is a big pill with small writing in it — the exact
		complaint that started this pass. Held at a fraction of the pill instead, the type is the same
		size relative to its plate on a phone and on an ultrawide. ]]
	price.ZIndex = badge.ZIndex + 1
	price.Text = ""
	price.Parent = badge

	badge.Parent = card
	return badge
end

--[[ Show or hide one card's badge from the live schedule.

	`state` is the decoded `WeatherConfig.Attribute` — decoded ONCE by the caller and passed in,
	rather than re-parsed per card. Four worlds is four parses of the same string otherwise, on every
	publish of the world state, for an answer that cannot differ between them.

	AN EVENT WITH NO ICON FALLS BACK TO ITS NAME, which is what this badge used to be made of. That
	is not a state anything ships in — every event in `WeatherConfig` has art — but it is the honest
	failure for a client one deploy behind a server that added a seventh event: the old strip, in the
	right colour, beats an empty pill. ]]
local function paintBadge(card: GuiObject, index: number, state)
	local badge = ensureBadge(card)
	if not badge then
		return
	end

	local entry = state[index]
	local event = entry and workspace:GetServerTimeNow() < entry.endsAt and WeatherConfig.eventOf(entry.event)
	if not event then
		badge.Visible = false
		return
	end

	--[[ THE PILL IS THE EVENT'S COLOUR, chosen from the kit's seven faces rather than painted with
		`event.Color`. That is the whole difference between this badge and the one it replaced: the
		kit has no surface that can be tinted an arbitrary colour (its plates are textures), so a
		flag in a raw RGB was a flag drawn in a different language from the card it sat on.

		`noticePill` is the same lookup the badge over the car reads, so one storm is one colour on
		both surfaces, and an event this build has never heard of falls to the neutral silver
		rather than to nothing. ]]
	local face = WeatherConfig.noticePill(event.Key)
	local art = UIAssets.Pill[face.Pill] or UIAssets.Pill.Silver
	badge.Image = UIAssets.url(art.Idle)

	local id = WeatherConfig.iconOf(event.Key)
	local icon = badge:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		icon.Image = if id then UIAssets.url(id) else ""
		--[[ The pill re-balances rather than leaving a gap. With art the glyph takes the left third
			and the number the rest; without it the name has the whole pill, which is the layout this
			badge had before there were icons. ]]
		icon.Visible = id ~= nil
	end

	--[[ The MUTATION is what is priced, not the event: the icon already says what the weather is, and
		the number is the only reason to go rather than stay. An event with no mutation shows the icon
		alone, which is the right amount to say about weather that is worth nothing extra. ]]
	local price = badge:FindFirstChild("Multiplier")
	if price and price:IsA("TextLabel") then
		local mutationKey = WeatherConfig.MutationOfEvent[event.Key]
		local text = if mutationKey
			then WeatherConfig.formatMultiplier(WeatherConfig.valueMultiplierOf(mutationKey))
			else ""
		if not id then
			text = if text == "" then oneLine(event.Name) else oneLine(event.Name) .. "\u{00A0}" .. text
		end
		price.Text = text
		--- White on the four dark faces and the kit's outline navy on the three pale ones — see the
		--- readability note on `WeatherConfig.NoticePills`, which owns the pairing.
		price.TextColor3 = face.Text
		price.Position = UDim2.fromScale(if id then BADGE_TEXT_X else BADGE_ICON_X, BADGE_CENTRE)
		price.Size = UDim2.fromScale(
			(if id then 1 - BADGE_TEXT_X else 1 - BADGE_ICON_X) - BADGE_ICON_X,
			0.46
		)
	end

	badge.Visible = true
end

--- The kit's outline navy, as the artist's own title strokes on this page have it.
local TEXT_OUTLINE = Color3.fromRGB(22, 29, 47)

--[[ This player's luck, read the way `TrafficController._refreshLuck` reads it for the road, so the
	odds on the card are the odds the road rolls. Upgrades, Lucky Roads and Index claims all enter
	through `UpgradeConfig.luckFactor`; anything missing reads as no bonus at all. ]]
local LUCKY_ROADS_ATTRIBUTE = PassConfig.ownedAttribute("LuckyRoads")

local function luckOf(player: Player): number
	return UpgradeConfig.luckFactor(
		UpgradeConfig.decode(player:GetAttribute(UpgradeConfig.Attribute)),
		player:GetAttribute(LUCKY_ROADS_ATTRIBUTE),
		player:GetAttribute(IndexRewardConfig.CountAttribute)
	)
end

--[[ "23%", "9.3%", "0.4%". Whole numbers from ten up and one decimal below, because the bottom
	of a ladder is where the numbers are big and the top is where a player reads them closely: the
	gap between 2.3% and 1.8% is a car and a half of difference over a long run, and rounding both to
	2% would hide it. ]]
local function formatChance(chance: number): string
	local percent = chance * 100
	if percent >= 9.95 then
		return string.format("%d%%", math.floor(percent + 0.5))
	elseif percent >= 0.05 then
		return (string.gsub(string.format("%.1f", percent), "%.0$", "")) .. "%"
	end
	return "<0.1%"
end

local function accentOf(index: number): Color3
	local map = WorldConfig.mapFor(index)
	return (map and ACCENTS[map]) or ACCENT_FALLBACK
end

--- A rim: a transparent frame with a plain stroke round it, placed and sized by `setRim`.
local function ensureRim(card: GuiObject, name: string, colour: Color3, zIndex: number): Frame
	local rim = card:FindFirstChild(name)
	if not (rim and rim:IsA("Frame")) then
		if rim then
			rim:Destroy()
		end
		rim = Instance.new("Frame")
		rim.Name = name
		rim.BackgroundTransparency = 1
		rim.BorderSizePixel = 0
		rim.AnchorPoint = Vector2.new(0.5, 0.5)
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		--- Square corners, like the art under it. The default `Round` join rounds the stroke's
		--- outer corners, which on a square card reads as a frame that does not quite fit.
		stroke.LineJoinMode = Enum.LineJoinMode.Miter
		stroke.Parent = rim
		rim.Parent = card
	end
	rim.ZIndex = zIndex
	local stroke = rim:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = colour
	end
	return rim
end

--[[ Lay a rim over a box given in the card's scale, pulled in by its own thickness so the stroke
	lands on the box's outermost `px` pixels. `card` is the card's RENDERED size, and the inset is
	converted through it into scale rather than written as an offset: a stroke is drawn at its face
	value whatever `UIScale` says (measured at a page scale of 1.75) while an offset is scaled with
	everything else, so an offset inset misses the stroke for the whole of every open tween. ]]
local function setRim(rim: Frame, centreX: number, centreY: number, width: number, height: number, px: number, card: Vector2)
	rim.Position = UDim2.fromScale(centreX, centreY)
	rim.Size = UDim2.fromScale(width - 2 * px / card.X, height - 2 * px / card.Y)
	local stroke = rim:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = px
	end
end

--[[ Pull the picture in off the card's edges to leave room for both rims and the gap between them
	(see the section note). The TOP stays where the artist put it, under the title strip; the sides
	and the bottom move in by the same number of pixels, which is why the bottom's share is converted
	through the card's aspect. `Crop` so the narrower box trims the picture instead of squeezing it. ]]
local function fitThumb(thumb: GuiObject, cardAspect: number)
	local inset = CARD_RIM + THUMB_GAP
	local top = UIGeom.top(thumb)
	local bottom = 1 - inset * cardAspect
	thumb.Size = UDim2.fromScale(1 - 2 * inset, bottom - top)
	UIGeom.place(thumb, inset, top)
	if thumb:IsA("ImageLabel") then
		thumb.ScaleType = Enum.ScaleType.Crop
	end
end

--[[ One card's band and a cell per car the world can give, in `chancesFor` order. The cells start
	empty; `stepStrip` puts a car in each while it is in view. The numbers are written by
	`_paintChances`, because they move with the player's luck and the band does not. ]]
local function buildStrip(card: GuiObject, index: number, thumb: GuiObject?)
	local strip = Instance.new("Frame")
	strip.Name = STRIP_NAME
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.fromScale(0.5, STRIP_BOTTOM)
	--- As wide as the picture it lies across; the picture's own rim is drawn over both its ends.
	strip.Size = UDim2.fromScale(if thumb then thumb.Size.X.Scale else 1, STRIP_HEIGHT)
	strip.BackgroundColor3 = STRIP_COLOUR
	strip.BackgroundTransparency = STRIP_TRANSPARENCY
	strip.BorderSizePixel = 0
	strip.ClipsDescendants = true
	strip.ZIndex = (if thumb then thumb.ZIndex else card.ZIndex) + 1
	strip.Parent = card

	local cells = {}
	for slot, chance in TrafficConfig.chancesFor(index) do
		local cell = Instance.new("Frame")
		cell.Name = string.format("Car%d", slot)
		cell.BackgroundTransparency = 1
		cell.BorderSizePixel = 0
		cell.Size = UDim2.fromScale(CELL_OF_STRIP, 1)
		cell.ZIndex = strip.ZIndex + 1
		cell.Parent = strip

		local view = CarViewport.new(cell, "CarView", STRIP_COLOUR)
		view.AnchorPoint = Vector2.new(0.5, 0)
		view.Position = UDim2.fromScale(0.5, 0.03)
		view.Size = UDim2.fromScale(1, CELL_CAR)
		view.ZIndex = cell.ZIndex

		local label = Instance.new("TextLabel")
		label.Name = "Chance"
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.fromScale(0.5, 0.98)
		label.Size = UDim2.fromScale(0.92, CELL_TEXT)
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.FontFace = FONT
		label.TextScaled = true
		--- The rarity never moves with luck, so it is written once here; only the number changes.
		label.TextColor3 = CarRarity.colourOf(chance.Band)
		label.Text = ""
		label.ZIndex = cell.ZIndex + 1
		local outline = Instance.new("UIStroke")
		outline.Color = TEXT_OUTLINE
		outline.Thickness = 1.5
		outline.Parent = label
		label.Parent = cell

		table.insert(cells, { frame = cell, view = view, label = label, body = chance.Body, built = false })
	end

	return { frame = strip, cells = cells, live = false }
end

--- Take every car out of a band. For a card that has slid out of view, and for a closed page.
local function emptyStrip(strip)
	for _, cell in strip.cells do
		if cell.built then
			cell.built = false
			CarViewport.clear(cell.view)
		end
	end
end

--[[ Place one band's cells at `phase` (in cells travelled) and give a car to each cell in view,
	spending from `budget` and returning what is left of it.

	A BAND ONLY DRIFTS WHEN IT HAS MORE CARS THAN IT CAN SHOW, and the test is one cell stricter than
	"more than fit": a car has to be able to leave by the left edge before it is wanted again at the
	right, so the band has to hold one cell more than it shows. Every world has seven cars or more and
	drifts; a band that would not is centred and left still.

	`x` is the cell's LEFT edge as a fraction of the band. It runs from -1 cell (just gone off the
	left) to `count - 1` cells, and wraps from the first to the second, which is always past the
	right edge by the test above. ]]
local function stepStrip(strip, phase: number, budget: number): number
	local cells = strip.cells
	local count = #cells
	local drifts = (count - 1) * CELL_OF_STRIP >= 1
	local at = if drifts then phase % count else 0
	local lead = if drifts then 0 else (1 - count * CELL_OF_STRIP) / 2

	for slot, cell in cells do
		local x = if drifts then ((slot - at) % count - 1) * CELL_OF_STRIP else lead + (slot - 1) * CELL_OF_STRIP
		cell.frame.Position = UDim2.fromScale(x, 0)

		--- Half a cell of lead on the right, so a car is built a second before it drifts into view
		--- and never seen arriving. Gone on the left only once it has fully left.
		local wanted = x > -CELL_OF_STRIP and x < 1 + CELL_OF_STRIP * 0.5
		if wanted and not cell.built then
			if budget > 0 then
				budget -= 1
				cell.built = true
				local size = cell.view.AbsoluteSize
				CarViewport.set(cell.view, cell.body, { aspect = if size.Y > 0 then size.X / size.Y else 1.6 })
			end
		elseif not wanted and cell.built then
			cell.built = false
			CarViewport.clear(cell.view)
		end
	end
	return budget
end

--- One card per world, cloned from the authored sample.
function Page._build(self)
	local row = self.Row
	if not row then
		return
	end

	--[[ The samples have done their job (they were measured in `_measure`, and the one this clones
		from is a detached copy). The chassis this page builds — the viewport, its track and the two
		arrows — is KEPT rather than destroyed: `_buildTrack` and `_ensureArrow` re-point what is
		already there, so a rebuild does not churn six instances to arrive at the same six. Only
		the cards go. ]]
	local built = { [VIEWPORT_NAME] = true, [ARROW_NAMES.Left] = true, [ARROW_NAMES.Right] = true }
	for _, child in self.Cards:GetChildren() do
		if child:IsA("GuiObject") and not built[child.Name] then
			child:Destroy()
		end
	end

	local worlds = WorldConfig.Worlds
	self.Entries = {}

	--[[ THE PANEL IS SIZED TO THE ROW BEFORE A SINGLE CARD IS DEALT, and everything below is laid
		out in the widened page's units. `squeeze` is the one number that carries that: the factor
		every horizontal measurement taken off the AUTHORED page has to be multiplied by.

		`visible` IS NOT THE WORLD COUNT ANY MORE — see `_fitPage`. The arrows only exist when there
		is a world they could reach, which is what keeps a three-world config on the artist's own
		untouched page. ]]
	local visible = math.min(#worlds, VISIBLE_CARDS)
	self.Pages = math.max(#worlds - visible, 0)
	local squeeze = self:_fitPage(visible, self.Pages > 0)
	self:_pinClose(squeeze)

	local _, track = self:_buildTrack(squeeze)
	--[[ AND NOW THE OLD CARDS, which is the second half of the clear above and has to happen HERE
		rather than with it. The cards live on the track, `_measure` reads the row's shape off them
		when the authored samples are gone, and the track does not exist until the line above — so
		clearing them any earlier destroys the only record of the drawing a rebuild has, and
		clearing them any later deals the new row on top of the old one. ]]
	for _, child in track:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self:_buildArrows(squeeze)

	--- A card's width over its height in PIXELS, which `fitThumb` needs to make a bottom inset the
	--- same size as a side one. Off the authored page, where both are fractions of one rect.
	local cardAspect = row.width * (row.aspect or 1) / math.max(row.height, 1e-3)

	for index in worlds do
		local card = row.sample:Clone()
		card.Name = string.format("Card%d", index)
		--[[ The attribute the press is resolved through — see WorldController. Written here rather
			than authored, because which card is which world is a fact about the config and the
			sample cards ship with it blank. ]]
		card:SetAttribute(WorldConfig.WorldAttribute, index)

		local name = card:FindFirstChild("PlaceName")
		if name and name:IsA("TextLabel") then
			name.Text = oneLine(WorldConfig.displayName(index))
			--[[ WIDER THAN THE ARTIST'S BOX, and this is the one place on the card that takes a
				liberty with it. The title is capped at the size the LONGEST world name can hold
				(see `_fitTitles`), so every unused pixel of width costs all four cards type size —
				and at the authored 0.80 that cap lands at 15px while the strip the title sits on
				runs the full width of the card with nothing else in it. 0.94 buys ~20% and still
				leaves a clear margin inside the card's edge. ]]
			name.Size = UDim2.fromScale(0.94, name.Size.Y.Scale)
		end

		--[[ THE PICTURE OF THE ROAD, looked up by the world's MAP and not by its index — see
			`UIAssets.Worlds` for why, and for how a replacement shot is taken. A map with no
			picture (and a ladder with no map) resolves to the artist's placeholder, which is the
			same flat rect the sample card ships with, so this line cannot leave a card blank. ]]
		local thumb = card:FindFirstChild("Thumb")
		if thumb and thumb:IsA("ImageLabel") then
			thumb.Image = UIAssets.url(UIAssets.worldThumb(WorldConfig.mapFor(index)))
			fitThumb(thumb, cardAspect)
		else
			thumb = nil
		end

		--[[ The rims go over everything else on the card, the band of cars included: the picture's
			rim is drawn across both ends of the band, which is what makes the band read as lying ON
			the picture rather than beside it. ]]
		local accent = accentOf(index)
		local rimZ = card.ZIndex + 5
		local cardRim = ensureRim(card, CARD_RIM_NAME, accent, rimZ)
		local thumbRim = if thumb then ensureRim(card, THUMB_RIM_NAME, accent, rimZ) else nil
		local strip = buildStrip(card, index, thumb)

		self:_place(card, index)
		card.Parent = track

		--[[ The button's caption gets the same widening as the title, for the same reason and with
			the same care about the art. It is the LONGEST state that sets the size — "MOUNTAINS 0%"
			against PLAY — and at the authored 0.80 that state lands at 15px while three-quarters of
			the button's face is empty either side of it. 0.92 puts it at 18px against PLAY's 21,
			which is close enough to read as one row of buttons rather than four.

			HEIGHT IS LEFT ALONE. The label is inset to about half the button's height so the face's
			painted bevel is not written over, and that inset is the artist's and is correct. ]]
		local button = card:FindFirstChild("TeleportButton")
		local caption = button and button:FindFirstChild("Label")
		if caption and caption:IsA("TextLabel") then
			caption.Size = UDim2.fromScale(0.92, caption.Size.Y.Scale)
		end

		--[[ A CONSOLE SELECTION DRAGS THE ROW WITH IT. The cards off screen are still selectable —
			they are real instances a stick can reach — so without this the gamepad's focus walks
			into a card behind the clip and the screen looks like it stopped responding. Two lines,
			and it is the only thing on this page that knows a gamepad exists. ]]
		if button and button:IsA("GuiObject") then
			button.SelectionGained:Connect(function()
				self:_focus(index)
			end)
		end

		table.insert(self.Entries, {
			index = index,
			card = card,
			button = button,
			thumb = thumb,
			strip = strip,
			cardRim = cardRim,
			thumbRim = thumbRim,
		})
	end

	--- Snapped, not tweened: this is where the row STARTS, and a page that slides into place the
	--- first time it is opened reads as a page that has not finished loading.
	self:_slideTo(self.Offset or 0, true)
	self:_fitTitles()
	self:_fitRims()
	--[[ ...and again once the engine has laid the row out. The cap is worked out from the label's
		`AbsoluteSize`, and a card parented this frame does not have one yet — the call above is
		reading the sample's size or a zero.

		The first build gets away with it because measuring the font yields, so the re-fit that
		measurement schedules lands after the layout anyway. A REBUILD does not: the measurement is
		cached by then, `_fitTitles` returns synchronously, and at three worlds `_fitPage` changes
		nothing, so the `AbsoluteSize` signal never fires either and the row would keep whatever cap
		it computed off a stale box. One frame is the whole fix. ]]
	task.spawn(function()
		task.wait()
		self:_fitTitles()
		self:_fitRims()
	end)
end

--[[ === ONE TYPE SIZE FOR EVERY CARD TITLE ====================================================

	`TextScaled` sizes each label to ITS OWN string, and on a row of cards that is the wrong answer
	even though every individual card is right: CITY came out at about 20px and FOREST MOUNTAINS at
	13px, so four cards that are the same kind of thing were set in four sizes. That reads as a
	mistake, and it was the loudest thing wrong with this screen after the empty band.

	The fix is to cap every title at the size the LONGEST of them can take. `UITextSizeConstraint`
	does the capping; the number is what this works out. Every card is the same size, so the height
	term is common to all four and only the widest string matters — measured once, at a reference
	size, and kept as a width so it survives a viewport change without re-measuring.

	IT IS A CAP AND NOT AN ASSIGNMENT, which is what keeps `TextScaled` in charge: a name longer
	than anything in the config today still shrinks to fit rather than overflowing, and the cap only
	ever stops a SHORT name from growing past its siblings.

	NO WRAPPING TO WORRY ABOUT — `oneLine` joins every name with non-breaking spaces, so `TextScaled`
	cannot take its usual way out of breaking a long caption onto a second line instead of shrinking
	it (which this repo has paid for before; the note on the weather pill's `Multiplier` has it). ]]
local TITLE_REF = 100

--- The widest authored world name, in pixels at `TITLE_REF`. Measured once per session — it is a
--- fact about the config and the font, not about the viewport. Nil until the measurement lands, and
--- nil forever if it throws, which leaves every title on plain `TextScaled` exactly as before.
local titleWidth: number? = nil

local function measureTitles(face: Font)
	local widest = 0
	for index in WorldConfig.Worlds do
		local params = Instance.new("GetTextBoundsParams")
		params.Text = oneLine(WorldConfig.displayName(index))
		params.Font = face
		params.Size = TITLE_REF
		local ok, bounds = pcall(function()
			return TextService:GetTextBoundsAsync(params)
		end)
		if ok and bounds then
			widest = math.max(widest, bounds.X)
		end
	end
	if widest > 0 then
		titleWidth = widest
	end
end

function Page._fitTitles(self)
	if not self.Entries then
		return
	end

	local labels = {}
	for _, entry in self.Entries do
		local label = entry.card:FindFirstChild("PlaceName")
		if label and label:IsA("TextLabel") then
			table.insert(labels, label)
		end
	end
	local first = labels[1]
	if not first then
		return
	end

	--[[ The measurement is asynchronous and the row is not, so the first build lays the titles out
		on plain `TextScaled` and this comes back to cap them. Deferring the RE-fit rather than the
		whole thing is deliberate: a page that opens before the bounds land shows four correct
		titles at four sizes for a frame, not four blank cards. ]]
	if not titleWidth then
		task.spawn(function()
			measureTitles(first.FontFace)
			if titleWidth then
				self:_fitTitles()
			end
		end)
		return
	end

	for _, label in labels do
		local box = label.AbsoluteSize
		if box.X > 0 and box.Y > 0 then
			local cap = label:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
			cap.MaxTextSize = math.max(1, math.floor(math.min(TITLE_REF * box.X / titleWidth, box.Y)))
			cap.Parent = label
		end
	end
end

--[[ Both rims on every card, off the card's RENDERED width. Called wherever `_fitTitles` is, for
	the same reason: it is measured in a unit the window can change. The page's open tween fires it
	every frame, which is what keeps a rim the same share of its card all the way up the tween (a
	stroke does not grow with `UIScale` on its own; see `setRim`). ]]
function Page._fitRims(self)
	if not self.Entries then
		return
	end
	for _, entry in self.Entries do
		local card = entry.card.AbsoluteSize
		if card.X <= 0 or card.Y <= 0 then
			continue
		end
		if entry.cardRim then
			setRim(entry.cardRim, 0.5, 0.5, 1, 1, math.max(1, math.round(card.X * CARD_RIM)), card)
		end
		if entry.thumbRim and entry.thumb then
			local centreX, centreY = UIGeom.centre(entry.thumb)
			setRim(
				entry.thumbRim,
				centreX,
				centreY,
				entry.thumb.Size.X.Scale,
				entry.thumb.Size.Y.Scale,
				math.max(1, math.round(card.X * THUMB_RIM)),
				card
			)
		end
	end
end

--- Every card's numbers, at this player's luck. Called on every repaint and whenever luck moves.
function Page._paintChances(self)
	if not self.Entries then
		return
	end
	local luck = luckOf(self.Player)
	for _, entry in self.Entries do
		local strip = entry.strip
		if not strip then
			continue
		end
		local byBody = {}
		for _, chance in TrafficConfig.chancesFor(entry.index, luck) do
			byBody[chance.Body] = chance.Chance
		end
		for _, cell in strip.cells do
			cell.label.Text = formatChance(byBody[cell.body] or 0)
		end
	end
end

--[[ One frame of every band's drift. A card's band only moves, and only holds cars, while some of
	the card is inside the carousel's window; the moment it slides out its cars go.

	THE CARD'S PLACE IS READ OFF THE TRACK, NOT `self.Offset`. `_slideTo` writes the offset it is
	heading for at the start of a tween, so for the length of every slide the offset says the row has
	already arrived; the track's own position is where it actually is. ]]
function Page._stepStrips(self, dt: number)
	local entries, track = self.Entries, self.Track
	if not (entries and track) then
		return
	end
	self._stripPhase = (self._stripPhase or 0) + dt * STRIP_SPEED

	local scroll = track.Position.X.Scale
	local step, width = self.Step or 0, self.CardWidth or 0
	local budget = STRIP_BUILD_BUDGET
	for _, entry in entries do
		local strip = entry.strip
		if not strip then
			continue
		end
		local left = (entry.index - 1) * step + scroll
		if left < 1 and left + width > 0 then
			strip.live = true
			budget = stepStrip(strip, self._stripPhase, budget)
		elseif strip.live then
			strip.live = false
			emptyStrip(strip)
		end
	end
end

--[[ The drift runs while the page is up and not otherwise: a Heartbeat for as long as it is open,
	and every car emptied out of every band the moment it shuts. `UIController` hides the page at
	the END of its close tween, so the bands are still full for the whole of the animation out. ]]
function Page._runStrips(self, on: boolean)
	if on then
		if not self._stripLoop then
			self._stripLoop = RunService.Heartbeat:Connect(function(dt)
				self:_stepStrips(dt)
			end)
		end
		return
	end

	if self._stripLoop then
		self._stripLoop:Disconnect()
		self._stripLoop = nil
	end
	for _, entry in self.Entries or {} do
		if entry.strip then
			entry.strip.live = false
			emptyStrip(entry.strip)
		end
	end
end

--[[ What each card says right now: whether you can start a run there, what it would cost if you
	can't, and what you have to finish first if it is not even for sale.

	Every world you OWN reads PLAY, INCLUDING the one you are standing in — see the header. So there
	is nothing on the card that says "you are here" any more; the screen answers "where do you want
	to go", which is the question the Play button just asked.

	A world you do not own reads either a PRICE or a REQUIREMENT, and the difference between those
	two is the whole prerequisite design on one button: a price means the road before this one is
	finished and only money is left, a requirement means money would not help yet. `WorldController`
	decides which; this only draws it.

	DIMMING AND DEADNESS ARE NOT THE SAME THING HERE, which is why `enabled` is asked for separately.
	A price you cannot afford yet is a card you are meant to look at — it stays lit, showing the
	number you are saving toward, and since 2026-09-30 its press is live too: it offers the cash
	that closes the gap (`WorldController._onTeleportPressed`). Only a world that is not for sale
	at all fades. ]]
function Page._repaint(self)
	if not self.Entries then
		return
	end
	local WorldController = Shard.get("WorldController")
	-- Decoded once for the whole row — see `paintBadge`. Cheap enough to do on every repaint rather
	-- than caching and having to work out when the cache is stale.
	local weather = WeatherConfig.decode(workspace:GetAttribute(WeatherConfig.Attribute))

	for _, entry in self.Entries do
		paintBadge(entry.card, entry.index, weather)
		local state = if WorldController
			then WorldController:cardState(entry.index)
			else { action = "play", label = "play", enabled = true }

		local label = labelFor(state)
		local allowed = state.enabled
		-- Lit unless there is nothing to be done here at all. A price is worth reading.
		local lit = state.action ~= "blocked"
		local button = entry.button
		if button then
			local text = button:FindFirstChild("Label")
			if text and text:IsA("TextLabel") then
				text.Text = label
			end
			--[[ `Active` and not `Visible`: a dead button that is still there tells you the world
				exists and you cannot go now, which is the whole point of showing it. Roblox stops
				firing MouseButton1Down on an inactive button, so the press cannot land even though
				`WorldController` would refuse it anyway. ]]
			if button:IsA("GuiButton") then
				button.Active = allowed
				button.AutoButtonColor = allowed
			end
			if button:IsA("ImageButton") then
				button.ImageTransparency = if lit then 0 else DIM
			end
		end
		if entry.card:IsA("ImageLabel") or entry.card:IsA("ImageButton") then
			entry.card.ImageTransparency = if lit then 0 else DIM
		end
		--- The rims are the card's frame and fade with it; a bright frame round a faded card reads
		--- as the one card on the row that is lit.
		for _, rim in { entry.cardRim, entry.thumbRim } do
			local stroke = rim and rim:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = if lit then 0 else DIM
			end
		end
	end

	self:_paintChances()
	--- The arrows are drawn from the row's position rather than from any world's state, so they
	--- only need repainting here because a rebuild can change how many pages there are.
	self:_paintArrows()
end

function Page.initialize(self)
	self.Row = self:_measure()
	self:_build()
	self:_repaint()
	--- Snapped, because nothing has been on screen yet — see `_focus`.
	self:_focus(WorldConfig.resolve(self.Player:GetAttribute(WorldConfig.WorldAttribute)), true)

	--[[ The title cap is in PIXELS and is worked out from the card's pixel width, so it is stale the
		moment the window changes size. Cheap to redo and it is the only thing on this page measured
		in a unit the viewport can move. ]]
	self.PageUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_fitTitles()
		self:_fitRims()
	end)

	--[[ The odds under every card move with this player's luck, which is bought on a board, bought as
		a pass or claimed from the Index and published as these three attributes. Any can change while
		the page is open (the shop opens over it). ]]
	for _, attribute in { UpgradeConfig.Attribute, LUCKY_ROADS_ATTRIBUTE, IndexRewardConfig.CountAttribute } do
		self.Player:GetAttributeChangedSignal(attribute):Connect(function()
			self:_paintChances()
		end)
	end

	self.PageUI:GetPropertyChangedSignal("Visible"):Connect(function()
		self:_runStrips(self.PageUI.Visible)
	end)
	self:_runStrips(self.PageUI.Visible)

	-- Redrawn from the two things a card is drawn from: which world the server says we are in, and
	-- whether a race is on. WorldController publishes both as one event.
	Dispatcher:Subscribe(WorldConfig.StateEvent, function()
		self:_repaint()
	end)

	--[[ ...and on the weather, which is the one thing on this card that changes while the screen is
		OPEN and is not published through `WorldConfig.StateEvent`. A player deciding where to go can
		easily be looking at this when a storm starts somewhere; without this the flag would only
		appear the next time something else happened to repaint the row. ]]
	workspace:GetAttributeChangedSignal(WeatherConfig.Attribute):Connect(function()
		self:_repaint()
	end)
end

--[[ UIController's hook for "the page is opening", called before its scale tween and without this
	page having to own that tween. Belt and braces next to the event above — cheap, and it means a
	screen opened after a missed publish is still right.

	IT ALSO PUTS THE ROW BACK ON YOUR OWN WORLD every time the screen opens, and snaps rather than
	slides for the same reason the build does: the page is behind UIController's scale tween at this
	point, so a carousel animating underneath it arrives twice. Where the player left the row on the
	LAST visit is deliberately not remembered — the question this screen asks is always the same one,
	and the answer it should open on is always where you are now. ]]
function Page.StartOpenThread(self)
	self:_repaint()
	self:_focus(WorldConfig.resolve(self.Player:GetAttribute(WorldConfig.WorldAttribute)), true)
end

return Page
