--[[
	CarDoors  (shared, client-side in practice)
	------------------------------------------
	Drive a redressed car's doors through the stock CarBones hinge rig.

	WHY THIS EXISTS AS OUR OWN MODULE. The rig is stock and works, but nothing in this game ever
	triggers it. The only stock callers are the ProximityPrompt entry handler and
	`VehicleSeating.ExitSeat`, and the race flow reaches neither: RaceService seats and unseats
	the player programmatically, so `Humanoid.Sit = false` opens nothing. On top of that,
	`ExitSeat` teleports the character (`hrp.CFrame = ...` plus a `MoveTo`) — exactly the
	behaviour RaceService and StealController deliberately replace — so routing the race flow
	back through it to get a door swing would be trading a working teleport for a broken one.
	Hence: talk to the constraints directly, and leave the place-side script alone.

	THE RIG, which every body has to provide (see the door-rig memory doc). Per door, and living
	on the SEAT rather than on the door:

	  • `<Seat>.DoorHinge`      servo HingeConstraint, Attachment0 on the door's root part,
	                            Attachment1 on `Chassis.RedressMount`.
	  • `<Seat>.DoorLatchWeld`  WeldConstraint, Part0 = seat, Part1 = the door's root part.

	THE LATCH IS THE LOAD-BEARING PART and the reason `close` is asynchronous. While it is enabled
	the door is welded into the car's main assembly, so it cannot lag, swing or fling during a
	teleport or a road rebase — it is only a separate physics assembly for the ~1.5s it is open.
	Re-enabling it mid-swing would weld the door solid at whatever angle it happened to be at, so
	`close` has to wait for the hinge to actually arrive before latching. That wait is the stock
	behaviour too (`VehicleSeating` spins on `CurrentAngle` the same way); it is reproduced here
	rather than reused because the stock copy is unreachable from our code paths.

	A body with no doors rigged is a silent no-op, on purpose: `rigs` returns nothing, every entry
	point returns 0, and callers can treat "this body has no doors" and "this body has four" the
	same way. The count is returned so a caller that expected doors can warn.
]]

local RunService = game:GetService("RunService")

local CarDoors = {}

-- How long `close` will wait for a hinge to reach 0 before latching anyway. A door that never
-- arrives (the car was destroyed under us, the servo is fighting something) must not leave the
-- latch off forever — an unlatched door is a loose assembly, which is the thing the latch exists
-- to prevent.
local CLOSE_TIMEOUT = 3
--[[ Degrees below which the door counts as shut.

	DELIBERATELY LOOSER THAN THE STOCK 0.01. A servo hinge does not converge to zero, it converges
	to a steady-state error, and on this rig that error measures 0.0097° — inside the stock
	threshold by 3%. That margin is not real: a different frame rate, a heavier door or a body
	with a different hinge offset pushes it over, and then the stock loop
	(`while math.abs(CurrentAngle) > 0.01 do wait() end`, with no timeout) spins forever and the
	door NEVER re-latches. A permanently unlatched door is a loose assembly during teleports and
	road rebases, which is the exact failure the latch exists to prevent — so this is a real
	latent bug in the stock script, not a nicety.

	0.25° is still visually shut: across a ~6-stud door that is 0.026 studs of travel at the tip. ]]
local SHUT_EPSILON = 0.25

--[[ Every rigged door on `car`, discovered from the chassis rather than from a name list, so a
	two-door body and a four-door body both work without telling this module which it is.

	The `latch.Part1` test is what separates "rigged" from "the seat carries the stock constraints
	but the redress never wired them to a door" — which is exactly the state every car in this
	project was in before the Lambo, and which reads as the doors being broken rather than absent.

	IT IS NOT ENOUGH FOR `Part1` TO BE NON-NIL; the door has to still be ON THE CAR. `CarBody`
	strips the old dress by setting `Parent = nil` rather than destroying it, and Roblox only nils
	a weld's references when the part is DESTROYED — so after a redress this constraint still holds
	a live reference to an orphaned panel sitting wherever the car was when it was swapped. Without
	the descendant test that counts as a rigged door: `rigs` reports two, the bail dutifully poses
	a panel that is not in the world, and the car it is actually driving has no doors at all. It
	looks like the rig working right up until you notice nothing moves. ]]
