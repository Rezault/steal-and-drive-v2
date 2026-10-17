--[[
	RandomCarConfig
	---------------
	THE RANDOM CAR PULL: one Robux product, one roll against this world's ladder, one car that is
	yours from then on. The offer is the card that slides in from the right-hand edge on a timer;
	the payoff is the reveal panel that opens over the middle of the screen.

	=== READ THIS FIRST: IT ADDS NO ECONOMY AND NO SECOND WAY TO OWN A CAR =====================

	This is `OfflineConfig`'s bargain, made again. That file's header says offline income was never
	a thing the welcome-back screen added — the money already worked, nobody had ever SEEN it. The
	same is true here: `GarageService.awardCar` is how a car enters a collection, it has been since
	the day the truck banked the first one, and every branch of it is already written — the
	catalogue ticks, a free bay parks it, a better car pushes the worst one back, an exact duplicate
	sells at `SellSeconds`.

	SO THIS FILE ROLLS A NAME AND HANDS IT TO THAT CALL. It does not price a car, it does not park
	one, and it must never learn how. The moment "a car you pulled" and "a car you stole" go through
	different code, every screen in the game has two cases to draw and the two quietly disagree —
	which is the same argument `CarDealConfig` note 2 makes for cash buying, and it is the reason
	both features are as small as they are.

	=== ...AND THE ODDS ARE NOT NEW EITHER ====================================================

	`TrafficConfig.TiersByWorld` already holds, for every rung of every world, the `Weight` that
	decides how often that car turns up ON THE ROAD. That table is the game's own statement of what
	is common and what is rare — it is resampled from `TrafficConfig.Bands` onto whatever number of
	cars a world has, it is floored at 1 so no car is unreachable, and it carries the `Rarity` word
	the shop already prints on a listing.

	THE PULL USES IT UNCHANGED. Not a copy of it, not a table of its own scaled to feel generous:
	the literal same numbers. Two things fall out of that and both are worth more than any tuning
	this file could do instead.

	  • THE ODDS ARE ALREADY TRUE. A Supercar is 1-in-10 against a Beater on the road and 1-in-10
	    against a Beater in the pull. A player who has driven this world has already learned these
	    odds by playing, so the pull cannot feel like it is lying to them.
	  • THERE IS ONE PLACE TO TUNE RARITY. Move a band weight in `TrafficConfig` and the road and
	    the pull move together. A second table here would drift from the first within a month, and
	    the drift would show up as "why does the shop say Supercars are rare when I see them
	    constantly" — which is a bug report nobody can act on.

	If the pull ever genuinely needs to be kinder than the road, `WeightPower` below is the one
	honest lever: it bends the whole curve at once and stays a function of the same numbers. Reach
	for it before you reach for a table.

	=== WHAT THE CARD SHOWS IS NOT WHAT THE PULL GIVES =========================================

	`Teaser` decides the car on the OFFER card and it is `"BestInWorld"` — the top rung of the
	world the player is standing in, drawn as a silhouette. The pull itself rolls the whole ladder
	(`Pool`), so the car on the card is the best possible outcome and not the expected one.

	THAT IS A CLAIM WITH A KNIFE-EDGE ON IT, so it is worth writing down where the edge is. Showing
	the best car is honest as long as the card never says the player will GET it: it is a silhouette
	— a shape, unnamed, unpriced — over the words in `CardTitle`, which say "random". A card that
	named the car, or printed its income, would be selling a specific car for 99 Robux and would
	deserve every refund request it got. Keep the silhouette anonymous and the copy honest, or set
	`Teaser` to `"Rolled"` and let the card show nothing at all.

	`Pool` and `Teaser` are separate settings ON PURPOSE and either can move without the other.

	=== THE PULL IS BANKED, LIKE EVERY OTHER PRODUCT IN THIS GAME ==============================

	`ProfileKey` holds pulls bought and not yet rolled, exactly as `ExtraLives` holds lives and
	`OfflineBoosts` holds multipliers, and for the reason `DevProductsHandler`'s header gives: a
	receipt lands when it lands. But this product has a second reason the other two do not, and it
	is the stronger one.

	THE ROLL IS THE THING BEING SOLD. A revive that is granted late still revives; a boost granted
	late still multiplies the next claim. A car rolled inside a receipt on a server the player is
	not looking at is a car that appears in their lot with no moment attached to it — and the
	moment, the sunburst and the shape turning into a Mustang, is most of what 99 Robux bought.
	So the receipt banks a PULL and the reveal spends it. A player who bought one and left owns a
	pull, and the next screen they open rolls it in front of them.

	=== ROBLOX'S PAID RANDOM ITEMS POLICY (2026-10-15) =========================================

	A pull is a paid random item, so Roblox's policy applies to it, and it asks for three things.
	Each lives in one place:

	  • ELIGIBILITY. `PolicyService:GetPolicyInfoForPlayerAsync` says, per player, whether paid
	    random items are restricted where they live (`ArePaidRandomItemsRestricted`). Such a player
	    may not buy a pull OR open one. `RandomCarService` asks on join and reports the card as not
	    sellable to them, which takes it off their screen (the "remove or hide" treatment), and
	    refuses the press and the roll on the server whatever the client sends. A lookup that keeps
	    failing counts as restricted: the cost of that is one unsold pull, the cost of the other way
	    round is a breach. See `Policy` below.
	  • EVERY OUTCOME AND ITS CHANCE. Not a summary by rarity: each car, and each paint it can come
	    in, since body plus colour is the car. `oddsFor` and `paintOdds` below. The PolicyService
	    check does not replace this: the odds rule covers every player, the check is a second rule.
	  • PRECISION AND WORDING. A percentage to four decimal places below its first non-zero digit,
	    with a note that rounded figures may not total 100% (`formatChance`), behind a button that
	    says what it is ("ODDS"), never a bare `?` (`Odds.ButtonText`). On the new UI the button
	    opens a page of its own (`Odds.PageName`, `PagesV2/CarOdds`), a card per outcome.

	=== THE CARD IS A NAG, SO IT IS TUNED LIKE ONE =============================================

	Ported from NeedohEscape's `SideButtons` — the rotating right-side product buttons, which is
	the structure this project's `UIController` header already says is the one to be on. The cadence
	below is the whole of what keeps it the right side of annoying: it shows for `ShowSeconds`,
	goes away for `HideSeconds`, and takes itself off screen entirely while a race is running
	(`HideDuringRace`). A permanent button would be furniture the player stops seeing; a card that
	never leaves is a card they resent.

	THAT ARGUMENT LOST ON 2026-10-15: the boss wants the card up permanently, so `Card.Permanent`
	keeps it on screen in the lobby, smaller and without its panel. It is a flag so the cycle above
	can come back by flipping one value. See `Card.Permanent`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- The rbxsync-generated id table. The product id is resolved out of here by KEY, never pasted —
--- see `Key` below and the header on `shared/GameIds`.
local GameIds = require(ReplicatedStorage.shared.GameIds)

--[[ For the odds alone — `TiersByWorld` is the per-world, per-rung weight table this file rolls
	against. `TrafficConfig` requires `WorldConfig` and nothing that requires this file, so there is
	no cycle. ]]
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
--- For the paint odds alone (`paintOdds`). It requires nothing, so there is no cycle.
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)

local RandomCarConfig = {}

--[[ Master switch. Off = no card on the right, no reveal panel, no product function registered in
	`DevProductsHandler`, and nothing prompts for Robux. Pulls already banked on a profile survive
	it and roll on the day it is switched back on. ]]
RandomCarConfig.Enabled = true

-- === The product ============================================================

--[[ Ties this to its `[products.<key>]` block in `rbxsync.toml`. The id is filled in below from the
	rbxsync-generated `GameIds` and is 0 only if the sync has never been run — which reads
	downstream as "this cannot be sold" and takes the card off the screen, never as "it is free". ]]
RandomCarConfig.Key = "RandomCar"
RandomCarConfig.ProductId = GameIds["products." .. RandomCarConfig.Key] or 0

--[[ What the CARD says, in Robux. Roblox charges what the product is priced at in `rbxsync.toml`,
	so this is a display value kept honest by hand — the same contract `OfflineConfig.Boost.Price`
	and `ReviveConfig.Tiers[n].Price` have, and the same one-line failure if it is broken. ]]
RandomCarConfig.Price = 99

--[[ Pulls bought and not yet rolled. TOP-LEVEL on the profile for the reason `ExtraLives`,
	`LastSeen`, `World` and `Quests` are: `PlayerProfile`'s string path is a recursive key search,
	so a key nested inside `Garage` would be reachable only by array path from the two places that
	touch it.

	Absent is zero, so no profile written before this line needs migrating. ]]
RandomCarConfig.ProfileKey = "RandomCarPulls"

--[[ The eligibility check (see the header's policy note). `RandomCarService` asks PolicyService up
	to `Attempts` times, `RetrySeconds` apart, and a player it never gets an answer for is treated as
	restricted for the session.

	UNTIL THE ANSWER LANDS THE PLAYER IS NOT SOLD ANYTHING. The card is held off their screen and a
	press is refused, so the window between joining and the lookup returning cannot be used to buy. In
	practice the answer is back long before `Card.FirstDelay` would have shown the card.

	A pull already banked by a restricted player (bought somewhere it was allowed, or granted) stays
	banked and is not rolled while they are restricted. Nothing is taken away from them. ]]
RandomCarConfig.Policy = {
	Attempts = 3,
	RetrySeconds = 2,
}

-- === What can be rolled =====================================================

--[[ Which cars are in the pool.

	`"CurrentWorld"` — the ladder of the world the player is standing in (`WorldConfig.WorldAttribute`).
	This is the shipping answer and it is the one that keeps the product worth buying forever: a
	player in world 3 rolls world 3 cars, so the pull scales with them instead of becoming a machine
	that hands out beaters they sold months ago.

	`"UpToCurrentWorld"` — everything they have unlocked. Strictly more cars, and strictly worse:
	the pool dilutes with every world they clear, so the product gets WEAKER as the player gets
	stronger, which is exactly backwards for the thing they are meant to keep buying.

	`"AllWorlds"` — the flat pool. A brand new account can pull the best car in the game, which is a
	real thrill and a real problem: world unlocks are the game's spine, and a product that leapfrogs
	them sells the ending. ]]
RandomCarConfig.Pool = "CurrentWorld"

--[[ Bends the weight curve without replacing it. The roll uses `Weight ^ WeightPower`, so:

	    1   — the road's own odds, exactly. A Supercar is as rare in the pull as it is in traffic.
	    <1  — flatter. 0.5 square-roots every weight, which pulls the 10:1 Beater-to-Supercar ratio
	          in to about 3:1 — kinder, still ordered, still the same table underneath.
	    >1  — steeper. Rare cars get rarer.

	ONE NUMBER RATHER THAN A TABLE, and that is the whole point of it — see the header. It cannot
	reorder the ladder, cannot make a car unreachable and cannot drift away from `TrafficConfig`,
	which are the three things a hand-written odds table does within a month of being added.

	Shipping at 1: the odds the player has already learned from driving are the odds they get. ]]
RandomCarConfig.WeightPower = 1

--[[ What the OFFER card draws, which is not what the pull gives — see the header, and read the
	knife-edge note there before changing this.

	`"BestInWorld"` — a silhouette of the top rung of the current world. The best outcome, unnamed.
	`"Rolled"` — nothing at all until the reveal. Honest to a fault and a much weaker card. ]]
RandomCarConfig.Teaser = "BestInWorld"

--[[ A CAR YOU ALREADY OWN CAN BE ROLLED, AND THERE IS DELIBERATELY NO SWITCH FOR IT.

	This was very nearly a config flag and should not be one, because "exclude owned cars" is not a
	setting somebody could sensibly flip — it is a trap with two jaws, and a key sitting here would
	only invite one of them:

	  • It makes the LAST car a CERTAIN car. A player one short of a world's full ladder would be
	    buying a guaranteed Supercar for 99 Robux, which is a different product than this one.
	  • It makes the pull worthless the moment a ladder is complete — and "I own everything here" is
	    precisely the player most willing to spend.

	A duplicate is not nothing either. `GarageService.awardCar` sells it at `SellSeconds` of its own
	income and the reveal says so plainly (`DuplicateFormat`), so a pull always pays SOMETHING. That
	is the same deal a duplicate stolen off the road has always got, which is the point.

	And it is rarer than it looks: `GarageConfig.Banking` makes body AND COLOUR the identity of a
	car, and `RandomCarService` rolls the colour off `PaintConfig` too — so a second Civic is only a
	duplicate if it is the same Civic. ]]

-- === The card on the right ==================================================

--[[ The nag cadence. See the header: the card is tuned to be missable rather than permanent.

	`ShowSeconds` / `HideSeconds` are the two halves of the cycle. Twelve on, forty-five off puts it
	in front of the player a little over once a minute — often enough to be an offer, rare enough
	that the lobby is not a shop.

	`SlideSeconds` and `SlideOffset` are NeedohSide's own numbers (`SideButtons.SLIDE_SECONDS`,
	`SLIDE_OFFSET`) and are kept identical on purpose: this is the same motion, and two games in the
	same house sliding cards at different speeds is the kind of difference nobody can name but
	everybody feels. Sine easing, out on the way in and in on the way out, so it reads as a card
	arriving rather than a card thrown.

	`SlideSeconds = 0` cuts instantly, which is what a test harness wants. ]]
RandomCarConfig.Card = {
	ShowSeconds = 12,
	HideSeconds = 45,
	SlideSeconds = 0.3,
	SlideOffset = 2, -- off-screen rest position, in multiples of the card's own width

	--[[ The first appearance is held back this long after joining. A card that slides in over the
		loading screen is a card the player never chose to look at, and the lobby needs a moment to
		be a lobby before it is allowed to sell anything. ]]
	FirstDelay = 25,

	--[[ Off screen entirely while a race is running. The card is a LOBBY object: mid-run the player
		is dodging traffic at 50 studs a second and anything that slides into the corner of the
		screen is either ignored or fatal. There is no version of this that is worth a wreck. ]]
	HideDuringRace = true,

	--- Degrees/second the sunburst turns behind the silhouette. The `SunBurst` component reads this
	--- off the instance, so it is live-tunable in Studio; negative spins the other way.
	BurstSpeed = 18,

	--[[ FEATURE FLAG (2026-10-15, the boss's call): the card stays up instead of cycling.

		On, the card is lobby furniture: it is on screen whenever the player is not in a race or
		looking at a reveal, and `ShowSeconds`, `HideSeconds` and `FirstDelay` are not read. The
		kit card also loses its panel (face, gradient, border, checker and fade) and packs into the
		smaller square below, so a permanent card costs less of the screen than the nagging one did.
		The burst stays, unclipped, as the light the silhouette sits on.

		Off, everything above runs exactly as it did before the flag existed: the cycle, the
		template's own layout, the magenta panel. Flip this one value to revert. ]]
	Permanent = true,

	--[[ The permanent card's size and layout. `Height` is a share of the screen's height (the
		cycling card is 0.34); the card is square, so it is also the width. The rest are shares of
		the card, top to bottom: the car, the title, the honesty line and the button row, then the
		ODDS pill in the top LEFT corner, over the hood (every car is posed nose-left, so the roof
		is on the right and a pill there sits on it). `BurstSize` is a multiple of the card's
		width, and 0 drops the burst entirely; past about 1.2 the rays run off the screen edge. ]]
	Compact = {
		Height = 0.24,
		CarY = 0.32,
		CarSize = Vector2.new(0.96, 0.58),
		TitleY = 0.665,
		TitleHeight = 0.13,
		SubtitleY = 0.765,
		SubtitleHeight = 0.075,
		ButtonY = 0.9,
		ButtonSize = Vector2.new(0.8, 0.19),
		OddsSize = Vector2.new(0.3, 0.115),
		OddsInset = 0.02,
		BurstSize = 1.2,
	},
}

-- === The reveal =============================================================

--[[ How the payoff plays. The panel opens with the shape still a silhouette, holds, and then the
	car resolves — which is the whole beat, and the reason the numbers are here rather than in the
	controller where they would be four magic constants in a tween.

	`SuspenseSeconds` is the hold. Long enough to be a moment, short enough that a player buying
	their fifth pull is not waiting on a cutscene they have seen four times.

	`SpinSeconds` is how long the sunburst spins UP to `RevealBurstSpeed` before the resolve. It
	accelerates into the reveal so the motion peaks on the frame the car appears.

	`SettleSeconds` is the count-up on the value line afterwards — the same trick the welcome-back
	screen uses on its number, for the same reason: a figure that lands instantly is a figure the
	player does not read. ]]
RandomCarConfig.Reveal = {
	SuspenseSeconds = 1.1,
	SpinSeconds = 1.1,
	SettleSeconds = 0.45,
	BurstSpeed = 18,
	RevealBurstSpeed = 220,

	--[[ Seconds before the panel will accept a close. A modal that can be dismissed on the frame it
		opens eats its own reveal to a stray click — and the player who does that has paid 99 Robux
		to see nothing. It is a lockout on the BUTTON, never on the panel: nothing else is blocked,
		and the reveal has already happened by the time it lifts. ]]
	CloseLockSeconds = 0.6,
}

-- === What it says ===========================================================
--[[ Copy lives here rather than in the controller for `OfflineConfig`'s reason: every one of these
	is a sentence somebody who is not me will want to rewrite, and none of them should need a diff
	of a layout file to find. Everything is upper-cased by the screen, which is the kit's voice. ]]

--- On the offer card. It says RANDOM in the loudest place on the card, which is the whole of what
--- keeps a silhouette of the world's best car honest — see the header.
RandomCarConfig.CardTitle = "RANDOM CAR"
RandomCarConfig.CardSubtitle = "ANY CAR IN THIS WORLD"

--- The card's own button. `%d` is `Price` above.
RandomCarConfig.CardBuyFormat = "R$%d"

--- ...and what it says instead for a player already holding a pull they have not rolled. They are
--- not being sold anything, so the price is GONE rather than greyed — `OfflineConfig`'s
--- `BoostOwnedText` makes the same two-state split for the same reason.
RandomCarConfig.CardOpenText = "OPEN"
RandomCarConfig.CardOpenFormat = "OPEN (%d)"

--- The reveal panel, before and after the car resolves.
RandomCarConfig.RevealTitle = "YOUR CAR"
RandomCarConfig.RollingText = "ROLLING..."

--- Under the car once it lands. `%s` is the rarity word off `TrafficConfig.Bands` ("Legendary").
RandomCarConfig.RarityFormat = "%s"

--[[ The outcome line, one per branch `GarageService.awardCar` can return. They are separate strings
	rather than one with a verb swapped in because they are genuinely different news and the player
	deserves to be told which one happened:

	`ParkedFormat`   — new car, free bay, it is standing on the lot. `%s` is the bay number.
	`SwappedFormat`  — new car, full lot, it took the worst bay and that car went to the collection.
	                   `%s` is the bay. IT DOES NOT NAME THE CAR THAT CAME OFF, on purpose:
	                   `GarageService.awardCar` decides which bay was worst and does not report it,
	                   so naming it here would mean this service re-deciding "worst" with its own
	                   copy of `rateOf` — a second definition of the rule, drifting from the first
	                   the day either moves. The bay number is read back off the lot, which is a
	                   fact rather than a re-derivation.
	`CollectedText`  — new car, full lot, not better than anything on it. Still owned, still in the
	                   collection, and the line says so rather than leaving the player to wonder.
	`DuplicateFormat`— already owned, so it sold. `%s` is the cash, already formatted by
	                   `GarageConfig.formatCash` — the pull always pays something, see `AllowOwned`. ]]
RandomCarConfig.ParkedFormat = "PARKED IN BAY %s"
RandomCarConfig.SwappedFormat = "PARKED IN BAY %s. YOUR WORST CAR WENT BACK"
RandomCarConfig.CollectedText = "ADDED TO YOUR COLLECTION"
RandomCarConfig.DuplicateFormat = "AUTO-SOLD FOR %s"

--- The reveal's dismiss button.
RandomCarConfig.RevealCloseText = "NICE"

--- Shown on the card when the product exists but the roll cannot happen — no world loaded, no
--- profile yet. It is never shown for a car the roll simply did not like; there is no such case.
RandomCarConfig.UnavailableText = "COMING SOON"

-- === The odds ===============================================================

--[[ The pool for a world, as a list of `TrafficConfig.TiersByWorld` entries.

	IT RETURNS THAT TABLE'S OWN ROWS, not copies and not a reshaped subset: every consumer here
	wants `Name`, `Tier`, `Rarity` and `Weight`, which is exactly what a row already is. Copying
	them would be a second definition of what a car is, which is the thing this whole file is
	written to avoid.

	An unknown or absent world resolves to the active one (`WorldConfig.resolve`), so a player whose
	world attribute has not replicated yet rolls world 1 rather than nothing. ]]
function RandomCarConfig.poolFor(world: unknown): { any }
	local index = WorldConfig.resolve(world)

	if RandomCarConfig.Pool == "AllWorlds" then
		local all = {}
		for worldIndex in WorldConfig.Worlds do
			for _, entry in TrafficConfig.TiersByWorld[worldIndex] or {} do
				table.insert(all, entry)
			end
		end
		return all
	end

	if RandomCarConfig.Pool == "UpToCurrentWorld" then
		local upTo = {}
		for worldIndex = 1, index do
			for _, entry in TrafficConfig.TiersByWorld[worldIndex] or {} do
				table.insert(upTo, entry)
			end
		end
		return upTo
	end

	--- `"CurrentWorld"` and anything unrecognised. An unknown pool name falling back to the tightest
	--- pool is the safe direction: it cannot accidentally hand out a car from a world the player has
	--- never seen.
	return TrafficConfig.TiersByWorld[index] or {}
end

--[[ Roll one. Returns the winning entry, or nil for a world with no cars — which is a real answer
	(a ladder that has not been authored yet) and not a case to paper over.

	=== IT TAKES AN RNG RATHER THAN USING `math.random` ========================================

	SERVER-SIDE AND SEEDED BY ITS CALLER, always. Two reasons, and the second is the one that
	matters:

	  • A shared `math.random` is a global the whole server takes turns advancing, so a pull's
	    outcome depends on what else happened to run that frame. A `Random` handed in is a stream
	    this call owns.
	  • It makes the roll REPRODUCIBLE, which is what lets a support ticket be answered. Log the
	    seed with the outcome and "I paid 99 Robux and got a beater" can be re-run rather than
	    argued about.

	The client never calls this. It cannot — the pool is public but the roll is the product, and a
	client that rolls its own car is a client that rolls until it likes the answer. ]]
function RandomCarConfig.roll(world: unknown, rng: Random): any?
	local pool = RandomCarConfig.poolFor(world)
	if #pool == 0 then
		return nil
	end

	local power = RandomCarConfig.WeightPower

	--[[ Two passes rather than one, because the total has to be known before a point can be picked
		in it. `math.max(weight, 0)` guards a hand-edited negative in `TrafficConfig`; the floor of 1
		that table already applies means the realistic total is never 0, and the fallback below
		covers the case where somebody removes that floor. ]]
	local total = 0
	for _, entry in pool do
		total += math.max(tonumber(entry.Weight) or 1, 0) ^ power
	end
	if total <= 0 then
		--- Every weight zeroed: fall back to flat rather than returning nothing. A ladder with no
		--- odds is still a ladder, and a player who paid must get a car.
		return pool[rng:NextInteger(1, #pool)]
	end

	--[[ A zero-weight rung is skipped outright rather than subtracted. Subtracting nothing changes
		nothing on almost every roll, but a `point` of exactly 0 would have landed on the first rung
		whatever its weight, and `oddsFor` promises a zero-weight car is never given. ]]
	local point = rng:NextNumber() * total
	local last = nil
	for _, entry in pool do
		local weight = math.max(tonumber(entry.Weight) or 1, 0) ^ power
		if weight > 0 then
			last = entry
			point -= weight
			if point <= 0 then
				return entry
			end
		end
	end

	--- Floating-point crumbs only: `point` can survive the loop by a few ulps on a long ladder.
	--- The last rung that could be rolled is the correct answer for it, not an error.
	return last or pool[#pool]
end

export type CarOdds = { Body: string, Tier: number, Rarity: string, Band: number, Chance: number }
export type PaintGroup = { Indices: { number }, Chance: number }
export type PaintOdds = {
	Common: { PaintGroup },
	Exceptions: { { Bodies: { string }, Groups: { PaintGroup } } },
}

--[[ THE ODDS, AS THE ODDS PAGE AND TOOLTIP PRINT THEM: one row per CAR in this world's pool, in ladder order,
	each with its chance of being the roll. `Chance` is in 0..1.

	PER CAR SINCE 2026-10-15. It was one row per rarity (2026-09-30), which read better as a tooltip
	and is not enough: Roblox's paid random items policy wants every possible outcome with its own
	number, and a rarity is a group of outcomes, not one.

	THE SAME ARITHMETIC AS `roll`, NOT A SUMMARY OF IT: the pool from `poolFor`, each rung's
	`Weight ^ WeightPower` as a share of the total. So the panel cannot disagree with the roll: move a
	band weight in `TrafficConfig` or `WeightPower` here and both move. The all-zero fallback `roll`
	makes (flat odds) is mirrored for the same reason. A car `roll` can never give (weight 0) is left
	off, because the list is of what a player may receive. Pure. ]]
function RandomCarConfig.oddsFor(world: unknown): { CarOdds }
	local pool = RandomCarConfig.poolFor(world)
	local power = RandomCarConfig.WeightPower
	local total = 0
	for _, entry in pool do
		total += math.max(tonumber(entry.Weight) or 1, 0) ^ power
	end
	local rows = {}
	for _, entry in pool do
		local chance = if total > 0 then math.max(tonumber(entry.Weight) or 1, 0) ^ power / total else 1 / #pool
		if chance > 0 then
			table.insert(rows, {
				Body = tostring(entry.Name),
				Tier = tonumber(entry.Tier) or 0,
				Rarity = tostring(entry.Rarity or ""),
				Band = tonumber(entry.Band) or 1,
				Chance = chance,
			})
		end
	end
	return rows
end

--[[ One body's paint pool as groups of colours that share a chance, biggest chance first, Stock
	before any colour it ties with. Mirrors `PaintConfig.roll`, which picks uniformly off the pool
	LIST: an index repeated in it (the default pool names Stock `StockWeight` times) is that many
	shares, so it is counted here exactly as the roll counts it. ]]
local function paintGroups(body: string): { PaintGroup }
	if not PaintConfig.Enabled then
		return { { Indices = { PaintConfig.StockIndex }, Chance = 1 } }
	end
	local pool = PaintConfig.poolFor(body)
	local counts: { [number]: number } = {}
	for _, index in pool do
		counts[index] = (counts[index] or 0) + 1
	end
	local byCount: { [number]: { number } } = {}
	for index, count in counts do
		byCount[count] = byCount[count] or {}
		table.insert(byCount[count], index)
	end
	local groups = {}
	for count, indices in byCount do
		table.sort(indices)
		table.insert(groups, { Indices = indices, Chance = count / #pool })
	end
	table.sort(groups, function(a, b)
		return a.Chance > b.Chance
	end)
	return groups
end

--- A pool's identity, so cars that roll from the same pool can share one set of rows.
local function poolKey(groups: { PaintGroup }): string
	local parts = {}
	for _, group in groups do
		table.insert(parts, string.format("%s=%.12f", table.concat(group.Indices, ","), group.Chance))
	end
	return table.concat(parts, ";")
end

--[[ THE PAINT ODDS for a world's pull. `RandomCarService` rolls a colour after the car
	(`PaintConfig.roll`), and body plus colour is the car (`GarageConfig.Banking`), so the paint is
	part of what a pull gives and is disclosed with it.

	`Common` is the pool most of this world's cars share (every car with no `PaintConfig.Pools` entry
	and no livery). `Exceptions` is each other pool, with the cars that use it: today that is only
	the `KeepLivery` cars, which always come in their factory paint. The panel marks those cars and
	prints their pool on its own row. Pure. ]]
function RandomCarConfig.paintOdds(world: unknown): PaintOdds
	local pools: { [string]: { Bodies: { string }, Groups: { PaintGroup } } } = {}
	local order: { string } = {}
	for _, car in RandomCarConfig.oddsFor(world) do
		local groups = paintGroups(car.Body)
		local key = poolKey(groups)
		if not pools[key] then
			pools[key] = { Bodies = {}, Groups = groups }
			table.insert(order, key)
		end
		table.insert(pools[key].Bodies, car.Body)
	end
	local commonKey = order[1]
	for _, key in order do
		if #pools[key].Bodies > #pools[commonKey].Bodies then
			commonKey = key
		end
	end
	local exceptions = {}
	for _, key in order do
		if key ~= commonKey then
			table.insert(exceptions, pools[key])
		end
	end
	return {
		Common = if commonKey then pools[commonKey].Groups else {},
		Exceptions = exceptions,
	}
end

--[[ The odds, wherever they are drawn. Off the offer card's ODDS button in both UIs, and visible
	before purchase, which is what Roblox's paid random items policy asks. `Enabled = false` draws
	neither and must not ship.

	ON THE NEW UI IT IS A PAGE (2026-10-15): `PageName` is `MainUIV2.Pages.<PageName>`, built by
	`BuildCarOddsV2`, and the card's button carries it as its `Page` attribute, so `UIController` opens
	it like any other page. Two tabs (`Tabs`), a card per car with the car drawn in it and a card per
	paint colour with the world's commonest car drawn in that colour. `Note` is the rounding disclaimer
	the policy asks for whenever figures are rounded (at five significant figures they always are),
	and `OnlyFormat` names a car whose paint pool is not the usual one, today the `KeepLivery` cars
	("GENES GE7: FACTORY PAINT ONLY").

	THE OLD UI KEEPS ITS TOOLTIP (`RandomCarController._buildOdds`): shown while the pointer is on the
	card and pinned open by the button, to the card's LEFT. The fields from `PaintTitle` down are only
	its. ]]
RandomCarConfig.Odds = {
	Enabled = true,
	Title = "ODDS",
	--- THE BUTTON SAYS WHAT IT IS. The policy names "Info" or "Details" and rules out a bare symbol,
	--- which is what the `?` was; "Odds" is the plainer word for the same door.
	ButtonText = "ODDS",
	PageName = "CarOdds",
	Tabs = { Cars = "CARS", Paint = "PAINT" },
	--- The top line of a paint card, where a car card prints its rarity.
	PaintWord = "PAINT",
	StockName = "FACTORY",
	OnlyFormat = "%s: %s paint only.",
	ExceptionFormat = "%s: %s.",
	Note = "Odds are rounded and may not add up to 100%.",

	PaintTitle = "PAINT",
	PaintEachFormat = "EACH OF THESE %d",
	Marks = { "*", "**", "***" },
	MarkedFormat = "%s CARS: %s",
	Width = 250,
	RowHeight = 22,
	Gap = 10, -- between the tooltip and the card
}

--[[ One chance as a percentage, to the precision Roblox's paid random items policy asks of a rounded
	figure: four decimal places below the first non-zero digit, which is five significant figures
	(35.843%, 5.8824%, 0.019996%). A figure that is exact at that precision drops its trailing zeros
	(100%, 25%); one that was rounded keeps them, because there they ARE the precision. Never 0% for
	a chance above zero. ]]
function RandomCarConfig.formatChance(chance: number): string
	local percent = chance * 100
	if percent <= 0 then
		return "0%"
	end
	local places = math.max(0, 4 - math.floor(math.log10(percent)))
	local text = string.format("%." .. places .. "f", percent)
	if places > 0 and math.abs((tonumber(text) or 0) - percent) < 1e-9 then
		text = (string.gsub(text, "%.?0+$", ""))
	end
	return text .. "%"
end

--- A paint index as the panel names it: the palette's own name, except Stock, which a player knows as
--- the car's factory paint (`GarageConfig.carName` never prints "Stock" either).
function RandomCarConfig.paintName(index: number): string
	if index == PaintConfig.StockIndex then
		return RandomCarConfig.Odds.StockName
	end
	return string.upper(PaintConfig.nameOf(index))
end

--[[ The car the OFFER card draws — see `Teaser` and the header's knife-edge note.

	Nil means "draw no car", which is `Teaser = "Rolled"` and is a supported card rather than a
	broken one. ]]
function RandomCarConfig.teaserFor(world: unknown): any?
	if RandomCarConfig.Teaser ~= "BestInWorld" then
		return nil
	end
	local pool = TrafficConfig.TiersByWorld[WorldConfig.resolve(world)]
	--- The ladder is authored worst-to-best (`WorldConfig.carsFor`), so the top rung is the last row.
	return pool and pool[#pool] or nil
end

--- Is there anything to sell? False when the feature is off or rbxsync has never been run, which
--- takes the card off the screen entirely — see `ProductId`.
function RandomCarConfig.sellable(): boolean
	return RandomCarConfig.Enabled and RandomCarConfig.ProductId ~= 0
end

return RandomCarConfig
