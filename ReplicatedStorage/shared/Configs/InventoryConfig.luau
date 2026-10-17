--[[
	InventoryConfig
	---------------
	THE CARS INVENTORY — the dealership screen, which is now the one place a player looks at the cars
	they own rather than one of three (Trello: "Cars Inventory").

	It answers three questions about a car that nothing in the game used to say out loud: what KIND
	of car is it, how good is it, and do I want to keep it. This file is the second and third of
	those; the first is `Modules/CarRarity`.

	FIVE THINGS TO KNOW BEFORE TUNING ANY OF IT.

	1. THE STAT BARS ARE A VIEW OF `CarConfig`, NOT A SECOND SET OF NUMBERS. Speed is `MaxSpeed`,
	   Acceleration is `DrivingTorque`, Handling is `MaxSteer x WheelFriction`, HP is `MaxHealth` —
	   the same fields the chassis is actually stamped with. There is deliberately no stat table
	   here: the moment a screen carries its own idea of how fast a car is, it starts lying, and the
	   one thing a stat screen cannot do is lie.

	2. THREE OF THE FOUR BARS ARE FLAT TODAY AND THAT IS A CONFIG PROBLEM, NOT A BUG HERE. Every one
	   of the 29 cars carries `DrivingTorque = 45000`, `MaxSteer = 1` and `WheelFriction = 2`, so
	   ACCELERATION and HANDLING read identically on every card in the game and only SPEED and HP
	   separate them. `CarConfig`'s own header says as much — it shipped behaviour-neutral and
	   "everything is therefore ready to be tuned and none of it is yet". This screen is what makes
	   that visible. Tune that file and these bars move; nothing here needs touching.

	3. THE BARS ARE NORMALISED AGAINST A DECLARED RANGE, NOT AGAINST THE LIVE ROSTER. Normalising
	   against the roster's own min and max is the obvious move and it is wrong twice over: with
	   flat data (note 2) the spread is zero and every bar divides by nothing, and with real data the
	   worst car in the game always draws an empty bar and the best always draws a full one, so the
	   ladder can never be seen to have moved. A declared range means a beater looks like a beater.
	   `Stats` below carries the range and the file warns at load if the roster leaves it.

	4. SPEED INCLUDES THE CAR'S LEVEL AND THE OTHER THREE DO NOT, because that is what the game
	   does: `RewardConfig.Xp.SpeedPerLevel` raises top speed and nothing else, so a levelled car is
	   genuinely faster and genuinely no grippier. It is the only reason the level on a card is worth
	   printing next to the bars rather than off on its own.

	5. A FAVOURITE IS A MARKER AND A SPEED BUMP, AND IT USED TO BE ONLY THE FIRST. It sorts a car to
	   the top of the inventory list, and at the sell lot it puts a star and an amber line on the
	   panel that asks and costs a SECOND press of SELL IT (`Sell.ConfirmFavorites` below). There was
	   a second flag called LOCK until
	   2026-08-24 and it was a hard rule — the server refused to sell a locked car — and it is gone,
	   on the owner's call: one flag, and a car you starred is SAID OUT LOUD rather than refused.
	   Profiles written before that keep a `Garage.Locked` list nothing reads, which is why nobody's
	   car is stranded behind a padlock they can no longer press.

	   THE SPEED BUMP HAS BEEN THREE THINGS AND IS STILL TWO PRESSES. A lock, then a second HOLD at
	   the button, and since 2026-08-31 a second PRESS on the panel: SELL IT turns the title into
	   ARE YOU SURE? and the next one goes through. Same number of deliberate acts as the hold, on a
	   screen where the car being confirmed is written down. `SellConfig` note 7 has the reasoning.

	HOUSE RULE: no wiki-style double-bracket links in this comment — the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarConfig = require(ReplicatedStorage.shared.Configs.CarConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local InventoryConfig = {}

--[[ Master switch for the three things this file adds to a screen that already worked: the stat
	block, the favourite flag and selling. Off = the dealership page is a bay picker again, the server
	refuses every sell and flag request, and nothing else in the game notices. ]]
InventoryConfig.Enabled = true

--[[ NOT DURING THE TUTORIAL (2026-10-14, the owner). The onboarding brings a first-timer home with
	the car in their hands and teaches the drop at a bay; the cars screen opened mid-lesson is a
	second way to do it that the lesson never mentions. `UIController:openPage` refuses `PageName`
	while any tutorial step is left. `LockedInTutorial = false`: the screen opens as before. ]]
InventoryConfig.PageName = "Dealership"
InventoryConfig.LockedInTutorial = true

--[[ THE SCREEN'S SIZE BY DEVICE (Aleafo, 2026-10-15: "can we make this menu a bit smaller?"). A share
	of the size the frame is authored at, keyed by `Enum.PreferredInput` name; a device not listed keeps
	the authored size. That size is `KitGrowth.Pages`, which was picked for PHONES (Dylan, 2026-09-16),
	so only the mouse and keyboard screen steps down: on a monitor the panel took most of the view and
	crowded the hotbar under it. Bay mode and MY CARS are one frame, so both change. ]]
InventoryConfig.PageScale = {
	KeyboardAndMouse = 0.85,
}

-- 2026-10-12: Backpack capacity only; hotbar and parked cars have separate spaces. Existing
-- larger collections stay intact; new awards auto-sell only when backpack and hotbar are full.
InventoryConfig.MaxCars = 200

-- === Profile keys ===========================================================
--[[ Both live under `Garage`, beside `Owned` and `Cars`, and both are mirrored into
	`Data/Components/Settings` TEMPLATE — these names and that template are two halves of one
	contract. There was a third, `Locked`, until 2026-08-24; header note 5 is where it went.

	`Found` IS NOT A DUPLICATE OF `Owned`, and the difference is the entire reason selling can exist:

	  • `Owned` is WHAT YOU HAVE. It used to be append-only — "nothing is ever removed from it" —
	    because nothing could take a car away from you. Selling can, so it shrinks now.
	  • `Found` is WHAT YOU HAVE EVER HAD, as BODY NAMES, and it never shrinks. The Index page is a
	    catalogue of the roster ("23/29 Stolen") and the BIGGEST COLLECTION board counts distinct
	    bodies; neither may go backwards because a player cashed in a spare Camaro. A catalogue that
	    un-ticks is a catalogue nobody trusts.

	Bodies rather than car keys, because that is the question the index asks — four colours of one
	Camaro is one entry in a catalogue. Seeded from `Owned` the first time it is read on a profile
	written before it existed, so nobody's index resets.

	THE MOST VALUABLE board is deliberately NOT moved onto `Found`: what your dealership is worth is
	a fact about the cars standing in it, so selling one should drop it. That board and the
	`DealershipValue` attribute both read `Owned` and both still should. ]]
InventoryConfig.Keys = {
	Found = "Found", -- array of BODY names, never removed
	Favorites = "Favorites", -- array of CAR KEYS the player has starred

	--[[ Array of CAR IDS the player has taken OFF sale. A car is for sale unless it is in here.

		STORED AS THE EXCEPTION, NOT AS A `ForSale` FIELD, because FOR SALE IS THE DEFAULT (the
		dealership rework's card, 2026-09-28): every car that has ever been banked — including every
		one banked before this key existed — is for sale without a single write, and only the player's
		own choice to hold one back costs a byte. It is a FLAG and not a `Garage.CarData` field for the
		reason the favourite is one: it rides `GarageService`'s flag machinery, which already owns the
		broadcast, the remote, the ownership check and the prune on sale.

		What it DOES is in `GarageService.isForSale` and the podium sign; what it will do — keep a
		buyer from making an offer — arrives with the buyers.

		VERSIONED (2026-10-06): `GarageConfig.Banking.DefaultNotForSale` was briefly on, which wrote
		every car banked in that window into the old "NotForSale" list. Bumping the key drops those
		tester-only flags without a migration; the old list is left in the profile, unread. ]]
	NotForSale = "NotForSale2",
}

--[[ The broadcasts: comma-separated car keys (or body names, for `Found`) on the Player — same
	shape and the same reasoning as `GarageConfig.OwnedAttribute`, which the header of that file has
	at length: attributes replicate, so the screen needs no remote and no round trip, and the profile
	stays the source of truth.

	`GarageConfig.OwnedAttribute` IS NOT RENAMED AND DOES NOT CHANGE MEANING. It is spelled
	"CarsFound" for historical reasons and it carries the COLLECTION, as car keys, exactly as it
	always has — the only difference is that the list can now get shorter. Four screens and one
	valuation read it; giving the new list the new name is one edit instead of five, and it leaves
	`GarageConfig.valueOfCollection` measuring the thing it was written to measure.

	So `CarsSeen` is the new one, and the Index page is the only reader that moves onto it. ]]
InventoryConfig.FoundAttribute = "CarsSeen" -- BODY names ever banked; never shrinks
InventoryConfig.FavoritesAttribute = "CarsFavorite"
InventoryConfig.NotForSaleAttribute = "CarsNotForSale" -- car IDs held back from buyers; see `Keys`

-- === The stat block =========================================================
--[[ THE FOUR BARS, in the order they are drawn. Header notes 1-4.

	`field` is the `CarConfig` key it reads; `Handling` has none because it is a product of two, and
	carries a `read` instead. `Min`/`Max` are the declared range the bar is normalised against — the
	number below `Min` draws empty, above `Max` draws full, and the load check at the bottom of this
	file names any roster car that leaves the range rather than letting a bar quietly clip.

	THE RANGES ARE WIDER THAN THE ROSTER ON PURPOSE. The speed ladder runs 42 to 114
	before upgrades (2026-10-12); level 10 plus transmission level 3 reaches 138.55.
	The 30..140 range keeps every owned car's speed visible without clipping. They are design numbers, not measurements — see header note 3. ]]
InventoryConfig.Stats = {
	{
		Key = "Speed",
		Label = "SPEED",
		Field = "MaxSpeed",
		Min = 30,
		Max = 155,
		--[[ The one stat a level moves — header note 4. `MaxSpeed` is in the pack's mph-ish unit
			(`CarConfig` divides by 0.6263 on the way to the chassis), which is why the range above is
			in that unit too and why no number from it is ever printed raw. ]]
		Levelled = true,
	},
	{
		Key = "Acceleration",
		Label = "ACCELERATION",
		Field = "DrivingTorque",
		Min = 30000,
		Max = 150000, -- Covers the existing torque buff and upgraded car values without clipping.
	},
	{
		Key = "Handling",
		Label = "HANDLING",
		--[[ TWO FIELDS, ONE BAR. `MaxSteer` is how far the rack turns and `WheelFriction` is whether
			the car holds when it does — a car with one and not the other does not handle, so the
			honest single number is the product rather than either alone or an average of the two.

			`CarConfig`'s tuning notes agree on the direction of both: steer up or friction up for
			"it corners like a boat", friction DOWN for "it should be a handful". So higher is better
			on both axes and the product needs no sign wrangling. Stock is 1 x 2 = 2, the middle of
			the range below. ]]
		Read = function(stats: { [string]: number }): number
			return ((stats.LaneSpeedScale or 1) + (stats.LaneAccelScale or 1)) * 0.5
		end,
		Min = 0.85,
		Max = 1.2,
	},
	{
		Key = "HP",
		Label = "HP",
		Field = "MaxHealth",
		Min = 60,
		Max = 160,
	},
}

--[[ What a bar's fraction is printed as beside it. Out of ten, because the artist's own card carries
	a `Rating` label reading "5.7" — a rating out of ten is the thing this kit was drawn expecting,
	and it is legible in a way "42%" and "48.8 mph-ish" are not.

	ONE DECIMAL, ALWAYS. Two cars a rung apart differ by well under a whole point on most of these,
	and a whole-number rating would print the same figure for both. ]]
InventoryConfig.RatingOutOf = 10

-- === Selling ================================================================
InventoryConfig.Sell = {
	Enabled = true,

	--[[ Most cars one request may sell. A bound on server work, not a design rule — every sale is a
		profile write plus a lot rebuild, and a client is the caller. Well above any real clear-out:
		the collection's own ceiling is 29 bodies x 15 colours, and nobody selects 40 cards by hand
		without meaning it. Anything past this is TRUNCATED, not refused, so a fat selection still
		does most of what was asked rather than silently doing nothing. ]]
	MaxPerRequest = 40,

	--[[ THE COOLDOWN MOVED (2026-08-24). It used to live here because selling was a remote the Cars
		Inventory fired; selling is now a place you drive to, so the rate limit belongs out there and is
		`SellConfig.Request.Cooldown`. Nothing on this screen can start a sale any more, so a number
		here would be one nothing reads.

		(It is a remote's rate limit again since 2026-08-31, when the held button became a panel — but
		it is that lot's remote, sent from that lot, and it is still not this screen's.) ]]

	--[[ A FAVOURITE IS ASKED ABOUT, NOT REFUSED. The panel at the lot marks a starred car with the
		same gold star this screen puts on the card and an amber line under the price, and the first
		SELL IT turns the title into ARE YOU SURE? instead of selling. It is what the LOCK flag used to
		be for and it is a better shape than that flag was: a lock was a hard refusal, and a refusal
		that can only be lifted on another screen is a car sitting unsellable until somebody remembers
		where the padlock was. Off = a starred car sells on one press like any other.

		THE WINDOW IS GONE and there is nothing to replace it with. The second hold had one
		(`SellConfig.Prompt.ConfirmSeconds`) because the first hold armed a server table that had to
		forget; the confirm is a state of a panel standing in front of the player now, so it ends when
		they answer or walk away and there is no clock to run out. ]]
	ConfirmFavorites = true,
}

-- === Words ==================================================================
--[[ Every string the screen prints, in one place. Non-breaking spaces are added where they are
	needed by the page rather than typed here, so these stay greppable. ]]
InventoryConfig.Text = {
	-- The two titles. Which one shows is which way the screen was opened — from a podium, or from
	-- the car button on the HUD rail.
	TitleBay = "CAR DEALERSHIP",
	TitleInventory = "MY CARS",

	-- The caption above the list. Bay mode names the bay; inventory mode counts the collection.
	CaptionBay = "BAY {bay}",
	CaptionInventory = "{count} / {limit}",

	--[[ THE VERB ON A CARD'S BUTTON, and only the new UI's cards have one.

		The kit draws a button under every card and the shipping screen has none (a press on the card
		IS the verb there, 2026-08-24), so these four say out loud what that press does. They are
		short because the button is a fifth of a card that is a fifth of the panel, and they are
		UPPER CASE because every other word on these two screens is.

		`ParkedHere` below doubles as the fifth: it is what the button says when it is the grey face,
		which is a card that is already what you are asking for. ]]
	ActionSpawn = "SPAWN",
	ActionPutAway = "PUT AWAY",
	ActionPark = "PARK HERE",
	ActionClear = "CLEAR BAY",

	--[[ THE INVENTORY CARD'S BUTTON SINCE THE HOTBAR (2026-09-30, `CarryConfig.Hotbar`): one press
		moves the car out of the inventory into a free hotbar slot. The grey face when every slot is
		taken says why the press is not there rather than hiding the button. SPAWN and PUT AWAY moved
		to the wings' second button, which is where the street still is. ]]
	ActionToHotbar = "TO HOTBAR",
	HotbarFull = "HOTBAR FULL",

	--[[ THE WINGS' SECOND BUTTON (2026-09-28), which only exists on the detail panel and only when the
		car it describes has a second thing to do. The panel's one button band is split in two rather
		than grown a row it has no room for (`Components/CarDetailV2.setSecondary`). Since 2026-09-30
		it is the sale toggle for a car on the bay being edited, and SPAWN / PUT AWAY (the street) for a
		car in the inventory — PICK UP and PUT DOWN went, because the hotbar is how a car reaches your
		hands now.

		THE SALE TOGGLE SAYS THE STATE, NOT THE PRESS. "FOR SALE: ON" and a press turns it off. The
		alternative — a button reading "NOT FOR SALE" on a car that IS for sale — reads as a label
		describing the car, which is the exact opposite of what it is. ]]
	ForSaleOn = "FOR SALE: ON",
	ForSaleOff = "FOR SALE: OFF",

	--[[ THE STATUS LINE ON A CARD, which is the only place any of these are printed now: the screen
		lost its primary button on 2026-08-24 and a press does the thing outright. `ClearBay` is also
		the LEAVE EMPTY card's own name. ]]
	ParkedHere = "ON THIS BAY",
	ClearBay = "LEAVE EMPTY",
	InTheLobby = "IN THE LOBBY",
	OnBay = "BAY {bay}",

	--[[ THE LAST LINE OF THE STATS TOOLTIP: what a press on the card under the pointer will do. It
		is the whole reason the tooltip has a bottom row — a screen with no buttons on it has to say
		what the gesture means somewhere, and the panel already under the player's eye is it.

		`{press}` is the verb for the device that asked, so nobody is told to click a touch screen.
		`HintParked` takes no verb because there is nothing to press for: the car is already there. ]]
	PressMouse = "CLICK",
	PressTouch = "TAP",
	HintSpawn = "{press} TO SPAWN",
	HintPutAway = "{press} TO PUT AWAY",
	HintPark = "{press} TO PARK ON BAY {bay}",
	HintParked = "ALREADY ON THIS BAY",

	--[[ SELLING LEFT THE SCREEN on 2026-08-24 and is a place you drive to, so nothing reads these
		four today. They are kept because the RULES behind them did not move — the server still
		truncates a fat batch — and a bulk-sell screen, if one ever comes back, will want the same
		words. There was a fifth, `SellLockedHint`, and it went with the lock. The lot has words of its
		own in `SellConfig.Lines`. ]]
	SellMode = "SELL",
	SellCancel = "CANCEL",
	SellConfirm = "SELL {count} FOR {value}",
	SellNothing = "PICK CARS TO SELL",

	-- The two empty states, because a panel with nothing in it should say which kind of nothing.
	NoCars = "STEAL A CAR FIRST",
	--- The inventory mode's own nothing (2026-09-30): cars are owned, just none stored here.
	NoStored = "CLICK A HOTBAR CAR TO STORE IT",
	--- The same on a controller, which cannot click a tile: the caption over the hotbar carries the
	--- button's glyph, so this names no button in words (2026-10-15).
	NoStoredPad = "HOLD A HOTBAR CAR TO STORE IT",
	NoMatch = "NO CARS MATCH THAT",

	-- The tooltip's own lines.
	Level = "LEVEL {level}",
	--[[ The card's version of the same thing. Short because it is a chip in the corner of a picture,
		and hidden entirely at level 1 — see the page's `_refresh`. ]]
	LevelShort = "LVL {level}",
	--[[ The line under the rarity: what rung the car is on and how far up its own ladder. Two facts
		that are easy to confuse, which is why they are on one line with a divider rather than on two
		lines that would read as a list. ]]
	Meta = "TIER {tier}  ·  {level}",
	--[[ The green line, which is the one number on this screen that is about MONEY rather than about
		driving. Worded as a rate rather than captioned "CASH PER SECOND" over a figure, because the
		tooltip is a third the height the detail pane was and a caption row would cost a stat bar. ]]
	RateLine = "{rate}/s",
}

-- === Derived ================================================================

--[[ The stat block a card is drawn from: `CarConfig.statsFor` with the level bonus applied to the
	one field it applies to. Returns a fresh table, because `statsFor` does and callers write into it.

	`level` may be nil — an unlevelled car, or a caller that has no levels to hand — and reads as 1,
	which is the multiplier's own no-op. ]]
function InventoryConfig.statsFor(body: unknown, level: number?, parts: unknown): { [string]: number }
	return CarConfig.statsFor(body, level, parts)
end

--[[ One stat's raw value out of a stat block, and where it lands on its own bar (0..1).

	Returns `(value, fraction)`. `fraction` is clamped, so a car tuned outside the declared range
	draws a full or empty bar rather than one that overflows its track — the load check below is
	what makes that a warning instead of a silent squash. ]]
function InventoryConfig.readStat(stat, stats: { [string]: number }): (number, number)
	local value = if stat.Read then stat.Read(stats) else (stats[stat.Field] or 0)
	local span = stat.Max - stat.Min
	local fraction = if span > 0 then (value - stat.Min) / span else 0
	return value, math.clamp(fraction, 0, 1)
end

--- That fraction as the number printed beside the bar: "6.3".
function InventoryConfig.formatRating(fraction: number): string
	return string.format("%.1f", math.clamp(fraction, 0, 1) * InventoryConfig.RatingOutOf)
end

--[[ === Load-time checks ======================================================

	A warning, never fatal, on the same principle as the rest of the config layer: a tuning mistake
	should be loud in the output of a playtest, not a game that will not start. Runs once per VM.

	IT CHECKS THE RANGE AGAINST THE ROSTER, which is the one thing a declared range can get wrong.
	`Speed` is checked at the TOP LEVEL a car can reach, because that is what will actually be drawn
	— the fastest body at level 10 is 114 x 1.18 before fitted parts, so the range must include the
	car a player worked hardest for. ]]
do
	if InventoryConfig.Enabled then
		local top = RewardConfig.Xp.MaxLevel
		for body in WorldConfig.TierOfBody do
			local best = InventoryConfig.statsFor(body, top)
			local worst = InventoryConfig.statsFor(body, 1)
			for _, stat in InventoryConfig.Stats do
				local high = (InventoryConfig.readStat(stat, best))
				local low = (InventoryConfig.readStat(stat, worst))
				if high > stat.Max or low < stat.Min then
					warn(string.format(
						"[InventoryConfig] '%s' leaves the declared %s range (%.4g..%.4g); it draws %.4g..%.4g and the bar will clip.",
						body,
						stat.Key,
						stat.Min,
						stat.Max,
						low,
						high
					))
				end
			end
		end
	end
end

--[[ "NEW CAR DISCOVERED!" (2026-10-08, `DiscoveryController`): the card for the first time a model joins
	the player's found list. `FoundFormat` is found / total over the whole roster (`CarCatalogue.Roster`,
	the Index page's own list), written over the kit's progress bar. `Hold` is seconds on screen.
	`Sound` is `SoundService.<Group>.<Name>`, silent until it exists. `Enabled = false`: no card.
	The title is in title case since 2026-10-12 because it sits in the kit's header strip, which sets
	every heading that way (the carry and weather notices beside it do too). ]]
InventoryConfig.Discovery = {
	Enabled = true,
	Title = "New Car Discovered!",
	--- A newly unlocked world's free starter car (`DiscoveryController._onUnlock`). `%s` is the world.
	FreeTitle = "New Free Car!",
	FreeFormat = "FREE IN %s",
	FoundFormat = "%d / %d FOUND",
	Hold = 5,
	Sound = { Group = "Collection", Name = "Discovered" },
}

return InventoryConfig
