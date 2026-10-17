--[[
	CarDoorRig  (shared)
	--------------------
	Build the door rig `Modules/CarDoors` drives, by working out from the body's own geometry which
	meshes are the doors.

	WHY THIS IS DERIVED AND NOT AUTHORED. There are two moments a car needs doors and only one of
	them is a place file:

	  • the race car RaceService clones out of `Workspace.CarSystem`, which can be authored, and
	  • every car after that, which is a REDRESS — `CarBody.swapMeshes` rebuilds `Body/` flat from
	    the traffic shell the player landed on, so whatever door structure the previous body had is
	    gone and the seat's constraints point at parts that no longer exist.

	The second case is why an authored-only rig would have opened the doors on the first car of a
	run and on no car after it, which is the shape of bug that reads as "the doors sometimes don't
	work". Deriving the rig means one implementation covers both: the pack is rigged in the place by
	running `apply` from the Command Runner, and the steal re-runs the same `apply` on the fresh
	dress (`StealController._applyTier`).

	THE DISCRIMINATOR. A door is a `shell_*_body` mesh that (a) stays entirely on one side of the
	centreline, (b) has a mirrored twin on the other side, and (c) straddles its seat. (a) rejects
	the main shell and the windscreen, (b) rejects anything that only exists on one side, and (c)
	rejects mirrored trim like sills and fender flares, which are mirrored but nowhere near the
	seat. Run over the pack this picks the same 32 panels the hand survey in
	`docs/CarDoors_RigPlan.md` §5 found, independently, with no disagreements — and it needs no
	per-car table, so a body added to the pack later rigs itself.

	SWING DIRECTION IS NOT GUESSED. The hinge axis is the car's UP vector on the driver's side and
	its DOWN vector on the passenger's. That is what the working four-door rig on `CarBones` uses,
	and independently what falls out of requiring `CarDoors.poseFrozen` to carry the rear of the
	panel outboard at a positive `StealConfig.Doors.Angle`. The two sides are mirror images, so do
	not "simplify" them onto a shared axis: that opens one door and drives the other down through
	the sill. §7 of the plan is emphatic that reaching the target angle proves nothing about
	direction — `audit` therefore measures a world-space outboard displacement instead.

	THE PANELS STAY MASSLESS, which departs from §4 of the plan. That step exists so an unlatched
	door is a legal physics assembly on its own, and a door only becomes one inside `CarDoors.open`
	— which nothing in the game calls. The shipped beat is `poseFrozen` on an ANCHORED car with the
	latch still enabled, so the door is part of the car's assembly throughout and mass would be
	dead weight. It would not be free weight either: these panels are ~10x the mesh volume of the
	Lambo's, so even at Roblox's 0.01 density floor they add ~0.17 to a 420-mass car, breaking the
	redress rule that a dress weighs nothing — which is what keeps every body in the pack driving
	identically. If the servo path is ever wired up, pass `carryMass`.
]]

local CarDoorRig = {}

-- Hinge line inset inboard from the panel's outermost face, as a fraction of panel thickness. The
-- panel's box reaches past the car's skin because the door mesh carries the wing mirror at its
-- leading edge, so pivoting on the raw outer face would put the axis in mid-air outside the body.
-- Backing off a fraction of thickness lands it near the real skin line across the pack and holds
-- the mirror's forward sweep to ~0.3 studs, well inside the gap to the front wheel.
local HINGE_INSET_FRACTION = 0.15
local HINGE_INSET_MIN, HINGE_INSET_MAX = 0.15, 0.60

-- Only relevant when `carryMass` is set; see the header. Roblox's floor.
local DOOR_DENSITY = 0.01

-- How far a candidate may poke past the door's own box and still count as part of the door.
-- Generous outboard (a mirror sticks out past the panel), tight everywhere else (the windscreen
-- must not be swept up as a door part).
local CONTAIN_TOL = 0.15
local CONTAIN_OUTBOARD = 1.0

--[[ The same two allowances, for a part that sits ON the door's top edge rather than inside its box
	— see `belongsTo`. Both are measured off the pack rather than chosen: the window on the bodies
	that need them clears the panel's inboard face by 0.46–0.79 studs and overhangs its ends by up to
	0.29, while the nearest thing that must NOT be swept up is the steering wheel at 2.40 inboard and
	a rear quarter light 0.56 past the door's trailing edge. So both numbers sit in a wide gap, not
	on a threshold. ]]
