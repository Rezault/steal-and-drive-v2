--[[
	ShowcaseController  (client)
	----------------------------
	THE NEW BEST CUTSCENE. `ShowcaseService` says a car beat the player's record; this builds a stage
	far above the map, stands a clone of the player's avatar beside the car, sets it dancing and
	sweeps the camera round the pair under NEW BEST!, then puts everything back exactly as it was.
	`ShowcaseConfig` has what "best" means and every number used here.

	FOUR THINGS TO KNOW BEFORE TOUCHING THIS.

	  1. EVERYTHING IT CHANGES IT PUTS BACK, AND ONLY WHAT IT CHANGED. The lens is put back
	     (`play` says to which value); the camera's type is never changed (note 2). The HUD is swept the way
	     `InterfaceController` sweeps it — every ScreenGui that was ON is switched off and remembered —
	     and the restore switches back on only those, so a modal that was closed stays closed. It does
	     NOT go through `InterfaceController.setVisibility`, because that raises the SHOW UI chip in
	     the topbar and would leave the player's own hide setting disagreeing with the screen.
	  2. A RUN STARTING ENDS IT, instantly (`RaceStart`), and the camera's TYPE is never touched at all
	     — `play` has why: it runs at the end of a run, where `RaceCameraController` is handing its
	     own camera back.
	  3. THE CAR IS A PUBLISHED SHELL (`ReplicatedStorage.TrafficCars`), not the roster master:
	     StreamingEnabled keeps `Workspace.CarSystem` off the client — `CarViewport` header note 1. It
	     is painted, plated and weathered with the same three modules the road uses, so the car on the
	     stage is the car you stole.
	  4. THE AVATAR IS A CLONE with its root anchored. The humanoid still animates (Motor6Ds animate an
	     anchored assembly), and nothing on the stage has physics to fall through.

		THE REVEAL (2026-10-02, `ShowcaseConfig.Reveal`) runs on its own thread beside the wait for the
	click, never in the way of it — a run starting mid-reveal must still end the stage at once — and
	every step of it checks whether the stage has already ended before touching anything.

	THE GARAGE (2026-10-02, `ShowcaseConfig.Stage.Room`) replaces the round room: built by
	`Modules/ShowcaseGarage` once the car has been measured, its neon in the car's rarity colour, dark
	through the reveal's hold and switched on at the hit from the car outward. Its floor shows a
	reflection, so the car and the avatar each get an upside-down twin under it (the car's goes in at
	the hit). `"Round"` is the old room, untouched.

	WHAT IS KNOWINGLY LEFT: proximity prompts round the real character still take E while the stage is
	up, because the skip keys below deliberately leave E alone. Switching `ProximityPromptService` off
	here would be one more writer to the flag the bay-prompt bug is being chased through.
]]

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local ShowcaseConfig = require(ReplicatedStorage.shared.Configs.ShowcaseConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
--- The handback after a run (`play`'s release, `CameraConfig.Landing`).
local CameraFacing = require(ReplicatedStorage.shared.Modules.CameraFacing)
local CarMutation = require(ReplicatedStorage.shared.Modules.CarMutation)
local CarPaint = require(ReplicatedStorage.shared.Modules.CarPaint)
local CarPlate = require(ReplicatedStorage.shared.Modules.CarPlate)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local ShowcaseGarage = require(ReplicatedStorage.shared.Modules.ShowcaseGarage)
--- The reveal's paper, shared with the tutorial's finish card.
local ScreenConfetti = require(ReplicatedStorage.shared.Modules.ScreenConfetti)

local ShowcaseController = Shard.new("ShowcaseController")

--- Above every screen in the game (the random-car reveal is 998), so the stage's own words are
--- never under a toast that switched itself on. An implementation detail, not a tuning knob.
local DISPLAY_ORDER = 1100
local GUI_NAME = "ShowcaseCutscene"
local SKIP_ACTION = "ShowcaseSkip"
--[[ TWO past the camera module's own step: `RaceCameraController` sits at one past it, and on a
	timeout play (the results never lifted) it may still be bound, so the stage's CFrame is written
	after both to be the last word each frame. ]]
local CAMERA_PRIORITY = Enum.RenderPriority.Camera.Value + 2
local CAMERA_STEP = "ShowcaseCamera"

export type Car = {
	body: string,
	paint: number?,
	mutation: string?,
	value: number,
}

--- What the reveal (`_runReveal`) needs of the stage `play` built.
type Rig = {
	stage: Model,
	car: Model?,
	landed: CFrame?, -- the car's resting pivot; it starts `depth` below it, under the floor
	depth: number,
	carAt: Vector3,
	key: SpotLight,
	fill: PointLight,
	flames: ParticleEmitter,
	beam: Part,
	beamSize: Vector3, -- the beam's full-grown size and CFrame, tweened to over the hold
	beamCFrame: CFrame,
	charge: ParticleEmitter,
	burst: ParticleEmitter,
	restore: (() -> ())?, -- `"Silhouette"`: puts the car's real looks back, at the hit
	rays: Model?, -- the sunburst, or nil when `Reveal.Rays` is off
	raysHub: CFrame?, -- its unspun pivot; the camera step turns it
	band: number, -- the car's `CarRarity` band; picks the hit's sound
	room: ShowcaseGarage.Room?, -- the garage (`Stage.Room`), held dark until the hit
	carTwin: Model?, -- the car's reflection in the garage floor, put in at the hit
	flamesOn: boolean, -- whether the hit lights the flames (the garage has none, `Garage.Flames`)
	waveColor: Color3, -- the floor wave's colour: the garage's rarity colour, else `Reveal.Wave`'s
}

-- === Building the stage =========================================================

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

--[[ The round room, centred on `origin`: floor, glowing rim, a ring of wall panels with glowing
	bands, and a lid. Returns the model and the floor's top-centre, which everything else is placed
	from. ]]
local function buildStage(origin: Vector3): (Model, Vector3)
	local stage = ShowcaseConfig.Stage
	local model = Instance.new("Model")
	model.Name = "ShowcaseStage"
	local floorTop = origin + Vector3.new(0, 0.5, 0)

	-- A cylinder part's round faces are on its X axis, hence the roll.
	local flat = CFrame.Angles(0, 0, math.rad(90))
	part(model, {
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, stage.FloorRadius * 2, stage.FloorRadius * 2),
		CFrame = CFrame.new(origin) * flat,
		Color = stage.FloorColor,
		Material = Enum.Material.SmoothPlastic,
	})
	part(model, {
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.9, stage.FloorRadius * 2 + 1.2, stage.FloorRadius * 2 + 1.2),
		CFrame = CFrame.new(origin - Vector3.new(0, 0.1, 0)) * flat,
		Color = stage.GlowColor,
		Material = Enum.Material.Neon,
	})
	part(model, {
		Name = "Lid",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, stage.WallRadius * 2 + 4, stage.WallRadius * 2 + 4),
		CFrame = CFrame.new(origin + Vector3.new(0, stage.WallHeight, 0)) * flat,
		Color = stage.WallColor,
		Material = Enum.Material.SmoothPlastic,
	})
	part(model, {
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, stage.WallRadius * 2 + 4, stage.WallRadius * 2 + 4),
		CFrame = CFrame.new(origin - Vector3.new(0, 1, 0)) * flat,
		Color = stage.WallColor,
		Material = Enum.Material.SmoothPlastic,
	})

	--[[ Panel width is the chord of one segment plus a little, so neighbours overlap rather than
		leave a slit of sky: chord = 2 · r · sin(π / n). ]]
	local count = stage.WallSegments
	local width = 2 * stage.WallRadius * math.sin(math.pi / count) + 0.6
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local at = origin + Vector3.new(math.cos(angle) * stage.WallRadius, stage.WallHeight / 2, math.sin(angle) * stage.WallRadius)
		local facing = CFrame.lookAt(at, Vector3.new(origin.X, at.Y, origin.Z))
		part(model, {
			Name = "Wall",
			Size = Vector3.new(width, stage.WallHeight, 1),
			CFrame = facing,
			Color = stage.WallColor,
			Material = Enum.Material.SmoothPlastic,
		})
		for _, height in stage.BandHeights do
			part(model, {
				Name = "Band",
				Size = Vector3.new(width, 0.5, 0.2),
				CFrame = facing * CFrame.new(0, height - stage.WallHeight / 2, -0.6),
				Color = stage.GlowColor,
				Material = Enum.Material.Neon,
			})
		end
	end

	model.Parent = Workspace
	return model, floorTop
