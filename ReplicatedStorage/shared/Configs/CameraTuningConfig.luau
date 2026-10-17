--[[
	CameraTuningConfig
	------------------
	THE CAMERA BENCH. Two things a test build needs that the shipping game does not: a short list of
	whole camera SHOTS a tester can step between from the settings screen, and the full rack of every
	value behind them, live, on sliders, in the admin panel.

	Read by `CameraTuningController`, which owns every write; by `Modules/SettingsRows`, which turns
	the presets into one row on the settings screen; and by `AdminPanelController`, which draws the
	rack. Nothing in the game reads this file, and that is the property worth keeping: the camera
	never asks whether it is being tuned.

	=== IT IS `TuningConfig`'S ARGUMENT, TAKEN FURTHER ======================================

	`TuningConfig` is the rack of A/B knobs, and its header makes the case that a knob should write
	the value the feature already reads rather than teaching the feature a second way to be
	configured. Everything here works the same way: a preset is a list of writes into `CameraConfig`,
	a slider is one write into `CameraConfig`, and `RaceCameraController` is untouched by both.

	What this adds is range. A knob answers one question with two or three answers. A tester asked to
	say which camera feels right needs to move numbers nobody thought to ask him about, and a boss
	shown the game for twenty minutes needs six named shots and no numbers at all. So there are two
	faces on one rack: the presets, which go on the settings screen, and the fields, which go in the
	panel.

	=== THE ONE RULE IS STILL THE ONE RULE ==================================================

	EVERY FIELD NAMED BELOW IS READ LIVE. `RaceCameraController` pulls each of them inside a render
	step, or for the hit and pass entries inside the call that reacts to one, so a write lands on the
	next frame and a slider feels like a slider. A value captured into a local at require time, or
	applied once when a race starts, would sit there unchanged and the control would look broken.
	That is the one way to get this wrong, and it is the thing to check before adding a field.

	The second thing to check is the RANGE. These are sliders, and a slider will be dragged to its
	end, so an end has to be a shot rather than a bug. `Min` and `Max` below are picked to be
	survivable rather than to be the whole of what a field could hold: nothing here can put the lens
	inside the deck or hand the camera a divide by zero.

	=== A PRESET IS A WHOLE SHOT, NOT A DIFF FROM WHATEVER IS ON SCREEN =====================

	`CameraTuningController.applyPreset` restores every field to what this build shipped and then
	writes the preset's `Set` over the top. So a preset means the same thing whatever was pressed
	before it, "Default" is the shipped shot exactly, and a field no preset mentions is the shipped
	value rather than a leftover from the last one.

	THE VALUES IN A `Set` ARE LITERAL AND NOT SHARES, which is the opposite of the rule `TuningConfig`
	argues for at length, and the difference is what a preset IS. A knob asks for a bit more or a bit
	less of what we ship, so a share is right there and a copied number would go stale. A preset is a
	shot somebody composed: Bumper is eleven studs in front of the car's middle because that is where
	the bonnet is, and scaling that by whatever `Distance` happens to be this week would put the lens
	somewhere nobody chose.

	=== NOTHING IS SAVED ====================================================================

	Same answer and the same reason as `TuningConfig`. Every session starts on Default, so two
	testers reporting on one build are reporting on one game, and rejoining is the reset. The way a
	tuned shot comes back to the repo is the report (`CameraTuningController.report`), which prints
	the assignments that differ from the shipped build in the form they would be pasted into
	`CameraConfig`.

	`Enabled = false` takes the settings row and the panel tab off and leaves `CameraConfig`
	untouched, which is what a shipping build wants.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- The one config this bench writes. A leaf table that requires nothing, so this file cannot be the
--- middle of a cycle however early a screen asks for it. The same argument `TuningConfig` makes.
local CameraConfig = require(ReplicatedStorage.shared.Configs.CameraConfig)

local CameraTuningConfig = {}

--[[ Master switch. Off = no "Camera mode" row on the settings screen, no Camera tab in the admin
	panel, no baselines captured and nothing written. Turn it off for a public build. ]]
CameraTuningConfig.Enabled = true

--- Published on the client whenever a preset or a field moves, so an open settings screen and an
--- open panel repaint from the controller rather than from their own copies. The same contract as
--- `TuningConfig.StateEvent`.
CameraTuningConfig.StateEvent = "CameraTuningState"

CameraTuningConfig.Copy = {
	--[[ The settings row. "Mode" rather than "Camera", because the row sits under "Time of day" and
		"Hide UI" and has to read as the same kind of thing: a noun with a state beside it. What the
		state says is the preset's `Name`, so those are the words carrying the meaning and they are
		kept to one or two. ]]
	Row = "Camera mode",
	--- The panel tab, and what anything that has to SAY the bench's name uses.
	Tab = "Camera",
}

-- === The fields =============================================================

export type Kind = "number" | "boolean"

export type Field = {
	--- Stable name, and the vocabulary a preset's `Set` is written in. Never shown.
	Key: string,
	--- What the control prints.
	Label: string,
	--- Which group it is drawn under, matching an entry in `Groups`.
	Group: string,
	--- The field inside `CameraConfig`, as the path to walk.
	Path: { string },
	Kind: Kind,
	--- Numbers only. `Step` is the slider's grain as well as the amount an arrow key moves it.
	Min: number?,
	Max: number?,
	Step: number?,
	--- Numbers only. `string.format` pattern for the value drawn on the grip.
	Format: string?,
	--- One line under the control, where the label alone does not say enough.
	Hint: string?,
}

--- The order the groups are drawn in, which is roughly the order `CameraConfig` sets them out and
--- the order somebody tuning a shot reaches for them: where it sits, then how it turns, then how it
--- follows, then the garnish.
CameraTuningConfig.Groups = {
	"Shot",
	"First person",
	"Low chase",
	"Turning",
	"Follow",
	"Speed",
	"Juice",
	"Hits",
	"Passes",
	"Nitro",
	"Bridges",
	"Bail",
}

local FIELDS: { Field } = {
	-- === Shot =================================================================
	{
		Key = "Distance",
		Label = "Distance back",
		Group = "Shot",
		Path = { "Distance" },
		Kind = "number",
		Min = -25,
		Max = 70,
		Step = 0.5,
		Format = "%.1f",
		Hint = "Studs behind the car. NEGATIVE puts the lens in front of the car's middle, which is how Bumper gets onto the bonnet. Past about -11 you stop seeing your own car at all.",
	},
	{
		Key = "Height",
		Label = "Height",
		Group = "Shot",
		Path = { "Height" },
		Kind = "number",
		Min = 2,
		Max = 45,
		Step = 0.5,
		Format = "%.1f",
		Hint = "Studs above the deck. IGNORED while Low chase is on, which is how this build ships.",
	},
	{
		Key = "PitchDeg",
		Label = "Pitch down",
		Group = "Shot",
		Path = { "PitchDeg" },
		Kind = "number",
		Min = -10,
		Max = 45,
		Step = 0.5,
		Format = "%.1f",
		Hint = "Degrees the lens tilts down. Also ignored while Low chase is on.",
	},
	{
		Key = "FieldOfView",
		Label = "Field of view",
		Group = "Shot",
		Path = { "FieldOfView" },
		Kind = "number",
		Min = 40,
		Max = 110,
		Step = 1,
		Format = "%.0f",
		Hint = "The resting lens, before speed and nitro add to it. 70 is the Roblox default.",
	},
	{
		Key = "LateralFollow",
		Label = "Lane framing",
		Group = "Shot",
		Path = { "LateralFollow" },
		Kind = "number",
		Min = 0,
		Max = 1,
		Step = 0.05,
		Format = "%.2f",
		Hint = "1 sits the shot directly behind the car. Below 1 it hangs back toward the road's centre line and the car ranges across the frame on its own.",
	},

	-- === First person =========================================================
	--[[ The experiment (`CameraConfig.FirstPerson`). The flag is here and NOT in a preset on purpose:
		a preset lands on the settings screen for every tester, and this is a shot to be shown to
		people, not found. Admins also have the V key for it mid-race. ]]
	{
		Key = "FirstPersonEnabled",
		Label = "First person",
		Group = "First person",
		Path = { "FirstPerson", "Enabled" },
		Kind = "boolean",
		Hint = "The view from the driver's seat, in the car's own cabin (or under the rarity cockpit, below). Admins can also press V in a race. Lands on the next frame, in or out of a run.",
	},
	{
		Key = "FirstPersonEyeHeight",
		Label = "Eye height",
		Group = "First person",
		Path = { "FirstPerson", "EyeHeight" },
		Kind = "number",
		Min = 1.4,
		Max = 4.5,
		Step = 0.05,
		Format = "%.2f",
		Hint = "Studs over the seat pad. A low roof pulls it down (Roof clearance) and the car's own wheel holds it up (Over the wheel), so this is the height in a roomy car.",
	},
	{
		Key = "FirstPersonOverWheel",
		Label = "Over the wheel",
		Group = "First person",
		Path = { "FirstPerson", "OverWheel" },
		Kind = "number",
		Min = 0,
		Max = 1.5,
		Step = 0.05,
		Format = "%.2f",
		Hint = "The eye never sits lower than this over the top of the car's own steering wheel, whatever the roof says. Under the rim there is no road in the shot.",
	},
	{
		Key = "FirstPersonPitchDownDeg",
		Label = "Look down",
		Group = "First person",
		Path = { "FirstPerson", "PitchDownDeg" },
		Kind = "number",
		Min = -5,
		Max = 20,
		Step = 0.5,
		Format = "%.1f",
		Hint = "Degrees below level. More shows road and wheel, less shows sky and headliner.",
	},
	{
		Key = "FirstPersonEyeForward",
		Label = "Eye forward",
		Group = "First person",
		Path = { "FirstPerson", "EyeForward" },
		Kind = "number",
		Min = -0.5,
		Max = 1.5,
		Step = 0.05,
		Format = "%.2f",
		Hint = "Studs ahead of the seat pad. Further forward puts more of the bonnet in frame and less of the pillars.",
	},
	{
		Key = "FirstPersonRoofClearance",
		Label = "Roof clearance",
		Group = "First person",
		Path = { "FirstPerson", "RoofClearance" },
		Kind = "number",
		Min = 0,
		Max = 2.5,
		Step = 0.05,
		Format = "%.2f",
		Hint = "The eye stays at least this far under the body's roofline, which only bites in the low supercars. Over the wheel wins if the two disagree.",
	},
	{
		Key = "FirstPersonFieldOfView",
		Label = "Field of view",
		Group = "First person",
		Path = { "FirstPerson", "FieldOfView" },
		Kind = "number",
		Min = 55,
		Max = 115,
		Step = 1,
		Format = "%.0f",
		Hint = "The resting lens in the seat, before speed and nitro add to it. Wider sells speed and shows more wheel.",
	},
	{
		Key = "FirstPersonSpeedFovDeg",
		Label = "Speed lens",
		Group = "First person",
		Path = { "FirstPerson", "SpeedFovDeg" },
		Kind = "number",
		Min = 0,
		Max = 30,
		Step = 0.5,
		Format = "%.1f",
		Hint = "Extra degrees at the car's ceiling.",
	},
	{
		Key = "FirstPersonHeadingGain",
		Label = "Heading follow",
		Group = "First person",
		Path = { "FirstPerson", "HeadingGain" },
		Kind = "number",
		Min = 0,
		Max = 40,
		Step = 0.5,
		Format = "%.1f",
		Hint = "How fast the view follows the car's heading. 0 is welded to the car. Lower lets the pillars slide a little in a turn, like a head lagging the car.",
	},
	{
		Key = "FirstPersonLookIntoTurnDeg",
		Label = "Look into turn",
		Group = "First person",
		Path = { "FirstPerson", "LookIntoTurnDeg" },
		Kind = "number",
		Min = 0,
		Max = 20,
		Step = 0.5,
		Format = "%.1f",
		Hint = "Degrees the eyes turn toward the steer at full lock.",
	},
	{
		Key = "FirstPersonTiltShare",
		Label = "Body tilt share",
		Group = "First person",
		Path = { "FirstPerson", "TiltShare" },
		Kind = "number",
		Min = 0,
		Max = 1,
		Step = 0.05,
		Format = "%.2f",
		Hint = "How much of the chassis's roll and pitch the eye takes. 1 is welded to the body, 0 keeps the horizon level however the suspension moves.",
	},
	{
		Key = "FirstPersonCockpit",
		Label = "Cockpit overlay",
		Group = "First person",
		Path = { "FirstPerson", "Cockpit" },
		Kind = "boolean",
		Hint = "The drawn rarity dash and wheel, the same in every car of a rarity. Off (the default) shows the car's own cabin.",
	},
	{
		Key = "FirstPersonTurnSteeringWheel",
		Label = "Turn the car's own wheel",
		Group = "First person",
		Path = { "FirstPerson", "TurnSteeringWheel" },
		Kind = "boolean",
		Hint = "With the overlay off, the car's own steering wheel turns with the steer. Off leaves it still. Lambo, Maybach, Car1 and TestCar have no wheel part to turn.",
	},
	{
		Key = "FirstPersonHands",
		Label = "Hands on the wheel",
		Group = "First person",
		Path = { "FirstPerson", "Hands" },
		Kind = "boolean",
		Hint = "The player's own arms, in their shirt, holding the wheel: the drawn one with the overlay on, the car's own with it off.",
	},
	{
		Key = "FirstPersonCabin",
		Label = "Black cabin",
		Group = "First person",
		Path = { "FirstPerson", "Cabin" },
		Kind = "boolean",
		Hint = "The car's insides redrawn black with no side or rear-view mirrors, baked per car. Off shows the car's own cabin as it was: painted insides, mirrors and all.",
	},
	{
		Key = "FirstPersonCabinDetail",
		Label = "Cabin detail",
		Group = "First person",
		Path = { "FirstPerson", "CabinDetail" },
		Kind = "boolean",
		Hint = "On the black cabin: the car's own door mirrors and a rear-view mirror, gauges behind the wheel that follow the car, a radio screen showing the soundtrack, vents. Off is the bare black cabin.",
	},

	-- === Low chase ============================================================
	{
		Key = "LowChaseEnabled",
		Label = "Low chase",
		Group = "Low chase",
		Path = { "LowChase", "Enabled" },
		Kind = "boolean",
		Hint = "On swaps the two below in for Height and Pitch, and holds the bridge duck off, since the shot is then already down where the duck would put it.",
	},
	{
		Key = "LowChaseHeight",
		Label = "Low height",
		Group = "Low chase",
		Path = { "LowChase", "Height" },
		Kind = "number",
		Min = 2,
		Max = 30,
		Step = 0.5,
		Format = "%.1f",
	},
	{
		Key = "LowChasePitchDeg",
		Label = "Low pitch down",
		Group = "Low chase",
		Path = { "LowChase", "PitchDeg" },
		Kind = "number",
		Min = -10,
		Max = 40,
		Step = 0.5,
		Format = "%.1f",
	},

	-- === Turning ==============================================================
	{
		Key = "YawFollow",
		Label = "Swing",
		Group = "Turning",
		Path = { "YawFollow" },
		Kind = "number",
		Min = 0,
		Max = 1,
		Step = 0.05,
		Format = "%.2f",
		Hint = "The camera's share of the car's heading. 0 is the fixed corridor shot exactly. 1 lines the frame up with the nose, so the car looks square in frame and only the world turns.",
	},
	{
		Key = "YawMaxDeg",
		Label = "Swing cap",
		Group = "Turning",
		Path = { "YawMaxDeg" },
		Kind = "number",
		Min = 0,
		Max = 45,
		Step = 1,
		Format = "%.0f",
		Hint = "Degrees, whatever the heading does. Set under the car's own steering angle and the car keeps rotating inside the shot after the frame has stopped.",
	},
	{
		Key = "YawGain",
		Label = "Swing response",
		Group = "Turning",
		Path = { "YawGain" },
		Kind = "number",
		Min = 0,
		Max = 25,
		Step = 0.5,
		Format = "%.1f",
		Hint = "How fast the swing closes, per second. High reads responsive and slightly mechanical, low lets the frame settle a beat after you straighten up. Too low and the rotation arrives after the turn is over.",
	},
	{
		Key = "RollDeg",
		Label = "Bank",
		Group = "Turning",
		Path = { "RollDeg" },
		Kind = "number",
		Min = -8,
		Max = 8,
		Step = 0.25,
		Format = "%.2f",
		Hint = "Degrees of roll at a full swing. Positive leans INTO the turn, which is the arcade convention. Negative leans out of it, mimicking the car's own body roll.",
	},

	-- === Follow ===============================================================
	{
		Key = "AlongGain",
		Label = "Along the road",
		Group = "Follow",
		Path = { "AlongGain" },
		Kind = "number",
		Min = 1,
		Max = 40,
		Step = 0.5,
		Format = "%.1f",
		Hint = "Higher is tighter. The shot rests speed/gain studs back from where it wants to be, so at 85 studs/s a gain of 20 trails by 4.3.",
	},
	{
		Key = "LateralGain",
		Label = "Across the road",
		Group = "Follow",
		Path = { "LateralGain" },
		Kind = "number",
		Min = 1,
		Max = 40,
		Step = 0.5,
		Format = "%.1f",
		Hint = "The one the player actually feels, because weaving is the whole input. Low reads loose and drifty. Past about 15 a lane change stops reading at all.",
	},
	{
		Key = "HeightGain",
		Label = "Vertical",
		Group = "Follow",
		Path = { "HeightGain" },
		Kind = "number",
		Min = 1,
		Max = 25,
		Step = 0.5,
		Format = "%.1f",
		Hint = "Deliberately the softest of the three. The deck is flat, so a stiff gain here turns every jump and every bit of suspension into a camera bounce.",
	},
	{
		Key = "JumpFollow",
		Label = "Air time",
		Group = "Follow",
		Path = { "JumpFollow" },
		Kind = "number",
		Min = 0,
		Max = 1,
		Step = 0.05,
		Format = "%.2f",
		Hint = "Share of the car's height above the deck the shot climbs with it. 1 hides the jump, since nothing moves in frame. 0 drops the car off the bottom of the screen.",
	},
	{
		Key = "MaxJumpFollowStuds",
		Label = "Air time ceiling",
		Group = "Follow",
		Path = { "MaxJumpFollowStuds" },
		Kind = "number",
		Min = 0,
		Max = 80,
		Step = 1,
		Format = "%.0f",
	},

	-- === Speed ================================================================
	{
		Key = "SpeedStartFraction",
		Label = "Reacts from",
		Group = "Speed",
		Path = { "SpeedStartFraction" },
		Kind = "number",
		Min = 0,
		Max = 1,
		Step = 0.05,
		Format = "%.2f",
		Hint = "Share of THIS car's top speed where the pullback and the lens start moving. Cruise is about 0.74 of the ceiling on every car in the roster.",
	},
	{
		Key = "SpeedFullFraction",
		Label = "Fully open at",
		Group = "Speed",
		Path = { "SpeedFullFraction" },
		Kind = "number",
		Min = 0.1,
		Max = 1.5,
		Step = 0.05,
		Format = "%.2f",
	},
	{
		Key = "SpeedPullbackStuds",
		Label = "Pullback",
		Group = "Speed",
		Path = { "SpeedPullbackStuds" },
		Kind = "number",
		Min = 0,
		Max = 30,
		Step = 0.5,
		Format = "%.1f",
		Hint = "Extra studs of distance at the top of the band. The car getting away from you.",
	},
	{
		Key = "SpeedFovDeg",
		Label = "Speed zoom",
		Group = "Speed",
		Path = { "SpeedFovDeg" },
		Kind = "number",
		Min = 0,
		Max = 35,
		Step = 0.5,
		Format = "%.1f",
		Hint = "Extra degrees of lens at the top of the band, and most of how fast the game reads. The first thing to lower if the wide end looks like fish-eye on a phone.",
	},

	-- === Juice ================================================================
	{
		Key = "JuiceEnabled",
		Label = "Reactions",
		Group = "Juice",
		Path = { "Juice", "Enabled" },
		Kind = "boolean",
		Hint = "Off takes every hit nod, pass lean and lane lean out at once and leaves the follow untouched.",
	},
	{
		Key = "JuiceScale",
		Label = "Reaction size",
		Group = "Juice",
		Path = { "Juice", "Scale" },
		Kind = "number",
		Min = 0,
		Max = 2,
		Step = 0.05,
		Format = "%.2f",
		Hint = "The master over all three. This is the motion sickness answer and the first thing to reach for if anyone reports it.",
	},
	{
		Key = "SpringFrequency",
		Label = "Spring speed",
		Group = "Juice",
		Path = { "Juice", "Spring", "Frequency" },
		Kind = "number",
		Min = 0.5,
		Max = 6,
		Step = 0.1,
		Format = "%.2f",
		Hint = "Hz: how quickly a punch comes and goes. Every peak below is the peak it actually reaches, whatever this says.",
	},
	{
		Key = "SpringDamping",
		Label = "Spring settle",
		Group = "Juice",
		Path = { "Juice", "Spring", "Damping" },
		Kind = "number",
		Min = 0.2,
		Max = 0.99,
		Step = 0.01,
		Format = "%.2f",
		Hint = "1 is no overshoot at all, 0.5 is visibly bouncy.",
	},
	{
		Key = "LaneRollDeg",
		Label = "Lane lean",
		Group = "Juice",
		Path = { "Juice", "Lane", "RollDeg" },
		Kind = "number",
		Min = 0,
		Max = 8,
		Step = 0.1,
		Format = "%.2f",
		Hint = "Degrees the horizon leans into a lane change at full sideways speed.",
	},
	{
		Key = "LaneGain",
		Label = "Lane lean response",
		Group = "Juice",
		Path = { "Juice", "Lane", "Gain" },
		Kind = "number",
		Min = 1,
		Max = 20,
		Step = 0.5,
		Format = "%.1f",
	},

	-- === Hits =================================================================
	{
		Key = "ImpactRollPeakDeg",
		Label = "Hit roll",
		Group = "Hits",
		Path = { "Juice", "Impact", "RollPeakDeg" },
		Kind = "number",
		Min = 0,
		Max = 12,
		Step = 0.1,
		Format = "%.2f",
		Hint = "Degrees the camera rolls toward the side that took the hit, at a full strength one.",
	},
	{
		Key = "ImpactPitchPeakDeg",
		Label = "Hit nod",
		Group = "Hits",
		Path = { "Juice", "Impact", "PitchPeakDeg" },
		Kind = "number",
		Min = 0,
		Max = 12,
		Step = 0.1,
		Format = "%.2f",
	},
	{
		Key = "ImpactFovPeakDeg",
		Label = "Hit lens",
		Group = "Hits",
		Path = { "Juice", "Impact", "FovPeakDeg" },
		Kind = "number",
		Min = -15,
		Max = 15,
		Step = 0.5,
		Format = "%.1f",
		Hint = "NEGATIVE squeezes the lens in, which reads as the car being stopped short. Positive punches it out.",
	},
	{
		Key = "HitStopEnabled",
		Label = "Hit stop",
		Group = "Hits",
		Path = { "Juice", "HitStop", "Enabled" },
		Kind = "boolean",
		Hint = "A heavy hit holds the shot for a couple of frames and eases back onto the car. The closest a physics car gets to a freeze frame, because the solver cannot be paused.",
	},
	{
		Key = "HitStopSeconds",
		Label = "Hit stop hold",
		Group = "Hits",
		Path = { "Juice", "HitStop", "Seconds" },
		Kind = "number",
		Min = 0,
		Max = 0.15,
		Step = 0.005,
		Format = "%.3f",
		Hint = "Seconds. Past about 0.06 the car visibly slides out of a frozen shot.",
	},

	-- === Passes ===============================================================
	{
		Key = "PassRollPeakDeg",
		Label = "Near miss roll",
		Group = "Passes",
		Path = { "Juice", "Pass", "RollPeakDeg" },
		Kind = "number",
		Min = 0,
		Max = 8,
		Step = 0.1,
		Format = "%.2f",
		Hint = "Degrees the camera leans toward the car you just shaved, on the middle tier. A thread is 1.4 times this and a near miss about a third of it.",
	},
	{
		Key = "PassFovPeakDeg",
		Label = "Near miss lens",
		Group = "Passes",
		Path = { "Juice", "Pass", "FovPeakDeg" },
		Kind = "number",
		Min = 0,
		Max = 12,
		Step = 0.1,
		Format = "%.2f",
	},

	-- === Nitro ================================================================
	{
		Key = "NitroShakeTranslation",
		Label = "Nitro shake",
		Group = "Nitro",
		Path = { "NitroShake", "Translation" },
		Kind = "number",
		Min = 0,
		Max = 1,
		Step = 0.01,
		Format = "%.2f",
		Hint = "Studs. Keep it under about a quarter of one, or the shake moves traffic far enough in frame to spoil gap reading.",
	},
	{
		Key = "NitroShakeRotationDeg",
		Label = "Nitro roll",
		Group = "Nitro",
		Path = { "NitroShake", "RotationDeg" },
		Kind = "number",
		Min = 0,
		Max = 3,
		Step = 0.05,
		Format = "%.2f",
	},
	{
		Key = "NitroShakeFrequency",
		Label = "Nitro shake speed",
		Group = "Nitro",
		Path = { "NitroShake", "Frequency" },
		Kind = "number",
		Min = 1,
		Max = 40,
		Step = 0.5,
		Format = "%.1f",
	},

	-- === Bridges ==============================================================
	{
		Key = "CoverEnabled",
		Label = "Duck under bridges",
		Group = "Bridges",
		Path = { "Cover", "Enabled" },
		Kind = "boolean",
		Hint = "Inert while Low chase is on, because the shot is then already under every roof in the game.",
	},
	{
		Key = "CoverHeight",
		Label = "Ducked height",
		Group = "Bridges",
		Path = { "Cover", "Height" },
		Kind = "number",
		Min = 4,
		Max = 25,
		Step = 0.5,
		Format = "%.1f",
		Hint = "The lowest roof over a drive lane in any world is 17.6 studs, so 11 clears it with room to spare.",
	},
	{
		Key = "CoverExtraPitchDeg",
		Label = "Ducked pitch",
		Group = "Bridges",
		Path = { "Cover", "ExtraPitchDeg" },
		Kind = "number",
		Min = -20,
		Max = 20,
		Step = 0.5,
		Format = "%.1f",
		Hint = "Degrees handed back while covered. NEGATIVE tilts the lens up, which is most of what sells being low.",
	},
	{
		Key = "CoverEnterGain",
		Label = "Duck speed",
		Group = "Bridges",
		Path = { "Cover", "EnterGain" },
		Kind = "number",
		Min = 0.5,
		Max = 15,
		Step = 0.5,
		Format = "%.1f",
	},

	-- === Bail =================================================================
	{
		Key = "FlightExtraDistance",
		Label = "Flight pullback",
		Group = "Bail",
		Path = { "Flight", "ExtraDistance" },
		Kind = "number",
		Min = 0,
		Max = 40,
		Step = 0.5,
		Format = "%.1f",
		Hint = "Extra studs back while airborne, so the whole arc and the car you are aiming at fit in one frame.",
	},
	{
		Key = "FlightExtraPitchDeg",
		Label = "Flight pitch",
		Group = "Bail",
		Path = { "Flight", "ExtraPitchDeg" },
		Kind = "number",
		Min = -10,
		Max = 25,
		Step = 0.5,
		Format = "%.1f",
		Hint = "Degrees further down while airborne. You are looking at the road you are about to land on, which is what makes the ground marker readable.",
	},
	{
		Key = "FlightJumpFollow",
		Label = "Flight air time",
		Group = "Bail",
		Path = { "Flight", "JumpFollow" },
		Kind = "number",
		Min = 0,
		Max = 1,
		Step = 0.05,
		Format = "%.2f",
		Hint = "Follows much harder than it does on the road, because in a bail the height IS the event.",
	},
}

CameraTuningConfig.Fields = FIELDS

-- === The presets ============================================================

export type Preset = {
	--- Stored answer, and what a press on the settings row hands back. Never shown.
	Key: string,
	--- What the row prints. One or two words, because the row is as wide as the setting's name.
	Name: string,
	--- One line, shown in the panel under the preset buttons. What the shot is FOR.
	Blurb: string,
	--- Field key to value. Everything not named here is the value this build shipped.
	Set: { [string]: any },
}

--[[ THE SHOTS. Six of them plus Default, which is as many as a settings row can be stepped through
	without the press becoming a chore, and each one is a different ANSWER rather than a different
	amount of the same answer. Two of them (Fixed and Chase) are the two ends of the swing dial that
	`CameraConfig`'s Turning section describes and has never had a control for.

	WHICH ONES TOUCH `LowChaseEnabled` AND WHY. The shipped shot rides Low chase, so `Height` and
	`PitchDeg` are not what the game is using. A preset that wants a specific low shot therefore
	writes the `LowChase` pair and leaves the flag alone, and a preset that wants a HIGH shot turns
	the flag off and writes `Height` and `PitchDeg`. That is not a style choice: with Low chase on,
	the bridge duck deliberately stays home, which is right for a shot already under every roof in
	the game and wrong for one twenty studs up. Turning the flag off hands the duck back with it.

	The three that say nothing about height at all (Chase, Fixed, Calm) are asking one question each,
	so they leave the shot exactly where the build puts it and change only the thing being asked
	about. That is what makes them honest A/Bs rather than third shots that resemble the first. ]]
local PRESETS: { Preset } = {
	{
		Key = "default",
		Name = "Default",
		Blurb = "The shot this build ships. Every other preset is a change from here, and pressing this one puts every value back.",
		Set = {},
	},

	--[[ THE ONE THE BENCH WAS BUILT FOR, and the thing people mean when they ask for a camera that
		follows the car as it turns. `YawFollow` at 1 lines the frame up with the nose, so the car
		looks square in frame at all times and the road swings around it. `CameraConfig` calls this
		the far end of the dial and warns that it pivots the world the way the stock VehicleCamera
		does; whether that reads as responsive or as sickening is exactly the question a tester is
		here to answer, and it has never been askable before.

		The cap goes up with it. Leaving it at 9 would take a full share of the heading and then clip
		it back to the same nine degrees the default gets, which is the default shot with extra
		steps. 35 is comfortably past anything the steering reaches, so the cap stops mattering and
		the swing is genuinely one to one. ]]
	{
		Key = "chase",
		Name = "Chase",
		Blurb = "The frame locks onto the nose. Steering turns the world rather than sliding the car across a fixed shot.",
		Set = {
			YawFollow = 1,
			YawMaxDeg = 35,
			YawGain = 9,
			RollDeg = 3,
			--- Tighter across the road to match: with the frame following the nose, a soft lateral
			--- gain leaves the car drifting off-centre in a shot that is already rotating after it.
			LateralGain = 9,
			--[[ AND SQUARE BEHIND THE CAR, which this has to say out loud because the build ships
				counter-framing (`LateralFollow` under 1, the camera hanging back toward the road's
				centre while the car ranges across the frame). That is a composition for a shot that
				does not rotate. Put it under one that does and the two fight: the frame swings into
				the turn while the subject slides the other way out of the middle of it. ]]
			LateralFollow = 1,
		},
	},

	--[[ The other end, and the camera this one grew out of: the Rodeo Stampede shot, a corridor you
		thread rather than a car you turn. At `YawFollow` 0 the swing, the rotated chase offset and
		the bank all collapse to identity, so this is bit for bit the fixed camera rather than an
		approximation of it. ]]
	{
		Key = "fixed",
		Name = "Fixed",
		Blurb = "No swing at all. The road stays a straight corridor and steering reads as pure sideways travel.",
		Set = {
			YawFollow = 0,
			--- Looser across the road, because with no rotation the sideways slide is the ONLY cue a
			--- turn has and it wants to be visible.
			LateralGain = 5,
		},
	},

	--[[ High, far back, narrow and loose: the elevated arcade shot this game shipped with before the
		low chase, with the lens work the low chase never got. The lag numbers are deliberately soft,
		which is what lets the car move inside the frame instead of being welded to the middle of it.

		`LowChaseEnabled = false` is what hands the bridge duck back, and at twenty studs up it is
		needed: City carries bridges at 21.7 and this shot would otherwise drive through one. ]]
	{
		Key = "cinematic",
		Name = "Cinematic",
		Blurb = "High and well back on a narrow lens that opens wide at speed. The car moves inside the frame rather than being welded to the middle of it.",
		Set = {
			LowChaseEnabled = false,
			Height = 24,
			PitchDeg = 21,
			Distance = 40,
			FieldOfView = 62,
			SpeedFovDeg = 18,
			SpeedPullbackStuds = 14,
			AlongGain = 12,
			LateralGain = 4.5,
			HeightGain = 3.5,
			YawFollow = 0.5,
			YawGain = 4.5,
			RollDeg = 3.5,
			LateralFollow = 0.85,
		},
	},

	--[[ Down on the deck and close in, with the lens wide open. Everything here is pointed at one
		feeling, which is traffic arriving rather than traffic passing: near the ground, a car two
		lanes over is a wall coming at you instead of a shape you are looking down onto.

		Low chase stays ON, which is what keeps the duck home. At seven studs there is nothing left
		to duck to and the lens tilt would be the only thing the duck could still do, on the one beat
		that now looks like the whole race. ]]
	{
		Key = "low",
		Name = "Low and fast",
		Blurb = "Down on the deck and close in. Traffic comes at you rather than past you, and the lens opens hard as you build speed.",
		Set = {
			LowChaseHeight = 7,
			LowChasePitchDeg = 5,
			Distance = 22,
			FieldOfView = 76,
			SpeedFovDeg = 16,
			SpeedPullbackStuds = 12,
			LateralGain = 8,
			YawFollow = 0.8,
			YawMaxDeg = 14,
			--- Most of the way behind the car, but not all. Down here the counter-framing the build
			--- ships would let the car slide to the very edge of a shot that has almost no road in it.
			LateralFollow = 0.85,
		},
	},

	--[[ ON THE NOSE, LOOKING OUT. A negative `Distance` is what does it: the shot is placed at the
		car less the chase offset, so a negative offset puts the lens that many studs IN FRONT of the
		car's middle. At -11 a typical rig's bonnet fills the bottom of the frame and nothing else of
		the car is in shot.

		THE ELEVEN IS THE ONE NUMBER HERE THAT IS ABOUT THE CAR RATHER THAN THE SHOT, and the roster
		is 65 rigs of different lengths, so a longer car shows more bonnet and a shorter one shows
		less. That is the correct behaviour for a bonnet cam and it needs no per-car wiring, but it
		is also why `Distance` is a slider: a tester who wants the lens exactly on the badge of the
		car he is driving can put it there in one drag.

		The follow gains go hard, all three of them. A bumper cam is bolted to the car by definition,
		and any lag at all reads as the camera swimming around inside the bodywork rather than as
		weight. The swing goes to 1 for the same reason: at this distance the frame IS the car. ]]
	{
		Key = "bumper",
		Name = "Bumper",
		Blurb = "On the nose, looking out. You see the bonnet and nothing else of your own car, and every lane change happens at the height of one.",
		Set = {
			Distance = -11,
			LowChaseHeight = 5.5,
			LowChasePitchDeg = 3,
			YawFollow = 1,
			YawMaxDeg = 40,
			YawGain = 12,
			RollDeg = 0,
			AlongGain = 30,
			LateralGain = 30,
			HeightGain = 12,
			JumpFollow = 1,
			--- Not negotiable here, unlike everywhere else it appears. The lens is ON the car, so
			--- anything under 1 leaves it hanging over the road's centre line while the car it is
			--- supposed to be bolted to drives out from under it.
			LateralFollow = 1,
			FieldOfView = 82,
			SpeedFovDeg = 14,
			--- The pullback would drag the lens back through the windscreen and into the cabin as
			--- the car builds speed, which is the one thing this shot cannot survive.
			SpeedPullbackStuds = 0,
			--- Halved rather than off. At this distance every reaction is magnified by having no
			--- car between the lens and the world, and full strength reads as a fight.
			JuiceScale = 0.5,
		},
	},

	--[[ NOTHING MOVES THE HORIZON. This is the answer for a tester who cannot play the game for ten
		minutes without feeling ill, and it is one press rather than six.

		It is also a useful A/B on its own: every effect switched off here is cosmetic, so if the game
		still reads as fast with this on, the speed is coming from the driving rather than from the
		lens, which is worth knowing. ]]
	{
		Key = "calm",
		Name = "Calm",
		Blurb = "Nothing rotates and nothing shakes. The answer for anyone who cannot play this for ten minutes, and an honest test of how much of the speed is the lens.",
		Set = {
			YawFollow = 0,
			RollDeg = 0,
			JuiceScale = 0,
			SpeedFovDeg = 0,
			SpeedPullbackStuds = 0,
			NitroShakeTranslation = 0,
			NitroShakeRotationDeg = 0,
			HitStopEnabled = false,
		},
	},
}

CameraTuningConfig.Presets = PRESETS

--- Where a session starts, and what "put it back" means. Has to be a key in the list above.
CameraTuningConfig.DefaultPreset = "default"

-- === Reading it =============================================================

--- Whether there is anything to show. `SettingsConfig.hasRows` asks, so that the gear never opens a
--- panel whose only row came from a bench that is switched off.
function CameraTuningConfig.hasPresets(): boolean
	return CameraTuningConfig.Enabled == true and #CameraTuningConfig.Presets > 1
end

--- The field under `key`, or nil. Callers hold a field rather than a key wherever they can; this is
--- for the ones that cannot, which is anything reading a preset's `Set`.
function CameraTuningConfig.fieldFor(key: string): Field?
	for _, field in CameraTuningConfig.Fields do
		if field.Key == key then
			return field
		end
	end
	return nil
end

--- The preset under `key`, or nil when it is not one this build has.
function CameraTuningConfig.presetFor(key: unknown): Preset?
	for _, preset in CameraTuningConfig.Presets do
		if preset.Key == key then
			return preset
		end
	end
	return nil
end

--- Every field in `group`, in the order they are declared. The panel draws one section per group.
function CameraTuningConfig.fieldsIn(group: string): { Field }
	local found = {}
	for _, field in CameraTuningConfig.Fields do
		if field.Group == group then
			table.insert(found, field)
		end
	end
	return found
end

--[[ What the field's slot says right now. Walks `Path` and stops at the first step that is not a
	table, so a path that no longer matches `CameraConfig` answers nil instead of erroring, which is
	what a config reorganised out from under this file looks like. Same contract as
	`TuningConfig.read`. ]]
function CameraTuningConfig.read(field: Field): any
	local node: any = CameraConfig
	for _, step in field.Path do
		if type(node) ~= "table" then
			return nil
		end
		node = node[step]
	end
	return node
end

--- Write `value` into the field's slot. False when the path does not lead anywhere, for the same
--- reason `read` returns nil: a stale path is reported rather than guessed at.
function CameraTuningConfig.write(field: Field, value: any): boolean
	local node: any = CameraConfig
	for index = 1, #field.Path - 1 do
		if type(node) ~= "table" then
			return false
		end
		node = node[field.Path[index]]
	end
	if type(node) ~= "table" then
		return false
	end
	node[field.Path[#field.Path]] = value
	return true
end

--[[ `value` made safe for the field: clamped to the slider's own ends for a number, coerced to a
	boolean for a flag, and nil for anything that cannot be either. The one place a value arriving
	from a control, a preset or a stale table becomes something `CameraConfig` can hold. ]]
function CameraTuningConfig.coerce(field: Field, value: any): any
	if field.Kind == "boolean" then
		if type(value) ~= "boolean" then
			return nil
		end
		return value
	end
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	local low = field.Min or -math.huge
	local high = field.Max or math.huge
	return math.clamp(value, low, high)
end

--[[ A number as short as it can be written without losing what a slider can express. Integers print
	as integers, so a report reads `CameraConfig.YawFollow = 1` rather than `1.0000`, and the rest
	lose their trailing zeros. Four places is past the finest `Step` in the rack by an order of
	magnitude, so nothing a control can produce is rounded away. ]]
local function numberText(value: number): string
	if value == math.floor(value) and math.abs(value) < 1e9 then
		return string.format("%d", value)
	end
	local text = string.format("%.4f", value)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

--- `value` as Luau source. Used by the report and by nothing else.
function CameraTuningConfig.valueText(value: any): string
	if type(value) == "boolean" then
		return if value then "true" else "false"
	end
	if type(value) == "number" then
		return numberText(value)
	end
	return tostring(value)
end

--[[ One line of the report: the assignment that would put this value into `CameraConfig` if it were
	pasted into the file. Written as the full dotted path from `CameraConfig` rather than as the
	field's own label, because the whole point of the report is that it is source rather than a
	description of source. ]]
function CameraTuningConfig.assignment(field: Field, value: any): string
	return string.format("CameraConfig.%s = %s", table.concat(field.Path, "."), CameraTuningConfig.valueText(value))
end

--- The answers as a settings row wants them: one option per preset, in order. The row steps through
--- them, so the order here is the order a press walks.
function CameraTuningConfig.options(): { { Key: string, Name: string } }
	local options = {}
	for _, preset in CameraTuningConfig.Presets do
		table.insert(options, { Key = preset.Key, Name = preset.Name })
	end
	return options
end

return CameraTuningConfig