local GREENHOUSE_INBOARD = 0.9
local GREENHOUSE_TOL = 0.45

-- Driver's side is local -X on every body in this pack: that is where `VehicleSeat` and the
-- `steering_wheel` sit, i.e. they are left-hand drive. Front is -Z.
local SIDES = {
	{ key = "FL", seat = "VehicleSeat", sign = -1, attachment = "BodyAttachmentFL", driver = true },
	{ key = "FR", seat = "SeatFR", sign = 1, attachment = "BodyAttachmentFR" },
}

--[[ ONLY THE DRIVER'S DOOR IS WIRED. The player leaves through it, so it is the only one the
	fiction justifies, and a passenger door flapping open on its own reads as damage rather than as
	someone getting out. It also halves the surgery the steal does per redress.

	THE POLICY IS APPLIED WHEN WIRING, NOT WHEN SEARCHING — `plan` still finds both panels. The
	"never overwrite an authored rig" guard in `apply` works by asking "is this seat already wired
	to a panel I would NOT have picked?", and if the search stopped at the driver's side that
	question has no answer for the passenger's: a legitimately authored passenger door would look
	like an unknown rig, and `apply` would refuse the whole car. Keeping the search symmetric costs
	one extra box comparison and keeps the guard honest.

	Flip this to false to open both again; nothing else has to change. ]]
local DRIVER_DOOR_ONLY = true

local BODY_FOLDER = "Body"
local CHASSIS_FOLDER = "Chassis"
local MOUNT_NAME = "RedressMount"
-- The chassis's own invisible hull. It lives under `Body/` but is not part of the dress.
local HULL_NAME = "HitBox"
local PANEL_PATTERN = "^shell_%d+_body$"

-- === Geometry ===============================================================

type Box = { min: Vector3, max: Vector3 }

-- A part's axis-aligned box in the frame `inv` inverts into. Taken from the eight corners of the
-- part's own box rather than from `Size`, because a redressed panel is not guaranteed to be
-- axis-aligned with the chassis and a rotated part's `Size` says nothing about its footprint.
local function boxIn(inv: CFrame, part: BasePart): Box
	local rel = inv * part.CFrame
	local h = part.Size / 2
	local mn, mx = Vector3.one * math.huge, Vector3.one * -math.huge
	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			for sz = -1, 1, 2 do
				local c = rel * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
				mn, mx = mn:Min(c), mx:Max(c)
			end
		end
	end
	return { min = mn, max = mx }
end

local function centre(b: Box): Vector3
	return (b.min + b.max) / 2
end

-- Is `b` a mirror image of `a` across the x=0 plane, to `tol`?
local function mirrors(a: Box, b: Box, tol: number): boolean
	return math.abs(-a.max.X - b.min.X) < tol
		and math.abs(-a.min.X - b.max.X) < tol
		and math.abs(a.min.Y - b.min.Y) < tol
		and math.abs(a.max.Y - b.max.Y) < tol
		and math.abs(a.min.Z - b.min.Z) < tol
		and math.abs(a.max.Z - b.max.Z) < tol
end

