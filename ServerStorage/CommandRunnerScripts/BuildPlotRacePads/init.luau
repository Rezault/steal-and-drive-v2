--[[
	BuildPlotRacePads — Command Runner command

	Authors one "ENTER RACE" pad on the forecourt of every dealership plot, tagged so `RaceService`
	picks it up with no code change at all.

	THE TAG IS THE WHOLE INTEGRATION. `RaceService.start` runs `Observers.observeTag(RaceConfig.
	EnterRaceTag, ...)` over Workspace, so a part carrying that tag *is* an entry trigger — it gets
	the Touched handler, the forgiving walk-near zone, and the ProximityPrompt binding for free.
	This command builds geometry and stamps a tag; it does not know what a race is.

	WHY ONE PER PLOT. There was exactly one trigger in the place, `workspace.EnterRacePart`, a 4x1x2
	grey slab at world (14, 0.5, -17.5) — near the origin, about 2,000 studs from the map. It was the
	pad the driving loop was built against and nothing ever moved it onto the island, so with plot
	spawning live there was no reachable way into a race from where players actually stand. Six pads,
	one per lot, is also the right shape for the game: your lot is where your cars are, and the road
	is the thing you leave it for.

	WHERE IT GOES, AND WHY NOT CLOSER TO THE SPAWN. `LocalZ` is -52: out on the forecourt on the
	PLAZA side of the spawn pad, which sits at local (0, ~1.9, -30). That gap is not cosmetic —
	`RaceService._bindEntryTrigger` wraps every trigger in an invisible `EnterTouchZone` of
	`part.Size + (6, 6, 6)`, so a 12-stud pad claims an 18-stud footprint for touch purposes. Put it
	within ~9 studs of the spawn and every respawn drops the player straight into a new race. 22
	studs of clearance is comfortably outside that, and it puts the pad between the two flanking
	planters, where it reads as the way out.

	It also faces the right way round for the trip a player actually makes. You spawn looking INTO
	your showroom (`PlotConfig.Fallback.FaceShowroom`), so your cars are in front of you and the road
	is behind you — turn around and the pad is there. Nothing on the route to your own bays crosses
	it.

	THE GROUND IS RAYCAST, NEVER ASSUMED — same rule as `PlotService._resolveSpawn` and for the same
	reason: the forecourt slab's height is derived from the floor mesh everywhere else in this map,
	and a hardcoded Y is the one number that silently breaks if the deck ever moves. The cast starts
	at plot-local Y 8, which is under the roof (~28) and over the slab (~1.4).

	IDEMPOTENT. An existing pad is rebuilt in place rather than duplicated, because plots get
	re-imported and copied around during map work and a half-updated pad is worse than none.
]]

local CollectionService = game:GetService("CollectionService")

local Types = require(script.Types)

-- === The map contract =======================================================

local PLOTS_PATH = { "Map", "Plots" }

-- Must match `RaceConfig.EnterRaceTag`. The in-world part is *named* EnterRacePart even though the
-- tag has no space — that predates this command; the tag is what matters.
local ENTER_RACE_TAG = "EnterRace"

local PAD_MODEL_NAME = "EnterRacePad" -- the container, so the whole thing deletes in one click
local PAD_PART_NAME = "EnterRacePart" -- the tagged trigger itself

-- === Geometry ===============================================================

-- Studs of pad above the forecourt slab. Deliberately near-flush: the pad is walked over, not
-- stepped onto, and a lip you can trip on beside your own spawn is a nuisance every single life.
local PAD_LIP = 0.15
local PAD_THICKNESS = 0.8

-- === Look ===================================================================
-- The `car ui.psd` kit, same values BuildDealershipSigns uses: #0066FF on #364157, Ubuntu Bold.
-- Anything new on a plot should match those two signs without thinking about it.

local COLOR_FRAME = Color3.fromRGB(21, 29, 45) -- the outline colour the driving HUD art uses
local COLOR_ACCENT = Color3.fromRGB(0, 102, 255) -- #0066FF
local COLOR_PANEL = Color3.fromRGB(54, 65, 87) -- #364157
local COLOR_TEXT = Color3.new(1, 1, 1)
local COLOR_TEXT_STROKE = Color3.fromRGB(10, 20, 32)

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

-- 60 px per stud, matching the dealership sign, so text on the pad and text on the sign above it are
-- the same physical size. Every offset below is in those pixels — fixed canvas, no scale maths.
local PIXELS_PER_STUD = 60

-- === Building ===============================================================