end

--[[ The car, standing on `at` with its nose along `facing`. nil when the body has no published shell,
	which `CarViewport.has` documents as a car no player can own — the stage then shows the avatar
	alone rather than failing. ]]
local function buildCar(parent: Instance, car: Car, at: Vector3, facing: Vector3): Model?
	local folder = ReplicatedStorage:FindFirstChild(TrafficConfig.TemplateFolderName)
	local template = folder and folder:FindFirstChild(car.body)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local clone = template:Clone()
	clone.Name = "ShowcaseCar"
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	CarPaint.apply(clone, car.paint, car.body)
	CarPlate.apply(clone, car.body, car.paint)
	--[[ The shell's `Root` is its pivot dropped to the ground with the nose down LookVector
		(`TrafficService._buildShell`), so pivoting it onto the floor facing `facing` is the whole
		placement. `lookAt` points LookVector at the target, which is the nose. ]]
	clone:PivotTo(CFrame.lookAt(at, at + facing))
	clone.Parent = parent
	-- After parenting: the weather's particles and lights are built against a model in the world.
	CarMutation.apply(clone, car.mutation, false)
	return clone
end

--[[ A clone of the local character standing at `at`, facing `toward`, dancing. nil with no character
	(dead, or between spawns) — the stage then shows the car alone. With `mirrorY` (the garage floor's
	height) it also gets its reflection under that floor (`ShowcaseGarage.reflect`), doing the same
	dance from the same frame. ]]
