--[[
	CarBlinkers  (shared, client-side in practice)
	----------------------------------------------
	Turn signals on a traffic shell, lit on the car's OWN lamp meshes.

	Which parts are lamps, why a lamp is never lit by writing the lamp, and how the lit twin of one
	is built and kept in front of it, all live in `Modules/CarLamps`; `CarBrakeLights` stands on the
	same module, so a blinker and a brake light on one body always agree about which mesh is the
	tail lamp. What is decided HERE is which of those lamps a turn signal is:

	  1. Only a lamp lying wholly on one side of the centreline. A tail bar spanning the car cannot
	     tell left from right, and flashing it would read as hazards, so it is skipped. The bodies
	     where that left no rear lamp at all had their bars split in two (`SplitLampMeshes`).
	  2. Per corner (front or rear, left or right): if any of that corner's lamps is `amber`, only
	     those. Otherwise all of them, so a cluster lights as one lamp and still reads from several
	     car lengths back.

	A corner with nothing left has no blinker, and the arrow over the car still covers it.

	The twin is named `light_blinker` and pushed `Proud` studs out from its lamp, which is further
	than the brake light's twin (`BrakeLightConfig`), so on a body whose only rear lamp does both
	jobs the flash shows through the brake light, the way a shared bulb does on a real car.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarLamps = require(ReplicatedStorage.shared.Modules.CarLamps)

local CarBlinkers = {}

export type Config = {
	Enabled: boolean,
	Hz: number,
	Color: Color3,
	Grow: number,
	Proud: number,
	CoverEnd: number,
}

export type Rig = {
	sides: { [number]: { BasePart } }, -- -1 left, 1 right
	config: Config,
	side: number, -- the side signalling now, 0 for none
	since: number, -- when that signal began, so every signal opens on a flash
	lit: boolean,
}

CarBlinkers.TWIN_NAME = "light_blinker"

--[[ The lamps that blink on each side of this shell, found from names and geometry alone.

	Pure: it reads the shell and writes nothing, so it can be run over the roster to audit what a
	body will do before any of it is built. Returns `{ [-1] = {...}, [1] = {...} }`, either list
	possibly empty. ]]
function CarBlinkers.plan(shell: Model, root: BasePart, config: Config): { [number]: { BasePart } }
	-- corners[side][isFront] = { all = {...}, amber = {...} }
	local corners = {
		[-1] = { [true] = { all = {}, amber = {} }, [false] = { all = {}, amber = {} } },
		[1] = { [true] = { all = {}, amber = {} }, [false] = { all = {}, amber = {} } },
	}

	for _, lamp in CarLamps.each(shell, root, config.CoverEnd) do
		if lamp.side == 0 then
			continue
		end
		local corner = corners[lamp.side][lamp.centre.Z < 0]
		table.insert(corner.all, lamp.part)
		if lamp.words.amber then
			table.insert(corner.amber, lamp.part)
		end
	end

	local sides = { [-1] = {}, [1] = {} }
	for side, ends in corners do
		for _, corner in ends do
			for _, part in if #corner.amber > 0 then corner.amber else corner.all do
				table.insert(sides[side], part)
			end
		end
	end
	return sides
end

--[[ Build the twins for one shell and hand back the rig `signal` drives. Nil when the config is
	off or the body has no one-sided lamp anywhere, and `signal` accepts that nil, so a caller
	never has to ask which kind of car it is holding.

	Run it on a pooled shell ONCE. The twins are welded to their lamps and ride the car through every
	`PivotTo`, physics hand-off and pool round trip after that. ]]
function CarBlinkers.build(shell: Model, root: BasePart, config: Config): Rig?
	if not (config and config.Enabled) then
		return nil
	end

	local planned = CarBlinkers.plan(shell, root, config)
	if #planned[-1] == 0 and #planned[1] == 0 then
		return nil
	end

	local frame = root.CFrame
	local spec = { Name = CarBlinkers.TWIN_NAME, Color = config.Color, Grow = config.Grow, Proud = config.Proud }
	local sides = { [-1] = {}, [1] = {} }
	for side, lamps in planned do
		for _, lamp in lamps do
			local twin = CarLamps.twin(lamp, frame, spec, shell)
			if twin then
				table.insert(sides[side], twin)
			end
		end
	end

	return { sides = sides, config = config, side = 0, since = 0, lit = false }
end

local function paint(rig: Rig, side: number, lit: boolean)
	for _, twin in rig.sides[side] do
		twin.Transparency = if lit then 0 else 1
	end
end

--[[ Say which way this car is turning, every frame: -1 left, 1 right, 0 not at all.

	The flash clock belongs to the signal, not to the wall clock, so every signal opens lit rather
	than on whichever half of a shared cycle it happened to start in. Only a CHANGE of lit state
	writes anything, so calling this for every car every frame costs a comparison. ]]
function CarBlinkers.signal(rig: Rig?, side: number, now: number)
	if not rig then
		return
	end
	if side ~= rig.side then
		if rig.lit and rig.side ~= 0 then
			paint(rig, rig.side, false)
		end
		rig.side, rig.since, rig.lit = side, now, false
	end
	if side == 0 then
		return
	end
	local lit = math.floor((now - rig.since) * rig.config.Hz * 2) % 2 == 0
	if lit ~= rig.lit then
		paint(rig, side, lit)
		rig.lit = lit
	end
end

--- The twins themselves, gone. For a rig whose body is being rebuilt under it (the player's car,
--- `CarLightsController`); a pooled traffic shell keeps its twins for life and never needs this.
function CarBlinkers.destroy(rig: Rig?)
	if not rig then
		return
	end
	for _, twins in rig.sides do
		for _, twin in twins do
			twin:Destroy()
		end
	end
	rig.sides = { [-1] = {}, [1] = {} }
	rig.side, rig.lit = 0, false
end

return CarBlinkers
