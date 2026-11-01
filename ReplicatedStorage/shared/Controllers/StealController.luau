--[[
	StealController  (client)
	-------------------------
	The steal (GDD §3.4, `docs/StealMechanic_Plan.md`): tap Space, your driver leaps out of the car,
	you fall toward a car ahead, and you press E to take it. Six states, four of which are new:

	    Driving --SPACE--> Bailing --~0.12s--> Airborne --E, near a car--> Mounted --> Driving
	                                              |                          ^
	                                              |  arc ends, car in reach  | E
	                                              \------------------------> Perched --0.45s--> Wrecked
	                                              \--arc ends, nothing near--------------------> Wrecked

	NOTHING TAKES A CAR ON ITS OWN. Touching a roof used to mount you on contact; now it parks you on
	it and E is the commit, with `Perched` holding that offer open for a beat after the arc is over so
	a late press still counts (`StealConfig.Prompt`). `Prompt.Enabled = false` collapses this back to
	the original four-state machine, contact-mount and all.

	THE SPINE: THE PLAYER NEVER LEAVES THEIR SEAT.

	The naive steal destroys your car, spawns the target as a real car and seats you in it. Do not
	build that. `RaceService.enterRace` costs a clone, a freeze, a `Sit`, a wait for the client's
	road ack, an unfreeze, a `SetNetworkOwner` and then `_deployDriving`'s eject/re-sit loop, which
	retries four times and waits twenty frames a pass for the stock `Driver` LocalScript to appear
	in PlayerGui. That whole sequence is why entering a race happens behind a fade. It cannot
	happen five times a run, at speed, in the open.

	So instead:

	  1. Space HIDES the seated rider — not the car — and spawns a FLIGHT AVATAR, a clone of the
	     character, anchored and CFrame-driven, at the seat. That clone is the thing the player
	     follows through the air. The rider has to go because they are welded into a seat that is
	     still on screen, and two copies of the player is worse than none.
	  2. The real car stays seated, network-owned, VISIBLE and ANCHORED, and is flown along the deck
	     with its door up — you watch it carry on down the lane you left it in. It is still the road
	     anchor: `RoadController._car` is latched once at RaceStart from `humanoid.SeatPart` and
	     `_loop` only ever reads `car.PrimaryPart.Position`, so tile recycling, rebasing, traffic
	     streaming and obstacle building all carry on with ZERO changes. It tracks the flight ALONG
	     the road for exactly that reason and deliberately does not track it ACROSS — see `_flyCar`.
	  3. E commits. The car WEARS THE SHELL'S BODY — its meshes are grafted onto the same chassis mounts
	     the old ones hung off (`Modules/CarBody`) — and is then teleported onto the shell's pose,
	     unanchored, given the shell's velocity and re-stamped with its tier, and the shell is recycled
	     back into the traffic pool. Same chassis, same seat, same `Scripts.Chassis` the DriveController
	     shim has wrapped, same collision group, same network ownership. You drive off in the car you
	     landed on, not in your own car in its colours.

	A STEAL IS A REDRESS, NOT A SPAWN (Modules/CarBody). No unseat, no re-deploy, no handshake, no
	fade — and specifically none of these three, each of which is a bug this repo has already paid
	for once:

	  • `humanoid.Sit = false` takes ~5 PHYSICS FRAMES to release, and anything written inside that
	    window is silently lost or flings the player (`RaceService._returnToSpawn`). A steal that
	    unseated would have to eat that latency at the start of a timing-based input.
	  • Destroying the deployed `_ClientControls` GUI leaks the stock Driver's ContextActionService
	    bindings — at priority 3000, sinking WASD for the rest of the session — and its
	    `ProximityPromptService.Enabled = false`. Tolerable once per race. Not five times a run.
	  • `_deployDriving`'s toggle exists because the FIRST `Sit` can't deploy controls at all.

	EVERYTHING IS IN THE ROAD'S FRAME. The arc is integrated by hand as (`along` down the drive
	direction, `cross` across it, `y` world-up), exactly the way TrafficController keeps its cars.
	Two things fall out of that for free: the touchdown point can simply be RUN FORWARD on a scratch
	copy of the flight (`_predict` steps the same `_advance` the flight does, which is what the
	ground marker reads out), and a world rebase mid-flight is one addition (`_onWorldShift`)
	instead of a mystery.

	THE ARC IS LOPSIDED — thrown up fast, floated down slow, and braked toward traffic pace on the
	way (StealConfig.Flight). That isn't decoration: the slow half is the half you steer in, and the
	brake is what keeps you over the car you picked, which is in turn what lets the ground marker sit
	honestly UNDER the avatar instead of seventy studs down the road (`Marker.Lead`). It has to be handled by hand, note: the
	flight avatar is NOT the character, so `RoadController._shiftWorld`'s character pass does not
	move it.

	THE CLIPS HAVE ARRIVED AND THE STATES WERE ALREADY SHAPED FOR THEM (StealConfig.Animations).
	Four, on two rigs: *Bail* across the launch and the rise, *FreeFall* looping down the arc,
	*Land* over the whole mount, and *DriverThrown* on an NPC — wearing one of your actual friends'
	avatars, where the friends list answers (StealConfig.Driver.Friends) — that only exists for that
	beat. The one thing that changed shape to fit them is `Mount.Time` — a 0.3s dead-air handoff
	became a 1.63s landing you watch, on a car that keeps driving under you, with its door swinging
	(`Modules/ShellDoors`) and its driver going over the side. Everything else was already a timed
	state with nothing in it.

	WHAT THIS PASS STILL DOES NOT DO, deliberately: no slow motion (`StealConfig.SlowMo.Enabled` is
	false; the plumbing is in via Modules/TimeScale, and the clips are wired to it), no splat clip on
	the whiff (the ragdoll is the read), no silhouette driver in the cars you DON'T steal, and no
	chase behaviour. Plan §6 phase 6.

	One cosmetic edge worth knowing before it's reported as a bug: the hidden car keeps its collision
	group while airborne, so a knocked traffic car tumbling into the space it occupies bounces off an
	invisible wall. It's anchored, so nothing moves and nothing breaks — and turning collision off
	would mean restoring per-part `CanCollide` on a suspension the handoff is about to re-simulate,
	which is a worse trade for a ~1.2 second window.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
-- A config-only dependency: the boarding attribute gates bail without a controller start cycle.
local GetawayConfig = require(ReplicatedStorage.shared.Configs.GetawayConfig)
--- Which mutations take no Highlight, so the locked car is boxed instead (`_updateMarker`).
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
local StealConfig = require(ReplicatedStorage.shared.Configs.StealConfig)
--- The steal's sounds, punches and toast — feedback only; the mechanics stay `StealConfig`'s.
local StealJuiceConfig = require(ReplicatedStorage.shared.Configs.StealJuiceConfig)
--- Whether a steal reports the car's issued token rather than its tier (`EncounterConfig`).
local EncounterConfig = require(ReplicatedStorage.shared.Configs.EncounterConfig)
local CollectorConfig = require(ReplicatedStorage.shared.Configs.CollectorConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
local CarConfig = require(ReplicatedStorage.shared.Configs.CarConfig)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local CarBody = require(ReplicatedStorage.shared.Modules.CarBody)
local CarDoors = require(ReplicatedStorage.shared.Modules.CarDoors)
--- Only for how long a revive holds the car frozen (`_onRevived`, after a missed jump).
local ReviveConfig = require(ReplicatedStorage.shared.Configs.ReviveConfig)
local CarDoorRig = require(ReplicatedStorage.shared.Modules.CarDoorRig)
local CarMutation = require(ReplicatedStorage.shared.Modules.CarMutation)
--- The stolen car's rarity band, for the cinematic's `MinBand` gate.
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarStats = require(ReplicatedStorage.shared.Modules.CarStats)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local Ragdoll = require(ReplicatedStorage.shared.Modules.Ragdoll)
local RigAnimator = require(ReplicatedStorage.shared.Modules.RigAnimator)
local NpcFriends = require(ReplicatedStorage.shared.Modules.NpcFriends)
local ShellDoors = require(ReplicatedStorage.shared.Modules.ShellDoors)
local TimeScale = require(ReplicatedStorage.shared.Modules.TimeScale)
local Vehicle = require(ReplicatedStorage.shared.Modules.Vehicle)

local StealController = Shard.new("StealController"):withDependencies({
	"RoadController",
	"DriveController",
	"TrafficController",
	"ObstacleController",
	"RaceCameraController",
	"WindController",
})

-- The `car ui.psd` kit's typeface, the same line every sign, page and prompt in the place is
-- set in. The steal prompt was in GothamBold until 2026-08-25; see `StealConfig.Prompt`.
local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

-- ContextActionService unbinds by name, so this is one shared name for the session.
local ACTION_NAME = "StealBail"
local ACTION_STEAL = "StealTake"

-- Per-second rate the tarmac perch bleeds the arc's along-speed at while the prompt window is open.
-- Gentle: over a full `Prompt.Grace` it sheds about a third, which reads as sliding to a stop rather
-- than as landing in glue.
local PERCH_SLIDE_EASE = 1.2

--[[ Sign of a `steer` value that moves the player toward the road's LEFT — i.e. toward +cross,
	which RoadController derives as `Y x forward`. Derived from DriveConfig exactly the way
	DriveController derives its own copy, so air control and the lane change can never disagree
	about which way the stick is pointing. ]]
local STEER_LEFT = if DriveConfig.PositiveSteerIsLeft then 1 else -1

-- Name of the client-only folder the flight avatar lives in.
local FLIGHT_FOLDER = "StealFlight"

--[[ Hard stop on how many pages of the friends list `_friendIds` will walk, whatever `Friends.Scan`
	asks for. A FriendPages page is 50, so this reaches the 200-friend cap in one pass and still
	terminates if the endpoint ever answers "not finished" without advancing. ]]
local MAX_FRIEND_PAGES = 4

--[[ The classic noob, worn by the fallback motorist when the friends list has nothing for us.

	AN EMPTY `HumanoidDescription` IS NOT A DEFAULT AVATAR — it is a BLACK one. Every colour field on
	a fresh description sits at `Color3.new()`, so the rig it builds comes out a solid black
	silhouette with no shirt, which on a sunlit road reads as a missing texture or a shadow rather
	than as a person. Measured off the built rig; it is what the first version of this shipped.

	So the fallback is dressed on purpose, in the one palette that says "a person we know nothing
	about" and is recognised on sight: yellow head and arms, blue torso, green legs. It costs four
	colour writes, needs no asset id in the place or in git, and cannot go missing. ]]
local NOOB_COLORS = {
	Head = Color3.fromRGB(245, 205, 48), -- Bright yellow
	Torso = Color3.fromRGB(13, 105, 172), -- Bright blue
	Arm = Color3.fromRGB(245, 205, 48),
	Leg = Color3.fromRGB(164, 189, 71), -- Br. yellowish green
}

--[[ Seconds before the bail clip runs out that the freefall loop is crossfaded in, measured in
	FLIGHT time — the same scaled clock the arc integrates on, so a dip into slow motion stretches
	the clip and this handover together (see StealConfig.Animations). Sized to the crossfade itself:
	starting the fade this far out means the flip is fully weighted at the instant the throw ends,
	rather than the body hanging in the bail's last pose for the length of a fade. ]]
local FALL_LEAD = 0.12
--[[ Studs a shoved car is put PAST the overlap line rather than exactly on it (`_clearLanding`).

	Landing a car on the boundary of the test that just rejected it invites the same frame's physics
	step to find them touching anyway, and a contact is all it takes — the whole point of the shove
	is that the solver is handed two bodies that are apart. Small enough to be invisible next to a
	shove measured in studs, big enough to survive the rounding in a dot-product road frame. ]]
local CLEAR_EPSILON = 0.25

-- === Road frame =============================================================

-- World position of a point in the road frame. `forward`, `cross` and `yAxis` are the three world
-- axes (the road contract's ForwardAxis is X, Y or Z), so this composition is exact rather than
-- approximate — the same one TrafficController._worldPos and ObstacleController use.
function StealController._worldPos(self, along: number, crossOffset: number, y: number): Vector3
	local info = self._info
	return info.forward * along + info.cross * (info.driveCenter + crossOffset) + Vector3.yAxis * y
end

-- The road-frame coordinates of a world position. Inverse of the above.
function StealController._roadCoords(self, pos: Vector3): (number, number, number)
	local info = self._info
	return pos:Dot(info.forward), pos:Dot(info.cross) - info.driveCenter, pos.Y
end

-- === Hiding =================================================================

--[[ Make a whole tree invisible and remember exactly how it looked, so it can be put back.

	Transparency alone is not enough on a car: the CarBones rig carries engine particles, exhaust
	trails and lights under `Effects/`, and a "hidden" car still trailing smoke down the road is
	the single most obvious tell there is. Emitters and lights are switched off alongside.

	Restoring captured values rather than zeroing is what keeps this correct over the things that
	were ALREADY invisible — the chassis `HitBox`, the query volumes, and the rider's legs and
	accessories, which the stock vehicle script hides on entering the seat and would otherwise
	come back at full opacity poking through the bodywork. ]]
local function hideTree(root: Instance)
	local transparency, enabled = {}, {}
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
			transparency[inst] = inst.Transparency
			inst.Transparency = 1
		elseif
			inst:IsA("ParticleEmitter")
			or inst:IsA("Trail")
			or inst:IsA("Beam")
			or inst:IsA("Smoke")
			or inst:IsA("Fire")
			or inst:IsA("Sparkles")
			or inst:IsA("Light")
		then
			enabled[inst] = inst.Enabled
			inst.Enabled = false
		end
	end
	return { transparency = transparency, enabled = enabled }
end

local function restoreTree(state)
	if not state then
		return
	end
	for inst, value in state.transparency do
		if inst.Parent then
			inst.Transparency = value
		end
	end
	for inst, value in state.enabled do
		if inst.Parent then
			inst.Enabled = value
		end
	end
end

-- === The flight avatar ======================================================

--[[ The thing the player actually watches during a bail: a clone of their character, anchored and
	driven by CFrame.

	THE HUMANOID IS DESTROYED, not disabled. Without one the rig is simply parts joined by Motor6Ds
	— but it comes back **with no clothes on**, and that is not a subtle failure: `Shirt`, `Pants`
	and `ShirtGraphic` are only rendered on a model that CONTAINS A HUMANOID, and layered clothing
	accessories need one to drive their `WrapLayer` deformation. Strip the Humanoid and the player
	watches a naked mannequin fly out of their car. (Measured — this shipped in the first build.)

	So the Humanoid stays and is simply switched off: `EvaluateStateMachine = false` stops the state
	machine outright, `PlatformStand` keeps it limp, and the root is anchored so nothing can move it
	anyway. Its own `Animator` is where Phase 5's flight clips will play from, which is a better home
	for them than a bolted-on AnimationController would have been. The name and health bars are
	turned off because this is a puppet, not a player.

	The legs and back/hat accessories are put BACK to opaque, because the source character has them
	hidden: the stock vehicle script's `onEnterSeat` strips them so the rider doesn't poke through
	the bodywork, and a clone taken from a seated driver inherits a driver with no feet. Reusing
	`Vehicle`'s own two lists means a redress that changes what gets hidden changes it here too.

	`Archivable` HAS TO BE FLIPPED FIRST, and this is not defensive coding — Roblox ships player
	characters with `Archivable = false`, and `Clone()` on a non-archivable instance doesn't error,
	it quietly returns nil. Measured: the first build of this fell straight through to the
	placeholder on every single bail, with a warning that read like a rig problem. Put back
	afterwards, because it's a property of the live character and not ours to leave changed.

	Returns nil on failure and the caller substitutes a plain block, because a bail that silently
	puts nothing on screen is far worse than one that puts a placeholder there. ]]
function StealController._buildAvatar(self, cframe: CFrame): Model?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end

	local archivable = character.Archivable
	character.Archivable = true
	local ok, clone = pcall(function()
		return character:Clone()
	end)
	character.Archivable = archivable
	if not (ok and clone) then
		self.log:warn("Could not clone the character for a flight avatar; flying a placeholder.")
		return nil
	end

	for _, inst in clone:GetDescendants() do
		if inst:IsA("BaseScript") then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
			inst.Anchored = false
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.Massless = true
		end
	end

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		-- Both of these matter for the ragdoll rather than the flight: `_ragdoll` cuts the neck
		-- Motor6D, and a Humanoid that requires a neck kills itself when one goes missing — which
		-- with BreakJointsOnDeath left on would blow the whole rig apart on the first frame.
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		humanoid.EvaluateStateMachine = false
		humanoid.PlatformStand = true
		-- Guarantee an Animator: a cloned Humanoid normally brings one, and Phase 5's flight clips
		-- play from it.
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
	end

	-- Undo the seated driver's stripped legs and accessories (see the header).
	for _, partName in Vehicle.HiddenLegParts do
		local part = clone:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Transparency = 0
		end
	end
	for _, child in clone:GetChildren() do
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

	local root = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
	if not (root and root:IsA("BasePart")) then
		clone:Destroy()
		self.log:warn("Character clone has no root to fly; flying a placeholder.")
		return nil
	end
	root.Anchored = true
	clone.PrimaryPart = root
	clone.Name = "FlightAvatar"

	-- Parent before placing, for the same reason TrafficController._place does: a joint only binds
	-- once its parts are in the workspace, and moving beforehand is what bakes a bogus offset.
	clone.Parent = self._folder
	clone:PivotTo(cframe)

	--[[ The clips, loaded onto the Animator guaranteed above. Built here rather than at the bail so
		that a rig this controller could not animate is known about before the beat starts — and
		because this is the one place that holds both the rig and the reason it exists. ]]
	if StealConfig.Animations.Enabled then
		self._anim = RigAnimator.new(clone, StealConfig.Animations.Clips)
		if not self._anim then
			self.log:warn("Flight avatar has no Animator; the bail plays no animation.")
		end
	end
	return clone
end

-- Last resort when the character can't be cloned. Visible on purpose: a rig failure should look
-- like a placeholder, not like the mechanic doing nothing.
function StealController._buildPlaceholder(self, cframe: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "FlightAvatar"

	local part = Instance.new("Part")
	part.Name = "Root"
	part.Size = Vector3.new(2, 4, 1)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Color = Color3.fromRGB(240, 200, 60)
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = model
	model.PrimaryPart = part

	model.Parent = self._folder
	model:PivotTo(cframe)
	return model
end

-- === The driver you throw out ===============================================

-- Only the throw clip is loaded onto the NPC: it has no other beat, and loading the player's three
-- onto it would fetch four tracks per steal to play one.
local DRIVER_CLIPS = { DriverThrown = StealConfig.Animations.Clips.DriverThrown }

--[[ Everything a fresh rig needs before it can be thrown out of a car, applied identically to the
	default motorist and to a friend's avatar so the two can never drift apart.

	Set up as a puppet in the same shape and for the same reasons as the flight avatar (`_buildAvatar`
	has the full reasoning): Humanoid kept but switched off — strip it and the rig tumbles down the
	road with no clothes on — root anchored, limbs loose so the Motor6Ds can animate, everything
	massless and query-blind until `Ragdoll.release` hands it to physics.

	Returns nil for a rig with no root, which is the one failure nothing here can work around. ]]
local function prepareDriverRig(model: Model): Model?
	for _, inst in model:GetDescendants() do
		if inst:IsA("BaseScript") then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
			inst.Anchored = false
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.Massless = true
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		-- The ragdoll cuts the neck Motor6D, and a Humanoid that requires a neck kills itself when one
		-- goes missing — which with BreakJointsOnDeath left on would blow the whole rig apart on the
		-- first frame of the throw. Same pair, same reason, as `_buildAvatar`.
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		humanoid.EvaluateStateMachine = false
		humanoid.PlatformStand = true
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
	end

	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not (root and root:IsA("BasePart")) then
		model:Destroy()
		return nil
	end
	root.Anchored = true
	model.PrimaryPart = root
	model.Name = "Driver"
	model.Archivable = true
	return model
end

--[[ Build the fallback rig: the nameless blocky motorist every throw gets when the friend pool is
	empty.

	`CreateHumanoidModelFromDescription` IS A WEB CALL AND IT YIELDS, which is the whole reason this
	is a template built once at start-up rather than a rig built at the moment of the throw. A yield
	inside `_mount` would put a network round trip in the middle of the signature beat.

	R15 EXPLICITLY, and not "whatever the player is": the clip is authored on an R15 skeleton
	(measured off the asset's own pose list), so an R6 rig here would load a track that drives joints
	it does not have and stand there doing nothing. The player's own rig type is irrelevant — this is
	not the player.

	A HAND-COLOURED `HumanoidDescription` gives the classic noob (see `NOOB_COLORS` for why it is
	coloured rather than left empty), which is the right look for a nameless motorist and, more
	usefully, needs nothing in the place or in git to stay in sync. See `StealConfig.Driver` for why
	that matters. `_buildFriendDrivers` is what puts a real face on it. ]]
function StealController._buildDriverTemplate(self)
	if self._driverTemplate or self._driverPending or not StealConfig.Driver.Enabled then
		return
	end
	self._driverPending = true
	task.spawn(function()
		local ok, model = pcall(function()
			local desc = Instance.new("HumanoidDescription")
			desc.HeadColor = NOOB_COLORS.Head
			desc.TorsoColor = NOOB_COLORS.Torso
			desc.LeftArmColor, desc.RightArmColor = NOOB_COLORS.Arm, NOOB_COLORS.Arm
			desc.LeftLegColor, desc.RightLegColor = NOOB_COLORS.Leg, NOOB_COLORS.Leg
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
		end)
		self._driverPending = false
		if not (ok and model) then
			self.log:warn(string.format(
				"Could not build a driver rig (%s); steals will take an empty car.",
				tostring(model)
			))
			return
		end

		local rig = prepareDriverRig(model)
		if not rig then
			self.log:warn("Driver rig has no root; steals will take an empty car.")
			return
		end
		self._driverTemplate = rig
	end)
end

--[[ Read the local player's friends list, as far as `Friends.Scan` and no further.

	EVERY LAYER IS pcall'd BECAUSE EVERY LAYER IS A WEB CALL. `GetFriendsAsync` throws on a throttle
	and on a user id the backend won't answer for — which includes the Studio session with nobody
	logged in, where `LocalPlayer.UserId` can be a placeholder. Whatever we have when it breaks is
	what we use; an empty list is a valid answer and means "blocky motorist", not "error".

	`IsFinished` is checked AFTER reading the page rather than before, because the first page is
	already loaded when the object arrives — advancing first would skip it.

	BOUNDED BY A PAGE COUNT as well as by `limit`, for the same reason the arc is bounded by
	`Flight.MaxTime`: this is a loop whose exit condition is owned by a web service, and a service
	that answers "not finished, nothing here" forever must not take a session with it. ]]
function StealController._friendIds(self, userId: number, limit: number): { number }
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(userId)
	end)
	if not (ok and pages) then
		return {}
	end

	local ids = {}
	for _ = 1, MAX_FRIEND_PAGES do
		local read = pcall(function()
			for _, item in pages:GetCurrentPage() do
				local id = tonumber(item.Id)
				if NpcFriends.isUsable(item) then
					table.insert(ids, id)
				end
			end
		end)
		if not read or #ids >= limit or pages.IsFinished then
			break
		end
		if not pcall(function()
			pages:AdvanceToNextPageAsync()
		end) then
			break
		end
	end
	return ids
end

--[[ Put your friends in the cars: up to `Friends.Count` real avatars, built once for the session
	and cloned per throw.

	SHUFFLED THEN TAKEN, not taken then shuffled — the pick has to be over everyone read rather than
	over the first three, or a player with 200 friends throws the same three out every session for
	the rest of the game's life. The shuffle is a Fisher-Yates on `self._rng`, which is the same
	generator the tumble spins on.

	FAILING ONE FRIEND IS NOT FAILING. A private account, a deleted user, a description the backend
	won't serve — each drops that id and moves to the next, and a pool that comes back short or empty
	is simply a pool with fewer faces in it. `_pickDriverRig` falls back to the blocky default on its
	own, so nothing downstream has to know how this went.

	Deliberately NOT retried and deliberately NOT re-run per race: this runs once, at start-up,
	alongside the clip preload, and whatever it produces is the session's cast. A player who joins
	with the friends endpoint down gets motorists for that session, which is a fine outcome for a
	cosmetic and a much better one than a retry loop hitting a rate limit mid-race. ]]
function StealController._buildFriendDrivers(self)
	local cfg = StealConfig.Driver.Friends
	if not (StealConfig.Driver.Enabled and cfg.Enabled) then
		return
	end
	if self._friendsPending or #self._friendTemplates > 0 then
		return
	end
	local player = Players.LocalPlayer
	if not player then
		return
	end
	self._friendsPending = true

	task.spawn(function()
		local want = math.max(cfg.Count, 0)
		local ids = self:_friendIds(player.UserId, math.max(cfg.Scan, want))
		for i = #ids, 2, -1 do
			local j = self._rng:NextInteger(1, i)
			ids[i], ids[j] = ids[j], ids[i]
		end

		local built = 0
		for _, id in ids do
			if built >= want then
				break
			end
			local gotDesc, desc = pcall(function()
				return Players:GetHumanoidDescriptionFromUserId(id)
			end)
			if gotDesc and desc then
				-- R15 forced, exactly as for the default rig: the throw clip is authored on that
				-- skeleton, so a friend who wears R6 gets their own face and clothes on a rig the
				-- animation can drive.
				local gotRig, model = pcall(function()
					return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
				end)
				if gotRig and model then
					local rig = prepareDriverRig(model)
					if rig then
						table.insert(self._friendTemplates, rig)
						built += 1
					end
				end
			end
		end

		self._friendsPending = false
		if built == 0 then
			self.log:info("No friend avatars for the thrown driver; using the default motorist.")
		end
	end)
end

--[[ Whose car it was. A friend where there is one, the blocky motorist otherwise.

	NEVER THE SAME FACE TWICE RUNNING, while still being random: a random pick that lands on the last
	one used steps to the next in the pool instead. With three rigs and several steals a run, plain
	random repeats often enough to read as "there is only one driver model" — which is the exact
	impression this whole block exists to remove. ]]
function StealController._pickDriverRig(self): Model?
	local pool = self._friendTemplates
	local n = #pool
	if n == 0 then
		return self._driverTemplate
	end
	local pick = if n > 1 then self._rng:NextInteger(1, n) else 1
	if n > 1 and pool[pick] == self._lastDriverRig then
		pick = pick % n + 1
	end
	self._lastDriverRig = pool[pick]
	return pool[pick]
end

--[[ Where this car's driver sits, in the world, right now.

	The shell carries its seat frame root-relative (`TrafficService._doorPlan`), so this follows the
	car down the road for free and survives a rebase without being told.

	THE FALLBACK IS ROUGH ON PURPOSE and exists only so an OLD PUBLISHED BODY — one built before the
	stamp existed — still gets a driver rather than silently getting none. Driver's side is local -X
	and the nose is -Z on every body in this pack (CarDoorRig's `SIDES`), and `Hit` is the visible
	bodywork's own box, so a fifth of the width off centre and a touch below the box's mid-height is
	somewhere plausibly inside the cabin on all 33. It is not accurate and is not meant to be; a
	republished body gets the real frame. ]]
function StealController._driverSeat(self, rec): CFrame?
	local root = rec and rec.root
	if not (root and root.Parent) then
		return nil
	end
	local seat = rec.model and rec.model:GetAttribute("DriverSeat")
	if typeof(seat) == "CFrame" then
		return root.CFrame * seat
	end
	local hit = rec.hit
	if not (hit and hit.Parent) then
		return nil
	end
	return hit.CFrame * CFrame.new(-hit.Size.X * 0.2, -hit.Size.Y * 0.1, 0)
end

--[[ Put a driver in the car being stolen and start throwing them out of it.

	Fired at the commit, alongside the player's landing clip — the two are a matched pair and are
	meant to be read as one event (plan §5: "give the animator the anchor CFrame, not a
	description"). The rig is anchored and pinned to the seat for now; `_stepDriver` is what carries
	it and eventually lets go.

	Every way this can fail — animations off, driver off, every rig still downloading, a shell with
	no seat frame — ends in an empty car and a landing that still plays. None of them is worth a
	warning on the frame the player is watching. ]]
function StealController._throwDriver(self, rec)
	local cfg = StealConfig.Driver
	local template = self:_pickDriverRig()
	if not (cfg.Enabled and template and self._folder) then
		return
	end
	local seat = self:_driverSeat(rec)
	if not seat then
		return
	end

	local model = template:Clone()
	model.Name = "ThrownDriver"
	-- Parent before placing, same rule as everywhere else here: a joint only binds once its parts
	-- are in the workspace.
	model.Parent = self._folder
	model:PivotTo(seat * cfg.SeatOffset)

	self._driver = model
	--- A second handle the cinematic's door shot tracks (`_cineShot`); `_releaseDriver` drops the first.
	self._cineDriver = model
	self._driverFree = false
	self._driverAt = self._flight.t
	self._driverAnim = RigAnimator.new(model, DRIVER_CLIPS)
	if self._driverAnim then
		self._driverAnim:play("DriverThrown", StealConfig.Animations.Fade)
		self._driverAnim:setSpeed(TimeScale.get() * StealConfig.Mount.PlaybackSpeed)
	end
end

--[[ Carry the driver while the clip plays, then let go.

	PINNED, NOT SIMULATED, for the first `Driver.ReleaseAt` of the clip. The car is still doing 27–44
	studs/s, so a rig left where it spawned would be standing in the road a car length back before
	the animation's first beat had finished — the throw has to happen in the car's frame and then
	leave it.

	The handover is on FLIGHT time (`_driverAt` is sampled from it), so it dips with everything else
	when slow motion lands. Losing the car mid-throw releases early rather than freezing the body in
	mid-air: whatever took the car away is not going to bring it back. ]]
function StealController._stepDriver(self)
	local model = self._driver
	if not (model and model.Parent) or self._driverFree then
		return
	end

	-- Off the loaded track where there is one, falling back to the authored length — the same
	-- preference and the same reason as `_mountBeat`: a re-uploaded clip re-times its own beat
	-- instead of being cut off by a constant nobody remembered to update.
	local length = if self._driverAnim
		then self._driverAnim:length("DriverThrown")
		else StealConfig.Animations.Clips.DriverThrown.Length
	local hold = length * math.clamp(StealConfig.Driver.ReleaseAt, 0, 1) / math.max(StealConfig.Mount.PlaybackSpeed, 0.1)
	local seat = if self._flight.t - self._driverAt < hold then self:_driverSeat(self._target) else nil
	if seat then
		model:PivotTo(seat * StealConfig.Driver.SeatOffset)
		return
	end
	self:_releaseDriver()
end

-- Limp, thrown, and on its own from here. The car's own velocity plus `Kick` in the car's frame —
-- see StealConfig.Driver for why it is added rather than substituted.
function StealController._releaseDriver(self)
	local model = self._driver
	local cfg = StealConfig.Driver
	if not (model and model.Parent) or self._driverFree then
		return
	end
	self._driverFree = true
	self:_sfx("Throw")

	if self._driverAnim then
		-- No fade: a track still blending out is still writing Motor6D transforms onto joints that
		-- are about to stop existing. See RigAnimator.stop.
		self._driverAnim:stop()
		self._driverAnim = nil
	end
	Ragdoll.limp(model, cfg)

	local rec, info = self._target, self._info
	local carVel = if rec and info
		then info.forward * rec.speed + info.cross * rec.lateral
		else Vector3.zero
	local frame = if rec and rec.root and rec.root.Parent then rec.root.CFrame else model:GetPivot()
	Ragdoll.release(model, carVel + frame:VectorToWorldSpace(cfg.Kick), Ragdoll.spin(self._rng, cfg.Spin))

	--[[ Handed over to a timer and forgotten. The reference is dropped so the flight's own teardown
		can't reach back and delete a body that is now just scenery — it is behind the camera within
		a second either way, and the flight folder is the backstop that clears anything still lying
		around at the end of the race. ]]
	self._driver = nil
	task.delay(cfg.DebrisTime, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

-- Anything still mid-throw when a flight ends, which is only reachable if the beat was cut short.
-- A driver that has already been released is nil here by design, and is left to tumble.
function StealController._clearDriver(self)
	if self._driverAnim then
		self._driverAnim:stop()
		self._driverAnim = nil
	end
	if self._driver then
		self._driver:Destroy()
		self._driver = nil
	end
	self._driverFree = false
end

-- === The arc ================================================================

--[[ One frame of flight. THE ONLY PLACE THE ARC IS DEFINED — `_stepAir` runs it on the live flight
	and `_predict` runs it forward on a copy, so the circle on the road and the body in the air
	cannot describe different arcs. That was worth a little indirection: the previous version solved
	the touchdown in closed form, which was exact right up until the arc stopped being a parabola,
	and a marker that quietly disagrees with the landing is the worst bug this feature can have.

	Three things happen here, and only the first is ordinary ballistics:

	  • VERTICAL is lopsided. `RiseGravity` pulls hard, `FallGravity` barely at all, and `Float` caps
	    descent speed by a ceiling that tightens as the deck comes up. So you're thrown, then you
	    hang — the time is spent where the decision is, not at the top of a parabola.
	  • ALONG brakes from the apex on, easing toward `Glide.Speed` (traffic pace). Slowing only: a
	    slow bail must not be sped up by it. This is what keeps you over the car you picked instead
	    of sailing past it, and what lets the marker sit under you honestly.
	  • CROSS is the player's steering, eased, then clamped — `Reach` from where you bailed and
	    `HalfWidth` on the road. Clamped on POSITION rather than faded on input, because a fade near
	    the limit reads as the controls going soft; a clamp reads as running out of road, which is
	    what has actually happened. Steering back is never restricted at any position.

	`want` is the cross velocity being asked for: the live steer while flying, and simply the current
	one while predicting — which is what makes the circle mean "where you land IF YOU HOLD THIS".

	`deckY` IS A PARAMETER RATHER THAN `self._info.deckY`, because this integrator is now asked about
	arcs that have not started. `predictBail` runs it on a jump the player has not made yet — the
	tutorial has to know where a bail from HERE would come down before it can put a car there — and at
	that moment there is no flight and `_info` is nil. Passed in, one integrator answers for the live
	arc, the predicted one and the hypothetical one, and none of the three can drift from the others. ]]
-- Ordinary cruise is the stable reference for every longitudinal jump dial. Unlike live assembly
-- velocity it does not change with brake or nitro, and unlike a fixed studs/s constant it follows
-- the car the player has just stolen.
function StealController._jumpCruise(self): number
	local cruise = self._drive and self._drive:getCruiseSpeed()
	return if type(cruise) == "number" and cruise > 0 then cruise else StealConfig.Launch.SpeedWindow.FallbackCruise
end

function StealController._normalisedRoadSpeed(self, liveSpeed: number): number
	local window = StealConfig.Launch.SpeedWindow
	local cruise = self:_jumpCruise()
	local kept = math.max(liveSpeed * StealConfig.Launch.ForwardKeep, 0)
	return math.clamp(kept, cruise * window.MinCruiseFraction, cruise * window.MaxCruiseFraction)
end

function StealController._launchAlongSpeed(self, liveSpeed: number): number
	return self:_normalisedRoadSpeed(liveSpeed) * StealConfig.Launch.SpeedWindow.ThrowScale
end

function StealController._glideSpeed(self): number
	return self:_jumpCruise() * StealConfig.Flight.Glide.CruiseFraction
end

function StealController._advance(self, f, dt: number, want: number, deckY: number)
	local cfg = StealConfig.Flight

	f.crossVel += (want - f.crossVel) * (1 - math.exp(-dt * cfg.SteerAccel))

	local gravity = if f.yVel > 0 then cfg.RiseGravity else cfg.FallGravity
	--- The hang at the top (`Flight.Hang`): softer gravity while the arc is nearly level.
	local hang = cfg.Hang
	if hang and math.abs(f.yVel) < hang.Window then
		--- Floatier with the jump upgrade (`UpgradeConfig.jumpHangFactor`), in the prediction too: same self.
		gravity *= (if f.yVel > 0 then hang.RiseScale else hang.FallScale) * (self._jumpHang or 1)
	end
	--- ...and the GLIDE at the top (`Flight.Hang.Hold`): from the apex, `Hold` seconds nearly level before
	--- the fall begins. Counted on the arc's own fields, so a predicted copy of it agrees (`_predict`).
	if hang and (hang.Hold or 0) > 0 then
		if f.yVel <= 0 then
			f.apexed = true
		end
		if f.apexed and (f.held or 0) < hang.Hold then
			f.held = (f.held or 0) + dt
			gravity *= hang.HoldScale
		end
	end
	f.yVel -= gravity * dt
	if f.yVel < 0 then
		local cap = cfg.Float.Speed + cfg.Float.Falloff * math.max(f.y - deckY, 0)
		f.yVel = math.max(f.yVel, -cap)
	end

	--[[ The JUMP upgrade's reach half (`UpgradeConfig.jumpGlideFactor`), and the whole of it: the
		brake settles you a little further above traffic pace, so every second of the descent closes a
		little more ground on the car you picked. Both uses of the number below have to be the scaled
		one — the comparison is what decides whether the brake engages at all, and a bail slower than
		the raised glide must still not be sped up by it. ]]
	local glide = self:_glideSpeed()

	--- Not while homing on a locked car (`StealConfig.Lock.Home`): that sets the along speed itself.
	if not f.homing and f.yVel <= 0 and cfg.Glide.Ease > 0 and f.alongVel > glide then
		f.alongVel += (glide - f.alongVel) * (1 - math.exp(-dt * cfg.Glide.Ease))
	end

	f.along += f.alongVel * dt
	f.cross += f.crossVel * dt
	f.y += f.yVel * dt

	local reach = cfg.Reach * (self._jumpForgiveness or 1)
	f.cross = math.clamp(f.cross, f.startCross - reach, f.startCross + reach)
	f.cross = math.clamp(f.cross, -cfg.HalfWidth, cfg.HalfWidth)
end

-- === The ground marker ======================================================

--[[ Raise an Animal's dashed ground circle: where the arc says you're going to come down.

	Free here, and unusually exact, for two reasons that are both properties of this codebase:
	`RoadController._deckY` is a single number for a whole race (every tile is a clone of one
	template, and both recycling and rebasing only ever translate ALONG the road), so this needs no
	raycast — and the arc is scripted rather than physical, so the touchdown point can be run
	forward instead of waited for.

	IT RIDES DIRECTLY UNDER THE AVATAR (`Marker.Lead`), so it reads as a reticle you carry rather
	than a dot on the horizon. What the prediction changes is the COLOUR: green the moment the arc
	says a car will be under you when you arrive.

	THE SNAP IS A DISPLAY SNAP, NOT AUTO-AIM. Nothing whatsoever changes about where the avatar
	actually goes — at `Lead > 0` the circle just stops drawing on the deck and starts drawing on
	the car. That's what lets the arc stay genuinely steerable and still tell the player plainly
	what they've earned (plan §4).

	=== IT IS AN OUTLINE NOW, NOT A DISC — 2026-08-25 =========================================

	It was a 16-stud `Neon` cylinder: a filled circle of flat colour laid on the road. The shape was
	the problem rather than the colour. A filled circle covers the roof you are steering onto at
	exactly the moment you are reading it — the one frame where what is UNDER the marker is the
	whole question — and a solid disc of tinted light on tarmac is the graphic every scripted Roblox
	game draws, which is the same complaint that had the plot signage rebuilt.

	So the part is a MOUNT now and a `SurfaceGui` on its top face does the drawing
	(`UIAssets.Steal.Marker`). `LightInfluence = 0` is what that buys: the unlit, full-brightness
	read the `Neon` material was giving for free, without a lump of glowing geometry in the world.
	The part keeps `CanQuery`/`CanTouch` off, so nothing that raycasts this road can see it either
	way.

	Moves into `StealUIController` when the candidate markers and the prompt land. One circle doesn't
	justify a controller. ]]
function StealController._ensureMarker(self)
	if self._marker or not StealConfig.Marker.Enabled then
		return
	end
	local cfg = StealConfig.Marker

	local part = Instance.new("Part")
	part.Name = "StealMarker"
	--- The shipped size, and a placeholder while `Marker.MatchReach` is on: that draws the circle at
	--- the player's own reach, which cannot be read here (the marker is built before there is a
	--- flight, and how far it reaches is bought), so `_updateMarker` resizes on the first frame.
	part.Size = Vector3.new(cfg.Diameter, cfg.Thickness, cfg.Diameter)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	--- The part itself is never seen. It is here to carry the surface the reticle is drawn on and to
	--- be somewhere to write a CFrame.
	part.Transparency = 1

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Face"
	surface.Face = Enum.NormalId.Top
	surface.Adornee = part
	--- Unlit, so the reticle reads the same at every hour the weather system can put on the sky.
	surface.LightInfluence = 0
	--- Off. It is lying on the road; a car it passes under should cover it, which is one more piece
	--- of the read — a reticle drawn through a roof would say nothing about being over one.
	surface.AlwaysOnTop = false
	--- PIXELS PER STUD RATHER THAN A FIXED CANVAS, because the circle is not one fixed size any
	--- more: `Marker.Diameter` is a dial and `Marker.MatchReach` can hand it the player's own
	--- bought reach. 16 is the density the old 256-pixel canvas gave the old 16-stud circle, so a
	--- bigger circle is drawn exactly as sharply rather than going soft as it grows.
	surface.PixelsPerStud = 16
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.Parent = part

	local image = Instance.new("ImageLabel")
	image.Name = "Reticle"
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.Image = UIAssets.url(UIAssets.Steal.Marker)
	image.ScaleType = Enum.ScaleType.Fit
	-- Born hidden. `_updateMarker` is the only thing that shows it, and it doesn't run until the
	-- arc proper starts — so a marker created visible would sit at the world origin for the length
	-- of the launch beat, which is exactly long enough to notice.
	image.ImageTransparency = 1
	image.Parent = surface

	part.Parent = self._folder
	self._marker = part
	self._markerImage = image

	local highlight = Instance.new("Highlight")
	highlight.Name = "PredictedStealTarget"
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = cfg.Hit
	highlight.OutlineColor = cfg.Hit
	highlight.FillTransparency = cfg.TargetHighlight.FillTransparency
	highlight.OutlineTransparency = cfg.TargetHighlight.OutlineTransparency
	highlight.Enabled = false
	highlight.Parent = self._folder
	self._predictedHighlight = highlight
end

--[[ Where the arc comes down: the flight run forward to the deck on a scratch copy.

	Stepped rather than solved, and that's the change that made the lopsided arc possible at all. A
	parabola has a closed-form touchdown; a parabola with a descent-speed ceiling and an along-road
	brake on it does not, or not one anybody should be asked to maintain. Running the REAL integrator
	forward is both simpler and structurally honest — the marker cannot drift out of agreement with
	the flight, because there is only one arc and this is it.

	Cheap enough not to think about: a ~2.0s flight at `PredictStep` is ~90 iterations of arithmetic
	on a six-field table, once per frame, for about two seconds per bail.

	Stops at the same height `_stepAir` calls a landing (`Landing.DeckGrace`), not at the deck, so
	the predicted point is where the flight will actually END rather than a few studs past it. The
	loop is bounded by `MaxTime` for the same reason the flight is — an arc that somehow never comes
	down must not take the frame with it. ]]
function StealController._predict(self): (number, number, number)
	local f = self._flight
	return self:_runArc({
		along = f.along,
		cross = f.cross,
		y = f.y,
		alongVel = f.alongVel,
		crossVel = f.crossVel,
		yVel = f.yVel,
		startCross = f.startCross,
		--- The glide's progress (`Flight.Hang.Hold`), so the prediction does not re-run a hold already flown.
		apexed = f.apexed,
		held = f.held,
	}, self._info.deckY)
end

--[[ Run a scratch arc to touchdown and say where and when it got there.

	Lifted out of `_predict` when `predictBail` arrived, and the split is the whole point of it: two
	callers now ask "where does this arc end", one about the flight that is up and one about a flight
	that has not started. Sharing the loop is what keeps either of them from quietly falling behind a
	change to `_advance`, which is the only thing in here that knows the shape of the arc.

	`sim` is CONSUMED — it comes back holding the touchdown state — which is why both callers build a
	fresh table rather than handing the same one in twice. ]]
function StealController._runArc(self, sim, deckY: number): (number, number, number)
	local cfg = StealConfig.Flight
	local step = math.max(cfg.PredictStep, 1 / 240)
	local floorY = deckY + StealConfig.Landing.DeckGrace
	local t = 0
	while t < cfg.MaxTime do
		self:_advance(sim, step, sim.crossVel, deckY)
		t += step
		if sim.y <= floorY then
			break
		end
	end
	return sim.along, sim.cross, t
end

--[[ Will there be a car IN REACH of the predicted touchdown when we get there?

	It used to ask whether one would be sitting ON it, which is a meaner question than the one E
	answers: `Prompt.Range` reaches 18 studs out of the padded volume, so an arc coming down BESIDE
	a car was drawn as a miss, went red, outlined nothing, and then handed the player the car
	anyway. The circle was calling a whiff on a steal that worked. Asking exactly what
	`_findCandidate` asks is what makes the ring, the outline and the prompt one piece of news
	instead of three that disagree.

	Cars are advanced to where they WILL be (`along + speed * t`) rather than tested where they are,
	which matters more than it sounds: over a ~2.0s flight a Tier 5 covers 83 studs, nearly four car
	lengths, so testing against today's positions would name the car that has already left the patch
	of road you are aiming at.

	Nearest wins on surface distance, with the normalised `_boxDistance` breaking the dead heats
	that leaves, which is the same order `_findCandidate` resolves two overlapping lanes in. So the
	circle and the press can never name different cars. Approximated in the ROAD's frame rather than
	each car's, which is exact while a car is running straight and off by its lean while it is
	changing lane, a fraction of a stud against a 4-stud pad. ]]
function StealController._predictedTarget(self, along: number, cross: number, t: number, prefer: any?)
	local traffic = self._traffic
	if not traffic then
		return nil
	end
	local reach = self:_reach()
	local best, bestSurface, bestBox
	--- `prefer` (`StealConfig.Lock.Stick`): the car the lock already holds, and its surface distance.
	local preferSurface: number? = nil
	for _, rec in traffic:getCars() do
		if not rec.physical and rec.hit and rec.hit.Parent and self:_canTake(rec) then
			-- A lane change that was already visibly underway is allowed to finish during the flight.
			-- Predict that committed lateral travel at TrafficController's same bounded rate.
			local lateralStep = TrafficConfig.LaneChangeSpeed * t
			local predictedCross = rec.cross + math.clamp(rec.targetCross - rec.cross, -lateralStep, lateralStep)
			local across = cross - predictedCross
			local gap = along - (rec.along + rec.speed * t)
			local surface = self:_roadSurfaceDistance(across, gap, rec.hit.Size)
			if rec == prefer and surface <= reach then
				preferSurface = surface
			end
			if surface <= reach then
				local box = self:_boxDistance(across, gap, rec.hit.Size)
				local better = if not best
					then true
					elseif surface < bestSurface - 1e-3 then true
					elseif surface > bestSurface + 1e-3 then false
					else box < bestBox
				if better then
					best, bestSurface, bestBox = rec, surface, box
				end
			end
		end
	end
	--- Sticky (`StealConfig.Lock.Stick`): the held car stays held unless the new best beats it clearly.
	if prefer and preferSurface and best ~= prefer and StealConfig.Lock.Enabled
		and preferSurface - (bestSurface or math.huge) < StealConfig.Lock.Stick then
		best = prefer
	end
	return best
end

--[[ How wide to draw the circle, in studs. `Marker.Diameter` as it ships, and with
	`Marker.MatchReach` on, the region E really works in: `Prompt.Range` plus `Landing.Pad`, doubled.

	That derived width is read off the PLAYER rather than out of the config, because both of those
	numbers are scaled by the jump upgrade's forgiveness and the first is widened again by the
	tutorial's rig — so the ring becomes the reach itself rather than a picture of it, which is the
	whole argument in `Marker.MatchReach`, and the reason the flag is off is written there too. ]]
function StealController._ringDiameter(self): number
	local cfg = StealConfig.Marker
	if not cfg.MatchReach then
		return cfg.Diameter
	end
	return 2 * (self:_reach() + StealConfig.Landing.Pad * (self._jumpForgiveness or 1))
end

function StealController._updateMarker(self, dt: number)
	local marker, image = self._marker, self._markerImage
	if not (marker and image) then
		return
	end
	local cfg = StealConfig.Marker

	local along, cross, t = self:_predict()
	local lock = StealConfig.Lock
	--[[ WITH THE LOCK ON, THE LOCK IS THE ONE TARGET (2026-10-20: "the indicator shows on a car, then I
		press E and it steals a completely different car", and "it doesn't show ANY car until the
		descent"). `_pickLock` names one car from the first frame of the jump; the circle and outline
		show it, `_findCandidate` offers E nothing else, and the assist steers for it. `ready` is
		whether E would take it NOW: green when it would, `Lock.AimColor` while it is still out of
		reach (on the way up, or a car length short). Lock off: the old prediction, as it was. ]]
	local rec, ready
	if lock.Enabled then
		if self._state == "launch" then -- the air re-picks in `_stepAir`; a perch holds its roof
			self._lockRec = self:_pickLock(self._flight)
		end
		rec = self._lockRec
		ready = rec ~= nil and self._candidate == rec
		if rec then
			local lateralStep = TrafficConfig.LaneChangeSpeed * t
			self._lockCross = rec.cross + math.clamp(rec.targetCross - rec.cross, -lateralStep, lateralStep)
			self._lockT = t
		end
	else
		rec = self:_predictedTarget(along, cross, t)
		ready = rec ~= nil
	end

	--[[ ONE CIRCLE, AND `Lead` DECIDES WHICH QUESTION IT ANSWERS. At 0 it rides under the avatar and
		says where you are, coloured by where you are going; at 1 it sits on the solved touchdown and
		says where you will be. It shipped at 0 and the pair that briefly stood here — a reach-wide
		ring out on the landing, a quieter twin under the player — went with `Marker.MatchReach`.

		`Flight.Glide` is what lets one circle do both jobs: braking to traffic pace leaves only a
		few studs between "under me" and "where I land", so the colour a circle under the avatar
		wears is a true statement about the landing rather than a guess. ]]
	local f = self._flight
	local herePos = self:_worldPos(f.along, f.cross, self._info.deckY)

	local pos, color
	if rec then
		-- The solved touchdown point. The highlight names the moving car the steal will be able to
		-- reach from there, so neither the circle nor the target identification has to lie.
		pos = self:_worldPos(along, cross, self._info.deckY)
		color = if ready then cfg.Hit else lock.AimColor
	else
		pos = self:_worldPos(along, cross, self._info.deckY)
		-- Neutral early, red once there's not much flight left to fix it with. Shouting about a
		-- tarmac prediction on the first frame of the arc is noise; you can still steer out of it.
		local total = math.max(f.t + t, 1e-3)
		color = if f.t / total >= cfg.CommitAt then cfg.Miss else cfg.Neutral
	end
	pos = herePos:Lerp(pos, math.clamp(cfg.Lead, 0, 1))
	--- Locked: on the car's roof instead, where it is now, so the circle is ON the car it names.
	if lock.Enabled and rec and rec.hit and rec.hit.Parent then
		pos = rec.hit.Position + Vector3.yAxis * (rec.hit.Size.Y * 0.5)
	end
	--- ...sliding there rather than jumping (and between cars as the lock moves), snapped on the
	--- first frame of a flight so it does not fly in from the last one.
	local shown = self._markerAt
	if lock.Enabled and shown then
		pos = shown:Lerp(pos, 1 - math.exp(-lock.Slide * dt))
	end
	self._markerAt = pos

	--- Sized here rather than at build time, because `Marker.MatchReach` can make the width a bought
	--- number. It cannot change inside a flight and this runs every frame of one, so the write is
	--- guarded on the value having actually moved.
	local diameter = self:_ringDiameter()
	--- Locked on a car: bigger, breathing, over the bodywork and at full strength (`Lock.OnTop`).
	local locked = lock.Enabled and rec ~= nil
	if locked then
		diameter *= lock.Grow * (1 + lock.Pulse * math.sin(os.clock() * math.pi * 2 * lock.PulseRate))
	end
	if math.abs(marker.Size.X - diameter) > 1e-3 then
		marker.Size = Vector3.new(diameter, cfg.Thickness, diameter)
	end
	local face = marker:FindFirstChild("Face")
	if face and face:IsA("SurfaceGui") then
		face.AlwaysOnTop = locked and lock.OnTop
	end

	--- No rotation on the CFrame any more. The old cylinder needed a 90-degree roll to stand its
	--- circular face up; a block's top face is already the road's plane, and the turn the reticle
	--- does is done in the image below rather than in the world.
	marker.CFrame = CFrame.new(pos + Vector3.yAxis * cfg.Lift)
	image.ImageColor3 = color
	image.ImageTransparency = if locked then 0 else cfg.Transparency

	--[[ A car whose mutation takes no Highlight (the Ghost's ForceField skin: "a transparent material
		takes no Highlight at all", `WeatherConfig`) gets a box round its body instead (2026-10-20, a
		tester: "it wasn't letting me hover on the ghost car"; it was locked, and nothing showed it). ]]
	local mutation = rec and rec.mutation and WeatherConfig.mutationOf(rec.mutation)
	local boxed = mutation ~= nil and mutation.Highlight == false
	local highlight = self._predictedHighlight
	if highlight then
		highlight.Adornee = if rec and cfg.TargetHighlight.Enabled and not boxed then rec.model else nil
		highlight.Enabled = highlight.Adornee ~= nil
		--- The outline wears the circle's colour: aiming until E would take it, green once it would.
		highlight.FillColor, highlight.OutlineColor = color, color
	end
	if boxed and not self._targetBox then
		local box = Instance.new("SelectionBox")
		box.Name = "PredictedStealTargetBox"
		box.LineThickness = 0.18
		box.SurfaceTransparency = 0.85
		box.Parent = self._folder
		self._targetBox = box
	end
	local box = self._targetBox
	if box then
		box.Adornee = if boxed and rec and rec.hit then rec.hit else nil
		box.Visible = box.Adornee ~= nil
		box.Color3, box.SurfaceColor3 = color, color
	end

	--- Off flight `dt`, so it slows with everything else if `SlowMo` is ever switched on. Wrapped
	--- rather than left to grow: `Rotation` is a float and a number that only ever climbs loses
	--- precision on a long session for no reason.
	if cfg.Spin ~= 0 then
		self._markerSpin = ((self._markerSpin or 0) + cfg.Spin * dt) % 360
		image.Rotation = self._markerSpin
	end
end

function StealController._hideMarker(self)
	local image = self._markerImage
	-- Only when it actually changes: this runs every frame of the launch and the mount, and there's
	-- no reason to poke a property that's already where we want it.
	if image and image.ImageTransparency ~= 1 then
		image.ImageTransparency = 1
	end
	if self._predictedHighlight then
		self._predictedHighlight.Enabled = false
		self._predictedHighlight.Adornee = nil
	end
	if self._targetBox then
		self._targetBox.Visible = false
		self._targetBox.Adornee = nil
	end
	--- The circle's slide restarts with it. The LOCK is not cleared here: a perch hides the marker and
	--- must keep the car E is offering. It is cleared with the flight (`_clearLock`).
	self._markerAt = nil
end

--- The highlighted car, if the jump came down within `Lock.LandReach` studs of it (flat, road plane), so
--- a landing a little short of E's reach still takes the car the player was shown. nil otherwise.
function StealController._lockNearby(self)
	local rec, f = self._lockRec, self._flight
	if not (StealConfig.Lock.Enabled and rec and f and not rec.physical and rec.hit and rec.hit.Parent) then
		return nil
	end
	local surface = self:_roadSurfaceDistance(f.cross - rec.cross, f.along - rec.along, rec.hit.Size)
	return if surface <= StealConfig.Lock.LandReach * (self._jumpForgiveness or 1) then rec else nil
end

--- Forget the lock (`StealConfig.Lock`): a new jump, or the jump over.
function StealController._clearLock(self)
	self._lockRec, self._lockCross, self._lockT, self._markerAt = nil, nil, nil, nil
	--- Flight time restarts at 0 each jump, so a hold left from the last one would read as still live.
	self._manualUntil = nil
end

--[[ THE TARGET LOCK'S PICK (`StealConfig.Lock`): one car, from the first frame of the jump.

	CARS IN FRONT FIRST, NEAREST FIRST. "In front" is a car whose middle is at least `FrontFrom` studs
	up the road from the player. Only with none of those in the window does it look beside and behind
	(`Behind` studs back). Nearest is measured with the sideways gap weighted by `SideWeight`, so the car
	in your own lane beats one the same distance off in the next. The window is `Ahead` studs up the
	road and `Side` studs either way, which is about everything the glide and the steering can reach.

	STICKY: the car already locked stays locked unless the new best is in a better group or nearer by
	`Stick` studs, so steering toward another car moves the lock and drifting between two does not.
	Behind comes last of all: with nothing in front or beside, a car behind is still a target.
	Road frame throughout, the same `along`/`cross` the flight and the traffic records are kept in. ]]
--[[ The collector's ⚡ gate (`CollectorConfig.RoadSteal`, 2026-11-01): a car above your Steal Power
	is never locked, aimed at or offered, so the jump only ever goes for one you can keep. A courtesy,
	not the rule — `RoamingCarService.awardRoadSteal` re-checks on the server. The LANDING is not
	gated (`_landingTarget`): coming down on a car you cannot keep still lands you in it, and the server
	answers "weak" instead of wrecking you for a jump the lock never offered. ]]
function StealController._canTake(self, rec): boolean
	local required = CollectorConfig.Enabled and CollectorConfig.RoadSteal and CollectorConfig.requiredForBody(rec.body)
	if not required then
		return true
	end
	return CollectorConfig.powerOf(Players.LocalPlayer) >= required
end

function StealController._pickLock(self, f, steering: boolean?)
	local traffic = self._traffic
	if not (traffic and f) then
		return nil
	end
	local cfg = StealConfig.Lock
	--- Where the player is heading across the road: now, plus `AimLead` seconds of their sideways drift.
	local aimCross = f.cross + (f.crossVel or 0) * cfg.AimLead
	--- ...and along it: the throttle's lean (`AlongSteer`), `AimAlong` studs at full gas or brake.
	local aimAlong = f.along + (f.push or 0) * (cfg.AimAlong or 0)
	local best, bestGroup, bestDist
	local held, heldDist
	for _, rec in traffic:getCars() do
		if not rec.physical and rec.hit and rec.hit.Parent and self:_canTake(rec) then
			local ahead = rec.along - f.along
			local side = rec.cross - aimCross
			if ahead >= -cfg.Behind and ahead <= cfg.Ahead * (self._jumpRange or 1) and math.abs(side) <= cfg.Side then
				--- 1 in front, 2 beside or diagonal (within `FrontFrom` either way), 3 behind.
				local group = if ahead >= cfg.FrontFrom then 1 elseif ahead > -cfg.FrontFrom then 2 else 3
				--- Nearness from the AIM (the throttle's lean along, the drift across), the window and
				--- the groups from where the player actually is.
				local toAim = rec.along - aimAlong
				local dist = math.sqrt(toAim * toAim + (side * cfg.SideWeight) ^ 2)
				if rec == self._lockRec then
					held, heldDist = rec, dist
				end
				if not best or group < bestGroup or (group == bestGroup and dist < bestDist) then
					best, bestGroup, bestDist = rec, group, dist
				end
			end
		end
	end
	--[[ ONCE LOCKED, IT STAYS LOCKED UNTIL THE PLAYER STEERS (2026-10-20: it kept "prioritising a car
		JUST in front of the one she wanted"). Catching up to the locked car takes it out of "in front"
		as you arrive over it, and the group rule then handed the lock to the next car up the road.
		So the groups only make the FIRST pick. After that the held car is kept, and steering moves the
		lock only to a car clearly nearer where you are steering (`Stick` studs), groups ignored. ]]
	if held then
		if not steering then
			return held
		end
		local nearest, nearestDist = held, heldDist
		for _, rec in traffic:getCars() do
			if rec ~= held and not rec.physical and rec.hit and rec.hit.Parent and self:_canTake(rec) then
				local ahead = rec.along - f.along
				local side = rec.cross - aimCross
				if ahead >= -cfg.Behind and ahead <= cfg.Ahead * (self._jumpRange or 1) and math.abs(side) <= cfg.Side then
					local toAim = rec.along - aimAlong
					local dist = math.sqrt(toAim * toAim + (side * cfg.SideWeight) ^ 2)
					if dist < nearestDist - cfg.Stick then
						nearest, nearestDist = rec, dist
					end
				end
			end
		end
		return nearest
	end
	return best
end

-- === The prompt =============================================================

--[[ The pill that says you can take this one, drawn over the car.

	A BillboardGui rather than a `ProximityPrompt`, because a real one cannot work here — the stock
	`Driver` LocalScript switches `ProximityPromptService.Enabled` off for the whole drive, and
	activation distance would be measured from the character, who is seated inside a car 22–70 studs
	behind the flight. `StealConfig.Prompt` has the full reasoning. Ours costs one instance and the
	keybind we were already paying for.

	IT IS MADE OF THE KIT — `UIAssets.Pill.Green` with the keycap beside it — which makes it the same
	object as the plaza's BUY CAR prompt down to the arithmetic below. `StealConfig.Prompt` has the
	account of what it replaced and why that mattered. The one thing worth repeating here is that the
	width is DERIVED: the pill art is aspect-locked and a box that does not match its 3.89:1 renders
	it as a lozenge, so `Height` is the only size in the config and everything else follows from it.

	BUILT ONCE AND RE-ADORNED, never rebuilt: the candidate changes as you drift across lanes, and a
	prompt that is destroyed and recreated on that boundary flickers. `Adornee` is the whole trick —
	the billboard tracks a car doing 40 studs/s for free, with no per-frame positioning to get wrong
	and nothing to keep in the road frame.

	`AlwaysOnTop` because it is standing on the roof of the thing it is describing, and would
	otherwise spend half its life inside the bodywork. ]]
function StealController._ensurePrompt(self)
	if self._prompt or not (StealConfig.Prompt.Enabled and self._folder) then
		return
	end
	local cfg = StealConfig.Prompt

	--[[ Pill, gap, cap — all three off `Height`, then each expressed as a fraction of the box they
		add up to. A `UIAspectRatioConstraint` is the obvious tool for the pill and it is the wrong
		one, for `CarDealController._buildPill`'s reason: `FitWithinMaxSize` resolves a zero-width
		box to nothing rather than deriving a width from the aspect. A billboard has what a screen
		does not — a fixed, known size of its own — so this is exact and cannot collapse. ]]
	local pillAspect = UIAssets.Size.Pill.X / UIAssets.Size.Pill.Y
	local width = cfg.Height * (pillAspect + cfg.KeyGap + cfg.KeyScale)
	local pillWidth = cfg.Height * pillAspect / width
	local capWidth = cfg.Height * cfg.KeyScale / width
	local gap = cfg.Height * cfg.KeyGap / width

	local gui = Instance.new("BillboardGui")
	gui.Name = "StealPrompt"
	--- Pixels at a nominal distance; a BillboardGui scales this with range on its own, so it shrinks
	--- as the car gets further away, which is what makes it read as attached to the car.
	gui.Size = UDim2.fromOffset(width, cfg.Height)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	-- Born hidden and born un-adorned. `_updatePrompt` is the only thing that shows it, and it does
	-- not run until there is a candidate — a billboard enabled with no adornee draws at the world
	-- origin, which on this road is a long way behind the player but still on screen at the start.
	gui.Enabled = false

	--[[ One frame for the pop to work on, centred so it grows about its own middle. It used to be
		the pill's `Size` that was animated, which was fine while the pill WAS the prompt and is not
		now there is a keycap beside it: scaling one of two siblings would have left the cap where it
		was and slid the gap open. ]]
	local root = Instance.new("Frame")
	root.Name = "Prompt"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Scale = cfg.PopScale
	scale.Parent = root

	local pill = Instance.new("ImageLabel")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0, 0.5)
	pill.Position = UDim2.fromScale(0, 0.5)
	pill.Size = UDim2.fromScale(pillWidth, 1)
	pill.BackgroundTransparency = 1
	pill.Image = UIAssets.url(UIAssets.Pill.Green.Idle)
	--- Stretch, never Slice — `UIAssets.Slice`'s own block is titled "why no pill is ever 9-sliced",
	--- and the short version is that a slice holds the corner radius at texture pixels, so a pill
	--- rendered smaller than its art comes out a lozenge.
	pill.ScaleType = Enum.ScaleType.Stretch
	pill.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	--- Off centre by a hair, and the plaza's pill is off by the same hair for the same reason: the
	--- artist's face sits slightly high in the art's own box, so a caption centred on the BOX reads
	--- visibly low on the FACE.
	label.Position = UDim2.fromScale(0.5, 0.46)
	label.Size = UDim2.fromScale(0.74, 0.44)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = cfg.Label
	label.TextColor3 = cfg.Text
	label.TextScaled = true
	label.Parent = pill

	--[[ The key cap. Square by construction rather than by `SizeConstraint`: `capWidth` is already
		`KeyScale` of the height expressed against the width, so it stays square through the pop and
		at every distance the billboard scales itself to.

		`GamepadConfig.Icon` FOR THE TWO COLOURS, not a pair of literals, because that table is
		already the answer to "what does a button prompt look like in this game" — it is what the
		on-screen gamepad badges are painted in, and it is kit-derived (`#28334B` is the card face).
		One place to restyle every key this game draws. ]]
	local cap = Instance.new("Frame")
	cap.Name = "Cap"
	cap.AnchorPoint = Vector2.new(0, 0.5)
	cap.Position = UDim2.fromScale(pillWidth + gap, 0.5)
	cap.Size = UDim2.fromScale(capWidth, cfg.KeyScale)
	cap.BackgroundColor3 = GamepadConfig.Icon.Background
	cap.BorderSizePixel = 0
	cap.Parent = root

	local capCorner = Instance.new("UICorner")
	capCorner.CornerRadius = UDim.new(0.24, 0)
	capCorner.Parent = cap

	local capStroke = Instance.new("UIStroke")
	capStroke.Color = GamepadConfig.Icon.Stroke
	capStroke.Thickness = GamepadConfig.Icon.StrokeThickness
	capStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	capStroke.Parent = cap

	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.AnchorPoint = Vector2.new(0.5, 0.5)
	key.Position = UDim2.fromScale(0.5, 0.5)
	key.Size = UDim2.fromScale(0.72, 0.6)
	key.BackgroundTransparency = 1
	key.FontFace = FONT
	key.Text = cfg.Key
	key.TextColor3 = cfg.Text
	key.TextScaled = true
	key.Parent = cap

	--[[ THE SAME CAP, DRAWN AS A CONTROLLER BUTTON. `StealConfig.Prompt.Keys` already carries both
		keys — E and ButtonX — so this is the same prompt saying which of them you are holding.

		The glyph REPLACES the cap rather than sitting on it: the stock art is a whole button, ring
		and symbol, and painting it onto the cap would be a button drawn inside a button. So on a
		controller the cap goes transparent AND ITS STROKE GOES WITH IT — a `UIStroke` on a frame at
		`BackgroundTransparency = 1` still draws its outline, which would leave a rounded square
		floating round the glyph. `Cap`'s own square aspect is what keeps the glyph round. ]]
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.Visible = false
	glyph.Parent = cap

	--[[ THE WHOLE PROMPT, AS A BUTTON, FOR THE ONE DEVICE THAT HAS NO KEY TO PRESS.

		Invisible and last, so it covers the pill and the cap and the finger gets the full box rather
		than the keycap's corner — and so nothing about how the prompt LOOKS is decided here. Shown
		only on touch (below), because on the other two devices a clickable billboard is a second way
		to do a thing the key already does and one more thing to be in the way of the shot.

		`InputBegan` rather than `Activated`, the same call `DrivingHudController._bindTap` makes and
		for the same reason: `Activated` wants the press AND the release on the same object, so a
		finger that lands on a pill riding a car doing eighty studs a second and slides off it does
		nothing at all. A steal is a timing read; it should fire on the frame the finger lands.

		`_onSteal` is the identical entry point E uses, guards and all — a tap with no candidate does
		nothing, exactly as the key press does — so there is no second code path here to keep in step
		with the first. ]]
	local tap = Instance.new("TextButton")
	tap.Name = "Tap"
	tap.AnchorPoint = Vector2.new(0.5, 0.5)
	tap.Position = UDim2.fromScale(0.5, 0.5)
	tap.Size = UDim2.fromScale(1, 1)
	tap.BackgroundTransparency = 1
	tap.Text = ""
	tap.AutoButtonColor = false
	tap.Selectable = false
	tap.ZIndex = 4
	tap.Visible = false
	tap.Parent = root
	tap.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			self:_onSteal()
		end
	end)

	--[[ IN PLAYERGUI, NOT THE FLIGHT FOLDER (2026-10-06). A BillboardGui parented under `workspace`
		draws fine and never receives input, so `Tap` above was dead on every phone: Leaf tapped the
		pill, nothing happened, and he took it for a label he had misread. Under PlayerGui with an
		`Adornee` it draws in the same place and takes the touch. The folder no longer takes it down
		with it, so `_teardown` destroys it itself. `ResetOnSpawn` off because the
		teardown owns its life, not the character. ]]
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._prompt = gui
	self._promptScale = scale

	--[[ Which of the two keys the prompt is advertising, re-asked every time the player's device
		changes rather than decided once at build time — a pad picked up mid-race has to change the
		prompt, and the glyph itself changes with the CONTROLLER BRAND (`GetImageForKeyCode` hands
		back PlayStation art on a DualSense), which is another reason not to cache it.

		Built once and re-adorned, like the rest of this billboard, so this subscribes once for the
		session. ]]
	local padKey = GamepadInput.gamepadKeyIn(cfg.Keys)
	GamepadInput.observePreferred(function(isGamepad: boolean)
		--[[ THREE DEVICES, NOT TWO — see `StealConfig.Prompt.Touch` for the bug the third one closes.

			`PreferredInput` rather than `TouchEnabled`, and asked HERE rather than hoisted: it is the
			same property `observePreferred` is already subscribed to, so the pad, the keyboard and the
			phone all move this prompt through one callback and cannot disagree about which of them is
			in the player's hands. It is also the read that survives the trap the rest of this codebase
			keeps tripping over — `TouchEnabled` is not reliable at client boot, and a phone with a
			keyboard paired (or Studio's device emulator, which keeps `KeyboardEnabled` true) makes the
			stricter "touch and no keyboard" test answer no on a device that is plainly a phone. ]]
		local useTouch = not isGamepad and UserInputService.PreferredInput == Enum.PreferredInput.Touch
		local usePad = isGamepad and padKey ~= nil
		if usePad then
			glyph.Image = GamepadInput.getButtonImage(padKey :: Enum.KeyCode)
		elseif useTouch then
			glyph.Image = cfg.Touch.Glyph
		end
		local glyphed = usePad or useTouch
		glyph.Visible = glyphed
		key.Visible = not glyphed
		cap.BackgroundTransparency = if glyphed then 1 else 0
		capStroke.Enabled = not glyphed

		--- `Active` is what makes a BillboardGui's buttons receive input at all, and it goes on and
		--- off with the button rather than being set once: on a pad or a keyboard this billboard is a
		--- readout, and a readout should not be eating clicks.
		tap.Visible = useTouch and cfg.Touch.Pressable == true
		gui.Active = tap.Visible
	end)
end

--[[ Point the prompt at this frame's candidate, or put it away.

	The pop is ~0.12s of scale and exists to stop the thing strobing: the candidate legitimately
	changes while you drift between two lanes' ranges, and an instant on/off on that boundary reads as
	a bug. It re-pops on a CHANGE of car, deliberately — that is different news, and it wants to be
	noticed rather than to slide sideways.

	Scaled by hand off flight dt rather than tweened, for the same reason everything else in this file
	is: TweenService cannot obey the time scale, and this runs inside the one beat that will eventually
	be in slow motion. ]]
function StealController._updatePrompt(self, dt: number)
	local cfg = StealConfig.Prompt
	if not cfg.Enabled then
		return
	end

	local rec = self._candidate
	if not (rec and rec.hit and rec.hit.Parent) then
		self:_hidePrompt()
		return
	end

	self:_ensurePrompt()
	local gui, scale = self._prompt, self._promptScale
	if not (gui and scale) then
		return
	end

	local hit = rec.hit
	if gui.Adornee ~= hit then
		gui.Adornee = hit
		-- World space, so it stays over the roof rather than swinging with the car as it leans into a
		-- lane change. Re-measured per car: `Hit` is sized to each body's own bodywork.
		gui.StudsOffsetWorldSpace = Vector3.new(0, hit.Size.Y * 0.5 + cfg.Lift, 0)
		self._promptPop = 0
	end
	gui.Enabled = true

	local pop = math.max(cfg.PopTime, 1e-3)
	self._promptPop = math.min((self._promptPop or 0) + dt, pop)
	local a = self._promptPop / pop
	a = 1 - (1 - a) * (1 - a)
	scale.Scale = cfg.PopScale + (1 - cfg.PopScale) * a
end

function StealController._hidePrompt(self)
	local gui = self._prompt
	if gui and gui.Enabled then
		gui.Enabled = false
	end
	self._promptPop = 0
end

-- === Landing ================================================================

--[[ How far a point is from the centre of a car's landing volume, as a fraction of that volume.

	Chebyshev distance in normalised box coordinates: 0 is dead centre, 1 is exactly on the padded
	edge, above 1 is outside. `across` and `along` are the offsets in the car's own frame and `size`
	is its `Hit` box, so the two axes are scaled by the volume's own proportions — which is what
	makes "nearest" mean the right thing on a car that is twice as long as it is wide. A raw
	distance would let a car 8 studs ahead of you beat one 6 studs to the side, when the sideways
	one is far closer to being missed. ]]
function StealController._boxDistance(self, across: number, along: number, size: Vector3): number
	local pad = StealConfig.Landing.Pad * (self._jumpForgiveness or 1)
	return math.max(math.abs(across) / (size.X * 0.5 + pad), math.abs(along) / (size.Z * 0.5 + pad))
end

--[[ How far a point is from the OUTSIDE of a car's padded volume, in plain studs, asked in the
	ROAD's frame: `across` and `along` are the two gaps already, which is how the marker's prediction
	holds them.

	The same answer `_surfaceDistance` gives a caller holding a world position and a part, for the
	one caller that holds neither. Flat rather than 3D because the prediction is a point on the deck,
	and the height an avatar has left at touchdown is inside every car's volume anyway. ]]
function StealController._roadSurfaceDistance(self, across: number, along: number, size: Vector3): number
	local pad = StealConfig.Landing.Pad * (self._jumpForgiveness or 1)
	local dx = math.max(math.abs(across) - (size.X * 0.5 + pad), 0)
	local dz = math.max(math.abs(along) - (size.Z * 0.5 + pad), 0)
	return math.sqrt(dx * dx + dz * dz)
end

--[[ Are we on a car?

	A point-in-box test in each shell's `Hit` frame, IN LUA, and that is a deliberate dodge rather
	than a shortcut. `CarCollision`'s matrix means an OverlapParams left in "Default" comes back
	empty for every traffic car on the road — a query would have to run as `PlayerGroup` to see
	anything, which has already bitten `TrafficController._checkClips` once and reads as the feature
	being broken rather than misconfigured. Twelve point-in-box tests per frame cost nothing and
	cannot be misconfigured.

	The volume is deliberately fatter than the car (`StealConfig.Landing.Pad`), per the GDD's feel
	rule: whiffing should always feel like the player's fault, never the hitbox's.

	Only fires while DESCENDING and only once the root has come down to within the mount height of
	the roof — so launching up through a car's volume can't mount you, and neither can grazing one
	on the way past at head height.

	THE PADDED VOLUMES OF NEIGHBOURING LANES OVERLAP, and that is fine, but it has to be resolved
	rather than left to iteration order. A shell is 10.36 wide, so a 4-stud pad makes it 18.36 —
	against 15-stud lane spacing, two cars side by side share about 3.4 studs of claimable road. So
	the choice is the NEAREST car rather than the first one found, measured as a normalised box
	distance (`_boxDistance`) so a stud across the road counts for more than a stud along it, in the
	same proportion the volume itself is stretched. Deterministic, and it agrees with the marker,
	which asks the same question of the predicted point. ]]
function StealController._landingTarget(self, pos: Vector3)
	local traffic = self._traffic
	if not (traffic and self._flight.yVel <= 0) then
		return nil
	end
	local reach = StealConfig.Mount.Reach

	local best, bestDist
	for _, rec in traffic:getCars() do
		local hit = rec.hit
		if not rec.physical and hit and hit.Parent then
			local localPos = hit.CFrame:PointToObjectSpace(pos)
			local dist = self:_boxDistance(localPos.X, localPos.Z, hit.Size)
			if dist <= 1 and pos.Y <= hit.Position.Y + hit.Size.Y * 0.5 + reach then
				if not bestDist or dist < bestDist then
					best, bestDist = rec, dist
				end
			end
		end
	end
	return best
end

--[[ How far a point is from the OUTSIDE of a car's padded volume, in plain studs. 0 anywhere inside
	it, and a true 3D distance out of it — the closest point on the box to `pos`, which is the
	textbook AABB distance done in the box's own frame so the car's heading comes for free.

	Studs rather than the normalised `_boxDistance`, because this answers a different question.
	`_boxDistance` asks "which of these two overlapping volumes am I more inside", where a stud across
	the road has to count for more than a stud along it. `Prompt.Range` asks "can I reach that car",
	and reach is reach in any direction — so it must not be stretched by the volume's proportions, or
	the prompt would light 30 studs behind a car and 15 studs beside it.

	The Y half-extent is used UNPADDED while X and Z carry `Landing.Pad`. The pad exists to forgive
	aim across the road, and there is no aiming in the vertical: the height that matters is how far
	above the roof E starts working, and that is `Prompt.Range`'s job to say, in one number, rather
	than something quietly added to it here. ]]
function StealController._surfaceDistance(self, pos: Vector3, hit: BasePart): number
	local pad = StealConfig.Landing.Pad * (self._jumpForgiveness or 1)
	local local_ = hit.CFrame:PointToObjectSpace(pos)
	local dx = math.max(math.abs(local_.X) - (hit.Size.X * 0.5 + pad), 0)
	local dy = math.max(math.abs(local_.Y) - hit.Size.Y * 0.5, 0)
	local dz = math.max(math.abs(local_.Z) - (hit.Size.Z * 0.5 + pad), 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--[[ The car the prompt is offering, or nil: the nearest one within `Prompt.Range` of the flight.

	Run every frame of the air and of the perch, and it is the ONLY thing that decides what E takes —
	so what the billboard is sitting on and what you get are the same lookup, not two that agree.

	ONLY WHILE DESCENDING, and that guard is load-bearing rather than tidy — it is the same rule
	`_landingTarget` has always had ("launching up through a car's volume can't mount you"), and it
	closes a hole the range test opens on its own. LANES ARE 15 STUDS APART. A car in the next lane
	is 15 across, less the padded half-width of its volume (~9.2), so it sits about SIX studs away
	while you are still sitting in your own car — comfortably inside `Prompt.Range`. Without this,
	tapping Space and immediately pressing E would take the car beside you having flown nothing at
	all, and the signature mechanic would have a one-frame shortcut past it. The rise is ~0.45s, so
	the offer cannot appear until you are over the top and genuinely coming down on something.

	Ties are real and have to be resolved rather than left to iteration order, for the same reason
	`_landingTarget` resolves them: two cars in neighbouring lanes are 15 apart, and a range of 18
	reaches both from the strip between them. Nearest wins on surface distance; when that is a dead
	heat — which it is for every point INSIDE both volumes, where both read 0 — it falls through to
	the normalised `_boxDistance`, so the answer agrees with the one the marker and the landing test
	would give. Same question, same car, whichever of the three asks it. ]]
--[[ How far E reaches, in surface studs — `Prompt.Range`, or the tutorial's wider one.

	THE FIRST STEAL A PLAYER EVER MAKES IS NOT ALLOWED TO MISS, and this is one of the two halves of
	that. The other is `TutorialDirector._placeStealTarget`, which aims the target at where the arc
	actually lands rather than at a distance that looks right. Even aimed, the placement cannot be
	exact: the car's cruise is rolled, the player keeps driving for the beat's grace, and they can
	steer in the air. The last dozen studs of slop are absorbed by reaching further instead.

	IT WIDENS THREE THINGS AT ONCE, which is why it is one number rather than three: the prompt that
	says E works, the tutorial's mid-air freeze (`TutorialController._watchFreeze` holds the world on
	the same condition the prompt is drawn under, deliberately), and the perch that catches a flight
	which came down a lane short. All three ask `_findCandidate`; none of them can disagree.

	THE LUNGE DOES NOT GET LONGER WITH IT, which is the objection to widening this that has to be
	answered. E is pressed from wherever the freeze caught the player, and that freeze is taken at the
	arc's CLOSEST approach rather than on the first frame E would work. Reaching further buys the beat
	more ways to succeed; it does not buy the dive more distance to cover.

	Scoped to `isRigged`, so it is the same switch as the damage floor and the truck timings, and it
	goes away with them at the steal. ]]
function StealController._reach(self): number
	local range = StealConfig.Prompt.Range * (self._jumpForgiveness or 1)
	local step = Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute)
	if TutorialConfig.isRigged(step) then
		return math.max(range, TutorialConfig.Rig.Stage.StealTarget.Reach)
	end
	return range
end

function StealController._findCandidate(self, pos: Vector3)
	local traffic = self._traffic
	--[[ With the lock on, E offers the locked car and nothing else (`StealConfig.Lock`, `_pickLock`),
		and its reach is measured FLAT, in the road plane, height ignored (2026-10-20: "even though
		you're on top of the car you want it's still yellow because your character is so far up"). So
		over the car is in reach, on the way up as much as on the way down, and the lunge covers the
		drop. Before the arc's apex check below, which the lock does not use. ]]
	if StealConfig.Lock.Enabled then
		local locked, f = self._lockRec, self._flight
		if traffic and f and locked and not locked.physical and locked.hit and locked.hit.Parent and self:_canTake(locked) then
			local surface = self:_roadSurfaceDistance(f.cross - locked.cross, f.along - locked.along, locked.hit.Size)
			if surface <= self:_reach() then
				return locked, surface
			end
		end
		return nil, math.huge
	end
	if not (traffic and self._flight and self._flight.yVel <= 0) then
		return nil, math.huge
	end
	local range = self:_reach()
	local best, bestSurface, bestBox

	for _, rec in traffic:getCars() do
		local hit = rec.hit
		-- `physical` is a car that has been knocked out of the lane system and is falling over; it is
		-- not a thing you can stand on, which is the same exclusion `_landingTarget` makes.
		if not rec.physical and hit and hit.Parent and self:_canTake(rec) then
			local surface = self:_surfaceDistance(pos, hit)
			if surface <= range then
				local local_ = hit.CFrame:PointToObjectSpace(pos)
				local box = self:_boxDistance(local_.X, local_.Z, hit.Size)
				local better = if not best
					then true
					elseif surface < bestSurface - 1e-3 then true
					elseif surface > bestSurface + 1e-3 then false
					else box < bestBox
				if better then
					best, bestSurface, bestBox = rec, surface, box
				end
			end
		end
	end
	--- Sticky like the lock (`StealConfig.Lock.Stick`): the car E would already take keeps the offer
	--- unless another is clearly nearer, so two cars side by side do not trade it back and forth.
	local held = self._candidate
	if StealConfig.Lock.Enabled and held and held ~= best and held.hit and held.hit.Parent and not held.physical and self:_canTake(held) then
		local heldSurface = self:_surfaceDistance(pos, held.hit)
		if heldSurface <= range and heldSurface - (bestSurface or math.huge) < StealConfig.Lock.Stick then
			best, bestSurface = held, heldSurface
		end
	end
	-- The distance comes back with the car, because the tutorial's freeze needs to know when the arc
	-- has stopped getting closer and re-measuring it from outside would be a second answer to a
	-- question this already answered. `math.huge` for "nothing", so a caller can compare without a
	-- nil check.
	return best, bestSurface or math.huge
end

--[[ Where the avatar is pinned for the landing: one fixed point on the car, and the clip does
	everything else from there.

	FIXED IS THE POINT (StealConfig.Mount.Anchor has the measurements). `Animations.Clips.Land` is
	authored against a single root: it holds the feet ~0.85 studs above it while the character is on
	the roof, then over its last third walks the body 3.8 studs to the driver's side and 3.4 studs
	down, which is the player climbing into the seat. Re-placing the root per frame — however
	cleverly — therefore fights the animation for the same body, and the version of this that planted
	the rig's lowest point on the roof every frame did exactly that: it cancelled the descent and the
	character walked off the side of the car and stood on the road instead of getting in.

	So the anchor holds the roof plane, offset by `Anchor`, and the clip is left alone.

	`hit.CFrame` carries the car's own orientation, so `Anchor` composes in the CAR's frame — -X the
	driver's side, -Z the nose — and only the final `lookAt` flattens it back onto the road's
	heading. That flattening is deliberate and predates this: the avatar should face down the road
	rather than roll with a car mid-lane-change. ]]
function StealController._roofCFrame(self, rec): CFrame
	local hit = rec.hit
	local anchor = StealConfig.Mount.Anchor
	local top = hit.CFrame * CFrame.new(anchor.X, hit.Size.Y * 0.5 + anchor.Y, anchor.Z)
	return CFrame.lookAt(top.Position, top.Position + self._info.forward)
end

-- === Flying the car you left ================================================

--[[ Carry the real car along under the flight, and swing its door.

	Height: the car keeps the deck height it bailed at rather than climbing with the arc. Everything
	downstream expects that — RaceCameraController measures air time as `pos.Y - deckY`,
	ObstacleController's wall sensor rides the HitBox, and the handoff is going to place the car at
	the deck anyway.

	NEITHER AXIS COPIES THE FLIGHT, and both departures are the difference between a car you left
	behind and a car stuck to you.

	ACROSS: `f.cross` is the flight's live lateral drift, the arc that carries you out of your lane and
	onto the target. Fed back into the car it slid sideways in perfect lockstep with the player, which
	read as the car chasing them through the air. Held at `f.startCross` it stays in the lane it was
	already in.

	ALONG: the car falls back behind the flight, fast at first and then steadily. Copying `f.along`
	parked it permanently underneath the player — with `Launch.ForwardKeep = 1` you leave at exactly
	the car's speed, so nothing separates you from it on its own. The gap is AUTHORED rather than
	simulated, and `StealConfig.BailedCar` carries the reason: the player is already shedding speed via
	`Flight.Glide`, so a deceleration on the car only counts for what it sheds on top of that, and one
	sized against the car's own speed moved it a third of a stud across a whole bail.

	THE SECOND TERM IS THE ONE THAT MATTERS TO THE SHOT. An eased gap alone SETTLES, and a car sitting
	at a constant distance behind you is a reference object moving WITH the arc — it made every jump
	read as short no matter how far it actually went, because on a landmark-free tiling road that car
	is the only thing measuring the distance. `Drift` keeps it opening, so the car recedes out of frame
	and what's left is you and the road going past. `Lag` is the beat you watch; `Drift` is the one you
	feel.

	`MaxLag` is what keeps that safe for the car's other job — being the road anchor that
	`RoadController._loop`, `TrafficController._playerAlong` and the camera all read. Bounded, the
	trail can never diverge; unbounded, the world would stream around a point behind the player.

	The pivot-to-primary offset is applied rather than ignored, so `car.PrimaryPart.Position` lands
	exactly on the flight's road coordinates instead of a constant couple of studs off them. ]]
function StealController._flyCar(self, dt: number)
	local car = self._car
	if self._lobby or not (car and car.Parent and car.PrimaryPart) then
		return
	end
	local f = self._flight
	local coast = StealConfig.BailedCar

	-- Ease-out to `Lag`: the shove, over in half a second and while both of you are still in frame.
	local k = if coast.LagTime > 0 then math.clamp(f.t / coast.LagTime, 0, 1) else 1
	local lag = coast.Lag * (1 - (1 - k) * (1 - k))
	-- Then keep opening it, so the car recedes out of the shot instead of holding station behind the
	-- arc. Capped, because this number is also how far the road anchor is allowed to trail.
	lag = math.min(lag + coast.Drift * math.max(f.t - coast.LagTime, 0), coast.MaxLag)

	local pos = self:_worldPos(f.along - lag, f.startCross, self._carY)
	local wantPrimary = CFrame.lookAt(pos, pos + self._info.forward)
	car:PivotTo(wantPrimary * self._primaryToPivot)

	--[[ The door opens on the way out and is already shutting as you drop into the next car, so the
		target is read off the state rather than scheduled: "mount" is the beat where you are arriving,
		and everything before it is the beat where you are leaving. `_unanchorCar` guarantees the shut
		pose at the handoff regardless of how far this got.

		POSED BY DELTA. `poseFrozen` turns the door from wherever it currently is, and the `PivotTo`
		above does NOT flatten it back to shut — it carries the open offset along with the car. So
		what goes in is the frame's change in angle, never the angle itself. ]]
	local cfg = StealConfig.Doors
	if cfg.Enabled then
		local closing = self._state == "mount"
		local want = if closing then 0 else cfg.Angle
		-- Rad/s, matching the servo's `AngularSpeed`, so these read the same as if physics turned it.
		local rate = math.deg(if closing then cfg.CloseSpeed else cfg.OpenSpeed) * dt
		local angle = self._doorAngle or 0
		if angle < want then
			angle = math.min(angle + rate, want)
		elseif angle > want then
			angle = math.max(angle - rate, want)
		end
		CarDoors.poseFrozen(car, angle - (self._doorAngle or 0))
		self._doorAngle = angle
	end
end

-- === Bailing ================================================================

function StealController._canBail(self): boolean
	-- `_downed` matters as much as `_state` here: a whiff goes back to idle immediately (so every
	-- suspended system resumes) but leaves a body on the road and a wreck in flight from the server.
	-- Without this you could bail again from the floor, out of a car you no longer have.
	if not (self._active and self._state == "idle" and not self._wrecked and not self._downed) then
		return false
	end
	local hop = Shard.get("HopController")
	if hop and hop:isFlying() then
		return false
	end
	--[[ THE TUTORIAL OWNS THE JUMP UNTIL THE BEAT THAT TEACHES IT.

		A first-timer who presses Space on BOOST, STEER or SURVIVE is jumping out of a car the next
		four objectives are all written about, and the flight has no target under it because the
		director has not dealt one yet (`TutorialDirector._placeStealTarget` runs on BAIL's grace).
		What they land in is a run the tutorial can no longer describe — and, on the two beats that
		hold the world, a flight inside a freeze, which is the pair of anchor bugs `_onBail` and
		`TutorialController._watchFreeze` each carry a note about.

		Refused here rather than survived there, because those two notes are the same admission
		twice: the jump was reachable on beats that never asked for it. Both of their fixes stay —
		BAIL's own hold is a freeze a bail must still be able to start from — but nothing before
		BAIL can produce one any more.

		READ OFF THE ATTRIBUTE, which is the client's own view of a server-owned value, so the gate
		and the card can never disagree: whatever beat this client is drawing is the beat it is
		gating on. `TutorialConfig.allowsBail` answers yes for a finished tutorial, a bypassed one
		and a switched-off one, so this costs one attribute read on the bail of every other player
		in the game. ]]
	if not TutorialConfig.allowsBail(Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute)) then
		return false
	end
	local info = self._road and self._road:getRoadInfo()
	local car = self._road and self._road:getCar()
	-- GetawayController owns the seated rig from ramp capture through docking. Starting a
	-- flight here would give two controllers the same anchors and competing CFrame writes.
	if car and car:GetAttribute(GetawayConfig.Boarding.Attribute) then
		return false
	end
	return info ~= nil and car ~= nil and car.Parent ~= nil and car.PrimaryPart ~= nil
end

function StealController._onBail(self)
	if not self:_canBail() then
		return
	end

	local info = self._road:getRoadInfo()
	local car = self._road:getCar()
	local primary = car.PrimaryPart
	local seat = car:FindFirstChild("VehicleSeat", true)
	local origin = if seat and seat:IsA("BasePart") then seat.CFrame else primary.CFrame

	self._info = info
	self._car = car
	self._carY = primary.Position.Y
	-- The constant transform from "where the primary part is" to "where the model's pivot is", so
	-- `_flyCar` and the handoff can both aim the primary part and get the pivot right for free.
	self._primaryToPivot = primary.CFrame:ToObjectSpace(car:GetPivot())

	-- The avatar starts at the seat; the flight is tracked in the road's frame from there.
	local along, cross, y = self:_roadCoords(origin.Position)
	local velocity = primary.AssemblyLinearVelocity
	local alongVel = self:_launchAlongSpeed(velocity:Dot(info.forward))
	self._launchY = y
	--[[ The speed we left the road at, kept separately from the flight's live one. `_stepMount`
		overwrites the live value with the TARGET's speed (so the camera follows the car being
		ridden rather than the arc that got there), and `Handoff.InheritVelocity` has to interpolate
		between what we had and what we're taking — which it can't do if both ends read the same
		number by the time it runs. ]]
	-- The throw belongs to the avatar, not to the chassis handed back after a successful steal.
	-- Remember the normalized road momentum here so landing cannot become a hidden 1.5x speed boost.
	self._bailAlongVel = alongVel / StealConfig.Launch.SpeedWindow.ThrowScale
	--- A new jump, a new lock (`StealConfig.Lock`).
	self:_clearLock()
	self._flight = {
		along = along,
		cross = cross,
		y = y,
		alongVel = alongVel,
		crossVel = 0,
		yVel = 0,
		t = 0,
		startCross = cross,
	}

	--[[ FREEZE THE CAR BEFORE ANYTHING ELSE TOUCHES IT.

		Every part, remembering its state, exactly the way RoadController._shiftWorld does — because
		from here on the car is positioned by CFrame writes, and writing a CFrame on a live
		unanchored assembly makes the engine synthesise a reconciliation velocity (Δpos/Δt) that
		flings the car and compounds into a float-overflow runaway. That is a documented bug in this
		codebase, not a hypothetical. Anchored, there is nothing to synthesise.

		=== ASK THE FREEZE WHAT WAS REALLY THERE, DO NOT READ IT OFF THE PART ====================

		A bail can start from inside a hold — the tutorial's BAIL beat is one, by design: the world
		stops, the card asks for the jump, and the jump happens with every part already anchored by
		`DriveController.setFrozen`. Read straight off the part, this loop then records 83 `true`s,
		and `_unanchorCar` faithfully restores them at the handoff. The player completes the steal and
		cannot move: the car is welded to the road, the run is still live, and the next objective is
		asking them to drive to the truck. Measured, exactly that — 0.0 studs in two seconds.

		`frozenAnchor` is the pre-hold value, which is the one that has to come back. Nil when nothing
		is holding the car, which is every ordinary bail. ]]
	local drive = self._drive
	self._carAnchors = {}
	-- Collector highway (`bailLobby`): the car you left is a real one in the open world; it coasts.
	for _, part in (if self._lobby then {} else car:GetDescendants()) do
		if part:IsA("BasePart") then
			local prior = if drive then drive:frozenAnchor(part) else nil
			self._carAnchors[part] = if prior ~= nil then prior else part.Anchored
			part.Anchored = true
		end
	end

	-- Clone the rider BEFORE hiding them, or the clone inherits the hide. `_buildAvatar` is what
	-- loads the clips, so the handle is cleared first: a bail that falls through to the placeholder
	-- must not be left holding the last flight's tracks, which are on a rig that no longer exists.
	self._anim = nil
	self._avatar = self:_buildAvatar(origin) or self:_buildPlaceholder(origin)

	--[[ THE CAR IS DELIBERATELY LEFT VISIBLE, and this is the bail's whole shot: it carries on down
		the lane you left it in with its door up while you arc away from it. Only two of the three
		things involved get hidden.

		THE RIDER STILL DOES. They are welded into that seat, and a visible car means a visible driver
		— you would watch yourself fly out of a car you are still sitting bolt upright inside. The
		flight avatar is the copy that gets to be seen.

		The whiff is the one outcome that puts the car away again; see `_whiff` for why. ]]
	local character = Players.LocalPlayer.Character
	--[[ A RESTORE STILL WAITING FROM THE LAST STEAL GOES FIRST (2026-10-20, a tester: "after stealing a car
		my body disappeared"). The handoff puts the rider back a few frames after the mount
		(`Handoff.SettleFrames`); a bail inside those frames hid a body that was still hidden, so it
		recorded "invisible" as how it looked, and every later restore put it back invisible. The race's
		own leg fix-up then left only the legs showing. Claimed here, as the note at the restore says a
		second flight should, so this hide records the body as it really is. ]]
	local waiting = self._pendingRestore
	if waiting then
		self._pendingRestore = nil
		self:_restoreRider(waiting, false)
	end
	self._riderHidden = if character then hideTree(character) else nil

	--[[ Posed by CFrame rather than by the servo, because the freeze above anchored the door too.
		Warned about here rather than at the landing: an unrigged body is a property of the CAR, so
		the moment it is first asked to open is the moment worth reporting, and reporting it at the
		bail names the beat the player actually saw nothing happen on. ]]
	self._doorAngle = 0
	if StealConfig.Doors.Enabled and #CarDoors.rigs(car) == 0 then
		self.log:warn("Bailed out of a body with no doors rigged — see Modules/CarDoors.rigs.")
	end

	-- Hand every scripted system that touches the car something to do other than touch it.
	if self._drive then
		self._drive:suspend()
	end
	if self._obstacles then
		self._obstacles:setSuspended(true)
	end
	if self._traffic then
		self._traffic:setSuspended(true)
		self._traffic:setStealLaneChangesLocked(true)
	end
	--[[ One getter, two readers. The camera frames the flight with it and the wind is measured
		against it — and they have to be the same one, or the air and the shot end up describing
		different journeys.

		THE WIND CANNOT BE LEFT TO THE CAR HERE, and not because the car has gone quiet: the freeze
		above anchored it, and an anchored assembly goes on reporting the velocity it had at the
		instant it was frozen (WindController._velocity has the measurement). A bail taken flat out
		used to leave the wind at full for the whole flight — and a whiff, which never unfreezes it,
		left it running until the race ended. ]]
	local subject = function()
		return self:_cameraSubject()
	end
	if self._cam then
		self._cam:setFlight(subject)
	end
	if self._wind then
		self._wind:setFlight(subject)
	end

	self._state = "launch"
	--- The press's own frame. `StealJuiceConfig` header on why every beat is fired where it happens.
	self:_sfx("Bail")
	self._candidate = nil
	self._stealBufferedUntil = 0
	self._perchOn = nil
	self._mountFrom = nil
	--[[ Out of the seat, onto the roof, thrown — one clip covering the launch and the rise, handed
		over to the freefall loop by `_updateAnimation` as it runs out. Started here rather than in
		`_stepLaunch` so that its first frame is the frame Space was pressed: `Launch.Time` is 0.08s
		and a clip that waited for the next Heartbeat would miss an eighth of the beat it exists to
		cover. ]]
	self._falling = false
	if self._anim then
		self._anim:play("Bail", StealConfig.Animations.Fade)
	end
	self:_ensureMarker()
	self:_ensurePrompt()
	-- E only means anything from here until the flight ends; `_releaseSystems` gives it straight back.
	self:_bindSteal()
	self:_publish()
end

-- === Per-frame ==============================================================

--[[ What the camera pulls once per render frame, from `setFlight`. Two subjects, one getter.

	IN FLIGHT it's the integrated arc state — position and velocity together, from one place, so the
	shot can never mix a position from this frame with a velocity from the last, and because the
	avatar is anchored and therefore reports no velocity of its own (see CameraConfig.Flight).

	DOWNED it's the ragdoll, read live off the part, because now physics owns it and its velocity is
	genuinely its own. `downed` swaps the camera onto the close, low, tilted-down shot that looks at
	the body — see CameraConfig.Downed. Returning nil once the ragdoll is gone hands the shot back
	to the car, which is the safe direction to fail in. ]]
function StealController._cameraSubject(self)
	if self._downed then
		local root = self._avatar and self._avatar.PrimaryPart
		if not (root and root.Parent) then
			return nil
		end
		return { position = root.Position, velocity = root.AssemblyLinearVelocity, downed = true }
	end
	return self._flightView
end

function StealController._publish(self)
	local f = self._flight
	self._flightView = {
		position = self:_worldPos(f.along, f.cross, f.y),
		velocity = self._info.forward * f.alongVel + self._info.cross * f.crossVel + Vector3.yAxis * f.yVel,
	}
end

--[[ The scripted launch: climbing up out of the seat, before ballistics take over.

	Purely a rise over `Launch.Time` with the car's speed carried along, so the *Getting out of your
	car* and *Jumping* clips have a beat to live in. With `Time` at 0 this state is skipped entirely
	and the arc starts on the frame Space is pressed, which is the tightest-feeling version and the
	useful A/B when tuning. ]]
function StealController._stepLaunch(self, dt: number)
	local f = self._flight
	local launch = StealConfig.Launch
	f.along += f.alongVel * dt

	if launch.Time <= 0 or f.t >= launch.Time then
		-- Fixed across progression: the upgrade enlarges correction and capture forgiveness rather
		-- than changing the trajectory the player is learning.
		f.yVel = launch.Up
		self._state = "air"
		self:_sfx("Whoosh")
		return
	end
	-- Ease out, so the rise decelerates into the throw rather than stopping dead at the top of it.
	local a = math.clamp(f.t / launch.Time, 0, 1)
	f.y = self._launchY + launch.Rise * (1 - (1 - a) * (1 - a))
end

--[[ The arc: one step of `_advance` on the live flight, then the ways it can end.

	AIR CONTROL IS THE CAR'S OWN STEERING INPUT, read straight off DriveController (which keeps
	stashing it while suspended for exactly this). No second keybind, and it works on the keyboard,
	the stick and the touch slider without any of them knowing this feature exists. The slow half of
	the arc is what makes it worth having: by the time you're low enough to read the roofs you're
	still descending at ~20 studs/s, so a late lane correction is a real option rather than a wish.

	NOTHING HERE TAKES A CAR. Getting near one lights the prompt (`_findCandidate` → `_updatePrompt`) and
	E is what commits — see `_onSteal`. So this function only ever ends the ARC, into one of three
	places: a perch on a roof it came down on, a perch on the tarmac beside something still reachable,
	or a whiff. `StealConfig.Prompt.Enabled = false` restores the original behaviour whole, where
	touching a volume mounted you on contact and there was no perch at all. ]]
function StealController._stepAir(self, dt: number)
	local f = self._flight
	local cfg = StealConfig.Flight

	local input = if self._drive then self._drive:getSteerInput() else 0
	--[[ FORWARD AND BACK IN THE AIR (`StealConfig.Lock.AlongSteer`, 2026-10-20): the throttle the car was
		driven with, W/S or the on-screen gas and brake pedals (`DriveController.getThrottleInput`, kept
		live through the suspend). It leans where the lock looks (`_pickLock`'s aim), so holding gas
		moves the target to the car ahead and brake to the one behind, and it shifts the glide's pace
		the same way below. ]]
	local push = if self._drive and StealConfig.Lock.AlongSteer then self._drive:getThrottleInput() else 0
	--- On a thumb device the stick flies it too (`_flightStick`): across is steer (+1 = LEFT, the
	--- drive's convention, so the stick's right is negative), up the screen is forward.
	local stick = self:_flightStick()
	input = math.clamp(input - stick.X * STEER_LEFT, -1, 1)
	if StealConfig.Lock.AlongSteer then
		push = math.clamp(push - stick.Z, -1, 1)
	end
	--[[ ...AND THE KEYS, READ HERE DIRECTLY (2026-10-20: "unable to move around on keyboard with wasd").
		The drive's stashed steer and throttle are what the car was being driven with, and in the air
		that hand-off is the one link in the chain that can go quiet; a held key is not a guess. A key
		held wins over the stash, either axis on its own. ]]
	local keyAcross = (if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then 1 else 0)
		- (if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then 1 else 0)
	if keyAcross ~= 0 then
		input = keyAcross * STEER_LEFT -- +1 = LEFT in the drive's convention, whatever `PositiveSteerIsLeft` says
	end
	local keyAlong = (if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then 1 else 0)
		- (if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then 1 else 0)
	if keyAlong ~= 0 and StealConfig.Lock.AlongSteer then
		push = keyAlong
	end
	--- A diagonal is one direction, not two at full strength (2026-10-20: "holding W and D at the same
	--- time ... makes you fly super super quick"): the pair is capped at length 1, as a stick is.
	local strength = math.sqrt(input * input + push * push)
	if strength > 1 then
		input, push = input / strength, push / strength
	end
	f.push = push
	--- The lock, re-picked every frame of the air (`_pickLock`); the marker draws what this names.
	if StealConfig.Lock.Enabled then
		local dead = StealConfig.Lock.DeadZone
		self._lockRec = self:_pickLock(f, math.abs(input) >= dead or math.abs(push) >= dead)
	end
	--[[ HOMING ALONG THE ROAD (`StealConfig.Lock.Home`, 2026-10-20: in faster cars "either got launched"
		past the car she wanted). The jump carries the bailed car's own pace, and a fast car's cruise
		is well over traffic's, so the arc overtook the target. With a car locked, the along speed eases
		to THAT car's speed plus enough to close the gap (`HomeGain` per second, capped at `HomeMax`),
		so you come down over the car you chose whatever you were driving. Along is never the player's
		to steer, so this runs whether or not they are steering; the glide brake in `_advance` stands
		down while it does (`f.homing`). ]]
	local home = StealConfig.Lock
	--[[ THE PLAYER'S INPUT WINS (2026-10-20: "I still can't move ... the movement should be very visible").
		The homing and the assist were pulling every input straight back onto the locked car, so a held
		key barely showed. Now any input switches both off, and they stay off `ManualHold` seconds after
		the last of it, so the player flies exactly where they steer; only hands-off do the helpers take
		over, onto whatever car the lock now names (`_pickLock` re-aims as they move). ]]
	local dead = home.DeadZone
	if math.abs(input) >= dead or math.abs(push) >= dead then
		self._manualUntil = f.t + (home.ManualHold or 0)
	end
	local handsOff = f.t >= (self._manualUntil or 0)
	local homeTo = if home.Enabled and home.Home and handsOff then self._lockRec else nil
	f.homing = homeTo ~= nil or not handsOff
	if homeTo then
		local close = math.clamp((homeTo.along - f.along) * home.HomeGain, -home.HomeMax, home.HomeMax)
		f.alongVel += (homeTo.speed + close - f.alongVel) * (1 - math.exp(-dt * home.HomeEase))
	elseif not handsOff then
		--- Flying by hand: the pace of the car you are over (or the glide's), plus the lean, quickly.
		local base = if self._lockRec then self._lockRec.speed else self:_glideSpeed()
		--- Back has its own, bigger number (`AlongBack`): past the road's pace, so brake flies you
		--- BACKWARDS down the road rather than just parking you in the air over it.
		local want = base + push * (if push >= 0 then home.AlongSpeed or 0 else home.AlongBack or home.AlongSpeed or 0)
		f.alongVel += (want - f.alongVel) * (1 - math.exp(-dt * (home.ManualEase or home.HomeEase)))
	end
	local want = input * STEER_LEFT * cfg.SteerSpeed * (self._jumpForgiveness or 1)
	--[[ THE ASSIST (`StealConfig.Lock.Assist`): hands off the stick and a car locked, ease across toward
		the cross that car's lane will be at touchdown, so you come down on its roof rather than beside
		it. A share (`AssistGain`) of the speed that would get there exactly, re-asked every frame, so
		it converges without snapping; capped at the player's own steering speed. ]]
	local lock = StealConfig.Lock
	if lock.Enabled and lock.Assist and handsOff and self._lockRec and self._lockCross then
		local need = (self._lockCross - f.cross) / math.max(self._lockT or 0, 0.25)
		local top = cfg.SteerSpeed * (self._jumpForgiveness or 1)
		want = math.clamp(need * lock.AssistGain, -top, top)
	end
	self:_advance(f, dt, want, self._info.deckY)

	local pos = self:_worldPos(f.along, f.cross, f.y)
	local target = self:_landingTarget(pos)
	--- Came down on a roof: that car is the target now, whatever was locked, so the car under your
	--- feet is the one E (and a touch screen's auto-steal) takes.
	if target and StealConfig.Lock.Enabled then
		self._lockRec = target
	end
	local grounded = f.y <= self._info.deckY + StealConfig.Landing.DeckGrace or f.t >= cfg.MaxTime

	if not StealConfig.Prompt.Enabled then
		if target then
			self:_mount(target)
		elseif grounded then
			self:_whiff()
		end
		return
	end

	self._candidate, self._candidateAt = self:_findCandidate(pos)
	self:_updatePrompt(dt)
	if self:_consumeBufferedSteal() then
		return
	end

	if target then
		if self:_autoSteal(target) then
			return
		end
		self:_perch(target) -- came down on a roof: stand on it, prompt still up
	elseif grounded then
		--- No car in E's reach, but the highlighted one close by: that one (`StealConfig.Lock.LandReach`).
		if self:_autoSteal(self._candidate or self:_lockNearby()) then
			return
		end
		-- Down on the road. Still a perch if anything is in reach, because "I mistimed the press" and
		-- "I came down a lane short" should both still be recoverable — that is the whole point of
		-- `Prompt.Grace`. Nothing in reach is the honest splat it always was.
		if self._candidate then
			self:_perch(nil)
		else
			self:_whiff()
		end
	end
end

--[[ The arc is over and you have not pressed E yet. `Prompt.Grace` seconds to change that.

	Two shapes, one state. `rec` is the roof you came down on, and you ride it — the car is driving,
	so this tracks it. `nil` is the tarmac version: you landed beside something, on your feet, sliding.
	Either way the prompt is live and E still works, which is what makes a late press cost you nothing
	and a missing one cost you the run.

	IT IS NOT A SECOND CHANCE AT AIMING. The candidate is re-read every frame, so a car that drives
	out of range takes the offer with it — on the tarmac that happens in well under a second, because
	you have stopped and it has not. The window is for your hand, not for the arc. ]]
function StealController._perch(self, rec)
	local f = self._flight
	self._state = "perch"
	self._perchOn = rec
	self._perchAt = f.t
	-- Posed from this frame rather than next: `_step`'s generic placement reads the flight's road
	-- coords, so writing them here is what puts the avatar in place without a frame of hanging in the
	-- air beside the car, or of standing a few inches under the road.
	if rec then
		f.along, f.cross, f.y = self:_roadCoords(self:_roofCFrame(rec).Position)
		f.alongVel, f.crossVel, f.yVel = rec.speed, rec.lateral, 0
	else
		-- Stood on the deck by the same anchor the roof uses, NOT at `Landing.DeckGrace`. That number
		-- is the height at which a flight counts as having COME DOWN, and it is deliberately
		-- generous for that job — parking the body there left it standing three studs over the road.
		-- Only the clip's on-roof second is ever seen here (`Prompt.Grace` is 0.45s and then the
		-- whiff ragdolls), which is precisely the stretch `Anchor.Y` was measured against.
		f.y = self._info.deckY + StealConfig.Mount.Anchor.Y
		f.yVel = 0
	end
	-- On a roof or on the tarmac, the arc is over and the flip has to stop. The landing clip is the
	-- same one either way: it opens on an arrival, which is what has just happened.
	self:_playLand()
	self:_hideMarker()
end

function StealController._stepPerch(self, dt: number)
	local f = self._flight
	local rec = self._perchOn
	if rec and not (rec.hit and rec.hit.Parent) then
		rec = nil -- the car we were standing on got recycled out from under us
		self._perchOn = nil
	end

	if rec then
		-- Re-read off the car rather than integrated, exactly as the mount does, so the hidden car and
		-- therefore road streaming, traffic and the camera all track what we're riding.
		f.along, f.cross, f.y = self:_roadCoords(self:_roofCFrame(rec).Position)
		f.alongVel, f.crossVel, f.yVel = rec.speed, rec.lateral, 0
	else
		-- Standing on the deck, shedding the arc's speed. Eased rather than stopped dead: you arrived
		-- at ~39 studs/s and a body that halts on contact reads as hitting a wall.
		f.y = self._info.deckY + StealConfig.Mount.Anchor.Y
		f.yVel = 0
		f.alongVel += (0 - f.alongVel) * (1 - math.exp(-dt * PERCH_SLIDE_EASE))
		f.along += f.alongVel * dt
	end

	--- Standing on a roof, that car is the lock; on the tarmac the lock stays the car it was.
	if rec and StealConfig.Lock.Enabled then
		self._lockRec = rec
	end
	self._candidate, self._candidateAt = self:_findCandidate(self:_worldPos(f.along, f.cross, f.y))
	self:_updatePrompt(dt)
	if self:_consumeBufferedSteal() or self:_autoSteal(self._candidate) then
		return
	end

	if not self._candidate or f.t - self._perchAt >= StealConfig.Prompt.Grace then
		self:_whiff()
	end
end

--[[ Standing on the roof, taking the car off the person in it. The car underneath is still driving —
	that's the shot, and `TrafficController._updateCars` keeps a frozen car moving for exactly this
	reason — so the flight's road coordinates are re-read off it every frame rather than integrated,
	which also keeps the hidden car (and therefore road streaming and traffic) tracking the target
	instead of the arc that got us here.

	THIS USED TO BE DEAD AIR and is now the beat the mechanic is named after. It runs for as long as
	the landing clip does (`_mountBeat`, ~1.63s against 0.3s before), and three things share it: the
	player's landing, the door coming up, and the driver going over the side (`_stepDriver`). The
	state was always shaped for this — plan §4 kept it as a state precisely so the throw would have
	somewhere to live. ]]
function StealController._stepMount(self, dt: number)
	local rec = self._target
	if not (rec and rec.hit and rec.hit.Parent) then
		self:_whiff() -- the car we landed on went away; nothing to take
		return
	end

	-- Before reading it back: the car speeds up under you for the whole beat (`Mount.CatchUp`).
	self:_catchUp(rec, dt)
	if self._preparedBody then
		debug.profilebegin("Steal.PrepareBody")
		CarBody.stepPrepared(self._preparedBody, StealConfig.Handoff.PreparePartsPerFrame)
		debug.profileend()
	end

	local roof = self:_roofCFrame(rec)
	local along, cross, y = self:_roadCoords(roof.Position)
	local f = self._flight
	f.along, f.cross, f.y = along, cross, y
	f.alongVel, f.crossVel, f.yVel = rec.speed, rec.lateral, 0

	if self._avatar then
		self._avatar:PivotTo(self:_mountPose(roof))
	end

	--[[ The door, eased open at `Target.OpenSpeed`. Posed absolutely rather than by delta — the one
		place in this file that can be, because `ShellDoors` holds the panel's own angle for us; the
		car's own door has no such holder and `_flyCar` has to track the total by hand. Only ever
		opens: nothing shuts this one, because the shell is recycled and the panel unwound in the
		same frame the handoff runs. ]]
	local door = self._shellDoor
	if door then
		local cfg = StealConfig.Doors.Target
		-- Rad/s, matching the servo's `AngularSpeed` units, so this and the real rig read alike.
		local rate = math.deg(cfg.OpenSpeed) * dt
		self._shellDoorAngle = math.min((self._shellDoorAngle or 0) + rate, cfg.Angle)
		ShellDoors.pose(door, self._shellDoorAngle)
	end

	if f.t - self._mountAt >= self:_mountBeat() then
		self:_finish()
	end
end

--[[ THE THUMB DEVICE'S FLIGHT CONTROLS (`DrivingHudController.setFlying`, 2026-10-20): up from the launch
	to the end of the perch, so a phone flies on Roblox's own stick; down for the mount and once idle.
	Told on a change only. ]]
function StealController._syncFlightHud(self)
	local flying = self._state == "launch" or self._state == "air" or self._state == "perch"
	if flying == (self._hudFlying == true) then
		return
	end
	self._hudFlying = flying
	local hud = Shard.get("DrivingHudController")
	if hud and hud.setFlying then
		hud:setFlying(flying)
	end
end

--[[ The stick's move vector while the thumb flight controls are up (`_syncFlightHud`), else zero.
	Camera-relative as Roblox gives it, and the flight camera looks down the road, so X is across
	(right positive) and -Z is up the road. Never yields: a missing PlayerModule is simply no stick. ]]
function StealController._flightStick(self): Vector3
	--- Only where the HUD really switched to the stick (a thumb device). On a keyboard the same move
	--- vector is WASD, already read above, and reading it twice is how the two came to fight.
	local hud = Shard.get("DrivingHudController")
	if not (self._hudFlying and hud and hud._flying == true) then
		return Vector3.zero
	end
	if self._stockControls == nil then
		local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		local ok, controls = pcall(function()
			return (require(module :: any) :: any):GetControls()
		end)
		self._stockControls = if ok and controls then controls else false
	end
	local controls = self._stockControls
	if not controls then
		return Vector3.zero
	end
	local ok, move = pcall(function()
		return controls:GetMoveVector()
	end)
	return if ok and typeof(move) == "Vector3" then move else Vector3.zero
end

function StealController._step(self, realDt: number)
	self:_syncFlightHud()
	if self._state == "idle" then
		return
	end

	local info = self._road and self._road:getRoadInfo()
	local car = self._road and self._road:getCar()
	if not (info and car and car.Parent and car.PrimaryPart) then
		-- The race went away under us (a leave, a death, a wreck mid-flight). Put back what we can
		-- and get out of the way rather than integrating against nothing.
		self:_abort()
		return
	end
	self._info = info
	self._car = car

	self:_updateTimeScale(realDt)
	local dt = realDt * TimeScale.get()
	self._flight.t += dt

	if self._state == "launch" then
		self:_stepLaunch(dt)
	elseif self._state == "air" then
		self:_stepAir(dt)
	elseif self._state == "perch" then
		self:_stepPerch(dt)
	elseif self._state == "mount" then
		self:_stepMount(dt)
	end

	-- A state handler may have finished the steal outright; publishing against a torn-down flight
	-- would resurrect it for the camera for one frame.
	if self._state == "idle" then
		return
	end

	self:_updateAnimation()
	self:_stepDriver()
	self:_publish()
	if self._avatar and self._state ~= "mount" then
		local pos = self._flightView.position
		self._avatar:PivotTo(CFrame.lookAt(pos, pos + info.forward))
	end
	self:_flyCar(dt)
	if self._lobby then
		self:_pinRider()
	end

	--- With the lock on, the marker is up from the launch to the end of the perch: the target is named
	--- the moment you leave the car and stays named until E takes it (`StealConfig.Lock`).
	if self._state == "air" or (StealConfig.Lock.Enabled and (self._state == "launch" or self._state == "perch")) then
		self:_updateMarker(dt)
	else
		self:_hideMarker()
	end
end

--[[ Keep the clips in step with the flight: hand the bail clip over to the freefall loop, and keep
	both rigs on the scaled clock.

	THE HANDOVER IS ON A TIMER, NOT ON THE TRACK'S `Stopped` EVENT, and that is the one decision in
	here worth defending. An event fires on the ENGINE's clock; everything else about a flight runs
	on `TimeScale`'s. They agree exactly at 1.0 and nowhere else — so the moment slow motion is
	switched on (StealConfig.SlowMo, plumbed and waiting), an event-driven handover would fire while
	the clip on screen was still a third of the way through the throw. Comparing flight time against
	the clip's own length keeps the two stretched by the same factor, because `setSpeed` below is
	stretching the clip by exactly the number the flight clock is scaled by.

	Only the launch and the air get it. A perch or a mount has already played the landing, and a
	freefall loop fading in over a body standing on a roof is the failure this guard exists for. ]]
function StealController._updateAnimation(self)
	local scale = TimeScale.get()
	local beat = StealConfig.Mount.PlaybackSpeed
	if self._driverAnim then
		-- The throw only ever plays inside the mount beat, so it always runs at the beat's speed.
		self._driverAnim:setSpeed(scale * beat)
	end

	local anim = self._anim
	if not anim then
		return
	end
	-- The landing clip plays from the perch and through the mount at the beat's speed; the bail and
	-- freefall play as authored.
	local landing = self._state == "perch" or self._state == "mount"
	anim:setSpeed(scale * (if landing then beat else 1))

	if self._falling or (self._state ~= "launch" and self._state ~= "air") then
		return
	end
	if self._flight.t >= anim:length("Bail") - FALL_LEAD then
		self._falling = true
		anim:play("FreeFall", StealConfig.Animations.Fade)
	end
end

--[[ You are on a car. Plays at whichever of the two beats gets there first — the arc ending on a
	roof (`_perch`) or E committing (`_mount`) — and is a no-op the second time, so a perch that
	turns into a steal keeps the landing it already started rather than snapping back to the top of
	it. The clip holds its last pose when it runs out, which is what makes that safe. ]]
function StealController._playLand(self)
	if self._anim then
		self._anim:play("Land", StealConfig.Animations.Fade)
	end
end

--[[ Ease the world into and out of slow motion, on REAL time.

	Real time on purpose, and it's the one thing in this file that must not be scaled: easing the
	ramp with the scaled dt would make the ramp slow itself down as it took effect, so it would
	never arrive. Off by default this pass — see StealConfig.SlowMo. ]]
function StealController._updateTimeScale(self, realDt: number)
	local cfg = StealConfig.SlowMo
	--[[ THE CINEMATIC'S CONTACT PULSE (`StealJuiceConfig.Cinematic.SlowMo`, 2026-09-30), on the same
		ramp as the flight's own slow motion so the two can never fight over `TimeScale`: while the
		pulse is live it is the target, and once it ends the ramp eases back to 1 on the pulse's own
		`EaseOut`. With neither live and the scale already at 1 this returns exactly as it used to. ]]
	local pulse = StealJuiceConfig.Cinematic.SlowMo
	local cine = self._cine
	local pulsing = cine ~= nil and pulse.Enabled and os.clock() - cine.startReal < pulse.Seconds
	if pulsing or (cine ~= nil and TimeScale.getRaw() < 1) then
		local current = TimeScale.getRaw()
		local goal = if pulsing then pulse.Scale else 1
		local time = math.max(if pulsing then pulse.EaseIn else pulse.EaseOut, 1e-3)
		TimeScale.set(current + math.clamp(goal - current, -realDt / time, realDt / time))
		return
	end
	if not cfg.Enabled then
		return
	end
	-- The perch counts as air for this, and that is not a technicality: it is the tail of the same
	-- decision — the prompt is up and E is still live — so letting time ramp back to normal there
	-- would speed the world up exactly as the player is deciding. It slows for the beat, not the state.
	local slowing = self._state == "air" or self._state == "perch"
	local target = if slowing then cfg.Scale else 1
	local time = math.max(if slowing then cfg.EaseIn else cfg.EaseOut, 1e-3)
	-- A linear ramp, capped at one full traversal per `time` seconds. Linear rather than
	-- exponential on purpose: an exponential approach never quite arrives, and "never quite back to
	-- real time" is a world that stays subtly slow for the rest of the run.
	--
	-- `getRaw` and not `get`, because the tutorial can HOLD the world at zero in the middle of a
	-- flight (the paused mid-air steal is one of its beats). Through `get` this ramp would read its
	-- own value as 0 for every frame of that hold, step down from there, and come out of the pause
	-- pinned at the 0.05 floor with the whole ease-out still to do. The ramp owns `scale`; the hold
	-- is a layer over the top of it that this must not see. See Modules/TimeScale.
	local current = TimeScale.getRaw()
	local step = realDt / time
	TimeScale.set(current + math.clamp(target - current, -step, step))
end

-- === Outcomes ===============================================================

function StealController._mount(self, rec)
	local f = self._flight
	--[[ Where the lunge starts. Sampled here rather than read off `_flightView`, which is still LAST
		frame's — the state handlers all run before `_publish`. Since E can be pressed from anywhere
		inside `Prompt.Range`, this is genuinely somewhere else: up to a car length out, and usually
		above. ]]
	self._mountFrom = self:_worldPos(f.along, f.cross, f.y)
	self._target = rec
	self._mountAt = f.t
	self._state = "mount"
	if self._traffic then
		self._traffic:freezeCar(rec)
	end
	CarBody.discardPrepared(self._preparedBody)
	self._preparedBody = nil
	if StealConfig.Handoff.PrepareBody and not self._lobby then
		self._preparedBody = CarBody.prepare(self._car, rec.model)
	end
	-- Placed this frame rather than next: the generic placement in `_step` skips mounted flights, so
	-- without this there'd be one frame of standing wherever the press caught us.
	if self._avatar then
		self._avatar:PivotTo(self:_mountPose(self:_roofCFrame(rec)))
	end

	--[[ The three halves of the landing, all started on this frame because they are one event: you
		come down on the roof, the door goes up, and the driver goes over the side. The clips were
		authored as a matched pair (`Land` on the player, `DriverThrown` on the NPC) and are timed
		against each other rather than against the state machine, so anything that staggers them here
		shows up as the throw happening to nobody. ]]
	self:_playLand()
	self:_openShellDoor(rec)
	self:_throwDriver(rec)
	--- Contact, and the door going with it. The throw's sound waits for the throw (`_releaseDriver`).
	self:_sfx("Land")
	self:_sfx("Door")
	self:_punch("Land")
	self:_startCinematic(rec)

	self:_hideMarker()
	self:_hidePrompt()
end

--[[ Take hold of the stolen car's door so `_stepMount` can swing it.

	A traffic shell has no hinge and no latch, so this is geometry rather than physics — see
	`Modules/ShellDoors`, which also explains why the panel MUST be handed back (`_closeShellDoor`)
	before the redress copies these very meshes onto the player's car. ]]
function StealController._openShellDoor(self, rec)
	local cfg = StealConfig.Doors
	if not (cfg.Enabled and cfg.Target.Enabled and rec.model and rec.model.Parent) then
		return
	end
	self._shellDoor = ShellDoors.rig(rec.model)
	self._shellDoorAngle = 0
end

-- Shut it and give the panel back. Idempotent, and called from every exit — including the ones that
-- never opened it — because a shell released with an unwelded, anchored door in it is broken for the
-- rest of the session, not just for this steal.
function StealController._closeShellDoor(self)
	local door = self._shellDoor
	self._shellDoor = nil
	self._shellDoorAngle = 0
	if door then
		ShellDoors.restore(door)
	end
end

--[[ How long the mount beat runs before the handoff.

	READ OFF THE LOADED TRACK when it can be, rather than off `Mount.Time`. The beat exists to hold
	the landing clip, so the clip is the honest source for its length — and the alternative is a
	constant that a re-upload silently invalidates, where the symptom is the handoff cutting the
	throw off a third of the way through and nothing anywhere saying why. `Mount.Time` is the answer
	when animations are off, when the asset hasn't downloaded, or when `MatchLandClip` is switched
	off to tune the beat by hand. ]]
function StealController._mountBeat(self): number
	local cfg = StealConfig.Mount
	-- The clip plays at `PlaybackSpeed`, so the beat that holds it is that much shorter.
	local speed = math.max(cfg.PlaybackSpeed, 0.1)
	if cfg.MatchLandClip and self._anim then
		local length = self._anim:length("Land")
		if length > 0 then
			return length / speed
		end
	end
	return cfg.Time / speed
end

--[[ The stolen car picks up speed while you take it (`Mount.CatchUp`). Eases the target toward a
	share of the speed you bailed at, capped so it can close on the car ahead in its lane but never
	drive through it. Only ever speeds the target up. ]]
function StealController._catchUp(self, rec, dt: number)
	local cfg = StealConfig.Mount.CatchUp
	local bail = self._bailAlongVel
	if not (cfg.Enabled and self._traffic and type(bail) == "number") then
		return
	end
	local want = bail * cfg.Fraction
	if want <= rec.speed then
		return
	end
	for _, other in self._traffic:getCars() do
		if other ~= rec and other.along > rec.along and math.abs(other.cross - rec.cross) < cfg.LaneWidth then
			local gap = other.along - rec.along - cfg.CarLength
			local allowed = (other.speed or 0) + math.max(0, gap - cfg.MinGap) / math.max(cfg.Horizon, 0.05)
			want = math.min(want, allowed)
		end
	end
	if want <= rec.speed then
		return
	end
	self._traffic:paceCar(rec, rec.speed + (want - rec.speed) * (1 - math.exp(-dt * cfg.Ease)))
end

--[[ The dive onto the roof, across `Mount.LungeTime`.

	Before the prompt, a mount could only start from inside the car's own volume, so putting the
	avatar on the roof was a placement. E can be pressed from `Prompt.Range` away, which makes the
	same placement a teleport — hence an ease instead.

	`LungeTime` RATHER THAN THE WHOLE MOUNT, which is the split the landing clip forced: the beat is
	now ~1.63s and easing the body onto the roof across all of it would have it still drifting in
	while the clip was already standing up and throwing somebody. The dive is the first fifth; the
	rest is spent on the roof.

	Lerped toward the LIVE roof, not a remembered one: the car is still driving, so the target moves
	while you cross to it, and the two motions compose into an arc that lands on a moving car. Ease-out
	so you leave fast and settle, rather than drifting in at a constant rate. ]]
function StealController._mountPose(self, roof: CFrame): CFrame
	local from = self._mountFrom
	local time = StealConfig.Mount.LungeTime
	if not from or time <= 0 then
		return roof
	end
	local a = math.clamp((self._flight.t - self._mountAt) / time, 0, 1)
	a = 1 - (1 - a) * (1 - a)
	local pos = from:Lerp(roof.Position, a)
	return CFrame.lookAt(pos, pos + self._info.forward)
end

--[[ THE HANDOFF. You are now driving that car.

	The car has been hidden and anchored at the deck this whole time, so all four steps below are
	writes on an assembly nothing is simulating — which is exactly why the seam can be one frame
	instead of a negotiation.

	  1. THE REDRESS, FIRST. The bodywork under `Body/` is replaced with the stolen shell's, welded to
	     the same chassis mounts the old one hung off (`Modules/CarBody`), plus the tier, the top speed
	     and the HP refill the server owns.

	     IT HAS TO RUN BEFORE THE POSE, for two independent reasons. The pose measures the car's own
	     BOUNDING BOX to find its ride height, and with 33 bodies in the roster that box is a property
	     of the dress — measure it with the old body and a low car stolen from a tall one is placed by
	     the wrong number. And a WeldConstraint bakes the offset it finds when it binds, so grafting
	     onto an assembly the solver already owns risks cementing whatever the wheels had moved to; here
	     every part is still anchored and nothing can move between placing a mesh and welding it.

	     Unseen, incidentally: `BailedCar.Drift` has left the car ~55 studs back up the road and the
	     camera is on the car being ridden, so the body it changes into is not on screen yet.
	  2. MATCH AT THE DECK, NOT AT THE PIVOT. The shell's `Root` is its wheels-on-deck frame (the
	     source car's pivot dropped to the bottom of its bodywork — TrafficService._buildShell), and
	     the player's car has live suspension, so aligning pivots would bury it or float it by
	     whatever this body's ride height happens to be. We place the car down the road at the
	     shell's position, measure its own bounding box, and lift it so its lowest bodywork sits
	     `Clearance` above the deck — the identical recipe RaceService._spawnCar uses, so the two
	     can't drift apart.
	     AND THE RIDER COMES ALONG FOR FREE. The `SeatWeld` means `PivotTo` on the car moves the
	     seated character with it, exactly, on the same frame — measured, and NOT what the step
	     that used to sit between 2 and 3 assumed. See step 2's note; it is the bug this was
	     reported for.
	  3. CLEAR THE SPACE FIRST. A solid car appearing inside another solid car is resolved by the
	     solver throwing one of them, and the space we're landing in is only free because the shell
	     we landed ON is about to be recycled — a car halfway through a lane change beside it is
	     not. See `_clearLanding`.
	  4. UNANCHOR BEFORE SEEDING THE VELOCITY, never after. An anchored assembly does not hold a
	     velocity — the write is thrown away, and the car would come out of the steal at a dead
	     stop. Same ordering, for the same reason, as `TrafficController._knock`. ]]
function StealController._finish(self)
	if self._lobby then
		self:_lobbyEnd(self._target)
		return
	end
	local rec = self._target
	local car = self._car
	local info = self._info
	local primary = car and car.PrimaryPart
	if not (rec and rec.root and rec.root.Parent and primary) then
		self:_whiff()
		return
	end

	--[[ 0. SHUT THE STOLEN CAR'S DOOR FIRST, and this is a step of the steal rather than tidy-up.
		Step 1 clones these very meshes onto the player's car and `CarDoorRig.apply` then welds them
		into a rig whose SHUT pose is wherever it finds them — so a panel still standing open at 55°
		becomes that car's closed door for the rest of the run. Invisible either way: the shell is
		released a few lines below in the same frame, with no physics step in between. ]]
	self:_closeShellDoor()

	-- 1. Become that car, while it's still anchored and still off screen.
	local tier = (rec.tier and rec.tier.Tier) or 1
	self:_applyTier(car, tier, rec)

	-- 2. Pose.
	local landing = rec.root.Position
	local deckPoint = Vector3.new(landing.X, info.deckY, landing.Z)
	local surface = CFrame.lookAt(deckPoint, deckPoint + info.forward)
	car:PivotTo(surface)
	local bbCF, bbSize = car:GetBoundingBox()
	local belowDeck = info.deckY - (bbCF.Position.Y - bbSize.Y * 0.5)
	car:PivotTo(surface + Vector3.new(0, belowDeck + StealConfig.Handoff.Clearance, 0))

	-- ...and then get it off the boundary geometry, if the shell we landed on was hugging it. The
	-- pose above lands wherever the target happened to be and has never asked whether that is on the
	-- road. See `_fitToRoad` — this is the step that stops a steal in the outside lane ending with
	-- the car buried in the guardrail at a dead stop.
	debug.profilebegin("Steal.RoadClearance")
	self:_fitToRoad(car)
	debug.profileend()

	-- ...and out of the getaway truck, which neither that check nor the traffic sweep below can see:
	-- one filters to the road tiles and the other to the traffic list, and the truck is in neither.
	-- See `_clearTruck` — this is the step that stops a steal taken alongside the truck ending with
	-- the car half inside the trailer floor.
	debug.profilebegin("Steal.TruckClearance")
	self:_clearTruck(car)
	debug.profileend()

	--[[ AND THE RIDER NEEDS NOTHING DOING TO THEM. There was a step here that did it anyway, and that
		step is what this whole function was reported for.

		`car:PivotTo` above already carries the seated character: the stock `SeatWeld` joins their
		`HumanoidRootPart` to the `VehicleSeat`, so moving the model takes the rider with it, exactly,
		on the same frame. Measured on the live rig at both ends of the anchor — car moved 4.00, rider
		moved 4.00, rider's offset from the car's pivot changed by 0.00.

		What was here instead walked `character:GetDescendants()` and wrote `delta * part.CFrame` on
		each one. A CHARACTER IS ONE RIGID ASSEMBLY, so every one of those writes moves the WHOLE
		body, not the part written — 19 BaseParts, 19 applications of `delta`. On a 70-stud handoff
		that put the rider 1337 studs down the road (measured: 1337.2) and dragged the `VehicleSeat`
		out of the car with them. Two things fell out of that, and both were reported as bugs:

		  • `_clearLanding` below sizes its search off `car:GetBoundingBox()`, which on that frame
		    read 1348 studs long — so it shoved or recycled every traffic car in a corridor the
		    length of the road. That is "cars vanishing near a steal", and it is the `%.1f wide`
		    figure its own log line exists to catch.
		  • the unanchor handed the solver a rider a thousand studs from the seat they are welded
		    into, which it resolves by throwing the car.

		`DriveController._resetUpright` and `GetawayController._rideBay` carried the same step for
		the same stated reason and have had it removed too — the reset one is why a car that flipped
		once went on flipping for the rest of the run. If a rider ever genuinely does need carrying,
		move the MODEL once (`character:PivotTo`) or dedupe on `AssemblyRootPart` the way
		`RoadController._shiftWorld` does. Never per part. ]]

	-- 3. Nothing else may be standing where we just put the car — see _clearLanding. Deliberately
	-- the last thing before the unanchor, so it lands in the same window as the target's own
	-- recycle: no physics step runs between here and the velocity seed below.
	debug.profilebegin("Steal.TrafficClearance")
	self:_clearLanding(car, rec)
	debug.profileend()

	-- 4. Let go, then hand it the stolen car's momentum.
	self:_unanchorCar()
	local keep = math.clamp(StealConfig.Handoff.InheritVelocity, 0, 1)
	local mine = self._bailAlongVel or rec.speed
	local alongVel = mine + (rec.speed - mine) * keep
	primary.AssemblyLinearVelocity = info.forward * alongVel + info.cross * rec.lateral
	primary.AssemblyAngularVelocity = Vector3.zero

	--[[ THE CAR'S TOKEN, NOT ITS TIER (2026-09-28, `EncounterConfig`): the server issued this car and
		prices the refill — and later the bank — off its own record of it, so a tier from here would be
		a claim it no longer needs. With encounters off it is the tier, as it always was. ]]
	self:getRemoteEvent("StealLanded"):Fire(if EncounterConfig.Enabled then rec.token else tier)
	if self._traffic then
		self._traffic:releaseCar(rec)
	end
	self.log:info(string.format("Stole a Tier %d.", tier))
	self:_notifyStolen(tier)

	--[[ 5. NO DOOR BEAT HERE ANY MORE. It used to live on the landing, because the bail hid the car
		and there was nothing on screen to swing. Now the door opens at the bail and is already
		shutting through the mount (`_flyCar`), and `_unanchorCar` above put it back on its shut
		offset before the solver was handed the car — so by this point the door is closed, latched
		and part of the main assembly again, which is exactly the state the teleport in step 2 and
		the velocity seed in step 4 need it to be in.

		Note the redress in step 1 REMOVES whatever door parts the old body had, so the rig the unwind
		above talks to is gone by then — which is why `_applyTier` rebuilds it (`CarDoorRig.apply`)
		on the body that replaces it. The ordering is load-bearing: the unwind has to run against
		the OLD rig, before the redress, and the new rig is born shut. ]]

	-- The one path that holds the rider hidden a beat longer (`Handoff.SettleFrames`) — belt and
	-- braces now that the seat weld is known to carry them on the teleport frame itself.
	self:_endFlight(true)
end

--[[ Move the landing inboard until the car is not inside the road's own boundary geometry.

	The handoff poses our car on the shell we landed on, and nothing in the steal has ever asked
	whether that spot is ON the road. A steal taken in the outside lane can therefore materialise the
	car inside `Gameplay.WallEast` and a guardrail — measured on a bench, and the ending is not a
	fling but a WEDGE: the car comes out of the handoff at a dead stop and stays there, which reads
	as the steal having broken it.

	DO NOT DERIVE THIS FROM `DriveWidth`. That is the obvious version and it is wrong twice over: the
	attribute is NOMINAL, measured out to the outer rail line, and THE TWO EDGES ARE NOT BUILT ALIKE
	— probed on the shipping tile, a car is stopped eastbound by a WHEEL on the guardrail and
	westbound by a raised kerb inside `RoadSurface` about 2.5 studs further in. Half of `DriveWidth`
	is thus a line that sits inside solid geometry on both sides, so an edge test derived from it
	never fires. Ask the geometry instead.

	`GetPartsInPart`, never `GetPartBoundsInBox`: the tile's diagonal cable props have enormous
	bounding boxes and a bounds test false-positives across the whole road. `RespectCanCollide` so
	lane lines and scenery are ignored, and the query runs in each part's OWN collision group, for the
	same reason `_clearLanding` avoids spatial queries altogether — a query left in the default group
	answers a question about a collision matrix that is not the one the solver is about to use.

	COSTS ONE CLEAR PROBE ON ALMOST EVERY STEAL. The car is nowhere near an edge, the first pass says
	so, and nothing moves. Only a landing that is genuinely buried walks, and it walks in half-stud
	steps because the two edges stop a car at different offsets and there is no closed form for how
	far in is clear.

	INWARD ONLY, AND CAPPED. A landing that cannot be freed inside `FIT_MAX` is not an edge case — it
	is something standing in the road — and dragging the car across the lanes chasing it would be a
	worse bug than the wedge. That one is put back where it landed and reported.

	Runs BEFORE `_clearLanding` deliberately, so the traffic sweep measures the corrected position;
	otherwise this would move the car into a lane that had just been cleared somewhere else. Yields
	nowhere, so the "no physics step between the pose and the unanchor" guarantee is unchanged. ]]
local FIT_STEP = 0.5
local FIT_MAX = 10

function StealController._fitToRoad(self, car: Model): number
	local road, info = self._road, self._info
	local segments = road and road:getSegments()
	if not (info and segments and #segments > 0) then
		return 0
	end

	local hull = {}
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide then
			table.insert(hull, part)
		end
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = segments
	params.RespectCanCollide = true
	params.MaxParts = 1 -- `buried` only needs a yes/no answer; do not allocate every overlapping road part.

	-- The first thing found, or nil for the ordinary landing. Named rather than counted: the log line
	-- is the only way anyone will ever learn WHICH bit of the tile a landing is meeting.
	local function buried(): BasePart?
		for _, part in hull do
			params.CollisionGroup = part.CollisionGroup
			local hits = workspace:GetPartsInPart(part, params)
			if #hits > 0 then
				return hits[1]
			end
		end
		return nil
	end

	local first = buried()
	if not first then
		return 0
	end

	local _, cross = self:_roadCoords(car:GetPivot().Position)
	local step = info.cross * (if cross >= 0 then -FIT_STEP else FIT_STEP)
	local moved = 0
	while moved < FIT_MAX do
		car:PivotTo(car:GetPivot() + step)
		moved += FIT_STEP
		if not buried() then
			self.log:info(
				string.format("Handoff landing was inside %s; moved it %.1f studs inboard.", first.Name, moved)
			)
			return moved
		end
	end

	car:PivotTo(car:GetPivot() - step * (moved / FIT_STEP))
	self.log:warn(
		string.format(
			"Handoff landing is inside %s and %d studs of inward room did not free it; leaving it where it landed.",
			first:GetFullName(),
			FIT_MAX
		)
	)
	return 0
end

--[[ Move the landing OUT of the getaway truck.

	=== THE BUG THIS EXISTS FOR ===============================================================

	Reported as "stole a car and that truck spawned inside where the car was merging", with the shot
	showing the stolen car half inside the trailer floor with its nose in the rear ramp — and then
	"now stuck". The truck did not spawn on anybody: `_spawn` puts it 300-460 studs ahead of the
	driver and `_arm` refuses to queue a second one while a truck is live, so it cannot arrive on
	top of a car. The steal walked into it.

	NOTHING IN THE HANDOFF HAS EVER KNOWN THE TRUCK EXISTS, and both of the guards that look like
	they would catch it are filtered past it. `_fitToRoad` includes the road SEGMENTS, and the truck
	is parented to the getaway folder rather than to a tile. `_clearLanding` walks `traffic:getCars()`,
	and the truck is not traffic — it is registered with `TrafficController.setAvoid`, which makes
	cars STEER round it and puts it in nobody's list.

	And the geometry makes the meeting likely rather than freak. The truck rolls in the CENTRE lane
	and measures 17.8 studs across including its mirrors, so a car in lane +/-15 clears it by 1.39
	studs (`GetawayConfig.Lane`). A traffic car halfway through a lane change beside the truck is
	therefore already touching it — and that is exactly the car a player chasing the truck jumps at.
	The handoff poses our car where that shell was, and the unanchor hands the solver a car inside a
	trailer. It cannot throw a 54-stud anchored truck, so it wedges instead.

	=== WHY OUTBOARD, WHICH IS THE OPPOSITE OF `_fitToRoad` ==================================

	The two are pushing off different things and the directions follow from that rather than
	disagreeing: the walls are at the edges, so the way out of them is inward; the truck is in the
	middle, so the way out of IT is outward. Running this after `_fitToRoad` and before
	`_clearLanding` is the same ordering argument that comment already makes — each correction
	measures the position the last one left, and the traffic sweep measures all of them.

	They cannot fight over the same car in practice. `TRUCK_MAX` puts the worst case at about 14
	studs of cross, still inside lane +/-15 and nowhere near a wall, so a car pushed off the truck is
	not a car `_fitToRoad` would have wanted to push back.

	YIELDS NOWHERE, like its two neighbours, so the "no physics step between the pose and the
	unanchor" guarantee the whole handoff rests on is unchanged: every correction lands in the same
	frame and the solver is only ever shown the finished position.

	BOTH SIDES ARE TRIED, unlike `_fitToRoad`, which gives up and leaves a hopeless landing where it
	found it. That is the right answer there — what it failed to escape is something standing in the
	road, and dragging a car across the lanes chasing it is worse than the wedge. Here the thing it
	failed to escape IS the wedge, and the truck is a known 17.8-stud box with clear road on both
	sides of it, so a landing that cannot get out to the left can nearly always get out to the right.
	Giving up put the car back inside the trailer, which is the bug.

	The preferred side is whichever one the car is already leaning toward, so an ordinary clip of a
	mirror steps half a stud and stops. ]]
local TRUCK_STEP = 0.5
local TRUCK_MAX = 14

function StealController._clearTruck(self, car: Model): number
	--[[ Fetched here rather than declared as a dependency, and it has to be: GetawayController
		depends on THIS controller — the truck is armed by `onStolen` — so naming it above would be
		a cycle in the start order. Same resolution `RaceService` uses for the same knot. ]]
	local getaway = Shard.get("GetawayController")
	local truck = getaway and getaway:getObstacle()
	local info = self._info
	if not (truck and info) then
		return 0
	end

	local hull = {}
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide then
			table.insert(hull, part)
		end
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { truck }
	params.RespectCanCollide = true
	params.MaxParts = 1 -- `buried` only consumes the first hit.

	--- `GetPartsInPart` in each part's OWN collision group, for the reason `_fitToRoad` spells out:
	--- a query left in the default group answers about a matrix the solver is not about to use.
	local function buried(): BasePart?
		for _, part in hull do
			params.CollisionGroup = part.CollisionGroup
			local hits = workspace:GetPartsInPart(part, params)
			if #hits > 0 then
				return hits[1]
			end
		end
		return nil
	end

	local first = buried()
	if not first then
		return 0 -- the ordinary steal, nowhere near the truck. One probe and out.
	end

	local origin = car:GetPivot()
	local _, cross = self:_roadCoords(origin.Position)
	--- Lean the way the car already is. A dead-centre landing has no side of its own, and either is
	--- as good — `>= 0` picks one rather than pretending to measure.
	local firstWay = if cross >= 0 then 1 else -1

	for _, way in { firstWay, -firstWay } do
		car:PivotTo(origin)
		local step = info.cross * (TRUCK_STEP * way)
		local moved = 0
		while moved < TRUCK_MAX do
			car:PivotTo(car:GetPivot() + step)
			moved += TRUCK_STEP
			if not buried() then
				local how = "Handoff landing was inside the truck's %s; moved it %.1f studs clear."
				self.log:info(string.format(how, first.Name, moved))
				return moved
			end
		end
	end

	--[[ Boxed in on both sides. Vanishingly unlikely — it needs the truck AND something solid
		fourteen studs out on each side — and there is no good answer left, so take the one that is
		at least not a wedge: put it back and say so. ]]
	car:PivotTo(origin)
	self.log:warn(
		string.format(
			"Handoff landing is inside the getaway truck (%s) and neither side had %d studs of room; leaving it where it landed.",
			first:GetFullName(),
			TRUCK_MAX
		)
	)
	return 0
end

--[[ Get every other traffic car out of where the handoff has just put ours.

	The steal's one unavoidable liberty: it teleports a solid car into a lane that already has
	traffic in it. The car we LANDED on is handled by ordering alone — it's released a few lines
	later in the same frame, and no physics step runs in between, so the solver is never shown the
	overlap. Its NEIGHBOUR is not: traffic changes lane, so the car alongside your target can be
	most of the way into the same lane, and unanchoring inside it hands the solver two solid bodies
	occupying one space. It resolves that by throwing one of them, which is how a steal taken
	alongside a second car ends with the player sliding down the road on their roof.

	TWO ANSWERS, CHOSEN BY HOW DEEP THE OVERLAP IS (StealConfig.Handoff.MaxNudge). A car that has
	only just crossed the line is SHOVED sideways clear of it and carries on driving. One genuinely
	inside the bodywork is recycled into the pool, and respawns up the road like any other car that
	leaves. Both happen here, before the unanchor, so the solver still never sees an overlap either
	way — the difference is purely what the player watches happen, and deleting a car that was a lane
	over is what the 9 Aug playtest reported as cars disappearing. See the `MaxNudge` note for why
	the response changed rather than the margin.

	A shove can be refused — a knocked car belongs to physics, a destination can be occupied — and
	the refusal falls straight through to the recycle. The anti-fling guarantee never depends on the
	nicer of the two answers being available.

	THE TEST IS TWO INTERVALS IN ROAD SPACE, not a spatial query, for the reason `_landingTarget`
	spells out: `CarCollision`'s matrix makes an OverlapParams in the default group come back empty
	for every traffic car on the road, and that misconfiguration reads as the feature being broken.
	It's exact enough to be the right call here — step 2 has just placed our car square to the road,
	and a traffic shell only ever steers a few degrees off it, so both boxes are road-aligned to
	within a rounding error and their extents along `forward` and `cross` are simply their own.

	`keep` is the car being stolen, skipped because step 6 releases it and doing it twice would be
	pointless rather than harmful (`releaseCar` no-ops on a record it can't find). Records are
	collected before any are touched: `releaseCar` removes from the very array we're walking. ]]
function StealController._clearLanding(self, car: Model, keep)
	local traffic = self._traffic
	local info = self._info
	local margin = StealConfig.Handoff.ClearMargin
	if not (traffic and info) or margin < 0 then
		return
	end

	local bbCF, bbSize = car:GetBoundingBox()
	local carAlong, carCross = self:_roadCoords(bbCF.Position)
	-- The model's pivot is aimed down `forward` (step 2), so its own Z is the road's along axis
	-- and its X is across — no projection needed.
	local halfAlong = bbSize.Z * 0.5 + margin
	local halfCross = bbSize.X * 0.5 + margin

	--[[ `offset` and `reach` are kept per car rather than recomputed below because the shove is
		expressed as a DISPLACEMENT: everything here is measured off `hit.Position`, and a shell's
		Hit box is offset from its Root by the bodywork's centre, so this frame and `rec.cross` need
		not share an origin. A delta is the same number in both; a destination is not. ]]
	local found
	for _, rec in traffic:getCars() do
		local hit = rec.hit
		if rec ~= keep and hit and hit.Parent then
			local along, cross = self:_roadCoords(hit.Position)
			--[[ PROJECT THE SHELL'S BOX ONTO THE ROAD AXES. It is NOT road-aligned, and assuming it
				was is what let this test pass a car that was plainly inside us.

				`_place` aims every shell down `forward * speed + cross * lateral`, so a car halfway
				through a lane change is yawed by `atan(lateral / speed)` — `LaneChangeSpeed` is 11
				against traffic speeds in the 20s, and a knocked one goes further still. Measured on
				live traffic: **8.6% of car-frames are mid-change and yaw peaked at 56°**, where the
				true cross half-extent of a 9.37 x 21.11 Hit box is 11.38 studs against the 4.68 this
				used to assume. Six and a half studs short, against a `ClearMargin` of 0.5 — so a
				turning car sat well inside the bodywork and was reported clear, the unanchor handed
				the solver two interpenetrating bodies, and it threw one. That is the "stealing a car
				flings you" report, and the bitter part is that the mid-lane-change neighbour is the
				exact case this guard was written for.

				Standard AABB-of-an-oriented-box: each half-extent contributes by how much of it
				points along the axis. Two dot products per car, exact at any yaw, and it collapses
				back to `Size.X * 0.5` for the road-aligned car that was the only one handled before. ]]
			local look, right = hit.CFrame.LookVector, hit.CFrame.RightVector
			local halfWidth = hit.Size.X * 0.5 * math.abs(right:Dot(info.cross))
				+ hit.Size.Z * 0.5 * math.abs(look:Dot(info.cross))
			local halfLength = hit.Size.X * 0.5 * math.abs(right:Dot(info.forward))
				+ hit.Size.Z * 0.5 * math.abs(look:Dot(info.forward))
			local reach = halfCross + halfWidth
			if math.abs(along - carAlong) < halfAlong + halfLength and math.abs(cross - carCross) < reach then
				found = found or {}
				table.insert(found, {
					rec = rec,
					offset = cross - carCross,
					reach = reach,
					halfWidth = halfWidth,
				})
			end
		end
	end
	if not found then
		return
	end

	-- Half the drivable width, for the road-edge test. `driveWidth` is nil when the tile does not
	-- declare one (RoadController leaves it nil rather than guessing), and then there is nothing to
	-- test a destination against, so a shove is judged on distance alone.
	local halfRoad = if info.driveWidth then info.driveWidth * 0.5 else nil
	local maxNudge = StealConfig.Handoff.MaxNudge
	local shoved, doomed = 0, nil

	for _, entry in found do
		--[[ The side it is already on, first: that is the shorter move, and it keeps a car
			mid-lane-change going roughly where it was going instead of reversing it across our nose.
			`>= 0` rather than `> 0` so one sitting dead centre on us still gets a definite side.
			The far side is tried second — it is what saves a car pinned against the road edge. ]]
		local near = if entry.offset >= 0 then 1 else -1
		local moved = false
		for attempt = 1, 2 do
			local side = if attempt == 1 then near else -near
			local destination = side * (entry.reach + CLEAR_EPSILON)
			local distance = math.abs(destination - entry.offset)
			local outerEdge = math.abs(carCross + destination) + entry.halfWidth
			if
				distance <= maxNudge
				and (halfRoad == nil or outerEdge <= halfRoad)
				and traffic:shoveCar(entry.rec, destination - entry.offset)
			then
				shoved += 1
				moved = true
				break
			end
		end
		if not moved then
			doomed = doomed or {}
			table.insert(doomed, entry.rec)
		end
	end

	if doomed then
		for _, rec in doomed do
			traffic:releaseCar(rec)
		end
	end

	--[[ `bbSize.X` is in the line because the whole judgement rests on it — the reach is half of it
		plus half the shell's. If it ever reads much over the ~9.4 studs a car measures, something
		(an open door, a stray part) is inflating the box, and then the reach is wrong at source
		rather than the response being wrong. ]]
	self.log:info(
		string.format(
			"Handoff landing: %d shoved clear, %d recycled (car box %.1f wide).",
			shoved,
			if doomed then #doomed else 0,
			bbSize.X
		)
	)
end

--[[ Wear the stolen car: its body, its tier, its top speed.

	`CarBody.apply` is the visible half — the bodywork under `Body/` is replaced with the stolen
	shell's and rewelded to the same chassis mounts, so what the player drives away in is the car they
	landed on rather than their own car in its colours. THE PAINT COMES ACROSS ON THE MESHES: the shell
	was painted when it spawned (`TrafficController._spawn`), and the graft clones its parts, so the
	red car you landed on is the red car you drive off in without anything having to be told.

	HOW IT DRIVES COMES OFF `CarConfig`, whole, and is not derived from the car being replaced. Speed,
	steering lock, torque, braking and grip are all absolute numbers belonging to the body that just
	arrived — so a run of five steals is five cars, not five multipliers stacked on the one the run
	started in. That used to need `_authoredMaxSpeed`, a latched copy of the race's opening value
	kept purely so the tier scalar had something stable to multiply; there is nothing left to
	compound, so it is gone.

	`MaxHealth` is written by the SERVER (StealService → ObstacleService), not here: HP has exactly
	one writer and this isn't it. All we do locally is the part the player looks at. ]]
function StealController._applyTier(self, car: Model, tier: number, rec)
	car:SetAttribute("Tier", tier)
	car:SetAttribute("Body", rec.body)
	--[[ THE THIRD HALF OF THE CAR'S IDENTITY, and it rides the same way the other two do: stamped
		here and read at the truck (`GetawayController._bank`), because between those two moments the
		only record of what colour this car is, is the car.

		A palette index rather than the colour itself — see PaintConfig. It is what lets the car on
		your podium and the one you park in the street be the car you actually stole rather than
		another one of the same model. ]]
	car:SetAttribute("Paint", rec.paint)

	debug.profilebegin("Steal.CommitBody")
	local changed = CarBody.apply(car, rec.model, rec.paint, rec.body, self._preparedBody)
	debug.profileend()
	CarBody.discardPrepared(self._preparedBody)
	self._preparedBody = nil
	if not changed then
		self.log:warn(string.format(
			"Steal redressed nothing from '%s' — is TrafficCars stale, or does this car have no Chassis.RedressMount?",
			tostring(rec.body)
		))
	end

	--[[ THE FOURTH, AND THE ONLY ONE THAT IS WORTH MONEY BY ITSELF: whatever the weather had done to
		the car we just landed on (`WeatherConfig`). It rides exactly the way the other three do —
		stamped on the car here and read back at the truck — for the same reason: between the spawn
		and the getaway, the only record of what this car is, is the car.

		`CarMutation.apply` is what stamps it, so the attribute and the look can never disagree. It
		is called UNCONDITIONALLY, including with a nil, and that is the half that is easy to miss:
		stealing an ordinary car while driving a Molten one has to take the glow OFF, and a branch
		here would leave the previous car's highlight, sparkle and attribute on the new body for the
		rest of the run — which would then be banked as a car the player never stole.

		AFTER THE REDRESS, NOT BEFORE IT. `CarBody.apply` repaints the body it just grafted on, and
		five of the six mutations are a SKIN on those very parts (a material, see `WeatherConfig`):
		dressed first, the repaint would lay the shell's colour straight back over the rust. Dressed
		here, the skin goes on last and the paint is underneath it where it belongs.

		WITHOUT A BADGE, deliberately: the marker over a traffic car is there to tell you what you
		are about to jump at, and the same marker over the car you are sitting in would hang in the
		middle of the chase camera until the next steal. See `Modules/CarMutation`. ]]
	CarMutation.apply(car, rec.mutation)

	--[[ Re-rig the doors onto the body that just arrived.

		THE REDRESS ALWAYS DESTROYS THE DOOR RIG, so this is not a repair for an edge case — it is
		half of the feature. `swapMeshes` rebuilds `Body/` flat from the traffic shell, which leaves
		the seat's `DoorHinge` / `DoorLatchWeld` pointing at parts that no longer exist; without
		this call `CarDoors.rigs` reports none from the first steal onward, and the bail's door beat
		is a no-op on every car except the one the race started in. That is a nastier bug than no
		doors at all, because it works when you first test it.

		Safe here specifically: `_applyTier` runs from `_finish` while the car is still ANCHORED, so
		destroying and rebuilding welds cannot be caught by a physics step. The body is also
		entirely client-built by this point, so none of this surgery is fighting replication.

		Cheap enough to be unconditional (~30 parts, a quadratic mirror search over the handful of
		`shell_*` among them), and a body with no separable doors — three in the pack — costs a
		survey and returns 0, which `CarDoors` treats as a clean no-op. ]]
	if StealConfig.Doors.Enabled then
		debug.profilebegin("Steal.RigDoors")
		local rigged, notes = CarDoorRig.apply(car)
		debug.profileend()
		if rigged == 0 then
			self.log:info(string.format("No doors rigged on '%s': %s", tostring(rec.body), table.concat(notes, "; ")))
		end
	end

	--[[ The stolen car's own handling, onto the rig the player is sitting in. The stock Chassis
		re-reads any parameter it owns when the attribute changes, so this lands on a live car —
		which is the whole reason a steal can change how the thing drives at all (`CarStats`).

		Keyed by BODY, not by tier: the tier is what the server prices the steal at, but two cars
		can share neither speed nor grip while sharing a rung in some future world, and the body is
		the thing that actually has an opinion. ]]
	CarStats.reapply(car, rec.body)

	--[[ …and then the speed dial again, through DriveController, which is not redundant: the shim
		latched a base at install and boost scales off it, so writing the attribute behind its back
		would leave it boosting off the car the run STARTED in and putting that car's value back on
		teardown. `setBaseMaxSpeed` is the supported way in, and it preserves live boost state.

		The car level multiplier rides here rather than in `CarStats` because it is a property of
		the PLAYER, not of the car — bank enough Mustangs and yours is quicker than the one the
		road hands somebody else. `CarConfig` describes a stock car; this is the one place a
		particular player's copy of it diverges. ]]
	if self._drive then
		self._drive:setBaseMaxSpeed(CarConfig.maxSpeedOf(rec.body) * self:_levelScale(rec.body))
	end
end

--[[ How much faster THIS PLAYER's version of this body is than a stock one.

	Car XP (RewardConfig) is per body: bank a `Sports16` and that body levels, and every `Sports16`
	you take from then on is a little quicker. This is where that lands — one multiplier alongside
	the tier's own, both against the AUTHORED speed, so neither can compound into the other.

	READ OFF A PLAYER ATTRIBUTE, WITH NO ROUND TRIP, which is the whole reason levels are broadcast
	that way (see GarageConfig.LevelsAttribute). A steal changes the car underneath the player inside
	a single anchored frame; there is nowhere in that to wait for an answer, so the answer has to be
	local already. `speedScaleFor` returns 1 for a body at level 1 and for one this player has never
	banked, so an unlevelled car is untouched and this needs no branch of its own. ]]
function StealController._levelScale(self, body: unknown): number
	local encoded = Players.LocalPlayer:GetAttribute(GarageConfig.LevelsAttribute)
	return RewardConfig.speedScaleFor(RewardConfig.levelOf(encoded, body :: any))
end

--[[ Turn the flight avatar into a body.

	Every Motor6D becomes a BallSocketConstraint between two attachments placed at that joint's own
	`C0`/`C1` — so the ragdoll's joints are exactly where the rig's joints were, and the pose it
	starts flopping from is the pose it was flying in. Limits on, because an unlimited socket lets
	limbs pass through the torso, which stops being funny immediately.

	Accessories are left alone: they hang off `Weld`s rather than Motor6Ds, so hats and backpacks
	stay rigidly attached and tumble with the body, which is what you want.

	`Massless` has to come back off. The avatar is built massless because it's an anchored puppet;
	leave it that way and the ragdoll has no inertia and behaves like tissue paper. `CanQuery` stays
	off, deliberately — the stock CarBones suspension raycasts run as "Default" and aren't ours to
	filter, so a query-visible body on the road is something the car could try to drive up. ]]
function StealController._ragdoll(self, velocity: Vector3)
	local avatar = self._avatar
	local cfg = StealConfig.Whiff
	if not avatar then
		return
	end

	--[[ THE CLIPS COME OFF BEFORE THE JOINTS DO, with no fade. A track that is still blending out is
		still writing Motor6D transforms — onto joints this is about to replace with ball sockets —
		so a fade here is a freefall flip fighting a limp body for the length of the fade. It reads
		as the splat not quite letting go. ]]
	if self._anim then
		self._anim:stop()
	end

	if cfg.Ragdoll then
		Ragdoll.limp(avatar, cfg)
	end
	Ragdoll.release(avatar, velocity * cfg.VelocityKeep, Ragdoll.spin(self._rng, cfg.Spin))
end

--[[ Landed on tarmac. The body drops, the camera drops with it, and the run is over.

	Nothing is handed back here, and that's the design rather than an oversight (StealConfig.Whiff):

	  • THE CAR IS PUT AWAY HERE, and this is the one outcome that does it — every other path leaves
	    it on screen from the bail onwards. Two reasons it cannot stay. `_releaseSystems` below drops
	    the state to idle, which stops `_flyCar`, so a visible car would stop DEAD in the middle of
	    the road and sit there — a frozen car reads as a bug, not as a beat. And there would be two
	    things competing for a shot that should have one: you, face down on the tarmac. Hiding it
	    costs a pop as it vanishes, but that lands under the ragdoll and the camera drop, which is
	    the cheaper of the two. It stays frozen and invisible until `_teardown` lets it go.
	  • THE RIDER STAYS HIDDEN TOO. They're still welded into that car. Restoring them now would put
	    a second copy of the player on screen, sitting upright inside an invisible car, next to their
	    own body. It's handed to `_teardown` instead (see `_endFlight` for why that restore has to
	    know the player is leaving the car).
	  • The avatar is NOT destroyed. It becomes the ragdoll, and the camera's `downed` shot frames it
	    until the fade takes over.

	The server runs the beat from there — `wreckRace(player, "badLanding")` — and the cause is what
	tells ObstacleController to skip the engine plume and the coast it gives an ordinary death. ]]
--- Public (RaceUIController): the flight avatar lying where a bad landing dropped it, or nil. It is
--- kept until the race is torn down (`_whiff` keeps it), so the end panel can show the ragdoll.
function StealController.downedAvatar(self): Model?
	if self._downed and self._avatar and self._avatar.Parent then
		return self._avatar
	end
	return nil
end

function StealController._whiff(self)
	if self._lobby then
		self:_lobbyEnd(nil) -- no race to wreck: you come down on your feet
		return
	end
	--[[ THE TUTORIAL DOES NOT WHIFF (`TutorialConfig.Unlosable.Catch`, 2026-10-05). The flight is
		called off right here — `_abort`, the restore an interrupted flight already gets — so the player
		is back in the seat of the car they left, driving, with no ragdoll, no wreck and no revive to
		paper over one. The server is told only that the attempt failed, so the beat goes back to the
		jump. ]]
	local unlosable = TutorialConfig.Unlosable
	if unlosable.Enabled and unlosable.Catch and TutorialConfig.isUnlosable(Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute)) then
		self.log:info("Missed the jump in the tutorial; back in the car.")
		self:_abort()
		self:getRemoteEvent("StealMissed"):Fire()
		return
	end
	-- Shut the door before it goes, so whatever `_teardown` hands back is in one piece.
	if self._doorAngle and self._doorAngle ~= 0 and self._car and self._car.Parent then
		CarDoors.poseFrozen(self._car, -self._doorAngle)
		self._doorAngle = 0
	end
	if self._car and self._car.Parent and not self._carHidden then
		self._carHidden = hideTree(self._car)
	end

	local velocity = self._flightView and self._flightView.velocity or Vector3.zero
	self:_ragdoll(velocity)
	self._downed = true

	-- No second bail from the floor. The server's wreck will unbind too, a beat later.
	self:_unbind()
	self:_releaseSystems()

	self.log:info("Bad landing.")
	self:getRemoteEvent("StealFailed"):Fire()
end

--[[ The race disappeared mid-flight (a leave, a death, a wreck from something else). Restore what
	still exists and get out. Nothing is reported to the server: whatever ended the race has already
	told it. ]]
function StealController._abort(self)
	if self._lobby then
		self:_lobbyEnd(nil)
		return
	end
	self:_unanchorCar()
	self:_endFlight(false)
end

--[[ Hand the car back to the physics solver.

	PUT THE DOOR BACK FIRST, and this is load-bearing rather than tidy-up. While the car is frozen the
	door is held open by CFrame alone (`_flyCar`); the latch WeldConstraint underneath it never moved
	and still holds the SHUT offset. Unanchor with the door standing open and the solver resolves that
	contradiction on the first frame by snapping the door through the bodywork. Unwinding by the
	negation of the angle we applied restores the exact pose the weld is expecting.

	Every exit runs through here — the steal, the whiff's teardown and the mid-flight abort — which is
	why the restore lives in this function rather than in each of the three. ]]
function StealController._unanchorCar(self)
	if self._doorAngle and self._doorAngle ~= 0 and self._car and self._car.Parent then
		CarDoors.poseFrozen(self._car, -self._doorAngle)
	end
	self._doorAngle = 0

	for part, anchored in self._carAnchors do
		if part.Parent then
			part.Anchored = anchored
		end
	end
	table.clear(self._carAnchors)
end

--[[ Stop being a flight. The bookkeeping both outcomes share, and NOTHING ELSE — in particular it
	does not hand the hazard systems back, because only one of the two outcomes wants that.

	A whiff must not: the car is hidden, anchored and one network hop away from being wrecked, and a
	traffic clip poll resumed on it could report a hit that reaches `wreckRace` FIRST — with no
	cause, so the beat we just set up would play as an ordinary engine-plume death instead of the
	shot of the player on the tarmac. Leaving them suspended costs nothing: each one's own RaceEnd
	teardown clears the flag, and each already stops reporting the moment it hears RaceWrecked. ]]
function StealController._releaseSystems(self)
	CarBody.discardPrepared(self._preparedBody)
	self._preparedBody = nil
	self._state = "idle"
	self._target = nil
	self._candidate = nil
	self._perchOn = nil
	self._mountFrom = nil
	self._stealBufferedUntil = 0
	self:_unbindSteal()
	self:_hideMarker()
	self:_hidePrompt()
	-- Collision charging may remain suspended after a whiff, but routine traffic steering must not:
	-- the short no-surprise window belongs to the flight, not to the remainder of the wreck beat.
	if self._traffic then
		self._traffic:setStealLaneChangesLocked(false)
	end
	--[[ Both of these are in the SHARED half rather than in `_endFlight` on purpose, because the
		whiff — which deliberately hands nothing else back — can still reach them: `_stepMount`
		whiffs when the car being stolen goes away, and by then the door may be open and a driver may
		be halfway out of it. A panel left unwelded and anchored goes back to the pool broken, which
		outlives the run rather than the beat. ]]
	self:_closeShellDoor()
	self:_clearDriver()
	TimeScale.reset()
end

--[[ Hand the flight back completely: car visible, avatar gone, camera on the car, rider unhidden.
	Every outcome except the whiff runs through here, and it has to be safe to call twice, because a
	teardown can race an outcome.

	`settle` holds the RIDER hidden for a couple of extra frames after a teleport (see `_finish`
	step 2's note — the seat weld does carry them, so this is margin), and only the successful
	handoff wants it — an abort moved
	nobody, and a teardown is on its way to destroying the car anyway. Getting that distinction
	wrong is not cosmetic: see `_restoreRider` for the trap. ]]
function StealController._endFlight(self, settle: boolean?)
	self:_releaseSystems()
	self._flightView = nil
	self._downed = false

	if self._obstacles then
		self._obstacles:setSuspended(false)
	end
	if self._traffic then
		self._traffic:setSuspended(false)
	end
	if self._drive then
		self._drive:resume()
	end

	restoreTree(self._carHidden)
	self._carHidden = nil

	if self._avatar then
		self._avatar:Destroy()
		self._avatar = nil
	end
	-- The tracks live on the avatar's Animator, so they die with it above. Dropping the handle is
	-- what stops `_updateAnimation` poking a track whose rig has been destroyed.
	self._anim = nil
	self._falling = false
	if self._cam then
		self._cam:setFlight(nil)
		self._cam:setCinematic(nil)
	end
	self._cine = nil
	if self._wind then
		self._wind:setFlight(nil)
	end

	local hidden = self._riderHidden
	self._riderHidden = nil
	if not hidden then
		return
	end
	local frames = if settle then math.max(StealConfig.Handoff.SettleFrames, 0) else 0
	if frames <= 0 then
		self:_restoreRider(hidden, false)
		return
	end

	self._pendingRestore = hidden
	task.spawn(function()
		for _ = 1, frames do
			RunService.Heartbeat:Wait()
		end
		-- Somebody else may have claimed it (a teardown, or a second flight): whoever holds it runs
		-- it, exactly once.
		if self._pendingRestore == hidden then
			self._pendingRestore = nil
			self:_restoreRider(hidden, false)
		end
	end)
end

--[[ Put the rider back on screen.

	`leavingCar` is the trap, and it is a real one rather than a hypothetical. What we captured is
	the transparency the STOCK VEHICLE SCRIPT left the character at — its `onEnterSeat` hides the
	lower legs and the back/hat accessories so they don't poke through the bodywork — and restoring
	it verbatim is exactly right while the player is still seated (a handoff), and exactly wrong the
	moment they aren't. RaceService puts those same parts back to 0 on the way out of a race
	(`_restoreRiderAvatar`), so a restore landing after it re-hides them and the player walks away
	from the pad with no feet. That bug already exists in this repo's history, from the other
	direction; this is the same fix-up, on the same two exported lists, so the two agree by
	construction. ]]
function StealController._restoreRider(self, state, leavingCar: boolean)
	restoreTree(state)
	if not leavingCar then
		return
	end
	local character = Players.LocalPlayer.Character
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

-- === Rebase =================================================================

--[[ RoadController snapped the whole world back toward the origin mid-flight.

	Our coordinates are road-frame scalars, so this is one addition — but it does have to happen,
	and it's easy to assume it doesn't: `_shiftWorld` moves the local road, the car assembly and
	`LocalPlayer.Character`, and THE FLIGHT AVATAR IS NONE OF THOSE. Left out, the road would jump
	8000 studs and the player would carry on falling where the road used to be.

	Runs inside the rebase frame, so it must not yield; it doesn't. Rare enough that it will never
	be seen in testing, which is exactly why it's written now rather than when it's noticed. ]]
function StealController._onWorldShift(self, shift: Vector3)
	if self._state == "idle" or not self._info then
		return
	end
	self._flight.along += shift:Dot(self._info.forward)
	self._carY += shift.Y
	self._launchY += shift.Y
	self._flight.y += shift.Y
	-- The lunge's origin is the one WORLD point this controller holds on to (everything else is a
	-- road-frame scalar), so it is the one that needs the shift applied whole rather than projected.
	if self._mountFrom then
		self._mountFrom += shift
	end
end

--[[ PUBLIC (TutorialController) — where a flight is up to, and whether E would take something.

	TWO FACTS AND NO CONTROL. The tutorial has two beats inside a steal — one that asks for the jump
	and one that holds the player at the top of the arc over the car they are about to take — and
	both need to know what the flight is doing without being allowed to steer it. Polled per frame
	off a beat that is already running rather than pushed, so there is no subscription to leak and
	nothing here to unwind when a race ends.

	`state` is the flight's own word: "idle" | "launch" | "air" | "perch" | "mount". `canMount` is
	whether `_candidate` currently has a car in it, which is precisely the condition the E prompt is
	drawn under — so a beat that freezes only while this is true can never strand a player in the air
	with a prompt they cannot satisfy.

	`reach` is how far that car is, in surface studs, or `math.huge` when there isn't one. The tutorial
	holds the world at the arc's CLOSEST approach rather than on the first frame E would work, which is
	a minimum it has to watch for — and the only honest place to measure it is the same lookup that
	decided what E takes. Measured again from outside, the freeze and the steal could name different
	cars on the frame two padded volumes overlap.

	Returned as three values rather than a table because it is read every frame and none of them is
	worth an allocation. ]]
--- Game-time road speed while the driver is in the scripted steal arc.
function StealController.roadSpeed(self): number?
	local flight = self._flight
	return if self._active and self._state ~= "idle" and flight then flight.alongVel else nil
end

function StealController.getFlight(self): (string, boolean, number)
	local rec = self._candidate
	return self._state or "idle", rec ~= nil, if rec then self._candidateAt or 0 else math.huge
end

--[[ PUBLIC (TutorialDirector) — where the arc that is IN THE AIR will come down, and when.

	The road-frame `along` of the touchdown and the seconds left to it; nil when nothing is flying.
	The same numbers the ground marker is drawn from, from the same `_predict`, so the tutorial and
	the circle under the player can never disagree about where this is going.

	It is read every tick of the beat rather than once, because the answer MOVES: the arc is steerable
	and its along speed is still braking, so a landing point sampled at the apex is not the one the
	player arrives at. What the director does with it is nudge the target car's pace — see
	`_aimStealTarget`, which is the half of the aim that no placement can do in advance. ]]
function StealController.predictLanding(self): (number?, number?)
	if not (self._flight and self._info and (self._state == "air" or self._state == "launch")) then
		return nil
	end
	local along, _, t = self:_predict()
	return along, t
end

--[[ PUBLIC (TutorialDirector) — where a bail STARTED RIGHT NOW would come down.

	Returns the studs of road the arc would cover, the seconds it would take, and the ROAD SPEED the
	player is driving at. Nil when there is no road or no car to leave.

	THE THIRD VALUE IS NOT THE SPEED THE ARC LEAVES AT, and the difference is the whole of a bug the
	tutorial's steal beat wore for a while. `Launch.SpeedWindow.ThrowScale` throws the avatar out at
	1.5x the car's normalised cruise, so "the speed it leaves at" and "the speed the player is doing"
	stopped being the same number the day that arrived. The caller wants the second one, because what
	it does with it is multiply it by the seconds of driving still to come before the world stops
	(`StealTarget.Settle`). Handed the throw instead, it led the target by half a cruise times that
	settle: seventy-odd studs at 85, three car lengths of road, every one of them in front of a jump
	that was never going to get there.
	That is what "the jump falls short" was. `_onBail` divides the same scale back out of
	`_bailAlongVel` for the same reason: the throw belongs to the avatar, not to anything measuring
	the car.

	=== WHY THE TUTORIAL CANNOT JUST PICK A DISTANCE ==========================================

	It tried, twice, and both numbers were wrong the same way: the reach of a bail is not a property
	of the game, it is a property of how fast you were going when you pressed Space. The arc's along
	speed is braked toward traffic pace (`Flight.Glide`) from the apex on, so a slow bail and a fast
	one do NOT cover the same ground — across the speeds this game is actually driven at, one covers
	96 studs and the other 122. Against a target that is itself driving away at ~31, the distance a
	jump CLOSES swings from 34 studs to 67. No constant lands on a car from both, and the shipped one
	(30) was short by half a road at cruise. That is exactly what a player sees: the jump sails clean
	over the car it was aimed at.

	So the tutorial asks. Same integrator, same launch, same upgrade factors — running the real arc
	forward on a scratch table is the only answer that cannot go stale, and it is the trick `_predict`
	already plays for the ground marker.

	CROSS IS DELIBERATELY NOT MODELLED. The arc is seeded with no steer and none is applied, because
	what the caller is asking for is the reach of a jump nobody has aimed yet. Where the player
	actually steers is their business, and the tutorial's wider `_reach` is what forgives it. ]]
function StealController.predictBail(self): (number?, number?, number?)
	local info = self._road and self._road:getRoadInfo()
	local car = self._road and self._road:getCar()
	local primary = car and car.PrimaryPart
	if not (info and primary) then
		return nil
	end

	local seat = car:FindFirstChild("VehicleSeat", true)
	local origin = if seat and seat:IsA("BasePart") then seat.CFrame else primary.CFrame
	local launch = StealConfig.Launch
	-- Kept as two values rather than one: the arc flies on the throw, the caller reasons about the
	-- car. See the header: collapsing them is the bug this splits back apart.
	local roadSpeed = self:_normalisedRoadSpeed(primary.AssemblyLinearVelocity:Dot(info.forward))
	local alongVel = roadSpeed * launch.SpeedWindow.ThrowScale

	--[[ The scripted launch, by hand, because `_stepLaunch` is a state rather than a step: it holds
		the along speed flat, walks the body up by `Rise`, and only then hands the arc its throw.
		Skipping it would start the ballistics an eighth of a second and three studs early — small,
		and exactly the kind of small that turns into a car placed a few studs off for no reason
		anybody can find later. ]]
	local sim = {
		along = alongVel * launch.Time,
		cross = 0,
		y = origin.Position.Y + launch.Rise,
		alongVel = alongVel,
		crossVel = 0,
		yVel = launch.Up,
		startCross = 0,
	}
	local travel, _, airborne = self:_runArc(sim, info.deckY)
	return travel, airborne + launch.Time, roadSpeed
end

-- === Input ==================================================================

--[[ Bind Space above the stock Driver, and sink it.

	SPACE IS ALREADY SPOKEN FOR — by the handbrake. The stock `Driver` LocalScript maps it in
	`Keymap.Handbrake` and binds its raw-input handler with `BindActionAtPriority(...,
	ContextActionPriority.High.Value, ...)` — 3000, above the PlayerModule's own movement actions —
	and that handler SINKS every key it recognises. Which is good news twice over: Roblox's own
	seat-jump-to-exit never sees Space, so there is no stock unseat racing our bail; and
	`DriveConfig.AllowHandbrake` is false with DriveController already no-opping the handbrake, so
	taking Space costs the player no verb they currently have. We bind above 3000 and sink.

	Begin only: a bail is a tap, and there is nothing to do on release. ]]
function StealController._bind(self)
	if self._bound then
		return
	end
	self._bound = true
	ContextActionService:BindActionAtPriority(ACTION_NAME, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			self:_onBail()
		end
		return Enum.ContextActionResult.Sink
	end, false, StealConfig.BindPriority, table.unpack(StealConfig.BailKeys))
end

function StealController._unbind(self)
	if not self._bound then
		return
	end
	self._bound = false
	ContextActionService:UnbindAction(ACTION_NAME)
end

--[[ Space again or E, only for the length of a flight.

	Bound when the bail starts and dropped the moment the flight ends, rather than held for the race.
	E is not ours the rest of the time, and a key sunk at priority 3500 for ninety seconds to do
	nothing is precisely the class of leak the bail's binding note above is about. One priority above the
	bail while it IS ours: Space takes a car during flight instead of trying another bail.

	Deliberately dumb: it takes whatever `_candidate` last found, which is the same record the
	billboard is adorned to. One lookup, so the prompt can never be advertising one car while E takes
	another. ]]
function StealController._bindSteal(self)
	if self._stealBound or not StealConfig.Prompt.Enabled then
		return
	end
	self._stealBound = true
	ContextActionService:BindActionAtPriority(ACTION_STEAL, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			self:_onSteal()
		end
		return Enum.ContextActionResult.Sink
	end, false, StealConfig.BindPriority + 1, table.unpack(StealConfig.Prompt.Keys))
end

function StealController._unbindSteal(self)
	if not self._stealBound then
		return
	end
	self._stealBound = false
	ContextActionService:UnbindAction(ACTION_STEAL)
end

--[[ E pressed: take the car the prompt is offering, from wherever we happen to be.

	Live in the air and on the perch, and in neither of the states either side of them — the launch is
	before you have left the seat, and the mount is after you have already taken something. A press
	with no candidate is a press with nothing to do rather than something to fail at: no sound, no
	shake, no "you missed". The prompt not being on screen has already said it. ]]
--- A player whose jump is ending with a car in reach takes it without the press: on touch
--- (`Prompt.TouchAutoSteal`), and since 2026-10-20 on every device (`Prompt.AutoSteal`).
--- Same checks as a press (`_onSteal`): a car that went physical or was recycled is not taken.
function StealController._autoSteal(self, rec): boolean
	local prompt = StealConfig.Prompt
	if not (prompt.AutoSteal or (prompt.TouchAutoSteal and UserInputService.PreferredInput == Enum.PreferredInput.Touch)) then
		return false
	end
	if not (rec and not rec.physical and rec.hit and rec.hit.Parent) then
		return false
	end
	self._stealBufferedUntil = 0
	self:_mount(rec)
	return true
end

function StealController._consumeBufferedSteal(self): boolean
	local rec = self._candidate
	local f = self._flight
	if
		rec
		and f
		and (self._stealBufferedUntil or 0) > 0
		and f.t <= (self._stealBufferedUntil or 0)
		and not rec.physical
		and rec.hit
		and rec.hit.Parent
	then
		self._stealBufferedUntil = 0
		self:_mount(rec)
		return true
	end
	return false
end

function StealController._onSteal(self)
	if self._state ~= "launch" and self._state ~= "air" and self._state ~= "perch" then
		return
	end
	local rec = self._candidate
	if rec and not rec.physical and rec.hit and rec.hit.Parent then
		self._stealBufferedUntil = 0
		self:_mount(rec)
		return
	end

	-- Remember intent, not a target. Candidate selection still happens through the ordinary spatial
	-- query, so an early press cannot steal a distant or arbitrary car.
	local f = self._flight
	if f then
		self._stealBufferedUntil = f.t + StealConfig.Prompt.InputBuffer
	end
end

-- === The touch HUD's two verbs ==============================================

--[[ Space and E, as public calls, for the one on-screen button that stands in for both.

	A phone has neither key. `DrivingHudController` binds a single button that reads JUMP while you
	are in the seat and STEAL once you are in the air over something worth taking, and it presses
	these rather than synthesising a key: the button is a `GuiButton`, and there is nothing for
	ContextActionService to receive. Routing it through the bindings would also mean fighting the
	stock Driver's own 3000-priority sink for Space, which is the thing `_bind` exists to get above.

	They are the SAME entry points the keys use, guards and all — `_onBail` still asks `_canBail`
	and `_onSteal` still wants a candidate — so a tap with nothing to bail out of or nothing to take
	does nothing, exactly as the key press does. Nothing here is a second code path to keep in step
	with the first. ]]
function StealController.bail(self)
	-- The touch HUD has one physical button for both verbs. Before a candidate is close enough to
	-- change its face to STEAL, a second tap during flight is still valid buffered steal intent.
	if self._state == "launch" or self._state == "air" or self._state == "perch" then
		--- Not in the launch beat, nor `Prompt.BailGuard` seconds in: that is the jump's own tap (or its
		--- bounce) landing a second time, and with the lock offering a car from the first frame, it was
		--- buffered into a steal the player never asked for (2026-10-20).
		local f = self._flight
		if self._state == "launch" or (f and f.t < (StealConfig.Prompt.BailGuard or 0)) then
			return
		end
		self:_onSteal()
	else
		self:_onBail()
	end
end

function StealController.steal(self)
	self:_onSteal()
end

-- === The collector highway's bail ===========================================

--- Answers any method with a no-op, so the race systems the flight pokes can be stood in for.
local QUIET = setmetatable({}, {
	__index = function()
		return function() end
	end,
})
local function quiet(methods)
	return setmetatable(methods, { __index = QUIET })
end

--[[ Space in the open-world car (`LobbyCarController._jumpExit`): the race's own bail, glide and E
	steal (owner, 2026-11-01: "re-use the previous jumping system... he gets to choose what car to hop
	into with E").

	There is no race, so the flight is pointed at stand-ins: the road is a frame laid along the car's
	heading at bail time, the traffic is the roaming cars (`RoamingCarController.stealTargets`), and
	the drive, camera, wind and obstacles are no-ops. The car you left is NOT frozen or flown; it is a
	real car in the world and coasts on. The outcome never reaches the race remotes: `_lobbyEnd` hands
	a mounted car to `RoamingCarController.landOn`, which asks `RoamingCarService` for it exactly as an
	on-foot leap does. Returns false when it could not start, and the caller falls back to a plain exit. ]]
function StealController.bailLobby(self, car: Model, exitSeat: () -> ()): boolean
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local primary = car and car.PrimaryPart
	local roaming = Shard.get("RoamingCarController")
	if self._active or not (StealConfig.Enabled and roaming and primary and humanoid and root and root:IsA("BasePart")) then
		return false
	end

	local velocity = primary.AssemblyLinearVelocity
	local forward = Vector3.new(velocity.X, 0, velocity.Z)
	if forward.Magnitude < 5 then
		local look = primary.CFrame.LookVector
		forward = Vector3.new(look.X, 0, look.Z)
	end
	forward = if forward.Magnitude > 0.01 then forward.Unit else Vector3.new(0, 0, -1)
	local cross = Vector3.yAxis:Cross(forward)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { car, character }
	local ground = workspace:Raycast(primary.Position + Vector3.yAxis * 5, Vector3.yAxis * -60, params)
	local info = {
		forward = forward,
		cross = cross,
		driveCenter = primary.Position:Dot(cross),
		deckY = if ground then ground.Position.Y else CollectorConfig.Corridor.FloorY,
	}

	self._lobby = {
		road = self._road,
		traffic = self._traffic,
		drive = self._drive,
		obstacles = self._obstacles,
		cam = self._cam,
		wind = self._wind,
	}
	self._road = quiet({
		getRoadInfo = function()
			return info
		end,
		getCar = function()
			return car
		end,
	})
	self._traffic = quiet({
		getCars = function()
			return roaming:stealTargets(info)
		end,
	})
	self._drive = quiet({
		getCruiseSpeed = function()
			return CollectorConfig.Drive.BailCruise
		end,
		getSteerInput = function()
			return 0
		end,
		getThrottleInput = function()
			return 0
		end,
	})
	self._obstacles, self._cam, self._wind = nil, nil, nil
	self:_activate()

	-- Out of the seat now, locally, so the flight starts from it (see `_pinRider` for the server's half).
	exitSeat()
	for _, joint in root:GetJoints() do
		if joint.Name == "SeatWeld" then
			joint:Destroy()
		end
	end
	humanoid.Sit = false
	humanoid.PlatformStand = true

	self:_onBail()
	if self._state == "idle" then
		self:_lobbyEnd(nil)
	end
	return true
end

--[[ The real character rides along under the (anchored) flight avatar, hidden: the default camera
	follows it, and the server's capture check measures it. Written every frame, so the kit's
	unseat teleport landing mid-flight is overwritten the frame after. ]]
function StealController._pinRider(self)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if self._avatar and root and root:IsA("BasePart") then
		root.CFrame = self._avatar:GetPivot()
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

--- A highway flight is over: put the race systems back, show the rider where the avatar was, and
--- hand a mounted car (`rec`, a `stealTargets` record) to the roaming leap's capture.
function StealController._lobbyEnd(self, rec)
	local lobby = self._lobby
	if not lobby then
		return
	end
	local pose = if self._avatar then self._avatar:GetPivot() else nil
	-- Restored by the teardown as leaving the car, so the legs the seat hid come back.
	self._pendingRestore = self._pendingRestore or self._riderHidden
	self._riderHidden = nil
	self:_teardown()
	self._lobby = nil
	self._road, self._traffic, self._drive = lobby.road, lobby.traffic, lobby.drive
	self._obstacles, self._cam, self._wind = lobby.obstacles, lobby.cam, lobby.wind

	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		return
	end
	if pose then
		root.CFrame = pose
	end
	local roaming = Shard.get("RoamingCarController")
	if rec and rec.roam and roaming and roaming:landOn(rec.roam) then
		return
	end
	humanoid.PlatformStand = false
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
end

--[[ Is that button showing JUMP or STEAL this frame?

	The same question `_onSteal` opens by asking itself, and deliberately read off the same
	`_candidate` the billboard over the car is adorned to — so the button and the prompt can never
	advertise different things. Polled per frame by the HUD rather than pushed, because the answer
	changes with the flight and there is no event for "the nearest car is now in range".

	`physical` is excluded here for the reason `_onSteal` excludes it: those are the shells that are
	already real cars rather than takeable traffic, and a button offering a steal that would not
	happen is worse than no button. ]]
function StealController.canSteal(self): boolean
	if self._state ~= "air" and self._state ~= "perch" then
		return false
	end
	local rec = self._candidate
	return rec ~= nil and not rec.physical and rec.hit ~= nil and rec.hit.Parent ~= nil
end

-- === Who else cares that a steal landed =====================================

--[[ Be told when a car is actually taken. Returns a disconnect function.

	The same shape as `RoadController:onWorldShift`, and registered the same way — once at start, for
	the session — because "a steal happened" is a fact about the run rather than about this flow.
	GetawayController is the first listener: the truck you leave in is armed by the steal it exists
	to let you get away with.

	A remote would be the wrong seam here even though the server already hears about every steal:
	the server's copy is a CLAIM it cannot verify (StealService's header), and bouncing it off the
	server would put a round trip between taking a car and the world reacting to it, for information
	this client already has firsthand.

	Listeners are called at the end of `_finish`, so they see a settled car, and one that throws is
	warned about rather than allowed to abort the handoff. ]]
function StealController.onStolen(self, fn: (number) -> ()): () -> ()
	self._stealListeners[fn] = true
	return function()
		self._stealListeners[fn] = nil
	end
end

-- === The cinematic (`StealJuiceConfig.Cinematic`, 2026-09-30) ==================

--[[ Direct the mount beat, if this steal earns it (`MinBand`, `Cooldown`). Called from `_mount`, on
	the contact frame. Everything it needs later is read live in `_cineShot`, because the car keeps
	driving (and the world keeps rebasing) under the whole beat. ]]
function StealController._startCinematic(self, rec)
	local cfg = StealJuiceConfig.Cinematic
	if not (cfg.Enabled and self._cam and rec and rec.root) then
		return
	end
	--[[ The player's own switch (`StealJuiceConfig.Setting`, 2026-10-02). Asked per steal, so a press on
		the settings screen mid-run counts from the next steal. No controller = the default. ]]
	local setting = Shard.get("StealCinematicController")
	if setting and not setting:wanted() then
		return
	end
	local _, band = CarRarity.of(rec.body)
	if band < cfg.MinBand then
		return
	end
	local now = os.clock()
	if cfg.Cooldown > 0 and now - (self._lastCine or -math.huge) < cfg.Cooldown then
		return
	end
	self._lastCine = now

	--- The door side, as a sign on the road's cross axis: which way the driver's seat sits off the
	--- car's centre. The driver goes out that side, so the door shot has to stand there.
	local seat = self:_driverSeat(rec)
	local side = 1
	if seat and self._info then
		side = if (seat.Position - rec.root.Position):Dot(self._info.cross) < 0 then -1 else 1
	end

	--- The door cut is timed off the driver's own release, so it lands a beat BEFORE he goes.
	local beat = math.max(self:_mountBeat(), 0.1)
	local clip = StealConfig.Animations.Clips.DriverThrown.Length
	local hold = clip * math.clamp(StealConfig.Driver.ReleaseAt, 0, 1) / math.max(StealConfig.Mount.PlaybackSpeed, 0.1)
	local cutAt = math.clamp(hold / beat - cfg.CutLead, cfg.CutMin, cfg.OutFrom - cfg.CutTime)

	local variants = cfg.HeroVariants
	self._cine = {
		startT = self._flight.t,
		startReal = now,
		beat = beat,
		side = side,
		cutAt = cutAt,
		hero = variants[self._rng:NextInteger(1, #variants)],
	}
	self._cam:setCinematic(function()
		return self:_cineShot()
	end)
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

--[[ This frame's directed shot: `{ cframe, fov, weight }`, or nil once the beat is over. Pure apart
	from reading the live car, roof, seat and thrown driver — the camera does the blending. ]]
function StealController._cineShot(self)
	local cine = self._cine
	local rec = self._target
	local info = self._info
	if not (cine and rec and rec.root and rec.root.Parent and info) or self._state ~= "mount" then
		return nil
	end
	local cfg = StealJuiceConfig.Cinematic
	local u = math.clamp((self._flight.t - cine.startT) / cine.beat, 0, 1)
	local roof = self:_roofCFrame(rec).Position
	local fwd, out, up = info.forward, info.cross * cine.side, Vector3.yAxis
	local focus = roof + up * cfg.FocusUp

	-- The hero shot, pushing in slowly across its span.
	local h = cine.hero
	local push = h.PushIn * smooth(u / math.max(cine.cutAt, 1e-3))
	local heroAt = roof + fwd * (h.Ahead - push * math.sign(h.Ahead)) + out * h.Out + up * (h.Up - (if h.Up > 0 then push else 0))
	local heroCF = CFrame.lookAt(heroAt, focus) * CFrame.Angles(0, 0, math.rad(h.Roll * cine.side))

	-- The door shot, looking at the door and following the driver once he is airborne.
	local d = cfg.Door
	local seat = self:_driverSeat(rec)
	local door = (if seat then seat.Position else roof - up * 2) + out * 1.5
	local look = door
	local body = self._cineDriver
	local bodyRoot = body and body.Parent and (body.PrimaryPart or body:FindFirstChild("HumanoidRootPart"))
	if bodyRoot and bodyRoot:IsA("BasePart") then
		look = door:Lerp(bodyRoot.Position, d.Track)
	end
	local doorAt = door + fwd * d.Ahead + out * d.Out + up * d.Up
	local doorCF = CFrame.lookAt(doorAt, look) * CFrame.Angles(0, 0, math.rad(d.Roll * cine.side))

	-- The timeline: fade in, hero, whip to the door, door, swoop out.
	local shot, fov
	if u < cine.cutAt then
		shot, fov = heroCF, h.Fov
	elseif u < cine.cutAt + cfg.CutTime then
		local a = smooth((u - cine.cutAt) / cfg.CutTime)
		shot, fov = heroCF:Lerp(doorCF, a), h.Fov + (d.Fov - h.Fov) * a
	else
		shot, fov = doorCF, d.Fov
	end
	local weight = smooth(u / math.max(cfg.BlendIn, 1e-3))
	if u > cfg.OutFrom then
		weight *= 1 - smooth((u - cfg.OutFrom) / math.max(1 - cfg.OutFrom, 1e-3))
	end
	return { cframe = shot, fov = fov, weight = weight }
end

-- === Feedback (`StealJuiceConfig`, 2026-09-30) =================================

--- One beat's clip out of the steal's sound bank. Silent with the flag off or no SoundController.
function StealController._sfx(self, beat: string)
	local cfg = StealJuiceConfig.Sounds
	local name = cfg.Enabled and cfg[beat]
	local sounds = Shard.get("SoundController")
	if type(name) == "string" and sounds then
		sounds:PlayNamed(cfg.Group, name)
	end
end

--- One of the steal's camera punches. See `RaceCameraController.stealPunch`.
function StealController._punch(self, kind: string)
	if self._cam then
		self._cam:stealPunch(kind)
	end
end

function StealController._notifyStolen(self, tier: number)
	--[[ THE TAKEOVER'S FEEDBACK, here because this is the one call made only by a handoff that
		worked. The toast reads the car's own stamps (`_applyTier` wrote them in step 1), so it names
		the body you are now driving rather than the record of the shell you left. ]]
	self:_sfx("Takeover")
	self:_punch("Takeover")
	--- The rev is the car's own engine, not a clip in the bank above. See `DriveConfig.EngineAudio.Rev`.
	if self._drive then
		self._drive:rev()
	end
	local car = self._car
	if car and car.Parent then
		Dispatcher:Publish("CarStolen", car:GetAttribute("Body"), car:GetAttribute("Paint"), car:GetAttribute("Mutation"), tier)
	end

	for fn in self._stealListeners do
		local ok, err = pcall(fn, tier)
		if not ok then
			self.log:warn(string.format("A steal listener errored: %s", tostring(err)))
		end
	end
end

-- === Lifecycle ==============================================================

function StealController._onRaceStart(self)
	self:_teardown()
	if not StealConfig.Enabled then
		return
	end
	if not self._road then
		self.log:warn("RoadController unavailable; the steal is off for this race.")
		return
	end
	self:_activate()
	self:_bind()
end

--- On for a flight: the folder, this run's JUMP levels, the frame loop. A race's start and the
--- collector highway's bail (`bailLobby`) both come through here.
function StealController._activate(self)
	local folder = Instance.new("Folder")
	folder.Name = FLIGHT_FOLDER
	folder.Parent = workspace
	self._folder = folder

	--[[ This run's JUMP levels, off the player's own replicated upgrades — the identical read
		`TrafficController` does for luck at the same beat, and for the identical reasons. It cannot
		move during a race (the board it is bought at stands on a forecourt and you are on a road), the
		levels are already on the Player, and a round trip at race start would be one more thing for
		the first spawn to wait on.

		A missing attribute — profile still loading, upgrades switched off — decodes to nothing and both
		factors answer 1, which is exactly the arc this had before the upgrade existed. ]]
	local upgrades = UpgradeConfig.decode(Players.LocalPlayer:GetAttribute(UpgradeConfig.Attribute))
	self._jumpForgiveness = UpgradeConfig.jumpForgivenessFactor(upgrades)
	--- ...and, since 2026-10-20, air time at the top of the arc and lock range (`UpgradeConfig.Upgrades.Jump`).
	self._jumpHang = UpgradeConfig.jumpHangFactor(upgrades)
	self._jumpRange = UpgradeConfig.jumpRangeFactor(upgrades)

	self._active = true
	self._wrecked = false
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end)
end

-- HP is gone. Stop offering the bail, and drop any flight still in the air — a wreck mid-steal
-- would otherwise land on a car the server has already taken away from us.
function StealController._onWrecked(self)
	self._wrecked = true
	self:_unbind()
	if self._state ~= "idle" then
		self:_abort()
	end
end

--[[ …and the wreck was paid out of (`ReviveService`): the bail goes back on offer.

	The exact inverse of `_onWrecked` and only of it. There is no flight to put back, because a wreck
	that landed mid-flight aborted it on the way in and a revive always comes back to `idle` — so the
	whole undo is the flag and the binding. `_bind` is idempotent, and gated on `_active` because a
	`RaceRevived` arriving outside a race (a late remote, the steal switched off in config) must not
	be the thing that binds a key for the lobby. ]]
function StealController._onRevived(self)
	if not self._active then
		return
	end
	self._wrecked = false
	--[[ ...EXCEPT AFTER A MISSED JUMP, which a revive can now come out of (the tutorial's free one,
		`TutorialConfig.Unlosable`, 2026-10-05; "badLanding" is not a cause anybody can PAY to revive).
		A whiff deliberately hands nothing back — the car hidden and anchored, the ragdoll on the tarmac,
		the systems suspended — because until now only `_teardown` ever followed it. Here the run goes
		on, so the whole of that is handed back the way a finished flight hands it back. ]]
	if self._downed then
		--[[ EVERYTHING BUT THE ANCHORS, NOW. First version (2026-10-05) unanchored the car here too,
			and the car came back "in the air, glitching": `RaceService.reviveRace` has the car FROZEN
			(anchored server-side) and is setting it down for `ReviveConfig.ReviveHoldTime`, and a
			client unanchoring it under that freeze simulates a car the server is holding still — two
			owners of one car. So the door is put back now and the anchors after the server's own thaw,
			which writes the same values for every part it knows; this pass is for any it does not. ]]
		if self._doorAngle and self._doorAngle ~= 0 and self._car and self._car.Parent then
			CarDoors.poseFrozen(self._car, -self._doorAngle)
		end
		self._doorAngle = 0
		local anchors = table.clone(self._carAnchors)
		table.clear(self._carAnchors)
		self:_endFlight(false)
		task.delay(ReviveConfig.ReviveHoldTime + 0.25, function()
			for part, anchored in anchors do
				if part.Parent and part.Anchored ~= anchored then
					part.Anchored = anchored
				end
			end
		end)
	end
	self:_bind()
end

function StealController._teardown(self)
	--- The race is going away with or without a flight up: the thumb flight controls go with it
	--- (`_syncFlightHud`), since `_step` will not run again to take them down.
	if self._hudFlying then
		self._hudFlying = false
		local hud = Shard.get("DrivingHudController")
		if hud and hud.setFlying then
			hud:setFlying(false)
		end
	end
	CarBody.discardPrepared(self._preparedBody)
	self._preparedBody = nil
	self._active = false
	self._wrecked = false
	self:_unbind()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end

	-- Restore before the car goes away, in whatever order the RaceEnd handlers happen to run.
	if self._state ~= "idle" then
		self:_endFlight(false)
	end
	-- Unconditionally, and outside that branch: a WHIFF leaves the car anchored and hidden on
	-- purpose (see `_whiff`) with the state already back to idle, so this is the only thing that
	-- ever hands it back. Idempotent — the table is cleared as it goes.
	self:_unanchorCar()
	-- Same reasoning, same idempotence: a shell whose door was never given back is broken in the
	-- pool for the rest of the session, and a race can end at any point in the beat.
	self:_closeShellDoor()
	self:_clearDriver()
	restoreTree(self._carHidden)
	self._carHidden = nil

	--[[ Everything the whiff deliberately held on to, released here because THIS is the moment the
		player leaves the car. Two of them:

		  • the ragdoll, which dies with the folder below;
		  • the rider, still hidden and still welded into that car. Claimed rather than left to a
		    timer, because a restore that fires after RaceService has fixed the rider's legs up would
		    quietly re-hide them — see `_restoreRider`. ]]
	local pending = self._pendingRestore or self._riderHidden
	self._pendingRestore = nil
	self._riderHidden = nil
	if pending then
		self:_restoreRider(pending, true)
	end

	if self._folder then
		self._folder:Destroy() -- takes the avatar and the marker with it
		self._folder = nil
	end
	self._marker = nil
	self._markerImage = nil
	self._predictedHighlight = nil
	self._markerSpin = 0
	if self._prompt then
		self._prompt:Destroy() -- in PlayerGui, so the folder above did not take it
	end
	self._prompt = nil
	self._promptScale = nil
	self._promptPop = 0
	self._candidate = nil
	self._perchOn = nil
	self._mountFrom = nil
	self._avatar = nil
	self._anim = nil
	self._falling = false
	self._car = nil
	self._info = nil
	self._target = nil
	self._downed = false
	self._flightView = nil
	if self._cam then
		self._cam:setFlight(nil)
		self._cam:setCinematic(nil)
	end
	self._cine = nil
	if self._wind then
		self._wind:setFlight(nil)
	end
	TimeScale.reset()
end

StealController:withRemoteEvents({
	{
		RaceStart = function()
			StealController:_onRaceStart()
		end,
		RaceWrecked = function()
			StealController:_onWrecked()
		end,
		RaceRevived = function()
			StealController:_onRevived()
		end,
		RaceEnd = function()
			StealController:_teardown()
		end,
	},
	"StealLanded",
	"StealFailed",
	"StealMissed",
})

StealController:withLifecycle({
	init = function(self)
		self._active = false
		self._wrecked = false
		self._bound = false
		self._stealBound = false -- E is bound only for the length of a flight; see _bindSteal
		self._state = "idle" -- "idle" | "launch" | "air" | "perch" | "mount"
		self._carAnchors = {} -- [BasePart] = wasAnchored, while the car is frozen for a flight
		self._flight = nil
		self._launchY = 0 -- deck-relative Y the launch rise is measured from
		self._carY = 0 -- the height the bailed car is flown at (its bail-time deck height)
		self._doorAngle = 0 -- degrees the door is currently posed open by; see _flyCar
		self._bailAlongVel = nil -- the speed we left the road at; see _onBail
		-- The JUMP upgrade, re-read at every race start (`_onRaceStart`). 1 is the unbought arc, and it
		-- is the value here rather than nil so an arc stepped before a race ever started is the old one
		-- rather than an error.
		self._jumpForgiveness = 1
		self._jumpHang = 1
		self._jumpRange = 1
		self._stealBufferedUntil = 0
		self._pendingRestore = nil -- a rider unhide waiting on the handoff's settle frames
		self._downed = false -- a whiffed bail is lying on the road; the camera is looking at it
		self._rng = Random.new()
		self._mountAt = 0 -- flight time at which the mount started
		self._mountFrom = nil -- world point the lunge onto the roof eases from; see _mountPose
		self._primaryToPivot = CFrame.identity
		self._prompt = nil -- the STEAL prompt billboard, built once per race and re-adorned
		self._promptScale = nil -- the UIScale the pop is driven through
		self._promptPop = 0 -- seconds into the prompt's scale-up
		self._candidate = nil -- the traffic record E would take right now, or nil
		self._perchOn = nil -- the roof being ridden during the grace window, nil if that's tarmac
		self._perchAt = 0 -- flight time the perch started
		self._anim = nil -- the flight avatar's clips; lives and dies with the avatar
		self._falling = false -- true once the bail clip has handed over to the freefall loop
		self._shellDoor = nil -- the stolen car's door panel, while it is ours to turn
		self._shellDoorAngle = 0 -- degrees it is currently posed open by
		self._driver = nil -- the NPC being thrown out, until physics takes it
		self._driverAnim = nil
		self._driverAt = 0 -- flight time the throw started
		self._driverFree = false -- true once the driver is a ragdoll and no longer ours
		-- Built once for the session and cloned per throw, because building them is a web call that
		-- yields; see `_buildDriverTemplate` and `_buildFriendDrivers`. The friend pool is what a
		-- throw uses when it has one; the template is the fallback it never stops needing.
		self._driverTemplate = nil
		self._driverPending = false
		self._friendTemplates = {} -- real avatars of up to `Driver.Friends.Count` of your friends
		self._friendsPending = false
		self._lastDriverRig = nil -- so two steals running never throw the same person out
		-- Survives a race teardown on purpose, exactly like the road's shift listeners: controllers
		-- register once at start and stay registered across every race. See `onStolen`.
		self._stealListeners = {} -- [fn] = true
	end,

	start = function(self)
		self._road = Shard.get("RoadController")
		self._drive = Shard.get("DriveController")
		self._traffic = Shard.get("TrafficController")
		self._obstacles = Shard.get("ObstacleController")
		self._cam = Shard.get("RaceCameraController")
		-- Held like the camera and read the same way: a bail hands it the arc so the air stops being
		-- the anchored car's. Optional — the wind is a cosmetic that a place without its art switches
		-- off entirely, and a bail must not depend on one being there.
		self._wind = Shard.get("WindController")

		--[[ All of these are network fetches and all of them are done here, at start-up, rather than at
			the bail — which is the one moment in the game that cannot afford to wait on anything. The
			clips are warmed so the FIRST bail of a session animates (an unloaded track plays nothing
			and then quietly starts, which on a 0.8s clip is the whole clip); the driver rigs are built
			once because `CreateHumanoidModelFromDescription` yields, and the friends list behind them
			yields twice more. Nothing blocks: a steal taken in the first second of a session simply
			gets whichever of them has landed, which is why the driver degrades friend → motorist →
			empty seat rather than erroring at any step. ]]
		if StealConfig.Animations.Enabled then
			RigAnimator.preload(StealConfig.Animations.Clips)
			self:_buildDriverTemplate()
			self:_buildFriendDrivers()
		end

		-- Registered once for the session, exactly like the other world-shift listeners: the road
		-- keeps them across race teardowns on purpose.
		if self._road then
			self._road:onWorldShift(function(shift)
				self:_onWorldShift(shift)
			end)
		end
	end,
})

return StealController
