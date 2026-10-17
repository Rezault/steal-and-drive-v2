--[[
	Vehicle  (server logic for a CarBones car)
	------------------------------------------
	The stock CarBones per-car `Vehicle` Script, lifted out of the place and into git.

	Every car model in Workspace.CarSystem used to carry its own full copy of this code
	(4 cars x 14 scripts = 56 copies), which meant a fix had to be hand-applied to each
	one and silently drifted when it wasn't — `Car1` had picked up two stray tabs, and a
	fresh CarBones import would quietly revert the `onExitSeat` nil-check below. Now each
	car carries only a stub:

		-- Workspace.CarSystem.<car>.Scripts.Vehicle  (Script)
		require(game:GetService("ReplicatedStorage").shared.Modules.Vehicle).setup(script)

	Cloning a car in Studio still "just works" — the stub is inert boilerplate that never
	needs patching — but every line worth editing is here.

	PER-CAR STATE: `setup` is called once per car and everything lives in its closure, so
	two cars never share state. That matters, because the sibling modules it requires
	(Chassis, Effects, VehicleSeating) keep their state in module-level upvalues and only
	work because each car has a *private copy* of them under its own Scripts folder. Those
	must stay place-side until they're refactored into classes — do not "finish the job"
	by pointing them at one shared module, or every car on the server shares one steering
	and torque state the moment two players race at once.

	Kept deliberately close to the stock source (including its `ipairs` loops and original
	comments) so it still diffs cleanly against a fresh CarBones import.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Vehicle = {}

-- What `onEnterSeat` hides on the rider so they don't poke through the car body, and
-- `onExitSeat` puts back. Exported because RaceService has to undo this itself: it
-- destroys the car outright on leave, so the exit handler below never gets to run.
Vehicle.HiddenLegParts = { "RightFoot", "RightLowerLeg", "LeftFoot", "LeftLowerLeg" }
Vehicle.HiddenAccessoryAttachments = { "BodyBackAttachment", "WaistBackAttachment", "HatAttachment" }

--[[ Stamp this on a car Model (before it is parented, so `setup` sees it) to keep the stock
	`VehicleSeating` prompt handler off the driver's seat. The caller then owns getting people in.

	THE ONE THING IT BUYS is control over WHEN the player is seated. The stock handler seats you on
	the first line and swings the door on the next, so the door opens around a driver who is already
	in the car — the animation plays, but it reads as scenery rather than as you getting in. There is
	no seam to hook: the sit is `seat:Sit(humanoid)` in the middle of a connected closure in a
	place-side module, and `Seat.Disabled` is not the lever it looks like (measured: `:Sit()` seats
	right through it, and setting it on an OCCUPIED seat ejects the occupant). So the only way to put
	a beat between the door and the driver is to own the trigger.

	IT IS A WITHHOLD, NOT AN EDIT. `setup` renames `PromptLocation` for the duration of the
	`AddSeat` call, so the stock prompt block finds nothing and connects nothing; the rest of
	`AddSeat` — the enter/exit callbacks that deploy the controls, the door sound it clones onto the
	seat — runs untouched, and the name is back before anything can look at it. That matters because
	the name is load bearing elsewhere: the CLIENT's `LocalVehicleSeating.ExitSeat` finds the prompt
	through `Part0.PromptLocation` and checks it is called `EndorsedVehicleProximityPromptV1` before
	running its exit functions, so genuinely renaming the attachment or moving the prompt out of it
	would break getting OUT of the car.

	WHAT THE CALLER INHERITS is everything that block did: enabling the prompt only while the seat is
	empty, the 15-stud reach, the upside-down car flip, and the door beat itself. `LobbyCarService`
	is the only caller and its `_wireEntry` is the reference implementation. Nothing else is affected
	— a race car and a roster master never carry the attribute, so `setup` runs exactly as it did. ]]
Vehicle.DeferredEntryAttribute = "DeferredSeatEntry"

--[[ Stamp this on a car Model (before it is parented, so `setup` sees it) to open its three
	PASSENGER seats. `LobbyCarService` is the only caller; see `LobbyCarConfig.Passengers`.

	=== WHY THE SEATS NEEDED ANYTHING DOING TO THEM AT ALL ======================================

	They are already there. Every one of the sixty-five rigs carries `SeatFR`, `SeatRL` and `SeatRR`
	beside its `VehicleSeat`, `Chassis.GetPassengerSeats` returns all three, `setup` has always run
	`VehicleSeating.AddSeat` over them, and the kit's prompt GUI even ships a separate PASSENGER
	button face for keyboard, gamepad and touch. What none of them carries is a `PromptLocation`
	attachment — and that one missing instance switches the whole seat off at BOTH ends:

	  • `VehicleSeating.AddSeat` reads `seat.PromptLocation` on its first line and connects its
	    entire prompt block inside that `if`. No attachment, no prompt, no way IN. (And the seats are
	    authored `Disabled`, so walking into one does not seat you either.)
	  • `LocalVehicleSeating.ExitSeat` walks the rider's `SeatWeld` back to `Part0`, looks for
	    `PromptLocation`, and checks the prompt inside it is called `EndorsedVehicleProximityPromptV1`
	    before it fires anything. So even a passenger seated by hand had no way OUT — the exit key,
	    the touch ExitButton and the `Passenger` LocalScript's own teardown all hang off that check.

	THIS ONLY FIXES THE SECOND ONE, and that is the whole of its job. The way IN is
	`LobbyCarService._wireEntry`, which now offers the nearest free seat off the car's single driver
	prompt — because four live prompts on one car do not work, and its note is where the measurement
	that proves it lives. So what is raised here is deliberately INERT: an attachment, a prompt by
	the right name, `Enabled = false`, added after the stock code has already looked. It is a shape
	the client insists on finding on the seat it is getting out of, and nothing more.

	CLONED FROM THE DRIVER'S RATHER THAN BUILT, because the name is the API. `Style = Custom`,
	`HoldDuration`, the reach, the keys and above all `EndorsedVehicleProximityPromptV1` all have to
	match what the client's exit path is looking for, and a clone cannot drift from the car it came
	off.

	NOT ON A RACE CAR, A TRAFFIC SHELL OR A ROSTER MASTER. This is the one line every live car runs
	through, so the switch is an opt-in attribute rather than a rule: a race car is on a client-sided
	road with a seat RaceService owns, and the roster masters are the source models nobody is meant
	to touch. Only the lobby asks for this, and only the lobby stamps it. ]]
Vehicle.PassengerEntryAttribute = "LobbyPassengerSeats"

-- The ContextActionService actions the deployed Driver LocalScript binds on the client, which
-- it likewise never gets to unbind — `onEnterSeat` below hands it a ScreenGui and RaceService
-- destroys that GUI outright on leave, killing the script mid-flight. Exported for the same
-- reason as the two lists above: DriveController has to undo this itself. The raw-input one is
-- the dangerous half — it's bound at ContextActionPriority.High, above the PlayerModule's own
-- movement actions, so leaking it sinks WASD and the player can never walk again.
Vehicle.DriverActionNames = { "VehicleChassisRawInput", "VehicleChassisExitVehicle" }

--[[ Stamp this on a car Model while the SERVER is deliberately taking the rider out of the seat and
	putting them straight back — `RaceService._deployDriving`'s occupant toggle, which is how the
	stock controls get deployed on a car that was anchored when the player first sat in it. While it
	is set, `onExitSeat` below does not tell the CLIENT about the exit.

	WHY THE CLIENT MUST NOT HEAR IT. `Remotes.ExitSeat` is not addressed to a seat or to a script: the
	client's `LocalVehicleSeating` calls EVERY registered exit handler on it, and the deployed
	Driver's handler unbinds the driving keys and writes `script.Disabled = true` without asking
	whether this player is still sitting in the car. The toggle sends that remote and then re-seats
	the rider a few frames later, so the fresh Driver the re-seat deploys can register its handler
	BEFORE the client gets around to the remote — and switch itself off on the frame it started. That
	is a car nobody can drive, and one the server cannot even see is broken: `Disabled` was written on
	the client and does not replicate, so `RaceService._hasDriverControls` goes on reporting a healthy
	deploy. Seen in a playtest as a car that would not move on the tutorial's BOOST beat, with the
	world frozen behind it waiting for a throttle that could no longer be pressed.

	SUPPRESSED RATHER THAN REORDERED, because there is no order that works: the exit is real (the
	seat does empty) and the remote is asynchronous. But it is an exit nobody asked for and nobody
	is meant to see — the rider never left the car as far as the run is concerned — so the honest
	thing is not to announce it. Everything else in `onExitSeat` still runs: the engine effects stop
	and restart with the seat, exactly as they do on a re-entry.

	The rest of the leak this used to cover is `DriveController._reviveDriver`, which puts a Driver
	back that switched itself off with the rider still seated — for the exits this attribute cannot
	cover, such as the same remote arriving from a revive's re-deploy. ]]
Vehicle.ReseatAttribute = "ServerReseating"

--[[ Every live car's engine effects, so they can be shut down from OUTSIDE the seat lifecycle.

	`EffectsInstance` is a local inside `setup`: the seat starts it (`onEnterSeat`) and the seat
	stops it (`onExitSeat`), and nothing else can reach it. That covers every ordinary way out of a
	car, and it covers a wreck — the rider is thrown out of the seat, which fires the exit.

	It does NOT cover a getaway. The driver banks the car and rides the truck out still sitting in
	it, so the exit never fires, the effects heartbeat keeps running, and the engine idles on for
	the whole results beat. Worse than merely audible: the stock crossfade drops to the `Idle`
	layer as the RPM decays, and every car authors Idle at Volume 3 against the driving layers'
	0.4 — so a car sitting still inside the truck gets steadily LOUDER than it was at speed.

	Weak-keyed. A race car is a clone that is destroyed at the end of the run and never comes back,
	so entries have to fall out on their own or this grows for the life of the server. ]]
local effectsByCar: { [Model]: any } = setmetatable({}, { __mode = "k" })

--[[ Every live car's seat teardown, so a car can be EMPTIED from outside the seat lifecycle.

	Same weak-keyed shape and the same reason as `effectsByCar` above: `onExitSeat` is a local
	inside `setup`, and the only thing that ever calls it is the seat's own `Occupant` listener.
	That listener covers every way a player gets OUT of a car. It does not cover the car being
	taken out from under them, and `Instance:Destroy()` disconnects it — so a destroyed car runs
	no exit at all. ]]
local evictByCar: { [Model]: () -> () } = setmetatable({}, { __mode = "k" })

--[[ Shut the engine down on a car whose driver is still sitting in it.

	The stock `Effects:Disable()` beat, run by hand: the loops carry on through its half-second
	grace period and then stop with the kit's own `EngineStop` clip — the same shutdown heard on
	every ordinary get-out, and the counterpart to the ignition `onEnterSeat` plays. Idempotent,
	and a no-op on a car that never had a driver. ]]
function Vehicle.silenceEngine(car: Model)
	local effects = effectsByCar[car]
	if effects then
		effects:Disable()
	end
end

--[[ Stand everybody up and run the stock exit teardown on them, before this car is destroyed.

	NOT THE CARJACK PATH. That one is a stranger pressing a prompt to take a car off the person
	driving it, and it is refused outright (`AllowCarjacking`, stamped false below). This is the
	OWNER putting their own car away with somebody still in it, and the only question is whether
	that person is left in one piece.

	They were not. `LobbyCarService._despawn` released the seat and destroyed the car on the next
	line, and both halves of the stock exit were lost:

	  * `Destroy()` DISCONNECTS the seat's `Occupant` listener, and the property change that
	    releasing the seat queues is dispatched after the current resumption point — so the exit
	    callback that listener would have run is disconnected before it is ever dispatched.
	  * Only the OWNER was stood up. Anyone else sitting in the car — which the lobby allows, an
	    empty car is open to whoever walks past — was not touched at all.

	What the lost teardown was carrying: `onEnterSeat` hides the rider's lower legs and feet
	(Transparency 1) so they don't poke through the floor, and only `onExitSeat` puts them back.
	So the driver of a despawned lobby car walked away with no legs — reported in the 16 Aug
	playtest, and visible in the clip as a torso standing in the road one frame after the car
	blinks out. It also carries the control-GUI teardown and the engine shutdown.

	Idempotent, and a no-op on an empty car. The fallback matters: a rig whose `Vehicle` stub has
	not run has no teardown to call, but it can still have somebody welded to it, and leaving them
	welded to a destroyed seat is the one outcome worse than a cosmetic one. ]]
--[[ Has this car's stock `setup` finished wiring its seats up?

	THE QUESTION IS "WILL A `Sit` BE NOTICED", and it has to be asked by anything that seats a driver
	itself rather than through the entry prompt. `VehicleSeating.AddSeat` is what connects the seat's
	`Occupant` listener, and everything a driver needs is on the far side of it: the control GUI, the
	Driver LocalScript, the network handover and the engine. A `Sit` that lands before it produces a
	car with somebody welded into the wheel that will never move, and NOTHING reports it — the seat
	is occupied, the model is complete, and the listener that would have deployed the controls was
	simply not there yet. `onEnterSeat`'s own note records the race arriving from the other
	direction, on a freshly cloned race car.

	`evictByCar` IS THE MARKER RATHER THAN A FLAG OF ITS OWN, because it is written on the line after
	the last `AddSeat` with no yield between the two, so it cannot be true early. A car that is not
	running the stock scripts at all never becomes ready, which is why every caller has to bound its
	wait rather than yield on this forever. ]]
function Vehicle.isReady(car: Model): boolean
	return evictByCar[car] ~= nil
end

function Vehicle.evictOccupants(car: Model)
	local evict = evictByCar[car]
	if evict then
		evict()
		return
	end

	for _, inst in car:GetDescendants() do
		if inst:IsA("Seat") or inst:IsA("VehicleSeat") then
			local occupant = (inst :: Seat).Occupant
			if occupant then
				occupant.Sit = false
			end
		end
	end
end

--[[ Is this part being held still by an anchor?

	`RaceService._setCarFrozen` anchors every BasePart in the car, so the part's own flag answers it
	in the case that matters; the root check covers a car held by one anchored member instead, which
	is the same thing as far as the network-ownership API is concerned ("…or parts welded to Anchored
	parts"). A part that is not in the workspace has no root, and nothing may be assigned on it
	either — so no root reads as "don't try", which is what the caller wants. ]]
local function isAnchored(part: BasePart): boolean
	if part.Anchored then
		return true
	end
	local root = part.AssemblyRootPart
	return root == nil or root.Anchored
end

--[[ Give one passenger seat the `PromptLocation` its rig shipped without, so the stock kit can see
	it. Returns the prompt, or nil if there was nothing to do or nothing to copy.

	WHERE IT FLOATS. The driver's attachment sits at a fixed local offset from its seat — the same
	(-1.87, 6, 0) on all sixty-five rigs, six studs up and a stud and a bit OUTBOARD of the door it
	belongs to. Every passenger seat in the pack is axis-aligned with the driver's (measured: 0.00
	degrees of relative yaw on every body), so the offset transfers as-is; only its side has to be
	decided, and the seat's own lateral position answers that. `SeatFR` and `SeatRR` sit 3.42 studs
	across the car from the driver and get the mirrored X; `SeatRL` is directly behind the driver and
	keeps it. Written as a LOCAL `CFrame` on an attachment that is already parented, which is the
	only form of this that cannot be misread as a world offset.

	FOUR PROMPTS, ONE ON SCREEN. The clone inherits `Exclusivity = OnePerButton`, so all four seats
	sharing E means the engine draws whichever is nearest and no other. That is the behaviour we
	want and it is inherited rather than chosen: walk to a door and you are offered that door's
	seat.

	A SEAT THAT ALREADY HAS ONE IS LEFT ALONE. The four authored rigs (the reference chassis, its
	backup, Car1 and the Lambo) are the reason: if a body ever ships passenger prompts of its own,
	they are the ones the artist positioned. ]]
local function raisePassengerPrompt(seat: BasePart, driverSeat: BasePart): ProximityPrompt?
	if seat:FindFirstChild("PromptLocation") then
		return nil
	end

	local template = driverSeat:FindFirstChild("PromptLocation")
	if not (template and template:IsA("Attachment")) then
		return nil
	end
	local source = template:FindFirstChildWhichIsA("ProximityPrompt")
	if not source then
		return nil
	end

	local location = Instance.new("Attachment")
	location.Name = "PromptLocation"
	location.Parent = seat

	-- Across the car from the driver, or behind them? A stud of slack, because "directly behind"
	-- measures as a few ten-thousandths rather than as zero.
	local offset = template.Position
	local across = math.abs(driverSeat.CFrame:ToObjectSpace(seat.CFrame).Position.X) > 1
	local sideways = if across then -offset.X else offset.X
	location.CFrame = CFrame.new(sideways, offset.Y, offset.Z)

	local prompt = source:Clone()
	--- Never drawn — `Style = Custom` means the kit's own GUI paints this prompt, and that GUI reads
	--- neither string. Set anyway so the Explorer says what the seat is during a playtest, which is
	--- the only place these two ever show up.
	prompt.ActionText = "Ride"

	--[[ AND IT NEVER LIGHTS. This prompt is a shape the client's exit path insists on finding, not a
		way in — `LobbyCarService._wireEntry` is the way in, for all four seats, and its note explains
		at length why four live prompts on one car cannot work (they all share E, the engine shows one
		and does not pick the nearest, and the driver's seat loses).

		Two things keep it dark and both are needed. `Enabled = false` is the obvious one. The other
		is WHEN this runs: `raisePassengerPrompt` is called AFTER `VehicleSeating.AddSeat` has already
		read this seat for a `PromptLocation` and found none, so the stock prompt block connects
		nothing — which matters because that block's `setCarjackPrompt` writes `Enabled = true` every
		time the seat empties, and would otherwise switch this back on the first time somebody got
		out of the back. ]]
	prompt.Enabled = false
	prompt.Parent = location
	return prompt
end

--[[ 2026-10-12: the one prompt GUI serves every car and must survive its donor streaming out.
	Publish the unchanged kit libraries, including their image children, outside Workspace before
	deploying that GUI. No yields between the existence check and parenting: concurrent car setups
	must publish one complete copy, never expose half a library or share chassis state. ]]
function Vehicle._publishPromptAssets(scripts: Instance): ()
	local modules = script.Parent
	if modules:FindFirstChild("VehiclePromptAssets") then
		return
	end
	local assets = Instance.new("Folder")
	assets.Name = "VehiclePromptAssets"
	for _, name in { "Keymap", "InputImageLibrary" } do
		local library = scripts:FindFirstChild(name)
		assert(library and library:IsA("ModuleScript"), "Vehicle prompt library missing: " .. name)
		library:Clone().Parent = assets
	end
	assets.Parent = modules
end

-- `vehicleScript` is the per-car stub Script: its parent is the car's Scripts folder and
-- its grandparent is the car model, exactly as the stock script assumed of itself.
function Vehicle.setup(vehicleScript: Script)
	local Scripts = vehicleScript.Parent
	local TopModel = Scripts.Parent

	local UniqueName = TopModel.Name .. "_" .. HttpService:GenerateGUID()

	local ChassisModel = TopModel.Chassis
	local EffectsFolder = TopModel.Effects

	-- Per-car copies by design — see PER-CAR STATE in the header.
	local Effects = require(Scripts.Effects)
	local Chassis = require(Scripts.Chassis)
	local VehicleSeating = require(Scripts.VehicleSeating)
	local RemotesFolder = TopModel.Remotes
	local BindableEventsFolder = TopModel.BindableEvents

	-- LocalScripts that are cloned and deployed
	local DriverScriptPrototype = Scripts.Driver
	local PassengerScriptPrototype = Scripts.Passenger
	local LocalGuiModulePrototype = Scripts.LocalVehicleGui

	-- Note that this has not been refactored into a class yet
	Chassis.InitializeDrivingValues()

	-- This module is a class with a new() constructor function
	local EffectsInstance = Effects.new(ChassisModel, EffectsFolder, TopModel)
	-- Published for `Vehicle.silenceEngine` — see the note on `effectsByCar`.
	effectsByCar[TopModel] = EffectsInstance

	VehicleSeating.SetRemotesFolder(RemotesFolder)
	VehicleSeating.SetBindableEventsFolder(BindableEventsFolder)

	local CharacterRemovingConnection = nil

	local DriverSeat = Chassis.GetDriverSeat()
	local AdditionalSeats = Chassis.GetPassengerSeats()

	local function setHatsAndLegsTransparency(obj, transparency)
		-- Nothing to strip if there's no occupant. The `if not obj` below only covers a Player with
		-- no Character; this covers being handed nothing at all (see onExitSeat).
		if not obj then
			return
		end

		if obj:IsA("Humanoid") then
			obj = obj.Parent
		elseif obj:IsA("Player") then
			obj = obj.Character
		end

		if not obj then
			return
		end

		for _, child in ipairs(obj:GetChildren()) do
			if child:IsA("Accoutrement") then
				local handle = child:FindFirstChild("Handle")
				if handle then
					local shouldRemove = false
					for _, attachmentName in ipairs(Vehicle.HiddenAccessoryAttachments) do
						if handle:FindFirstChild(attachmentName) then
							shouldRemove = true
						end
					end

					if shouldRemove then
						handle.Transparency = transparency
					end
				end
			end
		end

		for _, legName in ipairs(Vehicle.HiddenLegParts) do
			local legPart = obj:FindFirstChild(legName)
			if legPart then
				legPart.Transparency = transparency
			end
		end
	end

	-- `obj` can be nil. VehicleSeating only remembers an occupant if it observed the matching
	-- ENTER, so a seat that empties without one calls this with nothing to clean up. That is not
	-- hypothetical: a freshly cloned car's Occupant listener isn't connected yet when RaceService
	-- first seats the player, so the enter goes unseen -- and the occupant toggle it then uses to
	-- deploy the driver controls on the live car fires an exit with currentOccupant still nil.
	-- The SEAT half of the teardown below still has to run either way; only the occupant half is
	-- skipped.
	local function onExitSeat(obj, seat)
		if obj and obj:IsA("Player") then
			--- Not while the server is mid-reseat: that exit is one it is about to undo, and the
			--- client would answer it by switching off the controls the re-seat deploys. See
			--- `Vehicle.ReseatAttribute`.
			if not TopModel:GetAttribute(Vehicle.ReseatAttribute) then
				RemotesFolder.ExitSeat:FireClient(obj, false)
			end

			local playerGui = obj:FindFirstChildOfClass("PlayerGui")
			if playerGui then
				local scriptContainer = playerGui:FindFirstChild(UniqueName .. "_ClientControls")
				if scriptContainer then
					scriptContainer:Destroy()
				end
			end
		end

		setHatsAndLegsTransparency(obj, 0)

		if obj and obj:IsA("Humanoid") then
			obj.Sit = false
		end

		if CharacterRemovingConnection then
			CharacterRemovingConnection:Disconnect()
			CharacterRemovingConnection = nil
		end

		if seat == DriverSeat then
			--[[ GUARDED FOR THE SAME REASON AS THE `SetNetworkOwner` IN `onEnterSeat`, and it is the
				same one line's worth of throw: ownership cannot be assigned on an anchored assembly,
				and it cannot be assigned on a seat that is no longer in the workspace either — which
				is exactly the seat `Vehicle.evictOccupants` hands this, a frame before the car is
				destroyed. `isAnchored` answers both (no root reads as "don't try").

				Unguarded it does not merely fail: it throws PAST the two lines below, so the wreck
				you were thrown out of keeps its engine running and `Chassis` keeps the steering
				state of a car nobody is in. ]]
			if not isAnchored(DriverSeat) then
				DriverSeat:SetNetworkOwnershipAuto()
			end
			Chassis.Reset()
			EffectsInstance:Disable()
		end
	end

	local function onEnterSeat(obj, seat)
		if seat and seat.Occupant then
			local ShouldTakeOffHats = true
			local prop = TopModel:GetAttribute("TakeOffAccessories")

			if prop ~= nil then
				ShouldTakeOffHats = prop
			end

			if ShouldTakeOffHats then
				setHatsAndLegsTransparency(seat.Occupant, 1)
			end
		end

		if not obj:IsA("Player") then
			return
		end

		local playerGui = obj:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			local screenGui = Instance.new("ScreenGui")
			screenGui.Name = UniqueName .. "_ClientControls"
			screenGui.ResetOnSpawn = true
			screenGui.Parent = playerGui

			CharacterRemovingConnection = obj.CharacterRemoving:Connect(function()
				onExitSeat(obj)
			end)

			local localGuiModule = LocalGuiModulePrototype:Clone()
			localGuiModule.Parent = screenGui

			if seat == DriverSeat then
				local driverScript = DriverScriptPrototype:Clone()
				driverScript.CarValue.Value = TopModel
				driverScript.Parent = screenGui
				driverScript.Disabled = false

				--[[ NOT UNGUARDED, AND THIS ONE LINE WAS A BUG WITH THREE FACES.

					`SetNetworkOwner` throws on an anchored assembly, and RaceService seats a driver
					in an anchored car twice a race: on entry, while the client's local road is still
					being built, and again on a revive, while the car is being set back down on the
					lane. Entry never showed it — that first Sit lands before this car's freshly
					cloned Occupant listener is connected, so `onEnterSeat` simply never ran. A
					revive is the same Sit on a car whose listener HAS been up for the whole race, so
					it ran, and threw here.

					Throwing here does not abort a small tail; it abandons the deploy halfway. The
					ScreenGui and the Driver LocalScript above are already parented, but the
					`ScriptsReference` below never is — and that is precisely what `LocalVehicleGui`
					waits for, which is the Driver's very first require. So the player got: a car
					that would not move (the input loop is past that require, and so is
					`ProximityPromptService.Enabled = false`, hence the "E to get in" prompt over
					their own occupied car), no engine effects, an infinite-yield warning naming a
					GUI rather than this, and — worst — a control GUI complete enough that
					`RaceService._hasDriverControls` counted it as deployed and never repaired it.

					Skipping is correct rather than merely safe: whoever anchored the car owns
					handing it over, and RaceService does exactly that on the line it thaws (see
					`_onRaceReady` and `reviveRace`). Everything below then gets to run, which is the
					actual fix. ]]
				if not isAnchored(DriverSeat) then
					DriverSeat:SetNetworkOwner(obj)
				end
				EffectsInstance:Enable()
			else
				local passengerScript = PassengerScriptPrototype:Clone()
				passengerScript.CarValue.Value = TopModel
				passengerScript.Parent = screenGui
				passengerScript.Disabled = false
			end

			local scriptsReference = Instance.new("ObjectValue")
			scriptsReference.Name = "ScriptsReference"
			scriptsReference.Value = Scripts
			scriptsReference.Parent = screenGui
		end
	end

	--[[ NOBODY GETS PULLED OUT OF A CAR THEY ARE DRIVING. Stamped here rather than authored,
		and set before `AddSeat` connects so the very first seat this car sees is already
		governed by it.

		`VehicleSeating` ships a CARJACK path: its seat prompt normally hides itself once the
		seat is occupied, but if the car model carries `AllowCarjacking` the prompt stays up and
		triggering it EJECTS THE CURRENT OCCUPANT and seats the presser instead. Every one of the
		65 rigs in `Workspace.CarSystem` was imported from the car packs with that attribute
		authored TRUE, so in the lobby any player could walk up to the car you had just spawned
		and take it off you mid-drive — reported in the 16 Aug playtest and not a mechanic this
		game has ever wanted. The steal IS the game, but a steal is the bail-and-land beat on a
		client-sided road (`StealController`), which shares no code with this and cannot use a
		ProximityPrompt at all (`StealConfig`, "NOT A ProximityPrompt").

		HERE, AND NOT ON THE 65 RIGS, for the reason `CarConfig` gives at length about the tuning
		attributes it replaced: a place-file attribute is not in git, does not diff, and does not
		survive a re-import of the car pack. This is the one line every live car runs through —
		roster masters, lobby cars, race cars — so it is also the only place the rule cannot be
		half-applied.

		FALSE rather than nil, so the attribute is still visible in the Explorer during a
		playtest and reads as a decision instead of an omission. An empty seat is unaffected:
		the stock handler only consults it once there is someone to evict, so anyone may still
		get into a car nobody is sitting in. ]]
	TopModel:SetAttribute("AllowCarjacking", false)

	--[[ Listen to seat enter/exit.

		The driver's seat may have its prompt handler withheld — see `Vehicle.DeferredEntryAttribute`
		for what that is for and why it is done by hiding the attachment's NAME rather than by
		unparenting the prompt. `AddSeat` reads `PromptLocation` on its first line and never yields
		before it, so the rename is over inside one call and no client ever sees it.

		THE PASSENGER SEATS BELOW ARE THE MIRROR IMAGE: they carry no prompt, and on a car that has
		asked for riders (`Vehicle.PassengerEntryAttribute`) an inert one is raised for them just
		AFTER the same first line has looked and found nothing. Withheld by timing rather than by a
		rename, but withheld for the same reason — nothing of the stock prompt block may connect to
		these seats. `LobbyCarService._wireEntry` is the way into all four. ]]
	local promptLocation = DriverSeat:FindFirstChild("PromptLocation")
	local withheld = promptLocation and TopModel:GetAttribute(Vehicle.DeferredEntryAttribute) == true
	if withheld then
		promptLocation.Name = "PromptLocationDeferred"
	end

	VehicleSeating.AddSeat(DriverSeat, onEnterSeat, onExitSeat)

	if withheld then
		promptLocation.Name = "PromptLocation"
	end

	--- AFTER `AddSeat`, never before — see `raisePassengerPrompt`. The stock prompt block has to
	--- have already looked at this seat and found nothing, or it connects a handler that switches
	--- the attachment's prompt back on every time the seat empties.
	local ridable = TopModel:GetAttribute(Vehicle.PassengerEntryAttribute) == true
	for _, seat in ipairs(AdditionalSeats) do
		VehicleSeating.AddSeat(seat, onEnterSeat, onExitSeat)
		if ridable then
			raisePassengerPrompt(seat, DriverSeat)
		end
	end

	--[[ The teardown `Vehicle.evictOccupants` reaches in and runs — see the note on `evictByCar`.

		THE UNSEAT COMES FIRST and the teardown second, which is the order an ordinary get-out
		happens in: leaving the seat occupied while `onExitSeat` hands the car back and resets the
		chassis would be resetting a car somebody is still sitting in.

		`GetPlayerFromCharacter` and not the Humanoid, because that is what the seat's own listener
		passes (`VehicleSeating.AddSeat` resolves the occupant to a Player if it can) and the whole
		point is to run the identical handler. The Humanoid is the fallback for a seated NPC, and
		`onExitSeat` stands that one up itself. ]]
	evictByCar[TopModel] = function()
		local seats = { DriverSeat }
		for _, seat in ipairs(AdditionalSeats) do
			table.insert(seats, seat)
		end

		for _, seat in ipairs(seats) do
			local occupant = seat.Occupant
			if occupant then
				local player = Players:GetPlayerFromCharacter(occupant.Parent)
				occupant.Sit = false
				onExitSeat(player or occupant, seat)
			end
		end
	end

	local function playerAdded(player)
		Vehicle._publishPromptAssets(Scripts)
		local playerGui = player:WaitForChild("PlayerGui")

		if not playerGui:FindFirstChild("VehiclePromptScreenGui") then
			local screenGui = Instance.new("ScreenGui")
			screenGui.ResetOnSpawn = false
			screenGui.Name = "VehiclePromptScreenGui"
			screenGui.Parent = playerGui

			local newLocalVehiclePromptGui = Scripts.LocalVehiclePromptGui:Clone()
			newLocalVehiclePromptGui.CarValue.Value = TopModel
			newLocalVehiclePromptGui.Parent = screenGui
		end
	end

	Players.PlayerAdded:Connect(playerAdded)

	for _, player in ipairs(Players:GetPlayers()) do
		playerAdded(player)
	end
end

return Vehicle
