--[[
	UpgradeConfig
	-------------
	Everything a player can buy for their dealership, across the two boards they buy it from: the
	FOUR tiles on the billboard standing on the forecourt (`Upgrades`, below), and the CASH PER SECOND
	kiosk on each of the six podiums (`Bay`).

	The split between them is not arbitrary — the billboard sells things that change the whole lot,
	the kiosk sells one bay's income, and `Bay`'s own header argues why both are worth having. What
	they share is this file, the curve shape, and the three button colours in `Colors`.

	SIX THINGS TO KNOW BEFORE TUNING ANY OF IT.

	1. A LEVEL IS THE ONLY THING STORED. Everything an upgrade DOES is a function of that number,
	   recomputed on every read — the same split `GarageConfig` makes for income and `RewardConfig`
	   makes for car XP. Retuning a curve below re-prices every profile that already exists instead
	   of stranding it on the old one, and there is no second number that can drift out of step.

	2. COST GROWS GEOMETRICALLY, EFFECT GROWS LINEARLY. That is the whole shape of the curve and it
	   is the standard idle-game one: `BaseCost * CostGrowth^level` against `1 + Step * level`. It
	   means every level costs more and buys the same, so the answer to "should I buy the next one?"
	   goes from obviously-yes to obviously-not-yet on its own, which is what makes the board worth
	   walking back to. `CostGrowth` is the load-bearing number in each entry; `Step` is taste.

	3. THREE OF THE FOUR ARE NUMBERS AND ONE IS THE MAP. `Luck`, `Jump` and `Customers` move odds,
	   an arc and headcount; `Floor2` — the tile that reads EXPAND BASE — builds a second storey that
	   does not exist in Workspace until it is bought. That one is the reason `UpgradeService` is a
	   service and not four lines in `GarageService` — see its header for what unlocking actually
	   does, and note that it has to be REVERSIBLE, because a plot is a seat for a session and the
	   next player to sit in it must not inherit the last one's building.

	4. THE BILLBOARD IS AUTHORED, NOT BUILT AT RUNTIME. `BuildPlotUpgradeSigns` (Command Runner)
	   grafts a sign taken out of one of the race worlds onto every plot and draws the whole 2x2 grid
	   into it; the service only ever writes TEXT and a bar width into instances that already exist.
	   Same split as the dealership sign, the collect mats and the race pads, and for the same
	   reason: nothing on a hot path should be constructing UI it could instead be filling in.
	   `Board` below is the half of that contract the code reads — renaming anything in it means
	   re-running the command.

	5. THE UPGRADES ARE PER PLAYER AND THE BOARD IS PER PLOT. The billboard shows whoever currently
	   owns the lot it stands on, exactly like the name on the dealership sign, and it is public —
	   a visitor reads your levels off it. The BUTTONS are owner-only, and that is checked on the
	   server (`UpgradeService`), never by hiding them: a SurfaceGui button a client can see is a
	   SurfaceGui button a client can fire.

	6. `Upgrades` IS EVERY UPGRADE THAT HAS EVER EXISTED; `Order` IS THE FOUR ON SALE. The board's
	   line-up has changed twice (2026-08-09, 2026-08-14), and `Income`, `Storage`, `AutoCollect` and
	   `MythicalLuck` are all still in the table below with no tile. That is deliberate and it is not
	   dead code: a profile that bought eight levels of `Income` before the swap still earns 2.2x, and
	   one holding `MythicalLuck` is still that lucky, because every effect is a function of a stored
	   level and none of them asks whether the thing is still for sale. What `Order` decides is what
	   can be BOUGHT — `isOnBoard` is the gate on the purchase remote, not `isKey`, so a retired
	   ladder cannot be bought by a client that remembers the old key.

	   RETIRING AN UPGRADE IS THEREFORE: take it out of `Order`, leave everything else alone. Deleting
	   its entry is the thing not to do — that silently zeroes a level somebody paid for.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IndexRewardConfig = require(ReplicatedStorage.shared.Configs.IndexRewardConfig)

local UpgradeConfig = {}

-- Master switch. Off = the boards are left blank, nothing can be bought, and every effect below
-- reads as level 0 — so the garage behaves exactly as it did before this file existed.
UpgradeConfig.Enabled = true

-- === Where a level lives ====================================================

--[[ The profile key, inside the `Garage` table `GarageConfig.Keys` describes.

	A MAP of upgrade key -> level, `{ Income = 3, Floor2 = 1 }`, and a map for the same datastore
	reason `Levels` and `Paints` are maps: a string-keyed table round-trips through JSON unchanged,
	while a number-keyed one with a gap in it comes back as something else entirely. Absent means
	level 0, so a fresh profile needs no migration and neither does a profile written before an
	upgrade below existed. ]]
UpgradeConfig.ProfileKey = "Upgrades"

--[[ The broadcast, on the Player, as "Income:3,Floor2:1" — the same shape and the same reasoning as
	`GarageConfig.LevelsAttribute`. It exists so a client can draw its own state without a round
	trip; nothing server-side ever reads it back, because it is a copy of something the client
	watched us send. Only levels above 0 appear, so a fresh player's is the empty string. ]]
UpgradeConfig.Attribute = "Upgrades"

--[[ Attribute stamped on the PLOT model naming the highest storey currently standing on it.

	It lives on the plot and not on the player because it describes the BUILDING: `GarageService`
	discovers bays by walking the plot, and what it needs to know is which decks are really there,
	not who paid for them. Absent reads as 1, which is the state every plot is in at load. ]]
UpgradeConfig.PlotFloorsAttribute = "TopFloor"

-- === The board ==============================================================

--[[ Instance names inside the authored billboard. These and `BuildPlotUpgradeSigns` are the two
	halves of one contract — change one, change both, then re-run the command over the plots.

		<Plot>/UpgradeSign                     -- the model, taken from Worlds.FuturisticCity
		  .UpgradeScreen (Part, invisible)     -- the canvas plate, sized to the sign's aperture
		    .UpgradeGui    (SurfaceGui, Active) -- Front face, the classic `car ui.psd` look
		    .UpgradeGuiKit (SurfaceGui, Active) -- Front face, the Cartoony Kit look
		      .Panel
		        .Owner                         -- "<Name>'s Lot", or the vacant line
		        .Grid.<key>                    -- one tile per entry in `Order`, 2 x 2
		          .Title / .Headline / .Detail / .Level
		          .LevelBar.Fill               -- Size = UDim2.new(level / max, 0, 1, 0)
		          .LevelBar.Pip<n>             -- or lit pips, n = 1 .. MaxLevel (kit face)
		          .UpgradeButton               -- .Action, .CashIcon, .Cost and .Status

	TWO FACES, ONE CONTRACT (2026-09-17). Both guis carry the same names below and differ only in
	art, so `UpgradeService` draws each with the same loop and paints its button by the gui's
	`StyleAttribute`. Which one a player SEES is the client's call (`NewUIConfig.KitUpgradeBoards`),
	which is why the server never picks: it keeps both current, and a player on either UI reads a
	live board. A one-level tile (EXPAND BASE) has no `Level` and no `LevelBar` on either face.

	WHY A PLATE AND NOT THE SIGN'S OWN FACE. The sign is a Blender MeshPart and its neon panel is
	authored 0.001 studs thick, so a SurfaceGui parented straight to it renders against a bounding
	box that is not the geometry — the same trap `BuildDealershipSigns` documents for the entrance
	beam. The plate is our own part, sized to the aperture we measured, parked just proud of it. ]]
--[[ === THE UPGRADES MACHINE — 2026-10-14 ===
	Every plot carries an `Upgrades` model (the arcade cabinet with the gear sign), and the board's
	kit face now lives in a ScreenGui page, `MainUIV2.Pages.Upgrades`, instead of on a SurfaceGui.
	Walk up to the cabinet and a prompt opens that page.

	THE PROMPT IS THE SERVER'S, THE "IS IT MINE" IS THE CLIENT'S. `UpgradeService._wireMachine` puts
	one ProximityPrompt (tagged `PromptTag`) on every plot's cabinet at boot, so it replicates and
	streams in and out with the plot like any other part of it. `UpgradeController` then switches
	each one on only on the plot whose `PlotConfig.OwnerUserIdAttribute` is this player, so a
	visitor walking past your cabinet is not offered a screen of THEIR levels on YOUR lot. That is
	presentation, not access control: buying is still `RequestUpgrade`, which the server checks
	against the plot the buyer holds.

	AND IT REPLACES THE BILLBOARD, not joins it (same day: "I don't want it in a SurfaceGui any more").
	With this on, every `Board.GuiName`/`KitGuiName` SurfaceGui on a plot is switched off and never
	drawn or bound, so the only way to buy an upgrade on the lot is the prompt and the page.

	`Enabled = false`: no prompt and no way to the page, and the billboard back, exactly as before. ]]
UpgradeConfig.Machine = {
	Enabled = true,
	ModelName = "Upgrades",
	PageName = "Upgrades",
	PromptTag = "UpgradesMachinePrompt",
	ActionText = "Upgrades",
	ObjectText = "Dealership",
	--- Instant: it opens a screen and spends nothing, so a hold would only be a delay.
	HoldDuration = 0,
	--- Studs. WAS 10 (the cabinet's footprint plus a step), which made you walk right up to it; 18
	--- (2026-10-14, the owner: "make the distance more") lights it from the edge of its pad.
	--- ...and 18 to 28 (2026-10-20, "I still need to get really close to it"): measured from the part the
	--- prompt sits on, the cabinet's middle, so 18 only reached a few steps off its front.
	MaxDistance = 28,
	--- Where the prompt hangs, as a share of the cabinet's height from its base (`UpgradeService._wireMachine`).
	--- 2026-10-20: WAS its centre (0.5), "pretty high" on a tall cabinet. Distance is measured from here too.
	PromptHeight = 0.3,
}

--[[ THE FIRST-UPGRADE NUDGE (2026-10-20, Aleafo: "after a player earns 5k ... show players hey go to
	upgrades and spend ur money (if they haven't gone to upgrades yet)"). `UpgradeNudgeController`: a
	card in the notice lane and the guide line to the player's own cabinet, once the tutorial is done,
	they hold `Cash` and they have never bought a level; gone when the Upgrades page opens (for the
	session) or anything is bought (for good). `Text`'s `%s` is `Cash`, formatted.
	`Enabled = false`: no nudge. ]]
UpgradeConfig.Nudge = {
	Enabled = true,
	Cash = 5000,
	Title = "UPGRADE TIME!",
	Text = "You have %s! Follow the line to the Upgrades machine and spend it",
}

UpgradeConfig.Board = {
	--[[ The CollectionService tag on every board's screen plate, and the ONLY way the client finds
		one. Not a path walk: `StreamingEnabled` is on in this place, so a plot 500 studs away has no
		board in the client's DataModel at boot and can gain one at any moment — a controller that
		walked `Map.Plots` at start bound nothing at all in the first playtest and warned that the
		command had never been run. A tag plus `Observers.observeTag` binds each board as it arrives
		and drops it when it streams out, which is the same integration `RaceService` uses for its
		entry pads. ]]
	Tag = "UpgradeBoard",

	ModelName = "UpgradeSign",
	ScreenName = "UpgradeScreen",
	GuiName = "UpgradeGui",
	KitGuiName = "UpgradeGuiKit",
	PanelName = "Panel",
	TitleName = "Title",
	SubtitleName = "Subtitle",
	OwnerName = "Owner",
	GridName = "Grid",

	--[[ Stamped on each SurfaceGui, naming which art it is drawn in. The service reads it to paint the
		button (a pill texture on the classic face, a gradient on the kit one), and a gui that has none
		is a board from before the two faces existed, drawn as classic. ]]
	StyleAttribute = "BoardStyle",
	ClassicStyle = "Classic",
	KitStyle = "Kit",

	-- Inside one tile.
	TileIconName = "Icon",
	TileTitleName = "Title",
	TileHeadlineName = "Headline",
	TileDetailName = "Detail",
	TileLevelName = "Level",
	TileBarName = "LevelBar",
	TileFillName = "Fill",
	--- On a pip, its 1-based rung. A pip is lit while the level has reached it.
	PipAttribute = "Pip",
	ButtonName = "UpgradeButton",
	ButtonActionName = "Action",
	ButtonCashIconName = "CashIcon",
	ButtonCostName = "Cost",
	--- The one centred word a button says when there is nothing to buy: `MaxText` or `OwnedText`.
	ButtonStatusName = "Status",

	-- Stamped on each tile so one handler serves all four and neither side hard-codes an order.
	KeyAttribute = "UpgradeKey",

	-- The header copy under the title, shared by both faces.
	TitleText = "DEALERSHIP UPGRADES",
	SubtitleText = "UPGRADE YOUR DEALERSHIP TO EARN MORE AND GO FURTHER!",

	-- What the board reads while nobody owns the lot. Matches `PlotConfig.SignVacantText` in tone:
	-- an invitation, not a dash.
	VacantText = "Available Lot",
	OwnerFormat = "%s's Lot",

	-- `(level, max)`, under a ladder's name. Mixed case with spaces, the way the mockup sets it.
	LevelFormat = "Level %d / %d",

	-- Button captions. `MaxText` replaces the action, the cash note and the cost when a level cannot
	-- be bought again, so a maxed tile reads as finished rather than as a button that does nothing.
	BuyText = "UPGRADE",
	MaxText = "MAXED",
	OwnedText = "UNLOCKED",
}

--[[ The kit face's button, as the Cartoony Kit draws a button: a vertical `UIGradient` on a white
	face, so a state is a change of gradient rather than of texture. The same three states and the
	same sentence as `ButtonPills` below.

	BUY is the kit's own confirm (the `RebirthBtn` in its Upgrades frame), VACANT its `DisabledBtn`,
	and DONE the kit's blue, because its grey already means "nobody can press this" and a maxed
	ladder is a finished thing rather than a dead one. Captions stay white on all three: the kit
	outlines every label in `#021E38`, which reads on grey where plain white on the classic silver
	pill did not. ]]
UpgradeConfig.KitButtonGradients = {
	Buy = ColorSequence.new(Color3.fromHex("ffd900"), Color3.fromHex("11d306")),
	Done = ColorSequence.new(Color3.fromHex("3bebff"), Color3.fromHex("135dfd")),
	Vacant = ColorSequence.new(Color3.fromHex("bbc0c0"), Color3.fromHex("727272")),
}

--- The kit face's level pips: its lit green and unlit grey, from the same Upgrades frame.
UpgradeConfig.KitPipGradients = {
	Lit = ColorSequence.new(Color3.fromHex("ffd900"), Color3.fromHex("11d306")),
	Unlit = ColorSequence.new(Color3.fromHex("c2c2c2"), Color3.fromHex("7d7d7d")),
}

--[[ The `car ui.psd` kit colours anything on either board changes to at runtime.

	HERE RATHER THAN IN THE SERVICES because there are two boards drawn by two different files.
	`UpgradeService` paints the forecourt billboard, `GarageService` paints the per-bay kiosks, and
	the two must not drift apart on a hue. The build commands that author the boards read the same
	values for their static art.

	THIS TABLE IS NO LONGER A BUTTON PALETTE. It held the billboard's flat `BackgroundColor3` fills
	until the 2026-08-23 pill rebuild, and the three-state sentence it spelled (blue you can buy
	this, dark card fill you cannot yet, green nothing left) is not the one either board speaks any
	more. `ButtonPills` below is the two-state one that replaced it.

	WHAT IS STILL LIVE HERE: `Muted`, which `TipsConfig` sets its body copy in, and `Done`, whose green
	`BuildDealershipSigns` matches for the valuation on a plaza stand. `Buy` and `Poor` stay because
	`TipsConfig` reasons about `Buy` being the kit's #0066FF, and because they are what a board
	authored before the rebuild still wears. ]]
UpgradeConfig.Colors = {
	Buy = Color3.fromRGB(0, 102, 255), -- #0066FF, the kit interface blue
	Poor = Color3.fromRGB(41, 52, 75), -- #29344B, the kit card fill
	Done = Color3.fromRGB(13, 180, 21), -- #0DB415, the kit money green
	Muted = Color3.fromRGB(168, 179, 208), -- secondary copy
}

--[[ === THE BUTTON IS ORANGE WHENEVER PRESSING IT DOES ANYTHING, 2026-08-26 ==================

	The billboard's UPGRADE button is a `Pill`, the seven-colour button the Index page already wears
	(`UIAssets.Pill`), so its state is a change of TEXTURE and each state brings its own idle, hover
	and pressed art rather than relying on Roblox's automatic tint. These are PILL COLOUR NAMES and
	not asset ids, deliberately: `UpgradeConfig` has no business knowing an id, and both the build
	command and `UpgradeService` look them up in `UIAssets.Pill`, so neither can drift from the other.

	=== WHY AFFORDABILITY CAME OFF THE BUTTON ===============================================

	THERE USED TO BE A THIRD STATE AND IT HAD BECOME A LIE. The button went dead Silver when the
	price was more than the balance, which is what a control says when pressing it will do nothing.
	Pressing it has not done nothing since `CashService` arrived: a press you cannot afford opens
	Roblox's own window on the cheapest cash pack that covers THE GAP. `CashConfig` argues that at
	length, and the two refusal paths are in `UpgradeService._onRequest` and `_onBayRequest`.

	So affordability stopped being the button's business. It is already on the tile, as a number,
	which is where a price belongs and is the only place it can be READ rather than guessed at, and
	the button now says the one thing it is qualified to say: there is something to press here.

	That is also why one colour is more useful than two. A face that changes under you as your
	balance crosses a price teaches a player to look at the button to find out whether they can
	afford something, and the answer it gives is now wrong in the direction that costs a sale.

	=== WHY ORANGE ==========================================================================

	Blue is this kit's INTERFACE colour: title bars, page furniture, every pill on every page. A
	blue button on a board bolted to a forecourt reads as part of the panel rather than as the one
	thing on it you press. Orange is the only warm face in the set that is not also a warning, since
	`Red` is the kit's orange-red and is spoken for by damage and by refusals, and #FFA200 against
	the board's #28334B navy is the strongest contrast the kit can make without leaving the kit.

	GREEN KEEPS MAXED, and it is the only state left that is not orange. It survives for the reason
	the old table gave for gold: a maxed tile is the one state that is not a buy, so the affordance
	the orange face speaks does not apply to it. The objection that used to stand against green here,
	that it makes maxed and affordable the same colour, died with the blue.

	SILVER KEEPS VACANT. A board on an unclaimed plot draws real prices against level zero, so with
	no state of its own every tile on an empty forecourt would advertise a purchase nobody can make.
	Silver is the kit's neutral and the one face in the set that claims nothing at all, which is
	exactly what should be said about a lot with no owner. ]]
UpgradeConfig.ButtonPills = {
	Buy = "Orange",
	Done = "Green",
	Vacant = "Silver",
}

--[[ And the caption colour that goes on each of those pills, because two of the three are light.

	The kit sets every pill's own label in white and that is right for the saturated `Green` face. It
	is wrong for the other two: `Orange` is #FFA200 at luma 172 and `Silver` is #B9CAEC at luma 200,
	so white on either lands near 1.5:1, which is unreadable across a forecourt rather than merely
	low-contrast. `#151D2D` is the kit's own outline navy, the darkest value in the panel art, and it
	lands near 4.9:1 on both. A text stroke was tried before this and made it worse: at this canvas
	scale it only thickens the glyphs into each other. `WeatherConfig.NoticePills` measures the same
	three faces and reaches the same answer.

	IT IS A PAIR WITH `ButtonPills` ABOVE and must stay one: the colour is a property of the state
	and not of the label, because the same two TextLabels sit on every pill in turn. A caption that
	kept one colour across a state change is the bug this table exists to make impossible. ]]
UpgradeConfig.ButtonTextColors = {
	Buy = Color3.fromRGB(21, 29, 45), -- #151D2D
	Done = Color3.new(1, 1, 1),
	Vacant = Color3.fromRGB(21, 29, 45), -- #151D2D
}

-- === The kiosk on every bay =================================================
--[[ CASH PER SECOND: the tilted little board standing on each podium's collect mat, and the fifth
	thing a player can buy. It multiplies THAT BAY's income and nothing else.

	=== WHY A PER-BAY LADDER EXISTS AT ALL, NEXT TO A LOT-WIDE `Income` ONE ===================

	They ask different questions, and that is the whole justification for having both:

	  • `Income` is a decision about the DEALERSHIP. It is flat across the lot, so buying it never
	    involves looking at what is parked.
	  • A BAY LEVEL IS A DECISION ABOUT ONE CAR. The cost ladder is flat but the payoff is that bay's
	    rate, so a level bought under a Tier 8 is worth thirty-nine times the same level bought under
	    a Tier 1. There is a right answer — put it under your best car — and it is one a player can
	    work out by standing in their own showroom and reading six signs. That is a good decision to
	    hand somebody, and it is one the forecourt billboard structurally cannot ask.

	It also gives the six bays a reason to be different from each other, which they otherwise are not.

	=== THE NUMBERS ==========================================================================

	LEVEL 1 IS WHERE EVERY BAY STARTS, and it is a real level rather than a level 0, because the sign
	says `Lvl 1` on an untouched bay and a board that reads `Lvl 0` reads as broken. So the stored
	value is 1..`MaxLevel` and an absent one is 1 — the one place in this file where absent is not
	zero. Ninety-nine levels can be bought.

	=== 11 RUNGS BECAME 100 ON 2026-08-21, AND THE OTHER TWO DIALS HAD TO MOVE WITH IT =========

	Aleafo's call on the "Improve Upgrade UI" card, in as many words: "Max level will be 100 for now".
	Neither of the numbers under it could stay where it was, and neither change is cosmetic:

	  • `CostGrowth` WAS EXACTLY 2, AND IS NOW 1.15. A doubling is the one growth rate a player can
	    extrapolate without doing arithmetic ("the next one is twice this one"), which is why it was
	    picked and why giving it up is a real loss — but it only survives a ladder short enough to
	    finish. 250 x 2^98 is $8e31, orders of magnitude more money than this game will ever mint, so
	    a doubling ladder with 100 rungs is a ladder with about 35 real ones and 65 pieces of dead
	    sign. At 1.15 the rungs run 250, 288, 331 ... 222M, and one bay costs about $1.7B to max
	    against $256K before.
	  • `Step` WAS +25% OF THE BAY'S BASE RATE PER LEVEL, AND IS NOW +5%. A maxed bay is 5.95x where
	    it used to be 3.5x — so the CEILING barely moved and the GRAIN moved a lot, which is the whole
	    point of having a hundred rungs instead of eleven. Left at 0.25 a maxed bay would be 25.75x,
	    and six of them an income nothing else in this economy is sized against.

	Additive and not compounding, unchanged: two multiplying ladders on the same number is a curve
	nobody can hold in their head, and `Income` sitting on top of this already reaches 13x.

	SAY THE CAVEAT OUT LOUD. $1.7B a bay, about $10B for six, makes this comfortably the largest sink
	in the game, and since the 2026-08-28 re-prices on the forecourt billboard it is the only one:
	every tile on that board together costs under $5M. Both numbers here are a considered guess at
	what 99 rungs are worth, not a figure measured against a real session. They are one line each, and every number on the kiosk is derived from them, so re-tuning
	costs nothing but a re-read of this note.

	THE $250 RUNG AT THE BOTTOM IS STILL THE TUTORIAL'S, and it is the one number here that did not
	move. The gate it was cut for is gone — the rewritten `TutorialConfig` ends on COLLECT and never
	asks anybody to spend anything — but the reason outlived it: the first purchase a player makes is
	the one that has to be reachable off a single run, and a banked first run pays about $300. ]]
UpgradeConfig.Bay = {
	--[[ Off = the kiosks come off the podiums, nothing can be bought, and every bay earns at level 1
		(`bayMultiplier` answers 1, so levels already bought stop counting but are kept in the save).
		The lever to pull if the per-bay ladder ever needs taking out of the economy.

		=== OFF — 2026-09-28 =================================================================

		WHAT IT WAS. An orange board on every podium selling that bay's level: income per second while
		bays earned, then (from earlier the same day) the tip multiplier.

		WHAT IT IS. Pulled, on the owner's call: "we dont want to upgrade tips right now". Off used to
		leave the boards standing BLANK, which is a sign reading nothing in every aisle; it now takes
		them out of the world at runtime (`GarageService._discoverBays`) — the map still has them, so
		`true` brings every board back as it was. The one survivor is the workshop podium's board,
		which is the CUSTOMIZE sign and not an upgrade (`CustomizeConfig.Kiosk`). ]]
	Enabled = false,

	--[[ The profile key, inside the `Garage` table — see the note in `GarageConfig.Keys`.

		A MAP of bay index -> level with STRING keys, `{ ["1"] = 4 }`, and string-keyed for the same
		round-trip reason `Levels`, `Paints` and `Upgrades` are: a number-keyed table with a gap in it
		(bays 1 and 5 upgraded) comes back from the datastore as something else entirely.

		KEYED BY BAY, NOT BY CAR, and that is the modelling decision to argue with first if this ever
		feels wrong. A level is a property of the PODIUM: park a different car on it and the level
		stays, which is what makes "move my best car onto bay 3" a move worth making. The alternative
		— a level that follows the car — is a second car-upgrade system next to `RewardConfig`'s XP
		ladder, and one per car is enough.

		A level survives moving lots, because it is on the player's profile and a plot is only a seat
		for the session. Bays 7-12 exist only while `Floor2` is standing; their levels are kept
		regardless, so taking the storey away and buying it back does not cost anything bought. ]]
	ProfileKey = "BayLevels",

	MaxLevel = 100,
	BaseCost = 250,
	CostGrowth = 1.15,
	Step = 0.05,

	--[[ Instance names inside the authored kiosk. These and the model in the `CarSlot` source are the
		two halves of one contract: `BuildSlotUpgradeBoards` draws it, `PropagateCarSlots` copies it to
		every bay.

		    <CarSlot>/Upgrade/UpgradeBoard          -- the tilted panel
		      .UpgradeGui (SurfaceGui, Active)      -- Front face
		        .Panel                              -- the dark rim, and nothing else
		          .UpgradeButton                    -- the whole face, and the only control on it
		            .Cost                           -- headline: "$1.6B", or "MAX"
		            .Level                          -- "Lvl 24 > Lvl 25", or "Lvl 100"

		=== WHAT CAME OFF THIS BOARD ON 2026-08-21 ==============================================

		A title bar reading CASH PER SECOND, a `$/s` headline, a NEXT readout and a progress bar — six
		numbers, where the reference art on Aleafo's "Improve Upgrade UI" card has two. His note under
		it: "The UI is way too complicated and overwhelming."

		THE ONE THAT COST SOMETHING TO LOSE IS THE RATE. `$47/s` was the argument for having a per-bay
		ladder at all — see the header — because it is what let a player stand in their own showroom
		and work out that their next level belongs under their best car. It is not gone from the game,
		only off this sign: the mat this board stands on counts real money up in real time, and the HUD
		carries the lot's total. If that decision measurably stops being made, the rate is the thing to
		put back, and the space under the price is where it goes.

		THE PROGRESS BAR IS THE ONE WORTH ARGUING ABOUT THE OTHER WAY. It mattered less at 11 rungs
		than it would at 100, where `Lvl 24 > Lvl 25` says nothing about how far along that is. It came
		off anyway because the card's whole complaint is density and a bar is a fifth thing to read;
		the level number is a position on a ladder whose length is public.

		THERE IS NO TAG ON ANY OF THIS, unlike the forecourt billboard. It does not need one: the kiosk
		is a child of a `CarSlot`, the slots are already tagged, and `UpgradeController` reaches it
		through the tag the map already carries. One tag fewer to author, and a kiosk cannot go missing
		separately from the podium it stands on.

		THE BUTTON IS THE WHOLE FACE, which is what makes the sign readable at a glance: the plaque
		itself carries the state rather than a strip along the bottom of it. `Colors` below is what
		that state is now, and it is two words long. It also means `UpgradeController`'s press
		animation shrinks the board rather than a component of it. That is deliberate, and the reason
		the press is geometric rather than a recolour is unchanged. ]]
	ModelName = "Upgrade",
	BoardName = "UpgradeBoard",
	GuiName = "UpgradeGui",
	PanelName = "Panel",
	ButtonName = "UpgradeButton",
	CostName = "Cost",
	LevelName = "Level",

	--[[ The two lines, and what a maxed bay says instead of each.

		`LevelFormat` TAKES THE CURRENT LEVEL AND THE NEXT ONE, in that order, and the arrow between
		them is the whole reason this line beats the `LEVEL 4` it replaced: a price on its own says what
		a purchase costs and nothing about what it buys. `Lvl 24 > Lvl 25` is the smallest thing that
		answers both. A plain `>` and not an arrow glyph, because the sign is Ubuntu and a codepoint the
		font does not carry renders as a box on somebody else's device and nowhere on mine.

		A MAXED BAY DROPS THE ARROW RATHER THAN POINTING AT A LEVEL THAT DOES NOT EXIST, and its
		headline goes from a price to `MAX`. Both lines stay drawn: a blank top half reads as a sign
		that failed to load, which is the same mistake `EmptyFormat` used to exist to avoid — that one
		is gone with the rate it formatted, since a bay's ladder is a property of the PODIUM and reads
		the same whether or not there is a car standing on it. ]]
	LevelFormat = "Lvl %d > Lvl %d",
	MaxLevelFormat = "Lvl %d",

	--[[ === THE SIGN SAYS WHAT IT BUYS NOW — 2026-09-28 ======================================

		WHAT IT WAS. "Lvl 7 > Lvl 8" — enough while the bay's earnings were printed elsewhere (its mat,
		the HUD's $/s), so the player could watch a level land in a number.

		WHAT IT IS, without passive income (`GarageConfig.Income.Passive`). Nothing else on the lot
		prints what a bay is worth any more, and a level multiplies that bay's customer TIPS
		(`GarageService.getBayTip`), so the lower line names the multiplier itself: the one now and the
		one the press buys. Same `bayMultiplier` the tips are paid with, so the sign cannot promise a
		number the crowd does not pay. `%s` is the multiplier through `formatTipMultiplier`.

		The `Lvl` pair above is still what shows with passive income on. ]]
	TipsFormat = "TIPS ×%s > ×%s",
	TipsMaxFormat = "TIPS ×%s",
	MaxCostText = "MAX",

	--[[ THE PLAQUE IS ORANGE, AND ITS COLOUR IS THE WHOLE STATE READOUT.

		This is the kiosk's palette and `UpgradeConfig.Colors` is what is left of the billboard's.
		Two tables rather than one because the two boards are not the same kind of object: a
		billboard tile is a card in a 2x2 grid with a small button along its bottom, and the kiosk IS
		a button, the whole plaque, read at a glance from across a showroom. It is also a flat fill
		and not a `Pill`, because a pill is aspect-locked art and this face is 2.25:1.

		THE SENTENCE IS THE SAME ONE `ButtonPills` SPEAKS, and it went from three words to two on
		2026-08-26 for the reason written up in full there. The short version: the dim state used to
		mean "you cannot afford this yet", and since `CashService` arrived a press you cannot afford
		opens Roblox's window on a cash pack sized to the gap. A face that says "pressing me does
		nothing" in front of a press that does something is worth deleting, and the price is on the
		sign in dollars anyway.

		So orange is not a state, it is the sign: every kiosk in the game is this colour except a
		maxed one and an unowned one.

		#FFA200 IS THE KIT'S OWN `Orange` PILL FACE, taken from `assets/ui/pills/README.md` rather
		than picked, so the plaque and the billboard's button are the same orange to the byte.

		`Done` LEAVES THE ORANGE because it is the one state that is not a buy: a maxed bay has
		nothing to afford, so the affordance the orange face speaks does not apply to it. It is the
		kit money green now rather than the #FFC600 PLAY gold it wore before, and that swap was
		forced: gold sits 36 units of green away from #FFA200 and the two were indistinguishable on a
		plaque at showroom distance. Green also makes both boards agree, since the billboard has said
		green for maxed since its own rebuild.

		`Vacant` IS AN UNCLAIMED LOT and is a different sentence from either. It is derived and not
		eyeballed, through the same transform the old dim green went through:

		    Vacant = HSV(h, s * 0.72, v * 0.42)   -- of Buy

		which is the family the kit's own hover states use (`UIAssets.Pill`). Anything added here
		should go through it rather than be picked by hand, or it will read as a different sign
		instead of as the same sign unlit. A vacant plaque carries no text at all, so it wants to
		recede; leaving it full orange would have every empty bay on the island shouting a purchase
		nobody can make. ]]
	Colors = {
		Buy = Color3.fromRGB(255, 162, 0), -- #FFA200, the kit's Orange pill face
		Done = Color3.fromRGB(13, 180, 21), -- #0DB415, the kit money green
		Vacant = Color3.fromRGB(107, 79, 30), -- #6B4F1E, Buy at the dim transform above
	},
}

--[[ Seconds between one player's purchases. Same shape and the same reason as
	`GarageConfig.Picker.Cooldown`: the remote is a client caller and a Floor 2 unlock clones 53
	parts plus six podiums, so a mashed button is real server work. Well under the time the press
	animation takes, so nobody who is not scripting it can feel it. ]]
UpgradeConfig.PurchaseCooldown = 0.35

-- === The four upgrades ======================================================

--[[ `Order` is the grid, reading left to right then top to bottom — tile 1 is the top-left corner
	and tile 4 the bottom-right. Four because the sign has four corners; a fifth entry would need
	the command's layout maths changed, which is the honest place for that limit to live rather
	than a silent truncation here.

	IN PRICE ORDER, cheapest first, and that is the rule rather than a coincidence: the top-left tile
	is the one a player reads before they have decided to read anything, and the bottom-right is the
	one they read last. $2,500 to $1,000,000 across four corners, so the board is legible as a
	sentence about how far along you are.

	It costs the two LUCK tiles being stacked in one column, which would have read as a ladder. Price
	order won because a player who cannot afford the top-left tile can stop reading.

	=== WHAT CAME OFF THE BOARD ==============================================================

	This used to be `Income`, `Storage`, `AutoCollect`, `Floor2` — the four tycoon dials. Polish.md's
	upgrade list replaced three of them (`Floor2` survived and is what EXPAND BASE sells). The three
	that came off still work for anyone who bought them and are still in `Upgrades` below; note 6 in
	the header is the whole rule. `AutoCollect` has a second home waiting for it on the Robux list.

	`MythicalLuck` CAME OFF ON 2026-08-14 and `Jump` took its corner. That was a player ask (bug
	fixes.md, Drakeyym8) and Aleafo asked the right question about it on the spot — whether a jump
	upgrade replaces mythical luck or joins it — because a fifth entry is not free here: the grid has
	four corners and the command's layout maths is what enforces that. It replaces it. The board now
	sells one dial for the DEALERSHIP (`Floor2`), one for the SHOWROOM (`Customers`) and two for the
	RACE (`Luck` picks what is on the road, `Jump` decides what you can reach), which is a better
	spread than two tiles of the same stat at two exchange rates ever was.

	WHAT THAT COST, stated plainly because it is the one argument for the old tile: `MythicalLuck` was
	a $3.03B sink deliberately priced past world 4. Nothing on this board replaces it, and the two
	re-prices below took the rest of the far end away as well.

	=== JUMP AND EXPAND BASE SWAPPED CORNERS ON 2026-08-28 ===================================

	`Jump` inherited `MythicalLuck`'s corner AND its price, and the price was the half that did not
	belong to it. The one tile on the board a player feels on the very next run was also the last
	thing anybody could afford: $2M to open a ladder whose first level is +8% glide. Dylan's call, in
	as many words: switch it with EXPAND BASE, let JUMP be the casual buy, and put the money on
	EXPAND BASE instead.

	So the board reads LUCK / CUSTOMERS across the top and JUMP / EXPAND BASE underneath. `Jump` opens
	at $15,000 and maxes at $685K, about $1.1M for the whole ladder, which is roughly what the LUCK
	ladder above it costs. `Floor2` went from $250K to $1M and takes the bottom-right corner, which is
	where the one thing a player saves up for belongs.

	THE BILLBOARD IS NO LONGER A LATE-GAME SINK, and that is the honest cost of both moves: every tile
	on it together is under $5M, against $1.7B to max a single bay on the per-podium kiosk. The
	forecourt now sells the early curve and the podiums take the money after it. If the far end ever
	needs something again, the answer is a new tile with a new job, not one of these two put back at a
	price it was never written for. ]]
UpgradeConfig.Order = { "Luck", "Customers", "Jump", "Floor2" }

--[[ Every key this file has ever defined, board or retired, in a fixed order.

	`Order` cannot serve for this. It is the SHOP, and encoding off it would drop a retired ladder out
	of the broadcast the moment it left the board — so a client would read `Income` as level 0 on a
	profile that owns eight of them. Fixed order rather than `pairs` for the boring reason: the
	attribute is a string, and a string that reshuffles itself every join is a replication write and a
	changed-signal for nothing.

	Anything added to `Upgrades` belongs here too; a key that is in neither list is invisible to the
	client and nothing warns about it. ]]
UpgradeConfig.Keys = { "Luck", "Customers", "Floor2", "Jump", "MythicalLuck", "Income", "Storage", "AutoCollect", "Power" }

--[[ Each entry:

		Title       what the tile is called
		MaxLevel    the last level that can be bought
		BaseCost    what level 1 costs
		CostGrowth  the ratio between one level's price and the next
		Step        the per-level effect, read by the `*For` helpers at the bottom
		Headline    (level) -> the big number on the tile
		Detail      one line of static copy, so a tile says what it DOES and not only what it is at ]]
UpgradeConfig.Upgrades = {
	--[[ LUCK — better cars on the road, so there is something worth stealing.

		IT MULTIPLIES A TIER'S SPAWN WEIGHT BY WHERE THAT TIER SITS ON THE LADDER, not by a flat
		amount: `TrafficController._pickTier` scales each unlocked tier's weight by
		`luckFactor ^ ((rung - 1) / (rungs - 1))`, so the bottom car is untouched, the top car gets the
		whole factor, and everything between is smeared along the exponent. `+150%` on this tile is
		therefore literally "the top car's weight, plus 150%" and not a vibe.

		WHY AN EXPONENT ACROSS THE FULL LADDER AND NOT THE UNLOCKED POOL. A tier joins the pool at its
		`FromTile`, so 400 studs into a run only two cars exist. Normalised against the pool, luck would
		hand the whole factor to the SEDAN at tile 1 and be worth most in the first ten seconds of a
		race; normalised against the full ladder it is worth almost nothing there and everything at the
		top, which is the same shape as the rest of this game — drive further, get better cars. Luck
		steepens that curve, it does not skip it.

		EIGHT-CAR WORLD 1, MAXED, ALL TIERS UNLOCKED: the top car goes from 2.3% to 4.2% — 1 in 43 to
		1 in 24, measured, not estimated. That is a doubling and it is deliberately not more: this is
		the affordable ladder, and the one that reshapes the roster is the one below it that costs a
		thousand times as much.

		IT IS ROLLED ON THE CLIENT, because traffic is client-local (see `TrafficController`'s header
		and `NearMissConfig` on the same trust gap). A client that lies about its luck spawns itself
		better cars to steal; it already could, because it owns the roll outright. What bounds the
		damage is unchanged and is not here: a stolen car is only worth anything once it is BANKED, and
		banking goes through the server. ]]
	Luck = {
		Title = "LUCK",
		Detail = "Better cars on the road",
		MaxLevel = 10,
		BaseCost = 2500,
		CostGrowth = 1.9,
		--[[ 0.5 since 2026-10-14 (was 0.15; the owner: "upgrading luck doesn't seem to do much"). At 0.15
			World 1's two levels took a Legendary sighting from ~1 run in 17 to ~1 in 14, which nobody can
			feel. At 0.5 they make it ~1 in 10, and the full ten levels are x6 on the top car. ]]
		Step = 0.5,
		Headline = function(level: number): string
			--- Off `Step`, so the board can never disagree with what a level does.
			return string.format("+%d%%", math.round(level * UpgradeConfig.Upgrades.Luck.Step * 100))
		end,
	},

	--[[ CUSTOMERS — one more person in the showroom, tipping.

		THE ONLY UPGRADE HERE THAT WAS ALREADY WIRED. `CustomerConfig.countFor` has read a level off a
		key called `Customers` since the crowd was built, and answered 0 for it the whole time, because
		`levelOf` answers 0 for a key it has never heard of. Adding this entry is the entire feature —
		there is nothing to change in `CustomerService`.

		`MaxLevel` IS PINNED TO `CustomerConfig.Crowd`, not chosen: `countFor` clamps to `Crowd.Max`
		(6) over `Crowd.Base` (2), so four levels reach the ceiling exactly and a fifth would be a
		level that charges money and buys nothing. Raise `Crowd.Max` first if this ever wants a fifth.

		The cost curve is the steepest on the board (x3.2) over the fewest levels, which is what keeps
		a four-level ladder from being finished in a sitting: $5,000 to start and $163,840 for the last
		one, $236,040 for the lot. That was just under EXPAND BASE and is about a quarter of it since
		the 2026-08-28 re-price, so a full showroom is a step on the way to the second floor rather
		than the same decision twice. ]]
	Customers = {
		Title = "CUSTOMERS",
		Detail = "More browsers, more tips",
		MaxLevel = 4,
		BaseCost = 5000,
		CostGrowth = 3.2,
		Headline = function(level: number): string
			--[[ Required HERE rather than at the top of the file, and that is not laziness:
				`CustomerConfig` requires THIS module at its own top, so a top-level require back would
				be a cycle. By the time a headline is drawn the module is loaded and cached, so this is
				a table lookup.

				The alternative — hardcoding 2 — is a second copy of `Crowd.Base` on a board that would
				then quietly lie the day somebody tunes the crowd. ]]
			local CustomerConfig = require(script.Parent.CustomerConfig)
			return tostring(CustomerConfig.Crowd.Base + level)
		end,
	},

	--[[ JUMP — HISTORICAL ARC-SCALING NOTES, RETIRED BY THE PREDICTABILITY PASS.

		CURRENT BEHAVIOUR: every level enlarges air control, landing padding and prompt reach by 6%.
		It does not change launch height, airtime or longitudinal glide. The history below explains the
		old two-factor design and is retained so existing save/UI decisions still have context.

		IT SELLS THE SIGNATURE MECHANIC, which is what makes it the one tile on this board a player
		feels on the very next run rather than on the next hour of parked income. `StealConfig`'s arc
		is a pop and a hover — thrown up at `Launch.Up`, then braked along the road toward
		`Flight.Glide.Speed` for the whole descent — and a level multiplies both, so the leap hangs
		longer AND travels further relative to the traffic underneath it.

		=== THE TWO STEPS ARE NOT THE SAME SIZE ==================================================

		  • `Step` (+8% a level) SCALES THE GLIDE, and it is the one that buys REACH. `StealConfig`'s
		    header derives why: the brake settles you at 39 studs/s, a shade above mid-tier traffic, so
		    what closes a gap in the air is the difference between that and the TARGET's own speed. A
		    Tier 5 runs 39-44 — the same pace — which is exactly why a supercar has to be drawn roughly
		    level with before you jump today. Maxed, the glide is 54.6, and that difference becomes a
		    real ~+14 studs/s for the length of a descent. This is the upgrade.

		  • `AirStep` (+4% a level) SCALES THE LAUNCH, and it is deliberately half the size. Hang time
		    is capped by taste rather than by arithmetic: `Launch.Up` argues 2.0s is about the ceiling,
		    past which the player spends the mechanic watching instead of deciding, and `Flight.Reach`
		    (0.92s to cross at full steer) stops being the thing that limits a correction. +20% maxed
		    takes a flight from 1.86s to 2.26s — enough that a bigger jump reads as one, not so much
		    that the arc becomes a cutscene.

		WHAT THE WHOLE LADDER IS WORTH, stepped through the real integrator rather than estimated (a
		52 studs/s bail, no steering, net closing over a WHOLE flight against each tier's mid pace):

		    level 0   1.86s   80 studs of road    Tier 1 +29   Tier 3 +18   Tier 5  +3
		    level 5   2.26s  113 studs of road    Tier 1 +52   Tier 3 +39   Tier 5 +21

		The Tier 5 column is the one this ladder is tuned on. +3 studs is "you must already be level
		with it"; +21 is "you can take it from about a car length back" — a real change in what the top
		of the roster costs you, and still nowhere near being able to jump onto anything from anywhere.

		THE SAME TWO FLIGHTS FLOWN FOR REAL, back to back on one road at the same bail speed (79 and 80
		studs/s — note that is the CRUISE, half again what `StealConfig`'s header reasons from):

		    level 0   1.90s   109 studs   apex 28   braked to 40 studs/s
		    level 5   2.31s   151 studs   apex 38   braked to 55 studs/s

		+42 studs of road for +0.41s of air, which is the split those two steps are for. One thing that
		showed up only in the live pair and is worth knowing before it is reported as a bug: the maxed
		arc OVERSHOT the beater the unbought one landed on. That is the upgrade working — you close on
		everything faster, so the press comes earlier — and the ground marker is what says so, but it
		does mean a maxed player has to re-learn the timing on slow traffic.

		MORE AIR ALONE WOULD BUY ALMOST NOTHING, and that trap is the reason both steps exist: the
		extra second is flown at traffic pace, so a longer flight comes down on the same car it always
		did, having spent longer over the tarmac getting there. `StealConfig` learned this the hard way
		when the leap was lengthened (its header, `Launch.Up` 88 → 108) and had to move `Glide.Speed`
		with it. The two move together here as well — and here rather than in `StealConfig`, where
		either of them would be a permanent re-tune of the arc for everybody, bought or not.

		IT IS APPLIED ON THE CLIENT, like `Luck`, with the same trust gap: the arc is integrated in
		`StealController` on the machine that flies it. A client that lies about this reaches a car it
		should not have — and it already could, because it owns the arc outright, and a steal is
		already a claim the server cannot verify (`StealService`'s header). What bounds the damage is
		unchanged: a stolen car is worth nothing until it is BANKED, and banking goes through us.

		THE PRICE IS SET AGAINST A RUN, NOT AGAINST THE WORLDS. It was $2M at x4.5, inherited whole
		from `MythicalLuck` along with the corner, and that is the half of the swap nobody argued: it
		priced the one tile a player feels immediately behind everything else on the board. Since
		2026-08-28 it is $15,000 at x2.6, so the first level lands a couple of banked runs in, the
		fifth costs $685K, and the ladder is about $1.1M end to end. Five levels still, because the arc
		is tuned on five and the table above is what those five are worth.

		A CHEAPER LADDER IS NOT A BIGGER ONE, which is why the re-price is two numbers and nothing else
		in this block moved. What a level buys is bounded by taste and by `StealConfig` (the two
		bullets above), never by what it costs. See the swap note in `Order` for what the board gave
		up to make this the casual buy. ]]
	Jump = {
		Title = "JUMP",
		Detail = "More control and forgiveness",
		MaxLevel = 5,
		BaseCost = 15000,
		CostGrowth = 2.6,
		-- Per-level scale applied to prompt reach and lateral control, not to the ballistic arc. Keeping
		-- airtime and forward pace fixed means an upgrade never invalidates learned jump timing.
		Step = 0.06,
		--[[ 2026-10-20 ("increase the range, and also make it get more air time ... for more decision
			freedom"), so the arc DOES change with level now, on purpose and only at the top of it:
			`HangStep` softens `StealConfig.Flight.Hang`'s gravity per level (8% less a level, x0.60 maxed:
			the flight 2.6s to 3.5s, the throw unchanged), and `RangeStep` lengthens how far up the road
			the target lock looks (`StealConfig.Lock.Ahead`, 75 to 112 studs maxed). The timing you learn
			on the way up is the same at every level; the time you get at the top is what you buy. ]]
		HangStep = 0.08,
		RangeStep = 0.1,
		Headline = function(level: number): string
			return string.format("+%d%%", math.round(level * 6))
		end,
	},

	--[[ MYTHICAL LUCK — the same stat as `Luck`, an order of magnitude of it, and a price to match.

		RETIRED FROM THE BOARD 2026-08-14 — `Jump` has its corner; see the note in `Order` for the
		swap and what it cost. Still in force for every level anyone bought: `luckFactor` adds it in
		exactly as it did, and `TrafficController` neither knows nor cares that nothing sells it.
		Everything below this line is unchanged and describes what a level still does.

		IT IS A CURRENCY SINK FIRST AND AN UPGRADE SECOND, which is the honest way round to describe it.
		`luckFactor` adds the two ladders together and nothing distinguishes a point of luck bought here
		from a point bought above; what is different is the exchange rate. `Luck` buys 1.5x for $1.7M
		across ten levels. This buys 10x for $3.03B across five.

		THE PRICE IS SET AGAINST THE WORLDS, not against this board. `WorldConfig` sells the desert for
		$850K, world 3 for $33M and world 4 for $1.3B, so the top of the game already deals in billions
		and a sink that tops out under one of those would be finished before the content is. Three
		billion puts the last level a bit beyond world 4 — something to be spending on after the map
		has run out, which is the hole this fills.

		MAXED WITH `Luck` MAXED the factor is 12.5, and world 1's top car goes from 2.3% to 10.2% — 1
		in 43 to 1 in 10. What that does to the whole ladder is the interesting part and it is measured:
		the eight rungs land between 8% and 15%, so the road FLATTENS rather than inverting. The beater
		is still 1 in 12 and still turns up. That is the ceiling this was tuned to — the junk you trade
		up FROM has to stay on the road, or the steal stops being a decision.

		"MYTHICAL" IS A PRICE TAG, NOT A RARITY. There is no mythical band in `TrafficConfig.Bands` and
		this does not add one — it makes the existing top rungs common. If a real rarity above Supercar
		ever exists, this is the tile that should gate it, and that is a `Bands` change rather than one
		here. ]]
	MythicalLuck = {
		Title = "MYTHICAL LUCK",
		Detail = "LUCK, BY THE BILLION",
		MaxLevel = 5,
		BaseCost = 25000000,
		CostGrowth = 3,
		Step = 2,
		Headline = function(level: number): string
			return string.format("+%d%%", math.round(level * 200))
		end,
	},

	--[[ INCOME — every parked car earns more, everywhere, forever.

		RETIRED FROM THE BOARD 2026-08-09 — see note 6 in the header. Still in force for every level
		anyone bought; `GarageService.rateOf` reads it on every income calculation and does not know or
		care that nothing sells it. Everything below this line is unchanged and describes what a level
		still does.

		A FLAT MULTIPLIER OVER `GarageConfig.rateOf`, applied per player rather than baked into the
		ladder: `GarageConfig.Income.Multiplier` is the GLOBAL dial (the home of the 2x Cash
		gamepass) and this is the personal one, so the two compose instead of fighting.

		+15% a level, eight levels, so a fully upgraded lot earns 2.2x. Deliberately smaller than one
		rung of the car ladder (~1.69x per tier) — the run is supposed to be where the big jumps come
		from, and an income upgrade that out-earns stealing a better car would quietly turn the game
		into a menu. Eight levels because that is one per rung of world 1, which makes "a level of
		income or a better car?" a comparison a player can actually hold in their head.

		SALE PRICE IS DELIBERATELY NOT SCALED BY THIS. `GarageConfig.valueOf` stays flat, so this
		buys income and never a better refund; otherwise the duplicate-sale branch of banking would
		quietly become the fastest way to spend an income upgrade. ]]
	Income = {
		Title = "INCOME",
		Detail = "EVERY BAY EARNS MORE",
		MaxLevel = 8,
		BaseCost = 750,
		CostGrowth = 2.15,
		Step = 0.15,
		Headline = function(level: number): string
			return string.format("+%d%%", math.round(level * 15))
		end,
	},

	--[[ STORAGE — a bay holds more unclaimed cash before it stops counting.

		RETIRED FROM THE BOARD 2026-08-09 — see note 6 in the header. Still in force, and still read in
		two places that matter: `GarageService` caps banking with it and the WELCOME BACK panel prints
		the player's own ceiling off it (`OfflineService`), so a profile holding six levels still says
		8h on rejoin.

		It raises `GarageConfig.Income.MaxBankedSeconds` (2 hours) by half of it a level, six levels,
		to 8 hours. That number is the offline cap AND the online one — GarageConfig keeps them as one
		rule on purpose — so this is the "come back tomorrow" upgrade and the "go do a long run"
		upgrade at the same time, which is why it is the second thing offered rather than a late one.

		Its ceiling is 8 hours rather than infinity because the cap is also the only thing that makes
		collection a verb: with no cap there is never a reason to walk to a mat. Eight hours is a
		night's sleep, which is the longest gap the cap has to survive to stop feeling punishing. ]]
	Storage = {
		Title = "STORAGE",
		Detail = "BAYS HOLD MORE CASH",
		MaxLevel = 6,
		BaseCost = 1200,
		CostGrowth = 2.4,
		Step = 0.5,
		Headline = function(level: number): string
			-- Whole hours: the base is 2h and the step is 1h, so this never needs a fraction.
			return string.format("%dh", math.round(2 * (1 + level * 0.5)))
		end,
	},

	--[[ AUTO COLLECT — the lot pays itself out on a timer, with nobody standing on the mats.

		RETIRED FROM THE BOARD 2026-08-09 — see note 6 in the header. This is the one of the three with
		somewhere else to go: "Auto Collect" is on Polish.md's Monetization list, so the intended next
		move is a gamepass that writes a level here rather than a tile that sells one. Until then
		`UpgradeService._restartAutoCollect` still runs the sweep for anybody already holding a level.

		IT IS THE ONE UPGRADE THAT REMOVES A VERB, and that is worth being explicit about rather than
		discovering later: `GarageConfig.Collect` says walking your own showroom collecting from each
		car in turn is the thing the map was built for, and at level 5 you never have to again. It is
		here anyway because it is the archetypal tycoon purchase and because the verb it removes is
		the least interesting one in the game — but it is the LAST tile bought (nine thousand dollars
		to start, and the curve is the steepest of the four), so the walking is the whole early game
		and the robot is the reward for having outgrown it.

		THE FLOOR IS 25 SECONDS, NOT ZERO. A continuous drip would make `Storage` pointless (nothing
		would ever reach a cap it collects out of every frame) and would make the money arrive as a
		number that never visibly changes. A quarter-minute is short enough to feel automatic and long
		enough that a collection is still an event you can see land. ]]
	AutoCollect = {
		Title = "AUTO COLLECT",
		Detail = "THE LOT PAYS ITSELF",
		MaxLevel = 5,
		BaseCost = 9000,
		CostGrowth = 2.8,
		-- Seconds between sweeps, indexed by level. Index 1 is LEVEL 0 — off, and the only state
		-- where no timer runs at all.
		Intervals = { [0] = 0, 150, 105, 70, 45, 25 },
		Headline = function(level: number): string
			if level <= 0 then
				return "OFF"
			end
			return string.format("%ds", UpgradeConfig.Upgrades.AutoCollect.Intervals[level] or 0)
		end,
	},

	--[[ STEAL POWER (the 2026-11 collector rework) — the ⚡ number every roaming car is gated on.
		Level L is worth exactly the requirement of tier L+1, so each level unlocks one more car; the
		ladder and its prices live in `CollectorConfig.Power`, not here, because they are derived
		from the car value curve rather than tuned as a tile. Bought from the ⚡ button on the HUD,
		not the board (it is not in `Order`); `UpgradeService` lets it through when the collector is
		on. Required lazily, like `Customers.Headline`, so no config cycle can form. ]]
	Power = {
		Title = "STEAL POWER",
		Detail = "Steal rarer cars",
		MaxLevel = 49,
		BaseCost = 0, -- unused: `PriceOf` wins in `costOf`
		CostGrowth = 1,
		PriceOf = function(level: number): number?
			return require(script.Parent.CollectorConfig).powerCost(level)
		end,
		Headline = function(level: number): string
			return tostring(require(script.Parent.CollectorConfig).powerAt(level))
		end,
	},

	--[[ EXPAND BASE — the storey that is not in Workspace until it is paid for.

		THE KEY IS STILL `Floor2` AND MUST STAY THAT WAY. The tile was called SECOND FLOOR until
		2026-08-09 and is now called EXPAND BASE; only the caption changed. The key is what is written
		into the save file, so renaming it would hand every player who has already paid $250,000 a lot
		with one storey and no refund — the one migration on this board that is not worth having. The
		floor-building code (`UpgradeConfig.topFloor`, `UpgradeService._setFloor`) reads the key, and
		the copy below is what a player reads; the two are allowed to differ and this is why.

		ONE LEVEL, NOT A LADDER, because what it buys is a building and there is exactly one of them
		to build. `MaxLevel = 1` is what makes the tile read "UNLOCKED" instead of "MAXED" once it is
		owned, which is the difference between a purchase and a level.

		THE PRICE IS SET AGAINST WHAT IT PRODUCES, NOT AGAINST THE OTHER THREE. It doubles the lot
		from six bays to twelve, so it should cost roughly what a full lot earns in the time a player
		would accept spending on one goal.

		IT WENT FROM $250,000 TO $1,000,000 ON 2026-08-28, when it took the bottom-right corner from
		`Jump`. A mid-game six-bay lot runs around 150/s, so $250K was under half an hour of parked
		income: the right size for the tile a player reads third, and far too small for the one they
		read last. $1M is a couple of hours of that same lot, less once bay levels are on it, and it is
		now the only thing on this board worth saving for. It is still the cheapest doubling in the
		game, because the six bays it opens earn it back inside a session of owning them.

		IF IT BITES, LOWER THIS NUMBER. The failure it would cause is not a player who cannot afford
		the storey, it is a player who fills six bays and stops, because the next goal is out of sight.
		That is one line to move, and never a prerequisite to add.

		NOTHING GATES IT. No prerequisite level, no minimum lot — the price is the gate, and a second
		gate on top of a 250,000 one is a rule nobody would ever meet the far side of. ]]
	Floor2 = {
		Title = "EXPAND BASE",
		Detail = "Unlock 6 more bays upstairs",
		MaxLevel = 1,
		BaseCost = 1000000,
		CostGrowth = 1,
		Headline = function(level: number): string
			--[[ IT READ "6 BAYS" UNTIL 2026-08-28, which is the count the lot already has: the big line
				on the tile stated the status quo while the small line under it advertised the purchase.
				It now says what is being bought, and `Detail` is still what that gets you.

				NOT "SECOND FLOOR", and that is measured rather than taste. At the board's shared type
				ceiling the string is 693px wide in a 666px box, so `TextScaled` breaks it over two
				lines and halves it to fit, which is the one thing the shared scale exists to prevent.
				"2ND FLOOR" is 510px and holds the ceiling. ]]
			return if level >= 1 then "12 BAYS" else "2ND FLOOR"
		end,
	},
}

-- === Asking about a level ===================================================
--[[ Every function below takes the raw `Upgrades` table straight off a profile — which may be nil,
	may be a string, and may hold levels for keys that no longer exist — and answers for a REAL
	level rather than erroring. That is the same sanitising contract `WorldConfig.resolve` sets, and
	for the same reason: the callers are a remote handler, a replicated attribute and a UI, and all
	three can be handed nonsense by something that is not lying, just stale. ]]

--- Anything -> the stored level of `key`, clamped into 0 .. MaxLevel.
function UpgradeConfig.levelOf(upgrades: unknown, key: string): number
	local spec = UpgradeConfig.Upgrades[key]
	if not spec or type(upgrades) ~= "table" then
		return 0
	end
	local level = tonumber((upgrades :: any)[key])
	if not level or level ~= level or level % 1 ~= 0 then
		return 0
	end
	return math.clamp(level, 0, spec.MaxLevel)
end

--- What the NEXT level of `key` costs, or nil when there is no next level.
function UpgradeConfig.costOf(key: string, level: number): number?
	local spec = UpgradeConfig.Upgrades[key]
	if not spec or level >= spec.MaxLevel then
		return nil
	end
	-- `level` is how many are already owned, so level 0 pays `BaseCost` for the first one.
	if spec.PriceOf then
		return spec.PriceOf(level)
	end
	return if spec.Prices then spec.Prices[level + 1] else math.round(spec.BaseCost * spec.CostGrowth ^ level)
end

--- Is `key` an upgrade this file knows about, on sale or retired? Reading, not buying.
function UpgradeConfig.isKey(key: unknown): boolean
	return type(key) == "string" and UpgradeConfig.Upgrades[key] ~= nil
end

--[[ Is `key` one of the four currently on the board? THE gate on the purchase remote, and the gate
	on binding a tile.

	NOT `isKey`, and the difference is the point: `Upgrades` still holds three retired ladders (header
	note 6), and a client that remembers the old board — or one that read this file — could otherwise
	post `AutoCollect` at the remote and buy a tile that is not for sale. Nothing about that is
	profitable, they pay the full price out of their own balance, but "you can buy what is on the
	board" should be true because it is enforced and not because the UI happens not to offer it. ]]
function UpgradeConfig.isOnBoard(key: unknown): boolean
	return type(key) == "string" and table.find(UpgradeConfig.Order, key) ~= nil
end

-- === What a level BUYS ======================================================
--[[ The four accessors the rest of the game reads. They take the profile table rather than a
	player, so `GarageService` can answer with data it already has in hand and needs no dependency
	on `UpgradeService` at all — which is what keeps the two services acyclic. ]]

--- Multiplier over every parked car's dollars per second. 1.0 at level 0.
function UpgradeConfig.incomeMultiplier(upgrades: unknown): number
	return 1 + UpgradeConfig.levelOf(upgrades, "Income") * UpgradeConfig.Upgrades.Income.Step
end

--- How long a bay banks before it stops counting, given the config's base. Seconds.
function UpgradeConfig.bankSeconds(upgrades: unknown, baseSeconds: number): number
	return baseSeconds * (1 + UpgradeConfig.levelOf(upgrades, "Storage") * UpgradeConfig.Upgrades.Storage.Step)
end

--- Seconds between automatic sweeps of the lot, or nil while the upgrade is not owned.
function UpgradeConfig.autoCollectInterval(upgrades: unknown): number?
	local level = UpgradeConfig.levelOf(upgrades, "AutoCollect")
	local interval = level > 0 and UpgradeConfig.Upgrades.AutoCollect.Intervals[level]
	return if interval and interval > 0 then interval else nil
end

--- The highest storey this player's dealership should have standing. 1 or 2.
function UpgradeConfig.topFloor(upgrades: unknown): number
	return if UpgradeConfig.levelOf(upgrades, "Floor2") >= 1 then 2 else 1
end

--[[ WHAT THE LUCKY ROADS PASS IS WORTH, in the same units as the `Luck` and `MythicalLuck` ladders
	in `Upgrades` above: one flat term in `luckFactor`, added and not multiplied, for the reason
	that function gives.

	2.5 IS "MORE THAN THE WHOLE AFFORDABLE LADDER" and it was chosen against that ladder rather than
	picked. `Luck` maxed is +1.5 and costs about $1.7M; this is +2.5 and costs Robux, which is the
	trade every pass in this game makes. Measured on world 1 with every rung unlocked: the top car
	goes from 1 in 43 to 1 in 19 for someone who owns the pass and nothing else, against 1 in 24 for
	someone who maxed `Luck` and bought no pass.

	IT IS WORTH LESS TO A MAXED ACCOUNT ON PURPOSE, and that is the additive shape doing its job: on
	top of 12.5 it moves the top car from 1 in 10 to 1 in 9. A multiplicative pass would have been
	1 in 7 for that account and only 1 in 27 for the new player who is the one that actually buys
	passes, which is backwards. Nothing about luck multiplies, here or anywhere.

	THE PASS IS ROLLED ON THE CLIENT, exactly as `Luck` is, and `Luck`'s block has the whole argument
	for why that is survivable. Nothing changes by selling it: a client that lies about its luck
	could already spawn itself better cars before any of this was for sale, and what bounds the
	damage is still `GarageService.awardCar` refusing a tier that disagrees with the body. Worth
	knowing that this is now a PAID advantage sitting on that gap, and that the server-rolled spawn
	token `GarageService` names is what would close it. ]]
UpgradeConfig.LuckyRoadsStep = 2.5

--[[ How much heavier the TOP rung of a traffic ladder rolls for this player. 1.0 with no bonuses.

	ONE NUMBER OUT OF TWO LADDERS, A PASS AND INDEX CLAIMS, added rather than multiplied, and that is
	the whole relationship between them: they are the same stat earned at different exchange rates,
	so a point is a point wherever it came from. Only one of the two ladders is still for sale (`Jump` took the mythical
	tile on 2026-08-14) and this reads both regardless, which is the whole of what "retired" means
	here — the second term is 0 for everyone who never bought one and unchanged for everyone who did. Multiplying them would make the cheap ladder retroactively worth
	ten times more the moment the expensive one was touched, which is the sort of curve nobody can
	hold in their head — the same argument `Income` and `Bay` make for staying additive.

	Maxed on both: 1 + 1.5 + 10 = 12.5. With the LUCKY ROADS pass on top of that, 15.

	`TrafficController._pickTier` is the only consumer, and it does NOT apply this flat — see `Luck`
	for the exponent and why it is spread across the ladder rather than handed to whatever is
	unlocked. Anything else that ever wants "how lucky is this player" should call this rather than
	read the individual sources, so there is one answer. ]]
function UpgradeConfig.luckFactor(upgrades: unknown, luckyRoads: unknown, indexClaims: unknown): number
	return 1
		+ UpgradeConfig.levelOf(upgrades, "Luck") * UpgradeConfig.Upgrades.Luck.Step
		+ UpgradeConfig.levelOf(upgrades, "MythicalLuck") * UpgradeConfig.Upgrades.MythicalLuck.Step
		--- `== true` and not a truthiness test, because the caller reads this off an ATTRIBUTE and
		--- an attribute holds whatever was last written to it. Same contract as `levelOf` above:
		--- anything in, a real answer out.
		+ (if luckyRoads == true then UpgradeConfig.LuckyRoadsStep else 0)
		+ IndexRewardConfig.bonusFor(indexClaims)
end

--[[ LEGACY arc accessors. Both intentionally return 1 at every level so old readers remain valid
	without allowing progression to change the trajectory. `jumpForgivenessFactor` is the live dial.

	TWO NUMBERS AND NOT ONE, because the arc has two halves that are bought at different rates — see
	`Jump` for why the air is half the size of the glide, and for the reason a single "jump further"
	dial would have been a lie. `StealController` multiplies `Launch.Up` by the first and
	`Flight.Glide.Speed` by the second, and the ground marker inherits both for free, because it finds
	the touchdown by running that same integrator forward rather than by solving an arc of its own.

	`Flight.Reach` IS SOMETHING ELSE and neither of these touches it: that is the cross-road cap on how
	far you may drift from the lane you bailed in, and it is a statement about the road being three
	lanes wide rather than about how big a jump is. ]]
function UpgradeConfig.jumpAirFactor(upgrades: unknown): number
	return 1
end

function UpgradeConfig.jumpGlideFactor(upgrades: unknown): number
	return 1
end

-- The replacement payload for the jump upgrade: a larger correction/capture envelope while the
-- authored trajectory stays identical at every progression level.
function UpgradeConfig.jumpForgivenessFactor(upgrades: unknown): number
	return 1 + UpgradeConfig.levelOf(upgrades, "Jump") * UpgradeConfig.Upgrades.Jump.Step
end

--- The jump upgrade's air time: a multiplier on `StealConfig.Flight.Hang`'s gravity scales. 1 unbought,
--- lower is floatier; floored so no level can stall the arc (`Jump.HangStep`).
function UpgradeConfig.jumpHangFactor(upgrades: unknown): number
	return math.max(0.3, 1 - UpgradeConfig.levelOf(upgrades, "Jump") * UpgradeConfig.Upgrades.Jump.HangStep)
end

--- ...and its lock range: a multiplier on `StealConfig.Lock.Ahead` (`Jump.RangeStep`).
function UpgradeConfig.jumpRangeFactor(upgrades: unknown): number
	return 1 + UpgradeConfig.levelOf(upgrades, "Jump") * UpgradeConfig.Upgrades.Jump.RangeStep
end

-- === Asking about a bay's level =============================================
--[[ The same sanitising contract as the four above — anything in, a real level out — and the same
	reason for it. The extra wrinkle here is that the floor is 1 rather than 0 (see `Bay.ProfileKey`),
	so "absent", "nonsense" and "level 1" are all the same answer and no profile needs migrating. ]]

--- Anything -> the stored level of bay `index`, clamped into 1 .. Bay.MaxLevel.
function UpgradeConfig.bayLevelOf(levels: unknown, index: unknown): number
	local bay = tonumber(index)
	if type(levels) ~= "table" or not bay or bay ~= bay then
		return 1
	end
	--[[ Looked up by STRING key, because that is the shape the datastore hands back — a table
		written with `[1]` and round-tripped comes home with `["1"]`. Both are tried so a table that
		has not been through a save yet reads the same as one that has. ]]
	local raw = (levels :: any)[tostring(bay)]
	if raw == nil then
		raw = (levels :: any)[bay]
	end
	local level = tonumber(raw)
	if not level or level ~= level or level % 1 ~= 0 then
		return 1
	end
	return math.clamp(level, 1, UpgradeConfig.Bay.MaxLevel)
end

--- What the NEXT level of a bay costs, or nil when it is already maxed.
function UpgradeConfig.bayCostOf(level: number): number?
	if level >= UpgradeConfig.Bay.MaxLevel then
		return nil
	end
	-- Level 1 is the free one every bay starts on, so it pays `BaseCost` for the first upgrade.
	return math.round(UpgradeConfig.Bay.BaseCost * UpgradeConfig.Bay.CostGrowth ^ (level - 1))
end

--- Multiplier over this one bay's dollars per second. 1.0 at level 1.
function UpgradeConfig.bayMultiplier(level: number): number
	--- Switched off, every bay is level 1 whatever was bought: the ladder is out of the economy, not
	--- just off the signs. See `Bay.Enabled`.
	if not UpgradeConfig.Bay.Enabled then
		return 1
	end
	return 1 + (math.max(level, 1) - 1) * UpgradeConfig.Bay.Step
end

--[[ A bay multiplier as the kiosk prints it: "1.30", "5.95". TWO DECIMALS ALWAYS, because a level is
	worth `Bay.Step` (0.05) and one decimal would print 1.30 and 1.35 as the same "1.3" — a sign whose
	before and after read identically is the exact complaint `GarageConfig.formatRate` was written to
	fix. ]]
function UpgradeConfig.formatTipMultiplier(multiplier: number): string
	return string.format("%.2f", multiplier)
end

-- === Writing to the board ===================================================

--[[ U+00A0, and every space that reaches a label on this board is one.

	IT IS NOT COSMETIC AND IT IS NOT OPTIONAL. Every label on the sign is `TextScaled`, and TextScaled
	maximises text size subject to the laid-out text fitting its box — which means it will WRAP to a
	second line in preference to shrinking. On a tile this shape "AUTO COLLECT" and "6 BAYS" both
	break in half and read as a layout bug. Roblox only breaks lines at spaces, so a caption with no
	breakable space leaves shrinking as its only move.

	The two obvious fixes were measured on the dealership sign and neither works: `TextWrapped =
	false` silently clears `TextScaled` and drops the label to the default TextSize of 8, and a
	`UITextSizeConstraint` MinTextSize above the wrap threshold does nothing because the wrap happens
	first. See `PlotConfig.SignNonBreakingSpace`, which is the same rule for the same reason. ]]
UpgradeConfig.NonBreakingSpace = utf8.char(0x00A0)

function UpgradeConfig.oneLine(text: string): string
	return (string.gsub(text, " ", UpgradeConfig.NonBreakingSpace))
end

-- === Broadcasting ===========================================================

--[[ Encode for `UpgradeConfig.Attribute`. Only levels above 0 appear — see the note there.

	OVER `Keys` AND NOT `Order`: a retired ladder is still in force and a client still has to be able
	to read it. Encoding the shop would have quietly zeroed `Income` on every profile that owns it the
	day it left the board. ]]
function UpgradeConfig.encode(upgrades: unknown): string
	local parts = {}
	for _, key in UpgradeConfig.Keys do
		local level = UpgradeConfig.levelOf(upgrades, key)
		if level > 0 then
			table.insert(parts, string.format("%s:%d", key, level))
		end
	end
	return table.concat(parts, ",")
end

--- The other half of `encode`, for a client that wants the levels without a remote.
function UpgradeConfig.decode(text: unknown): { [string]: number }
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	for key, level in string.gmatch(text, "(%w+):(%d+)") do
		if UpgradeConfig.Upgrades[key] then
			out[key] = tonumber(level)
		end
	end
	return out
end

-- Approved economy balance, 2026-10-04.
local Balance = require(script.Parent.BalanceConfig)
for key, prices in Balance.UpgradePrices do
 UpgradeConfig.Upgrades[key].Prices = prices
 UpgradeConfig.Upgrades[key].RequiredWorlds = Balance.UpgradeWorlds[key]
 UpgradeConfig.Upgrades[key].BaseCost = prices[1]
end
--- 2026-10-20: the jump now also buys air time and lock range (`jumpHangFactor`, `jumpRangeFactor`).
UpgradeConfig.Upgrades.Jump.Detail = "More air time and lock range"
function UpgradeConfig.requiredWorldOf(key: string, level: number): number
 local spec = UpgradeConfig.Upgrades[key]
 return if spec and spec.RequiredWorlds then spec.RequiredWorlds[level + 1] or 1 else 1
end


--[[ THE UPGRADE MOMENT (2026-10-07, the polish pass). Buying an upgrade took the money and changed a
	number on a board, and that was the whole beat — spending felt like losing. Now a purchase is a
	celebration on the spot that changed: over the BAY for a bay's kiosk, at the buyer's feet for a lot
	upgrade bought at the board. Everyone on the lot sees it.

	=== "VERY BLAND", SO IT IS A SHOW NOW — 2026-10-07 =======================================
	The first cut was a gold UPGRADED! that floated off with a puff of sparkles. NOW, drawn on every
	client (`UpgradeCelebrationController`; the server only drops a tagged marker, `UpgradeService.
	_celebrate`), in this order over about two seconds:

	    0.00  a gold light pulses up over the spot and dies away              (`Light`)
	    0.00  a shockwave ring races out across the floor, a second behind it  (`Wave`)
	    0.00  a fountain of sparkles shoots straight up, and a burst sprays out (`Fountain`, `Burst`)
	    0.05  UPGRADED! slams in — overshooting, tilted, settling — in a gold gradient with a thick navy
	          stroke, a sunburst turning behind it and a LEVEL N pill under it  (`Banner`)
	    1.4   the banner floats up and fades
	    and the buyer alone hears `Sound` (`SoundService.<Group>.<Name>`; missing = silent).

	`Enabled = false`: purchases as before, with nothing drawn. ]]
UpgradeConfig.Celebrate = {
	Enabled = true,
	--- The marker's CollectionService tag, the contract between `UpgradeService` and the controller.
	Tag = "UpgradeCelebration",
	Seconds = 2.2,
	Title = "UPGRADED!",
	LevelFormat = "LEVEL %d",
	Gold = Color3.fromRGB(255, 214, 60),
	Orange = Color3.fromRGB(255, 140, 20),
	Light = { Brightness = 8, Range = 26 },
	Wave = { Radius = 16, Seconds = 0.6, Count = 2, Gap = 0.14 },
	Fountain = { Count = 45, Speed = { 28, 46 } },
	Burst = { Count = 60 },
	--- Studs: the banner's size, how high over the spot it sits, and how far it floats at the end.
	Banner = { Width = 10, Height = 5, Above = 6, Rise = 3.5, Hold = 1.4 },
	Sound = { Group = "Upgrade", Name = "Upgraded" },
}

-- Expansion keeps the original downstairs crowd and adds a dedicated upstairs pair.
UpgradeConfig.Upgrades.Floor2.Detail = "6 more bays + 2 upstairs visitors"
return UpgradeConfig


