--[[
	CarBody  (shared, client-side in practice)
	------------------------------------------
	Make the car you're driving BE the car you just stole.

	This is the visual half of the steal's handoff, and it's small for a reason that is the entire
	premise of `CarSystem_HandoffPlan.md` §1: every car in this game is one shared `CarBones`
	chassis plus a set of massless, non-colliding visual meshes welded on top. The chassis, the
	seat, the tuned suspension, the `Scripts.Chassis` module DriveController has wrapped, the
	collision group and the network ownership are all body-agnostic. So "I am now driving a
	different car" is honestly expressible as "swap the meshes and repaint them" — nothing about
	the thing being driven changes.

	Measured across the 33-car pack (2026-07-29) rather than assumed: every one of them has an
	identical `HitBox` (8.43 x 1.75 x 20.57), an identical 12.36-stud wheelbase, and identical
	wheel- and seat-offsets relative to `Chassis.RedressMount`. They are the same rig wearing
	different clothes, which is what makes the graft below exact instead of approximate.

	=== THE GRAFT ==============================================================================

	`swapMeshes` rebuilds `Body/` from the traffic shell the player landed on. Two mounts, and the
	split between them is the whole trick:

	  • THE BODYWORK goes on `Chassis.RedressMount` — one rigid part of the chassis, which is where
	    every car in the pack already welds its shell, glass, lights and trim.
	  • THE FOUR WHEEL VISUALS go on the matching `Chassis.Suspension*/Wheel`, and must not go on the
	    bodywork mount: those are the physics wheels, so a visual welded to them spins and steers for
	    free. Weld them to the body instead and you get a car whose wheels don't turn.

	Which mesh is which is not guessed here — `TrafficService._mountTag` resolved it from each source
	mesh's own WeldConstraint at publish time and stamped the answer on the shell part as a
	`DressMount` attribute. The frames those offsets are measured against ride on the shell as
	`MountFrame` / `WheelFrame*` (see `TrafficService._stampMountFrames`, which also explains why the
	mount frames are used rather than the two cars' deck frames — the deck answer is off by the
	target's live suspension travel).

	So the client needs nothing but the shell it is already holding: no access to the source rig, no
	measuring, no second published template. `newMeshCF = targetMount.CFrame * sourceMount:ToObjectSpace(meshCF)`.

	=== WHAT IT DOESN'T DO =====================================================================

	Nothing here touches mass, collision or joints on the chassis, and nothing here is allowed to:
	the handling is CarBones' and we don't re-tune it. The `HitBox` is left strictly alone for the
	same reason — it lives under `Body/` but it is the chassis's own invisible hull, it owns Health,
	and it is the volume ObstacleController's wall sensor rides.

	DOOR RIGS DO NOT COME ACROSS, and are rebuilt afterwards rather than carried. A body's doors are
	driven by constraints that live on the SEATS (`Modules/CarDoors`), pointing at door root parts in
	the dress; grafting the meshes leaves those pointing at parts that no longer exist, so
	`CarDoors.rigs` reports none. Transferring the rig through the graft would mean teaching this
	function which meshes are doors, and the flat shell it is handed does not say. So the split is:
	this module puts the bodywork on, and `Modules/CarDoorRig` re-derives the doors from the result's
	geometry — `StealController._applyTier` calls them back to back. Anything that reaches a car
	between those two calls sees a doorless body, which is a safe state but not a rigged one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarPaint = require(ReplicatedStorage.shared.Modules.CarPaint)

local CarBody = {}

-- The container the redress lives in on a rigged car (handoff doc §4). Everything visible about a
-- car's identity is under here; the chassis is its sibling.
local BODY_FOLDER = "Body"
-- The chassis's own invisible hull, which lives under `Body/` but is NOT part of the dress — it
-- owns Health and is sized to the chassis, so a redress must leave it exactly alone.
local HULL_NAME = "HitBox"

-- The two mounts a dress hangs off, keyed by the `DressMount` tag TrafficService stamps on each
-- shell mesh: `BODY_MOUNT` for the bodywork, a corner name for a wheel visual.
local BODY_MOUNT = "Body"
local CORNERS = { "FL", "FR", "RL", "RR" }
local SUSPENSION_PREFIX = "Suspension"
local WHEEL_NAME = "Wheel"
local MOUNT_NAME = "RedressMount"
-- Attribute names on a published shell (TrafficService._stampMountFrames).
local MOUNT_FRAME_ATTR = "MountFrame"
local WHEEL_FRAME_ATTR = "WheelFrame"
local DRESS_MOUNT_ATTR = "DressMount"
-- Children of a shell part worth carrying across: everything that makes it RENDER, and nothing
-- else. In particular the shell's own weld to its `Root` must not come along — see `swapMeshes`.
-- `SurfaceGui` is in the list because the number plate's text lives on one (`plate_face/PlateText`);
-- without it a stolen car arrives wearing a blank plate.
local RENDER_CLASSES = { "SpecialMesh", "Decal", "Texture", "SurfaceAppearance", "SurfaceGui" }

--[[ The meshes on `car` that take a paint.

	`Modules/CarPaint` owns the answer, and owns it for everyone — the traffic shell being tinted on
	the road, the display car on a garage podium and the one parked in the street all ask the same
	function, so the car you drove past and the car you keep can never disagree about which parts are
	"the paintwork". That module's header has the rule and the two real cars that broke each half of
	it on its own.

	Kept as a passthrough here rather than deleted because this module is the door the steal path
	comes in through, and `CarBody.paintParts(car)` is what reads correctly at that call site. ]]
function CarBody.paintParts(car: Model): { BasePart }
	return CarPaint.parts(car)
end

--[[ Repaint a car. Returns how many parts took the colour, so a caller can tell "the redress ran"
	from "the redress found nothing to do" — a car rigged without a `Body/` folder, or with meshes
	that don't match, is a silent no-op otherwise and reads as the steal being broken. ]]
function CarBody.paint(car: Model, color: Color3, detailMap: string?): number
	return CarPaint.paint(CarPaint.parts(car), color, detailMap)
end

--[[ The chassis parts on `car` a dress hangs off, keyed by `DressMount` tag. nil if this model isn't
	a CarBones rig at all, which is the one case a caller must not carry on past — stripping a car's
	body and then finding nowhere to put the new one back is the worst outcome available here.

	A MISSING CORNER IS TOLERATED and the bodywork mount is not. A rig with three wheels still makes a
	drivable car with one visual in the wrong place; a rig with no `RedressMount` has nothing to dress. ]]
function CarBody.mounts(car: Model): { [string]: BasePart }?
	local chassis = car and car:FindFirstChild("Chassis")
	local mount = chassis and chassis:FindFirstChild(MOUNT_NAME)
	if not (mount and mount:IsA("BasePart")) then
		return nil
	end

	local out = { [BODY_MOUNT] = mount }
	for _, corner in CORNERS do
		local suspension = chassis:FindFirstChild(SUSPENSION_PREFIX .. corner)
		local wheel = suspension and suspension:FindFirstChild(WHEEL_NAME)
		if wheel and wheel:IsA("BasePart") then
			out[corner] = wheel
		end
	end
	return out
end

--[[ Where a shell's meshes were measured from, in world space: the frames the source car's
	`RedressMount` and physics wheels would be at if this shell were that car.

	Recorded root-relative at publish time, so this composes them back through wherever the shell
	currently is — which for a live traffic car is 300 studs up the road, doing 40 studs/s. nil for a
	shell published before the frames existed, or one built from a rig that has no `RedressMount`;
	either way the caller declines the swap rather than grafting a body onto guessed geometry. ]]
function CarBody.dressFrames(shell: Model): ({ [string]: CFrame }?, BasePart?)
	local root = shell and (shell.PrimaryPart or shell:FindFirstChild("Root"))
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local mount = shell:GetAttribute(MOUNT_FRAME_ATTR)
	if typeof(mount) ~= "CFrame" then
		return nil
	end

	local out = { [BODY_MOUNT] = root.CFrame * mount }
	for _, corner in CORNERS do
		local wheel = shell:GetAttribute(WHEEL_FRAME_ATTR .. corner)
		if typeof(wheel) == "CFrame" then
			out[corner] = root.CFrame * wheel
		end
	end
	return out, root
end

--[[ Swap `car`'s visual body for the one `shell` is wearing. The header has the geometry; this is the
	order of operations, and each step is load-bearing.

	MEASURE EVERYTHING BEFORE DESTROYING ANYTHING. The offsets are collected up front and the function
	returns early if the shell turns out to carry no dress, so the failure mode is "the car keeps the
	body it had" rather than "the player is driving an invisible chassis". Same reason `mounts` is
	resolved first.

	THE SHELL'S OWN WELD MUST NOT COME ACROSS. Every mesh in a shell carries a WeldConstraint to that
	shell's `Root`. Cloning one part alone keeps `Part0` pointing at the ORIGINAL root — Roblox only
	remaps references that live inside the cloned subtree — so a naive clone arrives welded to the
	traffic car it was taken from and follows it down the road. Only render children survive.

	THE CFRAME IS SET BEFORE THE WELD IS PARENTED, always. A WeldConstraint bakes the offset it finds
	at the moment it binds, so a weld created before the part is in place cements the wrong pose. There
	is no yield anywhere in this function for the same reason: the target is a live rig, and a physics
	step landing between placing a part and welding it would bake whatever the assembly had moved to.
	(StealController runs this while the car is still ANCHORED, which removes the risk entirely — see
	`_finish`.)

	The clones are created UNANCHORED, which is not an oversight: welding them to a mount that is
	currently anchored puts them in the anchored assembly, and they join the live one when the car is
	handed back to physics. Nothing has to remember to unanchor them. ]]
-- 2026-10-04: Snapshot the closed shell before the mount animation opens its door. Cloning is
-- spread across that existing beat; no live chassis parts are replaced until commit.
function CarBody.prepare(car: Model, shell: Model)
	local body = car and car:FindFirstChild(BODY_FOLDER)
	local targets = CarBody.mounts(car)
	local sources, root = CarBody.dressFrames(shell)
	if not (body and targets and sources and root) then
		return nil
	end

	local dress = {}
	for _, part in shell:GetChildren() do
		local tag = part:IsA("BasePart") and part ~= root and part:GetAttribute(DRESS_MOUNT_ATTR)
		if type(tag) == "string" then
			-- An unknown or unrigged corner falls back to the bodywork mount: a wheel that doesn't spin
			-- is a far better outcome than a wheel that isn't there.
			local mount = targets[tag] or targets[BODY_MOUNT]
			local from = sources[tag] or sources[BODY_MOUNT]
			table.insert(dress, { part = part, mount = mount, offset = from:ToObjectSpace(part.CFrame) })
		end
	end
	if #dress == 0 then
		return nil
	end
	return { car = car, shell = shell, body = body, dress = dress, next = 1 }
end

function CarBody.stepPrepared(prepared, budget: number): boolean
	for index = prepared.next, math.min(#prepared.dress, prepared.next + budget - 1) do
		local entry = prepared.dress[index]
		local clone = entry.part:Clone()
		for _, child in clone:GetChildren() do
			local render = false
			for _, class in RENDER_CLASSES do
				if child:IsA(class) then
					render = true
					break
				end
			end
			if not render then
				child:Destroy()
			end
		end

		clone.Anchored = false
		clone.Massless = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		local weld = Instance.new("WeldConstraint")
		entry.clone, entry.weld = clone, weld
		prepared.next = index + 1
	end
	return prepared.next > #prepared.dress
end

function CarBody.discardPrepared(prepared)
	if not prepared then
		return
	end
	for _, entry in prepared.dress do
		if entry.weld then
			entry.weld:Destroy()
			entry.weld = nil
		end
		if entry.clone then
			entry.clone:Destroy()
			entry.clone = nil
		end
	end
end

function CarBody.swapMeshes(car: Model, shell: Model, prepared): boolean
	if prepared and (prepared.car ~= car or prepared.shell ~= shell
		or prepared.body ~= car:FindFirstChild(BODY_FOLDER)) then
		CarBody.discardPrepared(prepared)
		prepared = nil
	end
	prepared = prepared or CarBody.prepare(car, shell)
	if not prepared then
		return false
	end
	-- A short animation or dropped frames must never delay a steal: finish any remainder now.
	CarBody.stepPrepared(prepared, #prepared.dress)
	local body = prepared.body
	for _, child in body:GetChildren() do
		if child.Name ~= HULL_NAME then
			child:Destroy()
		end
	end
	for _, entry in prepared.dress do
		local clone, weld = entry.clone, entry.weld
		clone.CFrame = entry.mount.CFrame * entry.offset
		clone.Parent = body
		weld.Part0, weld.Part1 = entry.mount, clone
		weld.Parent = clone
		-- Ownership now belongs to the live car; cancellation must not destroy the new dress.
		entry.clone, entry.weld = nil, nil
	end
	return true
end

--[[ The whole visual redress, in one call: make `car` look like `shell`, in `paint`.

	`shell` is the traffic shell being stolen — its meshes are the look being taken — and `paint` is
	the `PaintConfig` palette index that shell was rolled with.

	THE PAINT IS VERY NEARLY REDUNDANT HERE, and it is worth knowing why it is still done. The shell
	standing in the road has ALREADY been painted (`TrafficController._spawn`), and `swapMeshes` clones
	its parts, so the colour arrives on the player's car by itself — that is what makes the car you
	drive away in the car you were looking at, down to the paint, with nothing having to be told. What
	this second pass buys is the case where the shell's own repaint found nothing: the car then gets
	the colour on whatever `CarPaint` can find on the RIGGED body, which is a different search over
	different geometry. It costs a walk of ~30 parts on a frame that is already anchored.

	`body` is the roster name of the car being taken, and it only reaches `CarPaint` to look up that
	body's detail map. The swap itself does not need it: `RENDER_CLASSES` carries `SurfaceAppearance`
	across, so a shell painted on the road arrives with its detail map already on it and this second
	pass is putting the same one back.

	Returns whether anything visibly changed, which is what the caller warns on: a steal that swaps
	nothing is a bug worth hearing about once. ]]
function CarBody.apply(car: Model, shell: Model?, paint: unknown, body: unknown, prepared): boolean
	local changed = false
	if shell and CarBody.swapMeshes(car, shell, prepared) then
		changed = true
	end
	if CarPaint.apply(car, paint, body) > 0 then
		changed = true
	end
	return changed
end

return CarBody
