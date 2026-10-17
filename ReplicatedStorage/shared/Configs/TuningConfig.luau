--[[
	TuningConfig
	------------
	THE PLAYTEST KNOBS. A short rack of A/B switches that put the camera and the steering onto values
	other than the ones this build ships with, so a tester can answer "which of these feels better"
	inside one session instead of asking for another build.

	Read by `TuningController`, which owns every write, and by `Modules/SettingsRows`, which turns
	each entry below into a row on the settings screen. Nothing else in the game knows this file
	exists, and that is the property worth keeping: no feature ever asks whether a knob is on.

	=== A KNOB WRITES THE VALUE THE FEATURE ALREADY READS ====================================

	`CameraConfig.LowChase.Enabled` is a field `RaceCameraController` reads once a frame, so the knob
	that switches the low camera off is one line that writes that field. The feature is not edited,
	does not learn a second way to be configured, and cannot disagree with the screen, because the
	screen and the feature are looking at the same table.

	The alternative was a preference per feature, the way the sky and the two volumes work: a config,
	a controller, a remote, a profile key and a branch at every read site. That shape is right for a
	setting a player keeps. It is far too much for a question a test build asks for a fortnight and
	then stops asking, and the branches it leaves behind outlive the question.

	=== THE ONE RULE: THE VALUE HAS TO BE READ LIVE ==========================================

	A knob moves a number in a table, so it can only be felt if whatever reads that number reads it
	again after the press. Every field named below is read inside a render step, and each entry says
	where. A value captured into a local at require time, or applied once when a race starts, would
	sit there unchanged and the row would look broken. That is the one way to get this wrong, and it
	is the thing to check before adding an entry.

	=== ANSWERS ARE SHARES OF THE SHIPPED VALUE, NOT NUMBERS OF THEIR OWN ====================

	`Scale = 0.75`, never `Value = 43.5`. Two people are tuning `DriveConfig` and `CameraConfig` right
	now, and `LaneSpeed` alone has been 26, 30 and 58 inside a fortnight. A copied number is a second
	baseline that goes stale the day the first one moves, silently, while still reading on screen as
	somebody's deliberate choice.

	So the shipped value is the baseline, captured once at boot by `TuningController`, and an answer
	is a multiple of it. NORMAL IS ALWAYS EXACTLY WHAT THIS BUILD SHIPS, whatever that happens to be
	today, and a knob nobody touches writes nothing at all.

	An answer may still carry a literal `Value` where the point IS a literal: off is zero, and a flag
	is true or false. A share of a value that ships at zero has nothing to multiply, which is why
	every "Off" below is a `Value` rather than `Scale = 0`.

	=== NOTHING IS SAVED =====================================================================

	The same answer `InterfaceConfig` gives, for a stronger reason. These knobs exist to be compared
	against the default, so every session starting on the default is the feature rather than a
	limitation: two testers reporting on the same build are then reporting on the same game. A saved
	knob is the tester who put the camera up six weeks ago, forgot, and is now filing bugs about a
	build nobody else is running.

	`Enabled = false` takes every row off the settings screen and leaves every config untouched,
	which is what a shipping build wants.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- The two configs the rack writes. Both are leaf tables that require nothing, so this file cannot
--- be the middle of a cycle however early a screen asks for it.
local CameraConfig = require(ReplicatedStorage.shared.Configs.CameraConfig)
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)

local TuningConfig = {}

--[[ Master switch. Off = no tuning rows on the settings screen, no baselines captured and nothing
	written. Turn it off for a public build: the rows are a tester tool, and a player who cannot be
	told what "Lane framing" is cannot be helped by a switch for it. ]]
TuningConfig.Enabled = true

--- Published on the client whenever an answer moves, so an open settings screen repaints from the
--- controller rather than from its own copy. Same contract as `InterfaceConfig.StateEvent`.
TuningConfig.StateEvent = "TuningState"

export type Option = {
	--- Stored answer, and what a press hands back. Never shown.
	Key: string,
	--- What the row prints. Two-answer rows read as OFF and ON, because the kit draws those as a
	--- coloured switch with no room for a word on it; three-answer rows get a caption and can say
	--- anything short.
	Name: string,
	--- Multiply the shipped value by this. Absent on the answer that IS the shipped value.
	Scale: number?,
	--- Or write this exactly, for an off that has to be zero and for a flag. Wins over `Scale`.
	Value: any?,
}

export type Knob = {
	--- Stable name for this knob, used as the key of the answer the controller is holding.
	Key: string,
	--- The row's title on the settings screen.
	Title: string,
	--- The config table the knob writes, and the field inside it, as the path to walk.
	Config: { [string]: any },
	Path: { string },
	--- Every answer, in the order pressing steps through them. The first is the one the kit draws as
	--- the "off" side of a two-answer switch.
	Options: { Option },
}

--[[ THE RACK. One entry per knob, camera first and steering second, which is the order the two
	questions get asked in.

	Deleting an entry is how a knob is retired. There is no per-knob switch, because a knob that is
	switched off is a row nobody can see and a line nobody reads. ]]
local KNOBS: { Knob } = {
	--[[ THE KNOB THIS RACK WAS BUILT FOR. `LowChase` is the bridge shot made permanent, 11 studs up
		with the lens handed 8 degrees back, and OFF is the high chase exactly: 22 up and 24 down,
		which is what `CameraConfig.Height` and `PitchDeg` still say on their own lines. So this is
		the honest A/B between the two shots the game has actually had, not a third one that
		resembles them.

		Read every frame by `RaceCameraController`'s `baseHeight` and `basePitchDeg`.

		Turning it off also hands the duck back: `_stepCover` stays home while `LowChase` is on,
		because the shot is already down where the duck would put it, and starts ducking again the
		moment this row says Off. Both halves of the old behaviour come back together. ]]
	{
		Key = "LowCamera",
		Title = "Low camera",
		Config = CameraConfig,
		Path = { "LowChase", "Enabled" },
		Options = {
			{ Key = "off", Name = "Off", Value = false },
			{ Key = "on", Name = "On", Value = true },
		},
	},

	--[[ How far back the shot sits, in studs down the road. Near reads faster and crowds the traffic
		ahead; far reads calmer and shows more of the deck. It is the cheapest thing on this list to
		have an opinion about, so it is second.

		Read every frame, twice: the chase offset itself and the lane framing's aim triangle. ]]
	{
		Key = "CameraDistance",
		Title = "Camera distance",
		Config = CameraConfig,
		Path = { "Distance" },
		Options = {
			{ Key = "near", Name = "Near", Scale = 0.8 },
			{ Key = "normal", Name = "Normal" },
			{ Key = "far", Name = "Far", Scale = 1.3 },
		},
	},

	--[[ The camera's share of the car's heading. `CameraConfig.YawFollow` says it out loud: at 0 the
		swing, the rotated chase offset and the bank all collapse and what is left is the fixed
		camera this one grew out of. That makes Off a real answer rather than a degraded one, and it
		is the fastest way to find out whether a turn is reading as understeer.

		Read every frame, and the read is guarded on the value being above zero, so Off costs nothing
		either. ]]
	{
		Key = "CameraSwing",
		Title = "Camera swing",
		Config = CameraConfig,
		Path = { "YawFollow" },
		Options = {
			{ Key = "off", Name = "Off", Value = 0 },
			{ Key = "half", Name = "Half", Scale = 0.5 },
			{ Key = "full", Name = "Full" },
		},
	},

	--[[ Every hit, near miss and lane lean at once. `CameraConfig.Juice.Scale` was written as the
		master for exactly this and its header names a settings toggle as the thing it was waiting
		for, so this row is that sentence cashed.

		IT IS ALSO THE MOTION SICKNESS ANSWER. A tester who cannot play for ten minutes without
		feeling ill has one row to reach for and it is this one, which is worth saying because the
		three effects it covers are the ones that move the horizon.

		Read through `juiceScale()`, once per effect per frame. ]]
	{
		Key = "CameraShake",
		Title = "Camera shake",
		Config = CameraConfig,
		Path = { "Juice", "Scale" },
		Options = {
			{ Key = "off", Name = "Off", Value = 0 },
			{ Key = "half", Name = "Half", Scale = 0.5 },
			{ Key = "full", Name = "Full" },
		},
	},

	--[[ Degrees of extra field of view at the top of the car's own speed range: most of how fast the
		game reads, and the effect most likely to be called fish-eye on a phone. Off leaves the lens
		where `FieldOfView` put it and lets the wind streaks carry the speed on their own, which is
		the comparison worth making.

		Nitro's own swing is not on this knob. It is `NitroConfig.Fov`, it is brief by construction,
		and it is meant to be the loudest moment in a run whatever this says.

		Read every frame while the speed ramp is above zero. ]]
	{
		Key = "SpeedZoom",
		Title = "Speed zoom",
		Config = CameraConfig,
		Path = { "SpeedFovDeg" },
		Options = {
			{ Key = "off", Name = "Off", Value = 0 },
			{ Key = "half", Name = "Half", Scale = 0.5 },
			{ Key = "full", Name = "Full" },
		},
	},

	--[[ The counter-framing at the outer lanes: below 1 the camera hangs back toward the road's
		centre while the car ranges across the frame, and the lens aims back at it. Off is 1, which
		puts the shot directly behind the car and collapses the aim with it, since the angle it is
		correcting for is then zero.

		A LITERAL 1 AND NOT A SHARE, because the answer here is "no counter-framing at all" and that
		is a fixed point rather than a multiple of whatever the framing currently is.

		Read every frame, and it is the value the whole lane composition hangs off. ]]
	{
		Key = "LaneFraming",
		Title = "Lane framing",
		Config = CameraConfig,
		Path = { "LateralFollow" },
		Options = {
			{ Key = "off", Name = "Off", Value = 1 },
			{ Key = "on", Name = "On" },
		},
	},

	--[[ Sideways speed at full input, which is how much road a lane change covers per second. This
		is the knob a tester means by "the car feels slow to move over" or "it feels like strafing",
		and the two complaints want it moved in opposite directions, which is why it is a row.

		Read once a frame through `DriveController._laneTuning`, so touch still scales it on top. ]]
	{
		Key = "SteerSpeed",
		Title = "Steering speed",
		Config = DriveConfig,
		Path = { "LaneSpeed" },
		Options = {
			{ Key = "slow", Name = "Slow", Scale = 0.75 },
			{ Key = "normal", Name = "Normal" },
			{ Key = "fast", Name = "Fast", Scale = 1.25 },
		},
	},

	--[[ How fast that sideways speed eases in and out. `DriveConfig.LaneAccel` calls it the most
		important feel knob in its section and the half a player actually feels, because what a
		"steering feels heavy" report registers is the first fifth of a second after the key goes
		down, which is this rather than the speed above.

		Read once a frame through the same `_laneTuning`, and it is the spring's frequency when
		`LaneWeight` is on, so the row below changes what this one feels like.

		THE RANGES ARE SIZED AGAINST THE EDGE DAMPER, which is the one invariant these two rows can
		break. `DriveConfig.LaneEdgeFade` asks for a damping ratio at or above about 0.85, computed as
		sqrt(LaneAccel * LaneEdgeFade / (4 * LaneSpeed * LateralAssist)). Untouched this build sits at
		1.12. The worst pair these two rows can reach is Fast with Soft, which is 0.84, and the
		overshoot that buys is 0.8% of the move into the edge, which is a small fraction of a stud
		rather than the 1.9 studs that ratio bought at 0.63. Widen either row and do that sum again:
		below about 0.8 the car starts burying itself in the barrier at the outer lane and scrubbing
		its own speed off, which is a handling bug that looks nothing like a camera setting. ]]
	{
		Key = "SteerResponse",
		Title = "Steering response",
		Config = DriveConfig,
		Path = { "LaneAccel" },
		Options = {
			{ Key = "soft", Name = "Soft", Scale = 0.7 },
			{ Key = "normal", Name = "Normal" },
			{ Key = "sharp", Name = "Sharp", Scale = 1.4 },
		},
	},

	--[[ Whether the lane change carries any mass. On is the spring: a beat of build-up starting a
		move and a small settle ending one. Off is the first-order filter it replaced, which arrives
		and stops dead on the new line, exactly on cue, every time.

		`DriveConfig.LaneWeight` was written with this comparison in mind and names `Enabled = false`
		as the way back to the old handling, and `DriveController` keeps the spring's velocity in
		step even while it is unused so that flipping this mid-session cannot resume a lane change
		that finished minutes ago. Both halves of that were already waiting for this row.

		Read every frame, at the branch that integrates the lateral. ]]
	{
		Key = "SteerWeight",
		Title = "Steering weight",
		Config = DriveConfig,
		Path = { "LaneWeight", "Enabled" },
		Options = {
			{ Key = "off", Name = "Off", Value = false },
			{ Key = "on", Name = "On", Value = true },
		},
	},
}

TuningConfig.Knobs = KNOBS

-- === Reading it =============================================================

--- Whether there is anything to show. `SettingsConfig.hasRows` asks, so that the gear never opens an
--- empty panel in a build where this rack is the only thing left switched on.
function TuningConfig.hasKnobs(): boolean
	return TuningConfig.Enabled == true and #TuningConfig.Knobs > 0
end

--- The knob under `key`, or nil. Callers hold a knob rather than a key wherever they can; this is
--- for the one that cannot, which is anything reading an answer back out of a table.
function TuningConfig.knobFor(key: string): Knob?
	for _, knob in TuningConfig.Knobs do
		if knob.Key == key then
			return knob
		end
	end
	return nil
end

--- The option under `key`, or nil when the answer is not one this build has, which is what a knob
--- that changed its answers between builds looks like.
function TuningConfig.optionFor(knob: Knob, key: unknown): Option?
	for _, option in knob.Options do
		if option.Key == key then
			return option
		end
	end
	return nil
end

--[[ What the knob's field says right now. Walks `Path` and stops at the first step that is not a
	table, so a path that no longer matches its config answers nil instead of erroring, which is what
	a config reorganised out from under this file looks like. ]]
function TuningConfig.read(knob: Knob): any
	local node: any = knob.Config
	for _, step in knob.Path do
		if type(node) ~= "table" then
			return nil
		end
		node = node[step]
	end
	return node
end

--- Write `value` into the knob's field. False when the path does not lead anywhere, for the same
--- reason `read` returns nil: a stale path is reported, never guessed at.
function TuningConfig.write(knob: Knob, value: any): boolean
	local node: any = knob.Config
	for index = 1, #knob.Path - 1 do
		if type(node) ~= "table" then
			return false
		end
		node = node[knob.Path[index]]
	end
	if type(node) ~= "table" then
		return false
	end
	node[knob.Path[#knob.Path]] = value
	return true
end

--[[ What an answer means in numbers, against the value the build shipped.

	`Value` wins over `Scale` so that an off can be a literal zero and a flag can be a boolean. An
	answer carrying neither IS the baseline, which is what makes Normal mean "whatever this build
	ships" rather than a number that has to be kept in step with one. ]]
function TuningConfig.valueFor(knob: Knob, option: Option, baseline: any): any
	if option.Value ~= nil then
		return option.Value
	end
	if option.Scale ~= nil and type(baseline) == "number" then
		return baseline * option.Scale
	end
	return baseline
end

--[[ Which answer leaves the field exactly as the build shipped it, as an option key. That is where
	every session starts, and it is worked out from the baseline rather than written down, so a knob
	cannot open on an answer that is not what the game is actually doing.

	The first option that matches wins, and the last resort is the first option in the list, which
	only happens when a knob's answers cannot express its own shipped value. ]]
function TuningConfig.baselineKey(knob: Knob, baseline: any): string
	for _, option in knob.Options do
		if option.Value ~= nil then
			if option.Value == baseline then
				return option.Key
			end
		elseif option.Scale == nil or option.Scale == 1 then
			return option.Key
		end
	end
	return knob.Options[1].Key
end

return TuningConfig
