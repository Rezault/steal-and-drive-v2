--[[
	RaceService  (server)
	---------------------
	Server-authoritative entry point for a player joining a race and getting a car.

	Because the road is client-sided now (RoadController builds a local road per driver),
	the car must not go live until the driver's local road exists — otherwise the
	server-owned car would briefly fall through nothing on that client. So entry is a
	small handshake:

	  1. Two ways in, one entry point. observeTag("EnterRace") wires a Touched trigger on the
	     tagged part(s) in the world, and the HUD's Play button fires `RequestEnterRace`
	     (RaceEntryController → `_onEnterRequest`, the rate-limited front door for the one
	     caller that is a client). Both land in `enterRace`, which is where every guard lives.
	     AS OF 2026-08-16 THERE ARE NO TAGGED PARTS: the six plot pads and the old dev slab were
	     deleted from the place, so the Play button is the only live door and observeTag over an
	     empty tag is a silent no-op. The trigger half below is kept, unchanged and working, for
	     whoever tags a part again — `BuildPlotRacePads` still builds them.
	     The button's press carries the world the player picked on the world-select screen and the
	     car they picked on the screen after it — `_onEnterRequest` moves them and stores the car
	     first, refuses the race if the WORLD was refused, and falls back to that world's own
	     starter if the CAR was (its note has why those two differ).
	  2. On trigger → fire `RaceEntering` so the client raises its transition/fade screen
	     over the (brief) spawn + road-build delay, then clone the set-up car, place it on
	     the deck (lane centre, facing the drive direction), ANCHOR it, and Sit the player.
	     Seating teleports the character onto the car, which streams that region in, and the
	     rider's SeatWeld is nudged down so their head clears the roof (see `_fitRiderWeld`).
	  3. Fire `RaceStart` (carrying the race's obstacle seed, from ObstacleService) → the
	     client builds its local road, its obstacle course, and fires `RaceReady` back.
	  4. On `RaceReady` (or a timeout fail-safe) → unanchor the car, hand network ownership
	     to the driver, and (re-)run the stock vehicle seat-enter so it deploys the client
	     Driver controls + engine effects on the now-live car (see `_deployDriving`). Then
	     fire `RaceLive` so the client drops its transition screen. Now it drives.
	  5. `RaceEnd` on leave/death tells the client to tear its local road down.

	Running out of HP is its own exit (`wreckRace`, called by ObstacleService when the car's
	Health hits 0): cut the driver's controls, throw the driver out of the car as a ragdoll, hold a
	short wreck beat so the player sees what happened, fade the screen, then stand them back up at
	their spawn and despawn the car.

	A WRECK MAY NOT BE THE END OF THE RUN ANY MORE. `ReviveService` gets first refusal on every one
	(`ReviveConfig`): where it takes the offer, `wreckRace` plays the whole wreck beat and then
	STOPS — it does not settle the run and it does not raise the fade — and that service puts the
	respawn screen up instead. Answering it lands in one of two places here, and they are the two
	public functions the split created: `endWreckedRun` (declined or timed out — the tail of
	`wreckRace`, run late) or `reviveRace` (paid — the car goes back on the lane where it died, the
	rider goes back in it, and the same run carries on with the distance it already had). Everything
	else about a wreck is unchanged, and with `ReviveConfig.Enabled` off this branch never runs.

	COMING OUT OF THE SEAT IS ALWAYS A RAGDOLL now, whichever way it happens (`_throwRider`, and
	RaceConfig.RiderThrow for the why). The wreck throws you out on purpose; `_onRiderLeftSeat`
	catches the other direction, where physics has already prised you out of a car that is still
	driving itself down the road, and routes it into the same wreck beat. The one hard rule this
	feature carries is that `_standRider` runs on EVERY way out of a run, `leaveRace` included: a
	player left limp past the end of a race has no controls for the rest of the session.

	FALLING OUT OF THE WORLD IS AN EXIT TOO (`_checkForFalls`), and it exists because of what the
	client-sided road costs the server: there is no floor under the car we own. It stays up only
	because its driver simulates it against tiles that exist on their machine alone, so anything that
	punches it through that deck drops it into open space — and until this guard, nothing anywhere
	noticed. Three seconds later `FallenPartsDestroyHeight` deleted the car and the rider welded into
	it, and the player was left with a dead Humanoid and a frozen camera for the rest of the session.
	The guard freezes the fall and routes it into the same `wreckRace` beat as any other death.

	EVERY RACE IS DRIVEN ON A STOREY OF ITS OWN (`RaceConfig.Lanes`, and `_claimLane` below). The
	road, the traffic and the obstacles were already client-local, so two players pressing Play used
	to build private copies of the world in the SAME piece of space and then crash into each other's
	replicated cars in it. Entry now claims a lane, and that one offset is handed to everything that
	places anything: the car spawn, the `RaceStart` the client lays its road from, the void guard's
	floor and a revive's landing. Slot 0 is the race origin unchanged, so a solo run is exactly the
	run it always was.

	No Instances are passed over the remotes (StreamingEnabled-safe): the client finds its
	own car via its seat.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Observers = require(ReplicatedStorage.Packages.Observers)
local Shard = require(ReplicatedStorage.Packages.Shard)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
--- For its `Cause` alone: the one ending whose car was never actually hit. See `wreckRace`.
local PoliceConfig = require(ReplicatedStorage.shared.Configs.PoliceConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local ReviveConfig = require(ReplicatedStorage.shared.Configs.ReviveConfig)
--- Whether this player's run is a tutorial one that may not be lost (`wreckRace`). A config, not
--- `TutorialService`, which is reached lazily: it requires nothing back, so it cannot cycle.
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local CarCollision = require(ReplicatedStorage.shared.Modules.CarCollision)
local CarDoorRig = require(ReplicatedStorage.shared.Modules.CarDoorRig)
local CarPaint = require(ReplicatedStorage.shared.Modules.CarPaint)
local CarMutation = require(ReplicatedStorage.shared.Modules.CarMutation)
local CarPlate = require(ReplicatedStorage.shared.Modules.CarPlate)
local CarRoster = require(ReplicatedStorage.shared.Modules.CarRoster)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local CarStats = require(ReplicatedStorage.shared.Modules.CarStats)
local Ragdoll = require(ReplicatedStorage.shared.Modules.Ragdoll)
local Vehicle = require(ReplicatedStorage.shared.Modules.Vehicle)

-- Hard cap on how long `_returnToSpawn` waits for the seat to let go of the rider before
-- moving them anyway. Measured at ~5 frames in practice; this is only a fail-safe for a
-- humanoid that never leaves the Seated state at all (a rider who died in the seat, say).
local SEAT_RELEASE_TIMEOUT = 0.5

--- How long `_returnToSpawn` gives the server to stream the lobby in around the pad before it
--- teleports the player there regardless. A cap, not a wait: a player standing in a pause on landing
--- is a better outcome than one left hanging over the road, so this expiring is a shrug, not a
--- failure.
local RETURN_STREAM_TIMEOUT = 2

--- Hard cap on how long `_holdInPlace` will keep a rider anchored before letting go on its own.
--- Sized well past the return beat's worst case (`SEAT_RELEASE_TIMEOUT` + `RETURN_STREAM_TIMEOUT`),
--- so reaching it means the beat died holding somebody and this is the only thing that will ever
--- give them their controls back.
local HOLD_FAILSAFE_TIMEOUT = 8

--- How long after a run ends a death is still the run's business, and gets the diagnosis below
--- written for it. Comfortably past the return beat's own worst case, because the point is to catch
--- the death that lands just AFTER the beat thinks it finished.
local DEATH_WATCH_TIME = 10

--[[ === WATCHING THE LANDING (see `_watchLanding`) ===========================================

	The return beat's last act is to UNANCHOR the player, and until 2026-08-24 that was also the
	last thing anybody checked. It is the wrong place to stop looking: the character is owned by the
	CLIENT, and the moment physics comes back it stands on whatever that client has streamed in — so
	a plot that has not arrived yet is a player falling out of the world from their own front door,
	with the server watching a teleport it already counted as successful.

	These three numbers are the check that was missing. They are deliberately far outside anything
	ordinary play can produce inside `RETURN_WATCH_TIME`, so the recovery can never fire on a player
	who simply walked away from the pad: a Humanoid does 16 studs/s, and the fade is still up over
	the first part of the window.

	  DROP    below the target, in studs. A character pivoted onto the pad settles ~1-3 studs; 12 is
	          past any settle and nowhere near a two-second fall (~200 studs by then).
	  STRAY   horizontal, in studs. 200 is six times the furthest a player could walk in the window,
	          and a fiftieth of the 2,189 studs between the race origin and the nearest plot — which
	          is the distance this is really here to catch. ]]
local RETURN_LANDING_DROP = 12
local RETURN_LANDING_STRAY = 200
local RETURN_WATCH_TIME = 2
--- How many times the landing may be re-tried before the beat gives up and says so. Three, because
--- each attempt re-streams first and a destination that has not arrived in three tries is not going
--- to; past that this is a log line, not a loop.
local RETURN_MAX_ATTEMPTS = 3

local RaceService =
	Shard.new("RaceService"):withDependencies({ "RoadService", "ObstacleService", "RewardService", "WorldService" })

RaceService:withSignals({
	--[[ (player: Player) — a race has begun for this player. Fired from `enterRace` once the entry
		is committed (car spawned, rider seated), NOT from the trigger, so a refused or failed entry
		never raises it.

		Exists for `LobbyCarService`, which has to put a player's showroom car away when they start
		driving a different one. A signal rather than a call into that service because the dependency
		only makes sense in that direction: racing is the game and the lobby car is a garnish on it,
		so the race must not know or care whether anything is listening. ]]
	"RaceEntered",

	--[[ (player: Player) : that race is over, whatever ended it. Fired from `leaveRace`, which is the
		one function every way out of a race goes through (a bank, a wreck, a disconnect, an admin
		ending it, an entry that fell over), so a subscriber cannot miss an ending by not knowing
		about a path.

		IT IS THE OTHER END OF `RaceEntered` AND IT IS NOT "THEY ARE HOME". The return beat is still
		in flight when this fires: the fade is up and the teleport onto their plot has not landed. So
		it answers "they are no longer driving", which is the question the things standing down for a
		run are actually asking. `CarryService` is the first subscriber, putting the car back into the
		player's hands after a run that had to take it off them. ]]
	"RaceLeft",

	--[[ (player: Player) : NOW they are home. Fired from `_returnToSpawn`'s `home()`, the moment the
		trip back lets go of their character — released, teleported, velocity zeroed — on every path
		out of that beat, including the ones that give up early. This is the "they are home" that
		`RaceLeft` above says it is not (2026-09-30).

		`CarryService` is why it exists. It used to put the banked car in the player's hands on
		`RaceLeft`, which is mid-beat: still leaving the seat of a car about to be destroyed, then
		anchored whole, teleported across the map and unanchored by the server. Welding sixty-odd parts
		onto a character in the middle of that is what the dead-bay-prompt trace caught — the SERVER's
		copy of the character pinned on the spawn pad for the rest of the session while the client
		walked away from it (`GarageService._watchDesync`). ]]
	"ReturnedHome",

	--[[ (player: Player) : a wreck was paid out of and the same run is driving again. Fired beside
		the `RaceRevived` remote in `reviveRace`. `PoliceService` is the subscriber: a wreck cancels a
		police call the client had not answered yet, so its steal floor has to go with it. ]]
	"RaceRevived",

	--[[ (player: Player, cause: string?) : the car is wrecked, before any revive offer or settlement.
		Fired once per wreck from `wreckRace`, whatever happens next (a revive, a tutorial rescue, the
		end of the run). `cause` is the wreck's own: nil for health run out, "thrown", "fell",
		"badLanding", or `PoliceConfig.Cause`. For `AnalyticsService` (2026-10-15), so a run's ending
		can say what ended it. ]]
	"RaceWrecked",
})

RaceService:withRemoteEvents({
	--[[ server -> client (seed, world, laneOffset, bench): build your local road + obstacle course.

		The fourth is the admin obstacle bench (`ObstacleConfig.Bench`) and is nil for every ordinary
		run. It rides here for the reason the seed and the world do: it is something the client
		BUILDS from, and a build argument belongs in the message that asks for the build. ]]
	"RaceStart",
	"RaceEnd", -- server -> client: tear your local road down
	"RaceEntering", -- server -> client: entry has begun — show the transition/fade screen
	"RaceLive", -- server -> client: car is live and drivable — hide the transition screen
	"RaceWrecked", -- server -> client: HP is gone — coast to a stop, show the banner
	--[[ server -> client: ...and that wreck has been PAID OUT OF. Undo it — clear the banner, stop
		the smoke, put the HUD and the control shim back — the car is on the road again and the same
		run is still going. Deliberately its own remote rather than a second `RaceStart`: that one
		carries a seed and would have the client tear down and rebuild the road and the obstacle
		course under a car that never left them. ]]
	"RaceRevived",
	--[[ server -> client: we gave up on this entry — your road never got built (`_abortEntry`).
		Fired BEFORE the return beat, because the transition screen is still up at that point and this
		is the one thing on it the player cannot work out for themselves: every other way that screen
		ends puts them in a car, and this one puts them back in the lobby holding nothing. Without it
		the game has silently eaten a press of Play. ]]
	"RaceAborted",
	"RaceReturning", -- server -> client: fade out, we're heading back to spawn
	--[[ server -> client ({ kind, cause, seconds }): the run is over and nobody is being offered a
		revive, so put the end panel up over the scene (`holdEndPanel`). `kind` is "bank" or "wreck". ]]
	"RaceEndPanel",
	-- server -> client: the end panel's hold is over whichever way it went; take it down if it is up.
	"RaceEndPanelClosed",
	{
		--[[ client -> server: "I draw the end panel" (`NewUIConfig.EndPanel`, new UI, the template in
			hand). Only a player who has said so is held for it; everybody else gets the old ending
			with no wait, so an old client is never left watching a scene for a panel it cannot draw. ]]
		RaceEndOptIn = function(player: Player)
			RaceService._endPanelOptIn[player] = true
		end,
		-- client -> server: the end panel was answered (HOME, RACE AGAIN, or its countdown ran out).
		RaceEndAnswer = function(player: Player)
			local hold = RaceService._endPanels[player]
			if hold then
				RaceService:_releaseEndPanel(player, hold, "answered")
			end
		end,
		-- client -> server: "my local road is built, you can let the car go live"
		RaceReady = function(player: Player)
			RaceService:_onRaceReady(player)
		end,
		--[[ client -> server (world: number?, carKey: string?): play. From the world-select screen
			(which sends the world its card stands for) or from anything else that wants the world
			you are already in (which sends nothing). RaceEntryController is the only client end.

			`carKey` is the SELECT CAR screen's card — the third step of Play — and it rides along
			for the same reason the world does: it is something the run has to be BUILT from, so it
			belongs in the message that asks for the run rather than in a second remote whose order
			against this one nothing guarantees. Absent means "whatever I chose last time", which is
			what the lobby pad and a one-click Play send. See `StartCarService`. ]]
		RequestEnterRace = function(player: Player, world: unknown, carKey: unknown)
			RaceService:_onEnterRequest(player, world, carKey)
		end,
	},
})

--[[ Resolve the pristine car template for a body (never modified — we always clone it).

	`body` is the car the caller has already decided on — `StartCarService.carFor`, which is either
	the player's own choice or the world's starter. With none in hand this falls back to that world's
	`StartRung`, so a run always begins on the ladder it is climbing — the Civic in the city, the
	EVO in the desert — and `RaceConfig.CarTemplateName` is the same lookup for the default world,
	reached only when there is no world either. ]]
function RaceService._getTemplate(self, world: number?, body: string?): Model?
	--- Asked rather than read off Workspace: the roster is relocated to ServerStorage at boot, and
	--- `CarRoster` is the one place that knows where it ended up.
	if CarRoster.folder() then
		local wanted = body
			or (if world then WorldConfig.startBodyFor(world) else RaceConfig.CarTemplateName)
		local named = CarRoster.car(wanted)
		if named then
			return named
		end
		self.log:warn(string.format("No car named '%s' in %s; falling back to the first tagged Car.", tostring(wanted), CarRoster.path()))
	end
	for _, inst in CollectionService:GetTagged(RaceConfig.CarTag) do
		if inst:IsA("Model") then
			return inst
		end
	end
	return nil
end

-- === Race lanes =============================================================

--[[ Take a storey for this player's run (`RaceConfig.Lanes` for what a lane is and why).

	SMALLEST FREE FIRST, so a session with one or two players in it only ever uses the bottom of
	the stack and the lone racer is on the ground at the race origin, exactly where every race
	used to be. That is worth having on purpose rather than by accident: it is the arrangement
	that has been played, and it is the one a solo playtest reproduces.

	Idempotent per player, and a full stack hands back slot 0 WITHOUT claiming it — that player
	shares the ground floor with whoever owns it, which is the pre-lane behaviour rather than a
	refused race. `_releaseLane` only frees a slot it still owns, so the sharer leaving cannot
	evict the owner. ]]
function RaceService._claimLane(self, player: Player): number
	local existing = self._lanes[player]
	if existing then
		return existing
	end
	for slot = 0, math.max(1, RaceConfig.Lanes.Count) - 1 do
		if not self._laneOwners[slot] then
			self._lanes[player] = slot
			self._laneOwners[slot] = player
			return slot
		end
	end
	self.log:warn(string.format(
		"All %d race lanes are taken; %s shares the ground floor and can collide with whoever owns it.",
		RaceConfig.Lanes.Count, player.Name))
	self._lanes[player] = 0
	return 0
end

-- Give the storey back. Idempotent, and safe on the overflow case above (a player who was never
-- the owner frees nothing). Called from every way out of a race, including the ways that fail
-- before there is a car — a leaked lane is a storey nobody can ever race on again.
function RaceService._releaseLane(self, player: Player)
	local slot = self._lanes[player]
	if not slot then
		return
	end
	self._lanes[player] = nil
	if self._laneOwners[slot] == player then
		self._laneOwners[slot] = nil
	end
end

-- Where this player's race sits, relative to the shared race origin. Zero for anyone not racing,
-- which is also what every caller wants for a race that predates or opts out of lanes.
function RaceService._laneOffset(self, player: Player): Vector3
	return RaceConfig.laneOffset(self._lanes[player])
end

-- Walk up from a touched part to the owning player (nil if it wasn't a character).
function RaceService._playerFromHit(self, hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	while model do
		local player = Players:GetPlayerFromCharacter(model)
		if player then
			return player
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

--[[ Freeze/thaw the whole car assembly, remembering each part's original anchor state.

	THE SECOND FREEZE MUST NOT REMEMBER THE FIRST ONE'S WORK, and that is what the guard below is.
	Two freezes with no thaw between them is a real sequence — `_catchFall` freezes a car that has
	left the world, and a paid revive on that same run freezes it again on its way to setting it
	back down — and without the guard the second pass recorded `Anchored = true` for all 83 parts,
	because the first pass had just made it so. The thaw then "restored" exactly that: a car nailed
	to the road for the rest of the run, with a live HUD, a seated driver, correct network ownership
	and a speedometer pinned at 0 that answers no throttle at all.

	That is the fingerprint three separate playtest reports describe (playtests/2026-08-24, "the big
	one: cars that will not move"), and it is the only path in this file that can produce it, so the
	fix is to make the freeze IDEMPOTENT: whoever froze it first owns what it was, and every freeze
	after that is a no-op on state it must not touch. The thaw is unconditional either way — one
	release ends the hold, exactly as before.

	DriveController's own freeze reaches the same conclusion from the other side and is worth
	reading beside this one (`frozenAnchor`: "two systems anchor the same car and each remembers
	what it found"). This is that hazard within a single system. ]]
function RaceService._setCarFrozen(self, car: Model, frozen: boolean)
	if frozen then
		if self._frozen[car] then
			-- Already held. Re-anchor anything that has joined the car since (a steal re-rigs
			-- `Body/` mid-race), but leave the remembered state — and the parts it names — alone.
			for _, p in car:GetDescendants() do
				if p:IsA("BasePart") then
					p.Anchored = true
				end
			end
			return
		end
		local state = {}
		for _, p in car:GetDescendants() do
			if p:IsA("BasePart") then
				state[p] = p.Anchored
				p.Anchored = true
			end
		end
		self._frozen[car] = state
	else
		local state = self._frozen[car]
		self._frozen[car] = nil
		for _, p in car:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = state and state[p] or false
			end
		end
	end
end

--[[ Sit the rider *in* the cabin instead of on top of it.

	The stock SeatWeld plants the character on the seat surface at full standing torso
	height, so in a low car the head pokes out through the roof. RaceConfig.RiderSeatOffset
	is a seat-local nudge applied to the weld's C0 (-Y down, +Z toward the back), which
	sinks the rider into the cabin; the legs end up inside the opaque floor where nothing
	sees them. Idempotent per weld — the attribute guards against double-applying. ]]
function RaceService._fitRiderWeld(self, weld: Weld)
	if weld:GetAttribute("RiderFitApplied") then
		return
	end
	weld:SetAttribute("RiderFitApplied", true)
	-- Pre-multiply: the stock C0 carries a rotation (its UpVector points along seat -Z), so
	-- post-multiplying would shove the rider sideways instead of down. Pre-multiplying
	-- applies the translation in the seat's own frame, which is what the offset means.
	weld.C0 = CFrame.new(RaceConfig.RiderSeatOffset) * weld.C0
end

-- The engine rebuilds the SeatWeld on every occupant change — and `_deployDriving`
-- deliberately toggles the occupant — so watch the seat rather than patch one weld.
function RaceService._watchRiderWeld(self, car: Model, seat: VehicleSeat)
	if RaceConfig.RiderSeatOffset.Magnitude == 0 then
		return
	end
	local existing = seat:FindFirstChild("SeatWeld")
	if existing and existing:IsA("Weld") then
		self:_fitRiderWeld(existing)
	end
	self._riderConns[car] = seat.ChildAdded:Connect(function(child)
		if child.Name == "SeatWeld" and child:IsA("Weld") then
			self:_fitRiderWeld(child)
		end
	end)
end

-- Alternative to the offset: hide the character outright while they're in the car.
-- Remembers each part's original transparency so accessories/faces come back intact.
function RaceService._setRiderHidden(self, player: Player, hidden: boolean)
	if hidden then
		local character = player.Character
		if not character or self._hidden[player] then
			return
		end
		local state = {}
		for _, inst in character:GetDescendants() do
			if inst:IsA("BasePart") or inst:IsA("Decal") then
				state[inst] = inst.Transparency
				inst.Transparency = 1
			end
		end
		self._hidden[player] = state
	else
		local state = self._hidden[player]
		self._hidden[player] = nil
		if not state then
			return
		end
		for inst, transparency in state do
			if inst.Parent then
				inst.Transparency = transparency
			end
		end
	end
end

--[[ Undo the stock vehicle script's "take off accessories" pass.

	Its onEnterSeat hides the rider's lower legs and back/hat accessories (so they don't poke
	through the car), and its onExitSeat puts them back at Transparency 0. We never get that
	second half: leaveRace destroys the car outright, so the vehicle script's exit cleanup
	never runs — same gap `_cleanupDriverControls` covers for the control GUIs — and the
	player walks away from the pad with no feet.

	Restoring to 0 (rather than a captured original) is deliberate: it's exactly what the
	stock onExitSeat does, so this behaves identically to a normal get-out. Idempotent, and
	safe to call when the vehicle never hid anything (R6 riders have none of these parts).

	The two lists come from Vehicle itself, so a redress that changes what gets hidden can
	only ever change it in one place. ]]
function RaceService._restoreRiderAvatar(self, player: Player)
	local character = player.Character
	if not character then
		return
	end

	for _, partName in Vehicle.HiddenLegParts do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Transparency = 0
		end
	end

	for _, child in character:GetChildren() do
		if child:IsA("Accoutrement") then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				for _, attachmentName in Vehicle.HiddenAccessoryAttachments do
					if handle:FindFirstChild(attachmentName) then
						handle.Transparency = 0
						break
					end
				end
			end
		end
	end
end

-- === Being thrown out of the car ============================================

-- Shut a seat so it can't re-grab the body we're about to tumble out of it (and re-arm it after).
-- Two branches for one line because `Humanoid.SeatPart` is typed as a plain BasePart, and `Disabled`
-- lives on `Seat` and `VehicleSeat` separately rather than on a shared parent.
local function armSeat(seat: BasePart?, armed: boolean)
	if seat and seat:IsA("VehicleSeat") then
		seat.Disabled = not armed
	elseif seat and seat:IsA("Seat") then
		seat.Disabled = not armed
	end
end

--[[ Take the rider out of the seat and let them hit the road as a body (RaceConfig.RiderThrow).

	Two callers, and they are the two ways you leave a car without meaning to: `wreckRace` when the
	run is being ended for you, and `_onRiderLeftSeat` when something has already prised you out of
	the seat and the run has not caught up yet. Returns whether it actually threw anyone, so a caller
	can tell "done" from "there was nobody to throw".

	THE ORDER BELOW IS THE FUNCTION. Reading it as a list of steps:

	  1. THE VELOCITY IS READ FIRST, off the still-welded root, because that reading IS the throw.
	     The rider is part of the car's assembly right now, so the root reports what the car is
	     doing; one line later the weld is gone and it reports whatever the solver has made of a
	     loose body. Read it late and the crash you were thrown by has already been forgotten.
	  2. THE AVATAR IS PUT BACK TOGETHER BEFORE IT IS ON SHOW. The stock vehicle script hides the
	     rider's lower legs and their hat/back accessories on the way IN and only restores them in an
	     onExitSeat we never get (see `_restoreRiderAvatar`), and `HideRiderInCar` may have hidden
	     them outright. Skip this and a footless, hatless — or entirely invisible — body slides down
	     the road.
	  3. THE SEAT IS SHUT BEFORE THE WELD GOES. A `VehicleSeat` re-grabs anything touching it, and a
	     body tumbling out of the cabin is touching it. Without `Disabled` the throw ends with the
	     player snapped back into the driving position mid-ragdoll.
	  4. THE HUMANOID IS MADE SURVIVABLE, then the joints go. `RequiresNeck` on a humanoid whose neck
	     joint has stopped solving is a death, `BreakJointsOnDeath` turns that death into a pile of
	     parts, and `CharacterAutoLoads` is off in this place — so between them those two defaults
	     turn a wreck into a lost session. `PlatformStand` is the third: without it the Humanoid
	     spends the whole beat trying to stand its own ragdoll up.
	  5. THE KICK IS WRITTEN TWICE, a frame apart, for exactly the reason `_returnToSpawn` zeroes
	     velocity twice: the client owns its own character, and it can re-assert what it thought the
	     body was doing on the physics step right after ours.
	  6. THE CAR IS GIVEN BACK TO THE DRIVER WHO JUST LEFT IT, which reads backwards and isn't. An
	     empty seat runs the stock vehicle's `onExitSeat`, and that calls `SetNetworkOwnershipAuto`
	     — but the car's whole death throe is client-side (ObstacleController coasts it to a stop and
	     smokes it), and a client can only write velocity onto an assembly it owns. Let the engine
	     reassign and the wreck you were thrown out of carries on down the road at speed. ]]
function RaceService._throwRider(self, player: Player, car: Model?): boolean
	local cfg = RaceConfig.RiderThrow
	if not cfg.Enabled then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not (character and humanoid and root and humanoid.Health > 0) then
		return false
	end
	-- Keyed on the CHARACTER rather than on the player, so a respawn invalidates the entry by itself
	-- and a second wreck in a new body is never refused by a stale one.
	local existing = self._ragdolls[player]
	if existing and existing.character == character then
		return false
	end

	local seat = humanoid.SeatPart
	local frame = if seat and seat.Parent then seat.CFrame else root.CFrame
	local carried = root.AssemblyLinearVelocity * cfg.VelocityKeep

	--[[ THE SLOT IS CLAIMED BEFORE A SINGLE THING IS TOUCHED, and this is not tidiness — everything
		below this line can re-enter it. Emptying the seat fires the very `SeatPart` change that
		`_onRiderLeftSeat` is watching for, and that handler's road back here is one call long. A
		second pass over a rig whose Motor6Ds are already disabled finds nothing left to cut, so it
		would overwrite this entry with an empty one and the player would never be put back together
		— limp, uncontrollable, for the rest of the session. Claiming first makes the re-entrant call
		return false at the check above. ]]
	local entry = {
		character = character,
		humanoid = humanoid,
		seat = seat,
		flags = {
			requiresNeck = humanoid.RequiresNeck,
			breakJoints = humanoid.BreakJointsOnDeath,
			autoRotate = humanoid.AutoRotate,
		},
		restore = nil :: Ragdoll.Restore?,
	}
	self._ragdolls[player] = entry

	self:_setRiderHidden(player, false)
	self:_restoreRiderAvatar(player)

	armSeat(seat, false)
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy() -- the weld IS the release; `Sit = false` alone takes ~5 physics frames
	end
	humanoid.Sit = false

	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true

	entry.restore = Ragdoll.collapse(character, cfg)
	if not entry.restore then
		self.log:warn(string.format("%s's character has no Motor6Ds to ragdoll; they go out stiff.", player.Name))
	end
	character:SetAttribute(cfg.Attribute, true)

	local velocity = carried + frame:VectorToWorldSpace(cfg.Kick)
	local spin = Ragdoll.spin(self._rng, cfg.Spin)
	Ragdoll.throw(character, velocity, spin)
	task.spawn(function()
		-- A Heartbeat, not a defer: the stock `onExitSeat` runs off the seat's Occupant change, so a
		-- deferred re-assert can still land in front of its `SetNetworkOwnershipAuto` and be undone
		-- by it. One physics step puts both writes unambiguously behind it.
		RunService.Heartbeat:Wait()
		local live = self._ragdolls[player]
		if not (live == entry and character.Parent) then
			return -- stood back up, respawned, or thrown again in a different body
		end
		Ragdoll.throw(character, velocity, spin)
		if car and car.Parent and car.PrimaryPart and self._cars[player] == car then
			pcall(function()
				car.PrimaryPart:SetNetworkOwner(player)
			end)
		end
	end)

	return true
end

--[[ Put them back on their feet. The exact inverse of `_throwRider`, and it runs on every way out of
	a run — the return home, a player who left, a character who died mid-tumble — because the one
	thing that must never survive this feature is a player still limp after the beat has ended.

	Returns whether anyone was actually stood up, which `_returnToSpawn` uses to decide whether the
	teleport has to wait a frame for the rig to become one assembly again.

	Idempotent and safe on a half-destroyed character: `Ragdoll.stand` re-checks every instance, and
	everything below is nil-guarded, because the ordinary case for a character that vanished mid-beat
	is `leaveRace` calling this after the fact. ]]
function RaceService._standRider(self, player: Player): boolean
	local entry = self._ragdolls[player]
	if not entry then
		return false
	end
	self._ragdolls[player] = nil

	Ragdoll.stand(entry.restore)

	local humanoid = entry.humanoid
	if humanoid and humanoid.Parent then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = entry.flags.autoRotate
		humanoid.RequiresNeck = entry.flags.requiresNeck
		humanoid.BreakJointsOnDeath = entry.flags.breakJoints
		if humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end

	local character = entry.character
	if character and character.Parent then
		character:SetAttribute(RaceConfig.RiderThrow.Attribute, nil)
	end

	-- The seat almost always dies with the car a beat later; re-arming it matters for the one case
	-- where it doesn't, and costs nothing in the case where it does.
	if entry.seat and entry.seat.Parent then
		armSeat(entry.seat, true)
	end
	return true
end

--[[ Get this rider OUT of whatever seat they are currently in, and wait for it to actually happen.
	Returns true once they are free (or already were), false if the seat never let go.

	THIS IS THE ONE THING THAT HAS TO HAPPEN BEFORE ANY `Seat:Sit`, and it was the 16 Aug playtest's
	"starting a match dumps you back in the lobby". A player driving their lobby car who presses Play
	is already seated, and `VehicleSeat:Sit(humanoid)` DOES NOT MOVE AN ALREADY-SEATED HUMANOID. It is
	not refused and it does not error — it is worse than either. Measured on bare seats, no game code
	anywhere near them:

	    seated in A                 A.Occupant=Humanoid  B.Occupant=nil  SeatPart=SEAT_A
	    B:Sit(hum), same resumption A.Occupant=nil       B.Occupant=nil  SeatPart=SEAT_A
	    +2 frames                   A.Occupant=nil       B.Occupant=nil  SeatPart=SEAT_A
	    +0.5s                       A.Occupant=nil       B.Occupant=nil  SeatPart=nil

	So the call vacates the OLD seat, never fills the new one, and leaves `SeatPart` pointing at the
	seat it just emptied for a few frames before it goes nil. The rider ends up in NO seat at all.

	What that cost, end to end: `enterRace` seats the player and hands off to the client, and the
	client's `RoadController._findCar` finds its car BY READING `humanoid.SeatPart`. It therefore read
	the lobby car (stale) and then nil, so `_awaitCar` never resolved, `RaceReady` was never fired,
	and `EnterReadyTimeout` later `_abortEntry` put the player back in the lobby under "Couldn't load the world
	in time" — a road-loading message for a seat bug, with their lobby car already despawned by
	`RaceEntered`. Nothing in the entry path could see it: `_onRiderLeftSeat` correctly ignores the
	unseat because `_pending` is set, and the server's own seat looks fine because it never had an
	occupant to lose.

	The release is the fix and it is cheap — `Sit = false` landed in 4 frames / 13 ms measured, and it
	is paid inside the entry's own fade. It cannot be skipped by "check `SeatPart` and only release if
	set", because that IS the check; and it cannot be done without waiting, because the release is a
	physics-frame thing and a `Sit` issued inside that window is the same no-op all over again. Same
	trap `_returnToSpawn` waits out at `SEAT_RELEASE_TIMEOUT`, which is the cap reused here. ]]
function RaceService._releaseSeat(self, humanoid: Humanoid): boolean
	if humanoid.SeatPart == nil then
		return true
	end
	humanoid.Sit = false
	local deadline = os.clock() + SEAT_RELEASE_TIMEOUT
	while humanoid.SeatPart ~= nil do
		if os.clock() >= deadline or humanoid.Parent == nil then
			return false
		end
		RunService.Heartbeat:Wait()
	end
	return true
end

--[[ The rider came out of the seat and nothing in this service asked them to.

	Physics is the honest answer to "how" — a hard enough clip, a handoff that resolves an overlap
	through the cabin, a stock seat-jump that got past the bail's Space binding — and the point of
	this handler is that the CAUSE doesn't matter. A driverless car and a player standing in the road
	is not a state this game has a beat for, so it becomes one it does: they get thrown properly, and
	the run ends through the same `wreckRace` the void guard and the HP death both end through.

	Every guard here is a legitimate unseat that must NOT be treated as one of these:
	  • `_wrecking` — the run is already ending, and its own throw is the unseat we are watching.
	  • `_reseating` — `_deployDriving` toggles the occupant on purpose to make the stock vehicle
	    scripts deploy (eject → re-sit); without this, every single race starts by ragdolling you.
	  • `_pending` — entry hasn't gone live yet, so the seat is still being set up.
	  • `_ragdolls` — we are already mid-throw and this IS our own unseat, arriving re-entrantly.
	  • a dead or missing humanoid — death already has its own exit through `leaveRace`. ]]
function RaceService._onRiderLeftSeat(self, player: Player, car: Model)
	if self._cars[player] ~= car or self._pending[player] or self._wrecking[player] or self._reseating[player] then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then
		return
	end
	local existing = self._ragdolls[player]
	if existing and existing.character == character then
		return
	end

	self.log:warn(string.format("%s came out of the seat mid-race; ending the run as a wreck.", player.Name))
	self:_throwRider(player, car)
	self:wreckRace(player, "thrown")
end

--[[ Clone the car and seat it on the deck at lane centre, facing the drive direction. Both halves
	are world-specific: which car it is, and where that world's lane centre lands. `laneOffset` is
	the player's own storey (RaceConfig.Lanes) — the same one their client lays its road at, which
	is the whole reason it is resolved once in `enterRace` and handed to both.

	`body` and `paint` are the third thing resolved once and handed down: WHICH car, and in which of
	that car's colours (`StartCarService.carFor`). Both are optional and both fall back to what this
	function did before there was anything to choose — the world's starter, in its authored livery. ]]
function RaceService._spawnCar(self, RoadService, player: Player, world: number, laneOffset: Vector3, body: string?, paint: number?, mutation: string?): Model?
	local template = self:_getTemplate(world, body)
	if not template then
		self.log:warn("No car template found to spawn.")
		return nil
	end
	local surfaceCF = RoadService:getSpawnCFrame(world)
	if not surfaceCF then
		self.log:warn("Road provider gave no spawn CFrame.")
		return nil
	end
	surfaceCF += laneOffset

	local car = template:Clone()
	car:SetAttribute("RaceWorld", WorldConfig.resolve(world)) -- Frozen build world, shared by server encounter rolls.
	-- Into the driver's collision group BEFORE it's parented, so the group replicates as part of
	-- the car's initial state. That group is the only thing client-side traffic collides with —
	-- tagging parts after they've replicated would mean chasing them as they trickle in, and any
	-- part that arrived untagged would be a hole a traffic car drives straight through.
	CarCollision.applyCar(car)

	--[[ How this car drives: `CarConfig`'s row for it, stamped as the attributes the stock chassis
		reads. BEFORE PARENTING, for the same reason as the two calls either side of it — the
		Chassis module reads its parameters when the car's Vehicle script first runs, which is when
		the model is parented into Workspace, so stamping now means it is set up correctly on its
		first pass rather than re-initialised a frame later while the player is looking at it.

		This is where the per-car speed and handling that used to be authored as attributes on the
		49 rigs in `Workspace.CarSystem` now comes from. Those rig attributes still exist and are
		still read as a fallback — see CarConfig's "THE HAND-OFF".

		READ OFF THE CLONE'S OWN NAME, deliberately, and that is why nothing is passed: the template
		may have fallen through to "the first tagged Car" when the wanted body was missing from the
		place, and in that case the name is the truth and the choice is not. `CarStats` documents the
		same trade from the other side. ]]
	local Garage = Shard.get("GarageService")
	local StartCar = Shard.get("StartCarService")
	local parts = nil
	if Garage and StartCar then
		local key = StartCar:selectionOf(player)
		local valid = StartCar:canDrive(player, key, world)
		if valid and GarageConfig.parseCarKey(key) == car.Name and Garage:owns(player, key) then
			parts = Garage:getCarData(player, key).Parts
		end
	end
	CarStats.apply(car, car.Name, if Garage then Garage:getCarLevel(player, car.Name) else 1, parts)

	--[[ The player's own colour, if this is a car out of their collection (`StartCarService.carFor`).
		Stock — the body's authored livery — paints nothing, which is what every run got before there
		was anything to choose and what a world's starter still gets.

		ON THE CLONE, NEVER THE TEMPLATE, and it is the same one-line-away disaster `LobbyCarService`
		documents: painting clears the MeshPart texture the roster's colour lives in (`Modules/
		CarPaint`), so the same call against `template` would strip that body for every player on the
		server, permanently, with no undo.

		IT DOES NOT SURVIVE THE FIRST STEAL, and should not: a steal rebuilds `Body/` out of the
		traffic shell it landed on (`CarBody.apply`), so the car you drive away in is the car you took
		— in the colour you took it in. This is the colour of the car you brought. ]]
	if paint and paint ~= PaintConfig.StockIndex then
		CarPaint.apply(car, paint, body)
	end

	--[[ The number plate, off the same identity the paint just came from: this body in this colour
		is one car (`GarageConfig.carKey`), and `PlateConfig` hashes that pair into a plate. So the
		car you drove out of the garage carries the number it wears on its podium, with nothing
		stored and nothing sent.

		READ OFF THE CLONE'S OWN NAME rather than the `body` argument, for the reason `CarStats.apply`
		gives above it: the template may have fallen through to "the first tagged Car" when the wanted
		body was missing from the place, and in that case the name is the truth and the request is not.

		LIKE THE PAINT, IT DOES NOT SURVIVE THE FIRST STEAL, and should not — a steal rebuilds `Body/`
		out of the shell it landed on and the plate rides on that shell's `SurfaceGui`. You drive away
		in the car you took, wearing the plate it was wearing. ]]
	CarPlate.apply(car, car.Name, paint)

	--[[ Doors, for the same reason and at the same moment as the collision group: done BEFORE the
		car is parented, so the rig replicates as part of its initial state rather than as a burst
		of reparenting and constraint edits against a model the client is already rendering.

		This is why no car in `Workspace.CarSystem` is authored with a door rig. Every car after
		this one is a redress, and a redress has to rebuild the rig from geometry anyway
		(`StealController._applyTier`) — so deriving it here too means one implementation, exercised
		every race, instead of a hand-authored place file that a re-import of the car pack would
		silently undo. A body with no separable doors just returns 0 (plan §6). ]]
	local rigged, notes = CarDoorRig.apply(car)
	if rigged == 0 then
		self.log:info(string.format("Race car '%s' has no doors to rig: %s", car.Name, table.concat(notes, "; ")))
	end
	-- Carry the server-validated owned variant into the race, including its Mutation attribute.
	CarMutation.apply(car, if car.Name == body then mutation else nil)

	--[[ THIS DRIVER KEEPS THIS CAR NO MATTER WHERE STREAMING IS LOOKING. A race car is the ONLY
		server-owned thing at the race origin — the road, the traffic, the obstacles and the getaway
		truck are every one of them client-built and never replicate — so the one instance out there
		that streaming could ever take away from its driver is this one, and being persistent means it
		never will be. Cheap insurance on the model the whole run hangs off.

		WHAT IT DOES NOT DO IS MAKE THE CAR SIMULATE. Persistent is about REPLICATION — does the client
		hold a copy — and says nothing about the client's SIMULATION region, which follows
		`Player.ReplicationFocus`. Getting those two confused froze every race car solid; the invariant
		and the measurement are written out at the `SetNetworkOwner` in `_onRaceReady`.

		BEFORE PARENTING, like the four calls above it, and for a sharper reason than theirs:
		`ModelStreamingMode` is read when the model enters Workspace, so a mode set afterwards leaves
		the car streaming normally for the window that matters most — the entry, when the client is
		waiting on this exact model to arrive before it can ack. `AddPersistentPlayer` is the one call
		that comes after, because it is a live list rather than initial state. ]]
	car.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	car.Parent = self._carsFolder
	car:AddPersistentPlayer(player)

	-- Template car is axis-aligned with its front toward -Z; the surface CFrame already
	-- looks down the road, so setting the pivot to it faces the car forward (+Z).
	car:PivotTo(surfaceCF)
	local bbCF, bbSize = car:GetBoundingBox()
	local belowDeck = surfaceCF.Position.Y - (bbCF.Position.Y - bbSize.Y * 0.5)
	car:PivotTo(surfaceCF + Vector3.new(0, belowDeck + RaceConfig.SpawnClearance, 0))

	return car
end

--[[ Public: begin entry for a player. Idempotent. Server-authoritative — safe to call
	from any trusted trigger. ]]
function RaceService.enterRace(self, player: Player)
	if self._cars[player] or self._pending[player] then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local RoadService = Shard.get("RoadService")
	if not RoadService then
		self.log:warn("RoadService unavailable; cannot enter race.")
		return
	end

	--[[ THE WORLD IS RESOLVED ONCE, HERE, and then carried — into the car we clone, the frame we
		spawn it on, and the `RaceStart` the client builds its road from. Every one of those could
		have read the player's attribute for itself, and that is exactly the bug: the attribute can
		change in the milliseconds between them (nothing stops a teleport request landing while the
		car is being cloned — `WorldService` only refuses once `isRacing` is true, which is a few
		lines below this one), and a run whose road and car came from different worlds is a car
		spawned into thin air. One read, one value, passed down. ]]
	local WorldService = Shard.get("WorldService")
	local world = if WorldService then WorldService:worldOf(player) else WorldConfig.ActiveIndex

	--[[ AND THE CAR IS RESOLVED ONCE TOO, here, for the world just settled on. `carFor` always
		answers — a selection that is missing, unowned or no longer on the roster comes back as that
		world's own starter in stock livery, which is what every run got before the SELECT CAR screen
		existed — so there is no new failure path below this and nothing downstream has to know
		whether the player chose anything. See `StartCarService`.

		AFTER THE WORLD, NOT BEFORE IT. Which cars are legal can depend on which world you are in
		(`StartCarConfig.WorldLadderOnly`), so asking first would be asking about the wrong road. ]]
	local body, paint = WorldConfig.startBodyFor(world), PaintConfig.StockIndex
	local mutation: string? = nil
	local StartCarService = Shard.get("StartCarService")
	if StartCarService then
		body, paint, mutation = StartCarService:carFor(player, world)
	end

	--[[ THE STOREY IS RESOLVED ONCE TOO, and for the same reason the world above it is: the car is
		placed on it, the void guard measures against it, a revive sets the car back down on it, and
		the client lays its whole road at it. A run whose car and road came from different storeys is
		a car spawned a thousand studs above the road it is supposed to be driving on.

		Claimed here, BEFORE the two failure paths below, because `_spawnCar` needs it — so both of
		them have to hand it back, and so does every ordinary exit through `leaveRace`. ]]
	local laneOffset = RaceConfig.laneOffset(self:_claimLane(player))

	-- Raise the client's transition screen immediately, before the (perceptible) work of
	-- cloning the car and building the road — so the whole delay reads as a smooth fade.
	self:getRemoteEvent("RaceEntering"):Fire(player)

	local car = self:_spawnCar(RoadService, player, world, laneOffset, body, paint, mutation)
	if not car then
		self:_releaseLane(player)
		self:getRemoteEvent("RaceLive"):Fire(player) -- nothing to enter — drop the fade
		return
	end

	local seat = car:FindFirstChild("VehicleSeat", true)
	if not (seat and seat:IsA("VehicleSeat")) then
		self.log:warn("Spawned car has no VehicleSeat; aborting entry.")
		self:_releaseLane(player)
		car:Destroy()
		self:getRemoteEvent("RaceLive"):Fire(player) -- drop the fade
		return
	end

	self._cars[player] = car
	self._pending[player] = car

	-- Hold the car still until the client's local road is built, then seat the player
	-- (which teleports them onto the car and streams the region in for their client).
	self:_setCarFrozen(car, true)

	--[[ ARM THE FAIL-SAFE IMMEDIATELY AFTER THE FREEZE, and never any later.

		This used to sit at the bottom of the function, after the seating, `ObstacleService:beginRace`
		and `RewardService:beginRun`. Every one of those can throw, and if one did the timer was never
		scheduled — leaving the player sitting in a car that is anchored forever, with no error that
		names the car. `_setCarFrozen(car, true)` is the only thing in this function that makes the
		world worse if the rest of it doesn't run, so its undo is armed on the next line.

		It stays just a fail-safe: the client's `RaceReady` normally beats it by seconds, and
		`_onRaceReady` clears `_pending` so whichever arrives first wins and the other is a no-op. ]]
	task.delay(RaceConfig.EnterReadyTimeout, function()
		self:_abortEntry(player, car)
	end)

	--[[ STAND THEM UP BEFORE WE SIT THEM DOWN. `_releaseSeat` carries the measurement and the whole
		story; the short version is that `Seat:Sit` is a silent no-op on a rider who is already
		seated, so a player who pressed Play while driving their lobby car got a race they were never
		actually in. This is the only yield in the function and it is deliberately HERE:

		  • after `_cars`/`_pending` are set, so the idempotency guard at the top of `enterRace`
		    already holds and a second press during the wait is refused rather than racing us;
		  • after the fail-safe is armed, so even the timeout branch below cannot strand a player in
		    an anchored car;
		  • before `_setRiderHidden`, because leaving the seat runs the OLD car's stock `onExitSeat`,
		    which puts the rider's legs back — and hiding them first would just have them un-hidden
		    inside the race car (`Modules/Vehicle`, `HiddenLegParts`).

		A release that never lands means the next line would no-op, so the entry ends here rather than
		a whole `EnterReadyTimeout` later under a message about the road. ]]
	if not self:_releaseSeat(humanoid) then
		self:_abortEntry(player, car, "could not get them out of the seat they were already in")
		return
	end

	self:_watchRiderWeld(car, seat) -- must be armed before the first Sit builds the weld
	if RaceConfig.HideRiderInCar then
		self:_setRiderHidden(player, true)
	end
	seat:Sit(humanoid)

	--[[ Start HP tracking and mint this race's obstacle seed. Must happen before RaceStart:
		the client builds its obstacle course from the seed that ships with it.

		The car's HP ceiling is resolved here and handed over rather than stamped by `CarStats`,
		because HP has exactly one writer and it is ObstacleService. Before `CarConfig` this was
		whatever `MaxHealth` the rig carried in the place — an identical 100 on all 49 of them —
		so the start car was the one car in the game whose HP ignored its own rung. ]]
	local seed, bench
	local ObstacleService = Shard.get("ObstacleService")
	if ObstacleService then
		--- The bench comes back beside the seed because it is the same kind of thing: what the
		--- client has to lay this run's obstacles from. Nil unless an admin armed one.
		seed, bench = ObstacleService:beginRace(player, car, world, CarStats.maxHealthOf(car))
	else
		self.log:warn("ObstacleService unavailable; this race runs with no obstacles.")
	end

	-- Start measuring how far they get. From here rather than from `_onRaceReady`, because the car
	-- is anchored until the client's road exists, so the samples until then are zeroes — and the
	-- first tile is the stretch every run has in common. See RewardService.
	local RewardService = Shard.get("RewardService")
	if RewardService then
		RewardService:beginRun(player, car)
	end

	--[[ Ask the client to build its road; go live on its ack (the fail-safe above covers the rest).

		The world rides along with the seed for the same reason the seed does: it is what the client
		has to BUILD from, and a build argument belongs in the message that asks for the build. The
		attribute would have been the other option and is the wrong one — see the note above.

		The lane is the third of exactly that kind of argument: WHERE to build. It is sent as the
		resolved offset rather than as the slot number so that the storey the car is standing on and
		the storey the road is laid at are one value that was computed once, not two computations
		that have to agree. ]]
	self:getRemoteEvent("RaceStart"):Fire(player, seed, world, laneOffset, bench)

	-- Leave the race if the rider dies. (PlayerRemoving is handled globally in start.)
	local diedConn
	diedConn = humanoid.Died:Connect(function()
		if diedConn then
			diedConn:Disconnect()
		end
		self:leaveRace(player)
	end)

	-- …and end it as a wreck if they come out of the seat any other way. Watched from here rather
	-- than polled beside the void guard because an unseat is an event, and half a poll interval is
	-- long enough for the player to be standing in the road looking at a car driving away.
	local seatConn = self._seatConns[player]
	if seatConn then
		seatConn:Disconnect()
	end
	self._seatConns[player] = humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		if humanoid.SeatPart == nil then
			self:_onRiderLeftSeat(player, car)
		end
	end)

	self:getSignal("RaceEntered"):Fire(player)

	self.log:info(string.format("%s entering the race in %s, driving a %s…",
		player.Name, WorldConfig.displayName(world), car.Name))
end

--[[ Public: is this player in a race right now?

	True from the moment `enterRace` commits until `leaveRace` runs, which deliberately INCLUDES the
	pending window — the car exists and the rider is seated in it well before the client's road acks,
	so anything asking "can they do something else right now" has to count that window as racing. ]]
function RaceService.isRacing(self, player: Player): boolean
	return self._cars[player] ~= nil or self._pending[player] ~= nil
end

--- The world used to build the current race, independent of a later selection change.
function RaceService.worldForRun(self, player: Player): number?
	local car = self._cars[player] or self._pending[player]
	local world = car and car:GetAttribute("RaceWorld")
	return if type(world) == "number" then WorldConfig.resolve(world) else nil
end

--[[ Public: is the trip home after a run still holding this player's character? True from the top of
	`_returnToSpawn` until its `home()` (and `ReturnedHome`). `CarryService` waits this out before it
	puts anything in their hands; see that signal. ]]
function RaceService.isReturning(self, player: Player): boolean
	return self._returning[player] ~= nil
end

--[[ The HUD Play button's end of `enterRace`, and the only caller that is not trusted.

	Every other way into a race is the server watching the world — a Touched, a prompt, a death.
	This one is a remote, so it arrives whenever a client says so, as often as a client says so.
	`enterRace` is already idempotent per player, which covers the case that matters (you cannot
	own two cars), but idempotent is not the same as free: the window between the click and
	`_cars[player]` being populated is several frames of cloning a car and rigging its doors, and
	a client firing this in a loop would spend the server's frame budget in that window before the
	first entry ever lands. Hence a plain per-player cooldown, stamped on the ATTEMPT rather than
	on the entry, so a rejected attempt is as cheap as an accepted one.

	Silent on refusal on purpose. A player who mashes Play through the entry fade is the ordinary
	case, not an error, and it is already visibly doing something.

	`world` IS THE WORLD-SELECT SCREEN'S CARD, and it is optional: absent means "the one I am in",
	which is what the lobby pad and a one-click Play send. It is moved through `WorldService` rather
	than passed to `enterRace`, because which world you are in is that service's to own and it has
	to persist past this run — `enterRace` then reads it back the same way it always has, so there
	is still exactly one read of "which world" per race (see its comment for why that matters).

	A REFUSED WORLD REFUSES THE RACE. `setWorld` says no to a world that does not exist or that this
	player has not earned, and starting the run anyway would drop them into their CURRENT world —
	a race they did not ask for, in the wrong place, off one press. Doing nothing is the honest
	answer; the card is greyed out for the same reason on the client.

	A REFUSED CAR DOES NOT, and the asymmetry is the point. `carKey` is the SELECT CAR screen's card
	and it is stored the same way the world is — through the service that owns it, so the choice
	outlives this run and the lobby pad honours it too — but a car this player cannot drive leaves the
	stored one untouched and the run goes ahead in that (the world's own starter, for a player who has
	never chosen). That is a car they can always drive and the one they would have got by never
	opening the screen, so entering is strictly better than eating the press. It also covers the one
	honest failure: a player who presses Play before their profile has arrived owns nothing that
	`GarageService` can see yet, and refusing their race over a slow load would be the worst possible
	reading of it.

	AND A REQUEST THAT ARRIVES MID-RETURN WAITS RATHER THAN BEING REFUSED. `leaveRace` clears
	`_cars[player]` at the START of the trip home, while `_returnToSpawn` is still holding the
	character, streaming the lobby in and about to teleport them onto it — so for up to about 2.5s
	the two guards above say "not racing" while the beat is still going to move this player. Racing
	inside that window puts them in a car the return then drags them out of, and unanchors them over
	the road on its way past.

	Nothing could reach that window before the results screen grew a RACE AGAIN button
	(`RaceUIController`): the screen used to lift a second after the beat's worst case, so a human
	press was always late enough. It is no longer, and the fix is on this side rather than on the
	button's, because it makes EVERY route in safe — including the player who mashes Play through
	the fade, which was only ever safe by a margin nobody measured.

	WAITING RATHER THAN REFUSING, because a refusal here is silent and the player has just pressed
	a button that then did nothing. Bounded by the same failsafe that bounds the beat itself, so a
	beat that dies holding somebody costs this request a wait and not the session. ]]
function RaceService._onEnterRequest(self, player: Player, world: unknown, carKey: unknown)
	local now = os.clock()
	local blockedUntil = self._entryCooldowns[player]
	if blockedUntil and now < blockedUntil then
		return
	end
	self._entryCooldowns[player] = now + RaceConfig.EnterRequestCooldown

	if self._cars[player] or self._pending[player] then
		return
	end

	if self._returning[player] then
		--[[ ONE REQUEST WAITS PER BEAT, and this is not belt-and-braces. The cooldown above is a
			second and the wait below can be several, so a player pressing twice gets two threads
			holding for the same beat — and they would come out of it in the same frame, both past
			the re-check below, because `enterRace` does not populate `_pending` until it has cloned
			a car. Two races, one player, and the second one owns the tables. Dropping the later
			press is right on its own terms too: it is asking for a race the first one is already
			getting them. ]]
		if self._waitingToEnter[player] then
			return
		end
		self._waitingToEnter[player] = true
		local deadline = os.clock() + HOLD_FAILSAFE_TIMEOUT
		repeat
			RunService.Heartbeat:Wait()
		until not self._returning[player] or os.clock() >= deadline or player.Parent ~= Players
		self._waitingToEnter[player] = nil
		--- Everything the two guards above asked has had seconds to change its answer, so all three
		--- are asked again rather than assumed. A player who left, or who got into a race by some
		--- other door while this waited, is not to be entered into one now.
		if player.Parent ~= Players or self._cars[player] or self._pending[player] then
			return
		end
	end

	if world ~= nil then
		local WorldService = Shard.get("WorldService")
		if WorldService then
			local moved, why = WorldService:setWorld(player, world)
			if not moved then
				self.log:info(string.format(
					"%s asked to race world %s and cannot (%s); not entering.",
					player.Name, tostring(world), tostring(why)))
				return
			end
		end
	end

	--[[ After the world, because `setStartCar` may have to ask which road this car is being taken
		onto, and because a request that names both should not have stored the car if the world it
		went with was refused. `enterRace` reads the choice back through the same service — one
		stored value, one read per race, the same shape as the world above it. ]]
	if carKey ~= nil then
		local StartCarService = Shard.get("StartCarService")
		if StartCarService then
			local chosen, why = StartCarService:setStartCar(player, carKey, tonumber(world))
			if not chosen then
				--[[ The stored choice is left exactly as it was — a refused request must not cost the
					player the car they had legitimately chosen — so this run drives that, and only a
					player who had chosen nothing gets the starter. `carFor` re-checks it either way. ]]
				self.log:info(string.format(
					"%s asked to race in %s and cannot (%s); racing in their stored car instead.",
					player.Name, tostring(carKey), tostring(why)))
			end
		end
	end

	self:enterRace(player)
end

--[[ Wire a tagged EnterRace part so a player can start a race by ANY of:
	  • pressing its ProximityPrompt ("Enter Race"),
	  • walking onto the authored pad (Touched), or
	  • walking through a larger invisible hitbox around it (so you don't have to land
	    exactly on the small pad — that was the "nothing happens" confusion).
	All three funnel through one debounced `begin`, and enterRace itself guards against
	double-entry, so overlapping triggers are safe. Returns a cleanup for observeTag.

	NOTHING CALLS THIS TODAY — no part in the place carries the tag (see the header). It is dead
	but not stale: tag a part and every route below wakes up as written. ]]
function RaceService._bindEntryTrigger(self, part: BasePart)
	local conns = {}
	local debounce: { [Player]: boolean } = {}

	--[[ A player who is SITTING IN A VEHICLE does not trip this trigger.

		The pads are authored on the plots, and a plot is exactly where `LobbyCarService` stands a
		player's showroom car — so without this, driving your own car around your own lot rolls your
		character (welded to the seat, and therefore touching everything the car touches) onto the
		pad and yanks you out of it into a race. Showing a car off near your own plot was impossible.

		Phrased as "seated", not as "seated in a lobby car", so RaceService keeps knowing nothing
		about that feature — the rule that falls out is a good one on its own terms: you start a
		race from the pad ON FOOT. The Play button is deliberately NOT covered by this, because
		pressing it is an explicit choice rather than something you drove over, and the lobby car
		gets put away for you when it fires (see the `RaceEntered` signal). ]]
	local function begin(player: Player?)
		if not player or debounce[player] or self._cars[player] or self._pending[player] then
			return
		end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.SeatPart then
			return
		end
		debounce[player] = true
		task.delay(1, function()
			debounce[player] = nil
		end)
		self:enterRace(player)
	end

	-- Walk-onto: the authored pad itself.
	table.insert(
		conns,
		part.Touched:Connect(function(hit)
			begin(self:_playerFromHit(hit))
		end)
	)

	-- Forgiving walk-near: a bigger invisible hitbox around the pad (runtime-only; not
	-- authored geometry, so it never syncs back to the place).
	local zone = Instance.new("Part")
	zone.Name = "EnterTouchZone"
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CastShadow = false
	zone.Anchored = true
	zone.Size = part.Size + Vector3.new(6, 6, 6)
	zone.CFrame = part.CFrame
	zone.Parent = part
	table.insert(
		conns,
		zone.Touched:Connect(function(hit)
			begin(self:_playerFromHit(hit))
		end)
	)

	-- Press-E: any ProximityPrompt on the trigger (the placeholder pad already ships one).
	for _, prompt in part:GetDescendants() do
		if prompt:IsA("ProximityPrompt") then
			if prompt.ActionText == "" or prompt.ActionText == "ProximityPrompt" then
				prompt.ActionText = "Enter Race"
			end
			prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 12)
			table.insert(
				conns,
				prompt.Triggered:Connect(function(player)
					begin(player)
				end)
			)
		end
	end

	return function()
		for _, c in conns do
			c:Disconnect()
		end
		if zone.Parent then
			zone:Destroy()
		end
	end
end

-- Client acked its local road is ready → unanchor, hand ownership, and deploy driving.
--[[ Private (the entry fail-safe): the client never said its road was ready, so give up on this
	entry — safely.

	THIS USED TO CALL `_onRaceReady` INSTEAD, AND THAT IS WHAT KILLED PEOPLE. Going live unanchors
	the car and hands it to the client, and the ONLY thing that makes that safe is the client having
	just said "my road exists". Doing it on a timeout does it in precisely the case where the road
	does NOT exist — and the road is client-sided (RoadController's header), so there is nothing
	under the car on this side either. There never was.

	MEASURED, with the client's road build stalled past the timeout. The car sat anchored at y=21,
	the fail-safe released it, and it fell clean through the world — 21 -> -11.9 in under half a
	second, reaching 109 studs/s — until the void guard caught it and ran `wreckRace(player, "fell")`.
	The player is shown WRECKED, paid a quarter of nothing, and never touched the car. That is the
	"random death for no reason" report, and it is the likeliest fling too: the release and the road
	finishing land within a few hundred ms of each other on a slow device, so the road can appear
	around a car that is already falling through where it is about to be.

	Note the second half of what going live did: `_onRaceReady` clears `_pending`, and the void
	sweep deliberately skips pending cars (see `_sweepFallen`). So the old fail-safe unanchored the
	car into an empty world and handed it to the sweeper in the same breath.

	SO THE FAIL-SAFE NOW DOES WHAT IT ALWAYS CLAIMED TO — stop the player getting STUCK, which is
	the thing it was written for. It puts them back on their feet and ends the entry. That costs
	them the race they asked for and nothing else: a run that never moved settles at nothing
	(`RewardConfig.Distance.MinStuds`), so there is no payout to lose and no wreck on the record.
	Being bounced back to the lobby is a bad outcome; being killed by your own phone's loading time
	is a worse one.

	The car is still anchored here — nothing has thawed it — so the rider is safe where they sit and
	the only thing that must happen before the car is destroyed is getting them out of the seat and
	home. `_returnToSpawn` owns the wait for the seat to genuinely release; `leaveRace` owns the
	rest, including dropping the fade the player has been looking at since `RaceEntering`. ]]
function RaceService._abortEntry(self, player: Player, car: Model, reason: string?)
	if self._pending[player] ~= car then
		return -- the client acked in the meantime, or the run already ended; nothing to abort
	end
	--[[ `reason` is for the callers that KNOW why, and it exists because the timeout's message is a
		diagnosis, not an observation: "never acked their road" was printed for every abort, including
		the ones that had nothing to do with the road, and that sent the seat bug above hunting through
		the road builder for a fortnight. The default stays exactly what it was for the fail-safe. ]]
	self.log:warn(string.format(
		"%s: aborting the entry rather than releasing the car into an empty world (%s).",
		player.Name,
		reason or string.format("never acked their road within %.1fs", RaceConfig.EnterReadyTimeout)
	))
	--[[ Say so, while there is still a screen to say it on. The client has been looking at its
		loading bar for `EnterReadyTimeout` seconds and is about to be put back in the lobby with no
		car; `RaceUIController._onAborted` is what turns that into a sentence rather than a press of
		Play that appeared to do nothing. It has to go FIRST — `leaveRace` below fires `RaceLive`,
		which is the client's cue to start dropping the screen. ]]
	self:getRemoteEvent("RaceAborted"):Fire(player)
	self:_returnToSpawn(player)
	self:leaveRace(player)
end

function RaceService._onRaceReady(self, player: Player)
	local car = self._pending[player]
	if not car then
		return
	end
	self._pending[player] = nil
	if not car.Parent then
		return
	end

	-- WHEN the car changed hands, which is what makes a fall in the next few seconds readable as a
	-- failed handoff rather than as a wreck. See `_catchFall` and `RaceConfig.HandoffGraceTime`.
	self._liveAt[player] = os.clock()
	-- ...and WHERE, which is what `_checkShields` measures "have they actually started driving"
	-- against. Read BEFORE the thaw below, so it is the car still standing still on the lane and
	-- not one that has already had a frame of physics. See `RaceConfig.SpawnShield`.
	self._liveFrom[player] = if car.PrimaryPart then car.PrimaryPart.Position else nil

	self:_setCarFrozen(car, false)
	--[[ THE LINE THAT MOVES THE CAR, and the reason NOTHING may move this player's
		`ReplicationFocus` away from their character for the length of a race.

		Handing ownership to the client is what makes the car drivable at all: the road it is driving
		on is client-built, so the server has no ground under it and could not simulate it if it
		wanted to. But a client only STEPS the assemblies inside its own simulation region, and that
		region follows `ReplicationFocus`. Point the focus somewhere else and the car falls down the
		crack between the two machines — the server won't simulate it (it is not the owner) and the
		client won't either (out of region). It does not error and it does not fall: it stops dead,
		holding the last velocity it was given, which reads as a car frozen at a slight tilt on the
		start line with a live HUD, a seated driver and correct network ownership.

		THIS IS MEASURED, NOT REASONED. A race was left running and sampled from the server:

		    focus parked on Plot1.PlotSpawn   0.0000 studs in 1s, velocity stale at (0, -22.2, 0)
		    focus cleared                    77.6242 studs in 2s, velocity (0, 0, +60.7)

		Same car, same owner, same seat, one property apart. `ModelStreamingMode.PersistentPerPlayer`
		in `_spawnCar` does not buy this back — persistent governs whether the client HOLDS the model,
		not whether it simulates it.

		So the "Gameplay Paused" fix cannot be bought here (see `playtests/2026-08-16`): parking the
		focus in the lobby was tried, and this is what it cost. That pause is a `StreamingIntegrityMode`
		setting on Workspace, and it has to be answered there. ]]
	if car.PrimaryPart then
		pcall(function()
			car.PrimaryPart:SetNetworkOwner(player)
		end)
	end

	-- Deploy the stock driving controls on the now-live car (and drop the fade when done).
	self:_deployDriving(car, player)
	self.log:info(string.format("%s is racing.", player.Name))
end

--[[ Does `player` currently have the stock Driver controls deployed for THIS specific car?

	The control GUI is named "<car>_<guid>_ClientControls"; we match on the Driver's CarValue so a
	leftover GUI from a previous car can't give a false positive.

	AND ON `ScriptsReference`, WHICH IS THE COMPLETENESS TEST. The stock `onEnterSeat` builds that
	GUI in pieces — ScreenGui, LocalVehicleGui, Driver, and `ScriptsReference` last — so a deploy
	that dies partway leaves a GUI with a Driver in it that will never run: `LocalVehicleGui` waits
	on exactly that ObjectValue, and it is the Driver's first require. Testing for the Driver alone
	read that corpse as a working deploy, so `_deployDriving` broke out of its repair loop on the
	first pass and left the player in a car that could not move (see the note on the anchored
	`SetNetworkOwner` in `Modules/Vehicle`, which is what killed the deploy). Testing for the LAST
	thing written instead means a half-deploy is repaired by the occupant toggle like any other. ]]
function RaceService._hasDriverControls(self, player: Player, car: Model): boolean
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	for _, gui in playerGui:GetChildren() do
		if string.find(gui.Name, "_ClientControls", 1, true) then
			local driver = gui:FindFirstChild("Driver")
			local carValue = driver and driver:FindFirstChild("CarValue")
			if carValue and carValue.Value == car and gui:FindFirstChild("ScriptsReference") then
				return true
			end
		end
	end
	return false
end

-- Remove stock driver-control GUIs for a given car, plus any orphaned ones whose car is
-- already gone. leaveRace destroys the car directly, which skips the vehicle's own
-- onExitSeat cleanup, so these would otherwise pile up in PlayerGui across races.
function RaceService._cleanupDriverControls(self, player: Player, car: Model?)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	for _, gui in playerGui:GetChildren() do
		if string.find(gui.Name, "_ClientControls", 1, true) then
			local driver = gui:FindFirstChild("Driver")
			local carValue = driver and driver:FindFirstChild("CarValue")
			local target = carValue and carValue.Value
			if (car and target == car) or target == nil or not target:IsDescendantOf(workspace) then
				gui:Destroy()
			end
		end
	end
end

--[[ Re-run the stock vehicle's seat-enter so it deploys the client Driver controls, engine
	effects and driver network ownership on the now-unanchored, live car.

	Why this is needed: the very first Sit (in enterRace) can't do it. That Sit fires before
	the freshly cloned Vehicle script has connected its "Occupant changed" listener, and while
	the car is still anchored — and the stock onEnterSeat throws when it calls SetNetworkOwner
	on an anchored assembly. Net result: onEnterSeat never ran, so the driver was stuck seated
	but unable to drive until getting out and back in (which is a fresh, clean occupant change).

	Toggling the occupant here (eject → immediately re-sit) reproduces that clean re-entry on
	the live car, so the stock scripts deploy exactly as a normal entry would. Fires `RaceLive`
	once the controls are confirmed (or after giving up) so the client's fade never sticks. ]]
function RaceService._deployDriving(self, car: Model, player: Player)
	local seat = car:FindFirstChild("VehicleSeat", true)
	if not (seat and seat:IsA("VehicleSeat")) then
		self:getRemoteEvent("RaceLive"):Fire(player)
		return
	end

	--[[ Set BEFORE the spawn below, not inside it. This flag is what tells `_onRiderLeftSeat` that
		the unseat it is about to see is ours — and a `task.spawn` body does not run until the next
		resumption point, which is one more scheduler turn than the guard can afford to be wrong for.
		Cleared on every exit from the loop, including the early returns. ]]
	self._reseating[player] = true
	--[[ ...and the same window in a form the CAR's own scripts can read. `Modules/Vehicle`'s
		`onExitSeat` checks this before it tells the client about an exit, so the toggle below no
		longer fires a seat-exit remote at the client that would answer it by switching off the very
		controls this function is deploying (`Vehicle.ReseatAttribute` has the whole account).
		Cleared on every path out of the loop, exactly as `_reseating` is. ]]
	car:SetAttribute(Vehicle.ReseatAttribute, true)

	task.spawn(function()
		-- Clear any orphaned control GUIs from previous cars before we deploy this one's.
		self:_cleanupDriverControls(player, nil)

		local deployed = false
		for _ = 1, 4 do
			if self._cars[player] ~= car or not car.Parent then
				self._reseating[player] = nil
				car:SetAttribute(Vehicle.ReseatAttribute, nil)
				return -- race ended / car gone; nothing to reveal for this car
			end
			if self:_hasDriverControls(player, car) then
				deployed = true
				break
			end

			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not (humanoid and humanoid.Health > 0) then
				break
			end

			--[[ Toggle the occupant so the stock onEnterSeat fires on the live car.

				THE RE-SIT WAITS ON `SeatPart`, NOT ON A FRAME. `seat:Sit(nil)` clears `Occupant` in
				the same resumption but the rider's own `SeatPart` takes a few physics frames to
				follow, and a `Sit` issued while it is still set is the silent no-op `_releaseSeat`
				documents — so the old one-frame `task.wait()` could put the driver out of the car and
				fail to put them back. The loop this sits in recovered on its next pass (by then the
				release had landed), which is exactly why it never showed up as anything more
				alarming than an occasional slow deploy. ]]
			if seat.Occupant == humanoid then
				pcall(function()
					seat:Sit(nil)
				end)
			end
			task.wait() -- one frame so the stock onExitSeat is observed distinctly...
			self:_releaseSeat(humanoid) -- ...and however many more the release itself needs
			if seat.Occupant == nil and humanoid.Parent then
				pcall(function()
					seat:Sit(humanoid)
				end)
			end

			-- Give the deferred onEnterSeat a moment to deploy the controls, then re-check.
			for _ = 1, 20 do
				task.wait()
				if self:_hasDriverControls(player, car) then
					break
				end
			end
			if self:_hasDriverControls(player, car) then
				deployed = true
				break
			end
		end

		-- The occupant is settled either way now, so hand the seat back to the watcher.
		self._reseating[player] = nil
		car:SetAttribute(Vehicle.ReseatAttribute, nil)
		if not deployed then
			self.log:warn(string.format("%s: driver controls did not deploy.", player.Name))
		end
		-- Reveal on the client regardless, so the transition screen never sticks.
		if self._cars[player] == car then
			self:getRemoteEvent("RaceLive"):Fire(player)
		end
	end)
end

--[[ Where a player lands when they come back from a run.

	Their own RespawnLocation comes first: it's the per-player hook, it's nil unless something
	deliberately assigned it, and it's where the planned per-player tycoon spawn will live — so
	that lands here for free once a tycoon sets it. Then a named part (so a lobby can move the
	shared return point without touching code), then any SpawnLocation, then the origin. ]]
--[[ The part a player goes home to. Split out of `_returnCFrame` because the streaming focus wants
	the PART and the teleport wants a CFrame above it, and they must not be allowed to disagree about
	which pad that is: a focus parked on one spawn while the return beat teleports to another would
	stream in the wrong corner of the lobby and land the player in the pop-in it was added to prevent. ]]
function RaceService._returnPart(self, player: Player): BasePart?
	local respawn = player.RespawnLocation
	if respawn and respawn:IsDescendantOf(workspace) then
		return respawn
	end
	if RaceConfig.ReturnSpawnName then
		local named = workspace:FindFirstChild(RaceConfig.ReturnSpawnName)
		if named and named:IsA("BasePart") then
			return named
		end
	end
	local any = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	return if any and any:IsA("BasePart") then any else nil
end

function RaceService._returnCFrame(self, player: Player): CFrame
	local target = self:_returnPart(player)
	if target then
		return target.CFrame + Vector3.new(0, 4, 0)
	end
	self.log:warn("No spawn point found to return to; using the origin.")
	return CFrame.new(0, 8, 0)
end

--[[ Freeze a character exactly where it stands, and hand back the undo.

	THE RETURN BEAT IS THE ONE STRETCH OF A RUN WHERE THE RIDER HAS NO FLOOR ON EITHER MACHINE.
	`leaveRace` destroys the car and fires `RaceEnd` in the same breath, and `RaceEnd` is the
	client's cue to tear its local road down (`RoadController._onRaceEnd`) — so the deck they were
	driving on a moment ago stops existing at both ends, and what is left is a loose body in the sky
	at deck height. Everything the beat does from there yields: the seat release (capped at
	`SEAT_RELEASE_TIMEOUT`), the frame a re-jointed body needs to become one assembly, and above all
	`RequestStreamAroundAsync` (capped at `RETURN_STREAM_TIMEOUT`).

	Those caps add up to 2.5s, and a body falling from the deck passes
	`Workspace.FallenPartsDestroyHeight` at about 2.3 — the same arithmetic `RaceConfig.VoidDropStuds`
	sets out for the car. So the beat's own worst case is LONGER THAN THE BUDGET IT IS SPENDING:
	Roblox deletes every part of the character mid-return, the Humanoid enters Dead, and PlotService
	respawns them. That is "sometimes the character dies when the game ends", and the reason no
	health bar ever moves on the way is that **nothing damaged them** — `Humanoid.Died` tracks the
	Dead STATE, and `Health` is still sitting at 100 when it fires (the same signature the
	void-fall guard below is written around).

	It is a race, not a certainty, which is why it is intermittent: the ordinary path spends ~2.0s of
	the 2.3 and lives. It loses when anything adds a few hundred milliseconds — a slow stream round
	trip on a real server (and the plot has ALWAYS streamed out by the end of a run, so the request
	is never free), a rider who died in the seat and therefore burns the full seat-release cap, or a
	body that was already falling before the beat started (`_catchFall`'s adrift branch).

	Anchoring removes the race instead of shortening it: a body that cannot fall cannot run out of
	time, however slow the stream request is. Two details it has to get right:

	  • EVERY part, not just the root. An anchored part is its own assembly root, so anchoring the
	    root alone leaves the rest of a rig falling out from under it — the same reason `_throwRider`
	    anchors part by part rather than once at the top.
	  • The undo restores what each part ACTUALLY was rather than blanket-unanchoring, so it can
	    never thaw something that was deliberately frozen, and it is safe to call twice.

	Velocity is deliberately NOT touched here. Anchoring does not clear `AssemblyLinearVelocity` —
	a frozen assembly goes on claiming whatever it was doing when it stopped — so the zeroing has to
	happen on the far side of the release, and that is where `_returnToSpawn` does it. ]]
function RaceService._holdInPlace(self, character: Model): () -> ()
	local held: { [BasePart]: boolean } = {}
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			held[part] = part.Anchored
			part.Anchored = true
		end
	end

	local released = false
	local function release()
		if released then
			return
		end
		released = true
		for part, wasAnchored in held do
			if part.Parent then
				part.Anchored = wasAnchored
			end
		end
	end

	--[[ AND A PLAYER LEFT ANCHORED IS WORSE THAN THE FALL THIS PREVENTS. The caller releases on
		every path it knows about, but "every path it knows about" is exactly the assumption that
		put a 2.5s beat inside a 2.3s budget in the first place — so the hold also lets itself go.
		The cap is well past the beat's own worst case, which means firing is always a bug and says
		so; a player standing frozen on their plot for the rest of the session would not. ]]
	task.delay(HOLD_FAILSAFE_TIMEOUT, function()
		if not released then
			self.log:warn("A return beat never released its rider; unfreezing them. This is a bug.")
			release()
		end
	end)

	return release
end

--[[ Say what killed them, on the frame it happens.

	A player dying as their run ends is the one failure in this flow that arrives with no evidence
	attached. There is no damage to trace because nothing in this game damages a player — grep the
	source: the only write to `Humanoid.Health` outside the admin panel is none. So a death here is
	always the ENGINE's, and the two ways it can be are told apart by one number:

	  • NO PARTS AND FULL HEALTH is `Workspace.FallenPartsDestroyHeight`. The body fell out of the
	    world and Roblox deleted it; `Humanoid.Died` tracks the Dead STATE, not the number, so it
	    fires with `Health` untouched at 100 and no health bar ever moves on the way down. That is
	    the shape `_holdInPlace` is written against, and if it shows up here the hold did not cover
	    the whole window.
	  • ZERO HEALTH WITH THE BODY INTACT is something else entirely and nothing in the race flow can
	    currently produce it, so it would be a genuinely new bug rather than this one recurring.

	Cheap and always on. It costs one connection per run, dropped on a timer, and the alternative is
	another playtest spent asking testers what their screen looked like. ]]
function RaceService._watchReturnDeath(self, player: Player, character: Model, humanoid: Humanoid)
	local conn
	conn = humanoid.Died:Connect(function()
		local parts = 0
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		self.log:warn(string.format(
			"%s died on the way home from a run: health %.1f, %d parts left, y=%s. %s",
			player.Name,
			humanoid.Health,
			parts,
			if root and root:IsA("BasePart") then string.format("%.1f", root.Position.Y) else "no root",
			if parts == 0
				then "No body and full health is the void fall — FallenPartsDestroyHeight deleted them mid-return, "
					.. "nothing damaged them. The return beat outran its budget; see `_holdInPlace`."
				else "Full body at zero health means something DAMAGED them, which the void fall never does — "
					.. "this is not the falling bug."
		))
	end)

	task.delay(DEATH_WATCH_TIME, function()
		conn:Disconnect()
	end)
end

--[[ Put the rider back on their feet at their spawn.

	Waiting for the seat to genuinely let go is the whole trick. Leaving the seat is what
	un-welds the rider from the car, but `Sit = false` doesn't take effect until a later
	physics step (~5 frames, measured) — until then the engine still has the root pinned to
	the seat, and a teleport written inside that window is simply lost. That was the bug:
	one deferred frame isn't a physics step, so the move landed on a still-seated rider and
	went nowhere, leaving the player hanging over the road until they fell into the void.
	(With the car still alive it's worse — the surviving weld resolves the teleport by
	flinging them across the map.) The cap is a fail-safe, not the normal path.

	Afterwards the character is a loose, fast-moving assembly, so its velocity is zeroed —
	twice, a frame apart, because the client owns the character and can re-assert the car's
	momentum on the step right after the move.

	`onHome` IS FOR THE ONE CALLER THAT HAS TO WAIT. Everything below the seat release runs in a
	spawned thread, so this function returns long before the player is anywhere near their plot —
	which costs nothing for an ending that has nothing left to do, and is the whole problem for
	`abandonRun`, whose job is to end one run and start another. Seating a player in a new car while
	this beat is still in flight lands the teleport home on them mid-race, so the beat says when it
	is done rather than the caller guessing at a duration. Called exactly once, on every path out of
	the thread including the ones that give up early: a caller waiting on it must never be left
	waiting. ]]
function RaceService._returnToSpawn(self, player: Player, onHome: (() -> ())?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid) then
		if onHome then
			onHome()
		end
		return
	end

	--[[ "THIS BEAT OWNS THIS CHARACTER", and it is raised here because everything below yields and
		one of the things that can arrive while it does is a request for another race.

		That used to be a theoretical worry and stopped being one with RACE AGAIN
		(`RaceUIController`): the button lands about 1.85s into the results screen and this beat's
		own worst case is about 2.5s — the seat release, a frame for a re-jointed body, and above
		all `RequestStreamAroundAsync`. An entry accepted inside that window seats the player in a
		new car and then this thread's `PivotTo(target)` drags them out of it and back to the lobby,
		with `release()` unanchoring them somewhere over the road. `_onEnterRequest` waits this out.

		IT COMES DOWN AT `home()`, NOT AT THE END. `_watchLanding` runs for seconds after and is
		already safe against a fresh run — it bails the moment `_cars[player]` exists, and says so —
		so the window that has to be fenced is exactly the stretch where the beat is still going to
		move somebody. ]]
	--[[ THE FLAG IS THIS BEAT'S TOKEN, NOT `true` (2026-10-14). A beat's failsafe below used to clear
		the flag unconditionally eight seconds on, so with two quick runs back to back the FIRST beat's
		timer cleared the flag in the middle of the SECOND beat, and a RACE AGAIN waiting on it walked
		straight into a player that beat was still holding: seated anchored in the new car, which then
		cannot move at all. Each beat now clears only its own token. ]]
	local beat = {}
	self._returning[player] = beat
	local function home()
		if self._returning[player] == beat then
			self._returning[player] = nil
		end
		self:getSignal("ReturnedHome"):Fire(player)
		if onHome then
			onHome()
		end
	end
	--- ...and a fence under the flag itself, because a thread that died between the line above and
	--- `home()` would otherwise leave this player's every future race waiting out a beat that is
	--- never going to finish. `HOLD_FAILSAFE_TIMEOUT` is already sized past this beat's worst case
	--- and is the failsafe on the anchor that would be stuck with it.
	task.delay(HOLD_FAILSAFE_TIMEOUT, function()
		if self._returning[player] == beat then
			self._returning[player] = nil
		end
	end)
	if humanoid.SeatPart then
		humanoid.Sit = false
	end
	--[[ A rider who was thrown out is put back together BEFORE the teleport, never after it. While
		they are limp the character is not one assembly but a dozen, so a `PivotTo` moves a dozen
		loose parts that then fall apart again at the far end — the player arrives home in a heap on
		the spawn pad. Standing them up first is also what re-arms their own controls. ]]
	local stoodUp = self:_standRider(player)
	self:_watchReturnDeath(player, character, humanoid)

	local target = self:_returnCFrame(player)
	task.spawn(function()
		local deadline = os.clock() + SEAT_RELEASE_TIMEOUT
		while humanoid.SeatPart or humanoid:GetState() == Enum.HumanoidStateType.Seated do
			if os.clock() >= deadline then
				self.log:warn(string.format("%s never left the seat; returning them anyway.", player.Name))
				break
			end
			RunService.Heartbeat:Wait()
		end
		-- A body that has just been re-jointed is still a dozen parts as far as this frame's solver
		-- is concerned; the wait is what lets it become one assembly before we move it. The seat loop
		-- above passes straight through for a thrown rider — they have no seat — so this is the only
		-- thing standing between the re-joint and the teleport.
		if stoodUp then
			RunService.Heartbeat:Wait()
		end

		--[[ NOTHING PAST THIS LINE MAY LET THEM FALL. The car is gone, the client has torn its road
			down, and everything below yields — see `_holdInPlace`, which is where the 2.3-second
			budget this used to overspend is written out. Held here rather than at the top of the
			beat because up to this point the rider is still welded into a seat, and anchoring a body
			that something else is holding fights whatever is holding it. ]]
		local release = self:_holdInPlace(character)

		--[[ Make sure the lobby is actually THERE before we drop them into it.

			This is the one place in the race flow where asking the server to stream is the right
			tool: unlike the race origin, the lobby is real server geometry, and this is a teleport
			across the map rather than a drive through empty space. Without it the player can arrive
			before their plot does and stand in the "Gameplay Paused" dialog on landing — the same
			dialog, earned honestly this time.

			It earns its keep on every return now, not just the odd one: the whole race happens
			thousands of studs from the lobby with the focus on the character, so by the time a run
			ends the player's plot has long since streamed out and has to come back before they land
			on it.

			Failure is not fatal and must not be. It yields, so it can outlive the character it was
			called for, and it throws on a request the engine will not serve — neither is a reason to
			skip the teleport and leave the player hanging over the road.

			BUT IT IS NOT A SHRUG EITHER, WHICH IS WHAT IT USED TO BE. A bare `pcall` here threw the
			answer away, and the answer is the single best predictor of the landing going wrong: a
			request that timed out means the plot has NOT arrived on that client, and the release at
			the bottom of this beat is about to stand the player on a floor that is not there yet.
			It is logged now, and `_watchLanding` below is what acts on it. ]]
		local streamed, streamErr = pcall(function()
			player:RequestStreamAroundAsync(target.Position, RETURN_STREAM_TIMEOUT)
		end)
		if not streamed then
			self.log:warn(string.format(
				"%s's lobby did not stream in before the return (%s); watching the landing.",
				player.Name, tostring(streamErr)))
		end

		if not (character.Parent and humanoid.Parent) then
			release() -- they were destroyed or respawned under us; leave nothing anchored behind
			home()
			return
		end
		--[[ Guarded because the release below MUST run. A character can be torn down between the
			check above and this line, and a throw here would otherwise leave the thread dead with
			the player still frozen. ]]
		local moved, err = pcall(function()
			character:PivotTo(target)
		end)
		if not moved then
			self.log:warn(string.format("%s could not be moved home: %s", player.Name, tostring(err)))
		end

		--[[ The pose is written, so physics can have them back — and it has to happen BEFORE the
			velocity is zeroed, not after. Anchoring never cleared what they were doing, so an
			anchored body still claims the fall it was on when the beat caught it; zeroing while it
			is held writes a number that the release then throws away. Release, then zero, then zero
			again a frame later for the reason the note above gives: the client owns this character
			and gets to re-assert its momentum on the very next step. ]]
		release()
		self:_stillAfterMove(character)

		--- The pose is written and physics has them back, which is as home as this beat ever gets.
		--- Before the watch below rather than after it, because that watch runs for seconds.
		home()

		--[[ ...and then WATCH, because everything above this line is the server's account of the
			return and the player's account is written somewhere else entirely. See `_watchLanding`. ]]
		self:_watchLanding(player, character, humanoid, target)
	end)
end

--[[ Zero what a returned body is carrying, twice, a frame apart.

	Split out of `_returnToSpawn` so `_watchLanding` can reuse it — a recovered landing has to settle
	exactly the way the first one does, and two copies of this would be two chances to fix one and
	not the other.

	TWICE, A FRAME APART, and the gap is the point: the client owns this character and gets to
	re-assert its momentum on the very next step, so a single write lands before the thing it is
	meant to cancel. It runs AFTER the release for the reason written at the release itself —
	anchoring never cleared the fall a body was on, so zeroing while it is held writes a number the
	release then throws away. ]]
function RaceService._stillAfterMove(self, character: Model)
	local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	RunService.Heartbeat:Wait()
	if root.Parent then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

--[[ Did the teleport home actually take? Watch for two seconds, and put them back if it didn't.

	=== WHY A SERVER-SIDE TELEPORT NEEDS A RECEIPT ============================================

	`PivotTo` returning is not the player arriving. The character is owned by the CLIENT, and the
	last act of the return beat is to hand physics back to it — so from the release onward the player
	stands on whatever THAT MACHINE has streamed in, not on what the server can see. The whole race
	happens thousands of studs from the lobby, so the plot has always streamed out by the end of a
	run and has to come back; when `RequestStreamAroundAsync` above runs out its two seconds without
	finishing, the release drops the player through a floor that has not arrived, at the exact moment
	the server has stopped looking.

	THIS IS THE OTHER HALF OF TWO REPORTED BUGS AND THEY ARE THE SAME BUG (playtest 24 Aug):

	  • "my character dies when the run ends" — three testers, consistent. The rider falls from the
	    deck with nothing under them, passes `Workspace.FallenPartsDestroyHeight` (-500), and every
	    part of them is destroyed. The Humanoid enters Dead with its Health still at 100, which is
	    why no health bar ever moves on the way (see `_watchReturnDeath`), and `PlotService`
	    respawns them — so the player experiences a death they did not earn between the run and
	    their plot.
	  • "dropped into an empty grey void after losing a run" — the same fall, on a run that ended
	    early enough to still be over `Workspace.Baseplate`. That part is 2048x2048 at y 0, and the
	    storey-0 race origin is (-334, 17.9, -554.8), directly above it — so instead of dying the
	    player lands 17.9 studs down on a bare grey plane, 2,189 studs from the nearest plot and far
	    outside any streaming radius. Nothing else is visible, so the game looks broken.

	    The Baseplate's edge is what picks which of the two you get: it runs out 1,578 studs down
	    the road, so a short run lands on it and a long one falls past where it ends.

	NOTHING CAUGHT EITHER because every guard the return beat has is keyed to the player DYING —
	`_watchReturnDeath` logs a death, `_checkForFalls` walks `self._cars` and `leaveRace` has already
	cleared that entry. A player who lands on a baseplate instead is invisible to all of it.

	=== WHAT IT DOES =========================================================================

	Re-anchor, re-stream, re-teleport, up to `RETURN_MAX_ATTEMPTS`. Anchoring first is what makes the
	retry safe to be slow: a body that cannot fall cannot run out of world while the second stream
	request takes its time, which is the same bargain `_holdInPlace` makes for the first attempt.

	The thresholds are `RETURN_LANDING_DROP` and `RETURN_LANDING_STRAY`, both sized so ordinary play
	inside the window cannot reach them — see their note. A player who walks off their own plot in
	the two seconds after a run is the one false positive this can have, and being set back down on
	your own spawn pad is a far cheaper wrong answer than the death it is here to prevent. ]]
function RaceService._watchLanding(self, player: Player, character: Model, humanoid: Humanoid, target: CFrame)
	task.spawn(function()
		local deadline = os.clock() + RETURN_WATCH_TIME
		local attempts = 0

		while os.clock() < deadline do
			RunService.Heartbeat:Wait()

			--[[ Every way this character can stop being our business, checked before it is measured.
				A destroyed or respawned character is `PlotService`'s from here (it respawns on
				`RespawnLocation`, which is the player's own plot pad), and a dead one is already
				past anything this could do for it. ]]
			if player.Parent ~= Players or player.Character ~= character then
				return
			end
			if not (character.Parent and humanoid.Parent) or humanoid:GetState() == Enum.HumanoidStateType.Dead then
				return
			end
			-- A racer who started a NEW run inside the window is not to be dragged back to the lobby.
			if self._cars[player] or self._pending[player] then
				return
			end
			local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
			if not (root and root:IsA("BasePart") and root.Parent) then
				return -- the void already took them; `_watchReturnDeath` owns that story
			end

			local offset = root.Position - target.Position
			local fell = offset.Y < -RETURN_LANDING_DROP
			local astray = Vector2.new(offset.X, offset.Z).Magnitude > RETURN_LANDING_STRAY
			if not (fell or astray) then
				continue
			end

			attempts += 1
			if attempts > RETURN_MAX_ATTEMPTS then
				self.log:warn(string.format(
					"%s is still not home after %d attempts (at %.0f, %.0f, %.0f, %.0f studs from the pad); giving up.",
					player.Name, RETURN_MAX_ATTEMPTS, root.Position.X, root.Position.Y, root.Position.Z, offset.Magnitude))
				return
			end

			self.log:warn(string.format(
				"%s did not land home (%s: %.0f, %.0f, %.0f, %.0f studs out); re-streaming and putting them back (attempt %d).",
				player.Name,
				if fell then "fell through the pad" else "never left the race",
				root.Position.X, root.Position.Y, root.Position.Z, offset.Magnitude,
				attempts))

			--[[ A RETRY IS A RETURN, AND IT FENCES ITSELF LIKE ONE (2026-10-14). It anchors the player
				and yields for up to `RETURN_STREAM_TIMEOUT`; `home()` already cleared the beat's flag,
				so a RACE AGAIN waiting on it used to go straight in during that yield, seat the
				anchored player in the new car (which is then anchored with them, and will not move),
				and this then dragged them back toward the lobby. The symptom was a car that sat still
				on the new road and jerked every few seconds as the attempts came round. So the flag is
				raised again for the length of the attempt, and the race is asked for again after the
				yield, where this lets go and stands down rather than moving anybody. ]]
			local attempt = {}
			self._returning[player] = attempt
			local hold = self:_holdInPlace(character)
			pcall(function()
				player:RequestStreamAroundAsync(target.Position, RETURN_STREAM_TIMEOUT)
			end)
			local racing = self._cars[player] ~= nil or self._pending[player] ~= nil
			if racing or not (character.Parent and humanoid.Parent) then
				hold() -- leave nothing anchored behind
				if self._returning[player] == attempt then
					self._returning[player] = nil
				end
				return
			end
			pcall(function()
				character:PivotTo(target)
			end)
			hold()
			self:_stillAfterMove(character)
			if self._returning[player] == attempt then
				self._returning[player] = nil
			end

			-- The clock restarts on the attempt, not on the beat: a retry that lands wants its own
			-- two seconds of being watched, and one that does not wants the next attempt.
			deadline = os.clock() + RETURN_WATCH_TIME
		end
	end)
end

-- === Falling out of the world ===============================================

--[[ Catch a car that has left the world, and end the run instead of the session.

	FREEZING COMES FIRST, AND IT IS THE POINT OF THIS FUNCTION. `wreckRace` below is a beat, not an
	instant: 1.5s of wreck, then a fade, then the teleport home — call it on a car in free fall and
	the car covers about 900 studs while it plays. From a deck at ~18 that is well past
	`FallenPartsDestroyHeight`, so Roblox destroys the car and every part of the rider welded into it
	partway through the beat, and the thing we were trying to rescue is gone before the rescue lands.
	Anchoring stops the fall dead and costs nothing: the car is invisible to the player by now, it is
	about to be destroyed by `leaveRace` anyway, and the rider is welded to it so they stop with it.

	A rider who is NOT in the seat any more is the other case and it needs the opposite treatment —
	freezing the car saves nobody, because they are falling on their own. They get sent home
	immediately rather than at the end of the beat; `_returnToSpawn`'s wait for the seat to release
	finds no seat and passes straight through.

	`wreckRace` is idempotent per player, so a car and its rider crossing the line on the same sweep
	runs one beat, not two. ]]
function RaceService._catchFall(self, player: Player, car: Model, riderAdrift: boolean)
	self:_setCarFrozen(car, true)

	--[[ DID THE HANDOFF FAIL, or did they fall? Inside `RaceConfig.HandoffGraceTime` of the car
		changing hands there is no third answer — read that config note for why a real wreck cannot
		be this early — so this is an entry that fell over, and it exits the way `_abortEntry` does
		instead of the way a wreck does: no WRECKED banner, no wreck beat, no revive offer over a run
		that never started, and nothing settled beyond the nothing a zero-distance run is worth.

		The car is already frozen above, so the rider is safe where they sit for as long as this
		takes. `RaceAborted` goes first for the same reason it does in `_abortEntry` — `leaveRace`
		fires `RaceLive`, which is the client's cue to drop the screen — though it only has a screen
		to draw on if the entry fade is somehow still up; by this point it usually isn't, and the
		player simply finds themselves back at the lobby.

		The measurement is logged because this line is now the only place the failure is visible. The
		handoff is fire-and-forget by design (the client's ack is the last word either side says about
		it), so if this ever fires in the wild, the Y and the speed are what say whether the car was
		dropped by nobody at the release or lost the deck a second later. ]]
	local liveAt = self._liveAt[player]
	local sinceLive = if liveAt then os.clock() - liveAt else math.huge
	--[[ ...OR the run is still inside its spawn shield, which is the same question asked of the
		client rather than of the clock. `HandoffGraceTime` is 3 seconds because that is how long a
		handoff can plausibly take; the shield is held until the client says it is driving, precisely
		because on the devices this matters for that takes longer than anyone can put a number on.
		A run that has not moved yet cannot have driven off anything, so a fall inside the shield is
		the same failed handoff — and must not be charged as a wreck. See `RaceConfig.SpawnShield`. ]]
	local ObstacleService = Shard.get("ObstacleService")
	local shielded = ObstacleService ~= nil and ObstacleService:isShielded(player)
	if shielded or sinceLive <= RaceConfig.HandoffGraceTime then
		local primary = car.PrimaryPart
		self.log:warn(string.format(
			"%s's car left the world %s after going live (y=%.1f, vy=%.1f)%s; reading that as a failed handoff, not a wreck — aborting the entry.",
			player.Name,
			if sinceLive == math.huge then "before it ever went live" else string.format("%.2fs", sinceLive),
			if primary then primary.Position.Y else 0,
			if primary then primary.AssemblyLinearVelocity.Y else 0,
			-- Which of the two answers said so, because they mean different things about the client:
			-- the clock means the handoff itself dropped it, the shield means it never got driving.
			if shielded then ", still inside its spawn shield" else ""
		))
		self:getRemoteEvent("RaceAborted"):Fire(player)
		self:_returnToSpawn(player)
		self:leaveRace(player)
		return
	end

	if riderAdrift then
		self:_returnToSpawn(player)
	end
	self.log:warn(string.format("%s's car left the world; ending the run.", player.Name))
	self:wreckRace(player, "fell")
end

--[[ Sweep live races for anything that has dropped out of the world.

	Asked of a NUMBER rather than of the geometry, because there is no geometry to ask: the road is
	client-sided, so the server owns a car with nothing underneath it (see RaceConfig.VoidDropStuds).
	`RoadService.getDeckY` is the same deck height every client builds at, and rebasing only ever
	moves the world horizontally, so it stays true for the whole race — PLUS the player's own lane
	(`RaceConfig.Lanes`), which is the one thing that makes the deck a different height for two
	players at once. Read per player inside the loop for exactly that reason: a single shared floor
	would declare every racer above the ground floor to have fallen out of the world the instant
	their car went live.

	Cars still `_pending` are deliberately not swept. They are anchored on the deck waiting for their
	driver's road to exist, so they cannot fall — and a car that has not gone live yet has no beat to
	wreck out of. ]]
function RaceService._checkForFalls(self)
	local RoadService = Shard.get("RoadService")
	local deckY = RoadService and RoadService:getDeckY()
	if not deckY then
		return
	end

	for player, car in self._cars do
		if not (self._wrecking[player] or self._pending[player]) and car.Parent then
			local floorY = deckY + self:_laneOffset(player).Y - RaceConfig.VoidDropStuds
			local primary = car.PrimaryPart
			local carY = if primary and primary.Parent then primary.Position.Y else nil

			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = humanoid and humanoid.RootPart
			local riderY = if root and root.Parent then root.Position.Y else nil

			local carGone = carY ~= nil and carY < floorY
			local riderGone = riderY ~= nil and riderY < floorY
			if carGone or riderGone then
				-- "Adrift" is about the seat, not about who crossed the line: a rider still welded in
				-- is saved by freezing the car, and only one who has come out of it needs moving.
				self:_catchFall(player, car, riderGone and not (humanoid and humanoid.SeatPart))
			end
		end
	end
end

--[[ Sweep live races for the one that has started actually driving, and end its spawn shield.

	=== WHY THE SERVER WATCHES THIS RATHER THAN BEING TOLD ====================================

	The shield (`RaceConfig.SpawnShield`) has to end on "this player can act", and the whole reason
	it exists is that we cannot know when that is: the failure it covers is Roblox's streaming pause
	sitting over a slow client's road while traffic — which is scripted, and therefore NOT paused —
	drives into a car the player cannot move. A timer is the wrong instrument for that by
	construction, and `RaceReady` is not the answer either: that ack means "I have a road and I am
	holding the car", and a client can be all of that and still be frozen under the overlay.

	Movement is the first moment the two are distinguishable, and the server can see it for free.
	The car is network-owned by its driver, so the position the server holds IS that client's
	simulation — a paused client sends no updates and the car does not move here either. No remote,
	nothing to trust, and nothing that depends on the drive shim being installed, which matters
	because a failed deploy is one of the things on the suspect list for the very same playtest.

	=== WHAT COUNTS AS DRIVING ================================================================

	Distance from where the car was handed over AND speed right now, both from
	`RaceConfig.SpawnShield`. Distance alone would accept a car nudged off a kerb; speed alone would
	accept the frame a traffic shell shoves it. Together, at 8 studs and 12 studs/s, they mean the
	car is pulling away — which is all this has to decide.

	Measured as a straight line rather than along the road on purpose: this is a THRESHOLD, not a
	distance the player is paid for (`RewardService` owns that), and a car that has moved 8 studs in
	any direction while doing 12 studs/s is driving whichever way it is pointed.

	Cars still `_pending` are skipped for the same reason the void guard skips them: they are
	anchored on the deck waiting for a road, so they cannot have moved, and asking costs a table
	lookup per sweep to learn nothing. ]]
function RaceService._checkShields(self)
	if not RaceConfig.SpawnShield.Enabled then
		return
	end
	local ObstacleService = Shard.get("ObstacleService")
	if not ObstacleService then
		return
	end
	local cfg = RaceConfig.SpawnShield

	for player, car in self._cars do
		local from = self._liveFrom[player]
		if from and not (self._wrecking[player] or self._pending[player]) and car.Parent then
			local primary = car.PrimaryPart
			if primary and primary.Parent and not primary.Anchored then
				local moved = (primary.Position - from).Magnitude
				local speed = primary.AssemblyLinearVelocity.Magnitude
				if moved >= cfg.DriveStuds and speed >= cfg.DriveSpeed then
					--[[ Cleared HERE and not in ObstacleService, so a run that ends and a player who
						is revived both get a fresh anchor from the two lines that set it rather than
						a stale one this sweep would keep measuring against. `reportDriving` is
						idempotent anyway, but a sweep that keeps calling it every 0.1s for the rest
						of the race is a sweep doing work for nothing. ]]
					self._liveFrom[player] = nil
					ObstacleService:reportDriving(player)
				end
			end
		end
	end
end

--[[ Public: the run is over. Run the wreck beat, then send them home.

	Four ways in, and the difference between them is the whole reason `cause` exists. ObstacleService
	calls it when HP hits 0 (nil, the ordinary death); StealService calls it with "badLanding" when a
	bail comes down on the tarmac instead of on a car; `_catchFall` calls it with "fell"; and
	`_onRiderLeftSeat` calls it with "thrown" when the seat emptied on its own. They are the same
	exit — cut the controls, hold the beat, fade, go home — but not the same READ, so the cause rides
	along on `RaceWrecked` and the client picks its reaction from it (a splat rather than an engine
	plume). Any cause a client handler doesn't recognise falls through to the ordinary death's
	reaction, which is why "thrown" needed no client change: it is a car coasting and smoking, which
	is exactly what it looks like.

	Cutting the driver's control GUI is what actually stops the driving — it's the stock
	Driver LocalScript's home, so tearing it down ends throttle and steering input at once.
	The client then coasts the car to a stop and smokes it (ObstacleController), which is
	also the only side that *can* do that smoothly: it owns the car's physics.

	Idempotent, and every step re-checks that this is still the same race, so a player who
	leaves or dies mid-beat doesn't get teleported into their next run. ]]
function RaceService.wreckRace(self, player: Player, cause: string?)
	local car = self._cars[player]
	if not car or self._wrecking[player] then
		return
	end
	self._wrecking[player] = true
	self:getSignal("RaceWrecked"):Fire(player, cause)

	self:_cleanupDriverControls(player, car)

	-- Each ending holds for as long as it has something to show. A whiffed bail holds longest —
	-- it's a different shot (the driver on the tarmac, camera down at road level) and it needs the
	-- ragdoll to land before the fade. A fall holds barely at all: the car is frozen out of the
	-- world with the camera under the deck, so there is nothing there to look at.
	--
	-- Resolved at the top rather than beside the timer it feeds, because the offer below is handed
	-- it too: the respawn screen goes up when the wreck beat is finished being watched, and that is
	-- the same moment, measured the same way, for both endings.
	local hold = if cause == "badLanding"
		then RaceConfig.BadLandingHoldTime
		elseif cause == "fell" then RaceConfig.VoidHoldTime
		else RaceConfig.WreckHoldTime

	--[[ IS THIS WRECK THE END OF THE RUN? Asked before anything is settled, because the answer
		decides whether it is the end or the middle.

		ONE CALL, NOT TWO, and it takes the hold with it. An earlier shape asked here and armed the
		screen further down, which left a window — every line between the two — in which a throw that
		errored would leave a run that had been told not to settle and had nobody left to settle it:
		a player parked on a wrecked car forever, with no fade and no way home. Handing the whole
		ending over in one call means `ReviveService` owns it from the instant it accepts, and its own
		safety timeout covers everything after.

		`ReviveService` is reached lazily rather than declared as a dependency: it calls back into
		`reviveRace` and `endWreckedRun` below, so declaring it here would be a cycle in the start
		graph. Absent — the feature switched off, the service failed to start — reads as "no offer",
		and every line after this behaves exactly as it did before revives existed. ]]
	--[[ THE TUTORIAL CANNOT BE LOST (`TutorialConfig.Unlosable`, 2026-10-05). Two things, both before
		the offer is asked about:

		  • A failed ATTEMPT goes back to the beat that starts it (`TutorialService.rewindAttempt`): a
		    miss on AIRBORNE is BAIL again, so the card asks for the jump, not for a steal from the seat.
		  • A tutorial run is RESCUED rather than offered: it counts as "offered" below — so the run is
		    held, not settled, exactly as an open offer holds it — and once the wreck has been watched
		    the car simply goes back on the road (`_rescueTutorial`). No screen, no price, no rung of
		    the revive ladder spent. "fell" is excluded: it is the void guard, and it goes home free.

		The beat is read off the player attribute BEFORE the rewind, which cannot change the answer:
		both ends of a rewind are race beats. ]]
	local tutorialStep = player:GetAttribute(TutorialConfig.StepAttribute)
	local rescue = TutorialConfig.Unlosable.Rescue and cause ~= "fell" and TutorialConfig.isUnlosable(tutorialStep)
	local TutorialService = Shard.get("TutorialService")
	if TutorialService and TutorialConfig.Unlosable.Enabled then
		TutorialService:rewindAttempt(player)
	end

	local ReviveService = Shard.get("ReviveService")
	local offered = rescue or (ReviveService ~= nil and ReviveService:offerRevive(player, car, cause, hold))
	local insuranceReward = Shard.get("RewardService")
	if insuranceReward then insuranceReward:markWreck(player, true) end

	--[[ Settle the run BEFORE the beat, not after it. The distance is already final — the controls
		are cut on the line above — and settling here means the client has its payout in hand well
		before `RaceReturning` raises the fade it gets shown on. A wreck keeps only
		`RewardConfig.Crash.CashFraction` of it, and earns no XP: the car is gone.

		UNLESS AN OFFER IS OPEN, in which case the run is not over yet and settling it here would be
		the bug the whole feature turns on: `settleRun` is idempotent per run, so a run paid out as a
		crash and then revived would drive its second half for nothing, and would already have been
		recorded against the map and paid its quarter. `ReviveService` settles it instead — on the
		same call that gives up on the offer, which is the first moment the run is genuinely over.

		THE MEASUREMENT IS STILL FROZEN THOUGH, and that is what `holdRun` is for. Settling used to be
		what stopped the distance moving — the sampler skips a settled run — so the sentence above
		about the distance being final was true by accident. Deferring the settlement without the hold
		would go on measuring a car that is coasting to a stop with nobody driving it, and then
		measuring it again through however long the player spends reading the offer. ]]
	local RewardService = Shard.get("RewardService")
	if RewardService then
		if offered then
			RewardService:holdRun(player, true)
		else
			RewardService:settleRun(player, false)
		end
	end
	self:getRemoteEvent("RaceWrecked"):Fire(player, cause)

	--[[ Out through the windscreen (RaceConfig.RiderThrow) — but only for the endings that have a car
		to be thrown out OF, which is the same split, drawn for the same reason, as the one
		ObstacleController calls `_silentWreck`:

		  • "badLanding" already has you on the tarmac. The body in that shot is the flight avatar and
		    the real rider is deliberately hidden inside the hidden car (`StealController._whiff`);
		    throwing them too puts a second copy of the player on screen beside their own corpse.
		  • "fell" is a car frozen tens of studs below the deck with the rider welded into it, and
		    that weld is the entire rescue — `_catchFall` freezes the car precisely BECAUSE it holds
		    the rider. Cutting it here drops them the rest of the way out of the world.
		  • "busted" is the police chase (`PoliceConfig.Cause`), and it is the one ending where the
		    car is INTACT. Nothing hit it. It is coasting to a stop with two cruisers pulling in
		    either side, which is a car being pulled over, and a driver going through the windscreen
		    of a car that was never in a crash is the beat contradicting itself in the one second
		    the player is watching it. They stay in the seat and the banner does the talking.

		Everything else — the HP death, a rider prised out of the seat — is a car that is still on
		screen coasting and smoking, and a driver who should not be sitting upright inside it. ]]
	if cause ~= "badLanding" and cause ~= "fell" and cause ~= PoliceConfig.Cause then
		self:_throwRider(player, car)
	end
	self.log:info(string.format("%s wrecked their car (%s).", player.Name, cause or "no health"))

	--[[ WITH AN OFFER OPEN, THE BEAT STOPS HERE. The wreck plays out exactly as it always did — the
		car coasts and smokes, the driver tumbles — and then `ReviveService` puts the respawn screen
		up over the top of it instead of the fade going up. Whichever way the player answers, that
		service comes back through `endWreckedRun` or `reviveRace`. ]]
	if not offered then
		task.delay(hold, function()
			-- ...and the end panel over it, for a client that draws one. See `holdEndPanel`.
			self:holdEndPanel(player, car, "wreck", cause, function()
				self:endWreckedRun(player, car)
			end)
		end)
	elseif rescue then
		task.delay(hold, function()
			self:_rescueTutorial(player, car, cause)
		end)
	end
end

--[[ The tutorial's free revive (`wreckRace`, `TutorialConfig.Unlosable.Rescue`): the same
	`reviveRace` a paid one runs, with nothing asked and nothing spent.

	A RESCUE THAT CANNOT LAND ENDS THE RUN THE ORDINARY WAY — no rider, no road frame, the race already
	gone — settled then, because `wreckRace` held it on the promise of this call. That is the same
	fallback `ReviveService._useLife` takes, and the player is no worse off than before this existed. ]]
function RaceService._rescueTutorial(self, player: Player, car: Model, cause: string?)
	if self._cars[player] ~= car or not self._wrecking[player] then
		return
	end
	if self:reviveRace(player) then
		self.log:info(string.format("%s's tutorial run was rescued after a wreck (%s).", player.Name, cause or "no health"))
		return
	end
	self.log:warn(string.format("Could not put %s's tutorial run back on the road; it ends as a wreck.", player.Name))
	local RewardService = Shard.get("RewardService")
	if RewardService then
		RewardService:settleRun(player, false)
	end
	self:holdEndPanel(player, car, "wreck", cause, function()
		self:endWreckedRun(player, car)
	end)
end

--[[ Public (and `wreckRace`, `bankRun`, `ReviveService`): the run is over and settled; hold here, on
	the scene, while the END PANEL is up, then run `proceed` (the return beat).

	THE PANEL IS THE RESULTS SCREEN NOW (`NewUIConfig.EndPanel`). It goes up over the wreck, the
	ragdoll or the truck rather than on the black after the teleport, which is what makes it light;
	so the return waits for it instead of running on its own timer. The client answers at the end of
	its countdown on its own, or sooner on a press, and `RaceConfig.EndPanel.Grace` past that is the
	fence for one that never does.

	ONLY FOR A PLAYER WHO OPTED IN (`RaceEndOptIn`). Everybody else, and any car that is no longer
	this player's race, goes straight to `proceed` with no wait, which is the ending exactly as it was.
	`proceed` keeps its own guards: it is the same closure the old timer ran. ]]
function RaceService.holdEndPanel(self, player: Player, car: Model, kind: string, cause: string?, proceed: () -> ())
	if not (self._endPanelOptIn[player] and self._cars[player] == car) then
		proceed()
		return
	end
	local hold = { car = car, proceed = proceed }
	self._endPanels[player] = hold
	local seconds = RaceConfig.EndPanel.Seconds
	self:getRemoteEvent("RaceEndPanel"):Fire(player, { kind = kind, cause = cause, seconds = seconds })
	task.delay(seconds + RaceConfig.EndPanel.Grace, function()
		self:_releaseEndPanel(player, hold, "timed out")
	end)
end

--[[ End a hold, once. The table's identity is the fence, as it is for the revive offer, so the
	answer and the timeout cannot both run the return. A hold that ended any way but the player's own
	answer also takes the panel down, which leaves the old results screen as the fallback. ]]
function RaceService._releaseEndPanel(self, player: Player, hold, why: string)
	if self._endPanels[player] ~= hold then
		return
	end
	self._endPanels[player] = nil
	if why ~= "answered" then
		self:getRemoteEvent("RaceEndPanelClosed"):Fire(player)
		self.log:info(string.format("%s's end panel closed (%s).", player.Name, why))
	end
	hold.proceed()
end

--[[ Public (and the tail of `wreckRace`): raise the fade and send them home.

	SPLIT OUT SO THE OFFER CAN OWN THE PAUSE. `wreckRace` runs it on a timer when nobody is being
	offered a revive; `ReviveService` runs it the moment the offer is declined or times out, which
	may be eight seconds later. Both arrive here with the same two facts — the run is over and this
	is the car it ended in — and from here on the two paths are one path again.

	`car` is passed rather than looked up because that is the guard: every step re-checks that the
	player is still in the race it was called about, so a player who left, died, or somehow started
	a new run inside the offer window is never teleported out of it. ]]
function RaceService.endWreckedRun(self, player: Player, car: Model)
	if self._cars[player] ~= car then
		return
	end
	self:getRemoteEvent("RaceReturning"):Fire(player)
	task.delay(RaceConfig.ReturnFadeTime, function()
		if self._cars[player] ~= car then
			return
		end
		self:_returnToSpawn(player)
		self:leaveRace(player) -- fires RaceEnd/RaceLive: road down, fade back up
	end)
end

--[[ Public (ReviveService): they paid. Put the car back on the road and let them keep driving.

	THE RUN NEVER ENDED, and everything about this function follows from that. The car is the same
	model, so the body, the paint and the tier stats a steal earned all survive; `RewardService` was
	never settled, so the distance keeps counting from where it was; `ObstacleService` still holds
	this race's seed and its set of already-consumed obstacles, so the course does not regenerate
	under the player. What is undone is only what the WRECK did.

	IN ORDER, AND THE ORDER IS THE FUNCTION:

	  1. FREEZE FIRST. The car is coasting, rolling or wedged in the barrier, and everything below
	     assumes it is still. Freezing also takes it away from the client's own `_dampWreck`, which
	     is writing velocity onto it every frame until the revive reaches it.
	  2. STAND THE RIDER UP BEFORE MOVING ANYTHING. They are a ragdoll somewhere down the road with
	     their joints cut; re-seating a limp body welds a pile of loose limbs into the cabin.
	     `_standRider` is the exact inverse of the throw and is idempotent.
	  3. SET THE CAR DOWN ON THE LANE, upright, facing down the road, a car length back from where
	     it died (`ReviveConfig.SetBackStuds` — the thing that killed you is still there).
	  4. HP LAST OF THE STATE, because `ObstacleService.clearWreck` is what re-opens the race to
	     damage, and re-opening it while the car is still being teleported would let the first frame
	     of the new run charge for the crash that ended the old one.
	  5. THEN THE CONTROLS, through the same `_deployDriving` a fresh entry goes through — occupant
	     toggle and all — because the stock vehicle scripts only deploy on a clean seat-enter and the
	     one this car had was destroyed by the throw. That fires `RaceLive` at the end of it, which
	     is what drops the screen.

	Returns whether the revive landed. A false is a life that must NOT be spent — see
	`ReviveService._spendLife`. ]]
function RaceService.reviveRace(self, player: Player): boolean
	local car = self._cars[player]
	if not (car and car.Parent and self._wrecking[player]) then
		return false
	end
	local seat = car:FindFirstChild("VehicleSeat", true)
	if not (seat and seat:IsA("VehicleSeat")) then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then
		return false -- nobody to put back in it; the run ends the ordinary way
	end

	local RoadService = Shard.get("RoadService")
	local WorldService = Shard.get("WorldService")
	local world = if WorldService then WorldService:worldOf(player) else WorldConfig.ActiveIndex
	local landing = self:_reviveCFrame(RoadService, car, world, self:_laneOffset(player))
	if not landing then
		self.log:warn(string.format("No road frame to revive %s onto; the run ends.", player.Name))
		return false
	end

	self:_setCarFrozen(car, true)
	self:_standRider(player)

	--[[ Set the PIVOT down, then lift by the bounding box so the wheels rest on the deck rather than
		the pivot doing — the same two-step `_spawnCar` places a fresh car with, and for the same
		reason: a car's pivot is not its underside and every body on the roster sits differently. ]]
	car:PivotTo(landing)
	local bbCF, bbSize = car:GetBoundingBox()
	local belowDeck = landing.Position.Y - (bbCF.Position.Y - bbSize.Y * 0.5)
	car:PivotTo(landing + Vector3.new(0, belowDeck + ReviveConfig.DropClearance, 0))

	--[[ THE CEILING IS NOT RE-DERIVED, and passing nothing here is the whole point.

		`CarStats.maxHealthOf` answers from the car's `Body` attribute, falling back to the Model's
		name — and `Body` is stamped CLIENT-side by `StealController._applyTier`, so the server never
		sees it. Asking here therefore answered for the rig this car was CLONED from, and a revive
		quietly handed a stolen car the starting beater's HP back (measured: a stolen 80 came back as
		a 97). Wrong in both directions, and the wrong one is silent: steal something tougher than
		what you set off in and the revive takes the toughness away.

		The car is already carrying the right number. `ObstacleService` stamped it at spawn and
		`StealService` re-stamped it on the steal, both through `_setMaxHealth`, and nil means "leave
		the ceiling alone" — so the fill below goes to whatever this car has actually become. ]]
	local ObstacleService = Shard.get("ObstacleService")
	if ObstacleService then
		ObstacleService:clearWreck(player)
		--[[ ...and shield the hand-back the same way an entry's is. A revive sets the car down
			stationary behind the respawn screen for `ReviveConfig.ReviveHoldTime` and then hands it
			to a client that has to pick it up again — an entry in every respect that matters here,
			except that this one is on a road that already has traffic on it, and the player has just
			PAID for it. `DriveController` fires `RaceDriving` off `RaceRevived` too, so this window
			closes on movement exactly as the entry's does. See `RaceConfig.SpawnShield`. ]]
		ObstacleService:rearmShield(player)
	end

	--[[ Start measuring again. AFTER the car has been moved, so the first sample lands on the new
		position: `RewardService.holdRun` explains why that discards the set-back rather than paying
		for it, and doing this the other way round would sample the crash site once more on the way
		past. ]]
	local RewardService = Shard.get("RewardService")
	if RewardService then
		RewardService:markWreck(player, false)
		RewardService:holdRun(player, false)
	end

	--[[ The run is live again for every guard that reads it. Cleared BEFORE the seat is touched:
		`_onRiderLeftSeat` refuses to act while `_wrecking` is set, and `_deployDriving`'s occupant
		toggle is an unseat — so clearing it after would leave the one window in the whole race where
		our own toggle is not recognised as ours. `_reseating` is what covers that window, and it is
		set inside `_deployDriving` on the line before the toggle. ]]
	self._wrecking[player] = nil

	--[[ Re-arm the weld fit-up before the seat is used again. The throw destroyed the SeatWeld and
		`_watchRiderWeld`'s connection is still live from entry, so this is belt-and-braces for the
		case where the car was re-rigged mid-race (a steal) and the watcher is watching a seat that
		no longer exists. Cheap, and the failure it prevents is the rider's head through the roof. ]]
	if self._riderConns[car] == nil then
		self:_watchRiderWeld(car, seat)
	end

	armSeat(seat, true) -- the throw shut it so it couldn't re-grab the tumbling body
	--[[ The throw normally left them seatless, so this is usually a no-op that returns on its first
		line. It is here for the revive that follows a wreck the rider was never thrown out of — a
		`Sit` onto an occupied rider is a silent no-op (`_releaseSeat`), and the cost of that here is
		a revived player standing on the road next to a car driving away. ]]
	self:_releaseSeat(humanoid)
	seat:Sit(humanoid)

	--[[ EVERY CLIENT SYSTEM THAT REACTED TO THE WRECK IS UNDONE BY THIS ONE MESSAGE, so a controller
		that listens to `RaceWrecked` and not to this is a system that stays switched off for the rest
		of the run. Both of the ones that went missing first were invisible rather than loud —
		`StealController` stopped offering the bail, and `TrafficController` stopped topping the road
		up, which between them left a player driving down an empty road unable to steal anything. If
		you add a `RaceWrecked` handler anywhere, add its inverse here in the same edit. ]]
	self:getRemoteEvent("RaceRevived"):Fire(player)
	self:getSignal("RaceRevived"):Fire(player)
	self.log:info(string.format("%s revived and is driving again.", player.Name))

	--[[ Hold the car still for a beat while the respawn screen is still over the top of it, then
		hand it back. Same shape as entry's freeze/thaw, and the same reason: the reset has to happen
		unseen, and the player has to come back to a car sitting still rather than to one already
		rolling. `_deployDriving` fires `RaceLive` when it is done, which drops the screen. ]]
	task.delay(ReviveConfig.ReviveHoldTime, function()
		if self._cars[player] ~= car or not car.Parent then
			return
		end
		-- A revive hands the car over exactly the way entry does, so it gets the same grace: a car
		-- that falls out of the world seconds after being set back down failed the handoff, it was
		-- not driven off anything. See `_catchFall`.
		self._liveAt[player] = os.clock()
		-- ...and the same anchor for the shield re-armed above, off the car where it has just been
		-- set down. See `_checkShields`.
		self._liveFrom[player] = if car.PrimaryPart then car.PrimaryPart.Position else nil

		self:_setCarFrozen(car, false)
		if car.PrimaryPart then
			pcall(function()
				car.PrimaryPart:SetNetworkOwner(player)
			end)
		end
		self:_deployDriving(car, player)
		self:_checkOwnerAfterRevive(player, car)
	end)
	return true
end

--[[ DID THE HAND-BACK LAND? (2026-10-21, a phone player busted in the tutorial chase: "everytime I
	did it kept teleporting me back when I drive ... then my car flung out the map".) Every
	`SetNetworkOwner` above is in a pcall, and a car the server still owns is exactly that report: the
	client's rebase (`RoadController._shiftWorld`) moves the car, the server's copy pulls it back, and
	the road and the car end up a rebase apart. Unconfirmed as the cause, so this LOGS it when it finds
	it, and gives the car back. A few checks, because `_deployDriving`'s occupant toggle runs the stock
	`onExitSeat`, which hands ownership to the engine for a moment. ]]
function RaceService._checkOwnerAfterRevive(self, player: Player, car: Model)
	task.spawn(function()
		for _ = 1, 3 do
			task.wait(1.5)
			local primary = car.PrimaryPart
			if self._cars[player] ~= car or self._wrecking[player] or not (primary and primary.Parent) then
				return
			end
			local ok, owner = pcall(function()
				return primary:GetNetworkOwner()
			end)
			if ok and owner ~= player then
				self.log:warn(string.format("%s's revived car was owned by %s, not them; giving it back.", player.Name, tostring(owner)))
				local given, err = pcall(function()
					primary:SetNetworkOwner(player)
				end)
				if not given then
					self.log:warn("Could not give the revived car back: " .. tostring(err))
				end
			elseif not ok then
				self.log:warn(string.format("Could not read the owner of %s's revived car: %s", player.Name, tostring(owner)))
			end
		end
	end)
end

--[[ Where a revived car is set down: the lane it should have been in, at the point it died, minus
	a car length or so of run-up (`ReviveConfig.SetBackStuds`).

	BUILT FROM THE ROAD'S OWN AXES RATHER THAN FROM THE CAR'S. The car may be upside down in the
	barrier by the time this is asked, so nothing about its current orientation is worth keeping —
	only its forward COORDINATE is, and that is one dot product. Cross-axis position comes from the
	world's drive centre and height from the deck, which is exactly how `RoadService.getSpawnCFrame`
	places a fresh car; the only difference is that the forward term is measured instead of reset,
	and that difference is the whole feature.

	`laneOffset` is the player's storey, added for the same reason the fresh spawn adds it: the road
	this car is being set back down on was laid there, and the deck the other two terms describe is
	the shared one at the origin. Measured terms are immune to it — the forward coordinate is read
	off the car, which is already up there, and the cross axis a lane never touches. ]]
function RaceService._reviveCFrame(self, RoadService, car: Model, world: number, laneOffset: Vector3): CFrame?
	local primary = car.PrimaryPart
	if not (RoadService and primary) then
		return nil
	end
	local forward, cross = RoadService:getForward(), RoadService:getCross()
	local deckY, driveCenter = RoadService:getDeckY(), RoadService:getDriveCenter(world)
	if not (forward and cross and deckY and driveCenter) then
		return nil
	end

	local along = RoadService:along(primary.Position) - ReviveConfig.SetBackStuds
	local position = forward * along + cross * driveCenter + Vector3.yAxis * deckY + laneOffset
	return CFrame.lookAt(position, position + forward)
end

--[[ Public: the run is BANKED — they drove into a getaway truck and left with the car (GetawayService).

	The mirror image of `wreckRace`, and deliberately built out of the same four beats, because the
	only thing that differs is why: cut the controls, hold, fade, go home. Reusing them is what stops
	a successful run and a failed one exiting through two subtly different paths — the second of
	which would be the one nobody tests.

	Cutting the driver's control GUI is the load-bearing step and it happens FIRST, not after the
	hold: the client has already frozen the car onto the bay floor, and leaving throttle and steering
	live through the beat would let a player drive out of their own getaway. The client spends the
	hold shutting the truck up behind them.

	Returns whether the bank was taken, so the caller only stamps its cooldown (and only prints) for
	a run that actually ended. `self._wrecking` is the shared "this run is already ending" guard, so
	a bank and a wreck in the same frame resolve to whichever arrived first rather than to both. ]]
function RaceService.bankRun(self, player: Player, tier: number?, mutation: string?): boolean
	local car = self._cars[player]
	if not car or self._wrecking[player] then
		return false
	end
	self._wrecking[player] = true

	self:_cleanupDriverControls(player, car)
	--[[ Cut the engine. A bank is the ONE exit that leaves the driver in the seat — they ride the
		truck out — so the vehicle's own `onExitSeat`, the only thing that ever stops the engine
		effects, never fires. Left alone the loop runs on for the whole `BankHoldTime` beat over a
		car that is frozen to the bay floor, and it does not merely persist: the stock crossfade
		falls to the `Idle` layer as the RPM decays, and Idle is authored at Volume 3 against the
		driving layers' 0.4, so a parked car swells to louder than it was at speed. ]]
	Vehicle.silenceEngine(car)
	-- The same settlement the wreck path runs, and the same place in the beat — but banked, so the
	-- distance pays in full. The XP half is awarded a step later by GetawayService, which is the
	-- first point anything knows WHICH car got away (see RewardService.awardCarXp).
	--[[ `mutation` is passed straight through, unexamined. It has ALREADY been sanitised and bounded
		against the weather schedule by `GetawayService`, which is the only caller — this service is
		the one that knows a run is ending and knows nothing whatever about the weather, and putting
		a second copy of that check here would be two bounds that have to agree forever.

		nil on every other path into `settleRun` (a wreck, a disconnect, `leaveRace`), which is
		correct rather than merely convenient: those endings award no car, so there is nothing for a
		mutation to be on. ]]
	local RewardService = Shard.get("RewardService")
	if RewardService then
		RewardService:settleRun(player, true, mutation)
	end
	self.log:info(string.format(
		"%s banked a run (%s%s).",
		player.Name,
		if tier then "Tier " .. tier else "unknown tier",
		if mutation then ", " .. mutation else ""
	))

	task.delay(RaceConfig.BankHoldTime, function()
		if self._cars[player] ~= car then
			return
		end
		-- The end panel goes up over the shut truck first, for a client that draws one.
		self:holdEndPanel(player, car, "bank", nil, function()
			if self._cars[player] ~= car then
				return
			end
			self:getRemoteEvent("RaceReturning"):Fire(player)
			task.delay(RaceConfig.ReturnFadeTime, function()
				if self._cars[player] ~= car then
					return
				end
				self:_returnToSpawn(player)
				self:leaveRace(player) -- fires RaceEnd/RaceLive: road down, truck down, fade back up
			end)
		end)
	end)
	return true
end

--[[ Public (AdminService): end this run on purpose, right now, and do not answer until the player
	is standing back in their lobby.

	IT IS THE BANK'S ENDING WITH NOTHING BANKED. Nothing hit them and there is no car to smoke, so
	this is not a wreck and it deliberately does not go anywhere near `wreckRace`: no `RaceWrecked`,
	no throw through the windscreen, no revive offer over the top of it. What it runs is the tail
	both real endings already share — raise the fade, wait it out, send them home, tear the race
	down — so this is the tail the two real endings already share, reached without either of them,
	rather than a third ending written out again.

	WHAT THE RUN EARNED SETTLES AS A CRASH, through the `RewardService.endRun` inside `leaveRace`
	that catches every run reaching the end unsettled. That is the honest answer: the car was taken
	away mid-drive, so paying the full distance would be paying for a run nobody finished.

	IT YIELDS, AND THAT IS THE POINT OF IT EXISTING rather than the caller stringing `_returnToSpawn`
	and `leaveRace` together for itself. The return beat anchors the rider, streams their plot in
	around them and teleports them onto it, all in a spawned thread — so anything that seats that
	player in a new car while it is still in flight gets the teleport home landing on them mid-race.
	The Obstacles tab's "end this run and drive the next hazard" is exactly that, so the wait lives
	here beside the beat rather than in the panel as a guessed duration. `onHome` is what the beat
	answers with; the cap below is `_holdInPlace`'s own fail-safe, which is the outer bound on how
	long the beat can take before it is a bug in its own right.

	`_wrecking` is claimed for the reason both real exits claim it: an obstacle hit landing in the
	same frame as the press would otherwise run a whole wreck beat over a run that is already being
	torn down. `leaveRace` clears it. A run that was ALREADY ending — a wreck mid-beat, a revive
	offer still open — is ended anyway rather than refused, because "stop what you are doing and
	drive this instead" is the request, and `leaveRace` closes the offer on its way past.

	Answers whether it ended a run. False means there was nothing to end. ]]
function RaceService.abandonRun(self, player: Player): boolean
	local car = self._cars[player] or self._pending[player]
	if not car then
		return false
	end
	self._wrecking[player] = true
	--- The same first move `wreckRace` makes, and for the same reason: tearing the driver's control
	--- GUI down is what actually stops the car being driven, so it happens before the fade rather
	--- than behind it.
	self:_cleanupDriverControls(player, car)
	self:getRemoteEvent("RaceReturning"):Fire(player)

	task.wait(RaceConfig.ReturnFadeTime)
	--[[ Somebody else finished the run inside the fade — a wreck beat that was already in flight, a
		disconnect, a rider who died in the seat. Their teardown owns it from here, and running a
		second one over the top would send a player home from a race they are no longer in. ]]
	if self._cars[player] ~= car and self._pending[player] ~= car then
		return false
	end

	local home = false
	self:_returnToSpawn(player, function()
		home = true
	end)
	self:leaveRace(player) -- fires RaceEnd/RaceLive: road down, fade back up

	local deadline = os.clock() + HOLD_FAILSAFE_TIMEOUT
	while not home do
		if os.clock() >= deadline then
			--- Past the beat's own fail-safe, so the rider has been unfrozen by it whatever else
			--- went wrong. Said out loud because the caller is about to start a run on top of this.
			self.log:warn(string.format(
				"%s's return beat never reported them home; ending the run anyway.", player.Name))
			break
		end
		RunService.Heartbeat:Wait()
	end
	return true
end

-- Public: tear down a player's race — tell the client, remove the car.
function RaceService.leaveRace(self, player: Player)
	local car = self._cars[player]
	if not car and not self._pending[player] then
		return
	end
	car = car or self._pending[player]
	self._cars[player] = nil
	self._pending[player] = nil
	self._wrecking[player] = nil
	self._liveAt[player] = nil
	self._liveFrom[player] = nil
	self._frozen[car] = nil
	-- Hand the storey back for the next racer. Here rather than only in the return beat, for the
	-- same reason `_standRider` is: this is the one function every way out of a race goes through.
	self:_releaseLane(player)

	local ObstacleService = Shard.get("ObstacleService")
	if ObstacleService then
		ObstacleService:endRace(player)
	end

	--[[ Reset the revive ladder, so the next run starts at the cheapest rung again — and close any
		offer still standing. That second half is the backstop for every way out of a race that does
		NOT come through the offer itself: a player who died in the seat while the respawn screen was
		up, an admin ending a run, a disconnect. Without it the screen has nobody left to answer to.
		Idempotent, and a no-op for the overwhelming majority of runs, which never wrecked at all. ]]
	local ReviveService = Shard.get("ReviveService")
	if ReviveService then
		ReviveService:endRun(player)
	end
	-- ...and an end panel still standing: the run it was holding is over, so it comes down.
	local endPanel = self._endPanels[player]
	if endPanel then
		self:_releaseEndPanel(player, endPanel, "the run ended")
	end

	--[[ Stop measuring, and pay for anything that got here without going through either exit — a
		rider who died in the seat, a player who left mid-run, an entry that fell over before the car
		went live. Those settle as crashes, so no way out of a race skips the payout. A run already
		settled by `wreckRace` or `bankRun` is untouched. ]]
	local RewardService = Shard.get("RewardService")
	if RewardService then
		RewardService:endRun(player)
	end

	local riderConn = self._riderConns[car]
	if riderConn then
		riderConn:Disconnect()
		self._riderConns[car] = nil
	end
	local seatConn = self._seatConns[player]
	if seatConn then
		seatConn:Disconnect()
		self._seatConns[player] = nil
	end
	self._reseating[player] = nil
	--[[ Hand streaming back to the character, unconditionally. Nothing in the race flow moves the
		focus any more (see `_onRaceReady`) — but a session that was live across the change, or any
		future code that reaches for it, would otherwise leave a player walking the map with their
		streaming pinned to wherever it was parked, and this is the one function every way out of a
		race goes through. Writing it is free; a stuck focus costs the rest of the session. ]]
	pcall(function()
		player.ReplicationFocus = nil
	end)
	self:_setRiderHidden(player, false)
	--[[ The backstop for the ragdoll, and the reason it is here rather than only in `_returnToSpawn`:
		this function is the ONE thing every way out of a race goes through, including the ways that
		skip the return beat entirely (a player who disconnected mid-tumble, a humanoid that died
		while limp, an entry that fell over). A player left ragdolled past the end of their run has no
		controls for the rest of the session — the single worst outcome this feature can have — so it
		is unwound from the path that cannot be missed. Idempotent; the return beat usually got here
		first. ]]
	self:_standRider(player)

	-- Both of these are the vehicle's onExitSeat cleanup, run by us: destroying the car below
	-- never fires it, which otherwise leaves the control GUI in PlayerGui and the rider's legs
	-- and accessories invisible. Also drops the fade in case entry was still mid-flight.
	self:_restoreRiderAvatar(player)
	self:_cleanupDriverControls(player, car)
	self:getRemoteEvent("RaceLive"):Fire(player)
	self:getRemoteEvent("RaceEnd"):Fire(player)
	if car and car.Parent then
		car:Destroy()
	end
	--- Last, beside the two remotes and for the same reason they are here: by now every part of this
	--- teardown has run, so a subscriber reading the player's state sees the run already ended.
	self:getSignal("RaceLeft"):Fire(player)
end

RaceService:withLifecycle({
	init = function(self)
		self._cars = {} -- [Player] = Model  (live cars)
		self._pending = {} -- [Player] = Model  (spawned, awaiting client road)
		-- [Player] = true. "This run is already ending" — set by BOTH exits (wreckRace and bankRun)
		-- and checked by both, so a bank and a wreck landing in the same frame resolve to whichever
		-- arrived first instead of running two return beats over one car.
		self._wrecking = {}
		self._endPanelOptIn = {} -- [Player] = true once their client says it draws the end panel
		self._endPanels = {} -- [Player] = { car, proceed } while an end panel holds their return
		self._frozen = {} -- [Model] = { [BasePart] = wasAnchored }
		-- [Player] = os.clock() at the moment their car was last handed to them (entry or revive).
		-- Only the void guard reads it, and only to tell a failed handoff from a wreck (`_catchFall`).
		self._liveAt = {}
		--[[ [Player] = the car's position at that same moment. `_checkShields` measures "have they
			actually started driving yet" against it, which is what ends the spawn shield
			(`RaceConfig.SpawnShield`). Cleared the moment the answer is yes, so the sweep stops
			asking, and again on every way out of a race beside `_liveAt`. ]]
		self._liveFrom = {}
		self._riderConns = {} -- [Model] = seat.ChildAdded connection (rider weld fit-up)
		self._seatConns = {} -- [Player] = humanoid SeatPart connection (came out of the car)
		self._hidden = {} -- [Player] = { [BasePart|Decal] = originalTransparency }
		self._entryCooldowns = {} -- [Player] = os.clock() before which RequestEnterRace is ignored
		--- [Player] = true while `_returnToSpawn` still owns their character — it is holding them
		--- still, streaming the lobby in, or about to teleport them onto it. `_onEnterRequest` waits
		--- this out rather than starting a race the trip home is going to interrupt.
		self._returning = {}
		--- [Player] = true while one entry request is already holding for the beat above. Two of
		--- them would come out of the wait together and start two races; see `_onEnterRequest`.
		self._waitingToEnter = {}
		--[[ Which storey each live race is being driven on, and who holds it (RaceConfig.Lanes).
			Two tables because the question is asked both ways: the void guard and the revive ask
			"where is this player racing", and `_claimLane` asks "is this slot free". A slot with no
			owner is free; an OVERFLOW racer appears in `_lanes` at 0 without owning it, which is
			what stops them evicting the ground floor's real occupant when they leave. ]]
		self._lanes = {} -- [Player] = slot (0-based)
		self._laneOwners = {} -- [slot] = Player
		-- [Player] = { character, humanoid, flags, restore, seat } while they are a body on the road.
		-- Written by `_throwRider`, unwound by `_standRider`, and keyed on the character inside so a
		-- respawn can't leave a stale entry refusing the next throw.
		self._ragdolls = {}
		-- [Player] = true while `_deployDriving` is deliberately toggling them out of the seat and
		-- back in. The seat watcher's "was this unseat ours?" flag; see `_onRiderLeftSeat`.
		self._reseating = {}
		-- One stream for the throw's tumble, so a run is reproducible from a seed if it ever needs
		-- to be, and so the spin never has to reach for a fresh Random per wreck.
		self._rng = Random.new()
	end,

	start = function(self)
		--[[ Loud at BOOT, not at the moment it bites. `_claimLane` already warns when the stack is
			full, but by then a player is on somebody else's storey and the symptom — being flung on
			a steal — is a long way from the cause. This is the same shape as PlotService's
			MaxPlayers warning and for the same reason: the fix is a number in Game Settings or in
			`RaceConfig.Lanes`, not code either service can write.

			`> Count` rather than `>= Count`: slots are 0..Count-1, so exactly `Count` players is
			the last arrangement that still gives everybody their own storey. ]]
		if RaceConfig.Lanes.Enabled and Players.MaxPlayers > RaceConfig.Lanes.Count then
			self.log:warn(
				string.format(
					"MaxPlayers is %d but there are only %d race storeys — %d racers could share the ground floor "
						.. "and collide (see RaceConfig.Lanes). Either set MaxPlayers to %d, or raise Lanes.Count to %d "
						.. "and check the altitude that puts the top storey at (%d studs).",
					Players.MaxPlayers,
					RaceConfig.Lanes.Count,
					Players.MaxPlayers - RaceConfig.Lanes.Count,
					RaceConfig.Lanes.Count,
					Players.MaxPlayers,
					Players.MaxPlayers * RaceConfig.Lanes.Spacing
				)
			)
		end

		local carsFolder = workspace:FindFirstChild(RaceConfig.RaceCarsFolderName)
		if not carsFolder then
			carsFolder = Instance.new("Folder")
			carsFolder.Name = RaceConfig.RaceCarsFolderName
			carsFolder.Parent = workspace
		end
		self._carsFolder = carsFolder

		Observers.observeTag(RaceConfig.EnterRaceTag, function(part)
			if not part:IsA("BasePart") then
				return nil
			end
			return self:_bindEntryTrigger(part)
		end, { workspace })

		Players.PlayerRemoving:Connect(function(player)
			self:leaveRace(player) -- also stands a thrown rider back up and drops their connections
			-- ...but `leaveRace` returns early for a player who wasn't racing, and an entry that
			-- fell over between claiming a lane and spawning a car is exactly that player. The one
			-- thing that must not outlive a disconnect is a storey held by somebody who has left.
			self:_releaseLane(player)
			self._entryCooldowns[player] = nil
			--- ...and the return beat's two flags. The beat itself checks the character before it
			--- moves anything, so it comes apart on its own; these are the tables it leaves behind,
			--- and a stale `_returning` would make a returning player's next session wait one beat
			--- out before its first race.
			self._returning[player] = nil
			self._waitingToEnter[player] = nil
			self._endPanelOptIn[player] = nil
			self._endPanels[player] = nil
			self._ragdolls[player] = nil
			self._reseating[player] = nil
			local seatConn = self._seatConns[player]
			if seatConn then
				seatConn:Disconnect()
				self._seatConns[player] = nil
			end
		end)

		-- The void guard. Throttled off Heartbeat rather than given its own loop so it can never
		-- outlive the service, and skipped entirely while nobody is racing.
		local sinceCheck = 0
		RunService.Heartbeat:Connect(function(dt)
			sinceCheck += dt
			if sinceCheck < RaceConfig.VoidCheckInterval then
				return
			end
			sinceCheck = 0
			if next(self._cars) then
				self:_checkForFalls()
				-- Same sweep, same reason: both questions are asked of a live car's own position,
				-- both are cheap, and neither is worth a second loop that could outlive this one.
				self:_checkShields()
			end
		end)
	end,
})

return RaceService