local function buildAvatar(parent: Instance, at: Vector3, toward: Vector3, mirrorY: number?): Model?
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid) then
		return nil
	end

	-- Characters are not Archivable, and a non-Archivable model clones to nil.
	local was = character.Archivable
	character.Archivable = true
	local clone = character:Clone()
	character.Archivable = was
	if not clone then
		return nil
	end
	clone.Name = "ShowcaseAvatar"

	--[[ The dance, read off the avatar's own `Animate` BEFORE its scripts are stripped: that script's
		children are where the player's emote pack keeps them. ]]
	local dances = {}
	local animate = clone:FindFirstChild("Animate")
	for _, name in ShowcaseConfig.Dance.AnimateFolders do
		local folder = animate and animate:FindFirstChild(name)
		local animation = folder and folder:FindFirstChildOfClass("Animation")
		if animation and animation.AnimationId ~= "" then
			table.insert(dances, animation.AnimationId)
		end
	end
	--[[ THE FACE'S OWN EXPRESSION (2026-10-15, "my face looks weird" off the group reward stand). A
		dynamic head's resting face is an animation too, `Animate`'s "mood", and stripping the script
		left the head in its blank default pose, which reads as a stare. Read here with the dances and
		played under them at Core priority, so the dance still owns the body and the face keeps the
		player's own look. An avatar without one (a classic face decal) plays nothing. ]]
	local moodFolder = animate and animate:FindFirstChild("mood")
	local moodAnimation = moodFolder and moodFolder:FindFirstChildOfClass("Animation")
	local moodId = if moodAnimation and moodAnimation.AnimationId ~= "" then moodAnimation.AnimationId else nil

	for _, descendant in clone:GetDescendants() do
		--[[ Scripts, the held car (a Tool, `CarryService`) and a spawn forcefield are not the avatar;
			a script left in would also start running the moment the clone is parented. ]]
		if descendant:IsA("BaseScript") or descendant:IsA("Tool") or descendant:IsA("ForceField") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end

	local cloneHumanoid = clone:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (cloneHumanoid and root) then
		clone:Destroy()
		return nil
	end
	cloneHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	--[[ STANDING, NOT SEATED (2026-10-14, a tester: "he did not take over the victory dance"). The
		clone is taken off a character still sitting in the run's car on the truck, so it came with
		`Sit` set and posed seated, and the seated pose beat the dance. Cleared here, and the dance
		below plays at the top priority, so nothing the copy brought with it can outrank it. ]]
	cloneHumanoid.Sit = false
	root.Anchored = true

	--[[ Feet on the floor: the root's centre sits (legs + half the root) above it. An R15's legs are
		its `HipHeight`; an R6's are always 2 studs and its HipHeight is 0. ]]
	local legs = if cloneHumanoid.RigType == Enum.HumanoidRigType.R6 then 2 else cloneHumanoid.HipHeight
	local position = at + Vector3.new(0, legs + root.Size.Y / 2, 0)
	clone:PivotTo(CFrame.lookAt(position, Vector3.new(toward.X, position.Y, toward.Z)))
	clone.Parent = parent
	local dancers = { clone }
	if mirrorY then
		local twin = ShowcaseGarage.reflect(clone, mirrorY)
		twin.Parent = parent
		table.insert(dancers, twin)
	end

	local fallback = if cloneHumanoid.RigType == Enum.HumanoidRigType.R6 then ShowcaseConfig.Dance.FallbackR6 else ShowcaseConfig.Dance.FallbackR15
	local pool = if #dances > 0 then dances else fallback
	local animation = Instance.new("Animation")
	animation.AnimationId = pool[math.random(1, #pool)]
	for _, dancer in dancers do
		local humanoid = dancer:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			continue
		end
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid
		--- A dance that will not load (moderated, or an R6 id on an R15) leaves the avatar standing.
		pcall(function()
			local track = animator:LoadAnimation(animation)
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Action4
			track:Play()
		end)
		--- The face's mood, under the dance (above). Failing to load leaves the blank face, as before.
		if moodId then
			pcall(function()
				local mood = Instance.new("Animation")
				mood.AnimationId = moodId
				local track = animator:LoadAnimation(mood)
				track.Looped = true
				track.Priority = Enum.AnimationPriority.Core
				track:Play()
			end)
		end
	end
	return clone
end

--- The key light above the pair, the warm fill and the flames behind the car — returned, for the reveal.
local function buildLights(parent: Instance, floorTop: Vector3, carAt: Vector3, facing: Vector3): (SpotLight, PointLight, ParticleEmitter)
	local stage = ShowcaseConfig.Stage
	local key = part(parent, { Name = "KeyLight", Transparency = 1, Size = Vector3.one, CFrame = CFrame.lookAt(floorTop + Vector3.new(0, 28, 10), floorTop) })
	local spot = Instance.new("SpotLight")
	spot.Brightness = stage.KeyBrightness
	spot.Range = 60
	spot.Angle = 70
	spot.Face = Enum.NormalId.Front
	spot.Parent = key

	local behind = carAt - facing.Unit * 8 + Vector3.new(0, 3, 0)
	local fill = part(parent, { Name = "Fill", Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(behind) })
	local light = Instance.new("PointLight")
	light.Color = stage.FillColor
	light.Brightness = stage.FillBrightness
	light.Range = 30
	light.Parent = fill

	local flames = stage.Flames
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Color = ColorSequence.new(flames.Color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, flames.Size * 0.5), NumberSequenceKeypoint.new(1, flames.Size) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(flames.Lifetime * 0.7, flames.Lifetime)
	emitter.Rate = flames.Rate
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = part(parent, { Name = "Flames", Transparency = 1, Size = Vector3.new(14, 1, 3), CFrame = CFrame.lookAt(behind - Vector3.new(0, 3, 0), behind - Vector3.new(0, 3, 0) + facing) })
	return spot, light, emitter
end

--- A gold sparkle emitter, switched off (`Rate` 0) — the reveal's charge and burst are both made of it.
local function sparkles(color: Color3, size: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Rate = 0
	return emitter
end

--[[ The reveal's column of light at `at`, built as a sliver on the floor (it grows over the hold to
	the returned size and CFrame), plus the sparkles that stream up it and the burst that goes off at
	the hit. A cylinder's length is its X, hence the roll that stands it up. ]]
local function buildBeam(parent: Instance, at: Vector3): (Part, Vector3, CFrame, ParticleEmitter, ParticleEmitter)
	local reveal = ShowcaseConfig.Reveal
	local cfg = reveal.Beam
	local height = ShowcaseConfig.Stage.WallHeight
	local upright = CFrame.Angles(0, 0, math.rad(90))
	local beam = part(parent, {
		Name = "RevealBeam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, cfg.Radius * 2, cfg.Radius * 2),
		CFrame = CFrame.new(at + Vector3.new(0, 0.1, 0)) * upright,
		Color = cfg.Color,
		Material = Enum.Material.Neon,
		--- `Beam.Show` off keeps the part (the reveal still tweens it) and simply never draws it.
		Transparency = if cfg.Show then cfg.Transparency else 1,
	})
	local fullSize = Vector3.new(height, cfg.Radius * 2, cfg.Radius * 2)
	local fullCFrame = CFrame.new(at + Vector3.new(0, height / 2, 0)) * upright

	local source = part(parent, { Name = "RevealCharge", Transparency = 1, Size = Vector3.new(cfg.Radius * 1.6, 0.2, cfg.Radius * 1.6), CFrame = CFrame.new(at + Vector3.new(0, 0.3, 0)) })
	local charge = sparkles(cfg.Color, 0.8)
	charge.EmissionDirection = Enum.NormalId.Top
	charge.Speed = NumberRange.new(8, 16)
	charge.SpreadAngle = Vector2.new(8, 8)
	charge.Lifetime = NumberRange.new(1.2, 2)
	charge.Rate = cfg.ChargeRate
	charge.Parent = source

	local centre = part(parent, { Name = "RevealBurst", Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(at + Vector3.new(0, 2.5, 0)) })
	local burst = sparkles(reveal.SparkleColor, 1.4)
	burst.Speed = NumberRange.new(20, 45)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Drag = 3
	burst.Acceleration = Vector3.new(0, -8, 0)
	burst.Parent = centre
	return beam, fullSize, fullCFrame, charge, burst
end

--- The disc of light that races out across the floor at the hit (`Reveal.Wave`), then is gone.
local function wave(parent: Instance, at: Vector3, color: Color3)
	local cfg = ShowcaseConfig.Reveal.Wave
	local flat = CFrame.Angles(0, 0, math.rad(90))
	local disc = part(parent, {
		Name = "RevealWave",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 2, 2),
		CFrame = CFrame.new(at + Vector3.new(0, 0.15, 0)) * flat,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
	})
	TweenService:Create(disc, TweenInfo.new(cfg.Time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, cfg.Radius * 2, cfg.Radius * 2),
		Transparency = 1,
	}):Play()
	task.delay(cfg.Time, function()
		disc:Destroy()
	end)
end

--[[ Black the car out for `"Silhouette"` and return the function that puts every bit of it back:
	every part black and matte (Neon headlights included, or they would glow through the shape), mesh
	textures, decals and SurfaceAppearances off, and its own lights and effects (plate glow, weather)
	switched off. Each change is recorded per instance and undone property by property, so the restore
	cannot get a car's looks wrong — it can only fail to find an instance the stage has since lost, and
	then that one is skipped. ]]
local function silhouette(model: Model): () -> ()
	local saved: { [Instance]: { [string]: any } } = {}
	local black = Color3.new(0, 0, 0)
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			local props: { [string]: any } = { Color = inst.Color, Material = inst.Material, Reflectance = inst.Reflectance }
			if inst:IsA("MeshPart") then
				props.TextureID = inst.TextureID
				inst.TextureID = ""
			end
			saved[inst] = props
			inst.Color = black
			inst.Material = Enum.Material.SmoothPlastic
			inst.Reflectance = 0
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			saved[inst] = { Transparency = inst.Transparency }
			inst.Transparency = 1
		elseif inst:IsA("SurfaceAppearance") then
			saved[inst] = { Parent = inst.Parent }
			inst.Parent = nil
		elseif inst:IsA("Light") or inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
			saved[inst] = { Enabled = inst.Enabled }
			inst.Enabled = false
		elseif inst:IsA("SurfaceGui") or inst:IsA("BillboardGui") then
			saved[inst] = { Enabled = inst.Enabled }
			inst.Enabled = false
		end
	end
	return function()
		for inst, props in saved do
			for key, value in props do
				pcall(function()
					(inst :: any)[key] = value
				end)
			end
		end
	end
end

--[[ The sunburst (`Reveal.Rays`): spokes on a wheel whose hub is `hub`, built in the hub's own XY
	plane (so the hub's LookVector is the way the wheel faces). Returned with every spoke at the hold's
	dimness; the camera step turns it by pivoting the model about the hub. ]]
local function buildRays(parent: Instance, hub: CFrame): Model
	local cfg = ShowcaseConfig.Reveal.Rays
	local model = Instance.new("Model")
	model.Name = "RevealRays"
	for i = 1, cfg.Count do
		local angle = (i / cfg.Count) * math.pi * 2
		part(model, {
			Name = "Ray",
			Size = Vector3.new(cfg.Width, cfg.Length, 0.2),
			CFrame = hub * CFrame.Angles(0, 0, angle) * CFrame.new(0, cfg.Length / 2, 0),
			Color = cfg.Colors[(i - 1) % #cfg.Colors + 1],
			Material = Enum.Material.Neon,
			Transparency = cfg.HoldTransparency,
		})
	end
	model.WorldPivot = hub
	model.Parent = parent
	return model
end

-- === The words ================================================================

local function stroked(label: TextLabel, thickness: number): TextLabel
	local stroke = Instance.new("UIStroke")
	stroke.Color = ShowcaseConfig.Colors.Stroke
	stroke.Thickness = thickness
	stroke.Parent = label
	return label
end

local function text(parent: Instance, name: string, value: string, position: UDim2, size: UDim2, font: Font, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = size
	label.FontFace = font
	label.Text = value
	label.TextColor3 = color
	label.TextScaled = true
	label.Parent = parent
	return label
end

--[[ The tag over the name: the weather's word when the car has one ("CHARGED"), in that mutation's
	own badge colour, else nothing.
	=== MUTATION ONLY, 2026-10-15 === WAS: a painted car said its colour here too ("GRAPHITE"), in
	the same gold as every mutation. Aleafo asked whether that line would always be a colour; now it
	only ever names a mutation, coloured like its notice and badge, so the line itself says "weather". ]]
local function tagOf(car: Car): (string?, Color3?)
	if car.mutation then
		return string.upper(WeatherConfig.nameOf(car.mutation)), WeatherConfig.colorOf(car.mutation)
	end
	return nil, nil
end

function ShowcaseController._buildGui(self, car: Car): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.DisplayOrder = DISPLAY_ORDER
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false

	local fonts, colors = ShowcaseConfig.Fonts, ShowcaseConfig.Colors
	local title = text(gui, "Title", ShowcaseConfig.Text.Title, UDim2.fromScale(0.5, 0.14), UDim2.fromScale(0.6, 0.13), fonts.Title, Color3.new(1, 1, 1))
	stroked(title, 4)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(colors.TitleTop, colors.TitleBottom)
	gradient.Rotation = 90
	gradient.Parent = title
	local pop = Instance.new("UIScale")
	pop.Scale = 0
	pop.Parent = title

	local tag, tagColor = tagOf(car)
	local nameY = if tag then 0.84 else 0.8
	local lines = {}
	if tag then
		table.insert(lines, stroked(text(gui, "Tag", tag, UDim2.fromScale(0.5, 0.76), UDim2.fromScale(0.5, 0.07), fonts.Name, tagColor or colors.Tag), 3))
	end
	table.insert(lines, stroked(text(gui, "Name", GarageConfig.displayName(car.body), UDim2.fromScale(0.5, nameY), UDim2.fromScale(0.7, 0.08), fonts.Name, colors.Name), 3))
	table.insert(
		lines,
		stroked(
			text(gui, "Worth", string.format(ShowcaseConfig.Text.WorthFormat, GarageConfig.formatCash(car.value)), UDim2.fromScale(0.5, nameY + 0.065), UDim2.fromScale(0.4, 0.04), fonts.Name, colors.Tag),
			2
		)
	)
	--[[ With the reveal on, the lines wait out of sight, `TextRise` below where they belong, for
		`_impact` to slide them up. Their resting positions are kept beside them for that. ]]
	local reveal = ShowcaseConfig.Reveal
	self._lines = {}
	if reveal.Enabled then
		for _, label in lines do
			local final = label.Position
			label.Position = final + UDim2.fromScale(0, reveal.TextRise)
			label.TextTransparency = 1
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 1
			end
			table.insert(self._lines, { label = label, final = final })
		end
	end

	--- Under the words (ZIndex 0, they are at 1), so a name is never covered by a piece of paper.
	local confetti = Instance.new("Frame")
	confetti.Name = "Confetti"
	confetti.BackgroundTransparency = 1
	confetti.Size = UDim2.fromScale(1, 1)
	confetti.ZIndex = 0
	confetti.Parent = gui

	local flashFrame = Instance.new("Frame")
	flashFrame.Name = "Flash"
	flashFrame.BackgroundColor3 = reveal.Flash.Color
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.ZIndex = 9
	flashFrame.Parent = gui
	local hint = text(gui, "Continue", ShowcaseConfig.Text.Continue, UDim2.fromScale(0.5, 0.96), UDim2.fromScale(0.3, 0.03), fonts.Name, colors.Name)
	hint.TextTransparency = 1
	--[[ The outline hides with the text. A UIStroke does not follow TextTransparency, so left at 0 it
		drew "Click to continue" as dark outlined letters through the whole reveal, before the click
		was even armed (seen 2026-10-02 in the garage's first playtest). ]]
	local hintOutline = stroked(hint, 1.5):FindFirstChildOfClass("UIStroke")
	if hintOutline then
		hintOutline.Transparency = 1
	end

	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BorderSizePixel = 0
	fade.Size = UDim2.fromScale(1, 1)
	fade.ZIndex = 10
	fade.Parent = gui

	self._pop = pop
	self._continue = hint
	self._fade = fade
	self._flashFrame = flashFrame
	self._confettiLayer = confetti
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

-- === The HUD and the controls ====================================================

--[[ Hold one screen off for the cutscene: record that it wants to be on and switch it off, and keep
	it off if it switches itself back on. Header note 1.

	A SCREEN THAT TURNS ITSELF ON MID-CUTSCENE IS THE CASE THAT MATTERS — the tutorial's "Your First
	Car" card went up over the first stage ever played. Only a `Changed` that reads TRUE is acted on:
	this file only ever writes false, so true can only be the game asking for the screen, which is
	recorded for the restore and undone. That is what keeps the deferred signal from being a loop. ]]
function ShowcaseController._holdGui(self, gui: ScreenGui)
	if gui.Name == GUI_NAME or self._watched[gui] then
		return
	end
	self._watched[gui] = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			self._wanted[gui] = true
			gui.Enabled = false
		end
	end)
	if gui.Enabled then
		self._wanted[gui] = true
		gui.Enabled = false
	end
end

--- Every ScreenGui held (`_holdGui`), and every one that arrives while the stage is up.
function ShowcaseController._hideHud(self)
	self._wanted = {}
	self._watched = {}
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	for _, inst in playerGui:GetDescendants() do
		if inst:IsA("ScreenGui") then
			self:_holdGui(inst)
		end
	end
	self._arrivals = playerGui.DescendantAdded:Connect(function(inst)
		if inst:IsA("ScreenGui") then
			self:_holdGui(inst)
		end
	end)
end

--- Listeners off first, then every screen that wanted to be on put back on — and only those.
function ShowcaseController._restoreHud(self)
	if self._arrivals then
		self._arrivals:Disconnect()
		self._arrivals = nil
	end
	for _, connection in self._watched or {} do
		connection:Disconnect()
	end
	for gui in self._wanted or {} do
		if gui.Parent then
			gui.Enabled = true
		end
	end
	self._wanted, self._watched = nil, nil
end

--- The stock movement controls, off or on. A missing PlayerModule leaves them on: the player can walk
--- about under the cutscene, which is harmless.
function ShowcaseController._controls(self, enabled: boolean)
	local ok, controls = pcall(function()
		local module = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 2) :: any)
		return module:GetControls()
	end)
	if ok and controls then
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

-- === Confetti ===================================================================

--[[ Both corner cannons at once, then the rain until `_confettiStop`. The paper itself is
	`Modules/ScreenConfetti` (moved there 2026-10-06 so the tutorial's finish fires the same one). ]]
function ShowcaseController._confettiStart(self)
	local cfg = ShowcaseConfig.Reveal.Confetti
	local layer = self._confettiLayer
	if not (cfg.Enabled and layer) then
		return
	end
	self:_confettiStop()
	self._confetti = ScreenConfetti.start(layer, cfg)
end

function ShowcaseController._confettiStop(self)
	if self._confetti then
		self._confetti.stop()
		self._confetti = nil
	end
end

-- === The reveal ===================================================================

-- The buildup and impact belong to this stage, including when RaceStart aborts it. Keeping real
-- playback handles prevents either clip carrying into the next scene through a hidden local copy.
function ShowcaseController._stopRevealSounds(self)
	local playing = self._revealSounds or {}
	if self._buildupSound then
		table.insert(playing, self._buildupSound)
	end
	for _, sound in playing do
		sound:Stop()
		sound:Destroy()
	end
	self._buildupSound = nil
	self._revealSounds = nil
end

--[[ The hit's clips for this car's rarity band (`ShowcaseConfig.Reveal.Sounds.RevealByBand`), all
	started at once. Falls back to the one `Reveal` clip when the band has no entry or none of its
	Sounds exist in the place. A `StartAt` attribute on a clip skips its lead-in; the playback is a
	clone, so it carries the attribute. ]]
function ShowcaseController._playReveal(self, sounds, band: number)
	local cfg = ShowcaseConfig.Reveal.Sounds
	local names = cfg.RevealByBand and cfg.RevealByBand[band]
	local playing = {}
	for _, name in names or {} do
		local sound = sounds:PlayNamedOwned(cfg.Group, name)
		if sound then
			table.insert(playing, sound)
		end
	end
	if #playing == 0 then
		local sound = sounds:PlayNamedOwned(cfg.Group, cfg.Reveal)
		if sound then
			table.insert(playing, sound)
		end
	end
	for _, sound in playing do
		local startAt = sound:GetAttribute("StartAt")
		if type(startAt) == "number" and startAt > 0 then
			sound.TimePosition = startAt
		end
	end
	self._revealSounds = playing
end

function ShowcaseController._startBuildup(self)
	local cfg = ShowcaseConfig.Reveal.Sounds
	local sounds = Shard.get("SoundController")
	if cfg.Enabled and sounds then
		self._buildupSound = sounds:PlayNamedOwned(cfg.Group, cfg.Buildup)
	end
end

--[[ The hit: everything that happens the instant the car lands (`ShowcaseConfig.Reveal` has the
	list). Only ever called from `_runReveal`, which has already checked the stage is still up. ]]
function ShowcaseController._impact(self, rig: Rig)
	self:_stopRevealSounds()
	local cfg = ShowcaseConfig.Reveal.Sounds
	local sounds = Shard.get("SoundController")
	if cfg.Enabled and sounds then
		self:_playReveal(sounds, rig.band)
	end
	local reveal = ShowcaseConfig.Reveal
	local stage = ShowcaseConfig.Stage
	if self._flashFrame then
		self._flashFrame.BackgroundTransparency = 0
		TweenService:Create(self._flashFrame, TweenInfo.new(reveal.Flash.Time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	end
	if rig.restore then
		rig.restore()
		rig.restore = nil
	end
	if rig.rays then
		for _, ray in rig.rays:GetChildren() do
			if ray:IsA("BasePart") then
				TweenService:Create(ray, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = reveal.Rays.Transparency }):Play()
			end
		end
	end
	rig.key.Brightness = stage.KeyBrightness
	rig.fill.Brightness = stage.FillBrightness
	rig.flames.Enabled = rig.flamesOn
	rig.charge.Enabled = false
	TweenService:Create(rig.beam, TweenInfo.new(0.35), { Transparency = 1 }):Play()
	--[[ The garage comes on from the car outward, in the rarity colour (`ShowcaseConfig.Garage`), and
		the car's reflection goes into the floor with it: a black car has no reflection worth showing,
		and a car rising out of the floor (`"Rise"`) would have met its own twin coming the other way. ]]
	if rig.room then
		ShowcaseGarage.powerOn(rig.room, rig.carAt)
	end
	if rig.carTwin then
		rig.carTwin.Parent = rig.stage
	end
	wave(rig.stage, rig.carAt, rig.waveColor)
	rig.burst:Emit(reveal.Sparkles)
	self._kick = 1

	local pop = self._pop
	if pop then
		local land = TweenService:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		land:Play()
		land.Completed:Once(function()
			if pop.Parent then
				TweenService:Create(pop, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = reveal.TitleBreathe }):Play()
			end
		end)
	end
	for i, line in self._lines or {} do
		task.delay(reveal.TextLead + (i - 1) * reveal.TextStagger, function()
			if not line.label.Parent then
				return
			end
			local info = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			TweenService:Create(line.label, info, { Position = line.final, TextTransparency = 0 }):Play()
			local stroke = line.label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, info, { Transparency = 0 }):Play()
			end
		end)
	end
	self:_confettiStart()
end

--[[ The reveal, start to finish, on its own thread (header): `after` seconds for the cover to clear,
	the hold while the beam grows, the rise, the hit. `isDone` is the stage having ended — checked
	after every wait, so a click or a run starting mid-reveal leaves nothing half-played behind. ]]
function ShowcaseController._runReveal(self, rig: Rig, after: number, isDone: () -> boolean)
	local reveal = ShowcaseConfig.Reveal

	--[[ `"Silhouette"`: no wait for the cover — the black car is already worth watching through it.
		The spin decelerates on `Quint` (whipping round at first, creeping into the pose at the end) and
		the rumble climbs linearly, so the two meet at the hit: the car stops, the shaking peaks, BANG. ]]
	if reveal.Style == "Silhouette" then
		if isDone() then
			return
		end
		self:_startBuildup()
		local car, landed = rig.car, rig.landed
		local started = os.clock()
		while not isDone() do
			local t = math.min((os.clock() - started) / reveal.SilhouetteHold, 1)
			if car and landed then
				local turn = (1 - TweenService:GetValue(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)) * reveal.Spins * math.pi * 2
				car:PivotTo(landed * CFrame.Angles(0, turn, 0))
			end
			self._rumble = t
			if t >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		self._rumble = 0
		if not isDone() then
			self:_impact(rig)
		end
		return
	end

	task.wait(after)
	if isDone() then
		return
	end
	self:_startBuildup()
	TweenService:Create(rig.beam, TweenInfo.new(reveal.Hold, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = rig.beamSize, CFrame = rig.beamCFrame }):Play()
	task.wait(reveal.Hold)
	if isDone() then
		return
	end

	--[[ Up out of the floor: height on `Back` (the overshoot and settle), turn on `Quad` so the spin
		is fastest leaving the floor and has stopped by the time the car settles. The landed pivot's
		only rotation is yaw, so its own -Y is straight down. ]]
	local car, landed = rig.car, rig.landed
	if car and landed then
		local started = os.clock()
		while not isDone() do
			local t = math.min((os.clock() - started) / reveal.Rise, 1)
			local up = TweenService:GetValue(t, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local turn = (1 - TweenService:GetValue(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)) * reveal.Spins * math.pi * 2
			car:PivotTo(landed * CFrame.new(0, -(1 - up) * rig.depth, 0) * CFrame.Angles(0, turn, 0))
			if t >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end
	if isDone() then
		return
	end
	self:_impact(rig)
end

-- === Playing ====================================================================

--[[ YIELDS until the stage is fit to be seen: everything in it loaded (the room, the car's meshes,
	the avatar's accessories) and then `Timing.ReadyFrames` frames drawn with the camera already on
	it. Capped at `Timing.ReadyTimeout` in total — past that the cover lifts on whatever is there,
	because a flash that never ends is worse than a car that pops in. Called with the cover up and
	the camera step already bound, which is the whole point: the loading happens behind the cover. ]]
function ShowcaseController._waitUntilDrawn(self, stage: Model)
	local timing = ShowcaseConfig.Timing
	local deadline = os.clock() + timing.ReadyTimeout
	local loaded = false
	task.spawn(function()
		--- A load that errors (a moderated asset) is a load that is over; the stage shows without it.
		pcall(function()
			ContentProvider:PreloadAsync({ stage })
		end)
		loaded = true
	end)
	while not loaded and os.clock() < deadline do
		RunService.RenderStepped:Wait()
	end
	for _ = 1, timing.ReadyFrames do
		if os.clock() >= deadline then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

--[[ The remote: a car beat the record. A bank (`afterRun`) waits for the run's results screen to
	START LIFTING (`RaceConfig.LiftingEvent`, subscribed in `start`) and cuts straight from it to the
	stage with a flash — the car you got is shown on the results first, then the show-off, and the
	plot is not seen in between. A screen that never lifts inside `ShowcaseConfig.ReturnTimeout` does
	not cost the cutscene: it plays anyway, from black. A car from anywhere else plays at once,
	unless a run is on: then it waits like a bank does (2026-10-06, Leaf got the stage while still
	driving). No fallback is armed for it here; `RaceEnd` arms one and the results' lift plays it.

	A later car replaces a waiting one: the record only goes up, so the later one is the better. ]]
function ShowcaseController._onNewBest(self, car: Car, afterRun: boolean)
	if not ShowcaseConfig.Enabled then
		return
	end
	if not afterRun and self._racing then
		self._pending = car
		return
	end
	if not afterRun then
		--- In the lobby, so the view before it is the player's own and is handed back (`play`).
		task.spawn(self.play, self, car, nil, true)
		return
	end
	self._pending = car
	self:_armFallback()
end

--[[ The ReturnTimeout fallback for a waiting car. Re-armed on `RaceEnd` (below), and dropped by
	`RaceStart` — see `_playPending` for why a run must never be where this fires. ]]
function ShowcaseController._armFallback(self)
	self._pendingToken += 1
	local token = self._pendingToken
	task.delay(ShowcaseConfig.ReturnTimeout, function()
		if self._pendingToken == token then
			self:_playPending(false)
		end
	end)
end

--[[ Play the waiting car, if there still is one. Whichever of the lift and the timeout comes first
	takes it; the other finds nothing.

	`task.spawn` RUNS THE STAGE'S FIRST STRETCH ON THIS THREAD, up to its first yield — and building
	the cover is before any yield, so off `LiftingEvent` it is up in the same frame the results
	start fading. That is the whole of "the plot is never seen". ]]
function ShowcaseController._playPending(self, flash: boolean)
	local car = self._pending
	if not car then
		return
	end
	--[[ NEVER DURING A RUN (2026-10-05). A playtester banked, pressed RACE AGAIN, and got the stage
		over the road while driving. RACE AGAIN keeps the results screen black straight into the next
		run's entry, so the lift this waits for never comes — and the `ReturnTimeout` fallback then went
		off forty-five seconds into the new run. Now a waiting car stays waiting for as long as a run is
		on (`_racing`, off `RaceStart`/`RaceEnd`), and plays when that run's results lift instead. ]]
	if self._racing then
		return
	end
	self._pending = nil
	task.spawn(self.play, self, car, flash)
end

--[[ Play the stage for `car`. Yields for the whole cutscene. A second call while one is playing is
	dropped: the record only goes up, so the one playing is never worse than a record it has not yet
	heard of by much, and two stages would fight over one camera. ]]
function ShowcaseController.play(self, car: Car, flash: boolean?, keepView: boolean?)
	if self._playing then
		return
	end
	self._playing = true
	--- For whatever must step aside while the stage is up (`UpgradeController`'s prompt, 2026-10-14:
	--- it showed through the cutscene). `ShowcaseEnded` below is the other half.
	Dispatcher:Publish("ShowcaseStarted")
	local timing = ShowcaseConfig.Timing
	local shot = ShowcaseConfig.Camera
	local camera = Workspace.CurrentCamera

	local gui = self:_buildGui(car)
	if flash then
		self._fade.BackgroundColor3 = ShowcaseConfig.Transition.Color
	end
	--[[ Above the character, not at a fixed far-off spot (`ShowcaseConfig.Stage.Above` has why). The
		camera's position is the fallback for a player between characters. ]]
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local base = if root and root:IsA("BasePart") then root.Position else camera.CFrame.Position
	local origin = base + Vector3.new(0, ShowcaseConfig.Stage.Above, 0)
	--- The player's own view, for the handback (`keepView`, below at the release).
	local viewBefore = camera.CFrame
	--[[ The garage is built round the shot (`Modules/ShowcaseGarage` note 1), so it waits until the car
		has been measured below; until then the stage is an empty model with the floor's height. ]]
	local garage = ShowcaseConfig.Stage.Room == "Garage"
	local stage: Model, floorTop: Vector3
	if garage then
		stage = Instance.new("Model")
		stage.Name = "ShowcaseStage"
		stage.Parent = Workspace
		floorTop = origin + Vector3.new(0, 0.5, 0)
	else
		stage, floorTop = buildStage(origin)
	end
	--- If anything takes the stage away mid-cutscene, say so: that was the vanishing-stage bug's
	--- signature, and the next one should arrive with a log line rather than a screenshot of sky.
	local builtAt = os.clock()
	stage.AncestryChanged:Connect(function(_, parent)
		if parent == nil and not self._stageEnding then
			warn(string.format("[ShowcaseController] The stage was removed %.1fs into the cutscene by something else.", os.clock() - builtAt))
		end
	end)

	--[[ The layout, in the stage's own terms: the camera rests on +Z looking at −Z, the car stands a
		little right of centre with its nose turned three-quarters toward the lens, the avatar left of
		it facing the lens. The avatar's gap scales with the car's footprint so a truck does not stand
		on its owner. ]]
	local facing = Vector3.new(-0.55, 0, 1).Unit
	local car3d = buildCar(stage, car, floorTop + Vector3.new(3, 0, 0), facing)
	local length = 14
	if car3d then
		local _, size = car3d:GetBoundingBox()
		length = math.max(size.X, size.Z)
	end
	local carAt = floorTop + Vector3.new(3, 0, 0)
	local avatarAt = floorTop + Vector3.new(3 - length * 0.55 - 2.5, 0, 2)
	local eyeLine = floorTop + Vector3.new(3 - length * 0.3, 3, 0)
	local distance = math.max(shot.Distance, length * shot.FitPadding + 4)

	--[[ The garage, in the car's rarity colour, centred under the point the camera looks at. The car's
		reflection is made now, before the reveal blacks the car out or sinks it, and kept out of the
		world until the hit (`_impact`) unless there is no reveal to wait for. ]]
	local room: ShowcaseGarage.Room? = nil
	local carTwin: Model? = nil
	local accent = ShowcaseConfig.Reveal.Wave.Color
	if garage then
		local rings = ShowcaseConfig.Garage.Ring
		local _word, colour = CarRarity.labelOf(car.body)
		accent = colour
		room = ShowcaseGarage.build(stage, floorTop, Vector3.new(eyeLine.X, floorTop.Y, eyeLine.Z), distance, math.max(rings.Radius, length * rings.PerLength), accent)
		if car3d then
			carTwin = ShowcaseGarage.reflect(car3d, floorTop.Y)
			if not ShowcaseConfig.Reveal.Enabled then
				(carTwin :: Model).Parent = stage
			end
		end
	end
	buildAvatar(stage, avatarAt, eyeLine + Vector3.new(0, 0, distance), if room then floorTop.Y else nil)
	local key, fill, flames = buildLights(stage, floorTop, carAt, facing)
	local flamesOn = not (garage and not ShowcaseConfig.Garage.Flames)
	flames.Enabled = flamesOn
	--- The world's sky and haze kept out of the garage while it draws (`ShowcaseConfig.Garage.World`).
	local releaseWorld = if room then ShowcaseGarage.holdWorld(room) else nil

	--[[ The reveal's starting state (`ShowcaseConfig.Reveal`): the room dimmed, the flames out, the
		sunburst glowing dimly behind, and the car either blacked out in place (`"Silhouette"`) or sunk
		out of sight under the floor, its own height and a margin down (`"Rise"`). ]]
	local reveal = ShowcaseConfig.Reveal
	local rig: Rig? = nil
	if reveal.Enabled then
		local landed = if car3d then car3d:GetPivot() else nil
		local depth = 0
		local restore: (() -> ())? = nil
		if car3d and landed then
			if reveal.Style == "Silhouette" then
				restore = silhouette(car3d)
			else
				local _, size = car3d:GetBoundingBox()
				depth = size.Y + 3
				car3d:PivotTo(landed * CFrame.new(0, -depth, 0))
			end
		end
		--- The sunburst's hub: behind the car from the camera's resting side (+Z), facing that side.
		local rays: Model? = nil
		local raysHub: CFrame? = nil
		if reveal.Rays.Enabled then
			local hubAt = carAt + Vector3.new(0, reveal.Rays.Up, -reveal.Rays.Behind)
			raysHub = CFrame.lookAt(hubAt, hubAt + Vector3.new(0, 0, 1))
			rays = buildRays(stage, raysHub :: CFrame)
		end
		key.Brightness = ShowcaseConfig.Stage.KeyBrightness * reveal.Dim
		fill.Brightness = ShowcaseConfig.Stage.FillBrightness * reveal.Dim
		flames.Enabled = false
		if room then
			ShowcaseGarage.setPower(room, 0)
		end
		local beam, beamSize, beamCFrame, charge, burst = buildBeam(stage, carAt)
		rig = {
			stage = stage,
			car = car3d,
			landed = landed,
			depth = depth,
			carAt = carAt,
			key = key,
			fill = fill,
			flames = flames,
			beam = beam,
			beamSize = beamSize,
			beamCFrame = beamCFrame,
			charge = charge,
			burst = burst,
			restore = restore,
			rays = rays,
			raysHub = raysHub,
			band = select(2, CarRarity.of(car.body)),
			room = room,
			carTwin = carTwin,
			flamesOn = flamesOn,
			waveColor = accent,
		}
	end

	--[[ THE CAMERA'S TYPE IS NEVER TOUCHED: this writes CFrame and lens every frame AFTER whatever
		camera is running, and then stops. Taking it Scriptable and handing a saved type back was the
		first version, and it is fragile in exactly the moment this plays: at the end of a run, where
		`RaceCameraController` is handing its own type back, and a type "saved" a beat too early is the
		RACE's Scriptable — a lobby with a frozen camera. Not writing the type cannot go wrong that
		way: left alone, the stock camera rebuilds its shot from its own state the frame this lets go.

		The lens is the one thing restored, and to the last value SOMEBODY ELSE wrote: a write this
		did not make (the race camera putting its own back) replaces what goes back. ]]
	local fovBack = camera.FieldOfView
	local fovOurs: number? = nil
	self:_hideHud()
	self:_controls(false)

	--[[ The orbit, per frame: an angle round the pair, a distance and a height, eased from the sweep's
		start to the resting shot, then a slow sine drift. `GetValue` is the ease without a tween. ]]
	--- Reset once the stage is on screen (below), so the sweep starts when it can be seen.
	local started = os.clock()
	local lastFrame = os.clock()
	local shakeRng = Random.new()
	local raysAngle = 0
	self._kick = 0
	self._rumble = 0
	RunService:BindToRenderStep(CAMERA_STEP, CAMERA_PRIORITY, function()
		local now = os.clock()
		local dt = now - lastFrame
		lastFrame = now
		--- The reveal's kick (`Reveal.FovKick`/`Shake`), set to 1 at the hit and decaying from there.
		local kick = self._kick
		if kick > 0 then
			self._kick = if kick < 0.01 then 0 else kick * math.exp(-reveal.KickDecay * dt)
		end
		local t = now - started
		local a = TweenService:GetValue(math.min(t / shot.SweepTime, 1), Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		local drift = math.sin(math.max(t - shot.SweepTime, 0) / shot.DriftPeriod * math.pi * 2) * shot.DriftDegrees
		local angle = math.rad(shot.StartAngle * (1 - a) + drift * a)
		local reach = distance * (shot.StartScale + (1 - shot.StartScale) * a)
		local height = shot.StartHeight + (shot.Height - shot.StartHeight) * a
		local eye = eyeLine + Vector3.new(math.sin(angle) * reach, height - 3, math.cos(angle) * reach)
		if fovOurs and camera.FieldOfView ~= fovOurs then
			fovBack = camera.FieldOfView
		end
		camera.FieldOfView = shot.FieldOfView + reveal.FovKick * kick
		fovOurs = camera.FieldOfView
		--- The hit's kick plus the silhouette's building rumble (`Reveal.Rumble`), one shake.
		local strength = reveal.Shake * kick + reveal.Rumble * self._rumble
		local shake = if strength > 0
			then Vector3.new(shakeRng:NextNumber(-1, 1), shakeRng:NextNumber(-1, 1), shakeRng:NextNumber(-1, 1)) * strength
			else Vector3.zero
		camera.CFrame = CFrame.lookAt(eye + shake, eyeLine)
		--- The sunburst turns here, with the camera, so the two never disagree by a frame.
		if rig and rig.rays and rig.raysHub then
			raysAngle += math.rad(reveal.Rays.Spin + reveal.Rays.HitSpin * kick) * dt
			rig.rays:PivotTo(rig.raysHub * CFrame.Angles(0, 0, raysAngle))
		end
	end)

	--[[ In. Off the results (`flash`) it is a FLASH: the cover went up opaque in the transition colour
		on the lift's first frame, before the lobby could show through, and it burns off into the stage
		— a camera flash reads as the cut being meant. Anywhere else it is the plain fade from black.
		The cover goes back to black once it is clear, because the way OUT is a fade to black. ]]
	self:_waitUntilDrawn(stage)
	started = os.clock()
	local inTime = if flash then timing.FlashOut else timing.FadeIn
	TweenService:Create(self._fade, TweenInfo.new(inTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	task.delay(inTime, function()
		if self._fade then
			self._fade.BackgroundColor3 = Color3.new(0, 0, 0)
		end
		--- With the reveal on, the title waits for the car (`_impact`).
		if self._pop and not rig then
			TweenService:Create(self._pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)

	--[[ The way out: a click after `SkipAfter`, or a run starting (header note 2, which skips the
		fade). Keyboard skips are Space and Enter only — E stays with the prompts.

		NO TIMER, since 2026-09-29 (it ended itself after 7 seconds; the user: "make it so when you
		click then it disappears"). The stage is the player's to leave. ]]
	local finished = Instance.new("BindableEvent")
	local done = false
	local function finish(instant: boolean?)
		if done then
			return
		end
		done = true
		self:_stopRevealSounds()
		finished:Fire(instant == true)
	end
	self._abort = function()
		finish(true)
	end
	--[[ The reveal runs beside the wait below, never in front of it (header). The click is armed
		`SkipAfter` after the HIT rather than after the cover, so it cannot skip the reveal — the
		reveal's own length is known up front, which is what lets this be a plain delay. ]]
	local skipAfter = timing.SkipAfter
	if rig then
		task.spawn(self._runReveal, self, rig, inTime, function()
			return done
		end)
		skipAfter += if reveal.Style == "Silhouette" then reveal.SilhouetteHold else inTime + reveal.Hold + reveal.Rise
	end
	task.delay(skipAfter, function()
		if done then
			return
		end
		--[[ The words for the device in hand, read now rather than at build: the player may have put
			the pad down since. On a pad the A glyph stands in front of them, hugging the words rather
			than the wide box they are centred in. ]]
		local words = ShowcaseConfig.Text
		local preferred = UserInputService.PreferredInput
		if preferred == Enum.PreferredInput.Gamepad then
			self._continue.Text = words.ContinuePad
			local icon = GamepadInput.createIcon(self._continue, Enum.KeyCode.ButtonA, "left")
			icon.AnchorPoint = Vector2.new(1, 0.5)
			icon.Position = UDim2.new(0.5, -self._continue.TextBounds.X * 0.5 - 8, 0.5, 0)
		elseif preferred == Enum.PreferredInput.Touch then
			self._continue.Text = words.ContinueTouch
		else
			self._continue.Text = words.Continue
		end
		TweenService:Create(self._continue, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		local outline = self._continue:FindFirstChildOfClass("UIStroke")
		if outline then
			TweenService:Create(outline, TweenInfo.new(0.3), { Transparency = 0 }):Play()
		end
		ContextActionService:BindActionAtPriority(SKIP_ACTION, function(_, state)
			if state == Enum.UserInputState.Begin then
				finish()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 1000, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.ButtonA)
	end)

	local instant = finished.Event:Wait()
	finished:Destroy()
	ContextActionService:UnbindAction(SKIP_ACTION)

	if not instant then
		local out = TweenService:Create(self._fade, TweenInfo.new(timing.FadeOut), { BackgroundTransparency = 0 })
		out:Play()
		out.Completed:Wait()
	end

	RunService:UnbindFromRenderStep(CAMERA_STEP)
	--[[ THE VIEW GOES BACK WHERE IT WAS (2026-10-15, a seller's NEW BEST: "it moved it inside the car
		for me and I couldn't see the cheer reaction"). The type is never touched (above), and the
		stock camera takes its DIRECTION from the camera's current CFrame, so it came back facing
		wherever the last shot of the stage pointed, and its occlusion pull dragged it in through
		whatever stood that way. Put back on the frame this lets go, moved with the character so it
		is the same shot of where they are now; the stock camera carries on from it.

		LOBBY PLAYS ONLY (`keepView`, from `_onNewBest`). After a run, the view before the stage
		was the race camera's, which is the wrong shot to hand back in the lobby. ]]
	if keepView then
		local nowCharacter = Players.LocalPlayer.Character
		local nowRoot = nowCharacter and nowCharacter:FindFirstChild("HumanoidRootPart")
		local moved = if nowRoot and nowRoot:IsA("BasePart") then nowRoot.Position - base else Vector3.zero
		camera.CFrame = viewBefore + moved
	else
		--- After a run: behind the character, facing where they face (`CameraConfig.Landing`), rather
		--- than wherever the stage's last shot pointed.
		CameraFacing.behindCharacter()
	end
	self._kick = 0
	self._rumble = 0
	self:_confettiStop()
	if self._confettiLayer then
		self._confettiLayer.Visible = false
	end
	camera.FieldOfView = fovBack
	if releaseWorld then
		releaseWorld()
	end
	self._stageEnding = true
	stage:Destroy()
	self._stageEnding = false
	self:_restoreHud()
	self:_controls(true)
	self._abort = nil

	if instant then
		gui:Destroy()
	else
		local back = TweenService:Create(self._fade, TweenInfo.new(timing.FadeIn), { BackgroundTransparency = 1 })
		for _, child in gui:GetChildren() do
			if child:IsA("TextLabel") then
				child.Visible = false
			end
		end
		back:Play()
		back.Completed:Once(function()
			gui:Destroy()
		end)
	end
	self._pop, self._continue, self._fade = nil, nil, nil
	self._flashFrame, self._confettiLayer, self._lines = nil, nil, nil
	self._playing = false
	--- For whatever waited for the screen to be free (`DiscoveryController`, `busy` below).
	Dispatcher:Publish("ShowcaseEnded")
end

--[[ True while the stage is up OR a car is waiting to go on it (the lift or the timeout will play it
	soon). Other lobby moments that would be hidden under it (`DiscoveryController`) ask this first and
	wait for `ShowcaseEnded`. Pure: reads two fields. ]]
function ShowcaseController.busy(self): boolean
	return self._playing or self._pending ~= nil
end

ShowcaseController:withRemoteEvents({
	{
		NewBestCar = function(body: unknown, paint: unknown, mutation: unknown, value: unknown, afterRun: unknown)
			if type(body) ~= "string" then
				return
			end
			ShowcaseController:_onNewBest({
				body = body,
				paint = if type(paint) == "number" then paint else nil,
				mutation = if type(mutation) == "string" then mutation else nil,
				value = if type(value) == "number" then value else 0,
			}, afterRun == true)
		end,
		-- Header note 2.
		RaceStart = function()
			ShowcaseController._racing = true
			--- A waiting car keeps waiting; its fallback timer must not go off mid-run.
			ShowcaseController._pendingToken += 1
			if ShowcaseController._abort then
				ShowcaseController._abort()
			end
		end,
		--- The run is over (its results are up); a car still waiting gets its fallback back.
		RaceEnd = function()
			ShowcaseController._racing = false
			if ShowcaseController._pending then
				ShowcaseController:_armFallback()
			end
		end,
	},
})

--[[ PUBLIC (`GroupRewardController`, 2026-10-15): the NEW BEST stage's own dancing clone of the local
	character, feet on `at`, facing `toward`, parented to `parent`. The same clone, the same strip and
	the same dance, so the player dances the same way everywhere. nil with no character. ]]
function ShowcaseController.buildDancer(self, parent: Instance, at: Vector3, toward: Vector3): Model?
	return buildAvatar(parent, at, toward)
end

ShowcaseController:withLifecycle({
	init = function(self)
		self._playing = false
		self._pending = nil :: Car?
		self._pendingToken = 0
		self._racing = false
		self._wanted = nil :: { [ScreenGui]: boolean }?
		self._watched = nil :: { [ScreenGui]: RBXScriptConnection }?
		self._arrivals = nil :: RBXScriptConnection?
		self._abort = nil :: (() -> ())?
		self._kick = 0
		self._rumble = 0
		self._confetti = nil :: ScreenConfetti.Handle?
	end,

	start = function(self)
		local sounds = Shard.get("SoundController")
		if ShowcaseConfig.Reveal.Sounds.Enabled and sounds then
			sounds:Preload(ShowcaseConfig.Reveal.Sounds.Group)
		end
		Dispatcher:Subscribe(RaceConfig.LiftingEvent, function()
			self:_playPending(true)
		end)
	end,
})

return ShowcaseController
