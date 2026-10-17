--[[
	Ragdoll  (shared)
	-----------------
	Turn an animated rig into a body.

	THREE RIGS IN THIS GAME GO LIMP and they go limp for different reasons — the flight avatar when
	you mistime the signature mechanic (`StealController._whiff`), the driver you throw out of the
	car you are stealing (`StealController._throwDriver`), and the player themself when a wreck puts
	them through their own windscreen (`RaceService._throwRider`).

	AND THERE ARE TWO KINDS OF RIG TO DO IT TO, which is the thing to understand before touching
	anything here, because the two have almost nothing in common:

	  • A MOTOR6D RIG — the classic one. Joints are `Motor6D`s, and nothing physical holds the body
	    together at all, so going limp means BUILDING the physics: every Motor6D becomes a
	    `BallSocketConstraint` between two attachments placed at that joint's own `C0`/`C1`. The
	    joints therefore end up exactly where the rig's joints were and the body starts flopping from
	    the pose it was animating in; anything else and it snaps to a T-pose on the first frame.
	    Limits go on, because an unlimited socket lets limbs pass through the torso, which stops
	    being funny immediately and is the difference between "cartoon-physical" (GDD §5) and
	    unpleasant.

	  • A CONSTRAINT RIG — what Roblox actually hands you now, both for a live player character and
	    for anything built from a `HumanoidDescription`. There is not one Motor6D in it. Every joint
	    is ALREADY a `BallSocketConstraint`, already limited (per joint, by Roblox, better than one
	    number of ours could be), already paired with `NoCollisionConstraint`s — and the thing
	    holding the body in its animated pose on top of all that is an `AnimationConstraint`.
	    So going limp is not surgery here at all. It is `Enabled = false` on the animation
	    constraints, and the ball sockets that were always there take over.

	    This is why `limits` is ignored on that path, and it is worth knowing that the Motor6D branch
	    below is now the FALLBACK rather than the main road: measured against a live R15 character in
	    this place (2026-08-03) the rig is 15 `AnimationConstraint`s, 14 `BallSocketConstraint`s and
	    zero Motor6Ds. Code here that only knew about Motor6Ds was a silent no-op on every rig in the
	    game — the ragdolls simply never happened.

	  • ONE JOINT IS NEVER RELEASED, and it is the reason this matches constraints up by the PARTS
	    they span rather than just switching every `AnimationConstraint` off: `Root`
	    (LowerTorso ↔ HumanoidRootPart) has no ball socket behind it. Let go of that one and the
	    body separates from its own root part — which is also the part the camera is following, so
	    the shot calmly tracks an invisible box while the player lies somewhere off screen. The rule
	    that falls out is a good one in general: only let go of a joint something else is already
	    holding.

	Common to both:
	  • ACCESSORIES ARE LEFT ALONE. They hang off welds and `RigidConstraint`s rather than joints, so
	    hats and backpacks stay rigidly attached and tumble with the body, which is what you want.
	  • `Massless` HAS TO COME BACK OFF (`release`). The two clone rigs are built massless because
	    they are anchored puppets; leave them that way and the ragdoll has no inertia and behaves
	    like tissue paper.
	  • `CanQuery` STAYS OFF, deliberately. The stock CarBones suspension raycasts run as "Default"
	    and are not ours to filter, so a query-visible body lying in the road is something the car
	    can try to drive up.

	THE HUMANOID HAS TO SURVIVE THE CUT, and that is set up by the caller rather than here: a
	Humanoid with `RequiresNeck` left on kills itself the moment the neck joint stops holding, and
	with `BreakJointsOnDeath` also on that death blows the rest of the rig apart on the same frame.
	Both are switched off at all three call sites. The Humanoid is kept for a reason worth repeating
	— `Shirt`, `Pants` and `ShirtGraphic` only render on a model that contains one, so a rig stripped
	of its Humanoid tumbles down the road with no clothes on.

	TWO WAYS TO GO LIMP, AND THE DIFFERENCE IS WHETHER THE RIG HAS A FUTURE. `limp` is one-way, which
	is right for the two clone rigs: both exist only to fall over and are deleted seconds later.
	`collapse` records what it did and hands back a `Restore`, because the third rig is THE PLAYER'S
	OWN CHARACTER — they have to stand back up at the end of the beat, in one piece, or the run has
	cost them their session rather than their car.
]]

local Ragdoll = {}

export type Limits = { JointAngle: number, TwistAngle: number }

