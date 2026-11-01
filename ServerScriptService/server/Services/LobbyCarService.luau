--[[
	LobbyCarService  (server)
	-------------------------
	"Put my Lamborghini on the street next to me so I can drive it around." The whole feature is
	three verbs — spawn, despawn, and clean up after yourself — and the interesting part of all
	three is what this service deliberately does NOT do.

	=== IT DOES NOT DRIVE THE CAR ==============================================================

	Every model under `Workspace.CarSystem` is a complete CarBones rig, not a body: chassis, seat,
	`Scripts.Vehicle`, `Scripts.Driver`, the proximity-prompt GUI, the lot. So spawning is a clone
	and a placement, and from the moment it is parented the car belongs to the stock system — it
	raises its own prompt, deploys its own controls when someone sits, and owns E for exit.

	That is the difference between this and `RaceService`, and it is worth being explicit about
	because the two look superficially similar. RaceService has to fight the stock system (freeze
	the car, seat the player by hand, re-run the seat-enter afterwards, unbind the leaked controls
	on the way out) for one reason only: THE ROAD IS CLIENT-SIDED, so the car cannot go live until
	the driver's local road exists. There is no local road in the lobby. The ground is real, the
	server owns it, and every one of those workarounds is unnecessary here — so none of them is
	copied. If this file ever grows a `_setCarFrozen`, something has gone wrong upstream.

	Network ownership is left alone for the same reason. A VehicleSeat hands ownership to whoever
	sits in it, which is the correct answer and arrives without being asked.

	=== IT DOES NOT DECIDE WHO OWNS WHAT =======================================================

	Ownership is `GarageService`'s, read through `_owns` rather than off the player attribute the UI
	reads — the attribute is a broadcast of the profile, and validating a request against your own
	broadcast is validating it against something the client watched you send. The profile is the
	only copy that was never on a client.

	=== WHAT IT OWNS ===========================================================================

	The lifetime. A spawned car is destroyed when its owner asks, spawns a different one, enters a
	race, dies, or leaves — and `_despawn` is the single path for all five, so there is no state
	where the world has a car in it and `LobbyCar` says otherwise. The reverse (the attribute says
	a car is out and it has been destroyed by something else) is covered by `_carOf` re-checking
	`IsDescendantOf(workspace)` rather than trusting the table.

	No Instances cross the remotes and no car is ever handed to a client — StreamingEnabled means
	`Workspace.CarSystem` is not reliably there client-side anyway, which is exactly why the clone
	is made here and not there.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local CarCollision = require(ReplicatedStorage.shared.Modules.CarCollision)
local CarDoorRig = require(ReplicatedStorage.shared.Modules.CarDoorRig)
local CarDoors = require(ReplicatedStorage.shared.Modules.CarDoors)
local CarMutation = require(ReplicatedStorage.shared.Modules.CarMutation)
local CarPaint = require(ReplicatedStorage.shared.Modules.CarPaint)
local CarPlate = require(ReplicatedStorage.shared.Modules.CarPlate)
local CarRoster = require(ReplicatedStorage.shared.Modules.CarRoster)
--- The race's own stat stamp, so a lobby car drives like that car (`LobbyCarConfig.Handling.Stats`).
local CarStats = require(ReplicatedStorage.shared.Modules.CarStats)
local Vehicle = require(ReplicatedStorage.shared.Modules.Vehicle)
local VehiclePromptGui = require(ReplicatedStorage.shared.Modules.VehiclePromptGui)

local LobbyCarService = Shard.new("LobbyCarService"):withDependencies({ "GarageService", "RaceService" })

LobbyCarService:withSignals({
	"CarSpawned", -- (player: Player, body: string, car: Model)
	"CarDespawned", -- (player: Player, body: string)

	--[[ (player: Player, key: string?) — the car this player is HOLDING, waiting to drop, has
		changed. `CarryConfig.Toy` has what that means and why it is not the garage's carry.

		IT EXISTS FOR `CarryService`, which builds the model in the hands. A signal rather than a
		call into that service, for the reason `GarageService.CarryChanged` is one: this service has
		no business knowing whether anything draws a car, and a server with `CarryConfig` switched
		off still hands out toys and drops them correctly. ]]
	"ToyChanged",
})

LobbyCarService:withRemoteEvents({
	{
		--[[ client -> server (carKey|nil): put this owned car in the lobby. `nil` means "put away
			whatever I have out", and so does passing the key already standing there — the SPAWN
			CARS list is both the spawner and the despawner (LobbyCarConfig note 2), so the toggle
			has to live on this side of the wire where the truth about what is out lives. ]]
		RequestSpawnLobbyCar = function(player: Player, key: unknown)
			LobbyCarService:_onSpawnRequest(player, key)
		end,

		--[[ client -> server (nothing): drop the car I am holding, here.

			NO ARGUMENTS ON PURPOSE, and `LobbyCarConfig.Toy.RemoteName` has the argument in full.
			The server knows which car it put in their hands and where the player is standing, so
			the only thing the client is trusted with is the word "now". ]]
		RequestDropLobbyCar = function(player: Player)
			LobbyCarService:_onDropRequest(player)
		end,

		--[[ client -> server (carKey): the car picked on the SPAWN screen a pad opened. Honoured only
			against a pad this player pressed moments ago and is still standing by
			(`LobbyCarConfig.Pad` "YOU PICK THE CAR"). ]]
		RequestPadSpawn = function(player: Player, key: unknown)
			LobbyCarService:_onPadPick(player, key)
		end,

		--[[ client -> server (on: boolean): my lobby car started / stopped drifting, so everyone else
			draws its smoke, sound and skid marks (`LobbyCarConfig.Handling.Drift.Attribute`).
			TRUSTED: nothing but the word. Bounded: only for the car this server put out for this player,
			and only while they are in its driver's seat. ACCEPTED GAP: a client can say "drifting" while
			driving straight, which buys smoke and a sound on its own car and nothing else. ]]
		ReportLobbyDrift = function(player: Player, on: unknown)
			LobbyCarService:_onDriftReport(player, on)
		end,
	},
	--- server -> client (nothing): a pad was pressed; put the SPAWN screen up (`StartCarController`).
	"OpenCarPadPicker",
})

--[[ What a trusted caller can ask for on top of "put this car out".

	BOTH FIELDS EXIST FOR ONE CALLER and neither is reachable from a client: `RequestSpawnLobbyCar`
	carries a key and nothing else, so a player can only ever ask for the ordinary spawn. The market
	is the trusted caller (`CarDealService._handover`), and what it needs that a screen does not is a
	place to put the car and a person to put in it. ]]
type SpawnOptions = {
	--- Where the wheels go: a frame on the ground, LookVector the way the car's nose should point.
	--- nil rings the candidates around the player, which is what every other caller means.
	ground: CFrame?,
	--- Put the owner in the driver's seat once it is standing there.
	seat: boolean?,
	--- Seconds to let the rig settle before sitting them. See `_seatDriver`.
	seatDelay: number?,
	--- Skip the ownership check: the collector's free starter car, or a capture the garage sold
	--- because the inventory was full. Server callers only — the remote never carries options.
	free: boolean?,
}

-- === The roster =============================================================

--[[ The pristine roster model for a body name. Never modified — always cloned.

	`Workspace.CarSystem` is the same folder `GarageService._buildDisplayCar` clones the dress out
	of and `RaceService._getTemplate` takes the race car from; there is one roster in this game and
	this is it. A name that is not in it returns nil and the request is refused, which is the only
	honest answer: the collection is stored as strings, and a body renamed in the place file has no
	car to be. ]]
function LobbyCarService._roster(self, body: string): Model?
	--- `CarRoster` rather than Workspace: the folder is relocated to ServerStorage as the server
	--- boots, which is long before any lobby car is spawned.
	return CarRoster.car(body, GarageConfig.Display.RosterFolderName)
end

-- === Placement ==============================================================

--[[ The box a car actually occupies, returned as the same pair `Model:GetBoundingBox` returns: the
	centre as an offset in the car's own pivot frame, and the size.

	AND FOR A HEALTHY RIG IT IS THE SAME ANSWER. It is measured by hand rather than asked for because
	on this roster not every part of a car is anywhere near the car. Four of the 65 rigs (Golf GTI,
	Senna, F40, Charger) carry chassis internals — a steering rack, a pair of torsion bars, the front
	knuckle arms — sitting some 796 studs BELOW the car in the place file, left behind by the pack
	import. They are invisible, they are held by constraints rather than welds, and nothing in the
	world shows it: `GetBoundingBox` on a Golf GTI reports 111 x 802 x 113 studs.

	Both halves of the placement are wrecked by a box like that, and neither one fails loudly:

	  • the clearance test is handed an 800-stud-tall volume, which overlaps most of the lobby, so
	    EVERY candidate reads as blocked and the search falls straight through to its fallback — the
	    car-versus-car check this section exists for never gets to run at all; and
	  • the centre of that box sits ~400 studs below the car, so standing the box on the ground
	    stands the car itself ~800 studs above it.

	`MeasureRadius` is what separates the car from the wreckage, and the gap it has to straddle is
	not a close thing: measured across all 65 rigs, the furthest part that legitimately belongs to a
	car is 11.93 studs from its pivot (`plate_face` on NewSports37), and the drift is 796.

	THE RIGS THEMSELVES ARE THE REAL FIX and those four have been repaired in the place file. This
	stays because a re-imported pack can drift again, and the failure it causes here is silent. ]]
function LobbyCarService._measure(self, car: Model): (CFrame, Vector3)
	local pivot = car:GetPivot()
	local radius = LobbyCarConfig.Placement.MeasureRadius
	local min: Vector3?, max: Vector3? = nil, nil

	for _, part in car:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local rel = pivot:ToObjectSpace(part.CFrame)
		if rel.Position.Magnitude > radius then
			continue
		end

		--[[ How far this part reaches along each of the PIVOT'S axes. A part turned at an angle
			reaches further than half its own size, so every axis takes a contribution from all
			three of the part's — the same arithmetic `GetBoundingBox` does, which is why an
			undrifted car measures out identically here. ]]
		local half = part.Size * 0.5
		local reach = Vector3.new(
			math.abs(rel.RightVector.X) * half.X
				+ math.abs(rel.UpVector.X) * half.Y
				+ math.abs(rel.LookVector.X) * half.Z,
			math.abs(rel.RightVector.Y) * half.X
				+ math.abs(rel.UpVector.Y) * half.Y
				+ math.abs(rel.LookVector.Y) * half.Z,
			math.abs(rel.RightVector.Z) * half.X
				+ math.abs(rel.UpVector.Z) * half.Y
				+ math.abs(rel.LookVector.Z) * half.Z
		)
		min = if min then min:Min(rel.Position - reach) else rel.Position - reach
		max = if max then max:Max(rel.Position + reach) else rel.Position + reach
	end

	if not (min and max) then
		-- Nothing measurable, which a roster rig cannot be. The honest answer is a point at the
		-- pivot rather than a made-up car-sized box that would then be tested against the world.
		return CFrame.identity, Vector3.zero
	end
	return CFrame.new((min + max) * 0.5), max - min
end

--[[ Everything a placement query must not see — and the one argument that separates its two callers.

	The characters are out of both. A car placed where somebody is standing pushes them out of the
	way, and a crowd gathered around you must not be able to refuse you your own car. So are the race
	cars, for a harder reason: they are parked on a client-sided road that does not exist on the
	server, so on this side they are 20-stud boxes floating in space over the lobby, and a spot the
	server thinks one of them is blocking is a spot nothing is actually standing in.

	`alsoIgnore` IS THE WHOLE FIX FOR CARS SPAWNING INTO EACH OTHER. The GROUND probe passes the
	entire lobby-car folder, because a car ROOF is not ground and a spot beside your own car must not
	read as solid at bonnet height. The CLEARANCE test passes only the car this player is REPLACING,
	because every other car standing out there is exactly what it is looking for. Handing the
	clearance test the whole folder — which is what it used to be handed, for the ground probe's
	reason — is what let two cars be placed in one volume and left the solver to fire them apart. ]]
function LobbyCarService._ignoreList(self, alsoIgnore: Instance?): { Instance }
	local ignore = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local raceCars = workspace:FindFirstChild(RaceConfig.RaceCarsFolderName)
	if raceCars then
		table.insert(ignore, raceCars)
	end
	if alsoIgnore then
		table.insert(ignore, alsoIgnore)
	end
	return ignore
end

--- Ground under a candidate spot, or nil if there isn't any within reach.
function LobbyCarService._groundAt(self, position: Vector3, ignore: { Instance }): Vector3?
	local place = LobbyCarConfig.Placement

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true

	local from = position + Vector3.new(0, place.ProbeUp, 0)
	local hit = workspace:Raycast(from, Vector3.new(0, -(place.ProbeUp + place.ProbeDown), 0), params)
	return if hit then hit.Position else nil
end

--[[ What is standing in the volume a car would occupy at `pivot`: `"car"`, `"scenery"`, or nil for
	nothing at all.

	TWO ANSWERS RATHER THAN A BOOLEAN, because the two are not equally bad and the caller has to tell
	them apart once it runs out of clear spots. A car left touching a hedge is shoved out of it by
	its own suspension inside a second; a car left sharing a volume with another player's car is two
	400-mass assemblies interpenetrating, and the solver's answer to that is to fire both of them
	into the sky. See `_placement`'s fallback.

	NO `MaxParts` ON THE QUERY, and that is the one thing to not "optimise" back in. Capping it at 1
	looks right — the loop has its answer the moment it sees a car — but the cap is applied by the
	QUERY, not by the loop: it returns one arbitrary part out of everything overlapping, and if that
	one happens to be non-colliding scenery the loop reports a clear spot and never learns about the
	wall (or the car) next to it. That is not hypothetical; it is what put the first test car inside
	a building on Plot 1, where the solver launched it forty studs into the air. ]]
function LobbyCarService._blockedBy(self, pivot: CFrame, size: Vector3, ignore: { Instance }): string?
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local parts = workspace:GetPartBoundsInBox(pivot, size + LobbyCarConfig.Placement.ClearancePad, params)
	local blocked: string? = nil
	for _, part in parts do
		-- Non-colliding scenery — signage, the plot glass, decals on posts — is not an obstruction.
		-- Only something the car would actually hit disqualifies a spot.
		if not part.CanCollide then
			continue
		end
		if self._folder and part:IsDescendantOf(self._folder) then
			-- A car. Nothing outranks it, so there is no reason to keep looking.
			return "car"
		end
		blocked = "scenery"
	end
	return blocked
end

--[[ Where the CENTRE of a `size` car should go for this player, nose pointed back at them.

	Tries the candidates in `LobbyCarConfig.Placement` in order and takes the first with ground under
	it AND nothing in the way. FACING THE PLAYER rather than facing away, because the point of the
	feature is looking at the thing: the car arrives showing its front, which is the side every one
	of these bodies was modelled to be seen from.

	FALLING BACK MAY PARK YOU BADLY AND MAY NEVER PARK YOU IN A CAR. When nothing is clear it takes
	the first candidate that was blocked only by SCENERY — a car in a hedge is one the suspension
	shoves clear in a second, and a request that silently does nothing reads as a broken button — but
	a spot with another player's car in it is not a fallback at any price, for `_blockedBy`'s reason.
	Only when every one of the 24 candidates is either off the map or occupied does this return nil
	and the caller refuse the request: standing in the middle of two dozen parked cars, doing nothing
	is the honest answer and the alternative is a car in the sky. ]]
function LobbyCarService._placement(self, player: Player, size: Vector3): CFrame?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end

	local place = LobbyCarConfig.Placement
	local origin = root.Position
	-- Flattened, so looking up a tower block does not launch the candidates into the sky.
	local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if forward.Magnitude < 1e-3 then
		forward = Vector3.zAxis
	end
	forward = forward.Unit
	local right = forward:Cross(Vector3.yAxis).Unit

	-- Both lists built once rather than per candidate: this is up to 24 ground probes and 24 box
	-- queries, and what a placement query ignores cannot change in the middle of one placement.
	local groundIgnore = self:_ignoreList(self._folder)
	local carIgnore = self:_ignoreList(self:_carOf(player))

	local fallback: CFrame? = nil
	for _, ring in place.Rings do
		for _, candidate in place.Candidates do
			local spot = origin
				+ right * (candidate[1] * place.Side * ring)
				+ forward * (candidate[2] * place.Ahead * ring)
			local ground = self:_groundAt(spot, groundIgnore)
			if not ground then
				continue
			end

			--[[ Nose at the player, wheels `Clearance` above what the probe found.

				The box is centred on the BOUNDING BOX, not on the model's pivot — a CarBones pivot
				is its chassis floor panel, which sits about a stud below centre, so pivoting to
				this frame directly would bury the wheels. `_prepare` takes that offset back out. ]]
			local base = ground + Vector3.new(0, size.Y * 0.5 + place.Clearance, 0)
			local aim = Vector3.new(origin.X, base.Y, origin.Z)
			local pivot = if (aim - base).Magnitude > 1e-3
				then CFrame.lookAt(base, aim, Vector3.yAxis)
				else CFrame.new(base)

			local blocked = self:_blockedBy(pivot, size, carIgnore)
			if not blocked then
				return pivot
			end
			if blocked == "scenery" then
				fallback = fallback or pivot
			end
		end
	end

	if fallback then
		self.log:info(string.format("No clear spot for %s's car; using the nearest one with ground.", player.Name))
	else
		self.log:info(string.format("Nowhere to put %s's car: every candidate spot has a car in it.", player.Name))
	end
	return fallback
end

-- === Spawning ===============================================================

--[[ The car this player has standing in the lobby, or nil.

	Re-checked against the tree rather than trusted, so a car removed by anything else — a Studio
	explorer delete during a playtest, a future cleanup pass — leaves this service agreeing with the
	world on the next call instead of holding a dead model forever. ]]
function LobbyCarService._carOf(self, player: Player): Model?
	local car = self._cars[player]
	if car and car:IsDescendantOf(workspace) then
		return car
	end
	if car then
		self._cars[player] = nil
	end
	return nil
end

--- Public: the car this player has standing in the lobby, or nil. `PlotService._onGoHome` asks it
--- whether the seat a player is leaving belongs to their own car, which is the one it puts away.
function LobbyCarService.getLobbyCar(self, player: Player): Model?
	return self:_carOf(player)
end

--[[ Take over getting into this car, so the door can open BEFORE the driver appears in the seat.

	WHAT THIS REPLACES, and it is worth being exact, because everything below is a line-for-line
	answer to a line of the stock `VehicleSeating.AddSeat` prompt block that
	`Vehicle.DeferredEntryAttribute` withheld:

	  • the prompt is up only while a seat is empty         (stock `setCarjackPrompt`)
	  • an upside-down car is flipped instead of entered    (stock `isFlipped` / `FlipSeat`)
	  • you have to be within 15 studs                      (stock `MAX_SEATING_DISTANCE`)
	  • door: unlatch, 55 degrees, `OpenCloseDoor`, shut    (stock `DOOR_OPEN_*`)

	"a seat" and not "the seat" in the first bullet is the one place this has grown past the block it
	replaces: this prompt speaks for the whole car now, the wheel and the three seats behind it. The
	long note on `passengerSeats` below is why that had to be one prompt rather than four.

	and the one thing it does differently: THE SIT MOVED TO AFTER THE SWING STARTS. That is the
	entire feature. Stock does `seat:Sit(humanoid)` and then opens the door; this opens the door,
	waits `Entry.SeatDelay`, and then sits — so the door is standing open when you appear in it.

	CARJACKING IS NOT REPRODUCED, and its absence is the same decision `Vehicle` already made when it
	stamps `AllowCarjacking = false` on every car: the stock block will eject a seated driver and put
	the presser in their place, which is not a thing this game has ever wanted in the lobby. With the
	attribute false the stock code could not reach that path either, so this is parity, not a cut.

	EVERY CHECK IS MADE TWICE, before the swing and again after the wait, because `SeatDelay` opens a
	window that did not exist before — 0.4s is long enough to walk away, to die, or for someone else
	to get in through the passenger door. The one that is easy to forget is `car.Parent`: putting the
	car away is a `Destroy` on another thread, and a sit into a destroyed seat welds the player to
	nothing (the failure `_despawn` exists to prevent, arrived at from the other direction).

	A BODY WITH NO DOOR SKIPS THE WAIT rather than serving it. `Entry.SeatDelay` is time bought to
	watch a door move, and on the three bodies with no separable panel there is nothing to watch —
	holding them at the prompt for 0.4s would be a hitch with no cause on screen.

	Returns false if this car has no driver prompt at all, which is the caller's signal to hand the
	seat back to the stock handler rather than leave it with no way in. ]]
function LobbyCarService._wireEntry(self, car: Model): boolean
	local chassis = car:FindFirstChild("Chassis")
	if not chassis then
		return false
	end

	--[[ The driver's seat, and the prompt on it. Asked of the rig rather than by seat NAME, which
		differs across the pack — but it does have to be asked of the CLASS as well as of the prompt.

		This loop used to take the first seat carrying a `PromptLocation` and call it the driver's,
		which was true only because the passenger seats had none. They do now
		(`Vehicle.PassengerEntryAttribute`) — inert ones, but present — and `VehicleSeat` is the test
		that cannot go stale: it is the same question `Chassis.driverSeat` asks, there is exactly one
		per rig, and the other three are plain `Seat`s. ]]
	local seat, prompt
	for _, part in chassis:GetChildren() do
		if part:IsA("VehicleSeat") then
			local location = part:FindFirstChild("PromptLocation")
			local found = location and location:FindFirstChildWhichIsA("ProximityPrompt")
			if found then
				seat, prompt = part, found
				break
			end
		end
	end
	if not (seat and prompt) then
		return false
	end

	local entry = LobbyCarConfig.Entry

	--[[ THE REACH HAS TO COVER THE CAR, NOT THE DOOR, NOW THAT ONE PROMPT SPEAKS FOR FOUR SEATS.

		The pack authors this at 10 studs, which was right when the only thing it offered was the
		seat it is bolted to: the attachment floats a stud and a bit outboard of the DRIVER'S door
		and six up, and ten studs is a comfortable ring around that one door.

		Measured on a two-client playtest, standing at the front-RIGHT door of a Skyline: 3.70 studs
		from the seat being asked for and 10.01 from the prompt — so the engine drew nothing at all
		and the passenger side of every car was a wall. The far rear corner is worse. That is not a
		tuning preference, it is the whole feature failing on half the car.

		`entry.MaxDistance` rather than a number of its own, because the handler below already
		refuses anything further than that: matching them means the prompt is visible exactly when
		pressing it would work, which is the only relationship between those two numbers that can
		never read as a bug. It is also the stock `MAX_SEATING_DISTANCE`, so this is the kit's own
		reach, applied to the kit's own prompt. ]]
	prompt.MaxActivationDistance = entry.MaxDistance

	--[[ AND THE PILL COMES DOWN OFF THE ROOF. `entry.PromptOffset` carries the measurement and the
		reasoning; the short version is that the pack's six studs of lift clears the tallest body in
		the roster by 0.1 studs and the shortest by 3.1, so on most cars the prompt hangs in the air
		above the car rather than sitting on the door it opens.

		WRITTEN ON THE ATTACHMENT AND NOT ON THE PROMPT, because an `Attachment` is what a prompt is
		positioned by and what `ButtonGuiPrototype` is adorned to. Setting `CFrame` on an attachment
		that is already parented is a LOCAL offset from its part, which is the seat, so this is the
		same frame the pack authored its own offset in.

		THE EXIT PATH DOES NOT CARE WHERE IT IS. `LocalVehicleSeating.ExitSeat` walks a rider's
		`SeatWeld` back to their seat and checks only that a `PromptLocation` holding a prompt named
		`EndorsedVehicleProximityPromptV1` EXISTS. Moving that attachment is safe; moving the prompt
		out of it is what would break getting out. ]]
	local location = prompt.Parent
	if location and location:IsA("Attachment") then
		location.CFrame = CFrame.new(entry.PromptOffset)
	end

	--[[ IS THERE A DRIVER IN THIS SEAT? `Occupant` on its own does not answer that, and the gap is
		the whole of the first half of this bug.

		`Occupant` is cleared by the engine when the weld comes down, and the weld does not always
		come down — a driver who dies, or whose character is removed under them, can leave the seat
		still naming a humanoid that is no longer anywhere. Every reader here believes it: the prompt
		stays dark, the guard in the handler below refuses every press, and the car stands in the
		lobby looking empty with no way into it for the rest of its life.

		So a seat held by a humanoid that has left the world or died is free, and saying so takes the
		weld down to make the engine agree — `RaceService:541` releases a rider exactly this way, for
		exactly the reason noted there: the weld IS the release, and clearing `Sit` alone takes about
		five physics frames. The destroy puts `Occupant` back to nil, which comes back round through
		the property signal below with nothing special-cased. ]]
	local function seatIsFree(which: BasePart): boolean
		local occupant = (which :: Seat).Occupant
		if not occupant then
			return true
		end
		if occupant.Parent ~= nil and occupant.Health > 0 then
			return false
		end

		local weld = which:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		return true
	end

	--[[ === THE OTHER THREE SEATS, AND WHY THIS ONE PROMPT SPEAKS FOR ALL FOUR ==================

		A lobby car has three passenger seats beside the driver's, and the obvious way to open them
		is the way the kit itself suggests: a `PromptLocation` on each, four prompts, four doors. It
		does not work, and the reason is worth writing down because the code that tried it looked
		correct.

		EVERY VEHICLE PROMPT IS BOUND TO E AND CARRIES `Exclusivity = OnePerButton`, so the engine
		shows exactly one of them and picks which. It does NOT pick the nearest. Measured on a
		two-client playtest with all four raised: standing at the DRIVER'S door, 5.09 studs from the
		driver's prompt and 9.29 from the rear-left one, the engine drew the REAR-LEFT prompt and
		kept drawing it — so the driver's seat, the one thing every player needs, became unreachable
		on a car parked in the open. Tightening the reach cannot separate them either: the doors are
		2.8 studs apart on a 10-stud prompt radius, so from any door three of the four are in range.

		SO THE CAR KEEPS ONE PROMPT AND IT ANSWERS THE WHOLE QUESTION. Free driver's seat means you
		drive; taken means you ride, in the free seat nearest to where you are standing. That is the
		same sentence the player was going to read off four prompts anyway, and it cannot be
		arbitrated wrongly because there is nothing to arbitrate.

		The passenger seats still get an attachment (`Vehicle.PassengerEntryAttribute`) — inert,
		`Enabled = false`, raised after the stock `AddSeat` has already looked — because the CLIENT'S
		exit path needs it: `LocalVehicleSeating.ExitSeat` walks the rider's `SeatWeld` back to its
		seat and refuses to fire unless it finds a `PromptLocation` holding a prompt by that exact
		name. No attachment, no way out of the seat.

		THOSE THREE ATTACHMENTS EARNED A SECOND JOB and are no longer only a shape the exit path
		insists on. `VehiclePromptGui` hangs the pill on the door of the seat the press is for, and
		these are the doors: `raisePassengerPrompt` builds them from the driver's attachment with the
		X mirrored for the two seats across the car, and it does that AFTER the offset below has been
		written, because that write happens before the car is parented and `Vehicle.setup` runs
		because the car is parented. So all four sit at their own window with nothing keeping them in
		step. The prompts inside them stay dark.

		THE ICON USED TO LIE ABOUT THAT AND NO LONGER DOES. The kit picks its prompt art off the seat
		the prompt is PARENTED to (`seat.Name == "VehicleSeat"`), which on this car is always the
		wheel, so the button drew a steering wheel even on the press that seats you in the back.
		Moving the prompt to a different seat to fix that is what would break the exit path above, so
		the prompt stays where it is and `refresh` below publishes the answer instead: the car writes
		`VehiclePromptGui.SeatAttribute` on its prompt and the client's pill draws off that. ]]
	local function passengerSeats(): { BasePart }
		local seats = {}
		for _, part in chassis:GetChildren() do
			if part:IsA("Seat") and part ~= seat then
				table.insert(seats, part)
			end
		end
		return seats
	end

	--- Where this press is going to put them: the wheel if it is free, otherwise the nearest free
	--- seat to where they are standing, otherwise nowhere and the press does nothing.
	local function seatFor(from: Vector3): BasePart?
		if seatIsFree(seat) then
			return seat
		end
		local best, bestDistance = nil, math.huge
		for _, part in passengerSeats() do
			if seatIsFree(part) then
				local distance = (from - part.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = part, distance
				end
			end
		end
		return best
	end

	--- Is there ANY way into this car right now? The prompt's light, and the first thing the
	--- handler asks — a full car is the one case where the press has nothing to offer.
	local function anySeatIsFree(): boolean
		if seatIsFree(seat) then
			return true
		end
		for _, part in passengerSeats() do
			if seatIsFree(part) then
				return true
			end
		end
		return false
	end

	--[[ The stock `setCarjackPrompt`, minus the carjack half. Driven off `Occupant` rather than set
		once, because the seat empties again every time somebody gets out.

		AND OFF THE DRIVER AS WELL AS THE SEAT, because the case above is a case in which `Occupant`
		never changes and so this never runs. Each time somebody sits we watch that humanoid's `Died`
		and `AncestryChanged`, which is what actually happens at the moment the seat goes stale, and
		re-ask. The watch is torn down and rebuilt on every pass, so it only ever holds connections
		to the humanoid currently in the seat, and `Destroying` takes the last of them with the car —
		the humanoid outlives the car it was sitting in, so nothing else would. ]]
	local watch: { RBXScriptConnection } = {}

	local function clearWatch()
		for _, connection in watch do
			connection:Disconnect()
		end
		table.clear(watch)
	end

	--- Every seat, not just the wheel: the prompt is now lit by whether ANY of them is free, so a
	--- rider who dies in the back has to bring it back on exactly as a driver who dies does.
	local function refresh()
		clearWatch()

		for _, part in { seat, table.unpack(passengerSeats()) } do
			local occupant = (part :: Seat).Occupant
			if occupant then
				table.insert(watch, occupant.Died:Connect(refresh))
				table.insert(watch, occupant.AncestryChanged:Connect(refresh))
			end
		end

		--[[ WHAT THE PRESS IS WORTH, published for the pill that draws it. The kit picks its icon
			off the seat the prompt is PARENTED to, which on this car is always the wheel, so a press
			that was going to seat you in the back still drew a steering wheel. That was written off
			as cosmetic for a while and it is not: it is the only thing on screen that says which
			seat you are about to take.

			`seatFor` is the function that actually decides, and it says the same thing this does:
			the wheel if the wheel is free, a passenger seat otherwise. It cannot be asked here
			because it wants the presser's position and this runs with nobody pressing anything, but
			the branch it takes first is exactly this one, so the icon and the outcome agree.

			`VehiclePromptGui.SeatAttribute` reads it back on the client and redraws the icon in
			place, so a car whose driver's seat fills while somebody is standing at the door changes
			under them rather than lying until they walk away. ]]
		local wheelIsFree = seatIsFree(seat)
		prompt:SetAttribute(
			VehiclePromptGui.SeatAttribute,
			if wheelIsFree then VehiclePromptGui.Driver else VehiclePromptGui.Passenger
		)

		prompt.Enabled = wheelIsFree or anySeatIsFree()
	end

	seat:GetPropertyChangedSignal("Occupant"):Connect(refresh)
	for _, part in passengerSeats() do
		part:GetPropertyChangedSignal("Occupant"):Connect(refresh)
	end
	car.Destroying:Once(clearWatch)
	refresh()

	--[[ Stock `isFlipped`: 70 degrees off vertical. Measured on the SEAT and not on the model pivot,
		which is a chassis panel whose orientation says nothing about which way up the body is. ]]
	local function isFlipped(): boolean
		local angle = math.deg(math.acos(math.clamp(seat.CFrame.UpVector:Dot(Vector3.yAxis), -1, 1)))
		return angle >= 70
	end

	--[[ Stock `FlipSeat`, which is a one-line call into the car's own `Chassis` module — the same
		per-car place-side copy the car is already running, so `require` is a cache hit and there is
		no second instance of anything. pcall'd because it is place-side code this file does not own
		and a car that will not right itself must not also break the way in. ]]
	local function flip()
		local scripts = car:FindFirstChild("Scripts")
		local module = scripts and scripts:FindFirstChild("Chassis")
		if module and module:IsA("ModuleScript") then
			pcall(function()
				require(module).Redress()
			end)
		end
	end

	-- One at a time. Two people pressing E on the same car a frame apart would otherwise queue two
	-- sits and two closes, and the second close lands on a door the first already latched.
	local busy = false

	prompt.Triggered:Connect(function(player: Player)
		if busy or car.Parent == nil then
			return
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and hrp and humanoid.Health > 0) then
			return
		end

		--- Which seat this press is for. Decided ONCE, here, off where the presser is standing, and
		--- carried through the door beat below — asking again after the wait would be asking a
		--- different question, since somebody else may have taken the seat this press was for.
		local target = seatFor(hrp.Position)
		if not target then
			return -- a full car
		end

		--- The reach is measured to the seat being taken rather than to the wheel, so the back doors
		--- are as reachable as the front ones on a long body.
		if (hrp.Position - target.Position).Magnitude > entry.MaxDistance then
			return
		end

		if isFlipped() then
			flip()
			return
		end

		--[[ EVERYTHING `busy` COVERS IS PCALL'D, and the second half of this bug is the reason.

			`busy` is raised here and lowered on the last line, and between the two are two
			`task.wait`s and four calls out of this file — three into `CarDoors` and one `Sit`. An
			error in any of them unwinds this thread past the line that lowers it, and `busy` is a
			per-car upvalue with no other writer: it stays true for as long as the car exists, and
			every later press returns at the first line of this handler. The visible result is a car
			with its prompt lit that silently refuses everyone, which is the report on the card.

			A door that fails to open or shut is a bug worth a line in the log. A car nobody can get
			into again is the one that gets reported, so the clear is unconditional and the failure
			is merely told. ]]
		busy = true
		local ok, err = pcall(function()
			--- The door for THIS seat. The two rear seats have no separable panel on any body in
			--- this pack (`CarDoorRig` rigs FL and FR only), so `rigOf` returns nil for them and
			--- they skip the swing and its wait — the same "a body with no door skips the wait"
			--- case the header describes, arrived at per seat instead of per car.
			local rig = CarDoors.rigOf(car, target)
			if rig then
				CarDoors.openRig(rig, entry.DoorAngle, entry.DoorSpeed)
				local sound = target:FindFirstChild("OpenCloseDoor")
				if sound and sound:IsA("Sound") then
					sound:Play()
				end
				task.wait(entry.SeatDelay)
			end

			--[[ Re-checked against the world as it is NOW, not as it was when E was pressed.
				Everything here can have changed during the wait, and the sit is the irreversible
				half. ]]
			local stillThere = car.Parent ~= nil
				and humanoid.Parent ~= nil
				and humanoid.Health > 0
				and hrp.Parent ~= nil
				and seatIsFree(target)
				and (hrp.Position - target.Position).Magnitude <= entry.MaxDistance
			if stillThere then
				(target :: Seat):Sit(humanoid)
			end

			if rig then
				task.wait(entry.DoorHold)
				CarDoors.closeRig(rig, entry.DoorSpeed)
			end
		end)
		busy = false

		if not ok then
			self.log:warn(string.format("%s's entry into a lobby car failed partway: %s", player.Name, tostring(err)))
		end
	end)

	return true
end

--[[ Clone `body` and stand it next to `player`. Returns the car, or nil with a reason.

	ORDER OF OPERATIONS, and each step is where it is on purpose:

	  1. The bounding box is measured on the CLONE, before it is parented — the roster car is
	     unanchored and physically live where it stands, so measuring the source would be measuring
	     whatever pose it has settled into rather than the car.
	  2. The collision group goes on before parenting, exactly as `RaceService._spawnCar` does it,
	     so the group replicates as part of the car's initial state instead of being chased through
	     replication part by part.
	  3. `PivotTo` happens while it is still out of the tree, and THE CAR IS RETURNED UNPARENTED. That
	     is what lets `setLobbyCar` do the whole thing in the safe order: prepare the new car, and
	     only once it has somewhere to go destroy the one the player already had. Parenting here
	     instead would mean a failed placement had already thrown away a perfectly good car.

	     It also means placement runs while the OLD car is still standing there — which is not a
	     problem but a feature, because both placement queries ignore the lobby-car folder: the
	     replacement lands on the spot the old one was occupying, a frame before it is removed.

	IT DOES RIG THE DOORS, exactly as `RaceService._spawnCar` does and for the same reason: NO CAR IN
	THE ROSTER IS AUTHORED WITH A DOOR RIG. Four of the sixty-five are — CarBones, its backup, Car1
	and the Lambo — and reading only those is what made this look for a while like the roster already
	carried its own doors; every pack body arrives with the seat's `DoorHinge`/`DoorLatchWeld` present
	but wired to nothing, so the stock prompt handler dutifully unlatched a door that did not exist and
	nothing moved. `CarDoorRig.apply` derives the rig from the body's geometry, and swept over the whole
	roster it rigs 57 of the 65 with no wrong-direction verdicts (2.1-3.5 studs OUTBOARD, height 0.00 —
	a conventional swing-out on every one). Of the eight it does not: four are the reference chassis and
	the Lambo, all of which carry their own authored rig and are deliberately left alone; the three real
	pack bodies with no separable panel are F&F EVO, Senna and Gemera, and they simply have doors that
	do not open.

	AND THEN IT TAKES THE WAY IN, but only the way in. Getting OUT is still stock and untouched: E
	fires `Remotes.ExitSeat`, `VehicleSeating.ExitSeat` swings the door, walks you to `ExitPosition`
	and re-latches. Only the ENTRY is ours, because the stock entry seats you on its first line and
	swings the door on its next — the door opens around a driver who is already sitting in the car.
	`_wireEntry` below puts `LobbyCarConfig.Entry.SeatDelay` between the two, and to get that seam it
	has to own the whole trigger: there is no hook inside a connected closure in a place-side module,
	and `Seat.Disabled` is not one either (measured: `:Sit()` seats straight through it, and setting
	it on an occupied seat ejects the occupant). `Vehicle.DeferredEntryAttribute` is what keeps the
	stock handler off this seat, and its note is where the mechanism is written down.

	NO `carryMass`, though `CarDoorRig`'s header suggests it for the servo path — this IS the servo path,
	so that suggestion was measured rather than taken. Massless, a Civic's door swings 2.5 studs outboard
	to 54°, holds there without sagging, and re-latches flush 1.6s after the prompt; the servo settles to
	0.005°, INSIDE the stock script's 0.01° threshold, which is the number that decides whether the door
	ever re-latches at all — the stock close loop is `while math.abs(CurrentAngle) > 0.01 do wait() end`
	with no timeout, and an unlatched door is a loose assembly forever. Carrying mass changed none of
	that and cost 0.06 on a 353.14 assembly, so the redress rule that a dress weighs nothing survives.

	And the latch does its job under the worst case, which is driving off inside the open half-second:
	shoved along at 60 studs/s through the whole swing, the panel tracked the car with no lag and came
	back to 0.016 studs of its shut pose before the weld went back on.

	IT DOES NOT DECIDE THE COLOUR. The colour arrives as half of the CAR KEY the caller was given, and
	the caller has already checked that key against the collection — so the clone is painted with the
	paint of a car this player provably owns, and the car in the street is the car on the podium is
	the car they stole. ]]
function LobbyCarService._prepare(self, player: Player, key: string, body: string, paint: number, mutation: string?, options: SpawnOptions?): (Model?, string)
	local source = self:_roster(body)
	if not source then
		return nil, "no such body in the roster"
	end

	local car = source:Clone()

	--[[ The car's own centre, in its pivot's frame. Measured along the pivot's axes, so this is a
		pure translation — and it is not zero: a CarBones pivot is the chassis floor panel, about a
		stud below the middle of the body. Placement works in centres (that is what the clearance box
		and the ride height are about), so the offset is measured here and taken back out when the
		car is finally pivoted.

		`_measure` rather than `Model:GetBoundingBox`, and its note has the four rigs that is for. ]]
	local centreOffset, size = self:_measure(car)

	--[[ WHERE IT GOES, AND THE ONE CALLER THAT ALREADY KNOWS.

		The ordinary answer is the ring of candidates around the player (`_placement`), because the
		ordinary caller is a screen and "beside me" is the only thing it can mean. `options.ground`
		is the other case: `CarDealService` has just sold a car standing in a parking bay it probed
		for road, flatness, clearance and room to pull out of before it ever painted the bay, and the
		car being handed over belongs in that bay rather than beside whoever bought it.

		THE OVERRIDE IS A GROUND FRAME AND THIS TURNS IT INTO A CENTRE, which is the same conversion
		`_placement` does with what its own probe found: the placement contract in this file is the
		middle of the car's BOX, and `_prepare` takes the box-to-pivot offset back out on its last
		line. A caller handing us a frame therefore says where the wheels go and does not have to
		know anything about the body standing on them.

		AND IT IS TRUSTED. There is no clearance test on this path, deliberately: the spot was tested
		when it was chosen and again when the stand moved onto it, and re-testing here would fail on
		the buyer, who is standing in the bay they just bought out of. A car arriving on top of
		somebody is unanchored and physical and sorts itself out in a frame; a purchase that silently
		refuses to hand over a car does not. ]]
	local place = LobbyCarConfig.Placement
	local target = if options and options.ground
		then options.ground * CFrame.new(0, size.Y * 0.5 + place.Clearance, 0)
		else self:_placement(player, size)
	if not target then
		car:Destroy()
		return nil, "nowhere to put it"
	end

	--- A group of its own, so it passes through other lobby cars but its wheels still meet its body
	--- (`CarCollision.applyLobbyCar`, 2026-10-15).
	CarCollision.applyLobbyCar(car, self._folder)
	car:SetAttribute(LobbyCarConfig.OwnerAttribute, player.UserId)
	car:SetAttribute(LobbyCarConfig.BodyAttribute, body)
	car:SetAttribute(LobbyCarConfig.KeyAttribute, key)

	--[[ Their paint, on the CLONE. Never on `source`: painting clears the MeshPart texture the
		roster's colour lives in (`Modules/CarPaint`), so the same call one line further up the
		function would strip the master copy of this body for every player on the server, permanently,
		with no undo. The clone is the whole safety here. ]]
	CarPaint.apply(car, paint, body)

	--[[ …and the weather that was on it when it was stolen (`WeatherConfig`), by the same module the
		road and the podium use. Same car, same look, in all three places — which is the whole reason
		that module exists rather than each of them dressing a car its own way.

		WITHOUT A BADGE. The pill over a traffic car tells you what to jump at; a street full of them
		would be signage. And this is a car somebody DROVE HERE to show off, so the tell should be on
		the paintwork rather than floating above it.

		nil for an ordinary car, which is nearly all of them, and `apply` no-ops on one. ]]
	CarMutation.apply(car, mutation)

	--[[ ITS OWN HANDLING (2026-10-08, `LobbyCarConfig.Handling`). A lobby car used to drive on the raw
		model's authored chassis numbers, which no one tuned, while the same car in a race got its
		`CarConfig` row — so the M5 on the street and the M5 on the road were two different cars. Now
		the same stamp the race uses (`RaceService`, `CarStats.apply`), with this player's level for
		the body and the parts fitted to this exact car. Before parenting, so the chassis reads them
		from its first frame. A garage that is not up stamps the bare row, never nothing. ]]
	if LobbyCarConfig.Handling.Enabled and LobbyCarConfig.Handling.Stats then
		local Garage = Shard.get("GarageService")
		local level = if Garage then Garage:getCarLevel(player, body) else 1
		local data = if Garage then Garage:getCarData(player, key) else nil
		CarStats.apply(car, body, level, data and data.Parts)
		--- The lobby's own damping on top (`LobbyCarConfig.Handling.DampingScale`): the city is not flat.
		--- And its ride height (`Handling.StiffnessScale` / `StiffnessByBody`): stiffer springs, with the
		--- damping raised by the root of the same factor so the car does not get bouncier for it.
		local handling = LobbyCarConfig.Handling
		local stiffness = (handling.StiffnessScale or 1) * ((handling.StiffnessByBody or {})[body] or 1)
		for _, name in { "StrutSpringStiffnessFront", "StrutSpringStiffnessRear", "TorsionSpringStiffness" } do
			local value = car:GetAttribute(name)
			if type(value) == "number" then
				car:SetAttribute(name, value * stiffness)
			end
		end
		local damping = (handling.DampingScale or 1) * math.sqrt(stiffness)
		for _, name in { "StrutSpringDampingFront", "StrutSpringDampingRear", "TorsionSpringDamping" } do
			local value = car:GetAttribute(name)
			if type(value) == "number" then
				car:SetAttribute(name, value * damping)
			end
		end
	end

	--[[ And its number plate, off the same body-and-colour identity (`PlateConfig.forKey`). The car
		standing in the street is the car on the podium is the card on the dealership page, right down
		to the number on the back of it, because all three ask the same question of the same table
		rather than being told an answer. ]]
	CarPlate.apply(car, body, paint)

	--[[ Doors, before parenting so the rig replicates as part of the car's initial state rather than
		as a burst of reparenting and constraint edits against a model the client is already drawing —
		the same reasoning, and the same moment, as the collision group above. A body with no separable
		doors returns 0 and is simply a car whose doors do not open. ]]
	local rigged, notes = CarDoorRig.apply(car)
	if rigged == 0 then
		self.log:info(string.format("Lobby car '%s' has no doors to rig: %s", body, table.concat(notes, "; ")))
	end

	--[[ Both halves of the entry beat, BEFORE the car is parented, and that is the whole reason
		neither one races the stock system.

		The attribute has to be on the model when `Vehicle.setup` runs, and `setup` runs BECAUSE the
		car is parented — so stamping it any later is stamping it after the stock handler has already
		connected. And connecting `_wireEntry` here means our `Triggered` handler exists before the
		car is in the world at all, so there is no window, however short, in which a car is standing
		in the lobby with a prompt that nothing answers. ]]
	car:SetAttribute(Vehicle.DeferredEntryAttribute, true)
	if not self:_wireEntry(car) then
		self.log:info(string.format("Lobby car '%s' has no driver prompt to wire; entry left to the stock handler.", body))
		car:SetAttribute(Vehicle.DeferredEntryAttribute, nil)
	end

	--[[ And the other three seats, in the same window and for the same reason: the attribute has to
		be on the model before `Vehicle.setup` runs, and `setup` runs because the car is parented.

		It buys the passenger seats the inert `PromptLocation` the client's exit path insists on
		finding — not a way in. The way in for all four seats is the prompt `_wireEntry` just took
		over, which is the only arrangement that leaves the driver's seat reachable. See
		`LobbyCarConfig.Passengers`. ]]
	if LobbyCarConfig.Passengers.Enabled then
		car:SetAttribute(Vehicle.PassengerEntryAttribute, true)
	end

	car:PivotTo(target * centreOffset:Inverse())

	return car, "ok"
end

--[[ Put the owner behind the wheel of a car that has just been parked for them.

	THIS IS NOT THE ENTRY BEAT AND IT DELIBERATELY SKIPS IT. `_wireEntry` exists to make getting in
	look like getting in: the door swings, and four tenths of a second later you appear in the seat
	through it. Nothing here is an approach. The player bought the car standing in front of them and
	the answer to "and then what" is that they are driving it, so the door beat would be a wait with
	nothing to look at.

	=== THE ONE THING THAT CAN GO WRONG, AND IT GOES WRONG SILENTLY ===========================

	A `Sit` that lands before the car's own `Vehicle` script has finished `setup` welds the player
	into a car that will never move. `VehicleSeating.AddSeat` is what connects the seat's `Occupant`
	listener, and everything a driver needs hangs off that listener firing: the control ScreenGui,
	the Driver LocalScript, the network handover and the engine. Before it, `Occupant` changes and
	nobody is listening. Nothing reports it either — the seat is occupied and the model is complete,
	which is exactly the "dead Driver" fingerprint, arrived at from a new direction.

	So this WAITS FOR THE CAR rather than for a duration. `Vehicle.isReady` is true on the line after
	the last `AddSeat`, and the wait is bounded because a rig that is not running the stock scripts
	at all would never become ready and yielding on it forever is how a purchase silently does
	nothing. Running out of patience seats them anyway and says so: a car that might not drive beats
	a car they are certainly not in, and the log line is what turns the report into a diagnosis.

	`settle` ON TOP OF THAT IS PHYSICS, NOT REPLICATION. A rig arrives unanchored and spends its
	first frames dropping onto its suspension; welding somebody into an assembly that is still
	resolving reads as the car twitching under them as they appear.

	EVERY CHECK IS MADE AFTER THE WAIT AND NOT BEFORE IT, for `_wireEntry`'s reason: the window is
	small but it is real, and a player can leave, die or be put in a race inside it. The one that is
	easy to forget is `car.Parent`, because putting a car away is a `Destroy` on another thread and a
	sit into a destroyed seat welds the player to nothing. ]]
local READY_TIMEOUT = 2

function LobbyCarService._seatDriver(self, player: Player, car: Model, settle: number?)
	--[[ The wheel. Asked of the CLASS rather than by name, which is `_wireEntry`'s rule and for its
		reason: seat names differ across the pack, there is exactly one `VehicleSeat` per rig, and
		the other three are plain `Seat`s. ]]
	local chassis = car:FindFirstChild("Chassis")
	local seat = chassis and chassis:FindFirstChildWhichIsA("VehicleSeat")
	if not seat then
		self.log:warn(string.format("%s's car has no driver's seat to put them in.", player.Name))
		return
	end

	local deadline = os.clock() + READY_TIMEOUT
	while not Vehicle.isReady(car) and os.clock() < deadline do
		if car.Parent == nil then
			return
		end
		task.wait()
	end
	if not Vehicle.isReady(car) then
		self.log:warn(string.format(
			"%s's car never finished wiring its seats; seating them anyway, the controls may not deploy.",
			player.Name
		))
	end

	if settle and settle > 0 then
		task.wait(settle)
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (car.Parent and humanoid and humanoid.Parent and humanoid.Health > 0) then
		return
	end
	--- Somebody else got in first, which on a car that has been standing there for two tenths of a
	--- second means a friend was already leaning on the door. They keep it; this is not a carjack.
	if (seat :: VehicleSeat).Occupant then
		return
	end

	(seat :: VehicleSeat):Sit(humanoid)
end

-- Put away whatever this player has out. Safe to call when they have nothing.
--- `ReportLobbyDrift` (remote above has the trust note). A car not being driven by its owner is never on.
function LobbyCarService._onDriftReport(self, player: Player, on: unknown)
	local car = self:_carOf(player)
	if not (car and type(on) == "boolean") then
		return
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local driving = seat ~= nil and seat:IsA("VehicleSeat") and seat:IsDescendantOf(car)
	car:SetAttribute(LobbyCarConfig.Handling.Drift.Attribute, on and driving)
end

function LobbyCarService._despawn(self, player: Player)
	local car = self:_carOf(player)
	self._cars[player] = nil
	self:_publish(player)
	if not car then
		return
	end

	local body = car:GetAttribute(LobbyCarConfig.BodyAttribute)

	--[[ Empty the car first. Destroying one out from under a seated rider leaves them welded to
		nothing — the same class of bug the race's void guard exists for — and unlike the race exit
		there is nowhere to teleport them to, because they are already exactly where they want to
		be. So the seats are released and the characters are left standing in the road.

		EVERY OCCUPANT, NOT THE OWNER. This used to stand up `player` and nobody else, which is the
		wrong question asked of the wrong person: an empty lobby car is open to anyone who walks
		past (that is deliberate — it is what lets a friend take the wheel; see the `AllowCarjacking`
		note in `Modules/Vehicle` for the part that is NOT allowed), so the person in your car when
		you put it away is often not you. `Vehicle.evictOccupants` walks the car's own seats, so it
		does not need to be told who to look for.

		AND IT RUNS THE STOCK EXIT TEARDOWN, which is the half that was silently missing even for
		the owner: `Destroy()` disconnects the seat listener that would have run it, so releasing
		the seat here and destroying the car on the next line meant `onExitSeat` never fired at all.
		The rider's lower legs are hidden on the way IN and only put back on the way OUT — so the
		driver of a despawned lobby car walked away with no legs. That is the 16 Aug playtest's
		"stealing a car strips the rider's legs", and it was neither the steal nor a missing limb. ]]
	Vehicle.evictOccupants(car)

	car:Destroy()
	if type(body) == "string" then
		self:getSignal("CarDespawned"):Fire(player, body)
	end
end

-- Broadcast which body is standing in the lobby, for the Cars Inventory. See LobbyCarConfig.
function LobbyCarService._publish(self, player: Player)
	if player.Parent ~= Players then
		return
	end
	local car = self:_carOf(player)
	local key = car and car:GetAttribute(LobbyCarConfig.KeyAttribute)
	player:SetAttribute(LobbyCarConfig.SpawnedAttribute, if type(key) == "string" then key else "")

	--- ...and the hands, published the same way and for the same reason `_publishCarried` gives: the
	--- empty string rather than a cleared attribute, so a client reading it never has to tell
	--- "holding nothing" from "not published yet". This is the join-time write; every change after
	--- it goes through `setToyCar`.
	player:SetAttribute(LobbyCarConfig.Toy.Attribute, self:getToyCar(player) or "")
end

-- === The car in your hands ==================================================
--[[ Public: the car this player is holding, waiting to drop, or nil for empty hands.

	IT EXISTS FOR `CarryService`, which asks it every time it works out what should be in somebody's
	hands. Nothing else needs it: the client draws off the attribute and the drop reads the table
	directly.

	IN MEMORY AND NOT IN THE PROFILE, which is the one real difference from the garage's carry and is
	argued in `LobbyCarConfig.Toy`. A toy that survived a rejoin would be a promise the player never
	made, and there is nothing to lose by dropping it: the car is in the collection and the screen
	that offers it is one press away. ]]
function LobbyCarService.getToyCar(self, player: Player): string?
	local key = self._toys[player]
	return if type(key) == "string" and key ~= "" then key else nil
end

--[[ Put a car in this player's hands, or empty them (`key = nil`).

	THE ORDER IS THE CONTRACT and `ToyChanged` is fired last, the same order `setCarriedCar` uses and
	for the same reason: the table is written, the attribute is published, and only then is anything
	told. A subscriber that rebuilt the model off a half-applied change would be holding a car this
	service has not finished agreeing to.

	IT DOES NOT CHECK OWNERSHIP. `_onSpawnRequest` checked it on the way in and `setLobbyCar` checks
	it again on the way out, which is the check that matters: the toy is a cosmetic promise, and the
	car it promises cannot be spawned without being owned at the moment of the drop. ]]
function LobbyCarService.setToyCar(self, player: Player, key: string?)
	if self._toys[player] == key or (self._toys[player] == nil and key == nil) then
		return
	end
	self._toys[player] = key
	if player.Parent == Players then
		player:SetAttribute(LobbyCarConfig.Toy.Attribute, key or "")
	end
	self:getSignal("ToyChanged"):Fire(player, key)
end

--[[ The drop. Everything the press used to do, done now that the player is stood where they want
	the car.

	THE HANDS ARE EMPTIED WHATEVER HAPPENS, AND THAT IS THE DECISION HERE. A drop that finds nowhere
	to put the car (`Placement` exhausted its 24 candidates, the player walked into a race, the car
	was sold out from under them) could keep the toy so they can try again two steps to the left, and
	that is the wrong trade: a toy that cannot be got rid of is a model welded to somebody with no
	way to take it off, which is the failure `GarageService.placeCarried` documents at length. The
	press is one button away and it costs nothing.

	So the toy goes first and the spawn is attempted second, and a refusal reads as the car simply
	not appearing. The reason is logged for us rather than sent, because the only caller is a client
	and a client being told "no" is the ordinary case. ]]
function LobbyCarService._onDropRequest(self, player: Player)
	local toy = LobbyCarConfig.Toy
	if not (LobbyCarConfig.Enabled and toy.Enabled) then
		return
	end

	local now = os.clock()
	local blockedUntil = self._dropCooldowns[player]
	if blockedUntil and now < blockedUntil then
		return
	end
	self._dropCooldowns[player] = now + toy.DropCooldown

	local key = self:getToyCar(player)
	if not key then
		return -- empty hands: the ordinary case for a click with nothing to drop
	end

	self:setToyCar(player, nil)
	local ok, reason = self:setLobbyCar(player, key)
	if not ok then
		self.log:info(string.format("%s's dropped %s did not make it into the lobby (%s).", player.Name, key, reason))
	end
end

-- === The request ============================================================

--[[ Public: stand this player's `key` car in the lobby, or despawn if that is what the request means.

	IT TAKES A CAR KEY (`GarageConfig.carKey` — "Sedan12:6"), not a body name, for the same reason
	`GarageService.setBayCar` does: a player can own the same body in several colours, so "spawn my
	Camaro" no longer has one answer and a caller has to say which one it means.

	Server-authoritative and safe to call from any trusted caller. Every refusal returns a reason
	rather than warning, because the only caller that is not us is a client and a client being told
	"no" is the ordinary case, not an error worth a line in the log. ]]
function LobbyCarService.setLobbyCar(self, player: Player, key: string?, options: SpawnOptions?): (boolean, string)
	if not LobbyCarConfig.Enabled then
		return false, "disabled"
	end

	local current = self:_carOf(player)
	local currentKey = current and current:GetAttribute(LobbyCarConfig.KeyAttribute)

	--[[ Nothing asked for, or the thing already standing there: put it away. Header note on the
		toggle in LobbyCarConfig — the list is the despawner too.

		Compared by KEY, so pressing the black Camaro while the red one is out swaps them rather than
		putting the red one away — which is what the two cards on that screen are for. ]]
	if key == nil or key == currentKey then
		if current then
			self:_despawn(player)
			return true, "despawned"
		end
		return false, "nothing to despawn"
	end

	local RaceService = Shard.get("RaceService")
	if RaceService and RaceService:isRacing(player) then
		return false, "racing"
	end

	local GarageService = Shard.get("GarageService")
	if not GarageService then
		return false, "garage unavailable"
	end
	--[[ Checked BEFORE the key is taken apart, so a client sending a colour it does not own fails
		here rather than being normalised into one it does. The same order `setBayCar` uses. ]]
	if not (options and options.free) and not GarageService:owns(player, key) then
		return false, "not owned"
	end

	local body, paint, mutation = GarageConfig.parseCarKey(key)
	if not (body and paint) then
		return false, "unusable key"
	end

	--[[ PREPARE, THEN REPLACE — never the other way round. The new car is cloned, measured and
		placed while it is still out of the tree, so a request that turns out to have nowhere to go
		leaves the player with the car they already had rather than with nothing. One car per player
		is enforced by the swap below, which is the only place two could ever coexist. ]]
	local car, reason = self:_prepare(player, key, body, paint, mutation, options)
	if not car then
		return false, reason
	end

	if current then
		self:_despawn(player)
	end
	car.Parent = self._folder

	self._cars[player] = car
	self:_publish(player)
	self:getSignal("CarSpawned"):Fire(player, body, car)
	self.log:info(string.format("%s spawned %s in the lobby.", player.Name, key))

	--[[ Last, and on its own thread, because it WAITS: for the car's own scripts to finish wiring
		its seats up, and then for its suspension to settle. Neither of those is anything the caller
		should be held behind, and the one caller there is (`CarDealService._handover`) is running
		inside a `ProximityPrompt.Triggered` handler that has a market to re-roll afterwards.

		So the seat is best-effort and reports itself. `setLobbyCar` returning "spawned" means the
		car is standing there, which is the part a caller can act on. ]]
	if options and options.seat then
		local delay = options.seatDelay
		task.spawn(function()
			self:_seatDriver(player, car, delay)
		end)
	end
	return true, "spawned"
end

--[[ The remote's end of `setLobbyCar` — the rate-limited front door, the same shape as
	`RaceService._onEnterRequest` and `GarageService._onSetBayRequest`, and rate-limited for the
	harder of the two reasons those are: this one CLONES A 310-INSTANCE RIG on the accepted path.
	The cooldown is stamped on the attempt, so a refused request costs a table write. ]]
function LobbyCarService._onSpawnRequest(self, player: Player, key: unknown)
	local now = os.clock()
	local blockedUntil = self._cooldowns[player]
	if blockedUntil and now < blockedUntil then
		return
	end
	self._cooldowns[player] = now + LobbyCarConfig.RequestCooldown

	if key ~= nil and type(key) ~= "string" then
		return
	end

	--[[ THE TOY TAKES THE PRESS, and `setLobbyCar` is not reached until the player clicks
		(`LobbyCarConfig.Toy`). Only the press that means "put this car out" is diverted: everything
		that means "put something away" still happens instantly, because there is nothing to hold
		and nowhere to walk to.

		    key = nil               put away whatever is out. Instant, as before.
		    key = the car out       the same toggle by another name. Instant, as before.
		    key = the toy in hand   pressing the held car again is "never mind": the hands empty and
		                            nothing is spawned. Without this the only way out of holding a
		                            car would be to drop it somewhere.
		    anything else           into the hands.

		OWNERSHIP IS CHECKED BEFORE THE TOY IS HANDED OVER, rather than only at the drop. It is
		checked again at the drop by `setLobbyCar`, which is the check that actually gates the car;
		this one is so that a request for a car the player does not own is refused where every other
		refusal happens, instead of being accepted into a pair of hands and quietly failing later. ]]
	local toy = LobbyCarConfig.Toy
	local wantsToy = LobbyCarConfig.Enabled and toy.Enabled and type(key) == "string"
	if wantsToy then
		local current = self:_carOf(player)
		local currentKey = current and current:GetAttribute(LobbyCarConfig.KeyAttribute)
		if key ~= currentKey then
			if key == self:getToyCar(player) then
				self:setToyCar(player, nil)
				return
			end

			local GarageService = Shard.get("GarageService")
			local RaceService = Shard.get("RaceService")
			if RaceService and RaceService:isRacing(player) then
				return
			end
			if not (GarageService and GarageService:owns(player, key :: string)) then
				self.log:info(string.format("%s asked to hold a %s they do not own.", player.Name, tostring(key)))
				return
			end

			self:setToyCar(player, key :: string)
			return
		end
	end

	--- Either the toy is switched off, or this press is a put-away. Both go straight through, and
	--- a put-away empties the hands on its way past so that a player cannot be left holding a car
	--- they have just decided against.
	self:setToyCar(player, nil)

	local ok, reason = self:setLobbyCar(player, key :: string?)
	if not ok and reason ~= "nothing to despawn" then
		self.log:info(string.format("%s's lobby car request was refused (%s).", player.Name, reason))
	end
end

-- === The pad ================================================================

--[[ The car a pad hands this player: their most valuable starred car, else their most valuable car
	(`LobbyCarConfig.Pad`). Model value, the number the NEW BEST record counts in. nil for nobody's
	collection. ]]
function LobbyCarService._padPick(self, player: Player): string?
	local GarageService = Shard.get("GarageService")
	if not GarageService then
		return nil
	end
	local bestId, bestValue, bestStarred = nil, -1, false
	for _, id in GarageService:ownedIds(player) do
		local body, _paint, mutation = GarageConfig.parseCarKey(GarageConfig.modelKeyOf(id))
		local tier = body and GarageConfig.TierOfBody[body]
		if not tier then
			continue
		end
		local value = GarageConfig.valueOf(tier, mutation)
		local starred = GarageService:isFavorite(player, id) or GarageService:isFavorite(player, GarageConfig.modelKeyOf(id))
		if (starred and not bestStarred) or (starred == bestStarred and value > bestValue) then
			bestId, bestValue, bestStarred = id, value, starred
		end
	end
	return bestId
end

--[[ Where a pad puts the wheels: its `SpotName` attachment, else the middle of its top face. nil
	when another player's car is still standing there, and the caller then places beside the player. ]]
function LobbyCarService._padGround(self, player: Player, pad: BasePart): CFrame?
	local spot = pad:FindFirstChild(LobbyCarConfig.Pad.SpotName)
	local ground = if spot and spot:IsA("Attachment")
		then spot.WorldCFrame
		else pad.CFrame * CFrame.new(0, pad.Size.Y / 2, 0)
	local flat = Vector3.new(ground.LookVector.X, 0, ground.LookVector.Z)
	if flat.Magnitude > 1e-3 then
		ground = CFrame.lookAt(ground.Position, ground.Position + flat, Vector3.yAxis)
	end
	--- Roughly a car's box: only other players' cars are checked, scenery is the pad itself.
	local probe = ground * CFrame.new(0, 3, 0)
	if self:_blockedBy(probe, Vector3.new(8, 4, 16), self:_ignoreList(self:_carOf(player))) == "car" then
		return nil
	end
	return ground
end

function LobbyCarService._onPadPressed(self, player: Player, pad: BasePart)
	local cfg = LobbyCarConfig.Pad
	local now = os.clock()
	if (self._padCooldowns[player] or 0) > now then
		return
	end
	self._padCooldowns[player] = now + cfg.Cooldown

	local id = self:_padPick(player)
	if not id then
		self.log:info(string.format("%s pressed a car pad with no cars.", player.Name))
		return
	end
	--- The picker (`LobbyCarConfig.Pad.Picker`): remember the pad, let the player choose.
	if cfg.Picker then
		self._padPending[player] = { pad = pad, at = now }
		self:getRemoteEvent("OpenCarPadPicker"):Fire(player)
		return
	end
	self:_spawnOnPad(player, pad, id)
end

--[[ A car picked on the SPAWN screen. Every check is against what the SERVER remembers of the press
	(`_onPadPressed`): which pad, how long ago, and whether the player is still by it. The pending
	press is consumed by the first pick, good or bad, so one press is one car. ]]
function LobbyCarService._onPadPick(self, player: Player, key: unknown)
	local cfg = LobbyCarConfig.Pad
	local pending = self._padPending[player]
	self._padPending[player] = nil
	if type(key) ~= "string" or not pending or os.clock() - pending.at > cfg.PickerSeconds then
		return
	end
	local pad = pending.pad
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (pad.Parent and root and root:IsA("BasePart")) or (root.Position - pad.Position).Magnitude > cfg.PickerReach then
		self.log:info(string.format("%s picked a pad car away from the pad; nothing spawned.", player.Name))
		return
	end
	self:_spawnOnPad(player, pad, key)
end

--- Put car `id` on `pad` and (per `Pad.Seat`) the player in it. Ownership is `setLobbyCar`'s check.
function LobbyCarService._spawnOnPad(self, player: Player, pad: BasePart, id: string)
	local cfg = LobbyCarConfig.Pad
	self:setToyCar(player, nil)
	--- A second press brings the car back to the pad rather than putting it away (`Pad` note).
	local current = self:_carOf(player)
	if current and current:GetAttribute(LobbyCarConfig.KeyAttribute) == id then
		self:_despawn(player)
	end
	local ok, reason = self:setLobbyCar(player, id, {
		ground = self:_padGround(player, pad),
		seat = cfg.Seat,
		seatDelay = cfg.SeatDelay,
	})
	if not ok then
		self.log:info(string.format("%s's car pad press was refused (%s).", player.Name, reason))
	end
end

--- One prompt per tagged pad. Default style, so touch gets the engine's own tap target.
function LobbyCarService._wirePad(self, pad: Instance)
	if not pad:IsA("BasePart") or pad:FindFirstChild("LobbyCarPadPrompt") then
		return
	end
	local cfg = LobbyCarConfig.Pad
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LobbyCarPadPrompt"
	prompt.ActionText = cfg.ActionText
	prompt.ObjectText = if cfg.Picker then cfg.PickerObjectText else cfg.ObjectText
	prompt.HoldDuration = cfg.HoldDuration
	prompt.MaxActivationDistance = cfg.MaxDistance
	prompt.RequiresLineOfSight = false
	self._trove:Add(prompt.Triggered:Connect(function(player: Player)
		self:_onPadPressed(player, pad)
	end))
	self._trove:Add(prompt)
	prompt.Parent = pad
end

-- === Lifecycle ==============================================================

--[[ Follow one player's character for as long as they are in the server.

	Death and respawn both put the car away (LobbyCarConfig's `DespawnOnDeath` note), and the
	CharacterAdded half is what covers a respawn that skipped the Died signal — the race's void
	guard exists because this game has produced exactly that, a character that was gone without
	ever having died. ]]
function LobbyCarService._watch(self, player: Player)
	if not LobbyCarConfig.DespawnOnDeath then
		return
	end

	local function bind(character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Once(function()
				self:_despawn(player)
			end)
		end
	end

	if player.Character then
		task.spawn(bind, player.Character)
	end

	-- Per-player trove, dropped on PlayerRemoving. The service-level one would hold a connection to
	-- every player who has ever been in the server, which on a long-lived server is a leak rather
	-- than a tidiness point — the same split PlotService uses for its own per-life connections.
	local trove = Trove.new()
	trove:Add(player.CharacterAdded:Connect(function(character)
		self:_despawn(player)
		bind(character)
	end))
	self._lifeTroves[player] = trove
end

LobbyCarService:withLifecycle({
	init = function(self)
		self._cars = {} -- [Player] = Model
		self._cooldowns = {} -- [Player] = os.clock() before which a request is ignored
		self._lifeTroves = {} -- [Player] = Trove of that player's own connections
		--- [Player] = the car key in their hands, waiting to be dropped. In memory only, and
		--- `LobbyCarConfig.Toy` argues why it is not in the profile.
		self._toys = {}
		--- Separate from `_cooldowns`, because the two cost different things: a refused spawn is a
		--- table write and an accepted one clones a 310-instance rig.
		self._dropCooldowns = {}
		self._padCooldowns = {}
		--- player -> the pad they last pressed and when, for the SPAWN pick (`LobbyCarConfig.Pad.Picker`).
		self._padPending = {} :: { [Player]: { pad: BasePart, at: number } }
	end,

	start = function(self)
		self._trove = Trove.new()

		local folder = workspace:FindFirstChild(LobbyCarConfig.FolderName)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = LobbyCarConfig.FolderName
			folder.Parent = workspace
		end
		self._folder = folder

		-- Racing and showing off are exclusive — LobbyCarConfig note 4.
		local RaceService = Shard.get("RaceService")
		if RaceService then
			self._trove:Add(RaceService:getSignal("RaceEntered"):Connect(function(player: Player)
				--- The toy goes with the car, and for the same reason: the race car IS your car for
				--- the duration. `CarryService` takes the model off the character on this signal
				--- anyway, so leaving the record standing would mean it came back after the run for a
				--- press the player made a lap ago.
				self:setToyCar(player, nil)
				self:_despawn(player)
			end))
		else
			self.log:warn("RaceService unavailable; a lobby car will survive its owner entering a race.")
		end

		--[[ A car you sold cannot go on standing in the street. `GarageService.sellCars` has already
			taken it out of the collection by the time this fires, so leaving it parked would be a car
			nobody owns sitting on the forecourt until the next despawn — and `setLobbyCar` would then
			refuse to put it away, because putting it away means naming a key you no longer own.

			MATCHED ON THE KEY, so selling the black Camaro while the red one is out leaves the red one
			exactly where it is. A SIGNAL rather than GarageService calling in here, because this
			service already depends on that one and the reverse would be a cycle. ]]
		local GarageService = Shard.get("GarageService")
		if GarageService then
			self._trove:Add(GarageService:getSignal("CarsSold"):Connect(function(player: Player, keys: { string })
				--[[ ...AND THE ONE IN THEIR HANDS, which is the same rule one step earlier. Selling
					the car you are holding a toy of leaves you holding a promise the drop would
					refuse, and `setLobbyCar` refusing it is not the failure: being unable to put it
					down is. Checked before the parked car so that a player who sold both is emptied
					of both. ]]
				local toy = self:getToyCar(player)
				if toy then
					for _, sold in keys do
						if sold == toy then
							self:setToyCar(player, nil)
							break
						end
					end
				end

				local car = self:_carOf(player)
				local key = car and car:GetAttribute(LobbyCarConfig.KeyAttribute)
				if type(key) ~= "string" then
					return
				end
				for _, sold in keys do
					if sold == key then
						self:_despawn(player)
						self.log:info(string.format("%s sold %s while it was out; put it away.", player.Name, key))
						return
					end
				end
			end))
		else
			self.log:warn("GarageService unavailable; a sold car will keep standing in the lobby.")
		end

		--- The spawner pads (`LobbyCarConfig.Pad`), found by tag so a map swap brings its own.
		if LobbyCarConfig.Enabled and LobbyCarConfig.Pad.Enabled then
			for _, pad in CollectionService:GetTagged(LobbyCarConfig.Pad.Tag) do
				self:_wirePad(pad)
			end
			self._trove:Add(CollectionService:GetInstanceAddedSignal(LobbyCarConfig.Pad.Tag):Connect(function(pad)
				self:_wirePad(pad)
			end))
		end

		for _, player in Players:GetPlayers() do
			self:_publish(player)
			self:_watch(player)
		end
		self._trove:Add(Players.PlayerAdded:Connect(function(player)
			self:_publish(player)
			self:_watch(player)
		end))
		self._trove:Add(Players.PlayerRemoving:Connect(function(player)
			self:_despawn(player)
			self._cooldowns[player] = nil
			self._toys[player] = nil
			self._dropCooldowns[player] = nil
			self._padCooldowns[player] = nil
			self._padPending[player] = nil
			local trove = self._lifeTroves[player]
			if trove then
				trove:Destroy()
				self._lifeTroves[player] = nil
			end
		end))
	end,
})

return LobbyCarService