local function clearChildren(instance: Instance)
	for _, child in ipairs(instance:GetChildren()) do
		child:Destroy()
	end
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
	return c
end

--[[ Paint the pad's top face.

	A SurfaceGui rather than a second Part for the blue inlay, for one practical reason: the pad is
	the TRIGGER, and a part sitting on top of it is a part the player stands on instead — so
	`Touched` would only ever fire on the inlay, and the tagged part underneath would never see a
	foot. One part, one canvas, no stacking. ]]
local function buildFace(part: BasePart)
	local existing = part:FindFirstChild("Face")
	local gui = if existing and existing:IsA("SurfaceGui") then existing else Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.ZOffset = 0
	clearChildren(gui)
	gui.Parent = part

	-- The blue inlay, inset so the part's own dark edge reads as the frame around it.
	local inlay = Instance.new("Frame")
	inlay.Name = "Inlay"
	inlay.AnchorPoint = Vector2.new(0.5, 0.5)
	inlay.Position = UDim2.fromScale(0.5, 0.5)
	inlay.Size = UDim2.fromScale(0.88, 0.88)
	inlay.BackgroundColor3 = COLOR_ACCENT
	inlay.BorderSizePixel = 0
	inlay.Parent = gui
	corner(inlay, UDim.new(0.12, 0))

	--[[ A darker plate under the wording. Pure white on #0066FF is legible but flat; the kit always
		sits text on the navy panel colour, and it is what makes the pad read as the same family as
		the sign on the beam eight studs behind it. ]]
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.fromScale(0.86, 0.34)
	plate.BackgroundColor3 = COLOR_PANEL
	plate.BorderSizePixel = 0
	plate.Parent = inlay
	corner(plate, UDim.new(0.24, 0))

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(0.9, 0.72)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.FontFace = FONT
	title.Text = "ENTER RACE"
	title.TextColor3 = COLOR_TEXT
	title.TextScaled = true
	title.Parent = plate

	local textStroke = Instance.new("UIStroke")
	textStroke.Color = COLOR_TEXT_STROKE
	textStroke.Thickness = 3
	textStroke.Parent = title

	--[[ Two chevrons pointing at the road, one above the plate and one below.

		They are the only thing on the pad that says which way it is *for*. A ground label reads from
		one side only, and a player arriving from the plaza rather than from their own showroom would
		otherwise meet it upside down with nothing else to go on. ]]
	for _, row in { { "ChevronOut", 0.14, "▼" }, { "ChevronIn", 0.86, "▲" } } do
		local chevron = Instance.new("TextLabel")
		chevron.Name = row[1]
		chevron.BackgroundTransparency = 1
		chevron.AnchorPoint = Vector2.new(0.5, 0.5)
		chevron.Position = UDim2.fromScale(0.5, row[2])
		chevron.Size = UDim2.fromScale(0.5, 0.16)
		chevron.FontFace = FONT
		chevron.Text = row[3]
		chevron.TextColor3 = COLOR_TEXT
		chevron.TextTransparency = 0.35
		chevron.TextScaled = true
		chevron.Parent = inlay
	end
end

-- The press-E half. `RaceService._bindEntryTrigger` finds any ProximityPrompt under the tagged part
-- and binds it, and rewrites a blank ActionText — so this only has to exist and be reachable.
local function buildPrompt(part: BasePart)
	local existing = part:FindFirstChildOfClass("ProximityPrompt")
	local prompt = existing or Instance.new("ProximityPrompt")
	prompt.Name = "EnterPrompt"
	prompt.ActionText = "Enter Race"
	prompt.ObjectText = "The Road"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	--[[ Line of sight off, distance generous. The prompt is measured from the CHARACTER to the pad,
		and the pad is on the floor — walk up to it and your own feet are between your head and it
		often enough to matter. Touch already covers standing ON it; this is for standing NEAR it. ]]
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 16
	prompt.Parent = part
	return prompt
end

--[[ Build (or rebuild) the pad on one plot. Returns the tagged trigger part.

	Everything is derived from the plot's own `Origin` — the frame `docs/MapLayout.md` §3.3 defines —
	so the six pads are identical by construction rather than by six hand placements that drift. ]]
