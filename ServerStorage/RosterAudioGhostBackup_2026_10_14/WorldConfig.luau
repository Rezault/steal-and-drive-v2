--[[
	WorldConfig: five worlds with ten independent car rungs each.
	Order approved in the Place1 review on 2026-10-09. Each car owns its own rarity,
	value and stats; former traffic variants are now independent rungs.
	Global tiers are 1-50. Removed bodies remain resolvable for existing ownership
	through LegacyBodies, but are excluded from all traffic and dealer pools.
]]

local WorldConfig = {}

-- === The maps ===============================================================
--[[ `Workspace.Worlds` holds one folder per themed road, and inside it the tiles that road is
	built from, named `1`, `2`, `3`... Each tile is one `SegmentLength` of road, and they are
	VARIANTS of each other, not a fixed sequence: any tile of a world can follow any other, so a
	world with six tiles is six ways the same stretch of road can look.

	WHAT A TILE IS. Every tile carries the same contract the streaming road already reads off the
	default map — `SegmentLength`, `ForwardAxis`, `DriveCenterX`, `DriveWidth`, and a
	`Gameplay/OriginMarker` PrimaryPart sitting on the deck at the tile's entry end, which is the
	pivot everything else is measured from. `ServerStorage.CommandRunnerScripts.NormalizeRoadSegments`
	is what puts that contract on a tile, and its `Segment` module is where the whole thing is
	written down; run it after importing anything new rather than hand-fitting a tile.

	ONE ATTRIBUTE IS NEW AND MATTERS HERE: `DriveCenterOffset`, the lane centre measured FROM THE
	PIVOT rather than in absolute world X. `DriveCenterX` only stays true while a tile is streamed
	at the X it happens to be parked at in the place file, and two of these worlds are parked
	straight through the lobby (Arctic sits at X 2067, Desert at 1236, and the lobby spans
	1286..2779 at exactly this height). So the road cannot be built where its tiles are authored —
	it has to be built at a fixed race origin with the tiles moved to it, and the offset is what
	survives that move. The default map is already streamed this way: its tiles live at X -349,
	nowhere near where the City art was authored.

	THESE TILES ARE A GREYBOX. The modeller handed over one built stretch — what is now `City/1`,
	the map the game currently ships — and then four themed passes at the same road so the rest of
	the game could be built against something before the real worlds exist. They WILL be replaced.
	That is exactly why the binding below is a folder NAME and the contract lives on the tiles:
	when a finished world lands, it goes in the folder, the command re-runs over it, and nothing
	in this file or downstream of it changes.

	The maps are art, not code: nothing here validates that a named folder exists, because a
	missing one should read as an empty road in a playtest, not as the config failing to load.

	`Workspace.Worlds.FuturisticCity` GOT ITS LADDER ON 2026-08-28 and is world 5 below, which is
	the fifth appended exactly the way the note that used to sit here said it would be: rungs are
	global, so appending at the end left tiers 1-29 where they were and cost no migration. Its four
	tiles carry the same normalised contract the other maps do (checked: `SegmentLength`
	1172.796, `DriveCenterOffset` -15.426, `DriveWidth` 77.79, an `OriginMarker` PrimaryPart and the
	`WorldRoadSegment` tag on all four), so nothing had to be re-run over them. ]]
WorldConfig.RoadFolderName = "Worlds"
-- CollectionService tag on every authored world tile. NOT `RaceConfig.RoadSegmentTag` — that one
-- belongs to the live seeded road in `Workspace.RoadSegments`, and RoadService both picks its
-- template and stashes Workspace by it, so a world tile wearing it would be picked at random.
WorldConfig.TileTag = "WorldRoadSegment"