--[[ Does `inner` travel with the door whose box is `outer`, on the side given by `sign`? Tight in y
	and z; loose outboard in x so a protruding wing mirror still counts. A part crossing the
	centreline is a one-piece canopy or a windscreen and is deliberately left behind — dragging one
	off with the door would tear the roof open (plan §6).

	THE DOOR MESH DOES NOT ALWAYS INCLUDE THE WINDOW FRAME, and half the pack is built that way: the
	panel stops at the waistline, and the window, its surround and the wing mirror all stand proud of
	the box. Measured against it they are simultaneously too TALL (the glass reaches ~1.3 studs above
	the panel's top edge) and too far INBOARD (the greenhouse leans in with the tumblehome, ~0.6),
	so a single tight test threw all three away and the door swung out leaving its own window hanging
	in mid-air. That shipped on eight roster cars — every World 1 body but one.

	The fix is not a looser tolerance everywhere; it is a second case. A part whose BOTTOM is above
	the door's waist and no higher than its top edge is SEATED ON the door rather than beside it, and
	only that case gets the greenhouse allowances. The waist test is what keeps the cabin out (the
	steering wheel is above the top edge and well inboard, and would sail through both of the looser
	bounds), and holding z near the panel's own ends is what keeps a rear quarter light — which
	belongs to the bodywork behind the door — from being torn off with it. ]]
local function belongsTo(inner: Box, outer: Box, sign: number): boolean
	if inner.min.X * sign < 0 or inner.max.X * sign < 0 then
		return false
	end
	-- Nothing that hangs below the door's bottom edge ever rides with it, in either case.
	if inner.min.Y < outer.min.Y - CONTAIN_TOL then
		return false
	end
	local ridesOnTop = inner.min.Y >= (outer.min.Y + outer.max.Y) / 2 and inner.min.Y <= outer.max.Y + CONTAIN_TOL
	if not ridesOnTop and inner.max.Y > outer.max.Y + CONTAIN_TOL then
		return false
	end
	local tol = if ridesOnTop then GREENHOUSE_TOL else CONTAIN_TOL
	if inner.min.Z < outer.min.Z - tol or inner.max.Z > outer.max.Z + tol then
		return false
	end
	local outboard = if sign < 0 then outer.min.X - CONTAIN_OUTBOARD else outer.max.X + CONTAIN_OUTBOARD
	local inboardTol = if ridesOnTop then GREENHOUSE_INBOARD else CONTAIN_TOL
	local inboard = if sign < 0 then outer.max.X + inboardTol else outer.min.X - inboardTol
	local lo, hi = math.min(outboard, inboard), math.max(outboard, inboard)
	return inner.min.X >= lo and inner.max.X <= hi
end

-- === Survey =================================================================

export type SidePlan = {
	key: string,
	seat: BasePart,
	panel: BasePart,
	extras: { BasePart },
	hinge: CFrame, -- in the car's own frame
}

export type Plan = {
	car: Model,
	chassis: Instance,
	body: Instance,
	mount: BasePart,
	frame: CFrame,
	sides: { [string]: SidePlan },
	notes: { string },
}

--[[ Work out what rigging this car would touch, WITHOUT touching it.

	Returns nil plus a reason when the body has no riggable doors, which is a normal outcome rather
	than an error: three bodies in the pack genuinely have no separable panel (plan §6), and
	`CarDoors` treats a doorless car as a clean no-op by design. ]]
function CarDoorRig.plan(car: Model): (Plan?, string?)
	-- Deliberately NOT a `car.Parent` check. The race car is rigged while it is still an unparented
	-- clone, so that the rig replicates as part of its initial state; requiring a parent here
	-- rejected exactly the case this is for, and did it quietly, as an info line about a car with
	-- "no doors".
	if not (car and car:IsA("Model")) then
		return nil, "not a Model"
	end
	local chassis = car:FindFirstChild(CHASSIS_FOLDER)
	local body = car:FindFirstChild(BODY_FOLDER)
	if not (chassis and body) then
		return nil, "no Chassis/Body"
	end
	local mount = chassis:FindFirstChild(MOUNT_NAME)
	if not (mount and mount:IsA("BasePart")) then
		return nil, "no Chassis." .. MOUNT_NAME
	end

	local frame = mount.CFrame
	local inv = frame:Inverse()
	local notes = {}

	-- Box every candidate once; the mirror search below is quadratic over this list.
	local boxes: { { part: BasePart, box: Box } } = {}
	local candidates: { { part: BasePart, box: Box } } = {}
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= HULL_NAME then
			local entry = { part = p, box = boxIn(inv, p) }
			table.insert(boxes, entry)
			-- A shell that stays one side of the centreline is a door candidate; a full-width one
			-- is the car's main body and can never be a door.
			if p.Name:match(PANEL_PATTERN) and (entry.box.min.X * entry.box.max.X) > 0 then
				table.insert(candidates, entry)
			end
		end
	end

	local sides: { [string]: SidePlan } = {}
	for _, side in SIDES do
		local seat = chassis:FindFirstChild(side.seat)
		if not (seat and seat:IsA("BasePart")) then
			table.insert(notes, `no Chassis.{side.seat}`)
			continue
		end
		local seatZ = (inv * seat.CFrame).Position.Z

		-- Where more than one candidate qualifies, the tallest wins: a door reaches the window
		-- line, a sill does not.
		local best, bestHeight = nil, -1
		for _, e in candidates do
			if centre(e.box).X * side.sign <= 0 then
				continue
			end
			if seatZ < e.box.min.Z or seatZ > e.box.max.Z then
				continue
			end
			local twin = false
			for _, o in candidates do
				if o ~= e and mirrors(e.box, o.box, 0.25) then
					twin = true
					break
				end
			end
			if not twin then
				continue
			end
			local height = e.box.max.Y - e.box.min.Y
			if height > bestHeight then
				best, bestHeight = e, height
			end
		end

		if not best then
			table.insert(notes, `{side.key}: no separable door panel`)
			continue
		end

		local extras = {}
		for _, e in boxes do
			if e.part ~= best.part and belongsTo(e.box, best.box, side.sign) then
				table.insert(extras, e.part)
			end
		end
		if #extras == 0 then
			table.insert(notes, `{side.key}: no window pane (one-piece canopy?) — rigs without it`)
		end

		--[[ The hinge line: vertical, at the panel's leading edge, backed off the outer face. The
			height is genuinely free — a vertical axis is fixed by its x and z alone — so it sits at
			the panel's mid-height, which is where it reads sensibly in the explorer. ]]
		local thickness = best.box.max.X - best.box.min.X
		local inset = math.clamp(thickness * HINGE_INSET_FRACTION, HINGE_INSET_MIN, HINGE_INSET_MAX)
		local hingeX = if side.sign < 0 then best.box.min.X + inset else best.box.max.X - inset
		local hingePos = Vector3.new(hingeX, centre(best.box).Y, best.box.min.Z)

		sides[side.key] = {
			key = side.key,
			seat = seat,
			panel = best.part,
			extras = extras,
			-- Axis on X (a hinge turns about its attachment's primary axis), mirrored per side.
			hinge = CFrame.fromMatrix(hingePos, Vector3.new(0, side.sign < 0 and 1 or -1, 0), Vector3.new(-1, 0, 0)),
		}
	end

	if not next(sides) then
		return nil, "no door panels: " .. table.concat(notes, "; ")
	end
	return { car = car, chassis = chassis, body = body, mount = mount, frame = frame, sides = sides, notes = notes }, nil
end

-- === Surgery ================================================================

local function weldsTouching(car: Model, part: BasePart): { WeldConstraint }
	local found = {}
	for _, d in car:GetDescendants() do
		if d:IsA("WeldConstraint") and (d.Part0 == part or d.Part1 == part) then
			table.insert(found, d)
		end
	end
	return found
end

--[[ Put a rigged car back the way a redress leaves it, so `apply` can run over a car that is
	already rigged without stacking a second rig on the first. Each step is the inverse of one in
	`apply`. Safe on a car that was never rigged. ]]
function CarDoorRig.unrig(car: Model): number
	local chassis = car and car:FindFirstChild(CHASSIS_FOLDER)
	local body = car and car:FindFirstChild(BODY_FOLDER)
	local mount = chassis and chassis:FindFirstChild(MOUNT_NAME)
	if not (chassis and body and mount) then
		return 0
	end

	local undone = 0
	for _, side in SIDES do
		local seat = chassis:FindFirstChild(side.seat)
		local hinge = seat and seat:FindFirstChild("DoorHinge")
		local latch = seat and seat:FindFirstChild("DoorLatchWeld")
		local panel = latch and latch:IsA("WeldConstraint") and latch.Part1
		local model = panel and panel.Parent

		if hinge and hinge:IsA("HingeConstraint") then
			local a0 = hinge.Attachment0
			hinge.Attachment0 = nil
			if a0 and a0.Name == "DoorAttachment" then
				a0:Destroy()
			end
			hinge.TargetAngle = 0
		end
		if latch and latch:IsA("WeldConstraint") then
			latch.Part1 = nil
		end

		if panel and model and model:IsA("Model") and model ~= body then
			for _, child in model:GetChildren() do
				if child:IsA("BasePart") then
					for _, w in child:GetChildren() do
						if w:IsA("WeldConstraint") then
							w:Destroy()
						end
					end
					child.Parent = body
					child.Massless = true
					child.CustomPhysicalProperties = nil
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = mount
					weld.Part1 = child
					weld.Parent = child
				end
			end
			model:Destroy()
			undone += 1
		end
	end
	return undone
end

--[[ Rig the front doors `DRIVER_DOOR_ONLY` allows — one, today. Returns how many were wired, plus
	a note per side for a caller that wants to report. Idempotent — a rigged car is unrigged first.

	ORDER MATTERS. The latch is wired and enabled BEFORE the panel's old weld to `RedressMount` is
	destroyed, so the panel is never off the car's assembly, even for an instant. And nothing here
	writes a part's `.CFrame`: that drags every rigidly welded part along with it, in edit mode
	too, which is how "let me just preview one door" ends up rotating the whole car. The only thing
	moved is an `Attachment`, which moves alone. ]]
function CarDoorRig.apply(car: Model, carryMass: boolean?): (number, { string })
	local plan, err = CarDoorRig.plan(car)
	if not plan then
		return 0, { err or "unknown" }
	end

	--[[ NEVER OVERWRITE AN AUTHORED RIG. The Lambo's doors are scissor — a lateral hinge axis and a
		pivot ahead of the panel — and re-deriving them as conventional swing-out would quietly
		convert an Aventador into a saloon. It is protected by accident today (its panels are named
		`LF_door_body`, so `plan` finds nothing and returns above), but accident is not a guarantee:
		any future body carrying both a hand-authored rig and `shell_*_body` panels would be
		silently rewritten.

		The test is deliberately "wired to a panel I did NOT choose" rather than "wired at all", so
		re-running over a car this module rigged itself still re-rigs it and `apply` stays
		idempotent.

		AND THE WIRED PANEL HAS TO STILL BE ON THE CAR. `CarBody` strips the old dress by setting
		`Parent = nil`, not by destroying it, and a weld only drops its references when the part is
		DESTROYED — so after a redress this constraint still points at an orphaned panel drifting
		wherever the car was at the swap. Read naively that is "already rigged to something I did
		not pick", and the guard would refuse to rig every car after the first steal: doors on the
		car you start in, and never again. ]]
	for _, side in SIDES do
		local seat = plan.chassis:FindFirstChild(side.seat)
		local latch = seat and seat:FindFirstChild("DoorLatchWeld")
		local wired = latch and latch:IsA("WeldConstraint") and latch.Part1
		if wired and not wired:IsDescendantOf(car) then
			wired = nil -- an orphan from the last dress, not an authored rig
		end
		local sp = plan.sides[side.key]
		if wired and (not sp or wired ~= sp.panel) then
			return 0, { `{side.key} is already rigged to '{wired.Name}', which is not the panel this would pick — leaving the authored rig alone` }
		end
	end

	CarDoorRig.unrig(car)

	local log = table.clone(plan.notes)
	local rigged = 0

	for _, side in SIDES do
		local sp = plan.sides[side.key]
		if not sp then
			continue
		end
		-- The passenger door is found but left welded to the body. `unrig` above already cleared
		-- any rig a previous policy left on it, so flipping the flag is safe in both directions.
		if DRIVER_DOOR_ONLY and not side.driver then
			table.insert(log, `{side.key}: {sp.panel.Name} found, left shut (driver's door only)`)
			continue
		end
		local hinge = sp.seat:FindFirstChild("DoorHinge")
		local latch = sp.seat:FindFirstChild("DoorLatchWeld")
		if not (hinge and hinge:IsA("HingeConstraint") and latch and latch:IsA("WeldConstraint")) then
			table.insert(log, `{side.key}: seat has no DoorHinge/DoorLatchWeld — skipped`)
			continue
		end

		--[[ The wrapping Model is REQUIRED, not tidiness. `CarDoors.poseFrozen` tests
			`latch.Part1.Parent:IsA("Model")` and silently skips a bare part — and `poseFrozen` is
			the path the bail actually uses, so skipping this passes every static check and then
			does nothing on screen. ]]
		local model = Instance.new("Model")
		model.Name = `{side.key}door`

		local carried = { sp.panel }
		table.move(sp.extras, 1, #sp.extras, 2, carried)
		for _, part in carried do
			-- A welded door cannot hinge; the servo just fights the joint and the door shudders.
			for _, w in weldsTouching(car, part) do
				w:Destroy()
			end
		end

		sp.panel.Parent = model
		model.PrimaryPart = sp.panel
		if carryMass then
			sp.panel.Massless = false
			sp.panel.CustomPhysicalProperties = PhysicalProperties.new(DOOR_DENSITY, 0.3, 0.5, 1, 1)
		end

		for _, extra in sp.extras do
			extra.Parent = model
			extra.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Name = `{side.key}doorWeld`
			weld.Part0 = sp.panel
			weld.Part1 = extra
			weld.Parent = extra
		end
		model.Parent = plan.body

		--[[ Both attachments are built from the SAME world CFrame, which is what makes the shut
			pose read as angle zero: a servo measures `CurrentAngle` between the two attachments'
			secondary axes, so any mismatch here is a permanent offset the door can never close out
			of. ]]
		local world = plan.frame * sp.hinge

		local anchor = plan.mount:FindFirstChild(side.attachment)
		if not (anchor and anchor:IsA("Attachment")) then
			anchor = Instance.new("Attachment")
			anchor.Name = side.attachment
			anchor.Parent = plan.mount
		end
		anchor.WorldCFrame = world

		local doorAtt = Instance.new("Attachment")
		doorAtt.Name = "DoorAttachment"
		doorAtt.Parent = sp.panel
		doorAtt.WorldCFrame = world

		hinge.Attachment0 = doorAtt
		hinge.Attachment1 = anchor
		hinge.TargetAngle = 0
		latch.Part0 = sp.seat
		latch.Part1 = sp.panel
		latch.Enabled = true

		rigged += 1

		local names = {}
		for _, e in sp.extras do
			table.insert(names, e.Name)
		end
		table.insert(log, `{side.key}: {sp.panel.Name} carrying [{#names > 0 and table.concat(names, ",") or "-"}]`)
	end

	return rigged, log
end

-- === Verification ===========================================================

--[[ Check a rigged car the way plan §8 asks: by a world-space displacement, never by an angle. A
	door swinging down through the road reaches its target angle just as happily as one swinging
	out, so "it got to 55°" proves nothing — the Lambo shipped for a day sweeping 2.76 studs under
	the road on exactly that evidence.

	The rotation applied here is the one `CarDoors.poseFrozen` applies, negation included, so this
	measures the shipped beat rather than a reconstruction of it. ]]
function CarDoorRig.audit(car: Model, degrees: number): { string }
	local out = {}
	local chassis = car and car:FindFirstChild(CHASSIS_FOLDER)
	if not chassis then
		return { "no Chassis" }
	end
	local right = car:GetPivot().RightVector
	for _, side in SIDES do
		local seat = chassis:FindFirstChild(side.seat)
		local hinge = seat and seat:FindFirstChild("DoorHinge")
		local latch = seat and seat:FindFirstChild("DoorLatchWeld")
		-- Same descendant test as `CarDoors.rigs`: a panel the last redress orphaned is still a
		-- live reference, and reporting its swing would say "OK" about a car with no doors on it.
		if
			not (
				hinge
				and latch
				and latch:IsA("WeldConstraint")
				and latch.Part1
				and latch.Part1:IsDescendantOf(car)
				and hinge.Attachment1
			)
		then
			table.insert(out, `{side.key}: NOT RIGGED`)
			continue
		end
		local panel = latch.Part1
		local anchorAtt = hinge.Attachment1
		local pivot = anchorAtt.WorldPosition
		local turn = CFrame.fromAxisAngle(anchorAtt.WorldCFrame.RightVector, math.rad(-degrees))
		local move = CFrame.new(pivot) * turn * CFrame.new(-pivot)

		-- Outboard is measured against the car's own axis, not the world's, so this stays true
		-- whichever way the car happens to be pointing.
		local before = panel.CFrame.Position
		local after = (move * panel.CFrame).Position
		local outboard = (after - before):Dot(right) * side.sign
		local rise = after.Y - before.Y

		--[[ A scissor door is not a failed swing-out door. The Lambo's hinge axis is lateral, so
			its panel LIFTS and barely moves outboard — which is correct for an Aventador and would
			read as "WRONG DIRECTION" against a swing-out expectation. Judge by which component
			dominates, and only call it wrong when the panel goes neither out nor up. ]]
		local verdict
		if outboard > 0.5 and outboard >= math.abs(rise) then
			verdict = "OK swings out"
		elseif rise > 0.5 then
			verdict = "OK scissor (lifts)"
		else
			verdict = "WRONG DIRECTION"
		end

		table.insert(out, string.format("%s: %s outboard %+.2f height %+.2f [%s]", side.key, panel.Name, outboard, rise, verdict))
	end
	return out
end

return CarDoorRig
