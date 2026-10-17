--[[
	CarLamps  (shared)
	------------------
	Finds the lamps on a car body, and builds the lit TWIN of one. `CarBlinkers` and
	`CarBrakeLights` both stand on this, which is the point of it: a turn signal and a brake light
	have to agree about which mesh IS the tail lamp, and the twin they draw over it has to be the
	same recipe, or one of them z-fights the other.

	THERE ARE NO LAMP MESHES TO SWITCH ON, which is why this module has to choose lamps at all.
	Surveyed over the whole roster on 2026-09-17: only 11 of 43 bodies carry a mesh named `amber`,
	some of those span both sides in one part, and a few are drawn red. What almost every body DOES
	have is a lamp per side at each end (`light_red_01` on one side, `light_red_02` on the other, and
	the same for the headlamps).

	A LAMP IS NEVER LIT BY WRITING THE LAMP. The shell's meshes are also the dress a steal grafts
	onto the player's car (`CarBody.swapMeshes`), so a lamp caught lit would be stolen lit and stay
	that way for the run. Each chosen lamp gets a TWIN instead: a clone of the same mesh in Neon,
	invisible until lit, welded to the lamp it copies. The twin carries no
	attributes, so the steal (`DressMount`) and the door (`DoorPanel`) never see it, and its name
	starts with `light_`, whose `light` token keeps `CarPaint` from sweeping it into a repaint.

	THE TWIN SITS PROUD BY A DISTANCE, NOT JUST BY A SCALE. Growing it a few percent about its own
	centre was the first version, and it works on a chunky lamp. On a thin one it does nothing: the
	GT's tail lamp mesh is 0.07 studs deep, so 4% moves its face 0.0015 studs and the original lamp
	still wins the depth test, which looks exactly like the lamp not firing. So the twin is also
	pushed `Proud` studs outward along the car, backwards for a rear lamp and forwards for a front
	one, which is the direction every lamp on the roster faces. Two twins of ONE lamp (a blinker and
	a brake light on a body with no amber part) are told apart the same way: whichever is pushed
	further out is the one you see when both are lit.

	WHAT COUNTS AS A LAMP (`each`):
	  1. Every part whose name has a `light` or `lens` token, minus `housing` and anything carrying
	     `body` (`lens_clear_01_body` is bodywork wearing a lamp's name).
	  2. ...and every `glass` part in the outer `coverEnd` of the car's length. On most of the
	     original vendor pack the part you actually SEE is not the lamp at all but an opaque red or
	     smoked cover named `glass_NN` sitting in front of it (the GT, EVO, F5 and 350Z tail lamps
	     are all this), so lighting only the lamp behind it lights nothing. Windows are glass too and
	     are why the band exists: measured over all 43 bodies, every one-sided glass part at 0.76 of
	     the half-length or beyond is a lamp cover, and the nearest window sits at 0.40.
	Each lamp comes back with its tokens, which end of the car it is at, and which side: -1 left,
	1 right, or 0 for a part that spans the centreline. The callers decide what to do with a
	spanning one (a blinker skips it, a brake light wants it).

	THE FRAME is the part whose CFrame is the car's: a shell's `Root`, whose nose faces its
	LookVector (TrafficService._buildShell), or the rigged car's `HitBox`, which looks the same way
	(NitroController mounts its jets off `Back` for exactly that reason). So left is local -X and
	the front is local -Z.
]]

local CarLamps = {}

export type Lamp = {
	part: BasePart,
	words: { [string]: boolean },
	side: number, -- -1 left, 1 right, 0 spanning the centreline
	rear: boolean,
	centre: Vector3, -- in the frame
}

export type TwinSpec = {
	Name: string,
	Color: Color3,
	Grow: number,
	Proud: number,
}

-- A part counts as a lamp if a token of its name is one of these...
local LAMP_TOKENS = { light = true, lens = true }
-- ...or as a lamp COVER if it has this one and sits far enough towards an end (header, rule 2)...
local COVER_TOKEN = "glass"
-- ...and none of its tokens is one of these. `blinker`, `brake` and `eventheadlight` are our own twins, so a second
-- build over a body that already has twins cannot twin them again.
local NOT_LAMP_TOKENS = { housing = true, body = true, blinker = true, brake = true, eventheadlight = true }
-- Studs a lamp's box may cross the centreline and still be one side's lamp. Mirrored lamps sit
-- 1.2 studs or more out, so this only forgives a box a shade wider than its mesh.
local CENTRE_MARGIN = 0.2

function CarLamps.tokens(name: string): { [string]: boolean }
	local set = {}
	for word in string.gmatch(string.lower(name), "%a+") do
		set[word] = true
	end
	return set
end

-- Extents of a part's box along the frame's X and Z, and its centre in the frame.
local function extents(frame: CFrame, part: BasePart): (number, number, number, number, Vector3)
	local lc = frame:ToObjectSpace(part.CFrame)
	local half = part.Size * 0.5
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for i = -1, 1, 2 do
		for j = -1, 1, 2 do
			for k = -1, 1, 2 do
				local corner = lc * Vector3.new(half.X * i, half.Y * j, half.Z * k)
				minX = math.min(minX, corner.X)
				maxX = math.max(maxX, corner.X)
				minZ = math.min(minZ, corner.Z)
				maxZ = math.max(maxZ, corner.Z)
			end
		end
	end
	return minX, maxX, minZ, maxZ, lc.Position
end

--[[ Half the car's length in the frame, for the cover band. The published shell stamps it
	(`BodyLength`, TrafficService); anything else (the player's rigged `Body`, an audit run
	straight over `Workspace.CarSystem`) measures its own visible parts instead, as the furthest a
	corner of any of them reaches along the frame's Z. ]]
function CarLamps.halfLength(shell: Instance, root: BasePart): number
	local stamped = shell:GetAttribute("BodyLength")
	if type(stamped) == "number" and stamped > 0 then
		return stamped * 0.5
	end
	local frame, reach = root.CFrame, 0
	for _, part in shell:GetDescendants() do
		if part:IsA("BasePart") and part ~= root and part.Transparency < 1 then
			local _, _, minZ, maxZ = extents(frame, part)
			reach = math.max(reach, -minZ, maxZ)
		end
	end
	return reach
end

--[[ Every lamp on this body, found from names and geometry alone (header).

	Pure: it reads the body and writes nothing, so it can be run over the roster to audit what a
	body will do before any of it is built. `shell` is whatever holds the meshes (a traffic shell,
	or a rigged car's `Body`), `root` the part whose CFrame is the car's frame. ]]
function CarLamps.each(shell: Instance, root: BasePart, coverEnd: number): { Lamp }
	local frame = root.CFrame
	local coverFrom = CarLamps.halfLength(shell, root) * coverEnd
	local lamps = {}

	for _, part in shell:GetDescendants() do
		if not part:IsA("BasePart") or part == root or part.Transparency >= 1 then
			continue
		end
		local words = CarLamps.tokens(part.Name)
		local lamp, cover = false, false
		for word in words do
			if NOT_LAMP_TOKENS[word] then
				lamp, cover = false, false
				break
			end
			if LAMP_TOKENS[word] then
				lamp = true
			elseif word == COVER_TOKEN then
				cover = true
			end
		end
		if not (lamp or cover) then
			continue
		end

		local minX, maxX, _, _, centre = extents(frame, part)
		if not lamp and math.abs(centre.Z) < coverFrom then
			continue -- glass this close to the middle of the car is a window
		end
		local side = if maxX < CENTRE_MARGIN then -1 elseif minX > -CENTRE_MARGIN then 1 else 0
		table.insert(lamps, {
			part = part,
			words = words,
			side = side,
			rear = centre.Z > 0,
			centre = centre,
		})
	end
	return lamps
end

--[[ Build the lit twin of one lamp: same mesh, Neon, invisible, welded to the lamp and parented
	under `parent`. Nil when the lamp cannot be cloned (Archivable off), and that lamp just does
	not light.

	WELDED TO THE LAMP, NOT TO THE FRAME PART, and that is a fix rather than a preference. A weld
	bakes the offset between its two parts at the moment it binds, and on the player's car at race
	start the `HitBox` and the body meshes replicate the car's teleport onto the road in different
	frames: twins welded to the hull on that frame were built 3.14 studs under their lamps and
	stayed there for the run. The offset between a lamp and its own twin is read off one part in
	one instant and cannot disagree with itself.

	The CFrame is written BEFORE the weld exists and while the twin is unparented, so the write
	moves the twin and nothing else. Writing a welded twin's CFrame drags the whole assembly with
	it and the offset silently never happens. ]]
function CarLamps.twin(lamp: BasePart, frame: CFrame, spec: TwinSpec, parent: Instance): BasePart?
	local twin = lamp:Clone()
	if not twin then
		return nil
	end
	twin:ClearAllChildren() -- its weld, SurfaceAppearance, plate gui: none of it belongs
	for name in twin:GetAttributes() do
		twin:SetAttribute(name, nil)
	end
	twin.Name = spec.Name
	if twin:IsA("MeshPart") then
		twin.TextureID = ""
	end
	twin.Material = Enum.Material.Neon
	twin.Color = spec.Color
	twin.Transparency = 1
	twin.Reflectance = 0
	twin.CastShadow = false
	twin.CanCollide = false
	twin.CanQuery = false
	twin.CanTouch = false
	twin.Massless = true
	twin.Anchored = false
	-- Grown about its own centre AND pushed out towards its own end of the car (header): the
	-- same mesh in the same place would z-fight the lamp, and on a thin lamp the grow alone is
	-- too small to win.
	local outward = if frame:PointToObjectSpace(lamp.Position).Z < 0 then -spec.Proud else spec.Proud
	twin.Size = lamp.Size * (1 + spec.Grow)
	twin.CFrame = frame * CFrame.new(0, 0, outward) * frame:ToObjectSpace(lamp.CFrame)
	twin.Parent = parent

	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = lamp, twin
	weld.Parent = twin
	return twin
end

return CarLamps