function CarDoors.rigs(car: Model): { { hinge: HingeConstraint, latch: WeldConstraint } }
	local out = {}
	local chassis = car and car:FindFirstChild("Chassis")
	if not chassis then
		return out
	end
	for _, seat in chassis:GetChildren() do
		if seat:IsA("BasePart") then
			local hinge = seat:FindFirstChild("DoorHinge")
			local latch = seat:FindFirstChild("DoorLatchWeld")
			if
				hinge
				and hinge:IsA("HingeConstraint")
				and latch
				and latch:IsA("WeldConstraint")
				and latch.Part1
				and latch.Part1:IsDescendantOf(car)
			then
				table.insert(out, { hinge = hinge, latch = latch })
			end
		end
	end
	return out
end

--[[ The rig belonging to ONE seat, or nil if that seat has no door wired to it.

	`rigs` answers "every door on this car" and is the right question for the bail, which poses the
	whole car at once. It is the WRONG question for a door that belongs to a person: the lobby entry
	beat opens the door of the seat you are getting into, and a four-door CarBones or the Lambo's pair
	of scissor doors would otherwise all fly open because one player pressed E at one of them. The
	discriminator is the same `latch.Part1` descendant test `rigs` uses, for the same reason. ]]
function CarDoors.rigOf(car: Model, seat: BasePart): { hinge: HingeConstraint, latch: WeldConstraint }?
	local hinge = seat and seat:FindFirstChild("DoorHinge")
	local latch = seat and seat:FindFirstChild("DoorLatchWeld")
	if
		car
		and hinge
		and hinge:IsA("HingeConstraint")
		and latch
		and latch:IsA("WeldConstraint")
		and latch.Part1
		and latch.Part1:IsDescendantOf(car)
	then
		return { hinge = hinge, latch = latch }
	end
	return nil
end

--[[ Swing one door open. Unlatching first is mandatory: with the weld still enabled the servo is
	fighting a rigid joint and the door just shudders. ]]
function CarDoors.openRig(rig: { hinge: HingeConstraint, latch: WeldConstraint }, angle: number, speed: number)
	rig.latch.Enabled = false
	rig.hinge.AngularSpeed = speed
	rig.hinge.TargetAngle = angle
end

--[[ Swing one door shut and re-latch it once it has actually arrived. Asynchronous by nature (see
	the header); safe on a car being torn down, because the loop re-checks `Parent`.

	IT WILL NOT LATCH A DOOR THAT SOMEONE RE-OPENED WHILE IT WAS WAITING, and that guard is load
	bearing now that two independent systems drive the same door: our lobby entry beat closes it,
	and the stock `VehicleSeating.ExitSeat` opens it again the moment the player presses E to get
	out. Get out fast enough and the close started before the exit did, so without this test the
	timeout expires on a door that is now standing open and the weld pins it there — a door welded
	at 55° through the bodywork, which no later beat can undo because the latch holds the SHUT
	offset. Re-reading `TargetAngle` rather than tracking a flag keeps it honest whoever re-opened
	it and however they did it. ]]
function CarDoors.closeRig(rig: { hinge: HingeConstraint, latch: WeldConstraint }, speed: number)
	rig.hinge.AngularSpeed = speed
	rig.hinge.TargetAngle = 0
	task.spawn(function()
		local deadline = os.clock() + CLOSE_TIMEOUT
		while rig.hinge.Parent and math.abs(rig.hinge.CurrentAngle) > SHUT_EPSILON and os.clock() < deadline do
			RunService.Heartbeat:Wait()
		end
		if rig.latch.Parent and rig.hinge.TargetAngle == 0 and math.abs(rig.hinge.CurrentAngle) <= SHUT_EPSILON then
			rig.latch.Enabled = true
		end
	end)
end

--[[ Swing every door open. Returns how many moved, so "this car has no doors" is distinguishable
	from "the door code ran". ]]
function CarDoors.open(car: Model, angle: number, speed: number): number
	local n = 0
	for _, rig in CarDoors.rigs(car) do
		CarDoors.openRig(rig, angle, speed)
		n += 1
	end
	return n
