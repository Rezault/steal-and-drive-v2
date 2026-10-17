--[[
	DayNightController  (client)
	----------------------------
	THE LOBBY'S SKY, MOVING. `DayNightConfig` says what a given hour looks like and where the hour
	comes from; this is the one thing that writes it onto `Lighting`.

	It does three things and nothing else:

	  1. Reads the map's own sky once, at boot, and keeps it as the thing every keyframe blends
	     against. Nothing in the config knows what colour this place is lit.
	  2. Steps the clock eight times a second and paints it. In AUTO the clock is a function of the
	     shared server time, so every player in the server sees the same sky at the same moment; on
	     DAY or NIGHT it simply stops somewhere.
	  3. Glides rather than cuts whenever the clock JUMPS: a press on the settings screen, the seed
	     arriving, or a race handing the lobby back. Two seconds of the sun moving is the same
	     movement the cycle makes slowly, where a cut is a graphics setting being applied.
	  4. ...and when the press lands mid-race, where it cannot write Lighting at all, hands the new
	     sky to `WeatherController` instead. See the rebase below.

	=== IT STANDS DOWN FOR A RACE, AND THAT IS THE WHOLE ARRANGEMENT ============================

	`WeatherController` captures Lighting at the start of a run and puts it back at the end, because
	a storm has to be able to change the sky over a moving car. Two files writing the same six
	properties with no ordering between them is not something to tune, so this one stops writing
	between `RaceStart` and `RaceEnd` and lets that one have it.

	What falls out of that is better than what was designed: weather captures the lobby as it finds
	it, so a run that starts at dusk is DRIVEN at dusk, and the clock resumes where it left off when
	the player comes back. Nothing on the race side had to be told about any of this.

	It also stands down while an admin has a sky STAGED (`WeatherController.debugStage`), which is
	the same situation without a race around it: the panel puts a race's weather up in the lobby to
	be looked at, and a cycle repainting over it every eighth of a second would make that useless.

	=== EXCEPT FOR A PRESS, WHICH GOES THROUGH IT RATHER THAN AROUND IT ========================

	Standing down answers a clock that is merely ADVANCING. It is the wrong answer to the player
	opening the settings screen mid-run and picking DAY, because that press has to be visible now or
	it is not a setting. The gear is on the topbar during a race even though `RaceEntryController`
	shuts the rail and every page at `RaceStart`, so this is an ordinary thing to do and not an edge
	case, and until `_rebase` existed the press was accepted, saved, and drawn on the screen while
	the road stayed exactly as dark as it was.

	`_rebase` does not break the arrangement above and that is the point of it: it hands the new look
	to `WeatherController.rebase`, which swaps it in as the base its event is composed over and
	repaints from there. Two files, one of them writing Lighting, exactly as before. What this file
	still writes on its own is its OWN grade, which that one has never touched.

	=== WHY LIGHTING IS SAFE TO WRITE ==========================================================

	Same reason `WeatherController` gives, and it is worth repeating because this file writes it far
	more often: `Lighting` is one shared instance, but a client writing its own is local to that
	client. Nobody else's sky moves. That is what lets the DAY and NIGHT settings be per player at
	all, and it is why there is no server side to this beyond remembering which one they picked.

	=== THE GRADE IS OURS ======================================================================

	The lobby's skybox is a painted texture and does not darken when the sun goes down, so the only
	thing that can make night look like night is post-processing over the whole frame. This creates
	its OWN `ColorCorrectionEffect` and never touches the one the place has authored, for the same
	reason `WeatherController` makes its own: the authored grade is the artist's baseline and the
	two compose cleanly, where sharing one instance would mean each file undoing the other's work.

	HOUSE RULE: no wiki-style double-bracket links in this comment, the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local DayNightConfig = require(ReplicatedStorage.shared.Configs.DayNightConfig)

local DayNightController = Shard.new("DayNightController")

--- Our own grade, by name, so a hot reload in Studio adopts the one it already made rather than
--- stacking a second effect on top of it.
local GRADE_NAME = "DayNightGrade"
local BLOOM_NAME = "DayNightBloom"
local SUN_RAYS_NAME = "DayNightSunRays"

--- ...and the Atmosphere we create only if the place has none. Named for the same reason.
local ATMOSPHERE_NAME = "DayNightAtmosphere"

--[[ How near the target the clock has to be, in game hours, for the glide to be over. A twentieth
	of an hour is two and a half minutes of game time, which at this cycle length is under two
	seconds of real time and is well below anything the eye resolves as a jump. ]]
local GLIDE_EPSILON = 0.05

type LightFixture = {
	NightBrightness: number,
	DayBrightness: number,
	NightEnabled: boolean,
}

type NeonFixture = {
	NightTransparency: number,
	DayTransparency: number,
}

local function finiteNumber(value: unknown, fallback: number): number
	if typeof(value) == "number" and value == value and math.abs(value) < math.huge then
		return value
	end
	return fallback
end

-- === The map's own sky ======================================================

--[[ Read what this place is lit as, once, and keep it. Every keyframe with an absent field blends
	against this, so a map re-lit tomorrow changes the whole cycle with no edit to the config.

	THE ATMOSPHERE IS THE AWKWARD ONE, exactly as it is for `WeatherController`: a place may or may
	not have one authored. Ours is adopted if it exists and created at the CLEAR settings if it does
	not, because an Atmosphere parented in at a real density is a wall of fog appearing on one frame.

	`Density` IS READ BUT NEVER WRITTEN. It is the weather's dial (a storm is mostly density) and a
	time of day has no business moving it. What this file animates is the colour of the air, not how
	much of it there is. ]]
function DayNightController._capture(self)
	if self._base then
		return
	end

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = ATMOSPHERE_NAME
		atmosphere.Density = 0
		atmosphere.Haze = 0
		atmosphere.Glare = 0
		atmosphere.Parent = Lighting
	end
	self._atmosphere = atmosphere

	local grade = Lighting:FindFirstChild(GRADE_NAME) :: ColorCorrectionEffect?
	if not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = GRADE_NAME
		grade.Parent = Lighting
	end
	local neutral = DayNightConfig.NeutralGrade
	grade.Brightness = neutral.Brightness
	grade.Contrast = neutral.Contrast
	grade.Saturation = neutral.Saturation
	grade.TintColor = neutral.Tint
	self._grade = grade

	local bloomCandidate = Lighting:FindFirstChild(BLOOM_NAME)
	local bloom: BloomEffect
	if bloomCandidate and bloomCandidate:IsA("BloomEffect") then
		bloom = bloomCandidate
	else
		bloom = Instance.new("BloomEffect")
		bloom.Name = BLOOM_NAME
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0
	bloom.Size = 24
	bloom.Threshold = 2
	self._bloom = bloom

	local raysCandidate = Lighting:FindFirstChild(SUN_RAYS_NAME)
	local rays: SunRaysEffect
	if raysCandidate and raysCandidate:IsA("SunRaysEffect") then
		rays = raysCandidate
	else
		rays = Instance.new("SunRaysEffect")
		rays.Name = SUN_RAYS_NAME
		rays.Parent = Lighting
	end
	rays.Intensity = 0
	rays.Spread = 0.8
	self._sunRays = rays

	self._base = {
		Ambient = Lighting.Ambient,
		Outdoor = Lighting.OutdoorAmbient,
		Brightness = Lighting.Brightness,
		Exposure = Lighting.ExposureCompensation,
		ColorShiftTop = Lighting.ColorShift_Top,
		ColorShiftBottom = Lighting.ColorShift_Bottom,
		ShadowSoftness = Lighting.ShadowSoftness,
		EnvironmentDiffuse = Lighting.EnvironmentDiffuseScale,
		EnvironmentSpecular = Lighting.EnvironmentSpecularScale,
		Atmosphere = {
			Color = atmosphere.Color,
			Decay = atmosphere.Decay,
			Glare = atmosphere.Glare,
			Haze = atmosphere.Haze,
		},
		Bloom = { Intensity = 0, Size = 24, Threshold = 2 },
		SunRays = { Intensity = 0, Spread = 0.8 },
	}
end

-- === Authored night fixtures ===============================================

--[[ Only tagged art participates. This keeps vehicle headlights and gameplay lights out of a
	presentation system while allowing lamps streamed in later to join automatically. Attributes
	are optional overrides; without them the values present when the tag is observed are the night
	look and the config supplies the daytime look. ]]
function DayNightController._trackFixture(self, instance: Instance, fixtureKind: string)
	local fixture = DayNightConfig.Fixtures
	if fixtureKind == "Light" and instance:IsA("Light") then
		local nightBrightness = math.max(0, finiteNumber(instance:GetAttribute("NightBrightness"), instance.Brightness))
		local dayBrightness = math.max(0, finiteNumber(instance:GetAttribute("DayBrightness"), nightBrightness * fixture.DayBrightnessScale))
		self._nightLights[instance] = {
			NightBrightness = nightBrightness,
			DayBrightness = dayBrightness,
			NightEnabled = instance.Enabled,
		}
	elseif fixtureKind == "Neon" and instance:IsA("BasePart") then
		local nightTransparency = math.clamp(finiteNumber(instance:GetAttribute("NightTransparency"), instance.Transparency), 0, 1)
		local dayTransparency = math.clamp(finiteNumber(instance:GetAttribute("DayTransparency"), math.max(nightTransparency, fixture.DayNeonTransparency)), 0, 1)
		self._nightNeons[instance] = {
			NightTransparency = nightTransparency,
			DayTransparency = dayTransparency,
		}
	else
		return
	end

	-- Force one repaint so a newly streamed fixture does not wait for the sun to move perceptibly.
	self._lastFixtureAmount = nil
end

function DayNightController._untrackFixture(self, instance: Instance, fixtureKind: string)
	if fixtureKind == "Light" then
		local light = self._nightLights[instance]
		if light and instance:IsA("Light") then
			instance.Brightness = light.NightBrightness
			instance.Enabled = light.NightEnabled
		end
		self._nightLights[instance] = nil
	end

	if fixtureKind == "Neon" then
		local neon = self._nightNeons[instance]
		if neon and instance:IsA("BasePart") then
			instance.Transparency = neon.NightTransparency
		end
		self._nightNeons[instance] = nil
	end
end

function DayNightController._restoreFixtures(self)
	for light, values in self._nightLights do
		if light.Parent then
			light.Brightness = values.NightBrightness
			light.Enabled = values.NightEnabled
		end
	end
	table.clear(self._nightLights)

	for part, values in self._nightNeons do
		if part.Parent then
			part.Transparency = values.NightTransparency
		end
	end
	table.clear(self._nightNeons)
	self._lastFixtureAmount = nil
end

function DayNightController._applyFixtures(self, clock: number)
	if not DayNightConfig.Fixtures.Enabled then
		return
	end

	local amount = DayNightConfig.nightAmount(clock)
	local previous = self._lastFixtureAmount
	if previous ~= nil and math.abs(previous - amount) < 0.001 then
		return
	end
	self._lastFixtureAmount = amount

	for light, values in self._nightLights do
		if light.Parent then
			local brightness = values.DayBrightness + (values.NightBrightness - values.DayBrightness) * amount
			light.Brightness = brightness
			light.Enabled = values.NightEnabled and brightness > 0.01
		else
			self._nightLights[light] = nil
		end
	end

	for part, values in self._nightNeons do
		if part.Parent then
			part.Transparency = values.DayTransparency + (values.NightTransparency - values.DayTransparency) * amount
		else
			self._nightNeons[part] = nil
		end
	end
end

-- === Painting ===============================================================

--- Put the sky at `clock`. The only function in this file that writes anything to Lighting.
function DayNightController._apply(self, clock: number)
	local base = self._base
	if not base then
		return
	end

	local look = DayNightConfig.lookAt(clock, base)

	Lighting.ClockTime = clock % 24
	Lighting.Ambient = look.Ambient
	Lighting.OutdoorAmbient = look.Outdoor
	Lighting.Brightness = look.Brightness
	Lighting.ExposureCompensation = look.Exposure
	Lighting.ColorShift_Top = look.ColorShiftTop
	Lighting.ColorShift_Bottom = look.ColorShiftBottom
	Lighting.ShadowSoftness = look.ShadowSoftness
	Lighting.EnvironmentDiffuseScale = look.EnvironmentDiffuse
	Lighting.EnvironmentSpecularScale = look.EnvironmentSpecular

	local air = self._atmosphere
	if air and air.Parent then
		air.Color = look.Atmosphere.Color
		air.Decay = look.Atmosphere.Decay
		air.Glare = look.Atmosphere.Glare
		air.Haze = look.Atmosphere.Haze
	end

	local grade = self._grade
	if grade and grade.Parent then
		grade.Brightness = look.Grade.Brightness
		grade.Contrast = look.Grade.Contrast
		grade.Saturation = look.Grade.Saturation
		grade.TintColor = look.Grade.Tint
	end

	local bloom = self._bloom
	if bloom and bloom.Parent then
		bloom.Intensity = look.Bloom.Intensity
		bloom.Size = look.Bloom.Size
		bloom.Threshold = look.Bloom.Threshold
	end

	local rays = self._sunRays
	if rays and rays.Parent then
		rays.Intensity = look.SunRays.Intensity
		rays.Spread = look.SunRays.Spread
	end

	self:_applyFixtures(clock)
end

--[[ Whether something else owns the sky right now, and this one has to keep its hands off it.

	TWO CASES AND THEY ARE THE SAME CASE: a real race, and an admin previewing a race's weather in
	the lobby. Both mean `WeatherController` has captured Lighting and is animating it, and both end
	with it restoring exactly what it captured, which is whatever this file had frozen.

	The staged check is a read of that controller's own public accessor rather than a flag it sets
	on us, so an admin panel that grows a fourth button cannot forget to tell us about it. ]]
function DayNightController._standingDown(self): boolean
	if self._racing and DayNightConfig.PauseDuringRace then
		return true
	end

	local weather = self:_weatherController()
	if weather and weather.debugState then
		return weather:debugState().staged == true
	end
	return false
end

--- `WeatherController`, looked up once and kept. Two callers now, one of them eight times a second,
--- which is what makes it worth a line of its own rather than a registry lookup at each.
function DayNightController._weatherController(self)
	local weather = self._weather
	if not weather then
		weather = Shard.get("WeatherController")
		self._weather = weather
	end
	return weather
end

--[[ Put the sky where the preference now asks WITHOUT writing Lighting, by handing the new look to
	whoever is holding it. The answer to a press that arrives while this file is standing down.

	THE CLOCK IS MOVED HERE TOO, and that is the half that is easy to miss. `_clock` is this file's
	idea of where the sky is and it has been frozen since `RaceStart`. Leaving it at the old hour
	would have `_onRaceEnd` glide the sun from the sky the player stopped looking at to the one they
	have been looking at for the whole run, which is up to a twelve hour swing over a lobby that is
	already correct. Setting it to the target is what makes the handover back a no-op.

	IT FALLS BACK TO WRITING LIGHTING ITSELF when there is nothing to rebase onto, which means
	weather is switched off or captured nothing. That is exactly the case where nobody else is
	animating it, so writing is safe here rather than a fight. ]]
function DayNightController._rebase(self)
	local base = self._base
	if not base then
		return
	end

	local target = DayNightConfig.clockFor(self._preference)
	local look = DayNightConfig.lookAt(target, base)
	local seconds = DayNightConfig.GlideSeconds

	self._clock = target
	self._glideLeft = 0

	local weather = self:_weatherController()
	local taken = false
	if weather and weather.rebase then
		taken = weather:rebase({
			Clock = target,
			Ambient = look.Ambient,
			Outdoor = look.Outdoor,
			Brightness = look.Brightness,
			Atmosphere = look.Atmosphere,
		}, seconds) == true
	end

	if not taken then
		self:_apply(target)
		return
	end

	--[[ Weather owns its captured sky fields, but deliberately does not touch this controller's
		post effects or the independent Lighting accents. Carry those through the same glide here. ]]
	self:_tweenAccents(look, target, seconds)
end

--[[ Move our local post effects and non-weather Lighting properties over `seconds`. This is the
	one place the clock is not stepping: during a run `_apply` is not being called and there is
	nothing to carry the change a frame at a time.

	KEPT SO IT CAN BE CANCELLED. `_apply` resuming at the end of a run writes these same properties
	eight times a second, and a tween still running would spend its remainder undoing
	each write. ]]
function DayNightController._tweenAccents(self, look: any, clock: number, seconds: number)
	self:_cancelAccentTweens()

	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local function play(instance: Instance, properties: { [string]: any })
		if not instance.Parent then
			return
		end
		local tween = TweenService:Create(instance, info, properties)
		table.insert(self._accentTweens, tween)
		tween:Play()
	end

	play(Lighting, {
		ExposureCompensation = look.Exposure,
		ColorShift_Top = look.ColorShiftTop,
		ColorShift_Bottom = look.ColorShiftBottom,
		ShadowSoftness = look.ShadowSoftness,
		EnvironmentDiffuseScale = look.EnvironmentDiffuse,
		EnvironmentSpecularScale = look.EnvironmentSpecular,
	})

	local grade = self._grade
	if grade then
		play(grade, {
			Brightness = look.Grade.Brightness,
			Contrast = look.Grade.Contrast,
			Saturation = look.Grade.Saturation,
			TintColor = look.Grade.Tint,
		})
	end

	local bloom = self._bloom
	if bloom then
		play(bloom, {
			Intensity = look.Bloom.Intensity,
			Size = look.Bloom.Size,
			Threshold = look.Bloom.Threshold,
		})
	end

	local rays = self._sunRays
	if rays then
		play(rays, {
			Intensity = look.SunRays.Intensity,
			Spread = look.SunRays.Spread,
		})
	end

	self._lastFixtureAmount = nil
	self:_applyFixtures(clock)
end

--- Stop a rebase's accent tweens if they are running. Safe to call when there are not.
function DayNightController._cancelAccentTweens(self)
	for _, tween in self._accentTweens do
		pcall(function()
			tween:Cancel()
		end)
	end
	table.clear(self._accentTweens)
end

--[[ One step of the clock, at `DayNightConfig.UpdateHz`.

	THE TARGET IS RE-READ EVERY STEP AND THE GLIDE CHASES IT, rather than being computed once when
	the glide starts. In AUTO the target is still moving while the glide runs, and a glide that
	aimed at where the sun WAS two seconds ago would land two seconds behind and then jump. The
	alpha is `dt / whatever is left`, which lands exactly on a moving target at exactly the moment
	the glide is due to be over.

	IT DOES NOT EASE, and that is on purpose: what a glide looks like is the sun moving fast, and a
	sun that slows down as it arrives somewhere is the one thing a sun never does. ]]
function DayNightController._step(self, dt: number)
	if self:_standingDown() then
		return
	end

	local target = DayNightConfig.clockFor(self._preference)
	local step = DayNightConfig.shortestStep(self._clock, target)

	if self._glideLeft > 0 and math.abs(step) > GLIDE_EPSILON then
		local alpha = math.clamp(dt / math.max(self._glideLeft, dt), 0, 1)
		self._clock = (self._clock + step * alpha) % 24
		self._glideLeft -= dt
	else
		self._glideLeft = 0
		self._clock = target
	end

	self:_apply(self._clock)
end

--- Start a glide from wherever the sky is now to wherever it should be. Called for every JUMP: a
--- press, the seed, and the end of a race. Never called by `_step`, which is what the clock doing
--- its ordinary business looks like.
function DayNightController._glide(self)
	self._glideLeft = DayNightConfig.GlideSeconds
end

-- === The setting ============================================================

--- Public: which of the three this player is on. The settings page puts its toggle on this.
function DayNightController.preference(self): string
	return self._preference
end

--- Public: the hour the sky is showing right now, for anything that wants to say so.
function DayNightController.clock(self): number
	return self._clock
end

--[[ Public (`UIController/Pages/Settings`): pick one of the three.

	`persist` is what separates a press from the seed, and it is the same split the music mute
	makes for the same reason: a press is the player's decision and is sent to the server to be
	saved, where the seed IS the server's saved answer arriving and must not be sent straight back.

	APPLIED INSTANTLY AND TOLD TO THE SERVER AFTERWARDS. There is no ruling to make about which sky
	somebody looks at, so waiting for a round trip would only put a delay on a button. ]]
function DayNightController.setPreference(self, preference: unknown, persist: boolean?)
	local key = DayNightConfig.resolve(preference)
	if key == self._preference and self._appliedOnce then
		return
	end

	self._preference = key
	self._appliedOnce = true

	--[[ A PRESS DURING A RUN IS A REBASE AND NOT A GLIDE. `_step` is standing down and will not
		paint anything until the run is over, so arming a glide here would record the answer, publish
		it, save it, and leave the player looking at the sky they just changed. The settings screen
		is reachable from the topbar gear mid-race even though the rail and every page are not, so
		this is an ordinary press rather than an edge case. ]]
	if self:_standingDown() then
		self:_rebase()
	else
		self:_glide()
	end

	Dispatcher:Publish(DayNightConfig.StateEvent, key)

	if persist then
		self._touched = true
		self:getRemoteEvent(DayNightConfig.RemoteName):Fire(key)
	end
end

--[[ Take the server's saved answer, once.

	IGNORED IF THE PLAYER HAS ALREADY PICKED (`_touched`), for the reason the music seed gives: a
	profile that loads slowly can land after an impatient player has chosen NIGHT, and adopting it
	then would put them back on AUTO. The save arriving would undo the press that is about to be
	saved. ]]
function DayNightController._seed(self, preference: unknown)
	if self._seeded or self._touched then
		return
	end
	self._seeded = true

	--[[ Always through `setPreference`, even when the saved answer is the AUTO this client already
		had. `_appliedOnce` is still false at this point, so the early return in there does not
		catch it and the state event goes out either way: a screen drawn from that event needs to
		hear that the answer is now the server's rather than the default. ]]
	self:setPreference(preference, false)
end

--- The run's brackets. Two lines each, and both of them are about NOT writing the sky.
function DayNightController._onRaceStart(self)
	self._racing = true
end

function DayNightController._onRaceEnd(self)
	self._racing = false
	--- Ours, and finished with: `_apply` is about to start writing these properties again.
	self:_cancelAccentTweens()
	--[[ Glide rather than snap. The clock has kept running in real terms for the length of the run,
		so resuming is a jump of however long the race was, and the race's own fade is still over
		the screen while it happens.

		A run that was REBASED mid-way has nothing left to glide on the two locked answers, because
		`_rebase` already moved `_clock` to where the sky is. This still runs and still costs
		nothing: `_step` finds the step below its epsilon and snaps to a target it is already at. ]]
	self:_glide()
end

-- === Lifecycle ==============================================================

DayNightController:withRemoteEvents({
	{
		--[[ The run's brackets, and the only two things that take the sky away from this file. The
			seed and the world are not read: what the sky does during a race is not this file's
			business, it is `WeatherController`'s. ]]
		RaceStart = function()
			DayNightController:_onRaceStart()
		end,
		RaceEnd = function()
			DayNightController:_onRaceEnd()
		end,
	},
	DayNightConfig.RemoteName,
})

DayNightController:withLifecycle({
	init = function(self)
		self._trove = Trove.new()
		self._base = nil :: any
		self._atmosphere = nil :: Atmosphere?
		self._grade = nil :: ColorCorrectionEffect?
		self._bloom = nil :: BloomEffect?
		self._sunRays = nil :: SunRaysEffect?
		self._nightLights = {} :: { [Light]: LightFixture }
		self._nightNeons = {} :: { [BasePart]: NeonFixture }
		self._lastFixtureAmount = nil :: number?
		self._preference = DayNightConfig.Preference.Auto
		self._clock = 12
		self._glideLeft = 0
		self._racing = false
		self._accumulator = 0
		--- A rebase's local-effect tweens, while they are running. See `_tweenAccents`.
		self._accentTweens = {} :: { Tween }
		--- Looked up once on first use and kept, so `_standingDown` is not a registry lookup eight
		--- times a second.
		self._weather = nil :: any
		--[[ The same pair the music mute keeps, and for the same reason: `_seeded` is the server
			having answered, `_touched` is the player having pressed first, and a seed that arrives
			after a press is dropped. ]]
		self._seeded = false
		self._touched = false
		self._appliedOnce = false
	end,

	start = function(self)
		if not DayNightConfig.Enabled then
			return
		end

		self:_capture()

		local fixture = DayNightConfig.Fixtures
		if fixture.Enabled then
			for _, instance in CollectionService:GetTagged(fixture.LightTag) do
				self:_trackFixture(instance, "Light")
			end
			for _, instance in CollectionService:GetTagged(fixture.NeonTag) do
				self:_trackFixture(instance, "Neon")
			end

			self._trove:Add(CollectionService:GetInstanceAddedSignal(fixture.LightTag):Connect(function(instance)
				self:_trackFixture(instance, "Light")
			end))
			self._trove:Add(CollectionService:GetInstanceRemovedSignal(fixture.LightTag):Connect(function(instance)
				self:_untrackFixture(instance, "Light")
			end))
			self._trove:Add(CollectionService:GetInstanceAddedSignal(fixture.NeonTag):Connect(function(instance)
				self:_trackFixture(instance, "Neon")
			end))
			self._trove:Add(CollectionService:GetInstanceRemovedSignal(fixture.NeonTag):Connect(function(instance)
				self:_untrackFixture(instance, "Neon")
			end))
		end

		--[[ Open on the RIGHT sky rather than on noon and a glide. A player joining at 3am should
			load into 3am: gliding there from noon would show them fifteen hours of sun in two
			seconds before the game had drawn anything else. ]]
		self._clock = DayNightConfig.clockFor(self._preference)
		self:_apply(self._clock)

		local player = Players.LocalPlayer

		--- The seed, whichever way round the attribute and this controller arrive in. Same shape as
		--- the music mute's, including the floor under it.
		local existing = player:GetAttribute(DayNightConfig.Attribute)
		if existing ~= nil then
			self:_seed(existing)
		else
			local connection
			connection = player:GetAttributeChangedSignal(DayNightConfig.Attribute):Connect(function()
				connection:Disconnect()
				self:_seed(player:GetAttribute(DayNightConfig.Attribute))
			end)

			--[[ ...and the floor. A profile that never loads or a server with the service switched
				off would otherwise leave this listening forever, which costs nothing but leaves the
				settings screen unable to say the answer is settled. AUTO is what an unanswered
				player was already on, so nothing moves. ]]
			task.delay(DayNightConfig.SeedTimeout, function()
				if not self._seeded and not self._touched then
					connection:Disconnect()
					self:_seed(DayNightConfig.Preference.Auto)
				end
			end)
		end

		--[[ Heartbeat rather than RenderStepped, and throttled on top of that. Nothing here has to
			be in step with the camera: the clock moves 0.027 game hours a second, so eight writes a
			second is a change of 0.003 per write and the stair is far below what the eye resolves.
			See `DayNightConfig.UpdateHz` for the cost this is avoiding. ]]
		local period = 1 / math.max(DayNightConfig.UpdateHz, 1)
		self._trove:Add(RunService.Heartbeat:Connect(function(dt)
			self._accumulator += dt
			if self._accumulator < period then
				return
			end
			local elapsed = self._accumulator
			self._accumulator = 0
			self:_step(elapsed)
		end))
	end,
})

DayNightController:withCleanup(function()
	DayNightController:_cancelAccentTweens()
	DayNightController:_restoreFixtures()
	if DayNightController._trove then
		DayNightController._trove:Destroy()
	end
end)

return DayNightController
