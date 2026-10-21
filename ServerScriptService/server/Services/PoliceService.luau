--[[
	PoliceService  (server: vehicle PROVIDER, section marker, and bust ratification)
	-------------------------------------------------------------------------------
	The police chase is client sided for the same reason the road, the obstacles, the traffic and
	the getaway truck are: driving is solo, so each driver owns their own copy of the world and none
	of it needs to replicate (see `RoadController`). This service therefore runs no chase. It does
	three things:

	  1. PUBLISHES the authored `Workspace.PoliceVehicles` models into
	     `ReplicatedStorage.PoliceVehicles` so every client has something cheap to clone, and
	     stashes the originals into ServerStorage so nothing police shaped sits in the live world.
	     Exactly what `GetawayService` does with the truck.
	  2. MARKS THE POLICE SECTIONS. `PoliceConfig.Sections` names the road tiles that carry police
	     art; this stamps `PoliceConfig.SectionAttribute` onto each of them once the roads have been
	     published. See that config's note 4 for why it is an attribute and not a tag, and note that
	     stamping is additive: a tile a modeller has already marked by hand is left exactly as it is.
	  3. RATIFIES A BUST. The client says "the police caught me"; the server ends that player's run
	     through `RaceService.wreckRace` with `PoliceConfig.Cause`.
	  4. KEEPS A RECORD OF THE CHASE (2026-10-12), for `GetawayService` to refuse a bank against
	     (`GetawayConfig.PoliceLock`). See "THE CHASE RECORD" below.

	=== ON TRUST ==============================================================================

	The same accepted gap `GetawayService` and `StealService` document, pointing the same way. There
	is no chase on the server to check a claim against: no cruiser, no bar, no speed history. What
	the server can bound is that the player is actually racing and that the claim arrives at a
	bounded rate, and it does both.

	WHAT A LIAR GETS IS THEIR OWN RUN ENDED, WORSE. A bust pays `RewardConfig.Crash.CashFraction`
	of a run that could have banked in full, so falsely claiming one is strictly self harm, in the
	same direction every other client report in this game is exploitable in. The inverse, refusing
	to report a bust you really did earn, is the same shape as under reporting an obstacle hit and
	is covered by the same accepted trade: the only person cheated is the cheater. That stays true
	exactly as long as driving is solo.

	HOUSE RULE: no wiki-style double-bracket links in this comment. The closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local PoliceConfig = require(ReplicatedStorage.shared.Configs.PoliceConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
--- Whether a race starting now is the tutorial's, which never has a chase (`_onRaceEntered`).
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)

--[[ NO DECLARED DEPENDENCIES, and that is a correction rather than an omission.

	The obvious shape is `withDependencies({ "RoadService" })`, because the section marking has to
	run after the world roads have been moved into ReplicatedStorage. IT DOES NOT WORK. Shard orders
	`init` by dependencies and then starts every service by iterating a hash table
	(`Shard.start`), so `start` runs in an arbitrary order whatever this list says. The first
	version of this file declared the dependency, marked zero sections, and logged a warning saying
	the roads had not been published yet.

	So the marking waits for the thing it needs instead of assuming a service ran first, which is
	both correct and immune to the ordering changing again. `RaceService` is reached with
	`Shard.get` at the moment a bust lands, which is long past any of this. ]]
local PoliceService = Shard.new("PoliceService")

--[[ Floor on how often one player can report a bust, seconds.

	Not an abuse number. A legitimate bust ends the run, so there is no second one to rate limit,
	and `wreckRace` is already idempotent against the shared "this run is already ending" flag. This
	is a duplicate-message guard: it keeps a client that fires twice on the same frame from putting
	two lines in the log for one arrest. ]]
local BUST_COOLDOWN = 3

--- Seconds each of the section marking's three waits gives up after. Generous, because it is
--- running in a spawned thread that nothing is behind, and because the thing it is waiting for is
--- another service's whole publish rather than one instance replicating.
local PUBLISH_WAIT = 20

--[[ Seconds taken off the steal floor (`_onStolen`) so that an honest client always clears it before
	the server does. The floor is meant to be the SHORTEST chase a client can run, and a server that
	refused a bank the client had already made would leave the car frozen in the truck's bay with no
	run ending under it (`GetawayController._bank` never hears a refusal). So every rounding goes the
	player's way: this covers the steal report and the bank arriving with different network jitter. ]]
local FLOOR_SLACK = 1.5

PoliceService:withRemoteEvents({
	{
		--[[ client -> server: "the police caught me."

			NO PAYLOAD, and that is not an oversight. Everything a bust could carry (how long the
			chase ran, how far under the floor the car was, which cruiser was closest) is a number
			the server cannot check and does not price: unlike a bank, a bust pays nothing and
			awards nothing, so there is nothing here for a field to be trusted with. The message is
			the whole message. ]]
		PoliceBusted = function(player: Player)
			PoliceService:_onBusted(player)
		end,
		--[[ client -> server (live, graced): a chase began or ended (`PoliceController._reportChase`).

			`live` is true from the arm through the PIT and false from the moment the cruisers peel
			off, which is exactly what `GetawayController._stepPoliceLock` counts as "chased".
			`graced` is that controller's one grace: the player was in the truck's shelter when the
			chase armed, and a report with it false follows the first frame they leave it.
			`(false, true)` is the bank's waiver (`PoliceController.onBanked`): no chase, the car is
			in the truck, and the steal floor is cleared. ]]
		PoliceChase = function(player: Player, live: unknown, graced: unknown)
			PoliceService:_onChase(player, live, graced)
		end,
	},
})

-- === Publishing =============================================================

--- The ServerStorage folder the authored models are parked in. Shared with the getaway truck's, so
--- an edit session ends with one folder of stashed props rather than one per feature.
function PoliceService._stash(self): Folder
	local stash = ServerStorage:FindFirstChild(PoliceConfig.StashName)
	if not stash then
		stash = Instance.new("Folder")
		stash.Name = PoliceConfig.StashName
		stash.Parent = ServerStorage
	end
	return stash
end

--[[ Strip a published vehicle down to something a client can clone a dozen times for nothing.

	Both models ship as a single anchored MeshPart, so there is very little to do and this is
	written to survive that stopping being true: it walks the model rather than assuming one part.

	THE THREE EDITS ARE ALL THE SAME EDIT, said three ways. A pursuer must be invisible to the
	physics engine, to every spatial query in the game and to the stock CarBones suspension rays
	(which run as "Default" and are not ours to filter). It is a picture of a police car, and a
	picture cannot block a road. `PoliceConfig`'s note 2 is why that is a design rule and not a
	shortcut. ]]
function PoliceService._strip(self, model: Model)
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.CastShadow = false
		elseif inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("ModuleScript") then
			--[[ Nothing in either model ships with a script today. This is here for the same reason
				`TrafficService` throws the chassis away rather than trusting a shell: art comes back
				from a modeller with whatever was in the file it was exported from, and a script that
				starts running on twelve clones is not a thing to discover in a playtest. ]]
			inst:Destroy()
		end
	end
end

--[[ Move the authored vehicles out to ReplicatedStorage under the names the client asks for.

	MOVED, NOT CLONED, for the half of the point that publishing shares with the truck: a copy would
	leave the originals in Workspace rendering and replicating. The place file is untouched, because
	a playtest's reparenting reverts when it stops.

	Reuses an already-published folder from a prior run in the same edit session, exactly as the
	truck and the road tiles do. That is what makes a second Play in one Studio session cheap, and
	it is also why the source may legitimately be missing on the second run: it was consumed by the
	first, and the published copy is the one that matters. ]]
function PoliceService._publish(self): boolean
	local published = ReplicatedStorage:FindFirstChild(PoliceConfig.TemplateFolderName)
	if not published then
		published = Instance.new("Folder")
		published.Name = PoliceConfig.TemplateFolderName
		published.Parent = ReplicatedStorage
	end

	local source = workspace:FindFirstChild(PoliceConfig.SourceFolderName)
	local found = 0

	for key, sourceName in PoliceConfig.SourceNames do
		local wanted = PoliceConfig.TemplateNames[key]
		if published:FindFirstChild(wanted) then
			found += 1
			continue
		end

		local authored = source and source:FindFirstChild(sourceName)
		if not (authored and authored:IsA("Model")) then
			self.log:warn(string.format(
				"No '%s/%s' model to publish; the chase will run without its %s.",
				PoliceConfig.SourceFolderName, sourceName, string.lower(key)
			))
			continue
		end

		local copy = authored:Clone()
		copy.Name = wanted
		self:_strip(copy)
		--[[ A single-part model has no PrimaryPart, and `Model:PivotTo` on one falls back to
			`WorldPivot`, which is not where the part is. Setting it here rather than on the client
			means every clone arrives able to be placed with one call, and a model that grows a
			second part later keeps whatever the modeller chose. ]]
		if not copy.PrimaryPart then
			copy.PrimaryPart = copy:FindFirstChildWhichIsA("BasePart", true)
		end
		copy.Parent = published
		found += 1
	end

	if source then
		source.Parent = self:_stash()
	end

	if found == 0 then
		self.log:warn("No police vehicles were published; the chase is switched off for this server.")
		return false
	end
	self.log:info(string.format("Police vehicles published (%d of %d).", found, 2))
	return true
end

-- === Marking the sections ===================================================

--[[ Stamp `SectionAttribute` onto every tile `PoliceConfig.Sections` names.

	Runs against the PUBLISHED roads (`ReplicatedStorage.WorldRoads`), because that is where the
	tiles are once `RoadService` has moved the authored folders out of Workspace. With
	`RaceConfig.WorldRoadsPerPlayer` on they are in `ServerStorage.WorldRoads` instead, and the
	attribute reaches a client on the copy of its world it is sent.

	IT WAITS FOR THEM RATHER THAN ASSUMING THEY ARE THERE. See the note beside the service
	declaration: Shard's start order is not dependency order, so this can and does run before
	`RoadService` has published anything. Three waits, each with its own timeout, and each one
	fails to a warning rather than an error.

	A named map or tile that never arrives is warned about and skipped. That is a real state and not
	an error path: these maps are greybox passes that will be replaced wholesale, and a config
	naming a tile the current art does not have should read as "no chase in that world" rather than
	as the service failing to start.

	ADDITIVE. A tile that already carries the attribute is left alone and counted, so marking one by
	hand in Studio is a supported way to test a chase in a world this file says nothing about. ]]
function PoliceService._markSections(self): number
	local home = if RaceConfig.WorldRoadsPerPlayer then ServerStorage else ReplicatedStorage
	local roads = home:WaitForChild(RaceConfig.WorldRoadsName, PUBLISH_WAIT)
	if not roads then
		self.log:warn("No published world roads to mark; the chase will only arm off PoliceConfig.FallbackTile.")
		return 0
	end

	local marked = 0
	for map, names in PoliceConfig.Sections do
		local folder = roads:WaitForChild(map, PUBLISH_WAIT)
		if not folder then
			self.log:warn(string.format("PoliceConfig.Sections names map '%s', which has no published road.", map))
			continue
		end
		for _, tileName in names do
			local tile = folder:WaitForChild(tostring(tileName), PUBLISH_WAIT)
			if not (tile and tile:IsA("Model")) then
				self.log:warn(string.format("No tile '%s/%s' to mark as a police section.", map, tostring(tileName)))
				continue
			end
			tile:SetAttribute(PoliceConfig.SectionAttribute, true)
			marked += 1
		end
	end
	return marked
end

-- === The bust ===============================================================

--[[ The police caught somebody. End the run.

	Three refusals before anything happens, and they are the whole of what the server can check
	(see the header):

	  1. The feature is on. A client one deploy ahead of a server that has switched the chase off
	     must not be able to end its run through a code path this build does not believe in.
	  2. The player is actually racing. `wreckRace` is idempotent and would no-op anyway; asking
	     first is what keeps a stray message out of the log.
	  3. It is not a duplicate of one that arrived on the same frame.

	`wreckRace` does the rest, and does it exactly as every other ending does: cut the controls,
	settle or hold the run, fire `RaceWrecked` with the cause, play the beat, go home. The CAUSE is
	the only thing that makes this ending different from an HP death, and it is what every reaction
	downstream keys off (`PoliceConfig.Cause`). ]]
function PoliceService._onBusted(self, player: Player)
	if not PoliceConfig.Enabled then
		return
	end

	local RaceService = Shard.get("RaceService")
	if not (RaceService and RaceService:isRacing(player)) then
		return
	end

	local now = os.clock()
	local blockedUntil = self._cooldowns[player]
	if blockedUntil and now < blockedUntil then
		return
	end
	self._cooldowns[player] = now + BUST_COOLDOWN

	RaceService:wreckRace(player, PoliceConfig.Cause)
end

-- === The chase record =========================================================

--[[ THE CHASE RECORD (2026-10-12, Aleafo punch list B2). `GetawayConfig.PoliceLock` shuts the truck
	while the police are on you, and until this it was only the client saying no: a modified client,
	or one whose getaway had fallen out of step with its chase, could bank anyway. `GetawayService`
	now asks `isChased` before it ratifies a bank.

	There is still no chase on the server (the header's point stands), so the record is built from
	two sources that are trusted to different degrees, and the difference is the whole design:

	  1. THE CLIENT'S REPORTS (`PoliceChase`). The chase as the player's own controller ran it: armed,
	     PIT, peeled off, revived, and the shelter grace. This is what makes an honest client and the
	     server agree to the frame, and it covers a getaway that is out of step with its chase. It
	     stops nobody who simply never sends it.
	  2. THE STEAL FLOOR, which the client cannot talk its way out of. A steal the server ratified
	     (`StealService.CarStolen`, with the SERVER's tier when encounters are on) of a car worth
	     calling in (`PoliceConfig.isHighValueSteal`) always arms a chase on the client, and no chase
	     can end sooner than `Duration[1] - Nitro.MaxCut` after it arms. So for that long after such
	     a steal the server refuses a bank whatever the client says, which is exactly the case worth
	     cheating for: the top rungs are the cars that pay.

	THE FLOOR ONLY STANDS WHERE THE CLIENT IS CERTAIN TO ARM, because a refusal the client did not
	expect strands the car in the bay (`FLOOR_SLACK`). So it is skipped for every case in which the
	client's call can lapse unanswered (`PoliceController._callDue`): a chase already on at the steal,
	a cooldown that outlasts `StealHeat.Window`, a tutorial run, a server with no police published.
	And it is dropped on a revive, because a wreck drops the call and a revive only re-arms over a run
	that has already had a chase, and on a bank, because the client drops the call there too
	(`PoliceController.onBanked`, after `TruckClearance` can hold a call off until the van has the car).

	THE GRACE IS THE CLIENT'S WORD and honoured over both halves. A forged report can claim it, and a
	forged report can equally claim "no chase": what the floor stops is a client that goes quiet or
	fires `GetawayBanked` on its own, not one that speaks this protocol to lie in it. ]]
export type ChaseRecord = {
	live: boolean, -- a chase is on, by the client's report ("leaving" is not)
	graced: boolean, -- ...and the player was in the truck's shelter when it armed, and has not left
	clearedAt: number?, -- os.clock() of the last report that a chase ended, for the cooldown test
	floorUntil: number, -- os.clock() before which a bank is refused regardless of reports
	tutorial: boolean, -- latched at race entry: the tutorial's run never has a chase
}

--- A race began: a clean record, the client's chase state being per run (`_onRaceStart` there).
function PoliceService._onRaceEntered(self, player: Player)
	self._records[player] = {
		live = false,
		graced = false,
		clearedAt = nil,
		floorUntil = 0,
		--- Read at the same moment the client latches its own (`PoliceController._onRaceStart`),
		--- off the same attribute.
		tutorial = TutorialConfig.isTutorialRun(player:GetAttribute(TutorialConfig.StepAttribute)),
	}
end

--- The client's report. Ignored for anybody not mid-run, which is also what keeps a stray message
--- from a race that has just ended from writing into the next one's record.
function PoliceService._onChase(self, player: Player, live: unknown, graced: unknown)
	local record = self._records[player]
	if not (record and type(live) == "boolean") then
		return
	end
	if live then
		record.live = true
		record.graced = graced == true
	else
		if record.live then
			record.clearedAt = os.clock()
		end
		record.live = false
		record.graced = false
		--- "No chase, in the truck" (`PoliceController.onBanked`): the run banked and the client
		--- dropped the steal's call, so the floor that stood for the call goes with it.
		if graced == true then
			record.floorUntil = 0
		end
	end
end

--[[ A steal the server ratified. Stamps the floor when the client is certain to answer it with a
	chase. Each refusal below mirrors one way `PoliceController` can let the call lapse. ]]
function PoliceService._onStolen(self, player: Player, tier: number)
	local record = self._records[player]
	if not (record and self._published and PoliceConfig.isHighValueSteal(tier)) or record.tutorial then
		return
	end
	--- A chase in the way can hold the call past its `Window`, and the client then drops it.
	if record.live then
		return
	end
	local now = os.clock()
	local heat = PoliceConfig.StealHeat
	--- ...and so can a cooldown, unless the call is allowed through one. The client's runs from the
	--- END of the peel-off (`_lose`), so the report of the chase ending starts it here.
	if not heat.IgnoreCooldown and record.clearedAt then
		local cooldownUntil = record.clearedAt + PoliceConfig.PullAway.Time + PoliceConfig.Cooldown
		if cooldownUntil > now + heat.Delay + heat.Window - FLOOR_SLACK then
			return
		end
	end
	--[[ Measured from the STEAL and not from the arm `Delay` later, which costs a second of floor and
		buys this: a road chase that arms between the steal and the call consumes the call, and that
		chase is still at least this long. ]]
	local nitroCut = if PoliceConfig.Nitro.Enabled then PoliceConfig.Nitro.MaxCut else 0
	local shortest = PoliceConfig.Duration[1] - nitroCut - FLOOR_SLACK
	if shortest > 0 then
		record.floorUntil = math.max(record.floorUntil, now + shortest)
	end
end

--[[ PUBLIC (`GetawayService._onBanked`). Should a bank from this player be refused because the
	police are on them? The grace, when the client reported one, wins over both halves of the record
	(see "THE CHASE RECORD"). ]]
function PoliceService.isChased(self, player: Player): boolean
	if not PoliceConfig.Enabled then
		return false
	end
	local record = self._records[player]
	if not record or (record.live and record.graced) then
		return false
	end
	return record.live or os.clock() < record.floorUntil
end

PoliceService:withLifecycle({
	init = function(self)
		-- [Player] = os.clock() before which another bust report is ignored. See BUST_COOLDOWN.
		self._cooldowns = {}
		--- [Player] = ChaseRecord while they are racing. See "THE CHASE RECORD".
		self._records = {} :: { [Player]: ChaseRecord }
		--- Whether any pursuer reached the clients. A client with none never arms (`_onRaceStart`
		--- there), so the steal floor must not stand either.
		self._published = false
	end,

	start = function(self)
		if not PoliceConfig.Enabled then
			--[[ Deliberately still stashes nothing and publishes nothing. With the feature off the
				authored models stay in Workspace, which is where the modeller can see them and is
				the correct place for art that no code is using. ]]
			self.log:info("Police chases are switched off; nothing published.")
			return
		end

		if not self:_publish() then
			return
		end
		self._published = true

		--[[ The chase record's three lifelines, reached at start and not declared, for this file's
			reason above. A missing RaceService means no record is ever made, and `isChased` answers
			false for everybody: the getaway as it was before the record existed. ]]
		local Race = Shard.get("RaceService")
		if Race then
			Race:getSignal("RaceEntered"):Connect(function(player: Player)
				self:_onRaceEntered(player)
			end)
			Race:getSignal("RaceLeft"):Connect(function(player: Player)
				self._records[player] = nil
			end)
			--- A wreck drops a steal call the client had not answered yet, and the revive re-arms
			--- only a run that already had a chase. The client's own report covers that one.
			Race:getSignal("RaceRevived"):Connect(function(player: Player)
				local record = self._records[player]
				if record then
					record.floorUntil = 0
				end
			end)
		end
		local Steal = Shard.get("StealService")
		if Steal then
			Steal:getSignal("CarStolen"):Connect(function(player: Player, tier: number)
				self:_onStolen(player, tier)
			end)
		end

		--- Spawned, because `_markSections` yields on the roads being published and `Shard.start()`
		--- is the server's boot barrier: blocking it would hold every other service behind a wait
		--- for a folder this one is not on the critical path of.
		task.spawn(function()
			local marked = self:_markSections()
			self.log:info(string.format(
				"%d police section%s marked. The chase is client streamed.",
				marked, marked == 1 and "" or "s"
			))
		end)

		Players.PlayerRemoving:Connect(function(player)
			self._cooldowns[player] = nil
			self._records[player] = nil
		end)
	end,
})

return PoliceService
