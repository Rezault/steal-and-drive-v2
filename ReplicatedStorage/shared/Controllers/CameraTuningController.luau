--[[
	CameraTuningController  (client)
	--------------------------------
	THE HAND ON THE CAMERA BENCH. `CameraTuningConfig` is the rack, its presets and its field list
	and the argument for why both write the camera's own config; this holds the baselines and does
	the writing.

	It is `TuningController` with three things added, and it is worth saying which three, because
	everything else about it is deliberately the same file:

	  • A PRESET IS A BATCH. `applyPreset` restores every field to its baseline and then writes the
	    preset's `Set` over the top, so a preset means the same shot whatever was pressed before it
	    and Default is the shipped build exactly. See `_restore`.
	  • A FIELD IS A LIVE SLIDER. `setValue` writes one field, clamped to that field's own ends, at
	    render rate while a grip is being dragged. There is no commit and nothing to save, so a drag
	    is just a lot of sets.
	  • THE REPORT. `report` is the way a shot tuned in a playtest comes back to the repo: the
	    assignments that differ from what this build shipped, in the form they would be pasted into
	    `CameraConfig`. Nothing here is saved, so without it a good camera found at eleven at night
	    is gone at the next rejoin.

	=== THE BASELINES ARE THE WHOLE TRICK ===================================================

	What each field's slot said at boot, captured once, before anything can have moved it. That is
	what Default restores, what "differs from the shipped build" is measured against, and what the
	report leaves out. It has to be read before the first press and never again: a baseline taken
	after a press would be that press's value, and the report would then say the build ships the
	thing somebody changed.

	`TuningController` captures its own baselines over the same config in its own `init`, and the two
	agree because neither of them writes anything during init. What they do not do is coordinate: the
	camera knobs on the settings screen and the fields here both write `CameraConfig` and the last
	press wins. That is the right answer for a bench. A knob says "a quarter more distance than we
	ship" and a preset says "forty studs", and neither is wrong, they are just two people talking
	about the same number. The panel prints what the number actually is, which settles it.

	=== REJOINING IS STILL THE RESET ========================================================

	No remote, no profile key, nothing saved, for the reason `CameraTuningConfig` gives: these
	controls exist to be compared against the build's own shot, so every session starting there is
	the point. There IS a reset here, unlike the knob rack, and the reason is that a bench with
	forty-four sliders on it can be got into a state nobody meant, mid-race, with no way back short
	of leaving the game.

	=== A STALE PATH SAYS SO AT BOOT ========================================================

	Every field names a slot in `CameraConfig` by a path, and that file belongs to somebody who is
	editing it this week. A path that no longer leads anywhere is therefore the failure to expect,
	and it is caught here, once, at `init`: the field is dropped with a warning naming it, and
	everything else comes up. The panel draws what it is given, so a dropped field is a control that
	is not there rather than one that does nothing when it is moved.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local CameraTuningConfig = require(ReplicatedStorage.shared.Configs.CameraTuningConfig)

local CameraTuningController = Shard.new("CameraTuningController")

-- === Reading ================================================================

--- Public: the preset last applied, as a preset key. Always something, so a row and a panel always
--- have a true answer to draw.
function CameraTuningController.preset(self): string
	return self._preset
end

--- Public: whether any field has been moved by hand since that preset was applied. The panel says
--- so beside the preset's name and the report says so in its header, because "Chase" and "Chase
--- with the distance pulled out eight studs" are two different reports.
function CameraTuningController.isEdited(self): boolean
	return self._edited == true
end

--- Public: what a field's slot says right now, or nil for a field this controller dropped at boot.
function CameraTuningController.value(self, fieldKey: string): any
	local record = self._fields[fieldKey]
	if not record then
		return nil
	end
	return CameraTuningConfig.read(record.field)
end

--- Public: what the build shipped for that field. What Default restores, and the thing the report
--- measures against.
function CameraTuningController.baseline(self, fieldKey: string): any
	local record = self._fields[fieldKey]
	if not record then
		return nil
	end
	return record.baseline
end

--- Public: whether that field is sitting somewhere other than the shipped value.
function CameraTuningController.isMoved(self, fieldKey: string): boolean
	local record = self._fields[fieldKey]
	if not record then
		return false
	end
	return CameraTuningConfig.read(record.field) ~= record.baseline
end

--- Public: every live field, in the order `CameraTuningConfig` declares them. The panel walks this
--- rather than the config's own list so a dropped field is simply absent.
function CameraTuningController.fields(self): { any }
	return self._live
end

-- === Writing ================================================================

--[[ Put every field back to what this build shipped. Used by `applyPreset` before it writes, and by
	the panel's reset.

	IT WALKS THE LIVE LIST AND NOT THE CONFIG'S, so a field whose path went stale between builds is
	not written to on the way past. Warnings for those were spent once at boot and this runs on every
	preset press. ]]
function CameraTuningController._restore(self)
	for _, record in self._live do
		CameraTuningConfig.write(record.field, record.baseline)
	end
end

--[[ Public (the settings row, and the panel's preset buttons): put a whole shot up.

	ALWAYS WRITES, even when the preset asked for is the one already showing. That is what makes the
	button a way back from a bench somebody has been dragging sliders on: press Chase again and you
	are on Chase rather than on Chase plus twenty minutes of edits.

	False means the press did nothing and says why in a warning, which is the same contract
	`TuningController.choose` keeps: a preset key the build does not have is a screen and a config
	that have drifted apart, and it should not be silent on a control whose whole job is to change
	something. ]]
function CameraTuningController.applyPreset(self, presetKey: string): boolean
	if not CameraTuningConfig.Enabled then
		return false
	end

	local preset = CameraTuningConfig.presetFor(presetKey)
	if not preset then
		self.log:warn(string.format("No camera preset called %q; the press did nothing.", tostring(presetKey)))
		return false
	end

	self:_restore()

	for fieldKey, value in preset.Set do
		local record = self._fields[fieldKey]
		if not record then
			--[[ A preset naming a field that is not in the rack, or one that was dropped at boot.
				Worth a warning rather than a silent skip: the preset is then not the shot it says it
				is, and the difference is invisible on screen. ]]
			self.log:warn(
				string.format("Camera preset %q names %q, which is not a field on this bench.", preset.Key, fieldKey)
			)
			continue
		end
		local safe = CameraTuningConfig.coerce(record.field, value)
		if safe == nil then
			self.log:warn(
				string.format(
					"Camera preset %q gives %q a value it cannot hold; that field is left alone.",
					preset.Key,
					fieldKey
				)
			)
			continue
		end
		CameraTuningConfig.write(record.field, safe)
	end

	self._preset = preset.Key
	self._edited = false
	Dispatcher:Publish(CameraTuningConfig.StateEvent, preset.Key)
	return true
end

--[[ Public (the panel's sliders and checkboxes): move one field.

	CALLED AT RENDER RATE while a grip is being dragged, which is why it publishes only when the
	value actually changed. Iris redraws from the config every frame anyway, so a publish per frame
	would buy nothing and would wake the settings screen forty times a second.

	The value is clamped to the field's own ends rather than trusted, because the same door is used
	by a slider, by a typed-in number (Iris lets you control-click a slider and type one) and by
	anything calling this from the command bar. ]]
function CameraTuningController.setValue(self, fieldKey: string, value: any): boolean
	if not CameraTuningConfig.Enabled then
		return false
	end

	local record = self._fields[fieldKey]
	if not record then
		self.log:warn(string.format("No camera field called %q; the change did nothing.", tostring(fieldKey)))
		return false
	end

	local safe = CameraTuningConfig.coerce(record.field, value)
	if safe == nil then
		return false
	end
	if CameraTuningConfig.read(record.field) == safe then
		return true
	end
	if not CameraTuningConfig.write(record.field, safe) then
		self.log:warn(string.format("%q no longer leads anywhere in CameraConfig; nothing was written.", fieldKey))
		return false
	end

	self._edited = true
	Dispatcher:Publish(CameraTuningConfig.StateEvent, fieldKey)
	return true
end

--- Public (the panel): back to the shipped build, and back to the Default preset with it. Same
--- thing as applying Default, named for what a tester is actually asking for.
function CameraTuningController.reset(self): boolean
	return self:applyPreset(CameraTuningConfig.DefaultPreset)
end

-- === The report =============================================================

--[[ Public (the panel): the current camera, as Luau.

	WHAT IT IS FOR. Nothing on this bench is saved, so a shot found in a playtest exists only until
	the tester leaves. This is how it comes back: the assignments that differ from what the build
	ships, in the form they would be pasted into `CameraConfig`, with a header saying which preset
	they started from and who was driving.

	`everything` prints all forty-odd fields instead of the changed ones. Worth having for a full
	snapshot of a build, and the wrong default, because the interesting part of a tuning session is
	always the handful of lines that moved.

	THE HEADER IS PART OF THE ANSWER. A block of eight assignments with no preset named is a report
	somebody has to reconstruct: "Bumper, edited" says that six of those lines came out of the
	preset and two came out of a tester's hands, which is the difference between a shot to ship and
	a shot to look at. ]]
function CameraTuningController.report(self, everything: boolean?): string
	local preset = CameraTuningConfig.presetFor(self._preset)
	local lines = {
		string.format(
			"-- CameraConfig, tuned live by %s on %s",
			Players.LocalPlayer.Name,
			os.date("%Y-%m-%d %H:%M")
		),
		string.format(
			"-- Preset: %s%s",
			if preset then preset.Name else self._preset,
			if self._edited then " (edited by hand)" else ""
		),
	}

	local moved = 0
	for _, record in self._live do
		local value = CameraTuningConfig.read(record.field)
		local differs = value ~= record.baseline
		if differs then
			moved += 1
		end
		if everything or differs then
			table.insert(lines, CameraTuningConfig.assignment(record.field, value))
		end
	end

	if moved == 0 and not everything then
		table.insert(lines, "-- Nothing has moved. This is the build exactly as it ships.")
	else
		table.insert(
			lines,
			string.format("-- %d of %d fields differ from the shipped build.", moved, #self._live)
		)
	end

	return table.concat(lines, "\n")
end

--[[ Public (the panel's button, and the command bar): the report, in the output.

	ONE `print` AND NOT ONE PER LINE. Roblox's output draws a multi-line string as a single entry, so
	this copies out of Studio and out of the in-game console as one block rather than as thirty rows
	somebody has to select in order. It is also what makes the report readable from a log dump, which
	is how it gets back to whoever is editing `CameraConfig`. ]]
function CameraTuningController.printReport(self, everything: boolean?): string
	local text = self:report(everything)
	print(text)
	return text
end

CameraTuningController:withLifecycle({
	init = function(self)
		--- One record per live field: the field itself and what its slot said at boot. Keyed by the
		--- field's `Key`, which is what a control and a preset's `Set` both hand back.
		self._fields = {} :: { [string]: { field: any, baseline: any } }
		--- The same records in declaration order, which is the order the panel draws them.
		self._live = {} :: { any }
		self._preset = CameraTuningConfig.DefaultPreset
		self._edited = false

		if not CameraTuningConfig.Enabled then
			return
		end

		--[[ Read before anything can have moved it. Nothing writes `CameraConfig` at runtime except
			this file and `TuningController`, and neither writes during init, so this is early enough.
			Being early is the whole requirement: see the header. ]]
		for _, field in CameraTuningConfig.Fields do
			local baseline = CameraTuningConfig.read(field)
			if baseline == nil then
				self.log:warn(
					string.format(
						"%q points at a CameraConfig field that is not there; the control is dropped.",
						field.Key
					)
				)
				continue
			end

			local record = { field = field, baseline = baseline }
			self._fields[field.Key] = record
			table.insert(self._live, record)
		end
	end,
})

return CameraTuningController
