--[[
	ShellDoors  (shared, client-side in practice)
	--------------------------------------------
	Swing the driver's door of a TRAFFIC SHELL — the car you land on during a steal, as you land on
	it.

	WHY THIS IS NOT `Modules/CarDoors`. That module drives a real CarBones rig: a servo
	`HingeConstraint` and a latch `WeldConstraint` living on the seat, which every car the player
	DRIVES has. A traffic shell has neither, and cannot: it is 21 parts of welded visual mesh with an
	invisible `Root`, no chassis, no seat, no constraints — that flatness is the whole reason a dozen
	of them can share a road (TrafficService's header). So the panel is turned by hand, off a plan the
	server stamped when it published the body (`TrafficService._doorPlan`), and the two modules stay
	separate because they have nothing in common but the angle.

	THE SURGERY, and every step of it is load-bearing:

	  1. THE PANEL IS WELDED TO `Root` AND MUST BE UNWELDED FIRST. Writing `.CFrame` on a welded part
	     drags the whole assembly with it and does not move the part relative to its neighbours —
	     which on a car reads as the car twitching sideways rather than as a door opening. The weld
	     is DISABLED rather than destroyed, so restoring it is one boolean and cannot mis-bind.
	  2. THE PANEL IS ANCHORED BEFORE THE WELD GOES. Un-welded and un-anchored, it is a massless free
	     body that falls out of the car on the next physics step.
	  3. IT STILL RIDES WITH THE CAR. `TrafficController._place` moves the shell with `Model:PivotTo`,
	     which transforms every part in the model — anchored ones included — so an anchored,
	     un-welded panel keeps its place in the bodywork for free while the car drives. That is
	     exactly why the rotation below is applied as a DELTA on top of wherever the part currently
	     is, never as an absolute pose: an absolute write would fight the pivot every frame. (The
	     same trap, and the same fix, as `CarDoors.poseFrozen` — where getting it wrong looked like
	     the door flickering rather than like it spinning.)
	  4. IT HAS TO BE UNWOUND BEFORE THE REDRESS. `CarBody.swapMeshes` clones these very meshes onto
	     the player's car at the handoff, and `CarDoorRig.apply` then welds them into a rig whose
	     SHUT pose is wherever it found them. Hand it a door standing open at 55° and that becomes
	     the car's closed door, permanently, for the rest of the run. `restore` is therefore not
	     tidy-up; it is a step of the steal.

	THE ANGLE'S SIGN is negated on its way to `CFrame.fromAxisAngle`, exactly as `CarDoors.poseFrozen`
	negates it, and for the same reason: the stamped hinge frame is the one `CarDoorRig` builds for a
	`HingeConstraint`, whose positive `TargetAngle` turns OPPOSITE to a right-handed rotation about
	its own primary axis. Keeping the negation is what makes a positive `StealConfig.Doors.Target.
	Angle` mean "outboard" on both mechanisms. Do not "correct" it without measuring a world-space
	outboard displacement — reaching the target angle proves nothing about which way the door went.

	A shell with no stamped plan (an old published body, or one of the three in the pack with no
	separable panel) returns nil from `rig` and every caller treats that as "this car's door does not
	open", which is a beat that reads slightly flat rather than a failure.
]]

local ShellDoors = {}

export type Door = {
	shell: Model,
	root: BasePart,
	parts: { BasePart },
	welds: { WeldConstraint },
	hinge: CFrame, -- root-relative, so it follows the car
	angle: number, -- degrees currently posed open
}

--[[ Take hold of this shell's driver door: find the panel, free it, and hand back the handle the
	caller poses and restores through.

	Returns nil for a shell the server stamped no plan onto, or one whose flagged meshes have gone
	(a body republished mid-session). Idempotent in the way that matters — it never mutates on the
	failure path, so a nil result leaves the car exactly as it found it. ]]
function ShellDoors.rig(shell: Model): Door?
	local root = shell and shell.PrimaryPart
	local hinge = shell and shell:GetAttribute("DoorHinge")
	if not (root and typeof(hinge) == "CFrame") then
		return nil
	end

	local parts, welds = {}, {}
	for _, part in shell:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("DoorPanel") then
			table.insert(parts, part)
			-- Anchor first, unweld second — step 2 in the header. Nothing steps physics between two
			-- Lua statements, so this is belt and braces rather than a live bug; it is written this
			-- way round so that reading it never raises the question.
			part.Anchored = true
			for _, weld in part:GetChildren() do
				if weld:IsA("WeldConstraint") and weld.Enabled then
					weld.Enabled = false
					table.insert(welds, weld)
				end
			end
		end
	end
	if #parts == 0 then
		return nil
	end
	return { shell = shell, root = root, parts = parts, welds = welds, hinge = hinge, angle = 0 }
end

--[[ Pose the door at an ABSOLUTE angle in degrees; the delta from wherever it is now is worked out
	here.

	Absolute at this seam and delta underneath, on purpose. The caller is easing an angle toward a
	target on a per-frame clock and should not also have to remember what it applied last frame —
	that bookkeeping is precisely what went wrong the last time this pattern was written by hand
	(`CarDoors.poseFrozen`'s header). ]]
function ShellDoors.pose(door: Door, degrees: number)
	local delta = degrees - door.angle
	if math.abs(delta) < 1e-4 or not door.root.Parent then
		return
	end
	door.angle = degrees

	-- Re-derived from the live root every call, so the hinge line follows the car down the road and
	-- through a world rebase without anything having to tell it either happened.
	local frame = door.root.CFrame * door.hinge
	local pivot = frame.Position
	local turn = CFrame.fromAxisAngle(frame.RightVector, math.rad(-delta))
	local about = CFrame.new(pivot) * turn * CFrame.new(-pivot)
	for _, part in door.parts do
		if part.Parent then
			part.CFrame = about * part.CFrame
		end
	end
end

-- Shut the door and give the panel back to the shell: welded, unanchored, and sitting exactly where
-- it was before `rig` touched it. Safe on a shell that has been torn down under us.
function ShellDoors.restore(door: Door)
	ShellDoors.pose(door, 0)
	for _, part in door.parts do
		if part.Parent then
			part.Anchored = false
		end
	end
	for _, weld in door.welds do
		if weld.Parent then
			weld.Enabled = true
		end
	end
end

return ShellDoors