local function buildPad(plot: Model, localZ: number, size: number): BasePart?
	local origin = plot.PrimaryPart
	if not origin then
		return nil
	end

	--[[ Find the forecourt surface under the pad's spot. Filtered to this plot so a neighbour's
		geometry, or a stray part parked on the plaza, cannot set the height of somebody's pad. ]]
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { plot:FindFirstChild("Building") or plot }

	local from = origin.CFrame * Vector3.new(0, 8, localZ)
	local hit = workspace:Raycast(from, -origin.CFrame.UpVector * 24, params)
	local groundY = if hit then (origin.CFrame:Inverse() * hit.Position).Y else 1.437

	local model = plot:FindFirstChild(PAD_MODEL_NAME)
	if not (model and model:IsA("Model")) then
		if model then
			model:Destroy()
		end
		model = Instance.new("Model")
		model.Name = PAD_MODEL_NAME
		model.Parent = plot
	end

	local part = model:FindFirstChild(PAD_PART_NAME)
	if not (part and part:IsA("BasePart")) then
		if part then
			part:Destroy()
		end
		part = Instance.new("Part")
		part.Name = PAD_PART_NAME
		part.Parent = model
	end

	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = true
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = COLOR_FRAME
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(size, PAD_THICKNESS, size)

	--[[ Sunk so the top sits `PAD_LIP` proud of the slab, then yawed a quarter turn.

		THE QUARTER TURN IS FOR THE LABEL, NOT THE TRIGGER, and it was measured rather than reasoned
		out. A Top-face SurfaceGui lays its canvas +X along the part's LOOK vector, not its right —
		so a pad left square with the plot renders "ENTER RACE" running bottom-to-top, ninety degrees
		out. Yawing -90° puts the pad's LookVector down plot-local +X, which is the right hand of a
		player walking out of their own showroom toward the plaza, and the wording reads flat. ]]
	part.CFrame = origin.CFrame
		* CFrame.new(0, groundY + PAD_LIP - PAD_THICKNESS / 2, localZ)
		* CFrame.Angles(0, -math.pi / 2, 0)

	buildFace(part)
	buildPrompt(part)

	model.PrimaryPart = part
	CollectionService:AddTag(part, ENTER_RACE_TAG)

	-- Breadcrumbs, so the next person can see what this was placed against without re-deriving it.
	part:SetAttribute("PlotLocalZ", localZ)
	part:SetAttribute("BuiltBy", "BuildPlotRacePads")

	return part
end

return {
	Description = "Builds a tagged ENTER RACE pad on the forecourt of every dealership plot.",
	Tags = { "map", "plots", "race" },
	AutoRecordChanges = true,

	Arguments = {
		LocalZ = {
			Type = "number",
			Default = -52,
			Description = "Plot-local Z for the pad. Negative is out toward the plaza; the spawn pad is at -30.",
			LayoutOrder = 1,
		},
		Size = {
			Type = "number",
			Default = 12,
			Description = "Pad width/depth in studs. RaceService adds a +6 stud touch halo on top of this.",
			LayoutOrder = 2,
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local folder: Instance = workspace
		for _, name in ipairs(PLOTS_PATH) do
			local nextFolder = folder:FindFirstChild(name)
			if not nextFolder then
				out:error(string.format("No workspace.%s — nothing to build on.", table.concat(PLOTS_PATH, ".")))
				return
			end
			folder = nextFolder
		end

		local localZ = if type(arguments.LocalZ) == "number" then arguments.LocalZ else -52
		local size = if type(arguments.Size) == "number" and arguments.Size > 0 then arguments.Size else 12

		--[[ Loud rather than clever. The touch halo is what makes a pad near the spawn unusable, and
			the symptom (a race starts every time you respawn, forever) is a long way from the cause. ]]
		if math.abs(localZ - (-30)) < (size + 6) / 2 + 5 then
			out:warn(
				string.format(
					"LocalZ %.0f is within the +6 stud touch halo of the spawn pad at -30 — players will re-enter a race on every respawn.",
					localZ
				)
			)
		end

		local built, missing = {}, {}
		for _, plot in ipairs(folder:GetChildren()) do
			if not plot:IsA("Model") then
				continue
			end
			local part = buildPad(plot, localZ, size)
			if part then
				table.insert(built, part)
			else
				table.insert(missing, plot.Name)
			end
		end

		if #built == 0 then
			out:error("Found no plot with a PrimaryPart — nothing to place a pad against.")
			return
		end

		pcall(function()
			props:SetSelection(built)
			props:FocusView(built)
		end)

		if #missing > 0 then
			out:warn(string.format("No PrimaryPart on: %s — those plots have no pad.", table.concat(missing, ", ")))
		end
		out:print(
			string.format(
				"Built %d race pad(s) at plot-local Z %.0f, %d studs square. RaceService binds them by the '%s' tag.",
				#built,
				localZ,
				size,
				ENTER_RACE_TAG
			)
		)
	end,
} :: Types.ScriptModule