--[[ What `collapse` released, and everything `stand` needs to put it back. Opaque to callers — hold
	it and hand it back, don't read it. ]]
export type Restore = {
	joints: { Motor6D }, -- Motor6D rig: disabled, to be re-enabled
	poses: { AnimationConstraint }, -- constraint rig: ditto
	junk: { Instance }, -- the attachments and sockets `collapse` added (Motor6D rig only)
	collide: { [BasePart]: boolean },
	query: { [BasePart]: boolean },
}

--[[ The part an attachment ultimately hangs off. Walks up rather than reading `.Parent`, because in
	a real R15 constraint rig the SHOULDER sockets are attached to a `JointRotation` attachment that
	is itself parented to the shoulder's rig attachment — so one hop lands on an Attachment, not on a
	part, and matching by `.Parent` quietly loses both arms. ]]
local function partOf(attachment: Attachment?): BasePart?
	local inst: Instance? = attachment
	while inst and not inst:IsA("BasePart") do
		inst = inst.Parent
	end
	return inst :: BasePart?
end

-- The Motor6D cut itself, in one place so `limp` and `collapse` can only ever differ in what they do
-- to the Motor6D afterwards. Returns the socket and its two attachments, which is what `stand`
-- deletes.
local function socketFor(joint: Motor6D, limits: Limits): (BallSocketConstraint, Attachment, Attachment)
	local a0 = Instance.new("Attachment")
	a0.CFrame = joint.C0
	a0.Parent = joint.Part0
	local a1 = Instance.new("Attachment")
	a1.CFrame = joint.C1
	a1.Parent = joint.Part1

	local socket = Instance.new("BallSocketConstraint")
	socket.Attachment0, socket.Attachment1 = a0, a1
	socket.LimitsEnabled = true
	socket.TwistLimitsEnabled = true
	socket.UpperAngle = limits.JointAngle
	socket.TwistLowerAngle = -limits.TwistAngle
	socket.TwistUpperAngle = limits.TwistAngle
	socket.Parent = joint.Part0
	return socket, a0, a1
end

--[[ Switch off every `AnimationConstraint` whose joint a `BallSocketConstraint` is already holding,
	collecting them into `out`. Returns how many were released.

	The "already holding" test is the whole function — see the `Root` note in the header. Matching is
	on the unordered pair of PARTS, because the two constraints on one joint do not necessarily share
	attachments (the shoulders don't) or agree on which end is 0 (several don't). ]]
local function releasePoses(model: Model, out: { AnimationConstraint }): number
	local held: { [BasePart]: { [BasePart]: boolean } } = {}
	for _, c in model:GetDescendants() do
		if c:IsA("BallSocketConstraint") and c.Enabled then
			local p0, p1 = partOf(c.Attachment0), partOf(c.Attachment1)
			if p0 and p1 then
				held[p0] = held[p0] or {}
				held[p0][p1] = true
				held[p1] = held[p1] or {}
				held[p1][p0] = true
			end
		end
	end

	local n = 0
	for _, c in model:GetDescendants() do
		if c:IsA("AnimationConstraint") and c.Enabled then
			local p0, p1 = partOf(c.Attachment0), partOf(c.Attachment1)
			if p0 and p1 and held[p0] and held[p0][p1] then
				table.insert(out, c)
				c.Enabled = false
				n += 1
			end
		end
	end
	return n
end

--[[ Go limp, one way, for a rig that is going to be deleted rather than stood back up. Returns how
	many joints were released, so a caller can tell "this rig had no joints" from "it ran".

	Safe to call twice: the second pass finds no live Motor6Ds and no enabled animation constraints,
	and does nothing. ]]
function Ragdoll.limp(model: Model, limits: Limits): number
	local n = 0
	for _, joint in model:GetDescendants() do
		if joint:IsA("Motor6D") and joint.Part0 and joint.Part1 then
			socketFor(joint, limits)
			joint:Destroy()
			n += 1
		end
	end
	if n > 0 then
		return n -- a Motor6D rig; there are no animation constraints to find
	end
	return releasePoses(model, {})
end

--[[ The same thing, REVERSIBLE. For a rig that has to get up again — in practice the player's own
	character, thrown out of a wreck.

	Nothing is destroyed and nothing is forgotten: Motor6Ds are DISABLED rather than cut (which is
	what makes `stand` a boolean rather than an attempt to remember a skeleton — an Animator carries
	on writing `Transform` onto a disabled motor, which costs nothing and goes nowhere), and on a
	constraint rig there was never anything to destroy in the first place.

	COLLISION IS ONLY TOUCHED ON THE MOTOR6D PATH. There, the parts the cut joints connect are made
	solid and the root part is made NON-solid, because a Motor6D rig's collision was never set up for
	a body lying down: the root is a 2x2x1 block in the middle of the torso and, left solid, grounds
	out first and props the whole ragdoll up on a stilt. A constraint rig arrives with all of this
	already right (torso solid, limbs not, `NoCollisionConstraint`s between neighbours), and
	"improving" it is how you get a body that tangles in its own arms. `CanQuery` comes off either
	way, for the reason in the header.

	Returns nil if there was nothing to release, which is a caller's cue that this was not a rig at
	all and that nothing needs standing back up. ]]
function Ragdoll.collapse(model: Model, limits: Limits): Restore?
	local restore: Restore = { joints = {}, poses = {}, junk = {}, collide = {}, query = {} }
	local limbs: { [BasePart]: boolean } = {}

	for _, joint in model:GetDescendants() do
		if joint:IsA("Motor6D") and joint.Enabled and joint.Part0 and joint.Part1 then
			local socket, a0, a1 = socketFor(joint, limits)
			table.insert(restore.junk, socket)
			table.insert(restore.junk, a0)
			table.insert(restore.junk, a1)
			table.insert(restore.joints, joint)
			limbs[joint.Part0], limbs[joint.Part1] = true, true
			joint.Enabled = false
		end
	end
	if #restore.joints == 0 then
		releasePoses(model, restore.poses)
		if #restore.poses == 0 then
			return nil
		end
	end

	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			restore.collide[part] = part.CanCollide
			restore.query[part] = part.CanQuery
			part.CanQuery = false
			if limbs[part] then
				part.CanCollide = part ~= root
			end
		end
	end
	return restore
end

--[[ Put a `collapse`d rig back together. Idempotent, nil-safe, and safe over a rig that has since
	been partly destroyed — every instance is re-checked for a parent on the way through.

	THE SOCKETS GO BEFORE THE JOINTS COME BACK. Both in the same frame either way, so the solver
	never sees both — but written in the other order, one bad yield between them leaves every limb
	held by a ball socket AND a motor pulling to different poses, which is a body that shakes itself
	apart rather than one that stands up. ]]
function Ragdoll.stand(restore: Restore?)
	if not restore then
		return
	end
	for _, inst in restore.junk do
		if inst.Parent then
			inst:Destroy()
		end
	end
	table.clear(restore.junk)

	for part, canCollide in restore.collide do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end
	for part, canQuery in restore.query do
		if part.Parent then
			part.CanQuery = canQuery
		end
	end
	for _, joint in restore.joints do
		if joint.Parent then
			joint.Enabled = true
		end
	end
	table.clear(restore.joints)
	for _, pose in restore.poses do
		if pose.Parent then
			pose.Enabled = true
		end
	end
	table.clear(restore.poses)
end

--[[ Hand the rig to the solver and give it something to do.

	ORDER MATTERS AND IT IS THE ORDER WRITTEN HERE: unanchor first, seed the velocity second. An
	anchored assembly does not hold a velocity — the write is simply thrown away — which is the same
	trap `TrafficController._knock` and `StealController._finish` both document, and it fails
	silently as a body that drops straight down instead of being thrown. ]]
function Ragdoll.release(model: Model, velocity: Vector3, spin: Vector3)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Massless = false
			part.CanCollide = true
			part.CanQuery = false
			part.Anchored = false
		end
	end
	Ragdoll.throw(model, velocity, spin)
end

--[[ Just the velocity half of `release`, for a body that was never an anchored puppet and so needs
	none of the property pass — a `collapse`d player character is already unanchored, already has
	mass, and had its collision left exactly as the rig shipped it.

	Anchored parts are skipped rather than written to: the write would be silently thrown away (the
	trap above), and skipping them makes that visible in a debugger instead of looking like a
	velocity that didn't take. ]]
function Ragdoll.throw(model: Model, velocity: Vector3, spin: Vector3)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			part.AssemblyLinearVelocity = velocity
			part.AssemblyAngularVelocity = spin
		end
	end
end

-- A random tumble, `spin` rad/s on each axis. Here rather than in the callers so the three ragdolls
-- in the game shake out the same way.
function Ragdoll.spin(rng: Random, amount: number): Vector3
	return Vector3.new(
		rng:NextNumber(-amount, amount),
		rng:NextNumber(-amount, amount),
		rng:NextNumber(-amount, amount)
	)
end

return Ragdoll