end

-- Swing them all shut and re-latch each once it has arrived. See `closeRig`.
function CarDoors.close(car: Model, speed: number): number
	local rigs = CarDoors.rigs(car)
	for _, rig in rigs do
		CarDoors.closeRig(rig, speed)
	end
	return #rigs
end

--[[ Turn the doors by CFrame instead of by the servo, for a car that is ANCHORED.

	WHY THIS IS SEPARATE FROM `open`. During a bail the whole car is anchored and repositioned by
	CFrame every frame (StealController._flyCar) — writing a CFrame on a live unanchored assembly
	makes the engine synthesise a reconciliation velocity and fling it, which is a documented bug in
	this codebase. An anchored door is a door the servo cannot move: `TargetAngle` would sit there
	doing nothing and the door would simply appear open on the next frame. So while the car is frozen
	the door is animated the same way the car is — geometrically, with no physics involved.

	`degrees` IS A DELTA, not an absolute angle — there is no cheap absolute reference to measure
	against once the door has been turned, so the caller tracks the total and passes the difference.

	DO NOT ASSUME THE `car:PivotTo` THAT PRECEDES THIS RE-ESTABLISHES THE SHUT POSE. It does not.
	`PivotTo` is a rigid transform of the whole model, so it carries the door's current open offset
	along with the car rather than flattening it. Passing the absolute angle every frame therefore
	adds that angle AGAIN every frame: the door accelerates to hundreds of degrees a second and laps
	itself between frames, which reads on screen as the door flickering rather than as a spin. (Shipped
	that way once — it is not an obvious failure to look at, so it is worth knowing the shape of it.)

	Unwind by the negation of the tracked total when handing the car back to physics, which is what
	`StealController._unanchorCar` does.

	The pivot is taken from `Attachment1` — the one bolted to the BODY. `Attachment0` rides the door
	and would move as it turned, so each frame's rotation would compound off the last one.

	THE ANGLE IS NEGATED, and that is not a fudge — `HingeConstraint`'s positive `TargetAngle` turns
	OPPOSITE to a right-handed rotation about the attachment's own stated primary axis. So the
	right-hand-rule reading of the axis that `CFrame.fromAxisAngle` implements runs backwards from
	the servo, and a `degrees` that means "open" to `CarDoors.open` would mean "shut into the road"
	here. Measured both ways on this rig rather than reasoned about; do not "correct" this without
	re-measuring, and measure it as a world-space height change, because angle magnitude alone is
	blind to which way the door went. ]]
function CarDoors.poseFrozen(car: Model, degrees: number): number
	if degrees == 0 then
		return 0 -- a no-op rotation, and `PivotTo` on 50-odd parts is not free
	end
	local n = 0
	for _, rig in CarDoors.rigs(car) do
		local anchorAtt = rig.hinge.Attachment1
		local door = rig.latch.Part1 and rig.latch.Part1.Parent
		if anchorAtt and door and door:IsA("Model") then
			local pivot = anchorAtt.WorldPosition
			local turn = CFrame.fromAxisAngle(anchorAtt.WorldCFrame.RightVector, math.rad(-degrees))
			door:PivotTo(CFrame.new(pivot) * turn * CFrame.new(-pivot) * door:GetPivot())
			n += 1
		end
	end
	return n
end

--[[ The whole beat in one call: throw the doors open, hold, swing them shut.

	Kept for a caller that wants the self-contained open-hold-shut on a LIVE car. The steal no longer
	uses it — the door is opened at the bail and shut on the way into the new car, which is a beat
	spread across the whole flight rather than one call (see StealConfig.Doors).

	Non-blocking: it returns as soon as the doors are moving. ]]
function CarDoors.flourish(car: Model, opts: { Angle: number, OpenSpeed: number, CloseSpeed: number, Hold: number }): number
	local opened = CarDoors.open(car, opts.Angle, opts.OpenSpeed)
	if opened == 0 then
		return 0
	end
	task.delay(opts.Hold, function()
		if car.Parent then
			CarDoors.close(car, opts.CloseSpeed)
		end
	end)
	return opened
end

return CarDoors
