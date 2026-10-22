--[[
	CustomerService  (server)
	-------------------------
	The people in your showroom. A customer walks in off the forecourt, stops in front of a car,
	looks at it, and sometimes says something and hands the owner money.

	It is the only thing on a dealership plot that moves on its own, and the only part of the meta
	game that is about the lot being LOOKED AT rather than about what it earns while nobody is there.
	`CustomerConfig` has the design; this file is the state machine and the rigs.

	=== WHY IT IS SERVER-SIDE, WHEN TRAFFIC AND THE ROAD ARE NOT ==============================

	This codebase pushes crowds to the client wherever it can — traffic is client-sided, the road is
	client-sided, and `StealController` builds its own friend avatars because the only friends list a
	client needs is its own. A customer is the exception, for two reasons that are not style
	preferences:

	  • IT HANDS OVER CASH. `GarageService` is the only thing in the game that writes `Cash`, and a
	    client that could say "a customer liked my car" would be a client that could say it a hundred
	    times a second. The decision, the roll and the payment all happen here, and the client is
	    never asked.
	  • IT IS IN A SHARED SPACE. A dealership is walked through by other players; a crowd that only
	    the owner could see would be a showroom that is full for one person and empty for everyone
	    standing next to them.

	The cost is honest and worth stating: up to `Crowd.Max` humanoids per plot, walking, on the
	server. That is what `_tendLoop` caps and what `Visit.MaxSeconds` guarantees can never leak.

	=== THE FIVE THINGS THAT ARE NOT OBVIOUS =================================================

	1. A RIG BUILT FROM A `HumanoidDescription` DOES NOT ANIMATE ITSELF. The `Animate` script that
	   makes a character walk is a LocalScript that belongs to a player's own character; an NPC the
	   server spawned has nobody to run one. So the walk and idle clips are played by hand off
	   `Humanoid.Running` (`_bindAnimation`), through the same `RigAnimator` the steal's rigs use.
	   Without that a customer slides around the showroom in an A-pose.

	2. WHERE THEY STAND IS DERIVED FROM THE PODIUM, and it is fitted, not fixed. `_standFor` steps
	   out a stud at a time until the customer's own footprint is clear of the building — because at
	   the natural distance one bay's viewing spot is inside a column. See `CustomerConfig.View`.

	3. THE RIGS LIVE IN `workspace.Customers`, NOT UNDER THE PLOT. That is not tidiness: `_standFor`
	   and `_groundAt` ask "is this spot clear?" and "where is the floor?" with queries scoped to the
	   plot, and a customer parented inside the plot would answer both questions himself — a crowd
	   that blocks its own viewing spots and stands on its own shoulders.

	4. NOTHING HERE IS AUTHORED IN THE MAP. No pad, no spawn point, no waypoint: one plot-local
	   arrival point in config, everything else measured off geometry that is already there. A
	   seventh plot dropped into `Map.Plots` gets a crowd with no map work at all.

	5. A CUSTOMER IS NOT SOLID TO ANYONE WITH A PULSE, and that costs a collision group for the
	   PLAYERS as well — `Modules/CrowdCollision` has the why. It cannot be done with CanCollide:
	   a rig with its collision off falls through the showroom floor, and collidability is a
	   property of a PAIR of groups rather than of one part. `_prepareRig` is the only place a
	   customer is put in its group and the only reason `bindPlayers` is called at all, so a game
	   with `CustomerConfig.Enabled` off leaves every character in "Default" exactly as before.

	=== LIFECYCLE ============================================================================

	A crowd is bound on `PlotAssigned` and torn down on `PlotReleased`, the same shape `GarageService`
	and `UpgradeService` both use, and everything it touches hangs off one trove. Customers are
	coroutines: each one walks its own trip and ends by removing itself, and every loop in that trip
	checks `customer.live`, which release sets false. A plot handed to the next player therefore
	cannot arrive with the last player's visitors still walking around it.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
--[[ Where a buyer stands and what their prompt says. A CONFIG and not `BuyerService`, which depends
	on this one (it asks this file to stand the rig) — the dependency runs one way only. ]]
local BuyerConfig = require(ReplicatedStorage.shared.Configs.BuyerConfig)
local CustomerConfig = require(ReplicatedStorage.shared.Configs.CustomerConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
--- For `_heldForTutorial`: which beat a player is on. Requires only configs, so it cannot cycle.
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local CrowdCollision = require(ReplicatedStorage.shared.Modules.CrowdCollision)
local NpcFriends = require(ReplicatedStorage.shared.Modules.NpcFriends)
local RigAnimator = require(ReplicatedStorage.shared.Modules.RigAnimator)

-- Hard stop on how many pages of a friends list `_friendList` will walk, whatever `Friends.Scan`
-- asks for — the same bound, for the same reason, as `StealController.MAX_FRIEND_PAGES`: this is a
-- loop whose exit condition belongs to a web service, and a service that answers "not finished,
-- nothing here" forever must not take a server thread with it. A page is 50.
local MAX_FRIEND_PAGES = 4

-- Where every customer in the server lives. One folder, deliberately not inside the plots — see
-- header note 3.
local FOLDER_NAME = "Customers"

--[[ Studs between the top of the head and the BOTTOM of an emoji drawn dead centre over it
	(`_emote`). About a tall hat's height: enough to clear the crowd's accessories without the face
	floating off as a separate thing. A detail of the bubble, not a tuning knob. ]]
local OVER_HEAD_CLEARANCE = 1.4

-- The `car ui.psd` kit's typeface, the same line every sign on a plot uses. See `CustomerConfig.Bubble`
-- for the rest of the kit values the bubble is painted in.
local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

-- One face, built once and cloned per customer. `name` is nil for the fallback extras, which get no
-- name tag at all (`CustomerConfig.Fallback`).
type Face = { model: Model, name: string?, id: number? } -- `id`: the friend's UserId, for `_rotateFace`

type Customer = {
	crowd: Crowd,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	face: Model, -- the template this one was cloned from, so a crowd does not wear one face twice
	anim: any?, -- RigAnimator, or nil on a rig with no Animator
	trove: any,
	live: boolean,
	expires: number, -- os.clock() past which the trip is abandoned wherever it is
	bay: number?, -- the bay currently claimed, so a teardown can release it
	seen: { [number]: boolean }, -- bays already looked at this trip
	floor: number,
	pendingTip: any?,
	checkoutPaid: boolean?,
	kind: any, -- `CustomerConfig.Kinds` entry; a Regular when kinds are off
}

type Crowd = {
	player: Player,
	plot: Model,
	origin: CFrame, -- the plot frame; `docs/MapLayout.md` §3.3
	folder: Folder,
	trove: any,
	customers: { [Customer]: boolean },
	busy: { [number]: boolean }, -- bays somebody is standing at right now
	departures: number?, -- customers who have left this lot, for `CustomerConfig.Friends.Rotate`
	blocked: { [number]: number }, -- bay -> os.clock() it may be tried again (see Walk.BlockSeconds)
	--- [car ID] = the buyer standing by that car (see "Buyers"). Torn down with the crowd.
	buyers: { [string]: { trove: any, name: string, bay: number, front: boolean, walker: any } },
	--- Bays whose viewing spot a buyer is standing on; customers skip them until the buyer goes.
	held: { [number]: boolean },
	--- The troves of turned-down buyers still walking out (`sendBuyerAway`). Torn down with the crowd.
	leaving: { [any]: boolean },
	nextSpawn: number,
	nextSpawnByFloor: {number},
	--- The lot's earnings not yet paid out, and when they were last added to (`_bank`).
	bank: number?,
	bankAt: number?,
	live: boolean,
	rayParams: RaycastParams,
	boxParams: OverlapParams,
}

local CustomerService = Shard.new("CustomerService"):withDependencies({ "PlotService", "GarageService" })

CustomerService:withSignals({
	--[[ (player: Player, amount: number, bay: number, body: string) — a customer liked what is on
		that bay and paid for the look. The cash is already in the profile by the time this fires;
		it is here for whatever wants to celebrate it (a quest, a sound, a server-wide feed). ]]
	"CustomerPaid",

	--[[ (player: Player, carId: string) — the owner pressed the buyer standing by that car. Checked as
		the owner before it fires (`placeBuyer`), so a subscriber never sees a visitor's press. It is
		`BuyerService`'s cue to open the offer screen; a signal rather than a call so this file never
		depends on that service, which depends on this one. ]]
	"BuyerPressed",
	--[[ (player: Player, carId: string, walked: boolean) — a buyer is standing at the car and their
		offer is now open (2026-09-28). `walked` is true for one who walked in, whose offer's clock
		`BuyerService` restarts from this moment (`BuyerConfig.Stand.ClockOnArrival`). A signal for the
		same no-dependency reason as `BuyerPressed`. ]]
	"BuyerArrived",
})

CustomerService:withRemoteEvents({
	--[[ server -> client (summary): what the showroom did while this player was out on a run —
		`{ visitors, tips, buyers }`. Fired once, when the run is over (`RaceService.RaceLeft`), and
		only if anybody came. `buyers` is 0 until the buyers' offers land; it is in the shape now so
		the screen does not change when they do. `ShowroomSummaryController` draws it. ]]
	"ShowroomSummary",
})

-- === Rigs ===================================================================

--[[ Everything a fresh rig needs before it can walk into a showroom.

	Applied identically to a friend's avatar and to a fallback extra, so the two can never drift
	apart — the same rule `StealController.prepareDriverRig` follows for the motorist.

	IT KEEPS THE HUMANOID ALIVE AND SWITCHED ON, which is the opposite of every other rig in this
	game: the steal's rigs are puppets with the state machine off, and this one has to WALK. So the
	only things turned off are the ones that would let it do something a customer should not —
	jumping onto a podium, dying, or wearing a health bar around a showroom.

	SCRIPTS ARE STRIPPED for the reason in header note 1: a description-built rig can arrive with an
	`Animate` LocalScript that will never run on the server, and leaving dead scripts in 36 rigs is
	36 instances of nothing.

	IT GOES IN THE NPC COLLISION GROUP HERE, on the template, so a clone is never solid for even the
	frame it takes to walk one. A customer collides with the showroom and with nothing that has a
	pulse — not the player looking at the same car, not the other five in the crowd. See
	`Modules/CrowdCollision`; header note 5 is why that is worth a group rather than a CanCollide.

	Returns nil for a rig with no root or no Humanoid, which is the one failure nothing here can work
	around. ]]
function CustomerService._prepareRig(self, model: Model, displayName: string?): Model?
	for _, inst in model:GetDescendants() do
		if inst:IsA("BaseScript") then
			inst:Destroy()
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		model:Destroy()
		return nil
	end

	humanoid.WalkSpeed = CustomerConfig.Walk.Speed
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

	--[[ NO ENGINE NAME TAG (the stock Humanoid one; `_tag` draws this game's own since 2026-10-08 —
		`CustomerConfig.Kinds.Tag.Everyone`). A friend customer's name is still stamped on the Humanoid so the rig
		is identifiable when you select it in the explorer, but it is never drawn: the tag sits in
		exactly the space `_say` puts the speech bubble in, and an obstructed bubble costs more than a
		name reads. `None` covers the fallback extras for free — a stranger with an invented name is a
		person this game made up, and the same four of them visit every dealership in the server. ]]
	if displayName and displayName ~= "" then
		humanoid.DisplayName = displayName
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	if not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid
	end

	CrowdCollision.applyNpc(model)

	model.Name = "Customer"
	model.PrimaryPart = root
	return model
end

--[[ The blocky extras, built once for the whole server and shared by all six lots.

	`CreateHumanoidModelFromDescription` IS A WEB CALL AND IT YIELDS, which is why every rig in this
	file is a template built off the critical path and cloned later. A customer built at the moment
	they were needed would put a network round trip inside the spawn.

	R15 EXPLICITLY, and for the same reason `StealController` forces it: the clips in
	`CustomerConfig.Animations` are the stock R15 walk and idle, and an R6 rig would load tracks that
	drive joints it does not have and stand there sliding. ]]
function CustomerService._buildFallbackFaces(self)
	task.spawn(function()
		for _, palette in CustomerConfig.Fallback.Palettes do
			local ok, model = pcall(function()
				local desc = Instance.new("HumanoidDescription")
				desc.HeadColor = palette.Head
				desc.TorsoColor = palette.Body
				desc.LeftArmColor, desc.RightArmColor = palette.Limbs, palette.Limbs
				desc.LeftLegColor, desc.RightLegColor = palette.Limbs, palette.Limbs
				return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
			end)
			if ok and model then
				local rig = self:_prepareRig(model, nil)
				if rig then
					table.insert(self._fallback, { model = rig, name = nil } :: Face)
				end
			end
		end

		if #self._fallback == 0 then
			self.log:warn("No fallback customer rigs could be built — lots will only have customers for players with friends.")
		end
	end)
end

--[[ Read a player's friends list, as far as `Friends.Scan` and no further.

	EVERY LAYER IS pcall'd BECAUSE EVERY LAYER IS A WEB CALL — `GetFriendsAsync` throws on a throttle
	and on an id the backend will not answer for, which includes a Studio session with nobody logged
	in. Whatever we have when it breaks is what we use; an empty list is a valid answer and means
	"blocky extras", not "error".

	`IsFinished` is checked AFTER reading a page rather than before, because the first page is
	already loaded when the object arrives — advancing first would skip it. ]]
function CustomerService._friendList(self, userId: number, limit: number): { { id: number, name: string? } }
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(userId)
	end)
	if not (ok and pages) then
		return {}
	end

	local friends = {}
	for _ = 1, MAX_FRIEND_PAGES do
		local read = pcall(function()
			for _, item in pages:GetCurrentPage() do
				local id = tonumber(item.Id)
				if NpcFriends.isUsable(item) then
					local name = item.DisplayName
					if not name or name == "" then
						name = item.Username
					end
					table.insert(friends, { id = id, name = name })
				end
			end
		end)
		if not read or #friends >= limit or pages.IsFinished then
			break
		end
		if not pcall(function()
			pages:AdvanceToNextPageAsync()
		end) then
			break
		end
	end
	return friends
end

--[[ Put this player's friends in their showroom: up to `Friends.Count` real avatars, built once
	when they claim a lot and cloned per customer for the rest of the session.

	SHUFFLED THEN TAKEN, not taken then shuffled, so the pick is over everyone read rather than over
	the first three — otherwise a player with 200 friends gets the same three visitors forever.

	FAILING ONE FRIEND IS NOT FAILING. A private account, a deleted user, a description the backend
	will not serve: each one drops that id and moves to the next, and a pool that comes back short or
	empty simply means `_pickFace` reaches for the extras. Nothing downstream knows how this went.

	The record is written BEFORE the thread starts and re-checked after every yield, because a
	player who joins and leaves inside this window has their plot handed on — without the check this
	thread would finish building rigs for somebody who is not in the server, and hand them to
	whoever took their lot. ]]
function CustomerService._buildFriendFaces(self, player: Player)
	local cfg = CustomerConfig.Friends
	if not cfg.Enabled or self._faces[player] then
		return
	end

	local record = { pending = true, faces = {} :: { Face } }
	self._faces[player] = record

	task.spawn(function()
		local want = math.max(cfg.Count, 0)
		local friends = self:_friendList(player.UserId, math.max(cfg.Scan, want))
		for i = #friends, 2, -1 do
			local j = self._rng:NextInteger(1, i)
			friends[i], friends[j] = friends[j], friends[i]
		end

		local used = 0
		for index, friend in friends do
			if #record.faces >= want or self._faces[player] ~= record then
				break
			end
			used = index
			local rig = self:_rigFor(friend)
			--[[ The record may have been dropped while those two web calls were out. Destroying the
				model rather than keeping it is what stops a player who left mid-build from leaving an
				orphan rig behind. ]]
			if self._faces[player] ~= record then
				if rig then
					rig:Destroy()
				end
				break
			end
			if rig then
				table.insert(record.faces, { model = rig, name = friend.name, id = friend.id } :: Face)
			end
		end
		--- Everyone not built yet, for `_rotateFace` to work through (`CustomerConfig.Friends.Rotate`).
		record.unused = table.move(friends, used + 1, #friends, 1, {})

		record.pending = false
		if #record.faces == 0 then
			self.log:info(string.format("No friend avatars for %s's customers; using the extras.", player.Name))
		else
			self.log:info(string.format("%d friend face(s) built for %s's showroom.", #record.faces, player.Name))
		end
	end)
end

--[[ One friend's avatar as a customer rig, or nil. Two web calls, each pcall'd: a private account, a
	deleted user or a throttle drops this friend and nothing else. Yields. ]]
function CustomerService._rigFor(self, friend: { id: number, name: string? }): Model?
	local gotDesc, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(friend.id)
	end)
	if not (gotDesc and desc) then
		return nil
	end
	local gotRig, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not (gotRig and model) then
		return nil
	end
	return self:_prepareRig(model, friend.name)
end

--[[ Swap one face on this player's lot for a friend not seen yet (`CustomerConfig.Friends.Rotate`).

	ONLY A FACE NOBODY IS WEARING is retired, so a customer on the lot never loses the template they
	were cloned from mid-visit and the "never the same friend twice on one lot" rule `_pickFace`
	keeps still holds. The retired friend goes to the FRONT of the queue (it is popped from the back),
	so the whole list cycles before anyone comes round again. One swap at a time per lot; a friend
	whose avatar will not build is dropped and the next one tried. ]]
function CustomerService._rotateFace(self, player: Player)
	local cfg = CustomerConfig.Friends.Rotate
	local record = self._faces[player]
	if not (cfg and cfg.Enabled and record and not record.pending and not record.rotating) then
		return
	end
	if not (record.unused and #record.unused > 0 and #record.faces > 0) then
		return
	end
	record.rotating = true
	task.spawn(function()
		while #record.unused > 0 do
			local friend = table.remove(record.unused)
			local rig = self:_rigFor(friend)
			if self._faces[player] ~= record then
				if rig then
					rig:Destroy()
				end
				return
			end
			if rig then
				local worn = {}
				local crowd = self._crowds[player]
				for customer in (if crowd then crowd.customers else {}) do
					worn[customer.face] = true
				end
				local free = {}
				for index, face in record.faces do
					if not worn[face.model] then
						table.insert(free, index)
					end
				end
				if #free == 0 then
					--- Every face is out on the lot; put the friend back and try on a later departure.
					rig:Destroy()
					table.insert(record.unused, friend)
				else
					local index = free[self._rng:NextInteger(1, #free)]
					local old = record.faces[index]
					record.faces[index] = { model = rig, name = friend.name, id = friend.id } :: Face
					if old.id then
						table.insert(record.unused, 1, { id = old.id, name = old.name })
					end
					old.model:Destroy()
				end
				break
			end
		end
		record.rotating = false
	end)
end

--[[ Drop a player's faces. Called when they leave rather than when they release a plot: a plot is a
	seat for the session and the friends list behind these rigs is not going to have changed by the
	time they sit in another one. ]]
function CustomerService._forgetFaces(self, player: Player)
	local record = self._faces[player]
	if not record then
		return
	end
	self._faces[player] = nil
	for _, face in record.faces do
		face.model:Destroy()
	end
end

--[[ Which face the next customer wears.

	NOT THE SAME FACE TWICE ON ONE LOT, while still being random: templates already worn by a live
	customer are taken out of the pool, and the pick is over what is left. With three faces and two
	customers that means the player never sees the same friend standing in two places, which is the
	one thing that would give away that these are clones. ]]
function CustomerService._pickFace(self, crowd: Crowd): Face?
	local record = self._faces[crowd.player]
	local pool = if record and #record.faces > 0 then record.faces else self._fallback
	if #pool == 0 then
		return nil
	end

	local worn = {}
	for customer in crowd.customers do
		worn[customer.face] = true
	end

	local free = {}
	for _, face in pool do
		if not worn[face.model] then
			table.insert(free, face)
		end
	end

	local choices = if #free > 0 then free else pool
	return choices[self._rng:NextInteger(1, #choices)]
end

-- === The plot's geometry ====================================================

--[[ Where the floor is under a point, in world space, or nil if there is nothing under it.

	SCOPED TO THE PLOT, which is what makes it an answer about the building rather than about
	whatever happens to be standing there — a customer, the owner, or a car parked on the forecourt
	would all otherwise read as ground. It is also why the rigs are not parented inside the plot
	(header note 3). ]]
function CustomerService._groundAt(self, crowd: Crowd, above: Vector3): Vector3?
	local hit = workspace:Raycast(above, -crowd.origin.UpVector * 26, crowd.rayParams)
	return if hit then hit.Position else nil
end

--[[ A point out on the forecourt to arrive at or leave from, and the CFrame to stand there in.

	`Arrival` is in the PLOT-LOCAL frame (`docs/MapLayout.md` §3.3), where local +Z is deeper into
	the showroom — so the configured negative Z is out front, and the extra half turn is what has
	them face the building rather than the plaza. Same trick, same reason, as
	`PlotConfig.Fallback.FaceShowroom`.

	The ground is raycast per arrival rather than cached with the crowd: it is one cast per customer
	spawned, and the lateral spread means it is not always the same point. ]]
function CustomerService._forecourt(self, crowd: Crowd): CFrame
	local cfg = CustomerConfig.Arrival
	local x = cfg.LocalX + self._rng:NextNumber(-cfg.Spread, cfg.Spread)
	local nominal = crowd.origin * CFrame.new(x, 0, cfg.LocalZ)

	local ground = self:_groundAt(crowd, nominal.Position + crowd.origin.UpVector * 12)
	local position = ground or nominal.Position
	return (crowd.origin.Rotation + position) * CFrame.Angles(0, math.pi, 0)
end

--[[ Where somebody stands to look at one bay, and what they look at from there. nil when no
	standoff between `Standoff` and `MaxStandoff` leaves room for a person.

	THE PODIUM'S OWN FRAME IS THE ANSWER. Every `CarSlot` base slab faces down the aisle at its own
	collect mat, so pushing out along its LookVector by half its depth plus a standoff is "in front
	of this bay", at whatever scale and whatever rotation the slot was placed at. Nothing is authored
	and nothing has to be kept in sync.

	AND IT IS FITTED, NOT FIXED — see `CustomerConfig.View`. Measured on Plot1: five of the six bays
	are clear from five studs out and bay 2 is not clear until ten, because the inner corner column
	stands directly in front of it. A fixed standoff puts one customer inside a column on every plot
	in the map. ]]
function CustomerService._standFor(self, crowd: Crowd, bay): { position: Vector3, look: Vector3 }?
	local base, deck = bay.base, bay.deck
	if not (base and base.Parent and deck and deck.Parent) then
		return nil
	end

	local view = CustomerConfig.View
	local up = crowd.origin.UpVector

	for standoff = view.Standoff, view.MaxStandoff do
		local spot = base.CFrame * CFrame.new(0, 0, -(base.Size.Z / 2 + standoff))
		local ground = self:_groundAt(crowd, spot.Position + up * 12)
		if ground then
			--[[ The box sits just above the floor, in the PLOT's rotation rather than the world's, so
				a lot on a 36-degree bearing is tested with the same footprint as one facing down the
				map's axes. ]]
			local at = crowd.origin.Rotation + (ground + up * (view.Clearance.Y / 2 + 0.5))
			if #workspace:GetPartBoundsInBox(at, view.Clearance, crowd.boxParams) == 0 then
				-- Looking at the car, not at the deck it stands on: roughly bonnet height above the
				-- top of the podium, which is where a body sits.
				return { position = ground + up * 3, look = deck.Position + up * 3 }
			end
		end
	end
	return nil
end

-- === Choosing a car =========================================================

--[[ The bays with a car on them and what each one earns per second.

	The rate comes from `GarageService.getBayCar`, which is the same expression the mats pay out and
	the HUD's per-second line is summed from — so what a customer hands over and what the bay earns
	cannot disagree about what a car is worth. ]]
function CustomerService._occupied(self, crowd: Crowd): { { bay: any, rate: number } }
	local GarageService = Shard.get("GarageService")
	if not GarageService then
		return {}
	end

	local out = {}
	for _, bay in GarageService:getBays(crowd.player) do
		--[[ `rate` IS WHATEVER A TIP IS PRICED OFF, and since 2026-09-28 that is the car's value
			rather than the bay's income (`CustomerConfig.Tip`). The field keeps its name because
			`_pickBay` weights by it and the weighting argument (`Visit.RateBias`) is identical for
			either number: the better car draws more of the crowd. ]]
		local car, basis
		if GarageConfig.Income.Passive then
			car, basis = GarageService:getBayCar(crowd.player, bay.index)
		else
			local _id
			car, _id, basis = GarageService:getBayTip(crowd.player, bay.index)
		end
		if car then
			table.insert(out, { bay = bay, rate = math.max(basis, 1) })
		end
	end
	return out
end

--[[ Which car this customer looks at next, or nil when there is nothing left worth walking to.

	WEIGHTED BY WHAT THE BAY EARNS (`Visit.RateBias`), so a crowd gathers around the best car on the
	lot — and, more importantly, so that parking a cheap car in a spare bay can never REDUCE what
	customers pay. `CustomerConfig.Visit.RateBias` has that argument in full; it is the one piece of
	behaviour in this file that is an economy decision rather than a look.

	Three things take a bay out of the running, and each has already been paid for once:
	  • somebody is standing at it (`busy`) — two people at one podium is a queue, not a showroom;
	  • this customer has already looked at it this trip (`seen`) — doubling back reads as a bug;
	  • the walk to it failed recently (`blocked`) — see `Walk.BlockSeconds`. ]]
function CustomerService._pickBay(self, crowd: Crowd, customer: Customer)
	local now = os.clock()
	local choices, total = {}, 0

	for _, entry in self:_occupied(crowd) do
		local index = entry.bay.index
		if CustomerConfig.floorForBay(index) ~= (customer.floor or 1) then
			continue
		end
		if crowd.busy[index] or crowd.held[index] or customer.seen[index] or (crowd.blocked[index] or 0) > now then
			continue
		end
		--- A CAR NERD heads harder for the best car (`CustomerConfig.Kinds`).
		local weight = entry.rate ^ (CustomerConfig.Visit.RateBias + ((customer.kind and customer.kind.RateBias) or 0))
		total += weight
		table.insert(choices, { bay = entry.bay, weight = weight })
	end

	if total <= 0 then
		return nil
	end

	local roll = self._rng:NextNumber() * total
	for _, choice in choices do
		roll -= choice.weight
		if roll <= 0 then
			return choice.bay
		end
	end
	return choices[#choices].bay
end

-- === Walking ================================================================

--[[ Walk one leg, to one point. false means they never got there — cancelled, out of time, or stuck.

	`MoveTo` IS RE-ISSUED WHILE WALKING, and that is not belt-and-braces: `Humanoid:MoveTo` abandons
	its target on its own after 8 seconds, so a customer who spends that long squeezing past the
	owner would simply stop and stand there forever. Re-issuing costs a property write.

	The distance test is FLAT. The aisle floor is not perfectly level (measured: 1.24 to 1.84 local Y
	across one showroom) and a 3D distance to a point on the ground never closes for somebody whose
	root is three studs above it. ]]
function CustomerService._step(self, customer: Customer, position: Vector3, timeout: number, passing: boolean?): boolean
	local cfg = CustomerConfig.Walk
	local deadline = os.clock() + timeout
	local reissue = 0
	--[[ SMOOTH WALKING (2026-10-20: the first buyer "looks staggered"). Two causes, both fixed here.

		  • THE SERVER KEEPS THE PHYSICS. Left to itself Roblox hands an unanchored rig's physics to the
		    nearest player, and a humanoid the server is steering then stutters on that player's
		    screen, which is exactly the one watching. Set every leg: it is a property write, and an
		    anchored root (a buyer who has stood) refuses it, so a once-only flag could miss the walk off.
		  • A WAYPOINT IT IS ONLY PASSING (`passing`) counts as reached one poll's worth of travel early,
		    so the next leg is issued before it gets there. It used to arrive, stand until the next
		    `PollSeconds` check, then set off again: stop-go at every waypoint, worse the faster it walks.
		    One poll and no more, so a corner beside a podium is not cut into it. ]]
	pcall(function()
		customer.root:SetNetworkOwner(nil)
	end)
	local radius = cfg.ArriveRadius
	if passing then
		radius += customer.humanoid.WalkSpeed * cfg.PollSeconds
	end

	while customer.live and customer.root.Parent do
		if os.clock() > customer.expires then
			return false
		end

		local delta = position - customer.root.Position
		if Vector3.new(delta.X, 0, delta.Z).Magnitude <= radius then
			return true
		end
		if os.clock() >= deadline then
			return false
		end
		if os.clock() >= reissue then
			customer.humanoid:MoveTo(position)
			reissue = os.clock() + cfg.ReissueSeconds
		end
		task.wait(cfg.PollSeconds)
	end
	return false
end

--[[ Walk to a point, around whatever is in the way.

	PATHFINDING RATHER THAN A STRAIGHT LINE, because the room is full of 26-stud podiums and the
	spot they are walking to is in front of one of them. A straight line from the door to bay 2
	crosses two other bays.

	A PATH THAT CANNOT BE COMPUTED IS STILL WALKED AT, in a straight line, rather than being treated
	as a failure: `ComputeAsync` can come back `NoPath` for a target a stud inside geometry it does
	not like, and the leg timeout is the real backstop for a customer who cannot get somewhere. What
	is NOT done is retrying the path — a second identical query gets a second identical answer.

	`strict` (2026-10-06, `CustomerConfig.Upstairs`) skips that straight walk: no path, no walk, false
	at once, for the caller to hop instead. ]]
function CustomerService._walkTo(self, customer: Customer, position: Vector3, strict: boolean?): boolean
	if not (customer.live and customer.root.Parent) then
		return false
	end

	local cfg = CustomerConfig.Walk
	local function timeoutFor(from: Vector3, to: Vector3): number
		return (from - to).Magnitude / math.max(cfg.Speed, 1) * cfg.TimeoutFactor + cfg.TimeoutGrace
	end

	local path = PathfindingService:CreatePath({
		AgentRadius = cfg.Agent.Radius,
		AgentHeight = cfg.Agent.Height,
		AgentCanJump = cfg.Agent.CanJump,
		WaypointSpacing = cfg.Agent.Spacing,
	})

	local computed = pcall(function()
		path:ComputeAsync(customer.root.Position, position)
	end)
	local waypoints = if computed and path.Status == Enum.PathStatus.Success then path:GetWaypoints() else nil

	if waypoints and #waypoints > 1 then
		local from = customer.root.Position
		-- From 2: the first waypoint is the point they are already standing on.
		for i = 2, #waypoints do
			local to = waypoints[i].Position
			if not self:_step(customer, to, timeoutFor(from, to), i < #waypoints) then
				return false
			end
			from = to
		end
		return customer.live
	end

	if strict then
		return false
	end
	return self:_step(customer, position, timeoutFor(customer.root.Position, position))
end

-- === Changing floor (`CustomerConfig.Upstairs`) ===============================

--- Is this world point on the upper floor of this lot?
function CustomerService._upstairs(self, crowd: Crowd, position: Vector3): boolean
	return crowd.origin:PointToObjectSpace(position).Y > CustomerConfig.Upstairs.SplitY
end

--- Where a customer stands at the foot of the ladder, in the same ground-plus-3 shape `_standFor`
--- answers in. nil on a lot with no floor under that point.
function CustomerService._ladderFoot(self, crowd: Crowd): Vector3?
	local foot = CustomerConfig.Upstairs.LadderFoot
	local up = crowd.origin.UpVector
	local nominal = (crowd.origin * CFrame.new(foot.LocalX, 0, foot.LocalZ)).Position
	local ground = self:_groundAt(crowd, nominal + up * 10)
	return if ground then ground + up * 3 else nil
end

--[[ Fade every visible part of a customer towards `alpha` (1 = gone) over `seconds`. The parts'
	own transparencies are remembered on the first call, so fading back to 0 restores them rather
	than drawing the invisible root. ]]
function CustomerService._fadeTo(self, customer: any, alpha: number, seconds: number)
	local originals = customer.fadeOriginals
	if not originals then
		originals = {}
		for _, inst in customer.model:GetDescendants() do
			if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
				table.insert(originals, { inst = inst, from = (inst :: any).Transparency })
			end
		end
		customer.fadeOriginals = originals
	end
	local steps = math.max(1, math.round(seconds / 0.06))
	local start = customer.fadeAlpha or 0
	for step = 1, steps do
		if not (customer.live and customer.model.Parent) then
			return
		end
		local a = start + (alpha - start) * (step / steps)
		for _, entry in originals do
			(entry.inst :: any).Transparency = entry.from + (1 - entry.from) * a
		end
		task.wait(seconds / steps)
	end
	customer.fadeAlpha = alpha
end

--- Fade out here, stand at `position` (ground plus 3, as every spot in this file is), fade in.
function CustomerService._hop(self, crowd: Crowd, customer: any, position: Vector3)
	local seconds = CustomerConfig.Upstairs.FadeSeconds
	self:_fadeTo(customer, 1, seconds)
	if not (customer.live and customer.model.Parent) then
		return
	end
	local up = crowd.origin.UpVector
	local lift = up * (customer.humanoid.HipHeight + customer.root.Size.Y / 2 - 3)
	local look = customer.root.CFrame.LookVector
	local flat = look - up * look:Dot(up)
	local at = position + lift
	customer.model:PivotTo(if flat.Magnitude > 1e-3 then CFrame.lookAt(at, at + flat, up) else CFrame.new(at))
	customer.humanoid:MoveTo(at)
	self:_fadeTo(customer, 0, seconds)
end

--[[ `_walkTo`, aware of the ladder. Same answer: false means they never got there. A leg on one
	floor of a lot without a second one is exactly `_walkTo`. ]]
function CustomerService._travel(self, crowd: Crowd, customer: any, position: Vector3): boolean
	local cfg = CustomerConfig.Upstairs
	local fromUp = self:_upstairs(crowd, customer.root.Position)
	local toUp = self:_upstairs(crowd, position)
	if not cfg.Enabled or (not fromUp and not toUp) then
		return self:_walkTo(customer, position)
	end

	if fromUp and toUp then
		if not self:_walkTo(customer, position, true) and customer.live then
			self:_hop(crowd, customer, position)
		end
		return customer.live
	end

	local foot = self:_ladderFoot(crowd)
	if toUp then
		--- Up: to the ladder on foot, then the hop. A foot that cannot be reached still hops.
		if foot then
			self:_walkTo(customer, foot)
		end
		if customer.live then
			self:_hop(crowd, customer, position)
		end
		return customer.live
	end

	--- Down: the hop lands them at the foot of the ladder, and they walk from there.
	if not foot then
		self:_hop(crowd, customer, position)
		return customer.live
	end
	self:_hop(crowd, customer, foot)
	return customer.live and self:_walkTo(customer, position)
end

--[[ Turn on the spot to face the car.

	EASED OVER A THIRD OF A SECOND, because a rig that changes facing between two frames reads as a
	teleport — and this is the moment the whole feature is named after, so it is the one that has to
	look deliberate.

	Written straight to the root's CFrame, recomputed from the CURRENT position every frame rather
	than lerped from a captured one: the customer has just stopped walking and is still settling, and
	a lerp from a stale start would drag them back a few studs while they turned. ]]
function CustomerService._face(self, customer: Customer, target: Vector3)
	local seconds = CustomerConfig.Visit.TurnSeconds
	local root = customer.root
	local started = os.clock()

	while customer.live and root.Parent do
		local elapsed = os.clock() - started
		local flat = Vector3.new(target.X, root.Position.Y, target.Z)
		if (flat - root.Position).Magnitude < 0.1 then
			return
		end

		local goal = CFrame.lookAt(root.Position, flat)
		if elapsed >= seconds then
			root.CFrame = goal
			return
		end
		root.CFrame = root.CFrame:Lerp(goal, math.min(1, RunService.Heartbeat:Wait() / seconds * 2))
	end
end

--- Stand still for a while. false means the customer was torn down or ran out of trip time.
function CustomerService._dwell(self, customer: Customer, seconds: number): boolean
	local until_ = os.clock() + seconds
	while customer.live and customer.root.Parent do
		if os.clock() > customer.expires then
			return false
		end
		if os.clock() >= until_ then
			return true
		end
		task.wait(0.1)
	end
	return false
end

-- === Saying something =======================================================

--[[ One row of the bubble: a `TextScaled` band placed from a `Bubble.Rows` entry, in fractions of
	the BODY's own height rather than of the whole texture — so the rows mean what they say and
	retuning the tail's length moves no text. ]]
local function row(parent: GuiObject, name: string, spec, colour: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, spec.Y)
	label.Size = UDim2.fromScale(0.82, spec.Height)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextColor3 = colour
	label.TextScaled = true
	label.Parent = parent
	return label
end

--[[ The speech bubble: our own billboard, not Roblox's bubble chat, for the reasons in
	`CustomerConfig.Bubble` — the short version is that `TextChatService:DisplayBubble` is a client
	call, bubble chat is off by default, and a chat bubble cannot show the money.

	Built rather than filled in, which is the one place this service breaks the rule the rest of the
	plot follows (`GarageConfig.Collect`, `UpgradeConfig.Board`: nothing on a hot path should build
	UI it could fill in). It is deliberate: a bubble belongs to a rig that did not exist a minute
	ago and will not exist in a minute, so there is nothing in the map to hang an authored one off.

	IT IS ONE TEXTURE PLUS FOUR INSTANCES, since 2026-08-25 — `UIAssets.Bubble.Panel` carries the
	kit's border, rim, face, weave AND the tail, so none of that is drawn in code any more. What is
	left here is the arithmetic the drawing cannot do: where the billboard's centre has to sit for
	the tail to land the right distance over a head that is a real avatar's, and where the money
	goes. See `CustomerConfig.Bubble`.

	THE ROWS ARE PLACED INSIDE A `Body` FRAME rather than inside the billboard, because the bottom
	fifth of the drawing is tail — see `UIAssets.BubbleBodyFraction`, which is a property of the
	texture and therefore lives with it. ]]
--[[ The kind's name tag over the head (`CustomerConfig.Kinds.Tag`), for the kinds that have a title:
	a gold badge with the title, and the customer's name under it. Server-built like the speech
	bubble, so everybody on the lot sees who walked in; it goes with the rig. Placed by `_placeTag`. ]]
function CustomerService._tag(self, customer: Customer, name: string?)
	local kind = customer.kind
	local cfg = CustomerConfig.Kinds.Tag
	local titled = kind ~= nil and kind.Title ~= nil
	local named = name ~= nil and name ~= ""
	--- A plain customer gets the name line alone (`Tag.Everyone`); a nameless one gets nothing to say.
	if not titled and not (cfg.Everyone and named) then
		return
	end
	local head = customer.model:FindFirstChild("Head")
	local anchor = if head and head:IsA("BasePart") then head else customer.root
	local ink = Color3.fromRGB(20, 16, 30)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CustomerKindTag"
	gui.Size = UDim2.fromScale(cfg.Width, if titled then cfg.Height else cfg.NameHeight)
	gui.MaxDistance = cfg.MaxDistance
	gui.LightInfluence = 0
	--- Over the world, so a tall hat (theirs or the VIP outfit's) can never swallow it.
	gui.AlwaysOnTop = true

	if not titled then
		local who = Instance.new("TextLabel")
		who.Name = "Name"
		who.Size = UDim2.fromScale(1, 1)
		who.BackgroundTransparency = 1
		who.FontFace = FONT
		who.Text = name :: string
		who.TextColor3 = Color3.new(1, 1, 1)
		who.TextScaled = true
		who.TextStrokeTransparency = 0
		who.TextStrokeColor3 = ink
		who.Parent = gui
		gui.Parent = anchor
		self:_placeTag(customer)
		return
	end

	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.fromScale(0.5, 0)
	badge.Size = UDim2.fromScale(0.42, 0.5)
	badge.BackgroundColor3 = kind.Color or Color3.fromRGB(255, 205, 40)
	badge.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.45, 0)
	corner.Parent = badge
	local rim = Instance.new("UIStroke")
	rim.Color = ink
	rim.Thickness = 2
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = badge
	local gloss = Instance.new("UIGradient")
	gloss.Rotation = 90
	gloss.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 200, 120))
	gloss.Parent = badge
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.86, 0.8)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.BackgroundTransparency = 1
	title.FontFace = FONT
	title.Text = "★ " .. kind.Title
	title.TextColor3 = ink
	title.TextScaled = true
	title.Parent = badge

	if name and name ~= "" then
		local who = Instance.new("TextLabel")
		who.Name = "Name"
		who.AnchorPoint = Vector2.new(0.5, 0)
		who.Position = UDim2.fromScale(0.5, 0.54)
		who.Size = UDim2.fromScale(1, 0.44)
		who.BackgroundTransparency = 1
		who.FontFace = FONT
		who.Text = name
		who.TextColor3 = Color3.new(1, 1, 1)
		who.TextScaled = true
		who.TextStrokeTransparency = 0
		who.TextStrokeColor3 = ink
		who.Parent = gui
	end
	gui.Parent = anchor
	self:_placeTag(customer)
end

--[[ Put the name tag `Tag.Above` studs over the TOP of the rig as it is dressed now — its highest part,
	hats included — rather than a fixed height over the head. Called when the tag is made and again
	when the VIP outfit lands (`_wear`), because the outfit's hat is what made the fixed height fail. ]]
function CustomerService._placeTag(self, customer: Customer)
	local head = customer.model:FindFirstChild("Head")
	local anchor = if head and head:IsA("BasePart") then head else customer.root
	local tag = anchor:FindFirstChild("CustomerKindTag")
	if not (tag and tag:IsA("BillboardGui")) then
		return
	end
	local top = anchor.Position.Y + anchor.Size.Y / 2
	for _, part in customer.model:GetDescendants() do
		if part:IsA("BasePart") and part ~= customer.root then
			top = math.max(top, part.Position.Y + part.Size.Y / 2)
		end
	end
	local cfg = CustomerConfig.Kinds.Tag
	--- The tag's own height (a VIP's badge or a plain name line), so both sit `Above` over the outfit.
	tag.StudsOffsetWorldSpace = Vector3.new(0, top - anchor.Position.Y + cfg.Above + tag.Size.Y.Scale / 2, 0)
end

--[[ A face popping beside the head (`CustomerConfig.Reactions.Emoji`): a billboard to the SIDE of the
	speech bubble so the two never cover each other, popped with a scale, gone after `Seconds`.
	`side` and `seconds` override those two for a caller with no bubble to dodge (a declined buyer). ]]
function CustomerService._emote(self, customer: Customer, face: string?, side: number?, seconds: number?)
	local cfg = CustomerConfig.Reactions.Emoji
	if not (cfg.Enabled and face and customer.live) then
		return
	end
	local head = customer.model:FindFirstChild("Head")
	local anchor = if head and head:IsA("BasePart") then head else customer.root
	local gui = Instance.new("BillboardGui")
	gui.Name = "CustomerEmote"
	gui.Size = UDim2.fromScale(cfg.Size, cfg.Size)
	--[[ STRAIGHT OVER THE HEAD IT CLEARS THE HAT (2026-10-15, "they get stuck in the character").
		Beside a speech bubble (`cfg.Side`) the old 0.6 stud lift was fine, because the emoji sits off
		to one side. Dead centre (a seller's 😠/😄, a declined buyer's huff), that lift put the middle of
		a `cfg.Size`-tall emoji 0.6 over the head, so its lower half sat in the face and the hat. There
		it is lifted to half its own height plus `OVER_HEAD_CLEARANCE`, so its bottom edge clears the
		hat. ]]
	local centred = (side or cfg.Side) == 0
	local lift = if centred then cfg.Size * 0.5 + OVER_HEAD_CLEARANCE else 0.6
	gui.StudsOffsetWorldSpace = Vector3.new(0, anchor.Size.Y * 0.5 + lift, 0)
	gui.StudsOffset = Vector3.new(side or cfg.Side, 0, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = CustomerConfig.Bubble.MaxDistance
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = face
	text.TextScaled = true
	text.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = text
	gui.Parent = anchor
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Debris:AddItem(gui, seconds or cfg.Seconds)
end

--- Catalogue asset type id -> how a `HumanoidDescription` wears it. Classic clothing is a property;
--- everything else is an accessory entry, and the layered kinds say so.
local CLASSIC_CLOTHING = { [2] = "GraphicTShirt", [11] = "Shirt", [12] = "Pants" }
local WORN_ACCESSORY: { [number]: { type: Enum.AccessoryType, layered: boolean } } = {
	[8] = { type = Enum.AccessoryType.Hat, layered = false },
	[41] = { type = Enum.AccessoryType.Hair, layered = false },
	[42] = { type = Enum.AccessoryType.Face, layered = false },
	[43] = { type = Enum.AccessoryType.Neck, layered = false },
	[44] = { type = Enum.AccessoryType.Shoulder, layered = false },
	[45] = { type = Enum.AccessoryType.Front, layered = false },
	[46] = { type = Enum.AccessoryType.Back, layered = false },
	[47] = { type = Enum.AccessoryType.Waist, layered = false },
	[64] = { type = Enum.AccessoryType.TShirt, layered = true },
	[65] = { type = Enum.AccessoryType.Shirt, layered = true },
	[66] = { type = Enum.AccessoryType.Pants, layered = true },
	[67] = { type = Enum.AccessoryType.Jacket, layered = true },
	[68] = { type = Enum.AccessoryType.Sweater, layered = true },
	[69] = { type = Enum.AccessoryType.Shorts, layered = true },
	[70] = { type = Enum.AccessoryType.LeftShoe, layered = true },
	[71] = { type = Enum.AccessoryType.RightShoe, layered = true },
	[72] = { type = Enum.AccessoryType.DressSkirt, layered = true },
}
--- [assetId] = its asset type id, or false for one that could not be read. Asked once per server.
local assetTypes: { [number]: number | false } = {}

local function assetTypeOf(id: number): number?
	local known = assetTypes[id]
	if known == nil then
		--- A web call, so pcall'd: a failed lookup is an item skipped, never a broken customer.
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, Enum.InfoType.Asset)
		end)
		known = if ok and type(info) == "table" and type(info.AssetTypeId) == "number" then info.AssetTypeId else false
		assetTypes[id] = known
	end
	return if known then known else nil
end

--[[ Put `ids` (catalogue items, `VipOutfit.Clothing`) on this customer over their own avatar, through
	their rig's `HumanoidDescription` — the one path that wears classic clothing, layered clothing and
	accessories alike, the way a real avatar is dressed. YIELDS (the type lookup and `ApplyDescription`
	are web calls), so it is spawned; the customer walks in in their own clothes and the outfit lands a
	moment later. Every failure is pcall'd and degrades to the VIP's light alone. ]]
function CustomerService._wear(self, customer: Customer, ids: { number })
	local ok, err = pcall(function()
		local humanoid = customer.humanoid
		local desc = humanoid:GetAppliedDescription()
		local accessories = desc:GetAccessories(true)
		for _, id in ids do
			local typeId = assetTypeOf(id)
			local classic = typeId and CLASSIC_CLOTHING[typeId]
			local worn = typeId and WORN_ACCESSORY[typeId]
			if classic then
				(desc :: any)[classic] = id
			elseif worn then
				table.insert(accessories, {
					AssetId = id,
					AccessoryType = worn.type,
					IsLayered = worn.layered,
					Order = if worn.layered then #accessories + 10 else nil,
				})
			end
		end
		desc:SetAccessories(accessories, true)
		if customer.live and humanoid.Parent then
			humanoid:ApplyDescription(desc)
			--- The outfit's hat is taller than the head the tag was first placed over.
			self:_placeTag(customer)
		end
	end)
	if not ok and not self._warnedOutfit then
		self._warnedOutfit = true
		self.log:warn(string.format("Could not dress a VIP in their outfit (%s); VIPs keep their own clothes and the gold glow.", tostring(err)))
	end
end

--[[ How a VIP looks (`CustomerConfig.Kinds.VipOutfit`, and its note on why it is light and not gold
	paint), on the clone only — the face template other customers are cloned from is never touched. ]]
function CustomerService._dress(self, customer: Customer)
	local kind = customer.kind
	if not (kind and kind.Outfit) then
		return
	end
	local outfit = CustomerConfig.Kinds.VipOutfit
	local model = customer.model

	if #outfit.Clothing > 0 then
		task.spawn(self._wear, self, customer, outfit.Clothing)
	end

	--[[ The gold outline. A `Highlight` with no fill draws only the silhouette's edge. Highlights are
		capped per client (31), which one VIP in twenty customers never comes near. ]]
	if outfit.Outline.Enabled then
		local highlight = Instance.new("Highlight")
		highlight.Name = "VipOutline"
		highlight.FillTransparency = 1
		highlight.OutlineColor = outfit.Outline.Color
		highlight.OutlineTransparency = outfit.Outline.Transparency
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = model
		highlight.Parent = model
	end

	local sparkle = outfit.Sparkle
	if sparkle.Enabled then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "VipSparkle"
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(sparkle.Color)
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, sparkle.Size), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Speed = NumberRange.new(0.5, 1.5)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = sparkle.Rate
		emitter.Parent = customer.root
	end
end

function CustomerService._say(self, customer: Customer, text: string?, amount: number?)
	local cfg = CustomerConfig.Bubble
	if not (cfg.Enabled and text and customer.live) then
		return
	end

	local head = customer.model:FindFirstChild("Head")
	local anchor = if head and head:IsA("BasePart") then head else customer.root
	--- The kind tag steps aside for the bubble's life, so the two never stack over one head.
	local tag = anchor:FindFirstChild("CustomerKindTag")
	if tag and tag:IsA("BillboardGui") then
		tag.Enabled = false
		task.delay(cfg.PopSeconds + cfg.HoldSeconds + cfg.FadeSeconds, function()
			if tag.Parent then
				tag.Enabled = true
			end
		end)
	end
	local existing = anchor:FindFirstChild("CustomerBubble")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "CustomerBubble"
	-- Scale is STUDS on a BillboardGui, so the bubble is a physical object in the showroom and gets
	-- smaller as you walk away from it.
	gui.Size = UDim2.fromScale(cfg.Size.X, cfg.Size.Y)
	--[[ `StudsOffsetWorldSpace` moves the billboard's CENTRE, and what wants to be a fixed distance
		over the head is the TIP OF THE TAIL — the bottom edge. So it is derived rather than
		configured: the anchor's own half-height, the clearance, and half the bubble.

		DERIVED AND NOT A CONSTANT BECAUSE THE HEADS ARE REAL. These rigs are built from friends'
		`HumanoidDescription`s and no two of those heads are the same size, so a single number would
		leave the tail buried in one avatar and floating over the next. ]]
	local lift = anchor.Size.Y * 0.5 + (if anchor == head then 0 else cfg.RootLift)
	gui.StudsOffsetWorldSpace = Vector3.new(0, lift + cfg.TailClearance + cfg.Size.Y * 0.5, 0)
	gui.MaxDistance = cfg.MaxDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false

	--[[ ANCHORED AT THE BOTTOM, which is the whole of what makes the pop read right: a `UIScale`
		scales its object about that object's own `AnchorPoint`, so from bottom-centre the bubble
		blooms out of its own tail — out of the speaker's head — instead of inflating around its
		middle. Everything else hangs off this, so one `UIScale` moves the lot. ]]
	local root = Instance.new("Frame")
	root.Name = "Bubble"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.fromScale(0.5, 1)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Scale = cfg.PopScale
	scale.Parent = root

	local panel = Instance.new("ImageLabel")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundTransparency = 1
	panel.Image = UIAssets.url(UIAssets.Bubble.Panel)
	--- Stretch, never Slice. The texture is drawn at exactly the aspect it renders at, so the
	--- stretch is the identity — and there is no corner curve for a slice to pin at texture pixels,
	--- because this kit's rectangles have square corners. `UIAssets.Slice` has the argument.
	panel.ScaleType = Enum.ScaleType.Stretch
	panel.Parent = root

	--- The part of the drawing that is not tail. Every label goes in here.
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.fromScale(1, UIAssets.BubbleBodyFraction)
	body.BackgroundTransparency = 1
	body.Parent = root

	--- Fades are per-property and there is no one property that covers both an image and a label,
	--- so the two lists are collected as the bubble is drawn rather than rediscovered later.
	local images: { ImageLabel } = { panel }
	local texts: { TextLabel } = {}

	local paid = amount ~= nil and amount > 0
	local rows = cfg.Rows
	local line = row(body, "Line", if paid then rows.Line else rows.Solo, cfg.Colors.Text)
	line.Text = text
	table.insert(texts, line)

	if paid then
		local money = Instance.new("Frame")
		money.Name = "Money"
		money.Position = UDim2.fromScale(0, rows.Money.Y)
		money.Size = UDim2.fromScale(1, rows.Money.Height)
		money.BackgroundTransparency = 1
		money.Parent = body

		--[[ The icon's width, in the money row's own scale units. A `UIAspectRatioConstraint` is the
			obvious tool and it is the wrong one here for `CarDealController._buildPill`'s reason —
			but the same escape applies, and more simply: a billboard has a FIXED, KNOWN aspect, so
			the width the icon needs is arithmetic and cannot collapse.

			Two conversions, and they are easy to get backwards. The body's aspect is the bubble's
			own, narrowed by the fraction of it that is body; the row's aspect is the body's again,
			widened by the row being a fraction of its height. A child of height `h` in the row is
			square on screen at a width of `h / rowAspect`, so at the icon's aspect it is
			`h * iconAspect / rowAspect`. ]]
		local bodyAspect = cfg.Size.X / (cfg.Size.Y * UIAssets.BubbleBodyFraction)
		local rowAspect = bodyAspect / rows.Money.Height
		local iconAspect = UIAssets.Size.CashIcon.X / UIAssets.Size.CashIcon.Y
		local iconWidth = cfg.MoneyIconHeight * iconAspect / rowAspect

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5 - cfg.MoneyOffset, 0.5)
		icon.Size = UDim2.fromScale(iconWidth, cfg.MoneyIconHeight)
		icon.BackgroundTransparency = 1
		icon.Image = UIAssets.url(UIAssets.Page.CashIcon)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = money
		table.insert(images, icon)

		local amountLabel = Instance.new("TextLabel")
		amountLabel.Name = "Amount"
		amountLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		amountLabel.Position = UDim2.fromScale(0.5 + cfg.MoneyOffset, 0.5)
		amountLabel.Size = UDim2.fromScale(cfg.MoneyTextWidth, 1)
		amountLabel.BackgroundTransparency = 1
		amountLabel.FontFace = FONT
		amountLabel.Text = "+" .. GarageConfig.formatCash(amount :: number)
		amountLabel.TextColor3 = cfg.Colors.Amount
		amountLabel.TextScaled = true
		amountLabel.Parent = money
		table.insert(texts, amountLabel)
	end

	gui.Parent = anchor
	TweenService:Create(scale, TweenInfo.new(cfg.PopSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	--[[ Debris is the backstop rather than the mechanism: the fade below is what the player sees, and
		this is what guarantees the bubble goes even if the fade thread is cut short by the rig being
		torn down under it. ]]
	local life = cfg.PopSeconds + cfg.HoldSeconds + cfg.FadeSeconds
	Debris:AddItem(gui, life)

	task.delay(cfg.PopSeconds + cfg.HoldSeconds, function()
		if not gui.Parent then
			return
		end
		local info = TweenInfo.new(cfg.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, image in images do
			TweenService:Create(image, info, { ImageTransparency = 1 }):Play()
		end
		for _, label in texts do
			TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		end
	end)
end

--[[ What they thought of the car: a tip and a line, a line on its own, or nothing at all.

	THE CAR IS RE-READ HERE rather than carried from the walk. Half a minute can pass between
	choosing a bay and standing in front of it, and the owner may have moved that car off the podium
	from the dealership screen in the meantime — paying for a car that is no longer there would be
	paying for a rate nothing is earning. ]]
-- A selected tip is a snapshot of the car as it was admired. It is paid once at checkout,
-- including an interrupted trip/plot teardown while the owner's profile is still active.
function CustomerService._checkout(self, customer: Customer)
 local pending = customer.pendingTip
 if customer.checkoutPaid or not pending then return end
 local crowd = customer.crowd
 local Garage = Shard.get("GarageService")
 if not Garage or not Garage:isProfileReady(crowd.player) then return end
 customer.checkoutPaid = true
 customer.pendingTip = nil
 Garage:addCash(crowd.player, pending.amount)
 self:_tallyTip(crowd.player, pending.amount)
 self:getSignal("CustomerPaid"):Fire(crowd.player, pending.amount, pending.bay, pending.body)
 if customer.model.Parent and crowd.player.Parent == Players then
  if CustomerConfig.Reactions.Burst.Enabled then
   Garage:burstCash(crowd.player, pending.amount, customer.root.Position)
  end
  self:_say(customer, CustomerConfig.lineFor(CustomerConfig.Lines.Liked, self._rng, pending.body), pending.amount)
 end
end

function CustomerService._react(self, crowd: Crowd, customer: Customer, bayIndex: number)
 local Garage = Shard.get("GarageService")
 if not Garage or customer.checkoutPaid then return end
 local car, basis
 if GarageConfig.Income.Passive then
  car, basis = Garage:getBayCar(crowd.player, bayIndex)
 else
  local id
  car, id, basis = Garage:getBayTip(crowd.player, bayIndex)
 end
 if not car then return end
 local visit = CustomerConfig.Visit
 local kind = customer.kind or {}
 if self._rng:NextNumber() >= math.min(0.95, visit.LikeChance * (kind.Like or 1)) then
  if self._rng:NextNumber() < visit.BrowseChance then
   self:_emote(customer, CustomerConfig.Reactions.Emoji.Unsure)
   self:_say(customer, CustomerConfig.lineFor(CustomerConfig.Lines.Browsing, self._rng, car.Body), nil)
   self:_dwell(customer, visit.ReactSeconds)
  end
  return
 end
 local passes = Shard.get("PassService")
 local vip = if passes and passes:owns(crowd.player, "VIP") then CustomerConfig.VIP.TipMultiplier else 1
 local emoji = CustomerConfig.Reactions.Emoji
 self:_emote(customer, if kind.Outfit then emoji.Loved else emoji.Liked)
 --[[ PAID FROM THE LOT'S EARNINGS (`CustomerConfig.Income.Ranked`, 2026-10-21): a liked look pays out
  whatever the lot has earned since the last one (`_bank`), so the crowd shows the money and the
  formula decides it. A profile not loaded yet leaves it banked for the next like. ]]
 if CustomerConfig.Income.Ranked and not GarageConfig.Income.Passive then
  local owed = math.floor(crowd.bank or 0)
  if owed > 0 and Garage:isProfileReady(crowd.player) then
   crowd.bank -= owed
   self:_payBanked(crowd, owed, bayIndex, car.Body, customer.root.Position)
  else
   owed = 0
  end
  self:_say(customer, CustomerConfig.lineFor(CustomerConfig.Lines.Liked, self._rng, car.Body), if owed > 0 then owed else nil)
  self:_dwell(customer, visit.ReactSeconds)
  return
 end
 --[[ PAID AS THEY REACT (`CustomerConfig.Visit.PayOnLike`, 2026-10-20: "an NPC can look at a car and say
  'Take my money!' but not actually tip anything until they leave", and the checkout bubble was up for
  half a second). The first car they like pays its tip with the line; a later, better car pays only the
  DIFFERENCE. One jitter per customer (rolled on their first like) makes the tip rise with the car's
  value, so the visit's total is exactly the approved one, the tip for the best car they liked, the
  same thing the checkout below used to pay in one go. A profile not loaded yet keeps the top-up for
  the checkout, which is the old path and still the only one with the flag off. ]]
 if visit.PayOnLike then
  local variance = CustomerConfig.Tip.Variance
  customer.tipJitter = customer.tipJitter or (1 + self._rng:NextNumber(-variance, variance))
  local base = if basis > 0 then math.max(CustomerConfig.Tip.Minimum, math.floor(CustomerConfig.perLook(basis) * customer.tipJitter)) else 0
  local tip = math.round(base * (kind.Tip or 1) * vip * Garage:incomeMultiplier(crowd.player))
  local owed = 0
  if tip > 0 and basis > (customer.tipBasis or -math.huge) then
   owed = math.max(0, tip - (customer.tipPaid or 0))
   customer.tipBasis = basis
  end
  if owed > 0 then
   customer.tipPaid = (customer.tipPaid or 0) + owed
   if Garage:isProfileReady(crowd.player) then
    Garage:addCash(crowd.player, owed)
    self:_tallyTip(crowd.player, owed)
    self:getSignal("CustomerPaid"):Fire(crowd.player, owed, bayIndex, car.Body)
    if CustomerConfig.Reactions.Burst.Enabled then
     Garage:burstCash(crowd.player, owed, customer.root.Position)
    end
   else
    local held = customer.pendingTip
    customer.pendingTip = { basis = basis, amount = (if held then held.amount else 0) + owed, bay = bayIndex, body = car.Body }
   end
  end
  self:_say(customer, CustomerConfig.lineFor(CustomerConfig.Lines.Liked, self._rng, car.Body), if owed > 0 then owed else nil)
  self:_dwell(customer, visit.ReactSeconds)
  return
 end
 local tip = math.round(CustomerConfig.tipFor(basis, self._rng) * (kind.Tip or 1) * vip * Garage:incomeMultiplier(crowd.player))
 if tip > 0 and (not customer.pendingTip or basis > customer.pendingTip.basis) then
  customer.pendingTip = { basis = basis, amount = tip, bay = bayIndex, body = car.Body }
 end
 self:_say(customer, CustomerConfig.lineFor(CustomerConfig.Lines.Liked, self._rng, car.Body), nil)
 self:_dwell(customer, visit.ReactSeconds)
end

-- === One customer's trip ====================================================

--[[ Play the walk clip while they are moving and the idle one while they are not.

	`Humanoid.Running` FIRES ON CHANGE, WITH THE SPEED, which is exactly the event this needs and is
	why there is no per-frame check anywhere in this file. See header note 1 for why an NPC needs
	this at all when a player's character does not.

	The playback speed follows the state rather than the rig, because `RigAnimator.setSpeed` writes
	every track: a walk slowed to match a browsing pace would otherwise leave the idle breathing at
	the same fraction. ]]
function CustomerService._bindAnimation(self, customer: Customer)
	local anim = customer.anim
	if not anim then
		return
	end

	local function apply(speed: number)
		if speed > 0.1 then
			anim:setSpeed(CustomerConfig.Animations.WalkPlaybackSpeed * ((customer :: any).walkScale or 1))
			anim:play("Walk", 0.15)
		else
			anim:setSpeed(1)
			anim:play("Idle", 0.2)
		end
	end

	customer.trove:Add(customer.humanoid.Running:Connect(apply))
	apply(0)
end

--[[ One customer, from the moment they are standing on the forecourt to the moment they are gone.

	Every step can be cut short — by the plot being released, by a leg that could not be walked, or
	by the trip watchdog — and every one of those ends in the same place: the walk to the exit and
	`_despawn`. There is no branch that leaves a rig standing in the showroom.

	A bay that could not be REACHED ends the trip, while a bay with nowhere to stand only skips that
	bay: the first says something is wrong with getting around this lot at all, and the second says
	one podium is walled in. Both blacklist the bay for `Walk.BlockSeconds` so the rest of the crowd
	does not queue up behind the same problem. ]]
function CustomerService._trip(self, crowd: Crowd, customer: Customer)
	local visit = CustomerConfig.Visit
	local stops = self._rng:NextInteger(visit.PerBay.Min, visit.PerBay.Max)

	for _ = 1, stops do
		if not customer.live then
			break
		end

		local bay = self:_pickBay(crowd, customer)
		if not bay then
			break
		end

		local stand = self:_standFor(crowd, bay)
		if not stand then
			crowd.blocked[bay.index] = os.clock() + CustomerConfig.Walk.BlockSeconds
			self.log:info(string.format("Bay %d on %s has nowhere to stand — customers will skip it.", bay.index, crowd.plot.Name))
			continue
		end

		crowd.busy[bay.index] = true
		customer.bay = bay.index
		customer.seen[bay.index] = true

		local reached = self:_travel(crowd, customer, stand.position)
		if reached then
			self:_face(customer, stand.look)
			if self:_dwell(customer, CustomerConfig.rollRange(visit.LookSeconds, self._rng)) then
				self:_react(crowd, customer, bay.index)
			end
		else
			crowd.blocked[bay.index] = os.clock() + CustomerConfig.Walk.BlockSeconds
		end

		crowd.busy[bay.index] = nil
		customer.bay = nil
		if not reached then
			break
		end
	end

	if customer.live then
		-- The result is not checked: whether they made it back to the forecourt or gave up halfway,
		-- the next thing that happens to them is the same.
		self:_travel(crowd, customer, self:_forecourt(crowd).Position)
	end
	self:_despawn(customer)
end

--[[ Put one customer on the forecourt and start their trip.

	Placed while still unparented and parented afterwards, so nobody is ever on screen standing at
	the world origin for a frame — the same order `GarageService._buildDisplayCar` places a car in.

	The lift is the rig's OWN hip height plus half its root, read off the clone rather than assumed,
	because a `HumanoidDescription` carries body scale: a friend with a tall avatar has a taller root
	and would otherwise arrive with their feet through the slab. ]]
function CustomerService._spawn(self, crowd: Crowd, floor: number?): boolean
	local face = self:_pickFace(crowd)
	if not face then
		return false
	end

	local model = face.model:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		model:Destroy()
		return false
	end

	model:PivotTo(self:_forecourt(crowd) + crowd.origin.UpVector * (humanoid.HipHeight + root.Size.Y / 2))
	model.Parent = crowd.folder

	local trove = Trove.new()
	trove:Add(model)

	local passes = Shard.get("PassService")
	local isVIP = passes ~= nil and passes:owns(crowd.player, "VIP")
	local customer: Customer = {
		crowd = crowd,
		model = model,
		humanoid = humanoid,
		root = root :: BasePart,
		face = face.model,
		anim = if CustomerConfig.Animations.Enabled then RigAnimator.new(model, CustomerConfig.Animations.Clips) else nil,
		trove = trove,
		live = true,
		expires = os.clock() + CustomerConfig.Visit.MaxSeconds,
		bay = nil,
		seen = {},
		floor = floor or 1,
		kind = CustomerConfig.pickKind(self._rng, isVIP),
	}
	self:_dress(customer)
	self:_tag(customer, face.name)

	crowd.customers[customer] = true
	self:_tallyVisit(crowd.player)
	self:_bindAnimation(customer)
	task.spawn(function()
		self:_trip(crowd, customer)
	end)
	return true
end

--[[ Take one customer out of the world.

	The fade is a handful of property writes per part and it is the difference between a person
	leaving and a person being deleted; `CustomerConfig.FadeSeconds = 0` turns it off. Transparency
	is raised FROM whatever each part already had rather than set flat, because a character is not
	uniformly opaque — the root is invisible, and forcing it to the fade value would make it appear
	on the way out. ]]
function CustomerService._despawn(self, customer: Customer)
	if not customer.live then
		return
	end
	self:_checkout(customer)
	customer.live = false

	local crowd = customer.crowd
	crowd.customers[customer] = nil
	if customer.bay then
		crowd.busy[customer.bay] = nil
		customer.bay = nil
	end
	--- Every `Rotate.Every` departures, a fresh friend's face (`_rotateFace`). After the removal above,
	--- so the face that just left counts as free.
	local rotate = CustomerConfig.Friends.Rotate
	if rotate and rotate.Enabled and crowd.player then
		crowd.departures = (crowd.departures or 0) + 1
		if crowd.departures % math.max(1, rotate.Every) == 0 then
			self:_rotateFace(crowd.player)
		end
	end

	local seconds = CustomerConfig.FadeSeconds
	if seconds > 0 and customer.model.Parent then
		customer.humanoid.WalkSpeed = 0

		local originals: { { inst: Instance, from: number } } = {}
		for _, inst in customer.model:GetDescendants() do
			if inst:IsA("BasePart") then
				table.insert(originals, { inst = inst, from = inst.Transparency })
			elseif inst:IsA("Decal") or inst:IsA("Texture") then
				table.insert(originals, { inst = inst, from = inst.Transparency })
			end
		end

		local steps = math.max(1, math.round(seconds / 0.06))
		for step = 1, steps do
			if not customer.model.Parent then
				break
			end
			local alpha = step / steps
			for _, entry in originals do
				(entry.inst :: any).Transparency = entry.from + (1 - entry.from) * alpha
			end
			task.wait(seconds / steps)
		end
	end

	customer.trove:Destroy()
end

-- === The crowd ==============================================================

--[[ Is this player's lot kept empty of customers for the tutorial? Yes from their first beat until
	they answer the tutorial buyer (`BuyerConfig.Tutorial.Beat`), so the one person who walks up to
	their first car is the buyer (Dylan: "we just have one npc come up and that is the offer npc").
	Customers come back with the beat after it. A customer already on the lot is left to finish their
	visit; this only stops new ones. Off the step attribute, so no service dependency. ]]
function CustomerService._heldForTutorial(self, player: Player?): boolean
	local tutorial = BuyerConfig.Tutorial
	if not (player and tutorial.Enabled and tutorial.SoleNpc and TutorialConfig.isOn()) then
		return false
	end
	local index = TutorialConfig.indexOf(player:GetAttribute(TutorialConfig.StepAttribute))
	local until_ = TutorialConfig.indexOf(tutorial.Beat)
	return index ~= nil and until_ ~= nil and index <= until_
end

--[[ How many customers this lot should have right now.

	NONE UNTIL THERE IS SOMETHING TO LOOK AT. A lot with no cars gets no customers, which is
	`CustomerConfig`'s header note 2 — an empty bay is what the run loop exists to fill, and a
	customer admiring one would say the opposite. It also means a brand new player's first customer
	arrives right after their first bank, which is a better first impression than a crowd that was
	already there.

	CAPPED BY OCCUPIED BAYS as well as by the upgrade, so a one-car lot gets one customer instead of
	two taking turns at the same podium.

	Zero while the profile is still loading: everything below is derived from it, and a crowd built
	against an empty profile would be a crowd built against an empty lot.

	ZERO THROUGH THE TUTORIAL'S OFFER, too (`BuyerConfig.Tutorial.SoleNpc`, 2026-10-19): see
	`_heldForTutorial`. ]]
function CustomerService._wantedFloor(self, crowd: Crowd, floor: number): number
 local Garage = Shard.get("GarageService")
 if not Garage or not Garage:isProfileReady(crowd.player) then return 0 end
 if self:_heldForTutorial(crowd.player) then return 0 end
 local occupied = 0
 for _, entry in self:_occupied(crowd) do
  if CustomerConfig.floorForBay(entry.bay.index) == floor then occupied += 1 end
 end
 return math.min(CustomerConfig.capacityForFloor(Garage:getUpgrades(crowd.player), floor), occupied)
end
function CustomerService._wantedCount(self, crowd: Crowd): number
 return self:_wantedFloor(crowd, 1) + self:_wantedFloor(crowd, 2)
end
--[[ The lot's earnings since its last paid like (`CustomerConfig.Income.Ranked`): the formula's rate
	(`OfflineService.liveRate`, the HUD line's own figure) for every second the lot has a crowd, which
	is when the old crowd could earn at all (no cars, a profile loading, the tutorial's held offer:
	nothing). Kept on the crowd, paid out by `_react` and, whatever is left, by `_release`. ]]
function CustomerService._bank(self, crowd: Crowd)
 local now = os.clock()
 local since = now - (crowd.bankAt or now)
 crowd.bankAt = now
 if not CustomerConfig.Income.Ranked or GarageConfig.Income.Passive then return end
 local Offline = Shard.get("OfflineService")
 if Offline and since > 0 and self:_wantedCount(crowd) > 0 then
  crowd.bank = (crowd.bank or 0) + Offline:liveRate(crowd.player) * since
 end
end

--- Pay `amount` of the lot's earnings: the cash, the summary tally, the signal quests and the tutorial
--- read, and the burst at `at` when there is a customer to burst from.
function CustomerService._payBanked(self, crowd: Crowd, amount: number, bay: number?, body: string?, at: Vector3?)
 local Garage = Shard.get("GarageService")
 if not Garage then return end
 Garage:addCash(crowd.player, amount)
 self:_tallyTip(crowd.player, amount)
 self:getSignal("CustomerPaid"):Fire(crowd.player, amount, bay, body)
 if at and CustomerConfig.Reactions.Burst.Enabled then
  Garage:burstCash(crowd.player, amount, at)
 end
end

function CustomerService._tend(self, crowd: Crowd)
 if not crowd.live then return end
 self:_bank(crowd)
 local alive = {0, 0}
 for customer in crowd.customers do
  local floor = customer.floor or 1
  alive[floor] += 1
 end
 crowd.nextSpawnByFloor = crowd.nextSpawnByFloor or {0, 0}
 local now = os.clock()
 for floor = 1, 2 do
  if alive[floor] < self:_wantedFloor(crowd, floor) and now >= crowd.nextSpawnByFloor[floor] then
   if self:_spawn(crowd, floor) then
    crowd.nextSpawnByFloor[floor] = now + CustomerConfig.rollRange(CustomerConfig.Crowd.ArrivalGap, self._rng)
   else
    crowd.nextSpawnByFloor[floor] = now + 2
   end
  end
 end
end

--[[ Redraw nothing, walk nobody: the loop only asks each lot whether it is short a customer.

	One service-level loop over every crowd rather than a thread per lot, the same shape (and the
	same reasoning) as `GarageService._labelLoop`: six lots at `Crowd.CheckInterval` is a handful of
	table counts a second, and one loop cannot leak a thread when a plot is released. ]]
function CustomerService._tendLoop(self)
	local accumulator = 0
	return RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < CustomerConfig.Crowd.CheckInterval then
			return
		end
		accumulator = 0
		for _, crowd in self._crowds do
			self:_tend(crowd)
		end
	end)
end

--[[ Bind a plot to its owner's crowd.

	Everything the crowd touches hangs off its trove — the folder its rigs live in, and the flag every
	customer's loops check — so releasing a lot is one `Destroy` and cannot leave a customer walking
	around a plot that now belongs to somebody else.

	The query params are built ONCE PER CROWD rather than per query. They are scoped to the plot (see
	`_groundAt`), which is a per-crowd fact, and the alternative is two allocations per waypoint. ]]
function CustomerService._claim(self, player: Player, plot: Model)
	if self._crowds[player] then
		return
	end
	local origin = plot.PrimaryPart
	if not origin then
		self.log:warn(string.format("%s has no PrimaryPart — no customers can be placed on it.", plot.Name))
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = plot.Name
	folder.Parent = self._folder

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { plot }

	local boxParams = OverlapParams.new()
	boxParams.FilterType = Enum.RaycastFilterType.Include
	boxParams.FilterDescendantsInstances = { plot }
	--[[ One part is all the answer this needs — every caller asks "is anything here?" and none of
		them filters what comes back, which is the one condition under which capping the query is
		safe. A cap truncates the QUERY, not the results. ]]
	boxParams.MaxParts = 1

	local trove = Trove.new()
	local crowd: Crowd = {
		player = player,
		plot = plot,
		origin = origin.CFrame,
		folder = folder,
		trove = trove,
		customers = {},
		busy = {},
		blocked = {},
		buyers = {},
		held = {},
		leaving = {},
		nextSpawn = 0,
		nextSpawnByFloor = { 0, 0 },
		live = true,
		rayParams = rayParams,
		boxParams = boxParams,
	}

	trove:Add(function()
		crowd.live = false
		-- Flip every live customer BEFORE the folder goes, so their loops exit on the flag rather
		-- than on a destroyed root — the same beat, but one that runs no further code.
		for customer in crowd.customers do
			self:_checkout(customer)
			customer.live = false
		end
		crowd.customers = {}
		--- Buyers go with the lot. Their OFFERS do not — those are in the save, and the next lot this
		--- player claims gets its buyers rebuilt from them (`BuyerService`).
		for _, buyer in crowd.buyers do
			buyer.trove:Destroy()
		end
		crowd.buyers = {}
		crowd.held = {}
		for trove in crowd.leaving do
			trove:Destroy()
		end
		crowd.leaving = {}
	end)
	trove:Add(folder)

	self._crowds[player] = crowd
	self:_buildFriendFaces(player)
end

function CustomerService._release(self, player: Player)
	local crowd = self._crowds[player]
	if not crowd then
		return
	end
	self._crowds[player] = nil
	--- What the lot earned since its last paid like is paid now rather than lost with the crowd.
	self:_bank(crowd)
	local owed = math.floor(crowd.bank or 0)
	local Garage = Shard.get("GarageService")
	if owed > 0 and Garage and Garage:isProfileReady(player) then
		crowd.bank = 0
		self:_payBanked(crowd, owed)
	end
	crowd.trove:Destroy()
end

-- === Lifecycle ==============================================================

-- === Buyers =================================================================
--[[ THE BUYER'S BODY (2026-09-28). `BuyerService` owns the offer — who, how much, until when — and
	asks this file to stand a person next to the car; this file owns the rig, because it already owns
	the faces, the collision group, the plot's ground and clearance queries and the idle clip, and a
	second rig-builder would be a second copy of all of them.

	A BUYER STANDS BESIDE THE CAR, anchored, idling, for as long as the offer does. It first appeared
	there outright; since 2026-09-28 a FRESH one walks in off the forecourt (`BuyerConfig.Stand.WalkIn`)
	and its offer only opens — sign, prompt, clock — once it is there (`BuyerArrived`). A rig rebuilt
	from the save on a rejoin still just IS there, because that buyer has already been waiting.

	The rig carries the offer as attributes (`BuyerController` draws the sign off them for everybody)
	and an owner-only prompt that fires `BuyerPressed`. It is tagged `BUYER_TAG` so the client can find
	every buyer on every lot without a remote. ]]

--- The CollectionService tag every buyer rig wears, and the attribute names it carries. Constants
--- here rather than in `BuyerConfig` because they are the wire between this file and one controller,
--- not something anybody tunes.
local BUYER_TAG = "Buyer"
local BUYER_ATTRIBUTES = {
	Owner = "BuyerOwner", -- UserId of the lot's owner, so the client knows whose prompt it is
	CarId = "BuyerCarId",
	Amount = "BuyerOffer",
	ExpiresAt = "BuyerExpiresAt", -- os.time(); the client counts down against GetServerTimeNow
	Name = "BuyerName", -- display name, or absent for a nameless fallback rig
	Body = "BuyerBody",
	--[[ true once the buyer is standing at the car (2026-09-28). The client draws no sign before it, so
		an offer does not open while its buyer is still crossing the forecourt. ]]
	Arrived = "BuyerArrived",
	Kind = "BuyerKind", -- `BuyerConfig.Kinds` key, absent for a Regular (2026-10-06)
	--- The friend whose avatar the rig wears, for the sign's headshot (2026-10-15); absent on a
	--- fallback rig, which gets the kit's silhouette instead.
	UserId = "BuyerUserId",
}
CustomerService.BuyerTag = BUYER_TAG
CustomerService.BuyerAttributes = BUYER_ATTRIBUTES

--[[ Where a buyer stands at one bay: beside the podium, left then right, fitted outwards a stud at a
	time until the rig's own footprint is clear (`BuyerConfig.Stand` has why beside and not in front).
	Falls back to the customers' viewing spot, and says so (`front = true`) so the caller can keep
	customers off it. Nil when neither fits. ]]
function CustomerService._buyerSpot(self, crowd: Crowd, bay): { position: Vector3, look: Vector3, front: boolean }?
	local base, deck = bay.base, bay.deck
	if not (base and base.Parent and deck and deck.Parent) then
		return nil
	end
	local stand = BuyerConfig.Stand
	local view = CustomerConfig.View
	local up = crowd.origin.UpVector

	--- In front first, where a person looking at a car stands (`BuyerConfig.Stand.Front`); `front` is
	--- what makes `placeBuyer` hold the bay so no customer stacks on the same car.
	if stand.Front then
		local front = self:_standFor(crowd, bay)
		if front then
			return { position = front.position, look = front.look, front = true }
		end
	end

	--[[ A side spot inside ANOTHER bay's footprint is no spot (2026-10-06, Leaf's "this dude is
		here"): the clearance box only sees the plot's walls, so an empty podium next door read as
		clear floor and the buyer stood on it. Measured on Plot1 with Floor 2: bay 11's buyer landed
		inside bay 10. Same floor only, so a deck overhead does not rule out the aisle below it. ]]
	local GarageService = Shard.get("GarageService")
	local others = if GarageService then GarageService:getBays(crowd.player) else {}
	local function inAnotherBay(position: Vector3): boolean
		for _, other in others do
			local otherBase = other.base
			if other == bay or not (otherBase and otherBase.Parent) then
				continue
			end
			local l = otherBase.CFrame:PointToObjectSpace(position)
			if math.abs(l.X) < otherBase.Size.X / 2 and math.abs(l.Z) < otherBase.Size.Z / 2 and math.abs(l.Y) < 8 then
				return true
			end
		end
		return false
	end

	for _, side in { -1, 1 } do
		for out = stand.Side, stand.MaxSide do
			local spot = base.CFrame * CFrame.new(side * (base.Size.X / 2 + out), 0, 0)
			local ground = self:_groundAt(crowd, spot.Position + up * 12)
			if ground and not inAnotherBay(ground) then
				local at = crowd.origin.Rotation + (ground + up * (view.Clearance.Y / 2 + 0.5))
				if #workspace:GetPartBoundsInBox(at, view.Clearance, crowd.boxParams) == 0 then
					return { position = ground + up * 3, look = deck.Position + up * 3, front = false }
				end
			end
		end
	end

	--[[ BY THE CAR, ON ITS OWN FLOOR, BEFORE THE FORECOURT (2026-10-13: "if an NPC offers for a car
		that's on the second floor, they're on the bottom floor near the entrance"). Upstairs bays sit
		on a narrow deck by a railing, so their fitted front and side spots fail more often, and every
		failure fell straight through to the forecourt waiting line below. Now the podium's nominal
		front at `View.Standoff` is taken first, unfitted: a buyer brushing a railing beside the car
		beats one stood downstairs by the door. Still `front = false`, for the line below's reason. ]]
	--[[ ...and ON THAT FLOOR (same day, second pass: the first cut stood the buyer on the upstairs
		railing, because the podium's front faces the atrium and the ray took the rail's top for floor).
		A spot counts only if its floor is level with the podium's own (`base`'s underside, within
		`LEVEL_SLACK`), which rules out railings and the storey below; searched outward from right in
		front of the podium so a narrow deck still finds the strip it has. ]]
	local LEVEL_SLACK = 1.5
	local floorLevel = crowd.origin:PointToObjectSpace(base.Position).Y - base.Size.Y / 2
	for standoff = 2, view.MaxStandoff do
		local ahead = base.CFrame * CFrame.new(0, 0, -(base.Size.Z / 2 + standoff))
		local floor = self:_groundAt(crowd, ahead.Position + up * 12)
		if floor and math.abs(crowd.origin:PointToObjectSpace(floor).Y - floorLevel) <= LEVEL_SLACK then
			return { position = floor + up * 3, look = deck.Position + up * 3, front = false }
		end
	end

	-- A failed side position must never reserve a paying browser's front spot.
 local count = 0
 for _ in crowd.buyers do count += 1 end
 local waiting = crowd.origin * CFrame.new(-10 + count * 6, 0, CustomerConfig.Arrival.LocalZ - 6)
 local ground = self:_groundAt(crowd, waiting.Position + up * 12)
 if ground then return {position = ground + up * 3, look = deck.Position + up * 3, front = false} end
 return nil
end

--[[ Public (BuyerService): stand a buyer beside the car on `bayIndex` for the offer on `carId`.
	Returns the name the buyer wears (or "" for a nameless one) when a rig now stands there, nil when
	it could not be built yet — no lot, no face built yet, or nowhere to stand. NIL IS NOT AN ERROR:
	`BuyerService` asks again on its next pass, which is how a buyer appears once the friends'
	avatars finish loading or the owner's plot is claimed.

	Idempotent: a car that already has a buyer standing by it keeps that one and answers its name.

	`walkIn` (2026-09-28, `BuyerConfig.Stand.WalkIn`): true for a buyer whose offer was only just made,
	who starts on the forecourt and walks to the car; false or nil for one rebuilt from the save, who
	is simply stood in place. The name comes back straight away either way — the rig exists from the
	first frame, it is only its position that is still moving.

	`walkSpeed` (2026-10-20): a walk-in at this pace instead of the browsing one, its stride sped to
	match. The tutorial's buyer (`BuyerConfig.Tutorial.WalkSpeed`); nil for everyone else. ]]
function CustomerService.placeBuyer(self, player: Player, bayIndex: number, carId: string, offer: { Amount: number, ExpiresAt: number, Kind: string? }, walkIn: boolean?, walkSpeed: number?): string?
	local crowd = self._crowds[player]
	if not (crowd and crowd.live) then
		return nil
	end
	local existing = crowd.buyers[carId]
	if existing then
		return existing.name
	end

	local GarageService = Shard.get("GarageService")
	local bay = nil
	for _, candidate in (if GarageService then GarageService:getBays(player) else {}) do
		if candidate.index == bayIndex then
			bay = candidate
			break
		end
	end
	if not bay then
		return nil
	end

	local face = self:_pickFace(crowd)
	local spot = face and self:_buyerSpot(crowd, bay)
	if not (face and spot) then
		return nil
	end

	local model = face.model:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		model:Destroy()
		return nil
	end

	--[[ ATOMIC, because the place streams (`StreamingEnabled`) and the client builds the sign the moment
		the tagged model arrives: streamed part by part, the model can land without its Head, and a
		sign with nothing to hang on is a buyer with no price over them. ]]
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	--- The rig's own lift, off its hip height, for standing it on the spot — `_spawn`'s arithmetic. The
	--- spot is the ground plus 3 (`_buyerSpot`), hence the 3 taken back off.
	local lift = crowd.origin.UpVector * (humanoid.HipHeight + root.Size.Y / 2 - 3)
	local flatLook = Vector3.new(spot.look.X, spot.position.Y, spot.look.Z)
	local standing = CFrame.lookAt(spot.position + lift, flatLook + lift)
	local walking = walkIn == true and BuyerConfig.Stand.WalkIn

	if walking then
		--- Where every customer comes in, and lifted the same way `_spawn` lifts one.
		model:PivotTo(self:_forecourt(crowd) + crowd.origin.UpVector * (humanoid.HipHeight + root.Size.Y / 2))
	else
		model:PivotTo(standing)
	end

	local name = face.name or ""
	model:SetAttribute(BUYER_ATTRIBUTES.Owner, player.UserId)
	model:SetAttribute(BUYER_ATTRIBUTES.CarId, carId)
	model:SetAttribute(BUYER_ATTRIBUTES.Amount, offer.Amount)
	model:SetAttribute(BUYER_ATTRIBUTES.ExpiresAt, offer.ExpiresAt)
	if type(offer.Kind) == "string" then
		model:SetAttribute(BUYER_ATTRIBUTES.Kind, offer.Kind)
	end
	if name ~= "" then
		model:SetAttribute(BUYER_ATTRIBUTES.Name, name)
	end
	if type(face.id) == "number" then
		model:SetAttribute(BUYER_ATTRIBUTES.UserId, face.id)
	end
	model:SetAttribute(BUYER_ATTRIBUTES.Body, (GarageConfig.parseCarKey(carId)))

	local trove = Trove.new()
	trove:Add(model)

	--[[ THE BUYER AS A WALKER: the same record shape a customer is, because `_walkTo`, `_face` and
		`_bindAnimation` are written against that shape and a buyer walks in exactly as a customer
		does. `live` is what `removeBuyer` flips to stop a walk that is still going — an offer can be
		cancelled while its buyer is halfway across the showroom. ]]
	local walker = {
		model = model,
		humanoid = humanoid,
		root = root :: BasePart,
		anim = if CustomerConfig.Animations.Enabled then RigAnimator.new(model, CustomerConfig.Animations.Clips) else nil,
		trove = trove,
		live = true,
		expires = os.clock() + CustomerConfig.Visit.MaxSeconds,
		--- The stride's share of the browsing one, so a faster walker's feet keep up (`_bindAnimation`).
		walkScale = if walking and walkSpeed then walkSpeed / CustomerConfig.Walk.Speed else nil,
	}
	if walking and walkSpeed then
		humanoid.WalkSpeed = walkSpeed
	end

	--[[ ONE PROMPT, OWNER-ONLY BY CHECK. Anybody walking the lot can read the sign; only the owner can
		answer it, and that is enforced here rather than by hiding the prompt — `Enabled` is a property
		a client can flip. `BuyerController` hides it on every other client so they are not offered a
		button that would refuse.

		ADDED ON ARRIVAL, NOT AT SPAWN, so a buyer cannot be answered mid-stride. It is a NEW instance
		rather than a disabled one switched on: a server write to `Enabled` would replicate over the
		client's own switch-off and hand every visitor the owner's button. `BuyerController` watches
		the root for it to appear. ]]
	local function arrive()
		if not walker.live then
			return
		end
		humanoid.WalkSpeed = 0
		--- Anchored once there: a buyer is a person waiting, and an anchored root cannot be shoved off
		--- its spot by a player walking through the showroom or by the next customer's path.
		root.Anchored = true
		if walker.anim then
			walker.anim:setSpeed(1)
			walker.anim:play("Idle", 0.2)
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BuyerPrompt"
		prompt.ActionText = BuyerConfig.Prompt.ActionText
		prompt.ObjectText = if name ~= "" then name else ""
		prompt.HoldDuration = BuyerConfig.Prompt.HoldDuration
		prompt.MaxActivationDistance = BuyerConfig.Prompt.MaxDistance
		prompt.RequiresLineOfSight = false
		trove:Add(prompt.Triggered:Connect(function(presser: Player)
			if presser == player then
				self:getSignal("BuyerPressed"):Fire(player, carId)
			end
		end))
		prompt.Parent = root

		--[[ THE OFFER OPENS HERE, NOT AT THE SPAWN. The signal first, so `BuyerService` can restart a
			walker's clock (and `setBuyerDeadline` rewrite the attribute) before the attribute below tells
			every client to draw the sign — in that order, so the sign's first frame shows the full five
			minutes rather than jumping back up to it. ]]
		self:getSignal("BuyerArrived"):Fire(player, carId, walking)
		model:SetAttribute(BUYER_ATTRIBUTES.Arrived, true)
	end

	model.Parent = crowd.folder
	CollectionService:AddTag(model, BUYER_TAG)
	trove:Add(function()
		walker.live = false
	end)

	crowd.buyers[carId] = { trove = trove, name = name, bay = bayIndex, front = spot.front, walker = walker }
	if spot.front then
		crowd.held[bayIndex] = true
	end

	if walking then
		--- The walk clip while moving and the idle while not, off `Humanoid.Running` — the customers'
		--- own binding, so a buyer walks in looking exactly like one.
		self:_bindAnimation(walker)
		walker.animBound = true
		task.spawn(function()
			local reached = self:_travel(crowd, walker, spot.position)
			if not walker.live then
				return
			end
			if reached then
				self:_face(walker, spot.look)
			end
			--- Reached or not, the buyer ends on their spot facing the car (`BuyerConfig.Stand.WalkIn`):
			--- a short snap after a blocked path is better than a buyer stranded mid-forecourt.
			if walker.live and root.Parent then
				model:PivotTo(standing)
			end
			arrive()
		end)
	else
		arrive()
	end
	return name
end

--- Public (BuyerService): send the buyer for this car away. A car with no buyer is a no-op.
function CustomerService.removeBuyer(self, player: Player, carId: string)
	local crowd = self._crowds[player]
	local buyer = crowd and crowd.buyers[carId]
	if not buyer then
		return
	end
	crowd.buyers[carId] = nil
	if buyer.front then
		crowd.held[buyer.bay] = nil
	end
	buyer.trove:Destroy()
end

--[[ Public (SellerService): one of this lot's faces, standing idle with its feet on `at` and facing
	its LookVector, parented to `parent`. The caller owns the rig and destroys it. nil when the lot has
	no crowd yet or no face to wear, and a seller with no person beside the car is still a seller.

	`clips` replaces the crowd's own (`CustomerConfig.Animations.Clips`) so the caller can add poses
	the crowd never needs (a seller sits in their car), and the animator comes back with the rig so
	the caller can switch between them. It starts on "Idle". nil animator: animations are off.

	A CROWD FACE, so the person selling you a car is off your friends list the way the people
	browsing your showroom are, and the faces stay this file's business. ]]
function CustomerService.standSeller(self, player: Player, at: CFrame, parent: Instance, clips: { [string]: any }?): (Model?, any?)
	local crowd = self._crowds[player]
	local face = crowd and crowd.live and self:_pickFace(crowd)
	if not face then
		return nil, nil
	end
	local model = face.model:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		model:Destroy()
		return nil, nil
	end
	--- Anchored for `placeBuyer`'s reason: a person waiting must not be shoved off the kerb.
	root.Anchored = true
	model:PivotTo(at + at.UpVector * (humanoid.HipHeight + root.Size.Y / 2))
	if face.name and face.name ~= "" then
		model:SetAttribute("SellerName", face.name)
	end
	--- The friend behind the avatar, for the face on the seller's sign (`SellerConfig.Attributes.UserId`).
	if face.id then
		model:SetAttribute("SellerUserId", face.id)
	end
	model.Parent = parent
	local anim = nil
	if CustomerConfig.Animations.Enabled then
		anim = RigAnimator.new(model, clips or CustomerConfig.Animations.Clips)
		anim:play("Idle", 0)
	end
	return model, anim
end

--- Public (SellerService): pop `face` over a rig's head for `seconds`, the crowd's own emoji bubble
--- (`_emote`), so a seller's 😠 or 😄 looks exactly like a buyer's.
function CustomerService.emoteOver(self, rig: Model, face: string, seconds: number)
	local root = rig.PrimaryPart
	if root then
		self:_emote({ model = rig, root = root, live = true } :: any, face, 0, seconds)
	end
end

--[[ Public (BuyerService): the owner turned this buyer down (2026-10-13, punch list A4,
	`BuyerConfig.Declined`). Where `removeBuyer` deletes the rig, this lets the person leave: the face
	pops, they hold a beat, turn away and walk to the forecourt, then fade as a customer does.

	THE OFFER IS OVER FROM THE FIRST LINE. The record leaves `buyers` and the bay is un-held before any
	of the walk, so a new buyer can be placed for the same car while this one is still on the lot. The
	tag comes off too: every client takes the sign down on it (`BuyerController._unbind`), and the
	tutorial's arrow and the admin list both read buyers off that tag, so neither points at somebody
	who is leaving. The walking rig is kept in `leaving` so a released lot still tears it down.

	A buyer with nobody to animate (torn down already, or the feature off) is removed outright. ]]
function CustomerService.sendBuyerAway(self, player: Player, carId: string)
	local crowd = self._crowds[player]
	local buyer = crowd and crowd.buyers[carId]
	if not buyer then
		return
	end
	local cfg = BuyerConfig.Declined
	local walker = buyer.walker
	if not (cfg.Enabled and crowd.live and walker.live and walker.model.Parent) then
		self:removeBuyer(player, carId)
		return
	end

	crowd.buyers[carId] = nil
	if buyer.front then
		crowd.held[buyer.bay] = nil
	end
	crowd.leaving[buyer.trove] = true

	local model, root, humanoid = walker.model, walker.root, walker.humanoid
	CollectionService:RemoveTag(model, BUYER_TAG)
	local prompt = root:FindFirstChild("BuyerPrompt")
	if prompt then
		prompt:Destroy()
	end
	--- Over the head (no side offset): a buyer has no speech bubble to make room for.
	self:_emote(walker, cfg.Emoji, 0, cfg.EmojiSeconds)

	task.spawn(function()
		local emote = nil
		if type(cfg.Emote) == "number" then
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator then
				emote = animator:LoadAnimation(RigAnimator.animation(cfg.Emote))
				emote:Play(0.15)
			end
		end
		task.wait(cfg.HoldSeconds)
		if emote then
			emote:Stop(0.2)
		end

		if walker.live and root.Parent then
			local exit = self:_forecourt(crowd).Position
			--- A buyer who waited out most of an offer is past the trip clock `placeBuyer` started.
			walker.expires = os.clock() + cfg.MaxWalkSeconds
			root.Anchored = false
			humanoid.WalkSpeed = cfg.WalkSpeed
			if not walker.animBound then
				self:_bindAnimation(walker)
				walker.animBound = true
			end
			self:_face(walker, exit)
			self:_travel(crowd, walker, exit)
		end
		if walker.live and model.Parent then
			humanoid.WalkSpeed = 0
			self:_fadeTo(walker, 1, CustomerConfig.FadeSeconds)
		end
		crowd.leaving[buyer.trove] = nil
		buyer.trove:Destroy()
	end)
end

--- Public (BuyerService): move the deadline a buyer's sign counts down to, after `BuyerService` has
--- restarted the offer's clock on arrival. A car with no buyer is a no-op.
function CustomerService.setBuyerDeadline(self, player: Player, carId: string, expiresAt: number)
	local crowd = self._crowds[player]
	local buyer = crowd and crowd.buyers[carId]
	if buyer and buyer.walker.model.Parent then
		buyer.walker.model:SetAttribute(BUYER_ATTRIBUTES.ExpiresAt, expiresAt)
	end
end

--- Public (BuyerService): is a buyer standing by this car right now? The rig check's question.
function CustomerService.hasBuyer(self, player: Player, carId: string): boolean
	local crowd = self._crowds[player]
	return crowd ~= nil and crowd.buyers[carId] ~= nil
end

-- === While you were driving =================================================
--[[ THE RUN SUMMARY (2026-09-28): how many people walked the lot and what they tipped while the owner
	was out on a run. Customers keep coming during a run — nothing here stops a crowd because its owner
	is driving — and without this the money arrives in a cash counter the driving HUD is hiding, so
	the reason the dealership is worth having would be invisible at the one moment it is working.

	A TALLY IS OPENED ON `RaceEntered` AND SENT ON `RaceLeft`, and only a player with an open tally is
	counted. So lobby visits are not in it (the owner can watch those happen), and a player who leaves
	mid-run just has their tally dropped with the rest of their state. ]]
function CustomerService._tallyVisit(self, player: Player)
	local tally = self._tallies[player]
	if tally then
		tally.visitors += 1
	end
end

function CustomerService._tallyTip(self, player: Player, amount: number)
	local tally = self._tallies[player]
	if tally then
		tally.tips += amount
	end
end

--- Send the run's summary, and close the tally. Silent for a run nobody visited during — a card
--- saying "0 customers" is the game pointing at an empty showroom for no reason.
function CustomerService._sendSummary(self, player: Player)
	local tally = self._tallies[player]
	self._tallies[player] = nil
	if not CustomerConfig.Summary.Enabled then
		return
	end
	--[[ Buyers WAITING, not buyers who came: a buyer who arrived and left mid-run is nothing the player
		can act on, and one still standing by a car is the most useful line on the card. Looked up
		rather than declared — `BuyerService` depends on this file, not the other way round. ]]
	local Buyers = Shard.get("BuyerService")
	local buyers = if Buyers then Buyers:waitingCount(player) else 0
	if not tally or (tally.visitors <= 0 and tally.tips <= 0 and buyers <= 0) or player.Parent ~= Players then
		return
	end
	self:getRemoteEvent("ShowroomSummary"):Fire(player, { visitors = tally.visitors, tips = tally.tips, buyers = buyers })
end

CustomerService:withLifecycle({
	init = function(self)
		self._crowds = {} :: { [Player]: Crowd }
		--- [Player] = the run tally, while that player is out on a run. See "While you were driving".
		self._tallies = {} :: { [Player]: { visitors: number, tips: number } }
		self._faces = {} :: { [Player]: { pending: boolean, faces: { Face } } }
		self._fallback = {} :: { Face }
		self._rng = Random.new()
		self._trove = Trove.new()

		if not (CustomerConfig.Enabled and PlotConfig.Enabled and GarageConfig.Enabled) then
			self.log:info("Disabled by config — no customers will visit.")
			return
		end

		--[[ Before the first rig is built, because `_prepareRig` puts one in a group that has to
			exist by then — and before the first character loads, because a character that spawned
			untagged is one an NPC can still walk into. Both are safe here: `PlotService` takes
			character loading over and does it in its `start`, which is after every `init`. ]]
		CrowdCollision.bindPlayers()

		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = workspace
		self._folder = folder
		self._trove:Add(folder)

		self:_buildFallbackFaces()
	end,

	start = function(self)
		if not (CustomerConfig.Enabled and PlotConfig.Enabled and GarageConfig.Enabled) then
			return
		end

		--[[ `withDependencies` orders start, so PlotService has already discovered its plots. The
			empty-table fallback is for the case it has not: a disabled or failed PlotService should
			cost the game its customers, not take this service down with it. ]]
		local PlotService = Shard.get("PlotService")
		local plots = PlotService and PlotService:getPlots()
		if not plots then
			self.log:warn("No plots from PlotService — customers cannot be bound to lots.")
			return
		end

		self._trove:Add(PlotService:getSignal("PlotAssigned"):Connect(function(player: Player, plot: Model)
			self:_claim(player, plot)
		end))
		self._trove:Add(PlotService:getSignal("PlotReleased"):Connect(function(player: Player)
			self:_release(player)
		end))

		--[[ Catch up on lots already claimed. `PlotService` assigns inside its own `start`, so on a
			hot reload — or simply if it starts first — a player can already be standing in their own
			showroom by the time this connects, and would otherwise have no customers until they
			rejoined. ]]
		for _, record in plots do
			if record.owner then
				self:_claim(record.owner, record.model)
			end
		end

		self._trove:Add(self:_tendLoop())

		--[[ The run tally's two ends. Looked up rather than declared a dependency: `RaceService`
			depends on half the server, and a customer is not a reason for it to start first — a
			missing RaceService costs the summary and nothing else. ]]
		local RaceService = Shard.get("RaceService")
		if RaceService then
			self._trove:Add(RaceService:getSignal("RaceEntered"):Connect(function(player: Player)
				self._tallies[player] = { visitors = 0, tips = 0 }
			end))
			self._trove:Add(RaceService:getSignal("RaceLeft"):Connect(function(player: Player)
				self:_sendSummary(player)
			end))
		else
			self.log:warn("No RaceService — players will not be told what their showroom did during a run.")
		end

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self._tallies[player] = nil
			self:_release(player)
			self:_forgetFaces(player)
		end))
	end,
})

CustomerService:withCleanup(function()
	if CustomerService._trove then
		CustomerService._trove:Destroy()
	end
end)

return CustomerService