-- === The worlds =============================================================
--[[ Ordered worst-to-best, left-to-right from the front (note 1). `Name` is a placeholder until
	the worlds are themed; nothing displays it yet.

	Editing a list re-prices and re-orders everything downstream and needs no other change. Moving a
	car BETWEEN worlds shifts every rung after it, which is fine before launch and a migration after
	it (a saved car is stored by body name, and its tier is looked up here on load).

	`Display` OVERRIDES WHAT THE SCREEN CALLS IT, and is optional. The card prints the world's MAP
	by default, because "DESERT" tells a player where they are going and "World 2" tells them
	nothing (`displayName`) — but a map folder is an Explorer name and is allowed to be one word.
	`FuturisticCity` is, and would set as "FUTURISTICCITY". So the override is a place to put the
	name a HUMAN would write without renaming the folder every downstream lookup keys off
	(`UIAssets.Worlds`, `MusicConfig.Worlds`, `ObstacleConfig.Courses`, `PoliceConfig.Sections`).
	It is a caption and nothing else: no code may branch on it.

	`Unlock` IS WHAT IT COSTS TO GET IN, and a world without one is free forever (world 1, and any
	world you want opened during a playtest — deleting the table is the whole switch).

	  • `Cost` is cash, spent once and kept. Priced off the income curve so the gate is worth the
	    same number of MINUTES at every world: `GarageConfig` pays 78/s for the top car of world 1
	    and multiplies by 39 each world, six bays to a lot, and each price below is ~30 minutes of a
	    full lot of the previous world's best car. World 2 lands at about one full collection cycle
	    for a mid-world-1 lot, which is the "save up once" this is meant to feel like.

	  • `RequirePrevious` is a FRACTION of the previous world's road (note 6) you must have driven
	    before the price is even offered — 1 meaning 100%, the point past which that world has
	    nothing new to show. It is a number and not a boolean so that softening the gate to 0.9 is
	    an edit here and not a code change, which matters because the denominator it is measured
	    against is tuning (`TrafficConfig.topTileFor`) and is expected to move.

	    World 2 deliberately has none: the first world you can buy is a pure cash sink, so a player
	    meets the idea of paying for a world before they meet the idea of qualifying for one.

	CHECKED WHEN YOU BUY, NEVER AFTER. Both halves are a condition of the PURCHASE; owning a world
	is a fact about the player from then on. That is what keeps a retune of the traffic bands — which
	moves everybody's percentage — from taking back a world somebody already paid for. ]]
WorldConfig.Worlds = {
	{
		Name = "World 1",
		Map = "City",
		Cars = {
			"Civic",
			"Golf GTI",
			"GNX",
			"Camaro",
			"Charger",
			"EVO",
			"Challenger",
			"Mustang",
			"Maybach",
			"M5",
		},
		Variants = {},
	},
	{
		Name = "World 2",
		Map = "Desert",
		Unlock = { ["Cost"] = 100000 },
		Cars = {
			"EVO 10",
			"WRX STI",
			"F&F EVO",
			"RX7",
			"350Z",
			"MK5 Supra",
			"Skyline R34",
			"RX7 F&F",
			"C7",
			"GT",
		},
		Variants = {},
	},
	{
		Name = "World 3",
		Map = "Forest Mountains",
		Short = "Mountains",
		Unlock = { ["RequirePrevious"] = 1, ["Cost"] = 8000000 },
		Cars = {
			"BRZ/FRS/GT86",
			"S15",
			"Supra MK4",
			"M4",
			"NewSports14",
			"NewSports02",
			"i8",
			"NewSports06",
			"M600",
			"F40",
		},
		Variants = {},
	},
	{
		Name = "World 4",
		Map = "Arctic",
		Unlock = { ["RequirePrevious"] = 1, ["Cost"] = 130000000 },
		Cars = {
			"190E",
			"C63 AMG",
			"Pantera GT5",
			"NewSports23",
			"NewSports18",
			"NewSports13",
			"918",
			"F1 LM",
			"Sian",
			"F5",
		},
		Variants = {},
	},
	{
		Name = "World 5",
		Map = "FuturisticCity",
		Display = "Futuristic City",
		Unlock = { ["RequirePrevious"] = 1, ["Cost"] = 1700000000 },
		Cars = {
			"DeLorean",
			"Roadster 2.0",
			"NewSports34",
			"720S",
			"NewSports04",
			"Gemera",
			"Huyara BC",
			"NewSports11",
			"Senna",
			"Jesko Attack",
		},
		Variants = {},
	},
}

-- === Being in a world =======================================================
--[[ WHICH WORLD A PLAYER IS IN LIVES ON THE PLAYER, as an attribute, exactly like cash and
	ownership: `WorldService` owns the value and writes it, everything else reads it and nobody
	sends a remote to ask. That is what makes a world per player at all — the road is client-built
	and driving is solo, so two players in one server can be on two different roads with nothing
	to reconcile, and the only thing that has to agree is this number.

	Absent means "hasn't chosen", which reads as `ActiveIndex` below. Never treat a missing
	attribute as an error: it is the state every player is in for the first second of their
	session, before the profile has loaded. ]]
WorldConfig.WorldAttribute = "World"

--[[ Where the chosen world is KEPT, as a key in the player's profile (`Settings.TEMPLATE`). The
	attribute above is the broadcast of this, exactly the way `Cash` is — one is what the client
	reads, this is the copy that was never on a client.

	It persists because the alternative is worse than it sounds: a player who has been driving the
	desert all evening rejoins into the city, presses Play out of habit, and the game has silently
	moved them. Which world you are in is a place, and a place is somewhere you come back to. ]]
WorldConfig.ProfileKey = "World"

-- === How far you have got down each road ====================================
--[[ A PERSONAL BEST PER WORLD, which is the only progress a player makes through a MAP as opposed
	to through its car ladder. `WorldService` owns both halves; `RewardService` hands it a run's
	distance when the run settles.

	THE PROFILE KEEPS STUDS, THE ATTRIBUTE CARRIES A PERCENTAGE, and that split is the point. Studs
	are what was measured and they never go stale; the percentage is studs divided by
	`TrafficConfig.topTileFor` (the tile past which a world has nothing new to show) times the road's
	`SegmentLength` — two things that are TUNING and are expected to move. Storing the fraction would
	freeze every existing save on the ladder it was set against; storing the studs means a retune
	re-derives everybody's percentage the next time it is published, exactly as `Garage.Levels` keeps
	XP and derives the level.

	It is also why the client is sent the fraction rather than working it out: the segment length is
	a property of the authored road, which the server has in hand (`RoadService.getSegmentLength`)
	and a UI page does not.

	`Maps` is a MAP with STRING keys — `{ ["1"] = 48210 }` — for the datastore reason `BayLevels`
	gives: a number-keyed table with a gap in it (worlds 1 and 3 driven, 2 not) round-trips through
	JSON as something the code that wrote it does not recognise. ]]
WorldConfig.ProgressKey = "Maps"
WorldConfig.ProgressAttribute = "MapProgress"

-- === Earning a world ========================================================
--[[ WHICH WORLDS YOU HAVE BOUGHT IS ONE NUMBER: the highest world you own, so 2 means "worlds 1
	and 2". Same profile/attribute split as everything else here — `WorldService` owns both writes,
	the profile is the truth and the attribute is what the card reads.

	A NUMBER AND NOT A SET, because the ladder is a ladder. You cannot meet world 4's requirement
	without having driven world 3, and you cannot drive world 3 without owning it, so the set of
	worlds a player owns is always 1..N — and a single number makes the one broken state that shape
	allows (owning 4 but not 3) impossible to write down rather than merely unlikely. It is also why
	nothing has to migrate when a world is appended: every existing profile already answers "1".

	If a world is ever buyable OUT OF ORDER — a bonus map, a Robux world — this is the line that
	changes, to the comma-separated string treatment `ProgressAttribute` already gets. Everything
	downstream asks `isUnlocked` and would not notice.

	Missing means 1, which is a fresh player and every profile written before this existed. ]]
WorldConfig.UnlockProfileKey = "WorldsUnlocked"
WorldConfig.UnlockAttribute = "WorldsUnlocked"

--[[ Seconds between one player's unlock attempts, matching `UpgradeConfig.PurchaseCooldown` in both
	value and reason: the remote has a client caller, and a mashed button should cost one answer
	rather than one per frame. Well under the two-press confirm the screen puts in front of it. ]]
WorldConfig.PurchaseCooldown = 0.35

--[[ What the buyer hears when a world purchase goes through (punch list A2, 2026-10-12, Aleafo: "need
	an sfx when you buy a new world"). `WorldService` fires `WorldBought` to that one client after the
	unlock is stored, and `WorldController` plays this through `SoundController:PlayNamed`.

	`Group` is a SoundGroup under SoundService and `Name` a Sound in it; both are authored in the place,
	as every SoundController group is. PlayNamed cannot seek, so the clip must start on frame one. A
	missing Sound is silence, not an error. An admin grant (`WorldService.setUnlocked`) is not a
	purchase and plays nothing. ]]
WorldConfig.UnlockSound = { Group = "World", Name = "Unlocked" }

--[[ How far short of a requirement still counts as meeting it. ONE QUANTUM of the stored fraction,
	and it is load-bearing rather than a fudge.

	`encodeProgress` writes four decimals and `recordDistance` floors the studs behind them, so a
	player standing exactly on the top tile of a road reads back 0.9999 — the last stud is rounded
	away before the screen ever sees it. Without this, "100%" would be a number a run can miss by an
	error of the config's own making, that the player cannot see (the screen prints 100%) and could
	not fix if they could (there is no further tile to drive to). Measured on the desert: 10 tiles of
	1172.8 studs is 11,728, the floor costs 1 stud, and 1 stud is 8.5e-5 of the road — inside this.

	ONE AND A HALF QUANTA, not one. The extra half is not slack, it is clearance: neither 0.9999 nor
	1e-4 is exact in binary, so an epsilon of exactly one quantum leaves the comparison landing on
	whichever side the rounding falls. Sizing it to the MIDPOINT between two adjacent stored values
	means the answer is decided by which quantum the player is on and never by the arithmetic. It is
	still far too small to turn 99.98% into a pass, which is the thing it must not do. ]]
WorldConfig.ProgressEpsilon = 1.5e-4

--[[ `{ [world] = { fraction, studs } }` <-> `"1:0.62:48210,3:0.14:9800"`. A world nobody has driven
	is simply absent from the string; there is no zero entry to keep in step.

	FOUR DECIMALS ON THE FRACTION, which is a tenth of a percent — finer than anything the screen can
	draw and short enough that all four worlds fit in a few dozen characters. Studs are floored: they
	are a distance in a game that measures them in thousands. ]]
function WorldConfig.encodeProgress(progress: { [number]: { fraction: number, studs: number } }): string
	local parts = {}
	for index = 1, #WorldConfig.Worlds do
		local entry = progress[index]
		if entry then
			table.insert(parts, string.format("%d:%.4f:%d", index, entry.fraction, math.floor(entry.studs)))
		end
	end
	return table.concat(parts, ",")
end

--- The other direction. Anything unparseable is skipped rather than fatal — this is read by a UI
--- off a replicated attribute, and a screen that errors is worse than one that reads 0%.
function WorldConfig.decodeProgress(raw: unknown): { [number]: { fraction: number, studs: number } }
	local progress = {}
	if type(raw) ~= "string" then
		return progress
	end
	for entry in string.gmatch(raw, "[^,]+") do
		local index, fraction, studs = string.match(entry, "^(%d+):([%d%.]+):(%d+)$")
		local world = tonumber(index)
		if world and WorldConfig.Worlds[world] then
			progress[world] = {
				fraction = math.clamp(tonumber(fraction) or 0, 0, 1),
				studs = tonumber(studs) or 0,
			}
		end
	end
	return progress
end

--[[ The world-select screen's end of it, all three halves named here so neither side hard-codes a
	string the other has to match.

	`PageName` is the screen itself — the module under `UIController/Pages` and the Frame under
	`MainUI.Pages`, which have to agree. It is named here rather than only in the place file because
	the HUD's Play button opens it (`RaceConfig.PlayOpensWorldSelect`): choosing a world is now the
	first half of starting a run, so the flow has to be able to say which screen that is. Still
	called "Teleport" in the Explorer, and renaming it is an edit here plus a rename there.

	`TeleportAction` is the `Action` attribute on a card's PLAY button — the house pattern from
	`Components/Button`: the button publishes the action on Dispatcher and `WorldController`
	subscribes, so the place file decides which button plays a world and the code decides what that
	means. The card itself carries `WorldAttribute` (above) naming the world it stands for, which is
	how one handler serves however many cards there turn out to be. The name is historical — the
	press used to only move you — and is left alone because it is authored on three cards in the
	place; what it does now is "play this world".

	`StateEvent` is the other direction: WorldController publishes it whenever anything the cards
	are drawn from changes (the chosen world, or whether a race is on). The page redraws off that
	rather than polling, and nothing else needs to know either fact. ]]
WorldConfig.PageName = "Teleport"
WorldConfig.TeleportAction = "TeleportToWorld"
WorldConfig.StateEvent = "WorldState"

--[[ The default world — what an unchosen player gets, and what anything holding no player has to
	assume (the config tables below, a system starting before anyone joins).

	It used to mean "the one live world" and it no longer does. If you are reading `Active*` and
	you have a player in hand, you are reading the wrong thing: use the `*For(index)` accessors
	with `WorldService:worldOf(player)`. The `Active*` fields are kept because pricing, the garage
	and the shop legitimately have no player-specific answer. ]]
WorldConfig.ActiveIndex = 1

--[[ The rung the run STARTS on, as an index into the active world's list (not a global tier).

	1 of 8 — the bottom of whichever ladder you are on: the Civic in the city, the EVO in the
	desert. Every run opens in that world's beater and every car on its road is an upgrade on it,
	so the climb starts at the first steal instead of halfway up.

	IT WAS 4 (the Charger), and that was an argument rather than an accident, so here is what
	moving it costs. "Stealing a beater genuinely costs you top speed" only bites while there is
	something below you, and traffic is drawn from this same ladder (`TrafficConfig.BodiesByWorld`)
	— at rung 1 there is nothing below, so every steal is sideways or up. And rung 4's speed (39.2)
	was the one nearest the 40 that every number in `DriveConfig` was tuned against, so the opening
	stretch now reads ~14% slower than that baseline (the Civic's 34.4 against the Charger's 39.2)
	for the ten-odd seconds before the first steal. Both are undone by setting this back to 4;
	nothing else has to change either way.

	`RaceConfig.CarTemplateName` and `StartBody` below are derived from this, and `startBodyFor`
	clamps it per world. ]]
WorldConfig.StartRung = 1

-- === Derived ================================================================
--[[ Everything below is built at load from the lists above, on the same principle as
	`TrafficConfig.Bodies` and `GarageConfig.Income.PerTier`: the roster is edited in exactly one
	place and nothing can disagree with it. ]]

-- The active world's table. Falls back to world 1 rather than erroring: a bad `ActiveIndex` should
-- cost you the world you meant, not the game.
WorldConfig.Active = WorldConfig.Worlds[WorldConfig.ActiveIndex] or WorldConfig.Worlds[1]

--[[ Global tier of the first rung of each world, minus one — i.e. how many cars sit below it.
	World 1 = 0, world 2 = 8, world 3 = 15, world 4 = 22. See note 3. ]]
WorldConfig.RungOffset = {}
do
	local offset = 0
	for index, world in WorldConfig.Worlds do
		WorldConfig.RungOffset[index] = offset
		offset += #world.Cars
	end
	-- Every car in every world, i.e. the highest tier the game will ever price. 29 today.
	WorldConfig.TotalRungs = offset
end

-- Global tier of a car by name, across ALL worlds — what `GarageConfig.TierOfBody` is built from.
WorldConfig.TierOfBody = {}
-- Which world a car belongs to, by name. Unused at runtime; here because "why is this car worth
-- that?" is a question with a one-lookup answer and shouldn't need a scan.
WorldConfig.WorldOfBody = {}
do
	for index, world in WorldConfig.Worlds do
		for rung, body in world.Cars do
			WorldConfig.TierOfBody[body] = WorldConfig.RungOffset[index] + rung
			WorldConfig.WorldOfBody[body] = index
		end
	end
end

--[[ === Variants: more than one car on a rung ================================================

	Note 8. `Variants` names the extra bodies; this is where they become real. Each is registered at
	its rung's GLOBAL TIER, which is the whole of what a variant is: `TierOfBody` prices it, the
	garage banks it, the steal pays for it and the collection screen gives it a slot, all without a
	single one of them learning that variants exist.

	IT RUNS AFTER THE LADDER LOOP ABOVE AND MUST. By this point `TierOfBody` holds every rung car in
	every world, which is what lets the check below catch a variant that is already somebody's rung —
	the one mistake in this table that would be genuinely bad, because a body with two tiers is a car
	the garage prices differently depending on which loop wrote last.

	`BodiesOfRung` is the list `TrafficConfig` builds a tier's `Bodies` out of, ladder car first. A
	rung with no variants is a one-entry list rather than nil, so the consumer has no branch. ]]
WorldConfig.VariantOfBody = {} -- a variant body -> the ladder car whose rung it shares
WorldConfig.BodiesOfRung = {} -- [world][rung] -> { ladder car, variant... }
do
	for index, world in WorldConfig.Worlds do
		local variants = world.Variants or {}
		local rungs = {}
		for _, body in world.Cars do
			rungs[body] = true
		end

		--- Warn, never fail — the same rule the rest of the config layer follows. A ladder that
		--- carries one bad variant should reach a playtest loud, not refuse to load.
		for primary in variants do
			if not rungs[primary] then
				warn(string.format(
					"[WorldConfig] world %d lists variants under '%s', which is not on its ladder; they will never spawn.",
					index,
					tostring(primary)
				))
			end
		end

		local byRung = {}
		for rung, body in world.Cars do
			local bodies = { body }
			for _, extra in variants[body] or {} do
				if WorldConfig.TierOfBody[extra] then
					warn(string.format(
						"[WorldConfig] '%s' is claimed twice (already tier %d); a car may sit on exactly one rung. Ignored.",
						tostring(extra),
						WorldConfig.TierOfBody[extra]
					))
				else
					table.insert(bodies, extra)
					WorldConfig.TierOfBody[extra] = WorldConfig.RungOffset[index] + rung
					WorldConfig.WorldOfBody[extra] = index
					WorldConfig.VariantOfBody[extra] = body
				end
			end
			byRung[rung] = bodies
		end
		WorldConfig.BodiesOfRung[index] = byRung
	end
end

-- Removed from spawning, retained as separate owned bodies and visual shells.
-- This maps pricing/world/rank without changing saved body names, IDs, paint or XP.
WorldConfig.LegacyBodies = { ["Model 3"] = "EVO", ["M3 GTR"] = "M4", ["SUPRA MK4"] = "Supra MK4" }
for body, replacement in WorldConfig.LegacyBodies do
	assert(WorldConfig.TierOfBody[replacement], "Missing legacy replacement: " .. replacement)
	WorldConfig.TierOfBody[body] = WorldConfig.TierOfBody[replacement]
	WorldConfig.WorldOfBody[body] = WorldConfig.WorldOfBody[replacement]
	WorldConfig.VariantOfBody[body] = replacement -- deterministic tier-stat resolution
end

-- The road the live world is driven on: a folder name under `Workspace.RoadFolderName`, or nil for
-- a world that has not been given one. Nil is a real answer, not an error — a ladder with no map
-- yet is the normal state for three of the four worlds below.
WorldConfig.ActiveMap = WorldConfig.Active.Map

-- The active world's cars, and the global tier of each — the two things every consumer wants.
WorldConfig.ActiveCars = WorldConfig.Active.Cars
WorldConfig.ActiveFirstTier = WorldConfig.RungOffset[WorldConfig.ActiveIndex] + 1
WorldConfig.ActiveLastTier = WorldConfig.ActiveFirstTier + #WorldConfig.ActiveCars - 1

-- The body the run starts in. Clamped, because `StartRung` is hand-edited and a world can shrink.
WorldConfig.StartBody = WorldConfig.ActiveCars[math.clamp(WorldConfig.StartRung, 1, #WorldConfig.ActiveCars)]

-- === Asking about a world by index ==========================================
--[[ The `Active*` fields above, but for whichever world a given player is in. Every one of these
	takes an index that may be anything — nil, a string off an attribute, 97 — and answers for a
	REAL world rather than erroring, because the callers are a remote handler, a replicated
	attribute and a UI, and all three can be handed nonsense by something that is not lying, just
	stale. `resolve` is where that sanitising happens exactly once. ]]

--- Anything -> a world index that exists. Nil, junk and out-of-range all become the default.
function WorldConfig.resolve(value: unknown): number
	local index = tonumber(value)
	if not index or index ~= index or index % 1 ~= 0 or not WorldConfig.Worlds[index] then
		return WorldConfig.ActiveIndex
	end
	return index
end

function WorldConfig.get(index: unknown)
	return WorldConfig.Worlds[WorldConfig.resolve(index)]
end

--- The world's car ladder, worst to best. ONE NAME PER RUNG — a rung's variants are not in here,
--- because every caller of this counts it or indexes it as the ladder. See `bodiesOfRung`.
function WorldConfig.carsFor(index: unknown): { string }
	return WorldConfig.get(index).Cars
end

--- Every body that wears a given rung, its ladder car first. Never nil; a rung with no variants
--- answers a one-entry list, and a rung that does not exist answers an empty one.
function WorldConfig.bodiesOfRung(index: unknown, rung: unknown): { string }
	local byRung = WorldConfig.BodiesOfRung[WorldConfig.resolve(index)]
	local list = byRung and type(rung) == "number" and byRung[rung]
	return list or {}
end

--- Global tier of the world's bottom car (world 2 starts at 9 — note 3).
function WorldConfig.firstTierFor(index: unknown): number
	return WorldConfig.RungOffset[WorldConfig.resolve(index)] + 1
end

--- The road folder under `Workspace.Worlds` this world is driven on, or nil for a ladder with no
--- map yet. Nil is a real answer — see "The maps".
function WorldConfig.mapFor(index: unknown): string?
	return WorldConfig.get(index).Map
end

--- The body a run in this world starts in (`StartRung` of its ladder, clamped).
function WorldConfig.startBodyFor(index: unknown): string
	local cars = WorldConfig.carsFor(index)
	return cars[math.clamp(WorldConfig.StartRung, 1, #cars)]
end

--[[ What the teleport screen prints on the card. The map name, because "DESERT" tells a player
	where they are going and "World 2" tells them nothing; `Name` is the fallback for a ladder with
	no map.

	`Display` WINS OVER BOTH when a world carries one, which is the one thing here that is purely a
	caption — see "The worlds". It exists because a map folder is an Explorer name and `FuturisticCity`
	is one word; every LOOKUP still keys off `Map`, so overriding what it is called cannot move which
	road, which music or which obstacle set a world gets. ]]
function WorldConfig.displayName(index: unknown): string
	local world = WorldConfig.get(index)
	return world.Display or world.Map or world.Name
end

--[[ The same name for a surface too narrow to take the real one.

	"Forest Mountains" is sixteen characters, and the world-select card has one place it has to fit:
	the button on a LOCKED card, which names the road you have to finish first. At the size that
	button is drawn, the full name sets at about 13px next to PLAY's 21px on the card beside it — one
	string long enough to make a row of four buttons look like four different designs. "Mountains"
	sets at the same size as every other label there.

	IT IS NOT A RENAME. `displayName` is still the world's name and is still what the card's own
	title, the analytics dimension, the weather notice and every server log say; this is only for the
	handful of places where the full name would have to shrink to fit, and it falls back to the full
	name for the three worlds that never needed a short one. ]]
function WorldConfig.shortName(index: unknown): string
	return WorldConfig.get(index).Short or WorldConfig.displayName(index)
end

--[[ What this world costs to unlock, or nil for one that is free (world 1, and anything whose
	`Unlock` table has been deleted for a playtest). ]]
function WorldConfig.costOf(index: unknown): number?
	local unlock = WorldConfig.get(index).Unlock
	local cost = unlock and unlock.Cost
	return if type(cost) == "number" and cost > 0 then cost else nil
end

--[[ How much of the PREVIOUS world's road you must have driven before this one is offered, as a
	fraction, or nil for a world that asks nothing (world 1 and world 2). Never returns a
	requirement for world 1, which has no previous world to demand. ]]
function WorldConfig.requiredProgressFor(index: unknown): number?
	if WorldConfig.resolve(index) <= 1 then
		return nil
	end
	local unlock = WorldConfig.get(index).Unlock
	local required = unlock and unlock.RequirePrevious
	return if type(required) == "number" and required > 0 then math.min(required, 1) else nil
end

--[[ How far this player has got down world `index`'s road, 0..1, read off the replicated
	attribute. Zero for a world they have never driven AND for one that cannot be scored yet — see
	`WorldService._publishProgress`, which is the only thing that can tell those apart and does not
	need to here: neither one has earned anything. ]]
function WorldConfig.progressOf(player: Player?, index: unknown): number
	if not player then
		return 0
	end
	local entry = WorldConfig.decodeProgress(player:GetAttribute(WorldConfig.ProgressAttribute))[WorldConfig.resolve(index)]
	return if entry then entry.fraction else 0
end

--- The highest world this player owns, so everything at or below it is theirs. Always at least 1:
--- world 1 is free, and an unwritten attribute is the state every player is in on join.
function WorldConfig.highestUnlocked(player: Player?): number
	local highest = tonumber(player and player:GetAttribute(WorldConfig.UnlockAttribute))
	if not highest or highest ~= highest then
		return 1
	end
	return math.clamp(math.floor(highest), 1, #WorldConfig.Worlds)
end

--[[ Can this player go to this world?

	OWNERSHIP ONLY. A world with no price is open to everyone, and a world with one is open to
	whoever has bought it — what it TOOK to buy (the cash, the previous map) was a condition of the
	purchase and is not re-asked here, so retuning either one cannot take back a world somebody
	already owns. `WorldService` is the only thing that may treat this as permission; the UI calls
	it to decide whether to grey a card out, and a greyed card is not a lock. ]]
function WorldConfig.isUnlocked(index: unknown, player: Player?): boolean
	if not WorldConfig.costOf(index) then
		return true
	end
	return WorldConfig.resolve(index) <= WorldConfig.highestUnlocked(player)
end

--[[ Everything the world-select card needs to know about one world, in one call, so the screen and
	the server's purchase guard cannot disagree about what is being offered.

	`state` is one of:
	  • "open"    — owned (or free). The card plays.
	  • "needs"   — the previous world is not finished. `progress`/`required` say how far off.
	  • "buy"     — eligible; `cost` is the price and `affordable` whether it can be met now.

	Takes cash as an argument rather than reading it, because the attribute it lives on belongs to
	`GarageConfig` and this file has no business knowing that name — the server passes the profile's
	balance, the client passes what it can see, and both get the same answer for the same number. ]]
function WorldConfig.unlockStateFor(index: unknown, player: Player?, cash: number?): (string, { [string]: any })
	local world = WorldConfig.resolve(index)
	local highest = WorldConfig.highestUnlocked(player)
	local cost = WorldConfig.costOf(world)
	if not cost or world <= highest then
		return "open", {}
	end

	--[[ WORLDS ARE BOUGHT IN ORDER, and this is the line that makes that true rather than merely
		likely. What is stored is the TOP of a prefix, so selling world 4 to somebody who never
		bought world 3 would hand them world 3 as well — free. Today's config cannot reach that
		(world 4 demands 100% of a road you would have to own to drive), but the invariant belongs
		next to the number it protects, not in the tuning that currently implies it.

		`required or 1` is the honest reading for a skipped world: owning the one before it is
		itself the requirement, so the card asks for all of it. ]]
	local required = WorldConfig.requiredProgressFor(world)
	local skipped = world > highest + 1
	if skipped or required then
		local progress = WorldConfig.progressOf(player, world - 1)
		if skipped or progress + WorldConfig.ProgressEpsilon < required then
			return "needs", {
				required = required or 1,
				progress = progress,
				previous = world - 1,
				previousName = WorldConfig.displayName(world - 1),
				--- For the world-select button, which cannot fit every world's full name. See
				--- `WorldConfig.shortName`.
				previousShort = WorldConfig.shortName(world - 1),
			}
		end
	end

	return "buy", { cost = cost, affordable = (cash or 0) >= cost }
end

--[[ Resample a hand-tuned curve onto `count` rungs, piecewise-linear (note 4).

	`points` is the authored curve — the five tier bands as they were tuned — and the result always
	starts at `points[1]` and ends at `points[#points]`, so the ends of the ladder keep the exact
	values a human chose for them and only the steps between are interpolated.

	Returns `{ points[1] }` for a single rung: a one-car world gets the bottom of the curve, not
	the top, because the alternative is a world whose only car is a supercar. ]]
function WorldConfig.resample(points: { number }, count: number): { number }
	if count <= 1 or #points == 0 then
		return { points[1] or 0 }
	end
	if #points == 1 then
		local flat = table.create(count, points[1])
		return flat
	end

	local out = table.create(count)
	for index = 1, count do
		-- Position along the authored curve in "band space", 1 .. #points.
		local at = 1 + (index - 1) / (count - 1) * (#points - 1)
		local lower = math.clamp(math.floor(at), 1, #points - 1)
		out[index] = points[lower] + (points[lower + 1] - points[lower]) * (at - lower)
	end
	return out
end

-- Approved economy balance, 2026-10-04.
local Balance = require(script.Parent.BalanceConfig)
WorldConfig.MapCompletionTiles = 8
for index, world in WorldConfig.Worlds do
 if index > 1 then
  world.Unlock.Cost = Balance.WorldCosts[index]
  world.Unlock.RequirePrevious = if index >= 3 then 1 else nil
 end
end

return WorldConfig
