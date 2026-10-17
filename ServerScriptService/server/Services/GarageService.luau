--[[
	GarageService  (server)
	-----------------------
	The meta game. A car you got away with is parked on a bay of your dealership plot, that bay owes
	you money for every second it stands there, and walking onto the mat in front of it pays out.

	=== MOST OF THAT FIRST PARAGRAPH IS THE FLAGGED-OFF MODE NOW — 2026-09-28 ================

	The dealership rework changed three things this file owns, each behind a flag that restores the
	old behaviour exactly:

	  • CARS ARE PLACED, NOT PARKED (`GarageConfig.Banking.AutoPark`, `SellDuplicates`). A bank goes to
	    the Cars Inventory under its own car ID (`GarageConfig.carId`), duplicates included, and the
	    player chooses what stands on the lot.
	  • A BAY EARNS NOTHING (`GarageConfig.Income.Passive`). `_collect` is gated, the mats are hidden
	    (`_hideMats`), the loops are not started. The dealership's income is `CustomerService`'s tips,
	    priced by `getBayTip`, and "NOTHING ACCUMULATES" below is still true — there is simply nothing
	    left to accumulate.
	  • A CAR HAS STATE OF ITS OWN (`Garage.CarData`, `NotForSale`): the condition it banked in, and
	    whether buyers may make offers on it.
	  • ONE BAY IS A WORKSHOP (`CustomizeConfig.Enabled`): that podium draws no tips, takes no buyers
	    and sells no tip levels, and a car on it can be repaired, repainted (`repaintCar`, which
	    re-keys it) and fitted with parts. See "The workshop" below.

	The rest of this header describes the passive-income design as it was built, and is exactly what
	`Income.Passive = true` brings back.

	It is the economy `PlotService` deliberately does not own. That one answers "which lot is this
	player's?" and nothing more; this one is the only thing in the game that writes `Cash`.

	=== THE ONE IDEA WORTH READING BEFORE ANYTHING ELSE ========================================

	NOTHING ACCUMULATES. There is no income tick adding to a counter anywhere in this file. A parked
	car stores a single number — the `os.time()` it was last collected — and what it owes is a
	function of the clock:

	    pending = min(now - collectedAt, MaxBankedSeconds) * rate(tier) * Multiplier

	Everything else falls out of that, and it is worth spelling out what it buys, because a service
	written the obvious way would need all of it:

	  • OFFLINE INCOME IS NOT A FEATURE HERE. It is what the formula already says. There is no
	    "catch up on login" pass, because there is nothing to catch up.
	  • NOTHING HAS TO BE FLUSHED. A player who crashes, disconnects mid-collection or is in the
	    server when it shuts down loses nothing, because the pending amount was never state.
	  • THE LOOP IS COSMETIC. `_labelLoop` redraws the numbers on the mats. Delete it and the money
	    is still exactly right; the mats just stop counting up in front of you.

	The only writes to the profile are the ones a player caused: collecting, banking a car, selling
	one. That is a handful per minute rather than one per second per bay.

	=== WHAT THE MAP OWNS ======================================================================

	Bays are AUTHORED, not built (`docs/MapLayout.md` §4, propagated by the `PropagateCarSlots`
	command). This service walks each plot's `CarSlots` folder, reads the `SlotIndex` the podium
	already carries, and fills in the mat's label. It never places a podium and never assumes six.

	The one thing it does build is the CAR on the podium, and that is a stripped clone rather than a
	vehicle: `Workspace.CarSystem.<Body>` is a 311-instance CarBones rig, and six of those on six
	plots is eleven thousand instances of fully-wired car standing still. Only the `Body` dress is
	cloned, its joints are destroyed and its parts are anchored. See `_buildDisplayCar` — the joint
	destruction in particular is load-bearing, not tidiness.

	=== WHAT IT TRUSTS =========================================================================

	`awardCar` is reached from `GetawayService`, i.e. from a client message. Traffic is client-sided,
	so there is no car on the server to check a bank against — the accepted gap `StealService`,
	`TrafficService` and `ObstacleService` all document, and the same server-rolled spawn token
	closes all four. What this service does add is a REAL constraint the others could not: the body
	name and the tier have to agree with `GarageConfig.TierOfBody`, which is the server's own copy of
	the roster. A client can still lie about which car it stole; it can no longer claim a Tier 5
	payout for a hatchback, and it cannot bank a car it never stole at all, because a car that was
	never stolen carries no `Tier` attribute for the client to send.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
--[[ The pending PLACEMENT a banked car now becomes, and the one profile key in the `Garage` table
	whose name is not written in `GarageConfig.Keys`. A CONFIG and not the service, for the reason
	`InventoryConfig` and `UpgradeConfig` are required here rather than their services: what is
	needed is a rule about a profile this file already owns every read and write of. `CarryService`
	owns the model in the player's hands and nothing about the record. ]]
local CarryConfig = require(ReplicatedStorage.shared.Configs.CarryConfig)
--[[ The Cars Inventory's half of the collection: the catalogue that never shrinks, the two flags,
	and what selling is allowed to do. A CONFIG and not a service, exactly like `UpgradeConfig`
	below — there is no inventory service, because everything it needs is a rule about a profile this
	file already owns every read and write of. ]]
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
--[[ For `ProfileKey` alone: where buyers' offers live in the `Garage` table this file owns. A CONFIG
	and not `BuyerService`, which depends on this one — the same acyclic split as `CarryConfig`. ]]
local BuyerConfig = require(ReplicatedStorage.shared.Configs.BuyerConfig)
-- What one car is worth, condition included. Pure and shared, so the price a client draws and the
-- price this file pays are one function; see its header for why it is not `GarageConfig.valueOf`.
local MarketValueConfig = require(ReplicatedStorage.shared.Configs.MarketValueConfig)
--[[ Which podium is the workshop, and the parts broadcast. A CONFIG and not `WorkshopService`, which
	depends on this one for every write it makes — the `BuyerConfig` split again. ]]
local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
--- The podium prompts are drawn as one glass card; the server only tags and attributes them.
local GlassPromptConfig = require(ReplicatedStorage.shared.Configs.GlassPromptConfig)
--- Only for the boot check that every rostered car has a game name. See `start`.
local CarNameConfig = require(ReplicatedStorage.shared.Configs.CarNameConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
--[[ A CONFIG, NOT THE SERVICE. `UpgradeService` owns buying an upgrade and the world-side effects
	of owning one; what this file needs is only "what is a level worth", which is a pure function of
	a table it already reads out of the profile. Requiring the config instead of the service is what
	keeps the two acyclic — UpgradeService depends on this one for cash, and nothing depends back. ]]
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
--- The CONFIG and not `CustomerService`, which depends on this service: only `tipScaleOf` is read.
local CustomerConfig = require(ReplicatedStorage.shared.Configs.CustomerConfig)
local CarInfoTag = require(ReplicatedStorage.shared.Modules.CarInfoTag)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
--[[ Building a car nobody drives, shared with `CarDealService`'s parking bays. It carries the
	weld-stripping, the box measurement and the yaw fit; what stays in this file is the part that is
	about a BAY. See `_buildDisplayCar`. ]]
local CarDisplay = require(ReplicatedStorage.shared.Modules.CarDisplay)
local CarMutation = require(ReplicatedStorage.shared.Modules.CarMutation)
--- The podium glow's colour and band (`GarageConfig.PodiumGlow`).
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local Data = require(script.Parent.Parent.Data)
local PlayerProfile = require(script.Parent.Parent.Data.Components.PlayerProfile)

-- One authored podium, resolved once at discovery so the paint path is straight-line property
-- writes and a malformed slot is one startup warning rather than a silent no-op per collection.
type Bay = {
	index: number,
	model: Model,
	deck: BasePart, -- the top platform the car stands on
	base: BasePart, -- the base slab; its LookVector points down the aisle at the mat
	button: BasePart?,
	label: TextLabel?,
	kiosk: Kiosk?, -- the CASH PER SECOND sign on the mat; nil if this podium was authored without one
}

-- The labels inside one bay's kiosk. Every field is optional for the same reason the billboard's
-- are: a podium half-authored by an older run of `PropagateCarSlots` should light up whatever it has
-- rather than erroring on the first missing label. The failure mode of a sign is a blank sign.
type Kiosk = {
	button: TextButton?,
	cost: TextLabel?,
	level: TextLabel?,
	--- The workshop sign's KIT face (`BuildWorkshopSign`), drawn beside the classic one; nil on every
	--- other podium and on a board built before it. Which face shows is the client's call.
	kit: {
		content: GuiObject,
		labels: { TextLabel }, -- each carries `CustomizeConfig.Kiosk.KitTextAttribute`
	}?,
}

type Car = {
	Body: string,
	Tier: number,
	--[[ The palette index this copy wears — part of what the car IS, not decoration. Two entries
		with the same `Body` and different `Paint` are two different cars; see `GarageConfig.Banking`.
		nil only on an entry written before that was true, and filled in on read; see `_cars`. ]]
	Paint: number?,
	--[[ The weather that was on this car when it was stolen (`WeatherConfig`), or nil for an ordinary
		one — which is nearly all of them, and is also every entry written before the weather existed.
		Part of what the car IS, like `Paint`, and the reason two entries with the same body and
		colour can earn different amounts: it multiplies the bay's income and therefore the sale
		price. See `GarageConfig.Banking` and `GarageConfig.rateOf`. ]]
	Mutation: string?,
	Collected: number,
	Bay: number?, -- nil only on an entry written before the player could choose; see `_cars`
	--[[ The ID of the owned car standing here (`GarageConfig.carId`). nil on an entry written before
		IDs existed, which is read as the entry's own key — the ID that car has always had. Go through
		`_entryId` rather than reading this, so that fallback lives in one place. ]]
	Id: string?,
}

local GarageService = Shard.new("GarageService"):withDependencies({ "PlotService" })

GarageService:withSignals({
	"CarParked", -- (player: Player, body: string, tier: number, bay: number)
	--- (player: Player, body: string, tier: number, amount: number, source: string). `source`
	--- (2026-10-15, for analytics) is "Buyer", "Lot", "Full" (banked into a full inventory) or "Duplicate".
	"CarSold",
	"CashCollected", -- (player: Player, amount: number, bay: number)

	--[[ (player: Player, keys: { string }, amount: number) — cars the player chose to sell out of the
		Cars Inventory have left the collection. Fired once per request, after every write and every
		broadcast, so a subscriber reading the profile sees the sale already done.

		IT IS NOT `CarSold` WITH A LIST. That one is fired per car and means "a bank turned into cash"
		— it is what a quest counting sales and a results screen listen to, and it still fires here,
		once per car, for exactly that reason. This one carries the car IDS (`GarageConfig.carId`;
		they were keys until 2026-09-28, and a legacy car's ID still is one), which is the thing the two
		services that hold a car key on a player need: `LobbyCarService` has to put away a car that is
		standing in the street and `StartCarService` has to forget one it was going to hand you at the
		start of a run. Neither can act on a body and a tier.

		A SIGNAL RATHER THAN THIS FILE CALLING THEM. Both of those services depend on this one (they
		ask it who owns what); calling back into them from here is the cycle that would make. ]]
	"CarsSold",

	--[[ (player: Player) — this player's profile has arrived and everything derived from it has been
		published. Fired once per assignment, from the spawned thread in `_watchProfile`.

		It exists because a second service now needs the same handle and the same moment.
		`UpgradeService` cannot act on a `PlotAssigned` alone — it has to know what the player has
		BOUGHT before it can decide whether to build them a second storey — and having it run its own
		`GetProfileAsync` would give the two services two independent ideas of when a player is ready,
		which is a race with a visible symptom (a lot rebuilt at the wrong floor count). One service
		owns the profile cache, so one service says when it is warm. Late subscribers use
		`isProfileReady`. ]]
	"ProfileReady",

	--[[ (player: Player, key: string?): what this player is HOLDING has changed. A car key, or nil
		for empty hands.

		Fired after the profile is written, after the attribute is published and after the podium
		prompts have been re-lettered, so a subscriber sees the whole change rather than half of it.
		It exists for `CarryService`, which builds the model in the player's hands: a signal rather
		than a call into that service because the dependency only makes sense in that direction. This
		file decides what a player is holding; whether anything is DRAWN for it is not its business,
		and a server with no `CarryService` at all still banks, carries and parks cars correctly. ]]
	"CarryChanged",

	--[[ (player: Player) — what stands on this player's lot, or whether it is for sale, may have just
		changed. Fired at the end of every `_rebuildLot`, which is the one call every such change
		already goes through (a park, a swap, a clear, a sale that unparks, a For Sale toggle), so a
		subscriber cannot miss one by not knowing a new path exists.

		It exists for `BuyerService` (2026-09-28): an offer is only good while its car is on a bay and
		for sale, and this is when that stops being true. It says MAY — a rebuild with nothing moved
		fires it too — so a subscriber re-checks rather than assuming. ]]
	"LotChanged",

	--[[ (player: Player) — the owner pressed the workshop podium, or its kiosk, with a car standing
		on it (2026-09-28, `CustomizeConfig`). `WorkshopService`'s cue to open the screen; a signal for
		the `CarryChanged` reason — that service depends on this one. Fired by `pressWorkshop`. ]]
	"WorkshopPressed",

	--[[ (player: Player, oldId: string, newId: string) — one car's ID changed under it, which only a
		repaint does (`repaintCar`). Fired after every table in the `Garage` save has moved, for the
		services that hold a car ID of their own: `StartCarService` keeps the start car by ID and would
		otherwise quietly fall back to the starter the moment its car was repainted. ]]
	"CarRekeyed",

	--[[ (player: Player, id: string, tier: number, mutation: string?, paint: number?, source: string?)
		— a car has just become this player's, under a fresh ID (2026-09-28, for `ShowcaseService`'s
		NEW BEST cutscene). Fired by `awardCar` THE MOMENT `_addOwned` has run and BEFORE the branch that
		decides where the car lands, because every branch below that point is the player getting the
		car: a subscriber may read ownership and value, but not placement (bay, hands, inventory). A
		duplicate that sells never reaches it, which is right — a sale is not a new car.

		A signal for the `CarryChanged` reason: the showcase depends on this service, not the reverse. ]]
	"CarAwarded",
})

GarageService:withRemoteEvents({
	"OpenDealership", -- server -> client (bay): you pressed a podium — open the picker on this bay
	"InventoryAutoSold", -- server -> client (body, amount, limit): payout already committed
	"InventoryFull", -- server -> client (limit): refused storage move; no car sold

	--[[ server -> client (amount, origin): draw this payout coming out of that mat. One per BAY, so
		a `collectAll` sweep sends six inside a frame; `origin` is the mat's top face, or nil for a
		podium authored without one.

		PURELY COSMETIC, AND FIRED LAST. The cash is in the profile, on the Player attribute and
		through `CashCollected` before this goes out, so a client that ignores it, is too far away to
		draw it, or has no character yet loses nothing — see `CashBurstController`. It is a remote
		rather than something the client derives from watching its own cash attribute because a
		change in the attribute says how much, and this beat needs to know WHERE. ]]
	"CashBurst",
	--- server -> client (changed, gain): EQUIP BEST's answer, how many bays changed and how much the
	--- parked cars' value rose by, for the screen's confirmation (`PagesV2/Dealership._equipBestDone`).
	"EquipBestResult",
	{
		-- client -> server (bay, carId|nil): put this owned car on that bay, or clear it. The ID is
		-- "Body:paint#serial", or a bare key for a car banked before IDs — see `GarageConfig.carId`
		-- and rule 2 of `setBayCar`.
		RequestSetBayCar = function(player: Player, bayIndex: unknown, key: unknown)
			GarageService:_onSetBayRequest(player, bayIndex, key)
		end,

		-- client -> server (nothing): EQUIP BEST on the cars screen. See `equipBest`. No arguments:
		-- the server knows the lot and the collection, so the client is trusted with "now" only.
		RequestEquipBest = function(player: Player)
			local now = os.clock()
			if now < (GarageService._equipCooldowns[player] or 0) then
				return
			end
			GarageService._equipCooldowns[player] = now + 2
			GarageService:equipBest(player)
		end,

		--[[ client -> server (prompt, clientPosition): the dead-prompt trace's probe
			(`GarageConfig.Picker.DebugPrompts`, 2026-09-28). The client saw a podium prompt TRIGGER
			and the server's handler never ran, so the engine dropped the press on the way in; this
			asks the server what IT sees at that moment. A diagnostic only — see `_probePrompt`. ]]
		--[[ client -> server (prompt, clientPosition): this client pressed one of its podium prompts
			(2026-09-30). ALWAYS sent, not a diagnostic: it is the other half of the desync heal
			(`_onBayPromptPressed`, `GarageConfig.Picker.HealDesync`). An ordinary press also reaches the
			prompt's own `Triggered` and this finds nothing to do. ]]
		BayPromptPressed = function(player: Player, prompt: unknown, clientPosition: unknown)
			GarageService:_onBayPromptPressed(player, prompt, clientPosition)
		end,

		PromptProbe = function(player: Player, prompt: unknown, clientPosition: unknown, clientAssembly: unknown)
			GarageService:_probePrompt(player, prompt, clientPosition, clientAssembly)
		end,

		--[[ client -> server (clientPosition, clientAssembly): the desync watch, once a second while
			`GarageConfig.Picker.DebugPrompts` is on. The probe above found the cause of the dead prompt
			— the SERVER's copy of the character stops moving while the client walks on — and this
			catches the moment that starts. A diagnostic only — see `_watchDesync`. ]]
		DesyncProbe = function(player: Player, clientPosition: unknown, clientAssembly: unknown)
			GarageService:_watchDesync(player, clientPosition, clientAssembly)
		end,

		--[[ THERE IS NO `RequestSellCars` AND THAT IS THE POINT. Selling used to be a mode on the
			Cars Inventory and this remote was how the screen asked for it; on 2026-08-24 it became a
			place you drive to (`SellConfig`), and the remote went with the screen. `sellCars` below
			is now reachable only from `SellService`, off a `ProximityPrompt` the engine will not fire
			for a player who is not standing at the lot — so "sell a car" is no longer a message a
			client can send from anywhere on the island. Do not add it back to give a screen a
			shortcut. ]]

		--[[ client -> server (carKey, flag, on): star or unstar one car. `flag` is `"Favorites"`, i.e.
			one of `InventoryConfig.Keys` — validated in `setCarFlag`, so a client naming any other key
			changes nothing. There were two flags to name until 2026-08-24; `FLAG_KEYS` has where the
			other went. ]]
		RequestSetCarFlag = function(player: Player, key: unknown, flag: unknown, on: unknown)
			GarageService:_onFlagRequest(player, key, flag, on)
		end,

		--[[ client -> server (action, carId): one hotbar move (2026-09-30, `CarryConfig.Hotbar`).
			`action` is "toggle" (hold it, or put it back in its slot), "toInventory" or "toHotbar".
			Replaced `RequestCarryCar`, whose PICK UP / PUT DOWN the hotbar now is. Every rule is
			`hotbarAction`'s; the client only names a car. ]]
		RequestHotbar = function(player: Player, action: unknown, id: unknown)
			GarageService:_onHotbarRequest(player, action, id)
		end,
	},
})

-- === Discovery ==============================================================

--[[ The bays on one plot, lowest index first.

	Tag AND path AND a whole-number index, the same three conditions `PlotService._discoverPlots`
	requires of a plot, and for the same reason: each one on its own has a false positive that has
	actually happened in this place. `workspace.Plot7` is a tagged copy of Plot1 parked off the
	island, and the `RoughSlot_*` demo cars carried the identical `Floor`/`SlotIndex` attributes the
	real podiums do — they differed only by tag.

	Floor is checked too, and WHAT IT IS CHECKED AGAINST IS THE PLOT, not this config. A plot in its
	locked state has one deck; a plot whose owner has bought `Floor2` has two, and the difference is
	real geometry that `UpgradeService` clones in and takes back out again. So the gate is the
	`TopFloor` attribute standing on the plot Model, which describes the BUILDING as it is right now
	— a `Floor 2` podium on a plot with no second storey would otherwise get a car parked on thin air
	above the dropped roof, which is exactly what this check has always been for. Absent reads as 1,
	the state every plot is in at load. ]]
function GarageService._discoverBays(self, plot: Model): { Bay }
	--[[ Read once per discovery rather than per podium: it is the same answer for all six, and the
		attribute is written by another service, so a mid-loop change would split the lot. ]]
	local topFloor = tonumber(plot:GetAttribute(UpgradeConfig.PlotFloorsAttribute)) or GarageConfig.BaseFloor

	local folder = plot:FindFirstChild(GarageConfig.SlotsFolderName)
	if not folder then
		return {}
	end

	local bays: { Bay } = {}
	for _, model in folder:GetChildren() do
		if not (model:IsA("Model") and CollectionService:HasTag(model, GarageConfig.SlotTag)) then
			continue
		end

		local index = model:GetAttribute(GarageConfig.SlotIndexAttribute)
		if type(index) ~= "number" or index ~= index or index % 1 ~= 0 then
			self.log:warn(
				string.format("%s has no usable %s — skipped.", model:GetFullName(), GarageConfig.SlotIndexAttribute)
			)
			continue
		end

		local floor = model:GetAttribute(GarageConfig.SlotFloorAttribute)
		if floor ~= nil and floor > topFloor then
			continue
		end

		local base, deck = self:_platforms(model)
		if not (base and deck) then
			self.log:warn(string.format("%s has no pair of Platform parts — skipped.", model:GetFullName()))
			continue
		end

		local button = model:FindFirstChild(GarageConfig.Collect.ButtonName, true)
		--[[ THE WORKSHOP HAS NO COLLECT MAT (2026-10-07, the polish pass). Every podium was authored
			with a cash mat in front of it, and the workshop never earns a tip, so its mat collected
			nothing and read as an unfinished slab beside the new pad. Hidden and switched off here, at
			discovery, on every plot — not deleted, so `CustomizeConfig.HideCollectMat = false` brings it
			back exactly as it was. ]]
		if button and index == CustomizeConfig.Bay.SlotIndex and CustomizeConfig.Enabled and CustomizeConfig.HideCollectMat then
			for _, piece in { button, table.unpack(button:GetDescendants()) } do
				if piece:IsA("BasePart") then
					piece.Transparency = 1
					piece.CanCollide = false
					piece.CanTouch = false
				elseif piece:IsA("SurfaceGui") or piece:IsA("BillboardGui") then
					piece.Enabled = false
				elseif piece:IsA("Decal") or piece:IsA("Texture") then
					piece.Transparency = 1
				end
			end
			button = nil
		end
		local gui = button and button:FindFirstChild(GarageConfig.Collect.GuiName)
		local label = gui and gui:FindFirstChild(GarageConfig.Collect.LabelName, true)

		table.insert(bays, {
			index = index,
			model = model,
			base = base,
			deck = deck,
			button = if button and button:IsA("BasePart") then button else nil,
			label = if label and label:IsA("TextLabel") then label else nil,
			kiosk = self:_kioskFor(model, index),
		})
	end

	table.sort(bays, function(a, b)
		return a.index < b.index
	end)
	return bays
end

--[[ The podium's two slabs: the base, and the deck the car stands on.

	THE SLOT MODEL HAS TWO CHILDREN BOTH NAMED `Platform`, so `slot.Platform` returns an arbitrary
	one of them — which is exactly the duplicate-name trap this codebase has already been bitten by
	elsewhere. They are told apart by WHICH ONE IS HIGHER, which is the only thing "the deck" ever
	meant: the car stands on the top face of the upper slab.

	IT USED TO SORT THEM BY VOLUME AND THAT PICKED THE WRONG SLAB ON ALL 36 PODIUMS. The deck is
	smaller in FOOTPRINT but thicker — 12.70 x 1.62 x 24.60 against the base's 13.94 x 1.21 x 26.32
	at the authored 0.85 scale — so it wins on volume (506 to 446) and came back as the base. Two
	things silently ran off the wrong slab: the car was stood on the base's top face, 0.33 studs
	BELOW the deck it visually sits on, and `fitYaw` fitted it to a platform 1.24 wider and 1.72
	longer than the one under it, so the showroom angle it cleared was one the real deck could not
	hold. Direction was the one thing unhurt — both slabs carry the same yaw, and the mat measures
	at local Z -15.7 off either. ]]
function GarageService._platforms(self, slot: Model): (BasePart?, BasePart?)
	local first, second
	for _, child in slot:GetDescendants() do
		if child:IsA("BasePart") and child.Name == "Platform" then
			if not first then
				first = child
			elseif not second then
				second = child
			end
		end
	end
	if not (first and second) then
		return nil, nil
	end

	local function top(part: BasePart): number
		return part.Position.Y + part.Size.Y / 2
	end
	if top(first) >= top(second) then
		return second, first
	end
	return first, second
end

--[[ Resolve one podium's upgrade kiosk into something the draw path can write to without searching.
	nil when the podium has no kiosk at all, which is not a warning: `Plot7` and the stored
	`Floor2Contents` are both copies that predate it, and a bay with no sign works perfectly — it just
	has no ladder to show.

	Resolved ONCE, at discovery, for the same reason the mat's label is: the draw path runs on every
	collection and on every change to the lot, and a `FindFirstChild` per label per bay per redraw is
	a search for something that has not moved since the map was authored.

	THE TWO LABELS HANG OFF THE BUTTON, NOT OFF THE PANEL, because the button IS the face — see the
	contract in `UpgradeConfig.Bay`. A board still carrying the pre-2026-08-21 layout resolves to a
	kiosk with a button and two nil labels, draws its colour and nothing else, and is fixed by
	re-running `BuildSlotUpgradeBoards` rather than by a special case here. ]]
--[[ The kiosk a podium keeps, or nil. With the per-bay ladder off (`UpgradeConfig.Bay.Enabled`,
	2026-09-28) the board is DESTROYED here, at runtime, on every podium but the workshop's — whose
	board is the CUSTOMIZE sign. Destroyed rather than hidden, unlike the mats (`_hideMats`): the mat
	is a slab people walk across, while the board is a post in the aisle, and an invisible post is
	something to walk into. The map is untouched, so switching the ladder back on restores every
	board. Runs at every discovery, so a floor-2 podium cloned in later loses its board too. ]]
function GarageService._kioskFor(self, slot: Model, index: number): Kiosk?
	if UpgradeConfig.Bay.Enabled or self:isWorkshopBay(index) then
		return self:_discoverKiosk(slot)
	end
	local model = slot:FindFirstChild(UpgradeConfig.Bay.ModelName)
	if model then
		model:Destroy()
	end
	return nil
end

function GarageService._discoverKiosk(self, slot: Model): Kiosk?
	local names = UpgradeConfig.Bay

	local model = slot:FindFirstChild(names.ModelName)
	local board = model and model:FindFirstChild(names.BoardName)
	local gui = board and board:FindFirstChild(names.GuiName)
	local panel = gui and gui:FindFirstChild(names.PanelName)
	if not (gui and gui:IsA("SurfaceGui") and panel) then
		return nil
	end

	local button = panel:FindFirstChild(names.ButtonName)
	return {
		button = if button and button:IsA("TextButton") then button else nil,
		cost = button and button:FindFirstChild(names.CostName) :: TextLabel?,
		level = button and button:FindFirstChild(names.LevelName) :: TextLabel?,
		kit = self:_discoverKitFace(board :: Instance),
	}
end

--[[ The workshop sign's kit face, the same walk one SurfaceGui over (`CustomizeConfig.Kiosk`
	names it). Its labels are found by the attribute the builder stamps, not by where they sit, so
	the layout can change without this following. ]]
function GarageService._discoverKitFace(_self, board: Instance)
	local sign = CustomizeConfig.Kiosk
	local names = UpgradeConfig.Bay
	local gui = board:FindFirstChild(sign.KitGuiName)
	local panel = gui and gui:FindFirstChild(names.PanelName)
	local face = panel and panel:FindFirstChild(names.ButtonName)
	local content = face and face:FindFirstChild(sign.KitContentName)
	if not (gui and gui:IsA("SurfaceGui") and content and content:IsA("GuiObject")) then
		return nil
	end
	local labels = {}
	for _, descendant in content:GetDescendants() do
		if descendant:IsA("TextLabel") and descendant:GetAttribute(sign.KitTextAttribute) ~= nil then
			table.insert(labels, descendant)
		end
	end
	return { content = content, labels = labels }
end

-- === The car on the podium ==================================================
--[[ Park a body on a bay. Returns the display model, or nil if the roster has no such car.

	A STRIPPED CLONE OF THE DRESS, NOT A CAR — see the header, and `Modules/CarDisplay` for the three
	things about building one that look like housekeeping and are not (chief among them: leave the
	welds in and the copy arrives welded to the ROSTER MASTER across the map, which drags that master
	onto this podium to stand inside the painted clone). That module is shared with the parking bays
	`CarDealService` sells from, which is the other place in this game that parks a car nobody drives.

	WHAT STAYS HERE IS THE PART THAT IS ABOUT A BAY:

	  • THE SHOWROOM ANGLE IS FITTED TO THIS DECK. `Display.Yaw` is a ceiling and `CarDisplay.fitYaw`
	    steps down from it until the rotated footprint fits the deck under the car, so a wide body is
	    not left hanging over the edge. See `GarageConfig.Display.Yaw` for why the ceiling is 5.
	  • THE AISLE IS THE BASE'S OWN FACING. `bay.base.CFrame.LookVector` points at the collect mat —
	    the mat is authored at base-local Z -15.7, and -Z is a part's look direction — so "nose down
	    the aisle" is a property of the podium rather than something this file decides.
	  • THE CAR IS NOT SCALED. The podiums are at `ScaleTo(0.85)` and the cars are 1:1. That is not
	    an oversight in the map — it is what leaves a typical body 1.44 studs of deck a side and 1.47
	    an end. Scale the car too and it rattles around inside its own bay.

	`paint` is the palette index this player's copy of the body wears, and `mutation` is the weather
	that was on it when it was stolen (`WeatherConfig`) — nil for an ordinary car, which is nearly all
	of them.

	THE MUTATION IS DRESSED ON LAST, after the car is placed and parented, and by the same module the
	road uses (`Modules/CarMutation`). Same look on the podium as on the traffic car it came off,
	which is the whole point: a player who chased a Molten M5 through a meteor shower should be able
	to see that that is what is standing in their dealership. Without a badge — the pill over a
	traffic car is there to tell you what to jump at, and six of them hanging over a forecourt would
	be signage rather than cars. ]]
function GarageService._buildDisplayCar(self, bay: Bay, bodyName: string, paint: number?, mutation: string?): Model?
	local display = GarageConfig.Display
	local clone, offsets, extents = CarDisplay.build(bodyName, paint, {
		rosterFolder = display.RosterFolderName,
		bodyFolder = display.BodyFolderName,
		hitBoxName = display.HitBoxName,
		name = display.CarName,
		castShadow = display.CastShadow,
	})
	if not clone then
		self.log:warn(
			string.format("No %s.%s to display — bay %d left empty.", display.RosterFolderName, bodyName, bay.index)
		)
		return nil
	end

	local yaw = CarDisplay.fitYaw(
		extents.maxX - extents.minX,
		extents.maxZ - extents.minZ,
		bay.deck.Size.X,
		bay.deck.Size.Z,
		display.Yaw
	)
	local facing = bay.base.CFrame * CFrame.Angles(0, math.rad(yaw), 0)
	local deckTop = bay.deck.Position.Y + bay.deck.Size.Y / 2

	-- Moved while still unparented, so nothing is ever on screen mid-placement.
	CarDisplay.place(offsets, CarDisplay.standOn(extents, bay.deck.Position, deckTop, facing, display.Lift))
	clone.Parent = bay.model

	--[[ AFTER the parent, deliberately. A `Highlight` adorns its own parent and a display clone is
		measured for the badge offset off its bounding box, so both want the model to be where it is
		going to stand. Nothing here yields, so there is no frame on which the car is visible
		undressed. ]]
	CarMutation.apply(clone, mutation)
	self:_dressPodium(bay, bodyName, deckTop)

	return clone
end

local PODIUM_GLOW = "PodiumGlow"

--[[ The podium glow (`GarageConfig.PodiumGlow`): a folder BESIDE the car under the bay's model, so
	nothing that measures the car (the sign's height, the badge) sees a forty-stud beam in it. Built
	every time a car is built and cleared with it (`_clearBay`). Nothing in it collides, is queried or
	casts a shadow — it is light, and the customers' standing-spot raycasts go straight through. ]]
function GarageService._dressPodium(self, bay: Bay, bodyName: string, deckTop: number)
	local cfg = GarageConfig.PodiumGlow
	local old = bay.model:FindFirstChild(PODIUM_GLOW)
	if old then
		old:Destroy()
	end
	local _, band = CarRarity.of(bodyName)
	if not cfg.Enabled or band < cfg.MinBand or self:isWorkshopBay(bay.index) then
		return
	end
	local colour = CarRarity.colourOf(band)
	local folder = Instance.new("Folder")
	folder.Name = PODIUM_GLOW

	local function glowPart(name: string, size: Vector3, cframe: CFrame, transparency: number): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = colour
		part.Transparency = transparency
		part.Size = size
		part.CFrame = cframe
		part.Parent = folder
		return part
	end

	--- A cylinder's length is its X axis, so the disc lies flat on a roll and the beam stands on none.
	local diameter = math.max(2, math.min(bay.deck.Size.X, bay.deck.Size.Z) - cfg.Inset * 2)
	local centre = Vector3.new(bay.deck.Position.X, deckTop + cfg.Thickness / 2 + 0.02, bay.deck.Position.Z)
	local disc = glowPart("Disc", Vector3.new(cfg.Thickness, diameter, diameter), CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90)), cfg.Transparency)
	local light = Instance.new("PointLight")
	light.Color = colour
	light.Brightness = cfg.Brightness + cfg.PerBand * (band - cfg.MinBand)
	light.Range = cfg.Range
	light.Shadows = false
	light.Parent = disc

	local aura = cfg.Aura
	if aura.Enabled and band >= aura.MinBand then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Aura"
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(colour)
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, aura.Size), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(1.5, 2.5)
		emitter.Speed = NumberRange.new(aura.Rise * 0.6, aura.Rise)
		--- Up off the disc's face: the disc is rolled onto its side, so its own +X is world up.
		emitter.EmissionDirection = Enum.NormalId.Right
		emitter.SpreadAngle = Vector2.new(15, 15)
		emitter.Rate = aura.Rate
		emitter.Parent = disc
	end

	local beam = cfg.Beam
	if beam.Enabled and band >= beam.MinBand then
		glowPart("Beam", Vector3.new(beam.Height, beam.Width, beam.Width), CFrame.new(centre + Vector3.new(0, beam.Height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), beam.Transparency)
	end
	folder.Parent = bay.model
end

--[[ The NOT FOR SALE signs alone, against the current flags, on the cars already standing (see
	`setCarFlag` for why not `_rebuildLot`). Takes every sign down and hangs the ones still owed, with
	`_rebuildLot`'s own rule for who gets one, so the two can never disagree about a podium. A bay
	whose display car is missing is left alone: that is a lot mid-rebuild, and the rebuild hangs its
	own signs. ]]
function GarageService._resignLot(self, player: Player)
	local lot = self._lots[player]
	if not lot then
		return
	end
	local cars = self:_cars(player)
	for _, bay in lot.bays do
		local clone = bay.model:FindFirstChild(GarageConfig.Display.CarName)
		if clone and clone:IsA("Model") then
			local old = clone:FindFirstChild("NotForSaleSign")
			if old then
				old:Destroy()
			end
			local car = self:_carAtBay(cars, bay.index)
			if car and not self:isWorkshopBay(bay.index) and not self:isForSale(player, self:_entryId(car)) then
				self:_hangSaleSign(bay, clone)
			end
		end
	end
	--- Whatever else reads the lot (a buyer heading for a car just taken off sale) hears it as before.
	self:getSignal("LotChanged"):Fire(player)
end

function GarageService._clearBay(self, bay: Bay)
	local existing = bay.model:FindFirstChild(GarageConfig.Display.CarName)
	if existing then
		existing:Destroy()
	end
	local glow = bay.model:FindFirstChild(PODIUM_GLOW)
	if glow then
		glow:Destroy()
	end
end

--[[ Public (`CustomerService` tips, 2026-10-06): the banknotes flying from `origin` into the player,
	the same effect a collect mat throws (`CashBurstController`). Purely visual and fired AFTER the
	money has moved, for `_collect`'s reason; the client culls it out of sight. ]]
function GarageService.burstCash(self, player: Player, amount: number, origin: Vector3)
	self:getRemoteEvent("CashBurst"):Fire(player, amount, origin)
end

-- === Reading a lot ==========================================================

--[[ The player's profile, or nil if it has not loaded yet.

	NON-YIELDING on purpose. `Data:GetProfileAsync` blocks until the profile arrives, and this is
	reached from a Touched handler and from the bank path — neither may stall. The handle is cached
	the first time a spawned thread manages to fetch it (`_watchProfile`), and until then every read
	here simply answers "not yet", which every caller already has to handle for a player with no
	profile at all. ]]
function GarageService._profile(self, player: Player)
	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

--[[ The parked cars, every one of them carrying the bay it stands on and the colour it wears.

	TWO MIGRATIONS, BOTH ON READ, and both are one line:

	  • `Bay`. Before the player could choose, the array index WAS the bay number, so an entry with
	    no `Bay` is read as standing on the bay its position implied — exactly what it meant when it
	    was written.
	  • `Paint`. Before colour was part of a car's identity it lived in one map keyed by body
	    (`Keys.Paints`), so an entry with no `Paint` takes the colour that map recorded for its body.
	    That map held one colour per body and this entry is that body, so the answer is unambiguous —
	    which is only true for profiles written before the change, and is why the fallback can never
	    be reached by anything this build writes.

	STAMPED ON READ RATHER THAN IN A MIGRATION PASS, so a profile nobody touches again is still read
	correctly, and picks up the new spelling the first time anything writes the lot. ]]
function GarageService._cars(self, player: Player): { Car }
	local profile = self:_profile(player)
	if not profile then
		return {}
	end
	local garage = profile:Get({ GarageConfig.Keys.Garage })
	local cars = garage and garage[GarageConfig.Keys.Cars]
	if type(cars) ~= "table" then
		return {}
	end

	local legacyPaints: { [string]: number }? = nil
	for index, car in cars do
		if type(car) ~= "table" then
			continue
		end
		-- Resolve saved tiers by body so ladder edits preserve correct pricing and income.
		local currentTier = type(car.Body) == "string" and GarageConfig.TierOfBody[car.Body]
		if currentTier then car.Tier = currentTier end
		if type(car.Bay) ~= "number" then
			car.Bay = index
		end
		if type(car.Paint) ~= "number" and type(car.Body) == "string" then
			-- Fetched lazily: a lot written by this build needs none of it, which is every lot after
			-- the first time one of these players parks anything.
			legacyPaints = legacyPaints or self:_legacyPaints(player)
			car.Paint = PaintConfig.sanitize(car.Body, legacyPaints[car.Body])
		end
	end
	return cars
end

--[[ Which owned car a lot entry is. Its stored `Id`, or — for an entry parked before IDs existed —
	its own key, which is the ID a car with no serial has always had (`GarageConfig.carId`). Every
	comparison between the lot and the collection goes through this, so a bay and the inventory can
	never disagree about which of two red Camaros is standing on the podium. ]]
function GarageService._entryId(self, car: Car): string
	if type(car.Id) == "string" and car.Id ~= "" then
		return car.Id
	end
	return GarageConfig.carKey(car.Body, car.Paint, car.Mutation)
end

-- The car standing on `bayIndex`, and where it sits in the array, or nil for an empty bay.
function GarageService._carAtBay(self, cars: { Car }, bayIndex: number): (Car?, number?)
	for index, car in cars do
		if car.Bay == bayIndex then
			return car, index
		end
	end
	return nil, nil
end

--[[ Public: the podiums on this player's lot, lowest index first. Read-only by convention, exactly
	as `PlotService.getPlots` is.

	It hands back the live records — the `base` and `deck` parts included — because the one caller
	is `CustomerService`, which needs the PODIUM ITSELF to work out where a person stands to look at
	the car on it. Answering with bay numbers alone would mean that service re-walking `CarSlots` and
	telling the two apart again, which is this file's job and one it has already got wrong once (see
	`_platforms`).

	Empty for a player with no lot, which is every player before `PlotAssigned` and after it is
	released. ]]
function GarageService.getBays(self, player: Player): { Bay }
	local lot = self._lots[player]
	return if lot then lot.bays else {}
end

--[[ Public: what is standing on one bay, and what that bay pays per second right now.

	`(nil, 0)` for an empty bay, an unloaded profile or a bay this player does not have.

	ONE CALL FOR BOTH, because the two answers come from the same profile read and every caller so
	far wants them together — and because a rate computed anywhere but here would be a second copy of
	the income formula. It is the identical expression `_publishRate` sums and `_pending` integrates,
	so what a customer pays for a look and what the mat pays for a minute cannot disagree about what
	a bay is worth. ]]
function GarageService.getBayCar(self, player: Player, bayIndex: number): (Car?, number)
	local car = self:_carAtBay(self:_cars(player), bayIndex)
	if not car then
		return nil, 0
	end
	return car, GarageConfig.rateOf(car.Tier, car.Mutation) * self:_bayMultiplier(player, bayIndex)
end

--[[ The collection: every car ever banked, as a CAR KEY (`"Sedan12:6"`), in the order it was first
	banked. A body owned in three colours is three entries.

	Deliberately NOT the same thing as the lot. `_cars` is the six bays that are earning; this is
	everything the player has, and the dealership screen is the one place the two meet.

	NORMALISED ON READ, which is where the legacy migration lives. An entry written before colour was
	part of a car's identity is a bare body name, and comes back as that body keyed to the colour the
	old `Paints` map recorded for it — so a player who owned a red Charger still owns the red one and
	not a stock one. Every entry is also re-sanitised through `PaintConfig`, so narrowing a body's
	pool tomorrow cannot strand somebody's car on a colour that body may no longer be. ]]
function GarageService._ownedList(self, player: Player): { string }
	local profile = self:_profile(player)
	if not profile then
		return {}
	end
	local garage = profile:Get({ GarageConfig.Keys.Garage })
	local stored = garage and garage[GarageConfig.Keys.Owned]
	if type(stored) ~= "table" then
		return {}
	end

	local legacyPaints: { [string]: number }? = nil
	local owned = {}
	local seen = {}
	for _, entry in stored do
		--[[ The mutation comes back sanitised by `parseCarKey` and is written straight back out
			below, which is what makes narrowing or renaming the mutation list survivable: a key
			naming a mutation this build no longer has is re-keyed to the same car WITHOUT it, so the
			player keeps the car and loses only the weather. The alternative — keeping an unknown key
			— would be a car nothing in the game could price. ]]
		local body, paint, mutation = GarageConfig.parseCarKey(entry)
		--[[ The serial rides through the normalisation below untouched. It is the only part of an ID
			that says WHICH car this is; rebuilding the key without it would turn two red Camaros back
			into one, and the dedupe would then delete the second from the save. ]]
		local _key, serial = GarageConfig.splitCarId(entry)
		--[[ A BODY THAT IS NOT ON THE ROSTER IS KEPT, not dropped. It cannot be parked or spawned —
			`setBayCar` and `awardCar` both check `TierOfBody` — but this list is written back on the
			next bank, so filtering here would DELETE that car from the save the first time the player
			banked anything. A roster rename must not cost somebody a car they earned; leaving it in
			means renaming the body back brings it home. ]]
		if not body then
			continue
		end
		if not paint then
			legacyPaints = legacyPaints or self:_legacyPaints(player)
			paint = legacyPaints[body]
		end

		--[[ Deduplicated because sanitising can COLLAPSE two entries into one: a body added to
			`PaintConfig.KeepLivery` after a player owned it in two colours has both of them resolve to
			`Stock`, and a collection listing the same car twice is one the dealership screen would
			draw twice and the duplicate check would disagree with itself about. Two SERIALS of one
			model never collapse — they are two cars, which is the whole point of an ID. ]]
		local id = GarageConfig.carId(GarageConfig.carKey(body, PaintConfig.sanitize(body, paint), mutation), serial)
		if not seen[id] then
			seen[id] = true
			table.insert(owned, id)
		end
	end
	return owned
end

function GarageService._owns(self, player: Player, id: string): boolean
	for _, owned in self:_ownedList(player) do
		if owned == id then
			return true
		end
	end
	return false
end

--[[ Public: does this player own THIS car — one ID, `"Camaro:6#17"`?

	The same question `_owns` answers, exported for the other services that have to gate something on
	the collection — `LobbyCarService` is the first. It takes an ID, so "do they own a red Camaro" and
	"do they own THAT red Camaro" are different questions; the first is `ownsModel`. It reads the
	PROFILE, which is the point: `GarageConfig.OwnedAttribute` is a broadcast of this answer, so
	validating a client's request against the attribute would be validating it against something the
	client watched us send. ]]
function GarageService.owns(self, player: Player, id: unknown): boolean
	return type(id) == "string" and self:_owns(player, id)
end

--[[ Public: does this player own ANY copy of this model — a KEY, `"Camaro:6"`?

	The question the market asks before it sells somebody a car they already have
	(`CarDealConfig.Offer.RefuseOwned`), and the one `awardCar` asks about a duplicate. It is not
	`owns` with the serial dropped from the argument: a player holding only `"Camaro:6#17"` does not
	own the ID `"Camaro:6"`, but they certainly own a red Camaro. ]]
function GarageService.ownsModel(self, player: Player, key: unknown): boolean
	if type(key) ~= "string" then
		return false
	end
	local model = GarageConfig.modelKeyOf(key)
	for _, owned in self:_ownedList(player) do
		if GarageConfig.modelKeyOf(owned) == model then
			return true
		end
	end
	return false
end

--[[ A fresh ID for a car of this model, and the counter moved past it. See
	`GarageConfig.Keys.NextCarSerial` for why this is a counter rather than derived from the
	collection.

	THE COUNTER IS WRITTEN BEFORE THE ID IS USED, so an award that fails after this line has burnt a
	serial and nothing else. The reverse order is the one that costs something: a serial handed out
	twice is two cars sharing one `CarData` record. nil when there is no profile to count in. ]]
function GarageService._mintId(self, player: Player, key: string): string?
	local profile = self:_profile(player)
	if not profile then
		return nil
	end
	local stored = profile:Get({ GarageConfig.Keys.Garage, GarageConfig.Keys.NextCarSerial })
	local serial = if type(stored) == "number" and stored >= 1 then math.floor(stored) else 1
	profile:Set({ GarageConfig.Keys.Garage, GarageConfig.Keys.NextCarSerial }, serial + 1)
	return GarageConfig.carId(key, serial)
end

--[[ Add a car to the collection. Returns whether it was new.

	Idempotent, and the only writer. It used to be bounded at one entry per (body, colour, mutation)
	the roster allows. Since IDs each copy is separate; awardCar now bounds new entries through
	InventoryConfig.MaxCars backpack spaces plus the hotbar and bays (2026-10-12). ]]
function GarageService._addOwned(self, player: Player, key: string): boolean
	local profile = self:_profile(player)
	if not profile or self:_owns(player, key) then
		return false
	end
	local owned = table.clone(self:_ownedList(player))
	table.insert(owned, key)
	profile:Set({ GarageConfig.Keys.Garage, GarageConfig.Keys.Owned }, owned)
	self:_publishOwned(player, owned)
	return true
end

--[[ Broadcast the collection for the Index page and the dealership screen. See GarageConfig.

	THE VALUATION GOES OUT ON THE SAME WRITE, off the same list, and that is the only reason it can
	be trusted: "what you own" and "what it is worth" are one fact published twice, so there is no
	path that can change one without the other. A separate `_publishValue` with its own call sites
	would be six places to remember instead of none. ]]
function GarageService._publishOwned(self, player: Player, owned: { string }?)
	if player.Parent ~= Players then
		return
	end
	local list = owned or self:_ownedList(player)
	player:SetAttribute(GarageConfig.OwnedAttribute, table.concat(list, ","))
	player:SetAttribute(GarageConfig.ValueAttribute, self:_collectionValue(player, list))
	--- A sale or a repaint changes what the hotbar can hold, so it goes out beside the collection.
	self:_publishHotbar(player)
	self:_publishConditions(player)
end

--[[ DEALERSHIP VALUE, since 2026-09-28: the sum of every owned car's MARKET value, so a battered car
	counts for what it would actually fetch. It was `GarageConfig.valueOfCollection`, which prices
	each key as its model; the two agree exactly for a collection with no recorded condition, which
	is every one banked before condition existed. That shared function is still what
	`LeaderboardService` runs over profiles it reads cold, and that board therefore still values
	models — close enough for a ranking, and not worth loading `CarData` for every row of it. ]]
function GarageService._collectionValue(self, player: Player, list: { string }): number
	local records = self:_carDataMap(player)
	local total = 0
	for _, id in list do
		total += MarketValueConfig.valueOfId(id, records[id])
	end
	return total
end

--[[ Mirror every recorded condition onto the Player (`GarageConfig.ConditionAttribute`) so a screen
	can price a car the way the server will. Only cars below full condition appear. Since 2026-09-28
	the fitted parts go out on the same pass (`CustomizeConfig.PartsAttribute`): the two are the
	whole of a car's record as a price sees it, and publishing them from one place is what stops a
	screen ever holding a new condition beside an old engine. ]]
function GarageService._publishConditions(self, player: Player)
	if player.Parent ~= Players then
		return
	end
	local conditions = {}
	local fitted = {}
	for id, record in self:_carDataMap(player) do
		local condition = type(record) == "table" and record.Condition
		if type(condition) == "number" and condition < 1 then
			table.insert(conditions, string.format("%s=%.3f", id, condition))
		end
		local parts = type(record) == "table" and CustomizeConfig.encodeParts(id, record.Parts)
		if parts then
			table.insert(fitted, parts)
		end
	end
	player:SetAttribute(GarageConfig.ConditionAttribute, table.concat(conditions, ","))
	player:SetAttribute(CustomizeConfig.PartsAttribute, table.concat(fitted, ","))
end

--- Public: every car ID this player owns, normalised (`_ownedList`). A fresh table the caller may keep.
function GarageService.ownedIds(self, player: Player): { string }
	return self:_ownedList(player)
end

--- Public: what this player's whole collection would sell for, whole dollars. The same sum the
--- attribute carries — for a caller that has the Player but would rather not parse a string back.
function GarageService.getCollectionValue(self, player: Player): number
	return self:_collectionValue(player, self:_ownedList(player))
end

-- === One car's own state ====================================================
--[[ `Garage.CarData`: what is true of one car ID and not of its model. `GarageConfig.Keys.CarData`
	has the shape and why absence means defaults.

	THE TABLE HANDED BACK IS A COPY. A caller that edited a live profile table in place would change
	the save without `profile:Set` ever running, and the Replica would never hear about it — a
	record that looks written and is silently not replicated. Writes go through `setCarData`. ]]
function GarageService._carDataMap(self, player: Player): { [string]: { [string]: any } }
	local profile = self:_profile(player)
	local garage = profile and profile:Get({ GarageConfig.Keys.Garage })
	local stored = garage and garage[GarageConfig.Keys.CarData]
	return if type(stored) == "table" then stored else {}
end

--[[ Public: one car's record, as a fresh table. Never nil — a car with no record gets an empty one,
	which every reader (`MarketValueConfig` first) treats as defaults. An ID the player does not own
	answers the same empty record: this is a read, and "what is that car's condition" has a harmless
	answer for a car that is not there. ]]
function GarageService.getCarData(self, player: Player, id: string): { [string]: any }
	local record = self:_carDataMap(player)[id]
	return if type(record) == "table" then table.clone(record) else {}
end

--[[ Public (server only — no remote reaches it): merge `patch` into one owned car's record. Returns
	whether anything was written.

	A patch cannot DELETE a field — a nil in a Luau table is not a key, so there is nothing to iterate.
	To put a field back to its default, write the default; `MarketValueConfig` reads an explicit
	default exactly as it reads an absent one.

	IT REFUSES AN ID THE PLAYER DOES NOT OWN, for the reason `setCarFlag` refuses one: the map is
	saved every session, and a record for a car that does not exist is bytes nothing will ever prune
	except by accident. `sellCars` is the one place that deletes a record, in the same call that
	takes the car away. ]]
function GarageService.setCarData(self, player: Player, id: string, patch: { [string]: any }): boolean
	local profile = self:_profile(player)
	if not profile or not self:_owns(player, id) then
		return false
	end
	local map = table.clone(self:_carDataMap(player))
	local record = if type(map[id]) == "table" then table.clone(map[id]) else {}
	for field, value in patch do
		record[field] = value
	end
	map[id] = record
	profile:Set({ GarageConfig.Keys.Garage, GarageConfig.Keys.CarData }, map)
	--- A record can move a car's price, so the valuation and the condition broadcast go out with it.
	self:_publishOwned(player)
	return true
end

--[[ Public: what this one car is worth right now, whole dollars — `MarketValueConfig.valueOfId` over
	its own record. The price the sell lot pays and a buyer's offer is measured against. ]]
function GarageService.marketValueOf(self, player: Player, id: string): number
	return MarketValueConfig.valueOfId(id, self:getCarData(player, id))
end

--[[ Public: where one owned car is. Returns `("Bay", n)`, `("Workshop", n)` (the customization
	podium, since 2026-09-28), `("Hotbar", slot)` (since 2026-09-30), `("Inventory", nil)`, or
	`(nil, nil)` for a car this player does not own.

	DERIVED, NOT STORED. There is no `Location` field anywhere in the save, because every place a car
	can be is already recorded exactly once — a lot entry names its car, and so does the hotbar list —
	and a second field saying the same thing is a second thing that can disagree with the first. A
	car in neither place is in the inventory by elimination.

	THERE IS NO "Carried" ANY MORE. It was its own place until the hotbar; the car in your hands is
	now always a hotbar car (`CarryConfig.Hotbar`), so "is it held" is `getCarriedCar`'s question and
	not a location.

	Pure: it reads the profile and writes nothing, so any system about to act on a car can ask this
	first and refuse if another system has it. That is how "one car, one system at a time" is kept —
	see the rework notes on the buyers, which are the first system that has to ask. ]]
function GarageService.locationOf(self, player: Player, id: string): (string?, number?)
	if not self:_owns(player, id) then
		return nil, nil
	end
	for _, car in self:_cars(player) do
		if car.Bay and self:_entryId(car) == id then
			--- The workshop podium is a place of its own (`CustomizeConfig` note 1): everything that
			--- acts on a car "on a bay" — buyers, the carry refusal — is thereby kept off it.
			return if self:isWorkshopBay(car.Bay) then "Workshop" else "Bay", car.Bay
		end
	end
	local slot = table.find(self:_hotbarList(player), id)
	if slot then
		return "Hotbar", slot
	end
	return "Inventory", nil
end

-- === The catalogue =========================================================
--[[ `Found`: every BODY this player has ever banked, and the one list here that never shrinks.

	IT EXISTS BECAUSE `Owned` STOPPED BEING PERMANENT. Selling takes a car out of the collection —
	that is what selling is — and the Index page ("23/29 Stolen") and the BIGGEST COLLECTION board
	are catalogues of the roster that must not un-tick because somebody cashed in a spare Camaro.
	`InventoryConfig.Keys.Found` names the key and its comment carries the rest of the reasoning.

	BODIES, NOT CAR KEYS. A catalogue counts cars that exist, and four colours of one Camaro is one
	entry in it — which is the call the Index page was already making when it threw the colour away
	on read. Storing bodies is that call made once, on write, instead of by every reader. ]]
function GarageService._foundList(self, player: Player): { string }
	local profile = self:_profile(player)
	if not profile then
		return {}
	end
	local garage = profile:Get({ GarageConfig.Keys.Garage })
	local stored = garage and garage[InventoryConfig.Keys.Found]
	if type(stored) ~= "table" then
		return {}
	end

	local out = {}
	local seen = {}
	for _, body in stored do
		--[[ A body off the roster is KEPT, the same call `_ownedList` makes and for the same reason:
			this list is written back, so filtering here would delete a car from the catalogue the
			first time the player banked anything. Readers filter; the store does not. ]]
		if type(body) == "string" and body ~= "" and not seen[body] then
			seen[body] = true
			table.insert(out, body)
		end
	end
	return out
end

--[[ Seed `Found` from `Owned` for a profile written before it existed. Runs once, on profile load.

	WITHOUT THIS, THE FIRST SALE COSTS AN INDEX TICK. A legacy profile has an empty `Found` and a full
	`Owned`; sell the only Camaro before anything else writes the catalogue and the Camaro is gone
	from both. Seeding is therefore not tidiness, it is the migration — and it is a union rather than
	an overwrite, so running it twice (a hot reload, a second `ProfileReady`) cannot lose anything.

	It writes only when it would change something, so the ordinary case — a profile whose catalogue is
	already ahead of its collection — costs one comparison and no profile write. ]]
function GarageService._migrateFound(self, player: Player)
	local profile = self:_profile(player)
	if not profile then
		return
	end

	local found = self:_foundList(player)
	local seen = {}
	for _, body in found do
		seen[body] = true
	end

	local added = false
	for _, key in self:_ownedList(player) do
		local body = GarageConfig.parseCarKey(key)
		if body and not seen[body] then
			seen[body] = true
			table.insert(found, body)
			added = true
		end
	end

	if added then
		profile:Set({ GarageConfig.Keys.Garage, InventoryConfig.Keys.Found }, found)
		self.log:info(
			string.format("Seeded %s's car catalogue with %d body/ies from their collection.", player.Name, #found)
		)
	end
end

--- Add a body to the catalogue. Returns whether it was new. The only writer, and it never removes.
function GarageService._addFound(self, player: Player, body: string): boolean
	local profile = self:_profile(player)
	if not profile or type(body) ~= "string" or body == "" then
		return false
	end
	local found = self:_foundList(player)
	for _, existing in found do
		if existing == body then
			return false
		end
	end
	table.insert(found, body)
	profile:Set({ GarageConfig.Keys.Garage, InventoryConfig.Keys.Found }, found)
	self:_publishFound(player, found)
	return true
end

-- Broadcast the catalogue for the Index page. See `InventoryConfig.FoundAttribute` for why this is a
-- second attribute rather than the one that page used to read.
function GarageService._publishFound(self, player: Player, found: { string }?)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(InventoryConfig.FoundAttribute, table.concat(found or self:_foundList(player), ","))
end

--- Public: has this player ever banked this BODY, in any colour? The catalogue's own question.
function GarageService.hasFound(self, player: Player, body: unknown): boolean
	if type(body) ~= "string" then
		return false
	end
	for _, found in self:_foundList(player) do
		if found == body then
			return true
		end
	end
	return false
end

-- === The favourite ==========================================================
--[[ One list of CAR KEYS, under `Garage`, broadcast on a player attribute like everything else on
	the collection is.

	IT IS A MARKER AND A SPEED BUMP, AND THE SPEED BUMP IS NOT IN HERE. A favourite sorts a card to
	the top of the inventory list, and `SellService` asks a second time before the lot takes one.
	`sellCars` does not refuse a favourite and must not start to — the confirmation belongs at the
	button the player is standing at, and a rule in here as well would be a second answer to the same
	question.

	THERE WERE TWO FLAGS UNTIL 2026-08-24. The other was `Locked` and it WAS a rule: `sellCars`
	skipped anything in it, which is what made bulk sell mode safe to offer. It went with the padlock
	chip on the inventory card, and the shape of its failure is the reason — a refusal that can only
	be lifted on another screen is a car sitting unsellable until the player remembers which screen.
	NOTHING WRITES OR READS `Garage.Locked` ANY MORE; a profile that has one keeps it and it does
	nothing. Adding a flag back is one line in the table below plus a key in `InventoryConfig`.

	KEYS RATHER THAN BODIES, so starring the red Camaro does not star the black one you were about to
	sell. Same identity rule as everything else on the collection — see `GarageConfig.Banking`.

	PRUNED ON WRITE, NOT ON READ. An entry for a car that is no longer owned is harmless (nothing
	looks a flag up except by a key it already has), and pruning on read would mean a profile write
	inside a getter. `setCarFlag` drops them as it goes past. ]]
local FLAG_KEYS = {
	[InventoryConfig.Keys.Favorites] = InventoryConfig.FavoritesAttribute,
	--[[ The second flag, and the first since the lock left (2026-09-28): a car the player has taken
		off sale. It rides this machinery for the reason the favourite does — ownership check, broadcast
		and prune on sale are already here — and it is the one flag that changes the WORLD, so
		`setCarFlag` rebuilds the lot when it moves (the sign over the podium). `isForSale` reads it. ]]
	[InventoryConfig.Keys.NotForSale] = InventoryConfig.NotForSaleAttribute,
}

function GarageService._flagList(self, player: Player, flag: string): { string }
	local profile = self:_profile(player)
	if not profile then
		return {}
	end
	local garage = profile:Get({ GarageConfig.Keys.Garage })
	local stored = garage and garage[flag]
	if type(stored) ~= "table" then
		return {}
	end

	local out = {}
	local seen = {}
	for _, key in stored do
		if type(key) == "string" and key ~= "" and not seen[key] then
			seen[key] = true
			table.insert(out, key)
		end
	end
	return out
end

--[[ Public: is this exact car starred? The one flag anything but the inventory screen asks about,
	and `SellService` is the asker — a favourite costs a second hold at the lot rather than a refusal
	here. See `FLAG_KEYS`. ]]
function GarageService.isFavorite(self, player: Player, key: unknown): boolean
	if type(key) ~= "string" then
		return false
	end
	for _, favorite in self:_flagList(player, InventoryConfig.Keys.Favorites) do
		if favorite == key then
			return true
		end
	end
	return false
end

function GarageService._publishFlags(self, player: Player)
	if player.Parent ~= Players then
		return
	end
	for flag, attribute in FLAG_KEYS do
		player:SetAttribute(attribute, table.concat(self:_flagList(player, flag), ","))
	end
end

--[[ Public: set or clear one flag on one car. Returns `(ok, reason)`.

	IT REFUSES A CAR THE PLAYER DOES NOT OWN, which is not paranoia about the flag itself — a star on
	a car you have never had does nothing — but about the LIST. A client that could add arbitrary
	strings could grow one of these without bound in a profile that gets saved every session.

	`flag` is checked against `FLAG_KEYS` rather than used as a path, so a client naming `"Cars"` or
	`"Cash"` writes to neither: it is a lookup, and anything not in the table is refused. ]]
function GarageService.setCarFlag(self, player: Player, key: unknown, flag: unknown, on: boolean): (boolean, string)
	if not (GarageConfig.Enabled and InventoryConfig.Enabled) then
		return false, "disabled"
	end
	if type(flag) ~= "string" or not FLAG_KEYS[flag] then
		return false, "noSuchFlag"
	end
	if type(key) ~= "string" or not self:_owns(player, key) then
		return false, "notOwned"
	end
	local profile = self:_profile(player)
	if not profile then
		return false, "noProfile"
	end

	--[[ Rebuilt rather than inserted into or removed from, which is what makes the prune free: the
		new list is every flagged car the player still owns, plus (or minus) this one. ]]
	local owned = {}
	for _, entry in self:_ownedList(player) do
		owned[entry] = true
	end

	local next_ = {}
	local changed = false
	local present = false
	for _, entry in self:_flagList(player, flag) do
		if entry == key then
			present = true
			if on then
				table.insert(next_, entry)
			else
				changed = true
			end
		elseif owned[entry] then
			table.insert(next_, entry)
		else
			changed = true -- a car that has since been sold; dropped on the way past
		end
	end
	if on and not present then
		table.insert(next_, key)
		changed = true
	end

	if not changed then
		return false, "unchanged"
	end

	profile:Set({ GarageConfig.Keys.Garage, flag }, next_)
	self:_publishFlags(player)
	--[[ The sale flag is drawn on the podium, so the podium follows it; a star changes nothing anyone can
		see from the forecourt.

		=== SIGNS ONLY, NOT THE LOT — 2026-10-08 ===
		WAS `_rebuildLot`: every car on every podium destroyed and rebuilt, glow and all, to add or take
		down one billboard. Behind a menu nobody saw it; once the sale tag put the toggle ON the podium
		(`SaleTagController`), every click flashed the whole showroom as six cars and their podium lights
		blinked out and back (the owner: "some flash of light when i click ... it looks weird"). IS
		`_resignLot`: the cars stay, only the signs change. ]]
	if flag == InventoryConfig.Keys.NotForSale then
		self:_resignLot(player)
	end
	return true, if on then "set" else "cleared"
end

--[[ Public: is this car on offer to buyers? True unless the player has taken it off sale — FOR SALE
	IS THE DEFAULT (`InventoryConfig.Keys.NotForSale`), so every car ever banked answers true without a
	write. It says nothing about WHERE the car is: a car in the inventory can be "for sale" and still
	never be offered for, because a buyer only looks at the lot. That second half is the buyers' rule
	and lives with them. ]]
function GarageService.isForSale(self, player: Player, id: unknown): boolean
	if type(id) ~= "string" then
		return false
	end
	for _, held in self:_flagList(player, InventoryConfig.Keys.NotForSale) do
		if held == id then
			return false
		end
	end
	return true
end

--- The remote's end of `setCarFlag`. Unrated: it is one small table write and cannot rebuild a lot.
function GarageService._onFlagRequest(self, player: Player, key: unknown, flag: unknown, on: unknown)
	local ok, reason = self:setCarFlag(player, key, flag, on == true)
	if not ok and reason ~= "unchanged" then
		self.log:info(string.format("%s's %s flag change was refused (%s).", player.Name, tostring(flag), reason))
	end
end

-- === Selling ================================================================
--[[ Public: sell these cars out of the collection. Returns `(soldCount, cash, reason)`.

	THE ONLY PATH THAT TAKES A CAR AWAY FROM A PLAYER, which is why every rule about it is here and
	none of it is on the caller. The caller sends a list of what it wants sold; this decides what that
	means, and the two are deliberately not the same list:

	  1. A CAR HAS TO BE OWNED. Matched on the whole key, so naming a red Camaro is not permission to
	     sell the black one.
	  2. THE LIST IS TRUNCATED, NOT REFUSED, past `MaxPerRequest`. That cap is a bound on server work
	     rather than a design rule, and refusing a fat batch outright would cost the caller the whole
	     action over one entry too many.
	  3. A PARKED CAR IS UNPARKED FIRST. It cannot stay standing on a podium earning money for a car
	     nobody owns, and making the player clear the bay first would be a rule with no reason behind
	     it that the caller would have to explain.

	A FAVOURITE IS NOT SKIPPED HERE AND MUST NOT BECOME SO. There was a `Locked` flag until
	2026-08-24 that this function did skip over, and what replaced it lives entirely on the panel at
	the sell lot — a star, an amber line, and a SELL IT that asks once more before it sends
	(`InventoryConfig.Sell.ConfirmFavorites`) — see `FLAG_KEYS`.

	THE PRICE IS `GarageConfig.valueOf` AND THERE IS NO SECOND PRICE TABLE — header note 3 of that
	file. A car is worth `SellSeconds` of its own income whether it was sold by choice here or by
	banking a duplicate, so "is this worth keeping" has one answer everywhere.

	PENDING CASH ON A SOLD CAR'S BAY IS PAID, not lost: the bay is collected before the car leaves it.
	The alternative is a sale that silently burns up to two hours of income, which reads as the game
	taking something extra, and it is one call to avoid.

	THE CATALOGUE IS UNTOUCHED. Selling your only Camaro does not un-find the Camaro; see `_foundList`. ]]
--[[ `prices` (2026-09-28) is an optional car ID -> dollars map that REPLACES the market value for the
	cars it names — a buyer's accepted offer (`BuyerService`), which is a price the player agreed to
	and not the lot's. Since 2026-10-15 the lot passes one too: its share of the car's worth,
	`SellConfig.LotRate`, worked out by `SellConfig.lotPriceOf` so its labels print the same number. Server-only: no remote reaches this function (see the remotes block), so no
	client can name its own price. Everything else — the ownership check, the unpark, the prune, the
	signals — is identical, which is the point of routing an accepted offer through here: a car sold
	to a buyer leaves the save by exactly the path a car sold at the lot does.

	`source` names the sale on `CarSold` for analytics; absent, a priced sale is a "Buyer" and any
	other is the "Lot", which are the two callers there are. The lot passes "Lot" itself, since its
	sales are priced now too. ]]
function GarageService.sellCars(
	self,
	player: Player,
	keys: unknown,
	prices: { [string]: number }?,
	source: string?
): (number, number, string)
	if not (GarageConfig.Enabled and InventoryConfig.Enabled and InventoryConfig.Sell.Enabled) then
		return 0, 0, "disabled"
	end
	if not self:_profile(player) then
		return 0, 0, "noProfile"
	end
	if type(keys) ~= "table" then
		return 0, 0, "badRequest"
	end

	local owned = {}
	for _, key in self:_ownedList(player) do
		owned[key] = true
	end

	-- What is actually going to be sold, deduped and capped. Order is the caller's — so a truncated
	-- request sells from the top of the list it was handed.
	local selling: { string } = {}
	local sellingSet: { [string]: boolean } = {}
	for _, key in keys do
		if #selling >= InventoryConfig.Sell.MaxPerRequest then
			break
		end
		if type(key) == "string" and owned[key] and not sellingSet[key] then
			-- A body off the roster prices at zero (`GarageConfig.valueOf`), and selling one for
			-- nothing is worse than leaving it alone: the car is gone and the player got nothing. A
			-- rename that stranded a car must not also be a way to lose it.
			local body = GarageConfig.parseCarKey(key)
			if body and GarageConfig.TierOfBody[body] then
				sellingSet[key] = true
				table.insert(selling, key)
			end
		end
	end

	if #selling == 0 then
		return 0, 0, "nothingToSell"
	end

	--[[ Collect every bay a sold car is standing on BEFORE anything is written, so its pending cash
		reaches the player rather than dying with the entry. `_collect` is the same call the mat makes
		and it writes the lot itself, so the read below has to come after it. ]]
	for _, car in self:_cars(player) do
		if car.Bay and type(car.Body) == "string" and sellingSet[self:_entryId(car)] then
			self:_collect(player, car.Bay)
		end
	end

	-- Unpark. Walked backwards because entries are being removed as we go.
	local cars = self:_cars(player)
	local unparked = false
	for index = #cars, 1, -1 do
		local car = cars[index]
		if type(car.Body) == "string" and sellingSet[self:_entryId(car)] then
			table.remove(cars, index)
			unparked = true
		end
	end

	local remaining = {}
	for _, key in self:_ownedList(player) do
		if not sellingSet[key] then
			table.insert(remaining, key)
		end
	end

	local profile = self:_profile(player)
	if not profile then
		return 0, 0, "noProfile" -- `_collect` yields nothing, but the profile can still have gone
	end
	profile:Set({ GarageConfig.Keys.Garage, GarageConfig.Keys.Owned }, remaining)

	if unparked then
		self:_writeCars(player, cars)
		self:_rebuildLot(player)
	end
	self:_publishOwned(player, remaining)

	--[[ The flags are rewritten too, and this is the one place it has to happen: a star on a car that
		has just been sold is a dangling entry, and `setCarFlag` only prunes when the player next
		presses the button. Cheap — one write, and only when something was actually dropped. ]]
	for flag in FLAG_KEYS do
		local kept = {}
		local dropped = false
		for _, key in self:_flagList(player, flag) do
			if sellingSet[key] then
				dropped = true
			else
				table.insert(kept, key)
			end
		end
		if dropped then
			profile:Set({ GarageConfig.Keys.Garage, flag }, kept)
		end
	end
	self:_publishFlags(player)

	--[[ ...and the car in their HANDS, if they have just sold it. Selling the car you are carrying is
		a perfectly reasonable thing to do (the Cars Inventory lists it like any other car you own),
		and the hands have to let go of it: `getCarriedCar` would answer nil from here on anyway, so
		this is what makes the model come off and the prompts go back to saying Change Car in the same
		frame as the sale rather than at the next press. ]]
	local carried = self:_carriedKey(player)
	if carried and sellingSet[carried] then
		self:setCarriedCar(player, nil)
	end

	local total = 0
	for _, key in selling do
		local body = GarageConfig.parseCarKey(key)
		local tier = body and GarageConfig.TierOfBody[body]
		-- Priced WITH its mutation, so the rare car sells for what it was actually earning — and,
		-- since 2026-09-28, with its own condition, through the same `MarketValueConfig` a buyer's
		-- offer is measured against. Two red Camaros can sell for different money now, and should.
		local agreed = prices and prices[key]
		local value = if type(agreed) == "number" and agreed >= 0
			then math.floor(agreed)
			else self:marketValueOf(player, key)
		total += value
		self:getSignal("CarSold"):Fire(player, body, tier, value, source or (if prices then "Buyer" else "Lot"))
	end

	--[[ THE RECORDS GO LAST, AFTER THE PRICES WERE READ OFF THEM. Pruned rather than left, because a
		serial is never reused (`_mintId`) and so nothing would ever overwrite them — they would sit in
		the save for good. One write, and only when a sold car actually had one. ]]
	local records = self:_carDataMap(player)
	local keptRecords, droppedRecord = {}, false
	for id, record in records do
		if sellingSet[id] then
			droppedRecord = true
		else
			keptRecords[id] = record
		end
	end
	if droppedRecord then
		profile:Set({ GarageConfig.Keys.Garage, GarageConfig.Keys.CarData }, keptRecords)
		-- `_publishOwned` above ran before this prune, so the condition list still named the sold cars.
		self:_publishConditions(player)
	end

	self:addCash(player, total)

	self:getSignal("CarsSold"):Fire(player, selling, total)
	self.log:info(
		string.format("%s sold %d car(s) for %d: %s.", player.Name, #selling, total, table.concat(selling, ", "))
	)
	return #selling, total, "sold"
end

--[[ `_onSellRequest` LIVED HERE AND IS GONE (2026-08-24). It was the rate-limited front door for
	the `RequestSellCars` remote, and it shared `_pickerCooldowns` so that a client alternating
	between selling and parking could not sidestep either cooldown taken on its own.

	Both halves went with the screen's sell mode. The only caller of `sellCars` now is `SellService`,
	off a panel that opens when a car of yours comes to rest on the sell pad, with its own per-player
	cooldown (`SellConfig.Request.Cooldown`) — so the shared-table trick has nothing left to guard
	against: a sale still costs driving a car to the lot and getting out of it, and nobody is
	alternating that with the picker sixty times a second. See the remotes block above. ]]

-- Broadcast which bay each parked car is on, as "1:Sedan12:6,4:Sports16:1" — bay, then the CAR KEY,
-- so the dealership screen can tell the red Camaro on bay 1 from the black one sitting unparked.
function GarageService._publishLot(self, player: Player, cars: { Car }?)
	if player.Parent ~= Players then
		return
	end
	local parts = {}
	for _, car in cars or self:_cars(player) do
		if car.Bay and type(car.Body) == "string" then
			table.insert(parts, string.format("%d:%s", car.Bay, self:_entryId(car)))
		end
	end
	player:SetAttribute(GarageConfig.LotAttribute, table.concat(parts, ","))
end

-- The single choke point for "what is parked changed", which is why the rate is republished here
-- rather than at each of the four call sites that would otherwise have to remember to.
function GarageService._writeCars(self, player: Player, cars: { Car })
	local profile = self:_profile(player)
	if not profile then
		return
	end
	profile:Set({ GarageConfig.Keys.Garage, GarageConfig.Keys.Cars }, cars)
	self:_publishRate(player, cars)
	self:_publishLot(player, cars)
end

-- === Cash ===================================================================

--[[ Mirror the profile's cash onto the Player.

	Attributes replicate, which is the whole point: the HUD reads its own number straight off the
	Player with no remote and no round trip, and every other client can read it too — which is what a
	future "richest player on the server" board wants. The profile stays the source of truth; this is
	the broadcast, exactly as `PlotConfig` describes for plot ownership. ]]
function GarageService._publishCash(self, player: Player, amount: number)
	if player.Parent == Players then
		player:SetAttribute(GarageConfig.CashAttribute, amount)
		--[[ And the player list's CASH column (2026-10-15). Written here, beside the attribute, so it
			can never disagree with it: every cash change already comes through this one function.
			Made on first use rather than at join, so a player whose profile never loads shows no
			column rather than a wrong $0.

			=== TEXT, NOT A NUMBER — 2026-10-15 === WAS an IntValue, on the belief that the list draws
			its own short form of a big number. It does not: a millionaire read "2345678". IS a
			StringValue in `GarageConfig.formatCash`'s own words ("$2.3M"), the form every other cash
			figure in the game uses. THE COST: Roblox's list cannot sort a text column by value, so it
			no longer orders players by cash. The richest-player boards (`LeaderboardConfig`) still do. ]]
		local stats = player:FindFirstChild("leaderstats")
		if not stats then
			stats = Instance.new("Folder")
			stats.Name = "leaderstats"
			stats.Parent = player
		end
		local cash = stats:FindFirstChild("Cash")
		if not (cash and cash:IsA("StringValue")) then
			if cash then
				cash:Destroy()
			end
			cash = Instance.new("StringValue")
			cash.Name = "Cash"
			cash.Parent = stats
		end
		;(cash :: StringValue).Value = GarageConfig.formatCash(amount)
	end
end

--[[ Public: what this player's EARNINGS are multiplied by (2026-10-15): 2 with the 2x Cash pass
	(`PassConfig` `CashDouble`), else 1. Read at every place cash is earned rather than given
	(`PassConfig`'s note on the pass lists them), and never inside `addCash`, which also carries
	purchases, refunds and rewards that must not double. ]]
function GarageService.incomeMultiplier(self, player: Player): number
	local passes = Shard.get("PassService")
	return if passes and passes:owns(player, "CashDouble") then 2 else 1
end

function GarageService.getCash(self, player: Player): number
	local profile = self:_profile(player)
	local cash = profile and profile:Get(GarageConfig.Keys.Cash)
	return if type(cash) == "number" then cash else 0
end

-- Add (or, with a negative amount, take) cash. Returns the new balance.
function GarageService.addCash(self, player: Player, amount: number): number
	local profile = self:_profile(player)
	if not profile or amount == 0 then
		return self:getCash(player)
	end

	local balance = math.max(0, self:getCash(player) + amount)
	profile:Set(GarageConfig.Keys.Cash, balance)
	self:_publishCash(player, balance)
	--[[ The kiosks follow the balance, so a level you have just earned the money for lights up while
		you are standing in front of it. The forecourt billboard gets this for free by watching
		`CashAttribute`; these are drawn here, so they are repainted here. ]]
	self:refreshKiosks(player)
	return balance
end

--[[ === Cash by post ========================================================

	A cash grant aimed at somebody who is not in the server the admin is standing in travels as a
	PROFILESTORE MESSAGE: `AdminService.Actions.cashOffline` posts one against their save key, and it
	is delivered here on whichever server has them next — this one, if they were already playing on
	it and it just had not been noticed.

	IT IS APPLIED HERE AND NOT IN `AdminService` for the reason at the top of this file: this service
	is the only thing in the game that writes `Cash`, and a message handler that reached into the
	profile itself would be the second.

	THE WAIT IS THE WHOLE OF IT. A message queued in the datastore is replayed the instant the
	profile session opens, which is before `_watchProfile` has put that profile into `self._profiles`
	— so an `addCash` at that moment is a silent no-op against a player who is standing right there.
	ProfileStore runs the handler in its own thread, so it can simply wait for the profile, and it
	reports the message as landed only once the money is in. A server that dies inside that window
	re-delivers on the next join rather than eating the grant, and one that times out (a player who
	joined and left again) leaves it queued for a join that finishes.

	REGISTERED AT REQUIRE TIME rather than in `init`, because a session replays its queue as it
	opens and `Data:initialize()` runs before `Shard.init()`. See `PlayerProfile.OnMessage`. ]]
local POST_TIMEOUT = 60 -- seconds to wait for a joining player's profile before leaving it queued

PlayerProfile.OnMessage("Cash", function(profile, message: { any }): boolean
	local amount = message[2]
	--[[ Discarded rather than replayed: a malformed message is not a thing a retry fixes, and a
		message that never processes is replayed on every join this player ever makes. ]]
	if type(amount) ~= "number" or amount ~= amount or amount == 0 then
		GarageService.log:warn(string.format("Dropped a posted cash message with amount '%s'.", tostring(amount)))
		return true
	end

	local player = profile:GetPlayer()
	if not player then
		return false
	end

	local deadline = os.clock() + POST_TIMEOUT
	while not GarageService:isProfileReady(player) do
		if player.Parent ~= Players or os.clock() > deadline then
			return false -- still queued; it lands on a join that gets far enough
		end
		task.wait()
	end

	local balance = GarageService:addCash(player, math.floor(amount))
	GarageService.log:info(
		string.format(
			"%s %s %s in the post from %s — balance is now %s.",
			player.Name,
			if amount > 0 then "was given" else "was docked",
			GarageConfig.formatCash(math.abs(amount)),
			tostring(message[3] or "an admin"),
			GarageConfig.formatCash(balance)
		)
	)
	return true
end)

-- === Car XP =================================================================
--[[ Every body a player has banked carries its own XP total, and a level derived from it.

	IT LIVES HERE FOR THE SAME REASON CASH DOES: this service is the only thing that touches the
	profile's `Garage` table, and one writer per number is what keeps every reader agreeing about it.
	`RewardService` decides how much XP a run is worth and which body earns it; the storage, the
	ladder lookup and the broadcast are this service's, exactly as it already owns `Owned`.

	XP is the only thing stored — level is `RewardConfig.levelFor(xp)`, recomputed on every read,
	which is the same "derived, never accumulated" choice this file's header makes about income. It
	means retuning the ladder re-levels every existing profile rather than stranding it on the old
	one, and there is no second number that can drift out of step with the first. ]]
function GarageService._levelsTable(self, player: Player): { [string]: number }
	local profile = self:_profile(player)
	if not profile then
		return {}
	end
	local garage = profile:Get({ GarageConfig.Keys.Garage })
	local levels = garage and garage[GarageConfig.Keys.Levels]
	return if type(levels) == "table" then levels else {}
end

function GarageService.getCarXp(self, player: Player, body: string): number
	local xp = self:_levelsTable(player)[body]
	return if type(xp) == "number" and xp == xp then xp else 0
end

-- Level 1 for a body with no XP, and for one the player has never owned — level 1 is what "an
-- ordinary example of this car" means, so every caller can use this without a nil branch.
function GarageService.getCarLevel(self, player: Player, body: string): number
	return RewardConfig.levelFor(self:getCarXp(player, body))
end

--[[ Add XP to one body. Returns `(level, gained)` — the level it is on now, and whether that is
	higher than it was.

	Written as a CLONE-AND-SET rather than a mutation, the same shape `_addOwned` uses: the table
	`_levelsTable` hands back is the replica's own, and writing into it directly would change the
	server's copy without ever telling the replica the path changed. ]]
function GarageService.addCarXp(self, player: Player, body: unknown, amount: number): (number, boolean)
	if not GarageConfig.Enabled or type(body) ~= "string" or body == "" then
		return 1, false
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return self:getCarLevel(player, body), false
	end
	local profile = self:_profile(player)
	if not profile then
		return 1, false
	end

	local before = self:getCarXp(player, body)
	local levels = table.clone(self:_levelsTable(player))
	levels[body] = before + math.floor(amount)
	profile:Set({ GarageConfig.Keys.Garage, GarageConfig.Keys.Levels }, levels)
	self:_publishLevels(player, levels)

	local wasLevel = RewardConfig.levelFor(before)
	local nowLevel = RewardConfig.levelFor(levels[body])
	return nowLevel, nowLevel > wasLevel
end

-- === Car paint ==============================================================
--[[ COLOUR IS NOT STORED SEPARATELY ANY MORE. It is part of the car's identity, so it rides in the
	`Owned` key (`"Charger:6"`) and on the `Cars` entry (`Paint`), and every reader takes it from
	whichever of those it already had in hand. There is nothing here to keep in step with anything.

	What is left is the one-way door back to the old shape. `Keys.Paints` was a map of body -> index,
	written once per body, from when a player could own exactly one Charger. Nothing writes it now;
	it is read to fill in the colour of a car saved before the key carried one, and that is its
	entire remaining job. See the note on that key for why deleting it repaints every existing
	player's collection to stock. ]]
function GarageService._legacyPaints(self, player: Player): { [string]: number }
	local profile = self:_profile(player)
	if not profile then
		return {}
	end
	local garage = profile:Get({ GarageConfig.Keys.Garage })
	local paints = garage and garage[GarageConfig.Keys.Paints]
	return if type(paints) == "table" then paints else {}
end

-- Broadcast the levels for StealController to read when a steal lands. See
-- GarageConfig.LevelsAttribute — only bodies above level 1 are listed.
function GarageService._publishLevels(self, player: Player, levels: { [string]: number }?)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(GarageConfig.LevelsAttribute, RewardConfig.encodeLevels(levels or self:_levelsTable(player)))
end

-- === Dealership upgrades ====================================================
--[[ The levels bought off the billboard on the forecourt. STORAGE AND BROADCAST ONLY — deciding
	whether a purchase is allowed, what it costs and what it does to the world is `UpgradeService`,
	exactly the way `RewardService` decides how much XP a run is worth while the XP itself lives
	here. One writer per number is what keeps every reader agreeing about it, and this service is
	already the only thing that touches the profile's `Garage` table. ]]

-- Broadcast the levels, so a client can draw its own board state without a round trip. See
-- `UpgradeConfig.Attribute` — only levels above 0 are listed.
function GarageService._publishUpgrades(self, player: Player, upgrades: { [string]: number }?)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(UpgradeConfig.Attribute, UpgradeConfig.encode(upgrades or self:_upgrades(player)))
end

--- Public: this player's upgrade levels, for `UpgradeService` to price the next one against.
function GarageService.getUpgrades(self, player: Player): { [string]: number }
	return self:_upgrades(player)
end

--[[ Public: set one upgrade's level. Returns whether anything was written.

	CLONE-AND-SET rather than a mutation, the same shape `_addOwned`, `addCarXp` and `setBayLevel`
	use and for the same reason: the table `_upgrades` hands back is the replica's own, and writing
	into it directly changes the server's copy without ever telling the replica the path changed.

	It republishes the RATE as well as the levels, because `INCOME` is one of these and the HUD's
	dollars-per-second line is derived from it — an upgrade that did not move that number would read
	as not having been bought. Labels are refreshed for the same reason: the mats are showing money
	computed at the old multiplier. ]]
function GarageService.setUpgradeLevel(self, player: Player, key: string, level: number): boolean
	local profile = self:_profile(player)
	if not profile or not UpgradeConfig.isKey(key) then
		return false
	end

	local upgrades = table.clone(self:_upgrades(player))
	upgrades[key] = level
	profile:Set({ GarageConfig.Keys.Garage, UpgradeConfig.ProfileKey }, upgrades)

	self:_publishUpgrades(player, upgrades)
	self:_publishRate(player)
	self:_refreshLabels(player)
	self:refreshKiosks(player)
	return true
end

-- === Bay levels =============================================================
--[[ The CASH PER SECOND kiosk on each podium. Storage, the income it scales, and the sign itself —
	the same three jobs this file already does for the mats, and split from `UpgradeService` on the
	same line: that service decides a level may CHANGE, this one owns what a level IS worth and what
	it looks like. See `UpgradeConfig.Bay` for the ladder and why it exists next to `Income`. ]]

--- This player's per-bay levels, straight off the profile. Never nil; every reader below is a pure
--- function that treats an empty table as "every bay at level 1", which is what a fresh profile is.
function GarageService._bayLevels(self, player: Player): { [string]: number }
	local profile = self:_profile(player)
	local garage = profile and profile:Get({ GarageConfig.Keys.Garage })
	local levels = garage and garage[UpgradeConfig.Bay.ProfileKey]
	return if type(levels) == "table" then levels else {}
end

--- Public: what level bay `index` is on, 1..MaxLevel. For `UpgradeService` to price the next one.
function GarageService.getBayLevel(self, player: Player, index: number): number
	return UpgradeConfig.bayLevelOf(self:_bayLevels(player), index)
end

--[[ Public: set one bay's level. Returns whether anything was written.

	CLONE-AND-SET rather than a mutation, the same shape `_addOwned`, `addCarXp` and `setUpgradeLevel`
	use and for the same reason: the table `_bayLevels` hands back is the replica's own, and writing
	into it directly changes the server's copy without ever telling the replica the path changed.

	STRING KEY, because that is what comes back out of the datastore and storing it under a number
	would mean the same bay reading as two different keys either side of a save. `bayLevelOf` tries
	both, so an in-memory table written before this line existed is still read correctly.

	It republishes the rate and repaints both signs, because all three are readouts of the number
	that just changed and a purchase that moved none of them would read as not having happened. ]]
function GarageService.setBayLevel(self, player: Player, index: number, level: number): boolean
	local profile = self:_profile(player)
	if not profile or type(index) ~= "number" or index ~= index or index % 1 ~= 0 then
		return false
	end

	local levels = table.clone(self:_bayLevels(player))
	levels[tostring(index)] = math.clamp(level, 1, UpgradeConfig.Bay.MaxLevel)
	--[[ The number-keyed twin is cleared as well as the string one being written. Without it a table
		that has not been through a save yet can hold BOTH, and `bayLevelOf` prefers the string —
		which is correct but leaves a stale number key to be resurrected by nothing at all. Cheap
		insurance against a shape that only differs after a round trip. ]]
	levels[index] = nil
	profile:Set({ GarageConfig.Keys.Garage, UpgradeConfig.Bay.ProfileKey }, levels)

	self:_publishRate(player)
	self:_refreshLabels(player)
	self:refreshKiosks(player)
	return true
end

--[[ What one bay's income is multiplied by: the owner's lot-wide `Income` upgrade AND that bay's own
	level. The one place the two ladders meet, so `_pending`, `_publishRate` and the kiosk cannot
	disagree about what a bay is worth. ]]
function GarageService._bayMultiplier(self, player: Player, bayIndex: number?): number
	local lot = UpgradeConfig.incomeMultiplier(self:_upgrades(player))
	if not bayIndex then
		return lot
	end
	return lot * UpgradeConfig.bayMultiplier(self:getBayLevel(player, bayIndex))
end

-- === Income =================================================================

--[[ The player's dealership upgrades, straight off the profile. Never nil — an unloaded profile and
	a player who has bought nothing are the same answer, level 0 across the board, and every reader
	below is a pure function that already handles it. ]]
function GarageService._upgrades(self, player: Player): { [string]: number }
	local profile = self:_profile(player)
	local garage = profile and profile:Get({ GarageConfig.Keys.Garage })
	local upgrades = garage and garage[UpgradeConfig.ProfileKey]
	return if type(upgrades) == "table" then upgrades else {}
end

--[[ What one parked car owes right now. The whole economy, in four lines — and every number it
	multiplies is the player's rather than the config's.

	It takes the PLAYER as well as the car for exactly that reason: a bay's income and its ceiling are
	both scaled by what the owner has bought — lot-wide by `Income`, and per bay by the level on that
	podium's own kiosk — so pending cash stopped being a property of the parked car alone. Nothing
	else changes: still derived from one timestamp, still nothing accumulated, and an upgrade bought a
	second ago is worth its full value on income the bay earned before it. That last part is
	deliberate. A level is a property of the LOT, not of the seconds, and the alternative — banding
	the elapsed time by when each level was bought — is a ledger, which is the whole thing this
	economy is built to not have. ]]
function GarageService._pending(self, player: Player, car: Car?): number
	if not car then
		return 0
	end
	local upgrades = self:_upgrades(player)
	local elapsed = math.max(0, os.time() - (car.Collected or 0))
	local cap = UpgradeConfig.bankSeconds(upgrades, GarageConfig.Income.MaxBankedSeconds)
	return math.min(elapsed, cap) * GarageConfig.rateOf(car.Tier, car.Mutation) * self:_bayMultiplier(player, car.Bay)
end

--[[ Take one bay's pending cash.

	Rounded DOWN and floored at `MinPayout`, and the stamp is only reset when something was actually
	paid — so brushing past a mat you emptied a moment ago does not silently reset its clock and
	throw away the seconds since. ]]
function GarageService._collect(self, player: Player, bayIndex: number): number
	--[[ No passive income, nothing to collect (`GarageConfig.Income.Passive`, off since 2026-09-28).
		Gated HERE, at the one payout every path runs through, rather than at each caller: the mat,
		`collectAll`, the AUTO COLLECT pass sweep, the Auto Collect upgrade's timer in `UpgradeService`
		and the welcome-back screen all reach this, so one line switches all five off together and
		the flag turns all five back on together. ]]
	if not GarageConfig.Income.Passive then
		return 0
	end
	local cars = self:_cars(player)
	local car = self:_carAtBay(cars, bayIndex)
	if not car then
		return 0
	end

	local amount = math.floor(self:_pending(player, car))
	if amount < GarageConfig.Collect.MinPayout then
		return 0
	end

	car.Collected = os.time()
	self:_writeCars(player, cars)
	amount *= self:incomeMultiplier(player) -- the 2x Cash pass, on collected income
	self:addCash(player, amount)
	self:getSignal("CashCollected"):Fire(player, amount, bayIndex)
	--[[ The visual half, and it goes LAST for the reason the remote's own declaration gives: by this
		line the money is banked and broadcast, so nothing downstream of here can cost the player a
		dollar. It is fired from `_collect` rather than from the mat's `Touched` handler so that every
		payout gets it — the AUTO COLLECT sweep and the welcome-back screen come through here too, and
		the client culls the ones that happen out of sight. ]]
	self:getRemoteEvent("CashBurst"):Fire(player, amount, self:_matPosition(player, bayIndex))
	return amount
end

--[[ The middle of a bay's collect mat's TOP FACE, in world space — where the money comes out of.

	Resolved through the mat's own CFrame rather than by adding half its height to its position, so a
	podium someone tilts in the Explorer still throws its notes off the plate rather than out of the
	middle of it. `bay.button` is optional by design (`_discoverBays` accepts a podium with no mat),
	and nil travels the wire fine — the client throws from the player instead. ]]
function GarageService._matPosition(self, player: Player, bayIndex: number): Vector3?
	local lot = self._lots[player]
	if not lot then
		return nil
	end
	for _, bay in lot.bays do
		if bay.index == bayIndex then
			local mat = bay.button
			return if mat then mat.CFrame:PointToWorldSpace(Vector3.new(0, mat.Size.Y / 2, 0)) else nil
		end
	end
	return nil
end

-- === Banking a car ==========================================================

--[[ Read a (tier, body) pair off the wire.

	Both or nothing. A car that was never stolen carries neither attribute — the starting `Sedan06`
	is spawned by `RaceService` with no `Tier` and no `Body` — so requiring the pair is what stops a
	player driving their starter into the truck for a free Tier 2 every run without ever performing
	the mechanic the game is named after.

	The pair also has to AGREE with the server's own roster. NaN is tested explicitly, because it
	fails every comparison and would otherwise sail through into a table lookup. There is no
	"price it at the minimum" fallback: a malformed bank pays nothing, and the client has already
	played the visual half locally, so the player sees their getaway and simply does not get the car. ]]
function GarageService._readCar(self, tier: unknown, body: unknown): (number?, string?)
	if type(body) ~= "string" or body == "" then
		return nil, nil
	end
	if type(tier) ~= "number" or tier ~= tier or tier % 1 ~= 0 then
		return nil, nil
	end
	if GarageConfig.TierOfBody[body] ~= tier then
		return nil, nil
	end
	return tier, body
end

-- The bay numbers this player actually has, lowest first. Read off the map rather than assumed:
-- `SlotIndex` is an authored attribute and nothing promises it runs 1..6.
function GarageService._bayIndices(self, player: Player): { number }
	local lot = self._lots[player]
	if lot then
		local out = {}
		for _, bay in lot.bays do
			table.insert(out, bay.index)
		end
		return out
	end
	local out = {}
	for i = 1, self._bayCount do
		table.insert(out, i)
	end
	return out
end

-- The lowest-numbered bay with nothing on it, or nil when the lot is full. Never the workshop: a car
-- only goes there because the player put it there (`CustomizeConfig` note 1).
function GarageService._freeBay(self, player: Player, cars: { Car }): number?
	for _, index in self:_bayIndices(player) do
		if not self:_carAtBay(cars, index) and not self:isWorkshopBay(index) then
			return index
		end
	end
	return nil
end

--[[ Public: the player got away with a car. Park it, hand it over, or sell it, but never nothing.

	Returns `(outcome, amount, id)` where outcome is "parked" | "upgraded" | "collected" | "sold" |
	"carried" | "rejected", and `id` is the car ID the player now owns (`GarageConfig.carId`) — nil
	for every outcome that did not add a car. A caller that needs to find the car afterwards (which
	bay it landed on, what to hand the player) should use this rather than rebuild a key: two copies
	of one model are two IDs, and only this one is the car just awarded.

	`source` NAMES THE CALLER ("Bank", "Pull", "Buy", "Admin", "Seller") and does exactly one thing: it decides
	whether the car goes into the player's HANDS instead of onto a bay (`CarryConfig.Sources`). It is
	a name rather than a boolean so the decision stays in one config instead of being made four times
	at four call sites, and it is optional so every caller that does not pass one keeps the behaviour
	it has always had.

	THE "NEVER NOTHING" RULE IS A DESIGN CONSTRAINT, NOT POLITENESS. Driving into the truck ENDS the
	run — that is GDD §3.5's design guard, and it is what makes banking a real decision — so a bank
	that paid nothing would be a whole minute of play thrown away, and it would read as a bug the
	first time it happened.

	WHAT THE COLLECTION CHANGED, because it changes what two of these branches MEAN. Every body you
	bank is now yours permanently (`Owned`), and the six bays are a display you choose. So:

	  • AN EXACT DUPLICATE IS THE ONLY REAL SALE, and "exact" means body AND colour. It is matched
	    against the collection rather than against the lot: a car you own but have not parked is one
	    you own. A Camaro in a colour you do not have is a new car and parks; a second Camaro in a
	    colour you already have is indistinguishable from the first, so it is cash.
	  • DISPLACING A CAR NO LONGER SELLS IT. The worst bay still gives way to a better car with no UI
	    involved — a lot of beaters still becomes a lot of supercars on its own — but the car that
	    comes off goes back to the collection instead of being cashed out, because you still own it
	    and can park it again. That is a real economy change: the refund that branch used to pay is
	    gone. It is the price of the car not being destroyed, and it is the one number to look at
	    first if banking starts to feel thin.
	  • A NEW CAR WITH A FULL LOT PAYS NOTHING AND IS STILL NOT NOTHING. It is a car you did not have,
	    on a screen that shows you the roster you are filling. "collected" is that outcome.

	WHAT "carried" DOES TO ALL OF THAT: nothing, except that no bay is picked here. The catalogue is
	still ticked, the collection still gets the car, a duplicate still sells for the same money. The
	only branch it replaces is the one that chose a podium, because that is the decision the player
	now makes for themselves (`CarryConfig`, and `placeCarried` below is the other end of it). ]]
--[[ Public: is there anywhere for one more car to go (a free hotbar slot, or space in the backpack)?
	False is exactly the case `awardCar` auto-sells, so a caller that must NOT be sold (a one-time
	reward, `GroupRewardService`) asks this first and refuses instead. Pure. ]]
function GarageService.hasRoom(self, player: Player): boolean
	return #self:_hotbarList(player) < CarryConfig.Hotbar.Slots
		or self:_inventoryCount(player) < InventoryConfig.MaxCars
end

function GarageService.awardCar(
	self,
	player: Player,
	tier: unknown,
	body: unknown,
	paint: unknown,
	mutation: unknown,
	source: unknown,
	initialCondition: number?
): (string, number, string?)
	if not GarageConfig.Enabled then
		return "rejected", 0
	end

	local realTier, realBody = self:_readCar(tier, body)
	if not (realTier and realBody) then
		self.log:warn(
			string.format(
				"%s banked an unusable car (tier %s, body %s) — not awarded.",
				player.Name,
				tostring(tier),
				tostring(body)
			)
		)
		return "rejected", 0
	end

	if not self:_profile(player) then
		self.log:warn(string.format("%s banked a %s with no profile loaded — not awarded.", player.Name, realBody))
		return "rejected", 0
	end

	local cars = self:_cars(player)

	--[[ The weather the car was stolen in, already sanitised AND bounded against the schedule by
		`GetawayService` — see this service's own trust note and `WeatherService.couldHaveSpawned`.
		Re-sanitised here anyway, because `awardCar` is a public function and the OTHER caller is not
		the truck: nothing stops a future admin command or a test harness handing it a raw string,
		and this is the last point before the key goes into a save file. Cheap, and it is the same
		belt-and-braces `PaintConfig.sanitize` gets three lines further down for the same reason. ]]
	local realMutation = WeatherConfig.sanitize(mutation)

	--[[ …AND THE PRICE IS THE MUTATED ONE. Everything below that quotes money uses this, so a
		Charged Camaro banked as a duplicate sells for what a Charged Camaro was earning rather than
		for what a plain one would. That is the single most important line in this function for the
		feature to be worth anything: the rare car has to be worth more at every exit, not only when
		it happens to find a free bay. ]]
	local value = GarageConfig.valueOf(realTier, realMutation)

	--[[ The colour the client says it stole it in, run through the body's own pool. SANITISED HERE
		AND NOWHERE ELSE ON THIS PATH, because everything below keys off the result: a client naming a
		colour outside the pool would otherwise own a car nothing else in the game agrees exists, and
		could bank the "same" car repeatedly by naming a different bogus index each time. A liveried
		body sanitises every index to `Stock`, which is what makes "one form only" fall out of the
		palette instead of needing a rule. ]]
	local realPaint = PaintConfig.sanitize(realBody, paint)
	local key = GarageConfig.carKey(realBody, realPaint, realMutation)

	--[[ THE CATALOGUE IS TICKED HERE, BEFORE ANY OF THE BRANCHES BELOW, because every one of them is
		a car this player got away with — a duplicate that sells is still a body they have found, and
		a full lot they had to leave it in the collection for certainly is. Putting it above the
		branching is what makes "have you ever banked this body" impossible to disagree with.
		Idempotent, so the ordinary case (a body you already have) is one scan and no write. ]]
	self:_addFound(player, realBody)

	-- New cars use a free hotbar slot first; only overflow into a full backpack is sold.
	-- Keeping the same sold outcome lets all reward callers finish normally without a phantom car.
	if not self:hasRoom(player) then
		local amount = MarketValueConfig.valueOf(realTier, realMutation, { Condition = initialCondition })
		self:addCash(player, amount)
		self:getSignal("CarSold"):Fire(player, realBody, realTier, amount, "Full")
		self:getRemoteEvent("InventoryAutoSold"):Fire(player, realBody, amount, InventoryConfig.MaxCars)
		return "sold", amount
	end

	--[[ Already in the collection: the duplicate sells (GDD §4).

		Matched on the KEY — body AND colour. Not on tier, because two different Tier 3s were always
		two different cars; and no longer on body alone, because a Camaro in a colour you do not have
		is a car you do not have. See `GarageConfig.Banking` for why that is the identity.

		`ownsModel` and not `owns`, since IDs (2026-09-28): the question is "do you have a red Camaro",
		and a player whose only red Camaro is `"Camaro:6#17"` does not own the ID `"Camaro:6"`. ]]
	--[[ `SellDuplicates` OFF (the default since 2026-09-28) FALLS THROUGH, and the repeat is kept as a
		car of its own. Before IDs it could not be: "the exact repeat is simply already yours" was the
		only honest reading when two identical cars on two podiums were a lot the picker could not
		tell apart. Each copy has its own ID now, so the picker can, and the repeat is just a car. ]]
	if GarageConfig.Banking.SellDuplicates and self:ownsModel(player, key) then
		self:addCash(player, value)
		self:getSignal("CarSold"):Fire(player, realBody, realTier, value, "Duplicate")
		self.log:info(
			string.format("%s banked a duplicate %s (Tier %d) — sold for %d.", player.Name, realBody, realTier, value)
		)
		return "sold", value
	end

	--[[ Theirs from here on, wherever it ends up standing — in the colour they stole it in, and as a
		car of its own even when they already own the same model.

		EVERY CAR IS HANDED OVER UNDER A FRESH ID, and from here to the end of this function `id` is
		what gets stored and returned — the lot entry, the carry and the caller all name this copy,
		never the model. `key` is still what prices it and what the log says. ]]
	local id = self:_mintId(player, key)
	if not id then
		self.log:warn(
			string.format(
				"%s banked a %s but their profile went away before it was stored — not awarded.",
				player.Name,
				realBody
			)
		)
		return "rejected", 0
	end
	self:_addOwned(player, id)
 if initialCondition ~= nil then
  self:setCarData(player, id, {Condition = math.clamp(initialCondition, 0, 1)})
 end
 if GarageConfig.Banking.DefaultNotForSale then
  self:setCarFlag(player, id, InventoryConfig.Keys.NotForSale, true)
 end
	self:getSignal("CarAwarded")
		:Fire(player, id, realTier, realMutation, realPaint, if type(source) == "string" then source else nil)

	--[[ INTO THE HOTBAR IF THERE IS A FREE SLOT (2026-09-30, `CarryConfig.Hotbar`), whatever the
		source: a new car goes where the player can use it, and the inventory holds only what they put
		there or what did not fit. A full hotbar leaves it in the inventory, which is simply where an
		unlisted, unparked car already is.

		...AND A BANK ALSO PUTS IT IN THEIR HANDS, and the two branches below are not reached. Placed
		AFTER `_addOwned` and never instead of it, which is the whole safety of the carry: the car is in
		the collection before anybody is holding anything, so a carry that is never placed and a player
		who leaves mid-carry end in the same harmless place — a car in their hotbar.

		A CAR ALREADY IN THEIR HANDS IS PUT BACK IN ITS SLOT rather than queued; it is still a hotbar
		car. A bank that found the hotbar full is NOT carried: the held car must be a hotbar car. ]]
	local stowed = self:_stow(player, id)
	if stowed and CarryConfig.carries(source) then
		self:setCarriedCar(player, id)
		self.log:info(
			string.format(
				"%s banked a %s %s (Tier %d) into their hands.",
				player.Name,
				PaintConfig.nameOf(realPaint),
				realBody,
				realTier
			)
		)
		return "carried", 0, id
	end

	--[[ INTO THE INVENTORY, AND THAT IS WHERE IT STOPS (`GarageConfig.Banking.AutoPark`, off since
		2026-09-28). The car is already owned — `_addOwned` ran above — so there is nothing left to
		write: the Cars Inventory lists it, and the podium picker or a carry is how it reaches a bay.
		"collected" is the outcome every caller already has words for, which is why it is reused
		rather than a new one being invented that four screens would need teaching. ]]
	if not GarageConfig.Banking.AutoPark then
		self.log:info(
			string.format(
				"%s banked a %s %s (Tier %d) into their inventory as %s.",
				player.Name,
				PaintConfig.nameOf(realPaint),
				realBody,
				realTier,
				id
			)
		)
		return "collected", 0, id
	end

	-- A free bay: park it. `Collected` starts now, so a fresh car owes nothing for its first second.
	local free = self:_freeBay(player, cars)
	if free then
		table.insert(
			cars,
			{
				Body = realBody,
				Tier = realTier,
				Paint = realPaint,
				Mutation = realMutation,
				Collected = os.time(),
				Bay = free,
				Id = id,
			}
		)
		self:_writeCars(player, cars)
		self:_rebuildLot(player)
		self:getSignal("CarParked"):Fire(player, realBody, realTier, free)
		self.log:info(
			string.format(
				"%s banked a %s %s (Tier %d) into bay %d.",
				player.Name,
				PaintConfig.nameOf(realPaint),
				realBody,
				realTier,
				free
			)
		)
		return "parked", 0, id
	end

	--[[ Full lot. The new car takes the worst bay if it is genuinely better, and the car that comes
		off goes back to the collection — so a lot of beaters still becomes a lot of supercars with
		no screen involved, and nothing is destroyed doing it.

		TIES DO NOT SWAP. Trading a Tier 3 for a different Tier 3 changes no income, and shuffling
		the lot for nothing reads as the game having lost your car. ]]
	--[[ MEASURED IN INCOME, NOT IN TIER, and that changed with the weather. "Better" used to be the
		same question as "higher rung", because a rung was the only thing that priced a bay. A
		mutation now multiplies that price (`GarageConfig.rateOf`), so a Charged Tier 3 can out-earn
		a plain Tier 4 — and a tier comparison would refuse to park it, then refuse again every time,
		leaving the rarest car the player has ever found sitting in the collection while a worse one
		earns.

		`rateOf` rather than `valueOf` only because it is the number without a rounding step in it;
		they order identically. The bay multiplier is deliberately NOT in this: which podium a car
		lands on is decided after this comparison, so folding in a kiosk level would make "is this
		car better" depend on where it was about to stand. ]]
	if GarageConfig.Banking.UpgradeWorstBay then
		local worstIndex, worstRate = nil, math.huge
		for index, owned in cars do
			local rate = GarageConfig.rateOf(owned.Tier, owned.Mutation)
			--- A car in the workshop is being worked on, not displayed, so it is never the one bumped.
			if rate < worstRate and not self:isWorkshopBay(owned.Bay) then
				worstIndex, worstRate = index, rate
			end
		end

		if worstIndex and GarageConfig.rateOf(realTier, realMutation) > worstRate then
			local displaced = cars[worstIndex]
			local bay = displaced.Bay
			cars[worstIndex] = {
				Body = realBody,
				Tier = realTier,
				Paint = realPaint,
				Mutation = realMutation,
				Collected = os.time(),
				Bay = bay,
				Id = id,
			}
			self:_writeCars(player, cars)
			self:_rebuildLot(player)
			self:getSignal("CarParked"):Fire(player, realBody, realTier, bay)
			self.log:info(
				string.format(
					"%s banked a %s (Tier %d) onto bay %s; the %s (Tier %s) it replaced went back to the collection.",
					player.Name,
					realBody,
					realTier,
					tostring(bay),
					tostring(displaced.Body),
					tostring(displaced.Tier)
				)
			)
			return "upgraded", 0, id
		end
	end

	-- Full lot and nothing to improve on. It is still a car they did not have; the dealership screen
	-- is where they decide whether to make room for it.
	self.log:info(
		string.format(
			"%s banked a %s (Tier %d) with a full lot — added to the collection.",
			player.Name,
			realBody,
			realTier
		)
	)
	return "collected", 0, id
end

-- === What is in your hands ==================================================
--[[ Public: the car this player is holding, as a car key, or nil for empty hands.

	A STALE KEY READS AS EMPTY HANDS. The only way to hold a car you do not own is to sell it out of
	the Cars Inventory while carrying it, which `sellCars` already clears; this is the belt to that
	braces, and it is what stops a profile written by an older build (or edited by hand) from leaving
	somebody with a model welded to them that no bay will ever accept. ]]
function GarageService.getCarriedCar(self, player: Player): string?
	local key = self:_carriedKey(player)
	if not key or not self:_owns(player, key) then
		return nil
	end
	--- THE HELD CAR IS A HOTBAR CAR (2026-09-30). One that has left the hotbar — parked, moved into
	--- the inventory — is not in anybody's hands, whatever the stored key still says.
	if not table.find(self:_hotbarList(player), key) then
		return nil
	end
	return key
end

--[[ The raw stored key, owned or not.

	It exists for exactly one caller, `sellCars`, which has to ask what is in the player's hands AFTER
	it has taken the sold cars out of the collection: at that point `getCarriedCar` already answers
	nil, and the hands would be left holding a model with nothing left to clear it. Nothing else has a
	reason to see a key the player does not own. ]]
function GarageService._carriedKey(self, player: Player): string?
	local profile = self:_profile(player)
	if not profile then
		return nil
	end
	local garage = profile:Get({ GarageConfig.Keys.Garage })
	local key = garage and garage[CarryConfig.ProfileKey]
	return if type(key) == "string" and key ~= "" then key else nil
end

--[[ Public: put a car in this player's hands, or empty them (`key = nil`).

	THE ORDER IS THE CONTRACT and `CarryChanged` is fired last: the profile is written, the attribute
	is published, the podiums are re-lettered, and only then is anything told. A subscriber that
	rebuilt the model off a half-applied change would be drawing a car the prompts would not take.

	IT DOES NOT CHECK OWNERSHIP, deliberately. Every caller is this file, on a path that has just
	written the collection; `getCarriedCar` is where a key that has stopped being owned is dropped,
	because that can happen long after this ran. ]]
function GarageService.setCarriedCar(self, player: Player, key: string?)
	local profile = self:_profile(player)
	if not profile then
		return
	end
	profile:Set({ GarageConfig.Keys.Garage, CarryConfig.ProfileKey }, key or "")
	self:_publishCarried(player, key)
	--- An old save's held car is folded into the hotbar on read; writing it here makes that stick.
	if key then
		self:_writeHotbar(player, self:_hotbarList(player))
	end
	self:_refreshBayPrompts(player)
	self:getSignal("CarryChanged"):Fire(player, key)
end

--- Mirror what is in this player's hands onto the Player, for the client to draw (`CarryConfig`).
--- Empty hands are the empty string rather than a cleared attribute, so a client reading it never
--- has to tell "nothing" from "not published yet".
function GarageService._publishCarried(self, player: Player, key: string?)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(CarryConfig.Attribute, key or "")
end

--[[ Re-letter this player's podium prompts for what they are holding.

	ONE PROMPT PER PODIUM, TWO MEANINGS. Empty handed it opens the Cars Inventory on that bay; with a
	car in your hands it parks that car. A second prompt on the same deck was the obvious build and is
	the wrong one: two prompts sharing one key on one part is the case `LobbyCarService._wireEntry`
	measured on the car doors, where the engine draws one of them and does not pick the nearest.

	VISITORS SEE THE OWNER'S WORD, which costs nothing: the `Triggered` handler has always refused
	anybody but the owner, so the text on a lot that is not yours was already describing something you
	cannot do. ]]
function GarageService._refreshBayPrompts(self, player: Player)
	local lot = self._lots[player]
	if not lot then
		return
	end
	local placing = self:getCarriedCar(player) ~= nil
	local cars = self:_cars(player)
	local picker = GarageConfig.Picker
	local hidden = GlassPromptConfig.Attributes.Hidden
	for index, prompt in lot.prompts do
		local occupied = self:_carAtBay(cars, index) ~= nil
		local workshop = self:isWorkshopBay(index)
		local objectText = if workshop
			then CustomizeConfig.Prompt.ObjectText
			else string.format("%s %d", picker.PromptObjectText, index)
		--- What the menu is called on this podium: the workshop with a car on it opens the workshop.
		local menuText = if workshop and occupied then CustomizeConfig.Prompt.ActionText else picker.PromptActionText
		local pickingUp = not placing and occupied and picker.PickUp.Enabled

		prompt.ObjectText = objectText
		prompt.ActionText = if placing
			then CarryConfig.Prompt.ActionText
			elseif pickingUp then picker.PickUp.ActionText
			elseif occupied then menuText
			else picker.EmptyActionText
		prompt.HoldDuration = if pickingUp then picker.PickUp.HoldDuration else picker.PromptHoldDuration

		--- F is the menu only while E is not: holding a car (E places it), or a bay with no car on it
		--- (E is the menu already).
		local option = lot.options and lot.options[index]
		if option then
			option.ObjectText = objectText
			option.ActionText = menuText
			option:SetAttribute(hidden, not pickingUp)
		end

		--- X, the sale toggle: only with a car on a showroom podium and empty hands, captioned for what
		--- a press does to it now.
		local sale = lot.sales and lot.sales[index]
		if sale then
			local car = if pickingUp and not workshop then self:_carAtBay(cars, index) else nil
			sale.ObjectText = objectText
			sale:SetAttribute(hidden, car == nil)
			if car then
				local forSale = self:isForSale(player, self:_entryId(car))
				sale.ActionText = if forSale then picker.Sale.TakeOffText else picker.Sale.PutOnText
			end
		end
	end
end

--[[ Public: the podium's HOLD (`GarageConfig.Picker.PickUp`). Take the car off `bayIndex` and put it
	in this player's hands. Returns `(ok, reason)`.

	IT IS `setBayCar(nil)` AND THEN A HOLD, nothing new: the clear already sends the car to the hotbar
	(or the inventory when the bar is full) exactly as CLEAR BAY did. The only addition is the last
	step, holding it, which is what makes this the mirror of placing. A full hotbar still clears the
	bay; the car is in the inventory and the hands stay empty. ]]
function GarageService.pickUpBay(self, player: Player, bayIndex: number): (boolean, string)
	local car = self:_carAtBay(self:_cars(player), bayIndex)
	if not car then
		return false, "alreadyEmpty"
	end
	local id = self:_entryId(car)
	local ok, reason = self:setBayCar(player, bayIndex, nil)
	if not ok then
		return false, reason
	end
	if table.find(self:_hotbarList(player), id) then
		self:setCarriedCar(player, id)
		self.log:info(string.format("%s picked %s up off bay %d.", player.Name, id, bayIndex))
		return true, "held"
	end
	self.log:info(
		string.format("%s picked %s up off bay %d; hotbar full, so it went to the inventory.", player.Name, id, bayIndex)
	)
	return true, "stored"
end

--[[ Public: park the car in this player's hands on `bayIndex`. The podium prompt's end of the
	carry, and the only one.

	IT IS `setBayCar` WITH THE KEY FILLED IN, which is the whole point of it being written this way:
	a placement is not a new way for a car to reach a bay. The swap rule, the ownership check, the
	`Collected` stamp, the rebuild and the `CarParked` signal are all that function's, so a car placed
	out of your hands and a car dragged onto a bay from the Cars Inventory land in exactly the same
	state. Placing onto an OCCUPIED bay therefore swaps: the car that was standing there goes back to
	the collection, which is what a player with a full lot is doing when they press this.

	TWO REFUSALS EMPTY THE HANDS ANYWAY, and they are the two that would otherwise persist forever.
	`notOwned` is a car sold out from under the carry, and `alreadyThere` is that same car ALREADY
	standing on the bay being pressed, which is what the Cars Inventory parking it mid-carry leaves
	behind. Neither has anything left to place, and a model welded to somebody that no press can ever
	take off them is worse than a carry that quietly ends. Every other refusal is a state the next
	press can succeed from, so the car stays in their hands.

	Returns `(ok, reason)`, the reasons being `setBayCar`'s plus "notCarrying". ]]
function GarageService.placeCarried(self, player: Player, bayIndex: number): (boolean, string)
	local key = self:getCarriedCar(player)
	if not key then
		--- Not an error and not logged: a client cannot reach this, and the one way to get here is to
		--- press a podium with empty hands, which is the ordinary case for that prompt.
		return false, "notCarrying"
	end

	local ok, reason = self:setBayCar(player, bayIndex, key)
	if not ok then
		-- Logged because a refused placement is otherwise invisible: the car stays in the player's
		-- hands and the press simply does nothing, which is indistinguishable from a broken prompt.
		self.log:info(
			string.format(
				"%s could not place the %s they were carrying on bay %d (%s).",
				player.Name,
				key,
				bayIndex,
				reason
			)
		)
		if reason == "notOwned" or reason == "alreadyThere" then
			self:setCarriedCar(player, nil)
		end
		return false, reason
	end

	self:setCarriedCar(player, nil)
	self.log:info(string.format("%s placed the %s they were carrying on bay %d.", player.Name, key, bayIndex))
	return true, reason
end

-- === The hotbar =============================================================
--[[ THE HOTBAR'S HALF OF THIS FILE (2026-09-30). `CarryConfig.Hotbar` has the design; what lives here
	is the list, and the three moves a client may ask for. ]]

--[[ The hotbar as it really is: the stored list with everything that has stopped being true taken
	out — a car sold, a car since parked on a bay, a repeat — capped at `Slots`.

	THE HELD CAR IS FOLDED IN when it is missing and there is room. That is the migration from the
	one-slot carry: a save from before the hotbar has an empty list and a car in its hands, and this
	is what makes that car a hotbar car rather than a car held from nowhere. `setCarriedCar` writes
	the folded list back.

	Pure: it reads the profile and writes nothing, which is what lets `locationOf` and
	`getCarriedCar` both lean on it. ]]
function GarageService._hotbarList(self, player: Player): { string }
	local profile = self:_profile(player)
	if not profile then
		return {}
	end
	local garage = profile:Get({ GarageConfig.Keys.Garage })
	local stored = garage and garage[CarryConfig.Hotbar.ProfileKey]
	local parked = {}
	for _, car in self:_cars(player) do
		if car.Bay then
			parked[self:_entryId(car)] = true
		end
	end
	local out = {}
	local function keep(id: unknown)
		if
			#out < CarryConfig.Hotbar.Slots
			and type(id) == "string"
			and not parked[id]
			and not table.find(out, id)
			and self:_owns(player, id)
		then
			table.insert(out, id)
		end
	end
	if type(stored) == "table" then
		for _, id in stored do
			keep(id)
		end
	end
	keep(self:_carriedKey(player))
	return out
end

--[[ 2026-10-12: Capacity follows the backpack grid, not total ownership. Hotbar and parked
	cars have their own spaces; counting either here made 191 visible cars report full.
	Pure and server-owned: the client cannot free space by hiding a card or changing an attribute. ]]
function GarageService._inventoryCount(self, player: Player): number
	local elsewhere = {}
	for _, id in self:_hotbarList(player) do
		elsewhere[id] = true
	end
	for _, car in self:_cars(player) do
		if car.Bay then
			elsewhere[self:_entryId(car)] = true
		end
	end
	local count = 0
	for _, id in self:_ownedList(player) do
		if not elsewhere[id] then
			count += 1
		end
	end
	return count
end

--- Store the hotbar and tell the client. The ONE writer of `CarryConfig.Hotbar.ProfileKey`.
function GarageService._writeHotbar(self, player: Player, list: { string })
	local profile = self:_profile(player)
	if not profile then
		return
	end
	profile:Set({ GarageConfig.Keys.Garage, CarryConfig.Hotbar.ProfileKey }, list)
	self:_publishHotbar(player)
end

--[[ Mirror the hotbar onto the Player (`CarryConfig.Hotbar.Attribute`), IDs comma-joined in slot
	order. Read fresh rather than passed, so the list the client draws is always the normalised one. ]]
function GarageService._publishHotbar(self, player: Player)
	if player.Parent ~= Players or not self:_profile(player) then
		return
	end
	player:SetAttribute(CarryConfig.Hotbar.Attribute, table.concat(self:_hotbarList(player), ","))
end

--[[ Put one owned, unparked car into the hotbar if there is a free slot. Returns whether it is there
	now. `slot` asks for a place in the order (a car coming off a bay takes the slot the car that
	went onto it left), and is clamped to the end of the list.

	NO FREE SLOT IS NOT A FAILURE: the car simply stays where an unlisted car is, the inventory. ]]
function GarageService._stow(self, player: Player, id: string, slot: number?): boolean
	local list = self:_hotbarList(player)
	if table.find(list, id) then
		return true
	end
	if #list >= CarryConfig.Hotbar.Slots or not self:_owns(player, id) then
		return false
	end
	table.insert(list, math.clamp(slot or #list + 1, 1, #list + 1), id)
	self:_writeHotbar(player, list)
	return true
end

--[[ Public: one hotbar move. Returns `(ok, reason)`.

	    toggle        a hotbar car: hold it, or put it back in its slot if it is the one held
	    toInventory   a hotbar car: out of the bar and into the Cars Inventory (let go if held)
	    toHotbar      an inventory car: into the first free slot; "hotbarFull" when there is none

	A CAR ON A BAY IS NONE OF THESE and every move refuses it ("onBay"): the podium is how it leaves
	a podium. A car that is not where the move assumes is refused rather than fixed up, because a
	client naming a car in the wrong place is a stale screen, and the attribute write it is about to
	receive is the repaint that fixes it. ]]
function GarageService.hotbarAction(self, player: Player, action: string, id: string): (boolean, string)
	if not (GarageConfig.Enabled and CarryConfig.Enabled) then
		return false, "disabled"
	end
	if not self:_profile(player) then
		return false, "noProfile"
	end
	local where = self:locationOf(player, id)
	if where == nil then
		return false, "notOwned"
	elseif where == "Bay" or where == "Workshop" then
		return false, "onBay"
	end

	if action == "toggle" then
		if where ~= "Hotbar" then
			return false, "notInHotbar"
		end
		local holding = self:getCarriedCar(player) == id
		self:setCarriedCar(player, if holding then nil else id)
		return true, if holding then "putAway" else "held"
	elseif action == "toInventory" then
		if where ~= "Hotbar" then
			return false, "notInHotbar"
		end
		if self:_inventoryCount(player) >= InventoryConfig.MaxCars then
			self:getRemoteEvent("InventoryFull"):Fire(player, InventoryConfig.MaxCars)
			return false, "inventoryFull"
		end
		if self:getCarriedCar(player) == id then
			self:setCarriedCar(player, nil)
		end
		local list = self:_hotbarList(player)
		table.remove(list, table.find(list, id) :: number)
		self:_writeHotbar(player, list)
		self.log:info(string.format("%s moved %s into their inventory.", player.Name, id))
		return true, "stored"
	elseif action == "toHotbar" then
		if where ~= "Inventory" then
			return false, "notInInventory"
		end
		if not self:_stow(player, id) then
			return false, "hotbarFull"
		end
		self.log:info(string.format("%s moved %s into their hotbar.", player.Name, id))
		return true, "stowed"
	end
	return false, "badAction"
end

--[[ The remote's end of `hotbarAction`. Rate limited on the carry's own table, the one the podium
	placement already uses: holding and letting go both rebuild a model on the character
	(`CarryService`), which is the cost worth flooring. ]]
function GarageService._onHotbarRequest(self, player: Player, action: unknown, id: unknown)
	if type(action) ~= "string" or type(id) ~= "string" then
		return
	end
	local now = os.clock()
	if now < (self._carryCooldowns[player] or 0) then
		return
	end
	self._carryCooldowns[player] = now + CarryConfig.Prompt.Cooldown

	local ok, reason = self:hotbarAction(player, action, id)
	if not ok then
		self.log:info(string.format("%s's hotbar %s on %s was refused (%s).", player.Name, action, id, reason))
	end
end

--[[ Public: put an owned car on a bay, or clear the bay (`key = nil`). Server-authoritative.

	IT TAKES A CAR ID, NOT A BODY — `"Sedan12:6#4"`, that red one specifically. That is the whole of
	what changed when a player could own the same body twice: "park my Camaro" stopped having one
	answer, and a screen that sent a body name would be asking the server to guess which of them it
	meant. It was a car KEY until 2026-09-28, which stopped being enough the day two copies of one
	model could both be kept; a legacy key with no serial is still a valid ID (`GarageConfig.carId`),
	so screens sending those keep working. `GarageConfig.parseCarKey` is the other end of it.

	Returns `(ok, reason)`. Four rules, and the third is the only interesting one:

	  1. The bay has to be a real bay on THIS player's lot.
	  2. The car has to be in their collection. This is the check that matters — it is the whole
	     reason ownership is a server-side list and not something the screen tells us. Matched on the
	     key, so owning a red Camaro is not permission to park a black one.
	  3. THAT car already parked on ANOTHER bay SWAPS with whatever is on the target, rather than
	     being cloned onto it. Otherwise picking your only Tier 5 for a second bay would quietly
	     duplicate its income, which is the one way this screen could break the economy. Matched on
	     the key rather than the body, which is what lets both your Camaros stand on the lot at once —
	     they are different cars, and only the SAME car may not be in two places.
	  4. `Collected` is preserved across a move, so shuffling the lot neither banks nor burns the
	     pending cash a bay had built up. Moving a car is not collecting from it. ]]
function GarageService.setBayCar(self, player: Player, bayIndex: number, key: string?): (boolean, string)
	if not (GarageConfig.Enabled and GarageConfig.Picker.Enabled) then
		return false, "disabled"
	end
	if not self:_profile(player) then
		return false, "noProfile"
	end
	if type(bayIndex) ~= "number" or bayIndex ~= bayIndex or bayIndex % 1 ~= 0 then
		return false, "badBay"
	end

	local isRealBay = false
	for _, index in self:_bayIndices(player) do
		if index == bayIndex then
			isRealBay = true
			break
		end
	end
	if not isRealBay then
		return false, "noSuchBay"
	end

	local cars = self:_cars(player)
	local target, targetSlot = self:_carAtBay(cars, bayIndex)

	-- Clearing the bay: the car goes back to the hotbar if there is room, else the inventory
	-- (`CarryConfig.Hotbar`, 2026-09-30) — it is still theirs either way.
	if key == nil then
		if not targetSlot then
			return false, "alreadyEmpty"
		end
		if #self:_hotbarList(player) >= CarryConfig.Hotbar.Slots
			and self:_inventoryCount(player) >= InventoryConfig.MaxCars then
			self:getRemoteEvent("InventoryFull"):Fire(player, InventoryConfig.MaxCars)
			return false, "inventoryFull"
		end
		table.remove(cars, targetSlot)
		self:_writeCars(player, cars)
		self:_stow(player, self:_entryId(target :: Car))
		self:_rebuildLot(player)
		self.log:info(string.format("%s cleared bay %d.", player.Name, bayIndex))
		return true, "cleared"
	end

	if type(key) ~= "string" or not self:_owns(player, key) then
		return false, "notOwned"
	end
	--[[ Split AFTER the ownership check, not before. `_owns` compares the key the collection actually
		holds, so a client that sends `"Sedan12:007"` or `"Sedan12:99"` fails there rather than being
		normalised into a car it does not own. The key is well-formed by the time it is taken apart. ]]
	local body, paint, mutation = GarageConfig.parseCarKey(key)
	local tier = body and GarageConfig.TierOfBody[body]
	if not (body and tier) then
		return false, "notOnRoster"
	end
	if target and self:_entryId(target) == key then
		return false, "alreadyThere"
	end

	local moving, movingSlot = nil, nil
	for index, car in cars do
		if self:_entryId(car) == key then
			moving, movingSlot = car, index
			break
		end
	end

	if moving and movingSlot then
		-- Rule 3: a swap, so the same car never stands on two bays. A different COLOUR of the same
		-- body does not match here, and neither does a different MUTATION — which is what lets a plain
		-- Camaro and the Charged one stand on the lot at the same time. They are different cars.
		local from = moving.Bay
		moving.Bay = bayIndex
		if target then
			target.Bay = from
		end
		self:_writeCars(player, cars)
		self:_rebuildLot(player)
		self.log:info(string.format("%s moved %s from bay %s to bay %d.", player.Name, key, tostring(from), bayIndex))
		return true, "swapped"
	end

	--[[ Coming in from the hotbar or the inventory: it takes the bay, and whatever was there goes back
		— into the hotbar SLOT THE INCOMING CAR LEFT when it came from the hotbar, so placing a held car
		on an occupied podium is a straight trade in the same slot. Otherwise the first free slot, or
		the inventory when there is none (`CarryConfig.Hotbar`).

		THE ORDER IS LOAD-BEARING: the lot is written first, so `_hotbarList` already reads the incoming
		car as parked (gone from the bar, its slot free) by the time the displaced car is stowed. ]]
	local _, freedSlot = self:locationOf(player, key)
	if targetSlot then
		table.remove(cars, targetSlot)
	end
	table.insert(
		cars,
		{ Body = body, Tier = tier, Paint = paint, Mutation = mutation, Collected = os.time(), Bay = bayIndex, Id = key }
	)
	self:_writeCars(player, cars)
	self:_writeHotbar(player, self:_hotbarList(player))
	if target then
		self:_stow(player, self:_entryId(target), freedSlot)
	end
	--[[ The held car parked from the PICKER rather than by the podium prompt: `getCarriedCar` already
		reads it as gone (it left the hotbar), but only `setCarriedCar` fires the `CarryChanged` that
		takes the model off the character. `placeCarried` clears it again after this, harmlessly. ]]
	if self:_carriedKey(player) == key then
		self:setCarriedCar(player, nil)
	end
	self:_rebuildLot(player)
	self:getSignal("CarParked"):Fire(player, body, tier, bayIndex)
	self.log:info(string.format("%s parked %s (Tier %d) on bay %d.", player.Name, key, tier, bayIndex))
	return true, "parked"
end

--[[ Public: EQUIP BEST (2026-10-15, the owner: "an equip best cars button in the car inventory").
	Fill this player's bays with the most valuable cars they own (`marketValueOf`, the number tips
	scale with), best first.

	EVERYTHING GOES THROUGH `setBayCar`, one bay at a time, so its four rules are this one's: only
	real bays, only owned cars, a car never on two bays, and a displaced car goes back to the hotbar or
	the inventory, never lost. On top: a car already parked that makes the cut STAYS where it is (no
	shuffling, its pending cash untouched), the workshop podium is never filled, and two cars are left
	out of the running: the one in the workshop (another system has it) and the one in the player's
	hands (taking it out of them unasked would be the surprise). Returns how many bays changed. ]]
function GarageService.equipBest(self, player: Player): number
	if not self:_profile(player) then
		return 0
	end
	local bays = {}
	for _, index in self:_bayIndices(player) do
		if not self:isWorkshopBay(index) then
			table.insert(bays, index)
		end
	end
	--- What is parked is worth, before and after, for the answer the screen shows.
	local function lotValue(): number
		local total = 0
		for _, car in self:_cars(player) do
			if car.Bay and not self:isWorkshopBay(car.Bay) then
				total += self:marketValueOf(player, self:_entryId(car))
			end
		end
		return total
	end
	local before = lotValue()
	--[[ THE HELD CAR COUNTS (2026-10-15, "equip best doesn't account for the car you're holding").
		WAS skipped outright, so the best car a player owned could be the one in their hands and the
		button walked past it. IS ranked like any other, and if it wins a bay its hands are emptied
		after it is parked (below), `placeCarried`'s order. Hotbar cars always counted: they are in
		`_ownedList`, and `setBayCar` takes one off the bar. ]]
	local carried = self:_carriedKey(player)
	local ranked = {}
	for _, id in self:_ownedList(player) do
		local place = self:locationOf(player, id)
		if place ~= "Workshop" then
			table.insert(ranked, { id = id, value = self:marketValueOf(player, id) })
		end
	end
	table.sort(ranked, function(a, b)
		return a.value > b.value
	end)
	local best = {}
	for i = 1, math.min(#bays, #ranked) do
		best[ranked[i].id] = true
	end

	--- Bays whose car is not in the best set (or which are empty) are the ones to fill.
	local open = {}
	for _, index in bays do
		local car = self:_carAtBay(self:_cars(player), index)
		local id = car and self:_entryId(car)
		if id and best[id] then
			best[id] = nil -- already parked, already counted
		else
			table.insert(open, index)
		end
	end
	local changed = 0
	for i = 1, math.min(#bays, #ranked) do
		local id = ranked[i].id
		if best[id] and #open > 0 then
			local ok = self:setBayCar(player, table.remove(open, 1), id)
			if ok then
				changed += 1
				--- Parked out of their hands: the hands are empty now, as after `placeCarried`.
				if id == carried then
					self:setCarriedCar(player, nil)
				end
			end
		end
	end
	self.log:info(string.format("%s equipped their best cars (%d bay(s) changed).", player.Name, changed))
	self:getRemoteEvent("EquipBestResult"):Fire(player, changed, math.max(0, lotValue() - before))
	return changed
end

--[[ The remote's end of `setBayCar` — the rate-limited front door, exactly as
	`RaceService._onEnterRequest` is for entering a race, and for the same reason: every other
	caller here is the server watching the world, and this one is a client talking. ]]
function GarageService._onSetBayRequest(self, player: Player, bayIndex: unknown, key: unknown)
	local now = os.clock()
	local blockedUntil = self._pickerCooldowns[player]
	if blockedUntil and now < blockedUntil then
		return
	end
	self._pickerCooldowns[player] = now + GarageConfig.Picker.Cooldown

	local ok, reason = self:setBayCar(player, bayIndex :: any, if key == nil then nil else key :: any)
	if not ok then
		self.log:info(string.format("%s's bay change was refused (%s).", player.Name, reason))
	end
end

-- === Lots ===================================================================

-- Repaint one player's whole lot: the cars on the podiums and the numbers on the mats. Called on
-- claim and after any change to what is parked. Six bays — cheap enough that a diff would be
-- more code than it saves, and a rebuild cannot drift out of step with the profile.
function GarageService._rebuildLot(self, player: Player)
	local lot = self._lots[player]
	if not lot then
		return
	end

	local cars = self:_cars(player)
	for _, bay in lot.bays do
		self:_clearBay(bay)
		local car = self:_carAtBay(cars, bay.index)
		if car and type(car.Body) == "string" then
			-- The colour comes off the ENTRY, not off a lookup by body: two Camaros on two podiums are
			-- two different colours, and a per-body table could only ever have answered with one.
			local clone = self:_buildDisplayCar(bay, car.Body, PaintConfig.sanitize(car.Body, car.Paint), car.Mutation)
			--- No sign in the workshop: nothing there is ever for sale to a buyer, so NOT FOR SALE would
			--- be a sign answering a question nobody on that podium can ask.
			if clone and not self:isWorkshopBay(bay.index) and not self:isForSale(player, self:_entryId(car)) then
				self:_hangSaleSign(bay, clone)
			end
			--- Name, rarity, value over every showroom car (`GarageConfig.InfoTag`); on the clone, so it
			--- dies with it. Not the workshop: a car being worked on is not on show.
			local tag = GarageConfig.InfoTag
			if clone and tag and tag.Enabled and not self:isWorkshopBay(bay.index) then
				--- pcall'd: decoration must never abort a lot rebuild (the held tag's first cut did that to holding).
				local ok, err = pcall(function()
					local value = self:marketValueOf(player, self:_entryId(car))
					local gui = CarInfoTag.build(bay.deck, car.Body, car.Paint, value, bay.deck.Size.Y / 2 + tag.ParkedHeight, tag.ParkedSize)
					if gui then
						gui.Adornee = bay.deck
						gui.Parent = clone
					end
				end)
				if not ok then
					self.log:warn(string.format("No info tag on bay %d (%s); the car is parked as normal.", bay.index, tostring(err)))
				end
			end
		end
	end
	self:_refreshLabels(player)
	self:refreshKiosks(player)
	--- The workshop prompt says CUSTOMIZE only with a car on it, so its wording follows the lot too.
	self:_refreshBayPrompts(player)
	--- A car that went onto a bay has left the hotbar by that fact (`_hotbarList`), so the bar repaints.
	self:_publishHotbar(player)
	--- Last, so a subscriber reads a lot that is already rebuilt. See the signal.
	self:getSignal("LotChanged"):Fire(player)
end

--[[ One line on the assembly `root` is part of, for the desync trace: how many parts, how many of
	them anchored, which part is the assembly's root and what tool the character holds. The client
	builds the same line (`DealershipController`), so a server/client pair that disagree about the
	count or the anchoring is the answer. Pure. ]]
local function assemblyLine(root: BasePart): string
	local parts = root:GetConnectedParts(true)
	local anchored = 0
	for _, p in parts do
		if p.Anchored then
			anchored += 1
		end
	end
	local assemblyRoot = root.AssemblyRootPart
	local tool = root.Parent and root.Parent:FindFirstChildOfClass("Tool")
	return string.format(
		"%d parts (%d anchored), assemblyRoot=%s, tool=%s",
		#parts,
		anchored,
		if assemblyRoot then assemblyRoot:GetFullName() else "nil",
		if tool then tool.Name else "none"
	)
end

--[[ THE DESYNC HEAL (`GarageConfig.Picker.HealDesync`, 2026-09-30).

	THE BUG IT HEALS, as the trace pinned it down over several playtests: after a run, the SERVER's copy
	of the character sits frozen on the spawn pad (always the same spot, 49.4 studs from bay 1) while the
	client walks freely. Every check agrees on everything else — the player owns the physics, the parts
	match on both sides, nothing is anchored, nobody is seated — so the working explanation is that the
	client never received "you own this again" after the return beat anchored and released it
	(`RaceService._holdInPlace`): the server believes the client is simulating it, the client does not
	send. The engine then measures every prompt from the frozen copy and drops the press. The source has
	not been found; this is the repair, and it doubles as the test of that theory.

	WHAT IT DOES, only when a podium press arrives that the server's copy is too far away for and the
	client's position is not: take ownership back for a step, stand the server's copy where the client
	says it is, hand ownership to the player again — a fresh ownership message — and then run the press
	through the prompt's own handler (`lot.presses`), so every rule an ordinary press has still applies.
	Two seconds later it logs whether the copy is MOVING again, which is the evidence for the theory.

	TRUST. The client names a prompt and a position. The prompt must be one of THIS player's own, and the
	position must be inside that prompt's reach and within `HEAL_MAX_STUDS` of the server's copy. The
	most a liar gets is to move their OWN character a bounded distance — which a client that owns its
	physics can already do by walking — and to press their own podium, which is theirs to press. ]]
local HEAL_MAX_STUDS = 200 -- further than this is not a desync on a lot, it is a claim to be elsewhere
local HEAL_COOLDOWN = 2 -- seconds; one heal per press burst, not one per mashed E

function GarageService._onBayPromptPressed(self, player: Player, prompt: unknown, clientPosition: unknown)
	if not GarageConfig.Picker.HealDesync or typeof(clientPosition) ~= "Vector3" then
		return
	end
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then
		return
	end
	local lot = self._lots[player]
	local bayIndex = nil
	for index, mine in (if lot then lot.prompts else {}) do
		if mine == prompt or (lot.options and lot.options[index] == prompt) then
			bayIndex = index
		end
	end
	local part = prompt.Parent
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (lot and bayIndex and part and part:IsA("BasePart") and root and root:IsA("BasePart") and humanoid) then
		return
	end

	local reach = prompt.MaxActivationDistance
	local serverDist = (root.Position - part.Position).Magnitude
	if serverDist <= reach + 1 then
		return -- the ordinary press: the prompt's own `Triggered` has it
	end
	if (clientPosition - part.Position).Magnitude > reach + 3 then
		return -- the client is not at the podium either; nothing to heal
	end
	if (clientPosition - root.Position).Magnitude > HEAL_MAX_STUDS or humanoid.SeatPart ~= nil or root.Anchored then
		return
	end
	local Race = Shard.get("RaceService")
	if Race and (Race:isRacing(player) or Race:isReturning(player)) then
		return -- the return beat owns the character; never fight it
	end
	local now = os.clock()
	self._healAt = self._healAt or {}
	if now < (self._healAt[player] or 0) then
		return
	end
	self._healAt[player] = now + HEAL_COOLDOWN

	self.log:warn(
		string.format(
			"%s's server character was stuck %.1f studs from bay %d while their client stood %.1f away; re-syncing ownership.",
			player.Name,
			serverDist,
			bayIndex,
			(clientPosition - part.Position).Magnitude
		)
	)
	task.spawn(function()
		local ok, err = pcall(function()
			root:SetNetworkOwner(nil)
			character:PivotTo(CFrame.new(clientPosition) * root.CFrame.Rotation)
			root.AssemblyLinearVelocity = Vector3.zero
		end)
		if not ok then
			self.log:warn(string.format("Could not re-sync %s (%s).", player.Name, tostring(err)))
			return
		end
		--- One step with the server holding it, so handing it back is a CHANGE and is sent as one.
		RunService.Heartbeat:Wait()
		if not root.Parent then
			return
		end
		pcall(function()
			root:SetNetworkOwner(player)
		end)
		local healedAt = root.Position
		local press = lot.presses and lot.presses[prompt]
		if press and self._lots[player] == lot then
			press(player)
		end
		task.delay(2, function()
			if root.Parent then
				local moved = (root.Position - healedAt).Magnitude
				self.log:info(
					string.format(
						"[DesyncHeal] %s, 2s after the re-sync: server character moved %.1f studs (%s).",
						player.Name,
						moved,
						if moved > 0.5 then "replicating again" else "STILL FROZEN, or standing still"
					)
				)
			end
		end)
	end)
end

--[[ THE SERVER'S SIDE OF THE DEAD-PROMPT TRACE (`GarageConfig.Picker.DebugPrompts`). A client-side
	trace showed a podium prompt TRIGGERING repeatedly on the client while the server's `Triggered`
	handler never ran at all — so the engine refused the press server-side, silently. It does that
	when, by the SERVER's reckoning, the character is out of `MaxActivationDistance`, the prompt is
	disabled, or the prompt is not the instance the client pressed. This logs every one of those
	facts at the moment of the press, and the client's own position beside the server's, so the log
	says which. A diagnostic, off with the flag. ]]
function GarageService._probePrompt(
	self,
	player: Player,
	prompt: unknown,
	clientPosition: unknown,
	clientAssembly: unknown
)
	if not GarageConfig.Picker.DebugPrompts then
		return
	end
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then
		self.log:info(
			string.format(
				"[PromptTrace] %s probe: the prompt the client pressed does not exist on the server.",
				player.Name
			)
		)
		return
	end
	local lot = self._lots[player]
	local live = false
	for _, mine in (if lot then lot.prompts else {}) do
		if mine == prompt then
			live = true
		end
	end
	local part = prompt.Parent
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local promptAt = if part and part:IsA("BasePart") then part.Position else nil
	local serverAt = if root and root:IsA("BasePart") then root.Position else nil
	local owner = "?"
	if root and root:IsA("BasePart") then
		local ok, who = pcall(function()
			return root:GetNetworkOwner()
		end)
		owner = if not ok then "anchored/none" elseif who then who.Name else "SERVER"
	end
	self.log:info(
		string.format(
			"[PromptTrace] %s probe: prompt=%s enabled=%s maxDist=%.0f livePromptOfTheirLot=%s | server char %s from prompt, client says %s | rootAnchored=%s netOwner=%s seated=%s state=%s | server assembly: %s | client assembly: %s",
			player.Name,
			prompt:GetFullName(),
			tostring(prompt.Enabled),
			prompt.MaxActivationDistance,
			tostring(live),
			if serverAt and promptAt then string.format("%.1f studs", (serverAt - promptAt).Magnitude) else "?",
			if typeof(clientPosition) == "Vector3" and promptAt
				then string.format("%.1f studs", (clientPosition - promptAt).Magnitude)
				else "?",
			tostring(root and root:IsA("BasePart") and root.Anchored),
			owner,
			tostring(humanoid and humanoid.SeatPart ~= nil),
			if humanoid then humanoid:GetState().Name else "?",
			if root and root:IsA("BasePart") then assemblyLine(root) else "?",
			tostring(clientAssembly)
		)
	)
end

--[[ THE DESYNC WATCH (`GarageConfig.Picker.DebugPrompts`, 2026-09-28). The prompt probe proved the
	dead bay prompt is not the prompt at all: the server's copy of the character had stopped where it
	was while the client walked on (server 49.4 studs from the podium, client 11.7, netOwner the
	player, root not anchored), and the engine checks `MaxActivationDistance` against the server's
	copy. This logs the MOMENT the two positions part and the moment they rejoin, with what the
	player was doing — holding a car, racing — and the assembly as each side sees it, which is what
	decides whether the server accepts the client's movement at all. Transitions only, so a
	healthy session logs nothing. A diagnostic, off with the flag. ]]
local DESYNC_STUDS = 8 -- well past the few studs of lag a walking character shows at 1 Hz

function GarageService._watchDesync(self, player: Player, clientPosition: unknown, clientAssembly: unknown)
	if not GarageConfig.Picker.DebugPrompts or typeof(clientPosition) ~= "Vector3" then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local gap = (root.Position - clientPosition).Magnitude
	local apart = gap > DESYNC_STUDS
	self._desynced = self._desynced or {}
	if apart == (self._desynced[player] == true) then
		return
	end
	self._desynced[player] = apart or nil

	local Race = Shard.get("RaceService")
	local ok, owner = pcall(function()
		return root:GetNetworkOwner()
	end)
	self.log:info(
		string.format(
			"[PromptTrace] %s DESYNC %s: gap %.1f studs | holding=%s racing=%s netOwner=%s | server assembly: %s | client assembly: %s",
			player.Name,
			if apart then "STARTED" else "ENDED",
			gap,
			tostring(self:getCarriedCar(player)),
			tostring(Race and Race:isRacing(player)),
			if not ok then "anchored/none" elseif owner then owner.Name else "SERVER",
			assemblyLine(root),
			tostring(clientAssembly)
		)
	)
end

-- === The workshop ===========================================================
--[[ THE CUSTOMIZATION BAY'S HALF OF THIS FILE (2026-09-28). `CustomizeConfig` has the design and
	`WorkshopService` the prices; what lives here is what only this file can do — say which podium
	the workshop is, and rewrite a car's ID across a save this file owns every write to. ]]

--- Public: is this bay index the workshop podium? False for everything with the workshop off, which
--- is what makes `CustomizeConfig.Enabled = false` hand the podium back to the showroom whole.
function GarageService.isWorkshopBay(self, bayIndex: number?): boolean
	return CustomizeConfig.Enabled
		and GarageConfig.Enabled
		and bayIndex ~= nil
		and bayIndex == CustomizeConfig.Bay.SlotIndex
end

--[[ Public: the car standing in this player's workshop — `(id, bayIndex)` — or nil for an empty
	workshop, a lot without one, or the workshop switched off. ]]
function GarageService.workshopCar(self, player: Player): (string?, number?)
	local lot = self._lots[player]
	if not lot then
		return nil, nil
	end
	local cars = self:_cars(player)
	for _, bay in lot.bays do
		if self:isWorkshopBay(bay.index) then
			local car = self:_carAtBay(cars, bay.index)
			return if car then self:_entryId(car) else nil, bay.index
		end
	end
	return nil, nil
end

--[[ Public: the owner pressed the workshop (its podium prompt or its kiosk). Fires `WorkshopPressed`
	and answers true when there is a car to customize; answers false for an empty workshop, so the
	caller can do what an ordinary podium would (open the picker) instead. One function for both
	presses, so the prompt and the kiosk cannot come to disagree about what the workshop does. ]]
function GarageService.pressWorkshop(self, player: Player): boolean
	local id = self:workshopCar(player)
	if not id then
		return false
	end
	self:getSignal("WorkshopPressed"):Fire(player)
	return true
end

--- Public: open the Cars Inventory's picker on one of this player's bays — the workshop screen's
--- CHANGE CAR, which is the podium press that the workshop took over (`pressWorkshop`).
function GarageService.openPicker(self, player: Player, bayIndex: number)
	self:getRemoteEvent("OpenDealership"):Fire(player, bayIndex)
end

--[[ Public (WorkshopService): repaint one owned car. Returns `(true, newId)` or `(false, reason)`.

	A REPAINT IS A RE-KEY (`CustomizeConfig` note 4). Colour is part of a car's ID, so the car keeps
	its SERIAL and takes a new key: `Camaro:6#17` -> `Camaro:3#17`. Every table in the save that names
	it moves in this one call — the collection, the lot entry (and its `Paint`), its record, both
	flags, the carry — and then `CarRekeyed` tells the services that hold an ID outside the save.
	A car banked before IDs has no serial to keep, so it is MINTED one here: a legacy key re-keyed to
	another legacy key could collide with a second legacy car of that colour.

	THE PAINT HAS TO BE ONE THE BODY ALLOWS, EXACTLY. `PaintConfig.sanitize` maps a bad index to a
	good one, which is right for reading a save and wrong for a request — a client asking for colour
	99 is refused, not quietly handed stock.

	Nothing here charges or checks the workshop; the caller does both. Any offer standing on the old
	ID is dropped, since a buyer's offer was for a car that, by colour, no longer exists. ]]
function GarageService.repaintCar(self, player: Player, id: string, paint: unknown): (boolean, string)
	local profile = self:_profile(player)
	if not profile then
		return false, "noProfile"
	end
	if not self:_owns(player, id) then
		return false, "notOwned"
	end
	local body, oldPaint, mutation = GarageConfig.parseCarKey(id)
	if not (body and GarageConfig.TierOfBody[body]) then
		return false, "notOnRoster"
	end
	if type(paint) ~= "number" or PaintConfig.sanitize(body, paint) ~= paint then
		return false, "badPaint"
	end
	if paint == oldPaint then
		return false, "samePaint"
	end

	local newKey = GarageConfig.carKey(body, paint, mutation)
	local _oldKey, serial = GarageConfig.splitCarId(id)
	local newId = if serial then GarageConfig.carId(newKey, serial) else self:_mintId(player, newKey)
	if not newId or self:_owns(player, newId) then
		return false, "collision"
	end

	local garage = GarageConfig.Keys.Garage
	local function swap(list: { string }): { string }
		local out = table.clone(list)
		for index, entry in out do
			if entry == id then
				out[index] = newId
			end
		end
		return out
	end

	local owned = swap(self:_ownedList(player))
	profile:Set({ garage, GarageConfig.Keys.Owned }, owned)

	local cars = self:_cars(player)
	for _, car in cars do
		if self:_entryId(car) == id then
			car.Id = newId
			car.Paint = paint
		end
	end
	self:_writeCars(player, cars)

	local records = table.clone(self:_carDataMap(player))
	if records[id] ~= nil then
		records[newId] = records[id]
		records[id] = nil
		profile:Set({ garage, GarageConfig.Keys.CarData }, records)
	end

	for flag in FLAG_KEYS do
		profile:Set({ garage, flag }, swap(self:_flagList(player, flag)))
	end

	local offers = self:getOffers(player)
	if offers[id] ~= nil then
		offers[id] = nil
		self:setOffers(player, offers)
	end

	--[[ Same slot, new ID. Swapped in the RAW stored list, not through `_hotbarList`: the collection
		already names `newId` by this line, so the normalised list has dropped the old ID as not owned
		and would lose the slot. And BEFORE the carry is re-keyed, because `setCarriedCar` folds the
		held car into the bar and would otherwise add it a second time at the end. ]]
	local rawBar = profile:Get({ garage, CarryConfig.Hotbar.ProfileKey })
	if type(rawBar) == "table" and table.find(rawBar, id) then
		profile:Set({ garage, CarryConfig.Hotbar.ProfileKey }, swap(rawBar))
	end

	if self:_carriedKey(player) == id then
		self:setCarriedCar(player, newId)
	end

	self:_publishOwned(player, owned)
	self:_publishFlags(player)
	self:_rebuildLot(player)
	self:getSignal("CarRekeyed"):Fire(player, id, newId)
	self.log:info(string.format("%s repainted %s -> %s.", player.Name, id, newId))
	return true, newId
end

-- === Buyers' offers =========================================================
--[[ `Garage.Offers`, read and written for `BuyerService`. The rule is `BuyerService`'s — what an
	offer is, when it stands and when it goes; this is only the storage, because this file owns every
	read and write of the profile's `Garage` table (header) and a second service reaching into it
	would be a second writer to keep in step.

	THE READ IS A COPY, for `getCarData`'s reason: a caller editing the live table would change the
	save without `profile:Set` running and the Replica never hearing of it. ]]
function GarageService.getOffers(self, player: Player): { [string]: any }
	local profile = self:_profile(player)
	local garage = profile and profile:Get({ GarageConfig.Keys.Garage })
	local stored = garage and garage[BuyerConfig.ProfileKey]
	return if type(stored) == "table" then table.clone(stored) else {}
end

--- Replace the whole offers map. Returns whether there was a profile to write to.
function GarageService.setOffers(self, player: Player, offers: { [string]: any }): boolean
	local profile = self:_profile(player)
	if not profile then
		return false
	end
	profile:Set({ GarageConfig.Keys.Garage, BuyerConfig.ProfileKey }, offers)
	return true
end

--[[ The NOT FOR SALE board over one podium. `GarageConfig.NotForSaleSign` has the look and why it
	is a placeholder BillboardGui.

	PARENTED TO THE DISPLAY CAR, adorned to the DECK. The parent is what makes it die with the car
	(`_clearBay`); the adornee is what makes its height a fact about the podium rather than about a
	bounding box — a display clone has no PrimaryPart to hang a billboard on, and working one out per
	body would be the measurement `CarDisplay` already does for a different purpose. ]]
function GarageService._hangSaleSign(self, bay: Bay, clone: Model)
	local sign = GarageConfig.NotForSaleSign
	if not sign.Enabled then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "NotForSaleSign"
	gui.Adornee = bay.deck
	gui.Size = UDim2.fromScale(sign.Size.X, sign.Size.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, bay.deck.Size.Y / 2 + sign.Height, 0)
	gui.MaxDistance = sign.MaxDistance
	gui.LightInfluence = 0

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = sign.Panel
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = panel

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Position = UDim2.fromScale(0.05, 0.1)
	label.BackgroundTransparency = 1
	label.FontFace = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)
	label.Text = sign.Text
	label.TextColor3 = sign.TextColor
	label.TextScaled = true
	label.Parent = panel

	gui.Parent = clone
end

-- The lot's total dollars per second, on the Player for the HUD to read. Published here rather than
-- computed per frame anywhere because it only changes when what is parked changes.
function GarageService._publishRate(self, player: Player, cars: { Car }?)
	if player.Parent ~= Players then
		return
	end
	--[[ A lot that earns nothing per second publishes nothing per second. Cleared rather than set to
		0 so that a reader asking "is there a rate" gets no, not "a rate of zero" — the HUD hides its
		line on the flag anyway, and an attribute of 0 would be one more place claiming a number. ]]
	if not GarageConfig.Income.Passive then
		player:SetAttribute(GarageConfig.RateAttribute, nil)
		return
	end
	--[[ Summed PER BAY rather than scaled at the end, because the multiplier is no longer the same
		for every car: each bay carries its own kiosk level on top of the lot-wide `Income` upgrade.
		`_pending` applies the identical `_bayMultiplier`, so the HUD's per-second line and the money
		the mats actually pay out cannot disagree. ]]
	local rate = 0
	for _, car in cars or self:_cars(player) do
		rate += GarageConfig.rateOf(car.Tier, car.Mutation) * self:_bayMultiplier(player, car.Bay)
	end
	player:SetAttribute(GarageConfig.RateAttribute, rate)
end

function GarageService._refreshLabels(self, player: Player)
	local lot = self._lots[player]
	-- The mats are hidden without passive income (`_hideMats`); a label nobody can see is not drawn.
	if not lot or not GarageConfig.Income.Passive then
		return
	end
	local cars = self:_cars(player)
	for _, bay in lot.bays do
		if bay.label then
			local car = self:_carAtBay(cars, bay.index)
			bay.label.Text = if car
				then GarageConfig.formatCash(self:_pending(player, car))
				else GarageConfig.Collect.EmptyText
		end
	end
end

-- === The kiosk ==============================================================

--[[ Draw one bay's upgrade sign for its owner.

	TWO LINES AND A COLOUR, all three derived from two numbers — the bay's level and the owner's
	balance — so there is no board state to keep in step with anything, and a redraw can never be
	stale in a way a diff would hide.

	IT NO LONGER READS WHAT IS PARKED, which is the whole of what the 2026-08-21 simplification did to
	this function: the headline used to be that car's dollars per second, with a second format for an
	empty bay so the sign never read `$0/s`. A bay's LADDER is a property of the podium (see
	`UpgradeConfig.Bay.ProfileKey`), so with the rate gone there is nothing left on this sign that an
	empty bay has to say differently. `refreshKiosks` is still called when the lot is rebuilt, and
	still has to be: that is also the path a plot takes from unowned to owned. ]]
function GarageService._drawKiosk(self, bay: Bay, player: Player?)
	local kiosk = bay.kiosk
	if not kiosk then
		return
	end

	local names = UpgradeConfig.Bay
	local enabled = GarageConfig.Enabled and UpgradeConfig.Enabled and names.Enabled

	--[[ THE WORKSHOP'S KIOSK IS ITS SIGN (2026-09-28, `CustomizeConfig.Kiosk`): a bay nobody tips has
		no tip level to sell, so the same board says what the podium is for and pressing it opens the
		screen (`UpgradeService._onBayRequest`). Written into the board's own two labels, so no art
		changes and switching the workshop off puts the level ladder straight back.

		ABOVE THE BLANKING BELOW, because it is not an upgrade: with the per-bay ladder switched off
		(`UpgradeConfig.Bay.Enabled`) every other board is gone and this one still has a job. An
		unowned lot still blanks it, for the same reason it blanks the rest. ]]
	if player and self:isWorkshopBay(bay.index) then
		local sign = CustomizeConfig.Kiosk
		if kiosk.cost then
			kiosk.cost.Text = sign.Title
		end
		if kiosk.level then
			kiosk.level.Text = UpgradeConfig.oneLine(sign.Subtitle)
		end
		if kiosk.button then
			kiosk.button.BackgroundColor3 = sign.Color
		end
		--- The kit face says the same thing in the kit's words. Both faces are drawn; the client
		--- shows one (`NewUIConfig.KitWorkshopSign`).
		local kit = kiosk.kit
		if kit then
			kit.content.Visible = true
			for _, label in kit.labels do
				local text = CustomizeConfig.kioskText(label:GetAttribute(sign.KitTextAttribute))
				if text then
					label.Text = text
				end
			end
		end
		return
	end

	--[[ An unowned lot blanks rather than showing level 1: the numbers on this sign belong to
		whoever holds the plot, and a vacant forecourt advertising somebody's ladder is the same
		mistake `_blankLot` exists to stop the mats making. ]]
	if not (enabled and player) then
		if kiosk.cost then
			kiosk.cost.Text = ""
		end
		if kiosk.level then
			kiosk.level.Text = ""
		end
		if kiosk.button then
			kiosk.button.BackgroundColor3 = names.Colors.Vacant
		end
		-- The kit face's blank is its bare panel: the card and everything on it go.
		if kiosk.kit then
			kiosk.kit.content.Visible = false
		end
		return
	end

	local level = self:getBayLevel(player, bay.index)
	local cost = UpgradeConfig.bayCostOf(level)

	if kiosk.cost then
		kiosk.cost.Text = if cost == nil then names.MaxCostText else GarageConfig.formatCash(cost)
	end
	if kiosk.level then
		--- Without passive income the line names the tip multiplier a level buys rather than the level
		--- number (`UpgradeConfig.Bay.TipsFormat` has why).
		local now = UpgradeConfig.formatTipMultiplier(UpgradeConfig.bayMultiplier(level))
		local text = if GarageConfig.Income.Passive
			then (if cost == nil
				then string.format(names.MaxLevelFormat, level)
				else string.format(names.LevelFormat, level, level + 1))
			else (if cost == nil
				then string.format(names.TipsMaxFormat, now)
				else string.format(
					names.TipsFormat,
					now,
					UpgradeConfig.formatTipMultiplier(UpgradeConfig.bayMultiplier(level + 1))
				))
		kiosk.level.Text = UpgradeConfig.oneLine(text)
	end

	if kiosk.button then
		--[[ The same sentence the billboard speaks, in the kiosk's OWN palette: orange while there is
			a level to buy, green once there is not. `UpgradeConfig.Bay.Colors` argues why that is a
			separate table and why the balance is not in it.

			IT DELIBERATELY DOES NOT READ THE CASH. A press the player cannot afford opens a cash
			pack (`UpgradeService._onBayRequest`), so dimming the plaque would advertise a dead
			control in front of a live one. The price is already on the sign, in dollars, which is
			the only form of it a player can act on.

			It is the whole plaque rather than a strip along the bottom of one, which is what lets
			this sign be read without being read. ]]
		kiosk.button.BackgroundColor3 = if cost == nil then names.Colors.Done else names.Colors.Buy
	end
end

--[[ Public: repaint every kiosk on this player's lot.

	Called from three places and only three: a purchase (`setBayLevel`), a rebuild of the lot
	(`_rebuildLot`), and a change to the balance (`addCash`). The last of those has been redundant
	since the plaque stopped following the balance on 2026-08-26 and is kept as the self-heal, the
	same call the forecourt billboard keeps for the same reason. The rebuild is in that list for
	the plot changing HANDS rather than for the car changing: since 2026-08-21 nothing on this board
	is derived from what is parked, but a lot going from unowned to owned still has to redraw from
	blank. Deliberately NOT in `_labelLoop`: the mats tick every second because their number really
	does change every second, and nothing on this board does. ]]
function GarageService.refreshKiosks(self, player: Player)
	local lot = self._lots[player]
	if not lot then
		return
	end
	for _, bay in lot.bays do
		self:_drawKiosk(bay, player)
	end
end

-- Blank every mat, kiosk and podium on a plot. Runs on release, so the next owner never walks into a
-- lot showing the last player's cars, the last player's money or the last player's levels.
--[[ Take the collect mats out of the world when there is nothing to collect (2026-09-28;
	`GarageConfig.Income.Passive`). The card asked for the pads to be REMOVED; they are authored into
	every podium (`GarageConfig.Collect`), so this hides them at runtime rather than deleting map art
	a Studio edit would have to put back for the A/B.

	HIDDEN, NOT DESTROYED, AND STILL SOLID. Transparency and the label's gui go, and so does
	`CanTouch` so no foot ever fires the handler; `CanCollide` is left alone because the mat is a
	slab in the aisle and players walk across it — pulling its collision would drop them the mat's
	thickness onto the floor under it. The bay's upgrade kiosk stands on the mat as a model of its own
	and is not touched here: it still sells a level, and a level still means something (tips).

	Idempotent, and a no-op with passive income on, so it is safe to call on every discovery. ]]
function GarageService._hideMats(self, bays: { Bay })
	if GarageConfig.Income.Passive then
		return
	end
	for _, bay in bays do
		local mat = bay.button
		if not mat then
			continue
		end
		mat.Transparency = 1
		mat.CanTouch = false
		for _, inst in mat:GetDescendants() do
			if inst:IsA("LayerCollector") then
				inst.Enabled = false
			elseif inst:IsA("Decal") or inst:IsA("Texture") then
				inst.Transparency = 1
			end
		end
	end
end

--[[ Public: what a customer's tip is priced off at one bay — the car standing there, its ID, and its
	market value times that bay's kiosk multiplier. `(nil, nil, 0)` for an empty bay.

	THIS REPLACED `getBayCar`'s rate AS THE CROWD'S INPUT (2026-09-28). A tip used to be seconds of
	the bay's income; there is no income, so it is a fraction of what the car is WORTH
	(`CustomerConfig.Tip`) — which is also what makes a battered car draw smaller tips than a clean
	copy of the same model, the same way it fetches less at the sell lot.

	THE KIOSK STILL COUNTS. A bay's upgrade level multiplied its income and now multiplies its tips,
	by the same `UpgradeConfig.bayMultiplier`, so every level a player bought still buys what it did
	in proportion. The lot-wide `Income` upgrade does NOT come along: it is off the board
	(`UpgradeConfig.Order`) and was a multiplier on podium income specifically. Since the per-bay
	ladder was switched off (2026-09-28, `UpgradeConfig.Bay.Enabled`) `bayMultiplier` answers 1, so
	for now a tip is the car's value alone — the kiosk term is still here for the day it comes back. ]]
function GarageService.getBayTip(self, player: Player, bayIndex: number): (Car?, string?, number)
	local car = self:_carAtBay(self:_cars(player), bayIndex)
	--[[ THE WORKSHOP ANSWERS EMPTY (2026-09-28). This is the one question the crowd, the offline
		simulation and the buyers' candidate list all ask of a bay, so answering "nothing here" for the
		workshop podium keeps every one of them off it without any of them knowing it exists. ]]
	if not car or self:isWorkshopBay(bayIndex) then
		return nil, nil, 0
	end
	local id = self:_entryId(car)
	--- x the car's world tip scale (`CustomerConfig.Tip.ByWorld`, 2026-10-08): here, once, so the crowd,
	--- the offline sum and the HUD rate all price the same look.
	local scale = CustomerConfig.tipScaleOf(car.Body)
	return car, id, self:marketValueOf(player, id) * UpgradeConfig.bayMultiplier(self:getBayLevel(player, bayIndex)) * scale
end

function GarageService._blankLot(self, bays: { Bay })
	for _, bay in bays do
		self:_clearBay(bay)
		if bay.label then
			bay.label.Text = GarageConfig.Collect.EmptyText
		end
		self:_drawKiosk(bay, nil)
	end
end

--[[ Public: the podiums standing on this plot have changed — look again.

	The one caller is `UpgradeService`, either side of building or removing a second storey. Bays are
	discovered once at init because a plot's geometry never used to change; a `Floor2` purchase is
	the first thing that makes it change under a live lot, and this is the whole of what that costs.

	IT RE-CLAIMS RATHER THAN PATCHING THE LIST, and that is deliberate. Everything a lot owns — a
	Touched handler per mat, a prompt per deck, the cars on the podiums — hangs off the assignment's
	trove, so releasing and re-claiming rebuilds all of it from the new list in one step and cannot
	leave a handler pointing at a podium that no longer exists. Six extra bays is a rebuild of
	twelve; a diff would be more code than it saves and could drift.

	The release also blanks the OLD bays before the new list replaces them, which is what stops a
	torn-down upstairs deck from taking the player's cars with it — `_rebuildLot` at the end of
	`_claim` reads the profile, so anything that was parked upstairs comes back the moment the
	storey does. ]]
function GarageService.refreshBays(self, plot: Model)
	if not GarageConfig.Enabled or not self._baysByPlot[plot] then
		return
	end

	local owner: Player? = nil
	for player, lot in self._lots do
		if lot.plot == plot then
			owner = player
			break
		end
	end

	if owner then
		self:_release(owner)
	end
	self._baysByPlot[plot] = self:_discoverBays(plot)
	self:_hideMats(self._baysByPlot[plot])
	if owner then
		self:_claim(owner, plot)
	end
end

--[[ Public: what this player's lot is holding right now, without taking any of it.

	Returns `(total, bays)` — whole dollars, and how many bays are holding at least `MinPayout` of
	it. `(0, 0)` for a player with no lot, which is every player before `PlotAssigned`.

	IT IS `collectAll` WITH THE PAYMENT TAKEN OUT, and it is written that way on purpose: same bay
	list, same per-bay floor, same `MinPayout` refusal. So the number the WELCOME BACK screen shows
	is arithmetically the number pressing its button will hand over, and the two cannot drift into
	the position where a screen advertises money the sweep then declines to pay. The only difference
	between them is the seconds that pass while the player reads it, which can only ever make the
	payout larger.

	The one caller is `OfflineService`. It is here rather than there because `_pending` is the
	economy and there is exactly one copy of it. ]]
function GarageService.getPending(self, player: Player): (number, number)
	local lot = self._lots[player]
	-- Nothing accrues without passive income, so nothing is pending; see `_collect`.
	if not lot or not GarageConfig.Income.Passive then
		return 0, 0
	end

	local cars = self:_cars(player)
	local total, bays = 0, 0
	for _, bay in lot.bays do
		-- Floored per bay, not at the end: `_collect` floors each payout on its own, so summing the
		-- raw values would over-report by up to a dollar a bay.
		local amount = math.floor(self:_pending(player, self:_carAtBay(cars, bay.index)))
		if amount >= GarageConfig.Collect.MinPayout then
			total += amount
			bays += 1
		end
	end
	return total, bays
end

--[[ Public: pay out every bay on this player's lot at once, and return the total.

	The AUTO COLLECT upgrade's whole implementation on this side. It is a loop over `_collect` and
	nothing more — no separate payout path, no second formula — so an automatic sweep and a foot on
	a mat are worth exactly the same and can never disagree.

	Silent when the lot is empty or nothing has accrued: `_collect` already refuses below
	`MinPayout`, so a sweep of six untouched bays writes nothing and pays nothing. ]]
function GarageService.collectAll(self, player: Player): number
	local lot = self._lots[player]
	if not lot then
		return 0
	end

	local total = 0
	for _, bay in lot.bays do
		total += self:_collect(player, bay.index)
	end
	if total > 0 then
		self:_refreshLabels(player)
	end
	return total
end

--[[ Bind a plot to its owner.

	Everything stamped onto the world goes in the assignment's trove, the same shape `PlotService`
	uses for the same reason: the list of things a lot touches is going to grow (bay upgrade prompts,
	the deck-2 unlock, per-bay billboards), and every one of them is a leak on `PlayerRemoving` if
	release is a hand-written list of undo statements. ]]
function GarageService._claim(self, player: Player, plot: Model)
	if self._lots[player] then
		return
	end

	local bays = self._baysByPlot[plot]
	if not bays or #bays == 0 then
		self.log:warn(string.format("%s claimed %s, which has no usable bays.", player.Name, plot.Name))
		return
	end

	local trove = Trove.new()
	--- `prompts` is [bay index] = the podium's ProximityPrompt, kept because its wording changes with
	--- what the player is holding (`_refreshBayPrompts`). Built below with the prompts themselves and
	--- thrown away with them, so it can never name one that has been destroyed.
	self._lots[player] = { plot = plot, bays = bays, trove = trove, cooldowns = {}, prompts = {} }

	--[[ ONLY THE OWNER COLLECTS. A visitor standing on someone else's mat gets nothing and no
		message — the mat simply is not theirs. Worth stating because the alternative (anyone can
		collect, it just pays the owner) is a perfectly reasonable social feature and is NOT what
		this does. ]]
	for _, bay in bays do
		if not bay.button then
			continue
		end
		local bayIndex = bay.index
		trove:Add(bay.button.Touched:Connect(function(hit: BasePart)
			local toucher = self:_playerFromHit(hit)
			if toucher ~= player then
				return
			end

			local lot = self._lots[player]
			if not lot then
				return
			end
			local now = os.clock()
			if now - (lot.cooldowns[bayIndex] or 0) < GarageConfig.Collect.Cooldown then
				return
			end
			lot.cooldowns[bayIndex] = now

			if self:_collect(player, bayIndex) > 0 then
				self:_refreshLabels(player)
			end
		end))
	end

	--[[ The podium's prompts: TWO per podium since 2026-10-07, drawn together as one glass card
		(`GlassPromptController`, `GlassPromptConfig`).

		ON THE DECK, NOT ON THE MAT. The mat is already the collect verb — it pays out the moment you
		stand on it — and hanging a second interaction off the same part would mean walking up to take
		your money and being offered a menu at the same time. The deck is the podium the car stands
		on, which is the thing the screen is about.

		THE MAIN PROMPT (E) does the thing your hands say: Place Car while holding one, Pick Up (a hold)
		at a car, Park a Car at an empty bay. THE OPTION PROMPT (F) is the menu for the car standing
		there, Customize in the workshop and Change Car anywhere else, and is hidden whenever the main
		prompt already is the menu. Two prompts on two KEYS, never one key: two prompts sharing a key
		on one podium is the failure `LobbyCarService._wireEntry` measured, the engine draws one of them.

		Owner-only, and checked on the server rather than by hiding the prompt: `prompt.Enabled` is a
		replicated property a client can flip, so the `Triggered` guard is the real gate. The glass card
		hides other people's podiums off `GlassPromptConfig.Attributes.Owner`, and owns `Enabled` on the
		client for the focus rule, which is why nothing here writes it after creation. ]]
	if GarageConfig.Picker.Enabled then
		local attrs = GlassPromptConfig.Attributes
		local glass = GarageConfig.Picker.Glass
		local function newPrompt(name: string, deck: BasePart, order: number): ProximityPrompt
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = name
			prompt.MaxActivationDistance = GarageConfig.Picker.PromptMaxDistance
			prompt.RequiresLineOfSight = false
			if glass then
				prompt.Style = Enum.ProximityPromptStyle.Custom
				prompt:SetAttribute(attrs.Order, order)
				prompt:SetAttribute(attrs.Owner, player.UserId)
				prompt:AddTag(GlassPromptConfig.Tag)
			else
				--- Roblox's own prompt (`GarageConfig.Picker.Glass`); the owner's clients alone keep it on.
				prompt.Style = Enum.ProximityPromptStyle.Default
				prompt:SetAttribute(GarageConfig.Picker.OwnerAttribute, player.UserId)
				prompt:AddTag(GarageConfig.Picker.PromptTag)
			end
			prompt.Parent = deck
			return prompt
		end

		for _, bay in bays do
			local prompt = newPrompt("ChangeCarPrompt", bay.deck, 1)
			prompt.HoldDuration = GarageConfig.Picker.PromptHoldDuration
			--- F and X exist only on the glass card (`GarageConfig.Picker.Glass`); the plain prompt is E alone.
			local option = if glass then newPrompt(GarageConfig.Picker.Option.Name, bay.deck, 2) else nil
			if option then
				option.KeyboardKeyCode = GarageConfig.Picker.Option.KeyboardKey
				option.GamepadKeyCode = GarageConfig.Picker.Option.GamepadKey
				option.HoldDuration = 0
			end
			--- X: the sale toggle (`GarageConfig.Picker.Sale`), third on the card.
			local saleCfg = GarageConfig.Picker.Sale
			local sale = if glass and saleCfg.Enabled and InventoryConfig.Enabled then newPrompt(saleCfg.Name, bay.deck, 3) else nil
			if sale then
				sale.KeyboardKeyCode = saleCfg.KeyboardKey
				sale.GamepadKeyCode = saleCfg.GamepadKey
				sale.HoldDuration = 0
			end

			local bayIndex = bay.index
			--- Every branch below says which it took while `Picker.DebugPrompts` is on. See that flag.
			local function trace(what: string)
				if GarageConfig.Picker.DebugPrompts then
					self.log:info(string.format("[PromptTrace] %s pressed bay %d: %s", player.Name, bayIndex, what))
				end
			end
			--- The two refusals both prompts share: somebody else's press, and a lot already let go.
			local function mine(presser: Player): boolean
				if presser ~= player then
					trace(string.format("ignored, pressed by %s (not the owner)", presser.Name))
					return false
				end
				if not self._lots[player] then
					trace("ignored, the owner has no lot any more")
					return false
				end
				return true
			end
			--- The carry's floor, shared by the place and the pick-up: both rebuild the lot.
			local function carryReady(): boolean
				local now = os.clock()
				if now < (self._carryCooldowns[player] or 0) then
					trace("ignored, inside the carry cooldown")
					return false
				end
				self._carryCooldowns[player] = now + CarryConfig.Prompt.Cooldown
				return true
			end
			--[[ The menu: the workshop on the WORKSHOP podium with a car on it, otherwise the picker.
				The workshop screen has CHANGE CAR for the picker (`openPicker`), so nothing is lost by it.

				THIS PODIUM ONLY — FIXED 2026-09-28. It used to ask `pressWorkshop` on every podium, and
				that answers "is there a car in the workshop", not "is this the workshop" — so once a car
				stood in the workshop, every other bay opened the workshop screen instead of the picker. ]]
			local function openMenu()
				if self:isWorkshopBay(bayIndex) and self:pressWorkshop(player) then
					trace("opened the workshop")
					return
				end
				trace("sent OpenDealership to the client")
				self:getRemoteEvent("OpenDealership"):Fire(player, bayIndex)
			end

			--[[ E. HANDS FIRST: a player holding a car has one thing to do with a podium, and being
				offered a screen instead is the feature's own worst failure. Then the car on the bay comes
				off into empty hands (the prompt is a hold there, `GarageConfig.Picker.PickUp`). An empty
				bay is the menu, which is how a car gets onto one at all. ]]
			local function onPressed(presser: Player)
				if not mine(presser) then
					return
				end
				if self:getCarriedCar(player) then
					if not carryReady() then
						return
					end
					local ok, reason = self:placeCarried(player, bayIndex)
					trace(string.format("placeCarried -> %s (%s)", tostring(ok), reason))
					if ok or reason ~= "notCarrying" then
						return
					end
				end
				if GarageConfig.Picker.PickUp.Enabled and self:_carAtBay(self:_cars(player), bayIndex) then
					if not carryReady() then
						return
					end
					local ok, reason = self:pickUpBay(player, bayIndex)
					trace(string.format("pickUpBay -> %s (%s)", tostring(ok), reason))
					if ok or reason ~= "alreadyEmpty" then
						return
					end
				end
				openMenu()
			end

			--- F. Only ever the menu; the card hides it whenever E already is.
			local function onOption(presser: Player)
				if mine(presser) then
					openMenu()
				end
			end

			--[[ X. Flip the car on this podium on or off sale, through `setCarFlag` (the inventory's own
				path, so the sign and any waiting buyer follow), then re-letter the card. Refused for the
				workshop, an empty bay and full hands, the three states the card hides it in. ]]
			local function onSale(presser: Player)
				if not mine(presser) or self:isWorkshopBay(bayIndex) or self:getCarriedCar(player) then
					return
				end
				local car = self:_carAtBay(self:_cars(player), bayIndex)
				if not car then
					return
				end
				local id = self:_entryId(car)
				local forSale = self:isForSale(player, id)
				local ok, reason = self:setCarFlag(player, id, InventoryConfig.Keys.NotForSale, forSale)
				trace(string.format("sale toggle -> %s (%s), now %s", tostring(ok), reason, if forSale then "off sale" else "for sale"))
				self:_refreshBayPrompts(player)
			end

			trove:Add(prompt.Triggered:Connect(onPressed))
			trove:Add(prompt)
			self._lots[player].prompts[bay.index] = prompt
			self._lots[player].options = self._lots[player].options or {}
			if option then
				trove:Add(option.Triggered:Connect(onOption))
				trove:Add(option)
				self._lots[player].options[bay.index] = option
			end
			if sale then
				trove:Add(sale.Triggered:Connect(onSale))
				trove:Add(sale)
				self._lots[player].sales = self._lots[player].sales or {}
				self._lots[player].sales[bay.index] = sale
				self._lots[player].presses = self._lots[player].presses or {}
				self._lots[player].presses[sale] = onSale
			end
			--- The same presses, reachable by the desync heal once the server agrees where they are
			--- (`_onBayPromptPressed`), so a healed press runs every rule an ordinary one does.
			self._lots[player].presses = self._lots[player].presses or {}
			self._lots[player].presses[prompt] = onPressed
			if option then
				self._lots[player].presses[option] = onOption
			end
		end
	end

	trove:Add(function()
		self:_blankLot(bays)
	end)

	self:_rebuildLot(player)
	--[[ ...and the prompts are lettered for whatever this player is already holding. A claim can
		happen either side of the profile arriving (a join, a plot swap, a second storey being built),
		so both paths letter them: this one for a claim that comes last, `_watchProfile` for a profile
		that does. Cheap, and idempotent. ]]
	self:_refreshBayPrompts(player)
	self.log:info(string.format("%s took %d bays on %s.", player.Name, #bays, plot.Name))
end

function GarageService._release(self, player: Player)
	local lot = self._lots[player]
	if not lot then
		return
	end
	self._lots[player] = nil
	lot.trove:Destroy()
end

-- Character part -> the player who owns it. Same helper RaceService keeps for its entry trigger.
function GarageService._playerFromHit(self, hit: BasePart): Player?
	local character = hit and hit.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid then Players:GetPlayerFromCharacter(character) else nil
end

--[[ Wait for the profile off the join path, then wire the player up.

	`GetProfileAsync` yields until the profile loads, which can take seconds, so this runs in its own
	thread — the same shape `PlotService._applyProfileName` uses and for the same reason.

	The re-checks after the yield are not paranoia. A player who joins and immediately leaves has
	their plot released and handed to the next player inside that window; without them this thread
	wakes up and paints the departed player's cars onto the new owner's podiums. ]]
function GarageService._watchProfile(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players then
			return
		end

		self._profiles[player] = profile
		--[[ FIRST, and before anything is published: it can WRITE the catalogue, and the publish
			below has to broadcast what it wrote rather than what was there a moment earlier. It is a
			no-op for every profile this build has already loaded once. ]]
		self:_migrateFound(player)

		self:_publishCash(player, self:getCash(player))
		self:_publishRate(player)
		self:_publishOwned(player)
		self:_publishFound(player)
		self:_publishFlags(player)
		self:_publishLot(player)
		self:_publishLevels(player)
		self:_publishUpgrades(player)
		--[[ What they were holding when they last logged off, which is a car they are still holding:
			the record is a profile key, so a carry survives a rejoin and even a server restart. The
			model itself is built by `CarryService` off the `CarryChanged`/`ProfileReady` pair. ]]
		self:_publishCarried(player, self:getCarriedCar(player))
		self:_publishHotbar(player)
		self:_refreshBayPrompts(player)
		self:_rebuildLot(player)

		-- Last, so anything waiting on it can assume every broadcast above has already happened.
		self:getSignal("ProfileReady"):Fire(player)
	end)
end

--- Public: has this player's profile arrived? The catch-up half of the `ProfileReady` signal, for a
--- service that connects after the thread above has already run (a hot reload, or a slower `start`).
function GarageService.isProfileReady(self, player: Player): boolean
	return self:_profile(player) ~= nil
end

-- === Lifecycle ==============================================================

--[[ Redraw the mats.

	PURELY COSMETIC — see the header. It reads the same clock `_pending` does and writes text; it
	never touches the profile and it is not what makes the money correct. One second between passes
	because a per-second income is what a per-second number should look like, and ~36 label writes a
	second across a full server is nothing. ]]
function GarageService._labelLoop(self)
	local accumulator = 0
	return RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < GarageConfig.LabelInterval then
			return
		end
		accumulator = 0
		for player in self._lots do
			self:_refreshLabels(player)
		end
	end)
end

--[[ THE AUTO COLLECT PASS, and the whole of it on this side (`GarageConfig.Collect.Auto`).

	ONE LOOP OVER `collectAll`, WHICH IS ONE LOOP OVER `_collect`, WHICH IS WHAT A FOOT ON A MAT
	RUNS. There is no second payout path and no second formula anywhere in this feature, so an
	automatic payout and a manual one cannot drift apart — they are the same call. That is the same
	guarantee `getPending` gives the WELCOME BACK screen, made the same way.

	IT SWEEPS EVERY LOT IT KNOWS ABOUT AND ASKS THE PASS PER PLAYER, rather than keeping a list of
	owners. `self._lots` is already the set of players with a bound plot — the exact set that can be
	paid — and a separate owner list would be a second thing to keep in step with joins, leaves,
	plot releases and a pass bought mid-session. `PassService.owns` is a non-yielding cache read, so
	asking it six times a minute for everyone on the server costs nothing worth measuring.

	A MISSING `PassService` PAYS NOBODY, which is the safe direction: the mats still work, and the
	feature is simply off. Fetched inside the tick rather than captured once, so a service that
	starts late is picked up on the next sweep instead of never.

	NOTHING IS LOGGED PER SWEEP. Six bays every thirty seconds for every owner on a sixty player
	server is a log nobody can read, and `_collect` already fires `CashCollected` for anything that
	actually wants to watch the money — which is what `AnalyticsService` books it from. ]]
function GarageService._sweepLoop(self)
	local accumulator = 0
	return RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < GarageConfig.Collect.Auto.Interval then
			return
		end
		accumulator = 0

		local PassService = Shard.get("PassService")
		if not PassService then
			return
		end

		for player in self._lots do
			if PassService:owns(player, GarageConfig.Collect.Auto.Key) then
				self:collectAll(player)
			end
		end
	end)
end

GarageService:withLifecycle({
	init = function(self)
		self._lots = {} :: {
			[Player]: {
				plot: Model,
				bays: { Bay },
				trove: any,
				cooldowns: { [number]: number },
				prompts: { [number]: ProximityPrompt },
			},
		}
		self._baysByPlot = {} :: { [Model]: { Bay } }
		self._profiles = {} :: { [Player]: any }
		self._pickerCooldowns = {} :: { [Player]: number }
		self._equipCooldowns = {} :: { [Player]: number } -- `RequestEquipBest`'s floor
		--- Separate from the picker's, because the two prompts cost different things. See the
		--- `Triggered` handler in `_claim`.
		self._carryCooldowns = {} :: { [Player]: number }
		self._bayCount = 0
		self._trove = Trove.new()

		if not GarageConfig.Enabled then
			self.log:info("Disabled by config — no bays are bound.")
			return
		end

		--[[ `withDependencies` orders init, so PlotService has already discovered its plots by now.
			The empty-table fallback is for the case it has not — a disabled or failed PlotService
			returns nil here, and iterating that would take this service down with it rather than
			leaving the game with a working race loop and no garage. ]]
		local PlotService = Shard.get("PlotService")
		local plots = PlotService and PlotService:getPlots()
		if not plots then
			self.log:warn("No plots from PlotService — bays cannot be bound to owners.")
			return
		end

		for _, record in plots do
			local bays = self:_discoverBays(record.model)
			self._baysByPlot[record.model] = bays
			self:_hideMats(bays)
			self._bayCount = math.max(self._bayCount, #bays)
			self:_blankLot(bays)
		end

		--[[ Loud, because the symptom is a long way from the cause: a plot with fewer bays than the
			rest silently caps that player's garage, and `_bayCount` (the capacity every player is
			checked against) is the MAXIMUM across the plots, so the mismatch shows up as one
			player's bank being sold instead of parked. Re-run `PropagateCarSlots`. ]]
		for _, record in plots do
			local bays = self._baysByPlot[record.model]
			if bays and #bays ~= self._bayCount then
				self.log:warn(
					string.format(
						"%s has %d bays but the biggest lot has %d — run PropagateCarSlots.",
						record.model.Name,
						#bays,
						self._bayCount
					)
				)
			end
		end

		self.log:info(string.format("%d bays per lot.", self._bayCount))
	end,

	start = function(self)
		--[[ Every car a player can own should have a game name (`CarNameConfig`, 2026-09-28). A body
			added to a ladder without one shows its REAL name — the trademark that file exists to keep
			off screen — and nothing else would notice, so it is said once, at boot, by name. ]]
		local roster = {}
		for body in GarageConfig.TierOfBody do
			table.insert(roster, body)
		end
		local unnamed = CarNameConfig.missing(roster)
		if CarNameConfig.Enabled and #unnamed > 0 then
			self.log:warn(
				string.format(
					"%d car(s) have no game name and will show their real name: %s. Add them to CarNameConfig.Names.",
					#unnamed,
					table.concat(unnamed, ", ")
				)
			)
		end

		if not GarageConfig.Enabled or self._bayCount == 0 then
			return
		end

		local PlotService = Shard.get("PlotService")
		local plots = PlotService and PlotService:getPlots()
		if not plots then
			return
		end

		self._trove:Add(PlotService:getSignal("PlotAssigned"):Connect(function(player: Player, plot: Model)
			self:_claim(player, plot)
			self:_watchProfile(player)
		end))
		self._trove:Add(PlotService:getSignal("PlotReleased"):Connect(function(player: Player)
			self:_release(player)
		end))

		--[[ Catch up on plots already claimed. `PlotService` assigns inside its own `start`, so on a
			hot reload — or simply if it starts first — a player can already hold a lot by the time
			this connects, and would otherwise stand on a working plot with dead mats until they
			rejoined. ]]
		for _, record in plots do
			if record.owner then
				self:_claim(record.owner, record.model)
				self:_watchProfile(record.owner)
			end
		end

		--- Both loops exist only to serve passive income: one redraws the mats, one sweeps them for
		--- the AUTO COLLECT pass. Neither is started without it, rather than started and made to idle.
		if GarageConfig.Income.Passive then
			self._trove:Add(self:_labelLoop())
			self._trove:Add(self:_sweepLoop())
		end

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self:_release(player)
			self._profiles[player] = nil
			self._pickerCooldowns[player] = nil
			self._equipCooldowns[player] = nil
			self._carryCooldowns[player] = nil
		end))
	end,
})

GarageService:withCleanup(function()
	if GarageService._trove then
		GarageService._trove:Destroy()
	end
end)

-- Approved economy balance, 2026-10-04.
function GarageService.tryStarterInsurance(self, player: Player, stolen, world: number): string?
 local profile = self:_profile(player)
 local Balance = require(ReplicatedStorage.shared.Configs.BalanceConfig)
 local tutorial = profile and profile:Get({"Tutorial"})
 if not (profile and world == 1 and type(stolen) == "table" and tutorial and tutorial.Done == true) then return nil end
 local used = math.max(0, math.floor(tonumber(profile:Get({"StarterInsuranceUsed"})) or 0))
 local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
 if used >= Balance.InsuranceLimit or WorldConfig.WorldOfBody[stolen.body] ~= 1 then return nil end
 if GarageConfig.TierOfBody[stolen.body] ~= stolen.tier then return nil end
 profile:Set({"StarterInsuranceUsed"}, used + 1)
 local outcome, _, id = self:awardCar(player, stolen.tier, stolen.body, stolen.paint, stolen.mutation, "insurance", Balance.InsuranceCondition)
 if outcome == "rejected" then
  profile:Set({"StarterInsuranceUsed"}, used)
  return nil
 end
 player:SetAttribute("StarterInsuranceUsed", used + 1)
 self.log:info(string.format("%s received starter insurance %d/%d: %s at 25%% condition.", player.Name, used + 1, Balance.InsuranceLimit, stolen.body))
 return id
end

return GarageService
