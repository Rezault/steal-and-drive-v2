--[[
	SettingsRows  (shared)
	----------------------
	WHAT IS ON THE SETTINGS SCREEN, and nothing about how it is drawn. One row per setting, in the
	order they appear, each one switched on by its own feature's config.

	Lifted out of `UIController/Pages/Settings` on 2026-09-15 because there are two settings screens
	now: the shipping one and the Cartoony Kit one behind `NewUIConfig.Enabled`. The list of settings
	is the same list on both, and it is the half of that page most likely to grow, so a fifth setting
	should be one edit rather than two that have to agree. See `docs/NewUI-Migration-Plan.md`, "Shared
	logic".

	=== IT DECIDES NOTHING, AND THAT IS THE POINT ============================================

	Every row asks its feature's own controller what the answer is and hands a press straight back to
	it. The repaint comes round through that feature's state event rather than being done on the way
	out. One truth, one direction. That is also what makes the H key work for free: hide the UI from a
	keyboard with a settings screen open and the control moves on its own.

	`SettingsConfig` stays the owner of whether the SCREEN exists and `hasRows` stays an `or` of the
	same switches read below. This file is the rows; that one is the door.

	=== TWO KINDS, AND A SPEC SAYS WHICH BY ITS `Kind` =======================================

	  • `toggle` holds ANY NUMBER OF ANSWERS, not two. `Options` is the list and `choose` takes the
	    next one's key. Two answers is a switch; three is Time of day, which is why this is a list and
	    not a boolean. How a screen DRAWS three answers is the screen's problem: the shipping page
	    slides one pill along a track, and the kit page steps a caption on a button.
	  • `slider` carries a 0 to 1, with `set(value, persist)`. `persist` is false for every frame of a
	    drag and true when the finger comes off, because a drag is one decision made over half a
	    second and not thirty of them.

	=== EVERY CONTROLLER IS FETCHED PER CALL =================================================

	`Shard.get` on every call rather than a reference captured once: controllers start from a hash
	table with no dependency order, so a reference taken while a page was being built could be nil for
	one that had not come up yet. Asking each time also means a controller that is genuinely absent
	degrades to "the row does nothing" instead of erroring.

	=== AND THEN THE PLAYTEST KNOBS =========================================================

	Everything above is a setting a player keeps. `TuningConfig` is a rack of A/B switches over the
	camera and the steering that a tester flips to say which of two builds feels better, and it comes
	out of here as more toggle rows, last, under the real settings.

	THEY GO THROUGH THE SAME TWO FUNCTIONS AND ARE NOT A THIRD KIND. A knob has a title and a list of
	answers, a press hands a key back, and the repaint arrives on a state event, which is a `toggle`
	exactly. Neither screen learns anything, and `TuningConfig.Enabled = false` takes the lot off.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local AudioConfig = require(ReplicatedStorage.shared.Configs.AudioConfig)
local CameraTuningConfig = require(ReplicatedStorage.shared.Configs.CameraTuningConfig)
local DayNightConfig = require(ReplicatedStorage.shared.Configs.DayNightConfig)
local InterfaceConfig = require(ReplicatedStorage.shared.Configs.InterfaceConfig)
local MusicConfig = require(ReplicatedStorage.shared.Configs.MusicConfig)
local StealJuiceConfig = require(ReplicatedStorage.shared.Configs.StealJuiceConfig)
local TuningConfig = require(ReplicatedStorage.shared.Configs.TuningConfig)

local SettingsRows = {}

export type Option = { Key: string, Name: string }

export type Spec = {
	Kind: "toggle" | "slider",
	--- The setting's name, as the row prints it.
	Title: string,
	--- Toggle only: every answer, in the order pressing steps through them.
	Options: { Option }?,
	--- What the feature's controller is holding right now: an option key, or a 0 to 1.
	current: () -> any,
	--- Toggle only. False means the controller behind it is not up and the press did nothing.
	choose: ((key: string) -> boolean)?,
	--- Slider only. `persist` is the "this was a decision" flag; see the header.
	set: ((value: number, persist: boolean) -> boolean)?,
}

--[[ What a settings screen has to subscribe to so its rows repaint when something moves, however it
	moved: the screen itself, the server's saved answer landing while the screen happens to be open,
	or the H key toggling the interface from underneath it.

	EVERY EVENT SHOULD REPAINT EVERY ROW rather than only its own. A repaint is a handful of
	properties, so telling them apart would cost more code than it saves work, and it would be a
	second place that has to learn about a fifth setting. ]]
SettingsRows.StateEvents = {
	DayNightConfig.StateEvent,
	InterfaceConfig.StateEvent,
	StealJuiceConfig.Setting.StateEvent,
	AudioConfig.Music.StateEvent,
	AudioConfig.Sfx.StateEvent,
	--- One event for the whole tuning rack rather than one per knob, which is the same argument the
	--- block above makes: every event repaints every row anyway.
	TuningConfig.StateEvent,
	--- And one for the camera bench, for the same reason: a preset pressed in the admin panel has to
	--- move the row on a settings screen that happens to be open behind it.
	CameraTuningConfig.StateEvent,
}

--[[ The rows, built rather than written out, so a feature that is switched off leaves no gap: it
	simply is not in the list, the rows below move up, and the canvas shrinks to however many are
	left. That is why `SettingsConfig.hasRows` is an `or` of the same switches and not a count.

	`hideScreen` is called just before the interface is hidden, and only then. It is a callback rather
	than something this module does, because "put your own page away" is the one thing here that only
	the screen can do. See the block at the Interface row for why it is not optional. ]]
function SettingsRows.build(hideScreen: (() -> ())?): { Spec }
	local specs: { Spec } = {}

	if DayNightConfig.Enabled then
		table.insert(specs, {
			Kind = "toggle",
			Title = DayNightConfig.Copy.Row,
			Options = DayNightConfig.Copy.Options,
			current = function()
				local controller = Shard.get("DayNightController")
				return if controller then controller:preference() else DayNightConfig.Preference.Auto
			end,
			choose = function(key: string)
				local controller = Shard.get("DayNightController")
				if not controller then
					return false
				end
				controller:setPreference(key, true)
				return true
			end,
		})
	end

	if InterfaceConfig.Enabled then
		table.insert(specs, {
			Kind = "toggle",
			Title = InterfaceConfig.Copy.Row,
			Options = InterfaceConfig.Copy.Options,
			current = function()
				local controller = Shard.get("InterfaceController")
				return if controller then controller:visibility() else InterfaceConfig.Default
			end,
			--[[ HIDING CLOSES THE SCREEN FIRST, and it has to, for a reason `InterfaceController`
				spells out at `_hold`: the sweep records what each ScreenGui was doing so it can put it
				back, and a page still up when the sweep runs is a page the restore faithfully brings
				back. Closing on the way is not enough either, because a normal close only hides the
				frame in the tail of a tween. So the screen hides itself on the spot and lets its tween
				run over an already invisible frame. ]]
			choose = function(key: string)
				local controller = Shard.get("InterfaceController")
				if not controller then
					return false
				end
				if key == InterfaceConfig.Visibility.Hidden and hideScreen then
					hideScreen()
				end
				controller:setVisibility(key)
				return true
			end,
		})
	end

	--[[ The steal cinematic (2026-10-02, `StealJuiceConfig.Setting`), with the other settings a player
		keeps and above the sliders. `StealCinematicController` owns the answer. ]]
	local cinematic = StealJuiceConfig.Setting
	if cinematic.Enabled and StealJuiceConfig.Cinematic.Enabled then
		table.insert(specs, {
			Kind = "toggle",
			Title = cinematic.Copy.Row,
			Options = cinematic.Copy.Options,
			current = function()
				local controller = Shard.get("StealCinematicController")
				return if controller then controller:preference() else cinematic.Default
			end,
			choose = function(key: string)
				local controller = Shard.get("StealCinematicController")
				if not controller then
					return false
				end
				controller:setPreference(key, true)
				return true
			end,
		})
	end

	if AudioConfig.Enabled and AudioConfig.Music.Enabled and MusicConfig.Enabled then
		table.insert(specs, {
			Kind = "slider",
			Title = AudioConfig.Music.Copy.Row,
			current = function()
				local controller = Shard.get("MusicController")
				return if controller then controller:volume() else AudioConfig.Music.Default
			end,
			set = function(value: number, persist: boolean)
				local controller = Shard.get("MusicController")
				if not controller then
					return false
				end
				controller:setVolume(value, persist)
				return true
			end,
		})
	end

	if AudioConfig.Enabled and AudioConfig.Sfx.Enabled then
		table.insert(specs, {
			Kind = "slider",
			Title = AudioConfig.Sfx.Copy.Row,
			current = function()
				local controller = Shard.get("SoundController")
				return if controller then controller:volume() else AudioConfig.Sfx.Default
			end,
			set = function(value: number, persist: boolean)
				local controller = Shard.get("SoundController")
				if not controller then
					return false
				end
				controller:setVolume(value, persist)
				return true
			end,
		})
	end

	--- The cars' own level (2026-10-15, `AudioConfig.Car`), under the sound effects it used to ride.
	if AudioConfig.Enabled and AudioConfig.Sfx.Enabled and AudioConfig.Car.Enabled then
		table.insert(specs, {
			Kind = "slider",
			Title = AudioConfig.Car.Copy.Row,
			current = function()
				local controller = Shard.get("SoundController")
				return if controller then controller:carVolume() else AudioConfig.Car.Default
			end,
			set = function(value: number, persist: boolean)
				local controller = Shard.get("SoundController")
				if not controller then
					return false
				end
				controller:setCarVolume(value, persist)
				return true
			end,
		})
	end

	--[[ THE CAMERA MODE, first of the test rows and last of the ones that read like settings, which
		is where it belongs on both counts. It is a preset picker over `CameraConfig`, so it is a
		playtest control like the knobs below it, but it is the one a tester will actually be told to
		go and press and the one a stranger could make sense of unaided, so it goes above them.

		ONE ROW FOR SEVEN SHOTS. Every other thing on this screen asks a question with two or three
		answers; this one steps through the whole list `CameraTuningConfig` declares, which is what
		makes it worth a row rather than seven. Both screens already draw any number of answers (the
		shipping page slides a pill along a track, the kit page steps a caption on a button), so
		neither of them learns anything here.

		The full rack of forty-odd values behind these presets is in the admin panel's Camera tab,
		which is admin-gated. That split is the point: a tester gets six named shots and a press, and
		whoever is tuning gets every number and a report button. ]]
	if CameraTuningConfig.hasPresets() then
		table.insert(specs, {
			Kind = "toggle",
			Title = CameraTuningConfig.Copy.Row,
			Options = CameraTuningConfig.options(),
			current = function()
				local controller = Shard.get("CameraTuningController")
				--- No controller means nothing has been written, so the camera is on the shot the
				--- build ships and Default is the true answer. The same fallback every row above makes.
				return if controller then controller:preset() else CameraTuningConfig.DefaultPreset
			end,
			choose = function(key: string)
				local controller = Shard.get("CameraTuningController")
				if not controller then
					return false
				end
				--- It warns for itself, and with the reason, which is more than a false can carry.
				return controller:applyPreset(key)
			end,
		})
	end

	--[[ The playtest knobs, last, so the settings a player keeps stay at the top of the screen where
		they have always been. `TuningConfig` owns what the knobs are and `TuningController` owns the
		writing; this is one toggle row each and no knowledge of either. ]]
	if TuningConfig.Enabled then
		for _, knob in TuningConfig.Knobs do
			--[[ A knob names a field in somebody else's config by a path, and those configs are being
				edited this week. A path that no longer leads anywhere leaves NO ROW rather than a dead
				one: the same answer a switched-off feature gets above, and it agrees with
				`TuningController`, which drops the same knob at boot and says so in a warning. ]]
			if TuningConfig.read(knob) == nil then
				continue
			end

			table.insert(specs, {
				Kind = "toggle",
				Title = knob.Title,
				Options = knob.Options,
				current = function()
					local controller = Shard.get("TuningController")
					local answer = if controller then controller:answer(knob.Key) else nil
					--[[ No controller, or a knob it dropped at boot: nothing has been written, so what
						the config says now is still the shipped value and its answer is the true one.
						That is the same fallback every row above makes, reached the same way. ]]
					return answer or TuningConfig.baselineKey(knob, TuningConfig.read(knob))
				end,
				choose = function(key: string)
					local controller = Shard.get("TuningController")
					if not controller then
						return false
					end
					--- It warns for itself, and with the reason, which is more than a false can carry.
					return controller:choose(knob.Key, key)
				end,
			})
		end
	end

	return specs
end

--[[ The answer after this one, wrapping. Both screens step a toggle the same way and neither should
	own the arithmetic: it is the `Options` list's own rule. Returns nil when the current answer is
	not in the list at all, which is a controller and a config that have drifted apart. ]]
function SettingsRows.nextOption(spec: Spec, current: any): Option?
	local options = spec.Options
	if not options or #options == 0 then
		return nil
	end

	local index = 1
	for optionIndex, option in options do
		if option.Key == current then
			index = optionIndex
		end
	end
	return options[(index % #options) + 1]
end

--- Which answer is showing, as an index into `Options`. 1 when the current answer is not in the list.
function SettingsRows.indexOf(spec: Spec, current: any): number
	local options = spec.Options
	if not options then
		return 1
	end
	for index, option in options do
		if option.Key == current then
			return index
		end
	end
	return 1
end

return SettingsRows
