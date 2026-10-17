--[[
	SettingsConfig
	--------------
	THE SETTINGS SCREEN ITSELF, and only the screen. Read by `UIController/Pages/Settings`, which
	wires it, and by `TopbarController`, which owns the button that opens it.

	IT HOLDS ALMOST NOTHING, AND THAT IS THE DESIGN. A setting's words, its stored key, its remote
	and its default all belong to the feature the setting is about, exactly as the radio's do
	(`RadioConfig.Copy`), the sky's do (`DayNightConfig`) and both volumes' do (`AudioConfig`). What
	is left over is the screen's own chrome: whether there is one at all, and where to find it.

	THAT HAS NOW HELD UP FIVE TIMES, which is the only test of a claim like this one. Hiding the UI
	cost a new `InterfaceConfig` and one extra term in `hasRows`. The two volume sliders cost a new
	`AudioConfig` and one more. A whole rack of playtest knobs cost a new `TuningConfig` and one more
	again, nine rows for one term. A bench of seven camera presets and forty-four live camera values
	cost a new `CameraTuningConfig` and one more again, and of all of that only the preset picker
	landed on this screen. Nothing else in this file has ever moved. If it grows a table of rows,
	that is the sign the screen has started deciding things about features it should know nothing
	about.

	=== IT IS A `UIController` PAGE NOW ========================================================

	It used to be a `SettingsController` that built its own ScreenGui out of Frames, because at the
	time nothing in `MainUI` could open it and making it a page would have meant inventing the one
	page with no button. That stopped being true when the boss authored a settings screen into
	`StarterGui.MainUI.Pages.Settings`: the art exists, so the screen is a page like every other and
	the topbar reaches it through `TopbarController._buildPageDoor` rather than through a controller.

	`PageName` below is the contract between those two halves, and it has to match the name of the
	Frame in the place.

	WHY THE MUTE IS NOT A ROW OF ITS OWN. It is a fair question, because a music toggle is the most
	settings-shaped thing in the game. It does not need one: the MUSIC slider IS the mute now
	(`MusicController`'s header — muted is what zero means), so the topbar button and this screen are
	two handles on one number rather than two settings that have to agree.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- The features with a row on this screen. All three require nothing, so all three are leaf
--- dependencies and none can cycle back through here the way a require of anything gameplay-shaped
--- would. The same argument `WeatherConfig` makes for requiring `UIAssets`.
local AudioConfig = require(ReplicatedStorage.shared.Configs.AudioConfig)
local CameraTuningConfig = require(ReplicatedStorage.shared.Configs.CameraTuningConfig)
local DayNightConfig = require(ReplicatedStorage.shared.Configs.DayNightConfig)
local InterfaceConfig = require(ReplicatedStorage.shared.Configs.InterfaceConfig)
local StealJuiceConfig = require(ReplicatedStorage.shared.Configs.StealJuiceConfig)
local TuningConfig = require(ReplicatedStorage.shared.Configs.TuningConfig)

local SettingsConfig = {}

--[[ Master switch. Off = no settings button in the topbar. Every setting the screen shows has its
	own switch as well, so this is for taking the SCREEN out rather than for taking a setting off
	it: a panel with every row switched off is an empty box, which is worse than no button.

	IT NO LONGER STOPS THE PAGE BEING BUILT, because a page is built by `UIController` from what is
	under `Pages` and this file is not consulted. What it stops is the way in. ]]
SettingsConfig.Enabled = true

--- The Frame under `StarterGui.MainUI.Pages`, and the name `UIController` files the page under.
--- Renaming it in the Explorer means renaming it here.
SettingsConfig.PageName = "Settings"

SettingsConfig.Copy = {
	--- On the blue cap. Authored into the place as well; this is what a caller that has to SAY the
	--- screen's name uses.
	Title = "Settings",
}

--[[ Whether the screen has anything on it, which is what the topbar asks before it puts a button
	up. Four settings today, plus however many playtest knobs `TuningConfig` is carrying and the
	camera preset picker. A new setting adds its own switch to this `or` and nothing else.

	It is a function rather than a constant because every switch it reads is a config value that a
	build can turn off, and a constant computed at require time would be right for as long as
	nobody changed one at runtime, which is exactly the situation Studio is. ]]
function SettingsConfig.hasRows(): boolean
	return DayNightConfig.Enabled == true
		or InterfaceConfig.Enabled == true
		or StealJuiceConfig.Setting.Enabled == true
		or (AudioConfig.Enabled == true and (AudioConfig.Music.Enabled == true or AudioConfig.Sfx.Enabled == true))
		or TuningConfig.hasKnobs()
		or CameraTuningConfig.hasPresets()
end

return SettingsConfig
