--[[
	TuningController  (client)
	--------------------------
	THE HAND ON THE PLAYTEST KNOBS. `TuningConfig` is the rack, its list of knobs and the argument for
	why a knob writes the feature's own config; this holds the answers and does the writing.

	It is about as small as a controller gets, and the two things it owns are the whole job:

	  • THE BASELINES. What each knob's field said at boot, captured once, before anything can have
	    moved it. That number is what "Normal" means on the settings screen and what every share is a
	    share of, so it has to be read before the first press and never again.

	  • THE ANSWERS. Which option each knob is on, as an option key. Session only. There is no remote
	    and no profile key, for the reason `TuningConfig` gives at length: these rows exist to be
	    compared against the build's own values, so every session starting there is the point.

	REJOINING IS THE RESET, and that is why there is no reset button. Nothing here is saved, so a
	tester who has flipped six rows and wants the shipping build back rejoins and has it, which is
	fewer moving parts than a control that would need a row of its own and a shape the screen does
	not draw.

	=== THE PRESS IS APPLIED HERE AND REPAINTED THROUGH THE EVENT ============================

	Same one-way street as the sky, the volumes and the interface: the settings row hands a key here,
	this writes the config and publishes, and the row repaints from what it reads back. No screen
	ever paints an answer the game is not actually on.

	=== FLIPPING MID-RACE CUTS, AND THAT IS ALLOWED =========================================

	The settings chip is up during a run on the new UI (`TopbarController._setRacing`), so a knob can
	be flipped with the car moving, which is exactly when a camera question is worth asking. The shot
	then CUTS rather than easing: `RaceCameraController` rides its height on a gain but applies the
	pitch straight to the CFrame each frame, so switching the low camera off moves 11 studs smoothly
	and 8 degrees at once.

	Left that way deliberately. Blending it would mean a second set of gains inside the camera for a
	transition only a test build can ask for, and a cut is what a tester comparing two shots wants
	anyway: the two framings side by side, not a slide between them.

	=== A STALE PATH SAYS SO AT BOOT ========================================================

	Every knob names a config field by a path, and the config it points into belongs to somebody else
	who is editing it this week. A path that no longer leads anywhere is therefore the failure to
	expect, and it is caught here, once, at `init`: the knob is dropped with a warning naming it.

	`Modules/SettingsRows` makes the same check when it builds the screen and leaves the row out
	entirely, so a stale knob is a row that is not there rather than one that does nothing when it is
	pressed. Two places asking the same question of the same path, which is cheap, and the alternative
	is the screen asking this controller for a list it would then have to publish changes to.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local TuningConfig = require(ReplicatedStorage.shared.Configs.TuningConfig)

local TuningController = Shard.new("TuningController")

-- === Answers ================================================================

--- Public (`Modules/SettingsRows`): which option a knob is on, as an option key. The baseline answer
--- for a knob this controller never took up, so a row always has something true to draw.
function TuningController.answer(self, knobKey: string): string?
	local record = self._knobs[knobKey]
	if not record then
		return nil
	end
	return record.answer
end

--[[ Public (the settings row): pick an answer.

	False means the press did nothing and says why in a warning: an unknown knob or option is a screen
	and a config that have drifted apart, and a write that does not land is a path that moved since
	boot. Both are worth hearing about, and neither should be silent on a screen whose whole job is
	to change something. ]]
function TuningController.choose(self, knobKey: string, optionKey: string): boolean
	if not TuningConfig.Enabled then
		return false
	end

	local record = self._knobs[knobKey]
	if not record then
		self.log:warn(string.format("No knob called %q; the press did nothing.", knobKey))
		return false
	end

	local option = TuningConfig.optionFor(record.knob, optionKey)
	if not option then
		self.log:warn(string.format("%q has no answer called %q; the press did nothing.", knobKey, optionKey))
		return false
	end

	if record.answer == optionKey then
		return true
	end

	local value = TuningConfig.valueFor(record.knob, option, record.baseline)
	if not TuningConfig.write(record.knob, value) then
		self.log:warn(string.format("%q no longer leads anywhere in its config; nothing was written.", knobKey))
		return false
	end

	record.answer = optionKey
	Dispatcher:Publish(TuningConfig.StateEvent, knobKey)
	return true
end

TuningController:withLifecycle({
	init = function(self)
		--- One record per live knob: the knob itself, what its field said at boot, and the answer it
		--- is on now. Keyed by the knob's `Key`, which is what a settings row hands back.
		self._knobs = {} :: { [string]: { knob: any, baseline: any, answer: string } }

		if not TuningConfig.Enabled then
			return
		end

		--[[ Read before anything can have moved it. Nothing writes these configs at runtime except
			this file, so `init` is early enough, and being early is the whole requirement: a baseline
			taken after a press would be that press's value and every share would compound. ]]
		for _, knob in TuningConfig.Knobs do
			local baseline = TuningConfig.read(knob)
			if baseline == nil then
				self.log:warn(
					string.format("%q points at a config field that is not there; the row is dropped.", knob.Key)
				)
				continue
			end

			self._knobs[knob.Key] = {
				knob = knob,
				baseline = baseline,
				answer = TuningConfig.baselineKey(knob, baseline),
			}
		end
	end,
})

return TuningController
