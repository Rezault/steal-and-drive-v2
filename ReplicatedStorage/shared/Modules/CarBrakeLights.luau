--[[
	CarBrakeLights  (shared, client-side in practice)
	-------------------------------------------------
	Stop lamps on a car body: the rear lamps lit red while the car is slowing, on traffic and on
	the car the player is driving alike.

	The lamps are found and their lit twins built by `Modules/CarLamps`, which `CarBlinkers` also
	stands on; that is what keeps a brake light and a turn signal on one body pointed at the same
	mesh. What is decided HERE is which of a body's lamps a stop lamp is:

	  1. Only lamps at the REAR. Which end a lamp is at comes from the frame (nose down -Z), so a
	     `light_red` side marker on the front wing stays dark.
	  2. Never a `reverse` or `white` lamp. Those are the reversing lamps on the packs that name
	     them, and a white lamp lit red reads as a bug even from a car length back.
	  3. A lamp spanning the centreline COUNTS, unlike for a blinker: a full-width tail bar is
	     exactly what a stop lamp looks like on half the modern cars in the pack. A bare `glass`
	     cover spanning the car does not, because that is the rear window, and the cover band the
	     lamp rules use was measured on one-sided glass only.
	  4. If any of what is left carries a `red` token (`light_red_NN`, `lens_red_NN`), only those.
	     Otherwise all of it, so a cluster of unnamed lamps still lights as one and reads from
	     behind, which is where the chase camera is.

	A body with nothing left has no brake light, and `build` says so with a nil that every other
	function here accepts, so a caller never has to ask which kind of car it is holding.

	THE TWIN IS NAMED `light_brake` and sits a shade less proud of its lamp than a blinker's twin
	does (`BrakeLightConfig` against `TrafficConfig.Blinkers`). On a body whose rear lamp does
	both jobs, a flashing indicator therefore shows THROUGH a lit brake light rather than under it,
	which is what a shared bulb does on a real car and which keeps the two twins from z-fighting.

	THE LAMP HOLDS. A real stop lamp is a switch on the pedal and it does not flicker, so once lit
	the twin stays lit for `hold` seconds after the last frame that asked for it. Traffic asks for
	it off a speed target that can dither by a fraction of a stud a second when it is following a
	wreck or a car that is itself following somebody, and a lamp that answered every frame would
	strobe; a held one reads as a car that touched its brakes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarLamps = require(ReplicatedStorage.shared.Modules.CarLamps)

local CarBrakeLights = {}

export type Config = {
	Enabled: boolean,
	Color: Color3,
	Grow: number,
	Proud: number,
	CoverEnd: number,
}

export type Rig = {
	twins: { BasePart },
	hold: number, -- seconds the lamp stays lit after the last frame that asked for it
	lit: boolean,
	since: number, -- the last frame that asked for it
}

CarBrakeLights.TWIN_NAME = "light_brake"

-- A rear lamp carrying one of these tokens is never a stop lamp (header, rule 2).
local NEVER_TOKENS = { reverse = true, white = true }

--[[ The lamps this body lights when it brakes, found from names and geometry alone (header).

	Pure: it reads the body and writes nothing, so it can be run over the roster to audit what a
	body will do before any of it is built. Possibly empty. ]]
function CarBrakeLights.plan(shell: Instance, root: BasePart, config: Config): { BasePart }
	local all, red = {}, {}
	for _, lamp in CarLamps.each(shell, root, config.CoverEnd) do
		if not lamp.rear then
			continue
		end
		local words = lamp.words
		local never = false
		for word in words do
			if NEVER_TOKENS[word] then
				never = true
				break
			end
		end
		if never then
			continue
		end
		if lamp.side == 0 and not (words.light or words.lens) then
			continue -- a bare glass cover across the whole car is the rear window (rule 3)
		end
		table.insert(all, lamp.part)
		if words.red then
			table.insert(red, lamp.part)
		end
	end
	return if #red > 0 then red else all
end

--[[ Build the twins for one body and hand back the rig `set` drives. Nil when the config is off
	or the body has no rear lamp.

	`shell` is whatever holds the meshes: a traffic shell (whose `Root` is `root`), or the rigged
	car's `Body` model (whose `HitBox` is). The twins are parented under `parent`, or `shell` when
	that is nil, and welded to their lamps, so they ride the car through every `PivotTo`, physics
	hand-off and pool round trip after that. On the player's car they are destroyed with the rest
	of the body by the next steal, and `CarLightsController` builds a fresh set for the new one. ]]
function CarBrakeLights.build(shell: Instance, root: BasePart, config: Config, hold: number?, parent: Instance?): Rig?
	if not (config and config.Enabled) then
		return nil
	end

	local planned = CarBrakeLights.plan(shell, root, config)
	if #planned == 0 then
		return nil
	end

	local frame = root.CFrame
	local spec = { Name = CarBrakeLights.TWIN_NAME, Color = config.Color, Grow = config.Grow, Proud = config.Proud }
	local twins = {}
	for _, lamp in planned do
		local twin = CarLamps.twin(lamp, frame, spec, parent or shell)
		if twin then
			table.insert(twins, twin)
		end
	end
	if #twins == 0 then
		return nil
	end

	return { twins = twins, hold = hold or 0, lit = false, since = 0 }
end

local function paint(rig: Rig, lit: boolean)
	for _, twin in rig.twins do
		twin.Transparency = if lit then 0 else 1
	end
end

--[[ Say whether this car is braking, every frame.

	Only a CHANGE of lit state writes anything, so calling this for every car every frame costs a
	comparison. A lamp asked off stays lit until `hold` seconds after it was last asked on (header). ]]
function CarBrakeLights.set(rig: Rig?, braking: boolean, now: number)
	if not rig then
		return
	end
	if braking then
		rig.since = now
		if not rig.lit then
			rig.lit = true
			paint(rig, true)
		end
	elseif rig.lit and now - rig.since >= rig.hold then
		rig.lit = false
		paint(rig, false)
	end
end

--- Out, now, with no hold: a car going back to the pool must not come out of it lit.
function CarBrakeLights.off(rig: Rig?)
	if rig and rig.lit then
		rig.lit = false
		paint(rig, false)
	end
end

--- The twins themselves, gone. For a rig whose body is being rebuilt under it; a pooled traffic
--- shell keeps its twins for life and never needs this.
function CarBrakeLights.destroy(rig: Rig?)
	if not rig then
		return
	end
	for _, twin in rig.twins do
		twin:Destroy()
	end
	rig.twins = {}
	rig.lit = false
end

return CarBrakeLights
