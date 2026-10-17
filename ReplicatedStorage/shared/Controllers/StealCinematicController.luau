--[[
	StealCinematicController  (client)
	----------------------------------
	The player's answer to "do I want the cinematic steal camera?" (`StealJuiceConfig.Setting`). It
	holds the answer, the settings screen reads and presses it (`SettingsRows`), and
	`StealController._startCinematic` asks `wanted()` on every steal.

	A FILE OF ITS OWN RATHER THAN A CORNER OF `StealController`, which is four thousand lines of steal
	and should not also be a settings owner. Shaped exactly like `DayNightController`'s setting half:
	applied the instant it is pressed, told to `SettingsService` afterwards, seeded once off the
	player attribute, and a seed that lands after a press is dropped (`_touched`), so a slow profile
	cannot undo the player's choice.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local StealJuiceConfig = require(ReplicatedStorage.shared.Configs.StealJuiceConfig)

local StealCinematicController = Shard.new("StealCinematicController")

--- Public: "on" or "off". The settings row puts its toggle on this.
function StealCinematicController.preference(self): string
	return self._preference
end

--- Public (`StealController._startCinematic`): should this steal get the cinematic?
function StealCinematicController.wanted(self): boolean
	return self._preference ~= StealJuiceConfig.Setting.Off
end

--[[ Public (`SettingsRows`): pick one. `persist` is a press (sent to be saved) as against the seed
	(the saved answer arriving, which must not be sent straight back). ]]
function StealCinematicController.setPreference(self, preference: unknown, persist: boolean?)
	local key = StealJuiceConfig.resolveSetting(preference)
	self._preference = key
	Dispatcher:Publish(StealJuiceConfig.Setting.StateEvent, key)
	if persist then
		self._touched = true
		self:getRemoteEvent(StealJuiceConfig.Setting.RemoteName):Fire(key)
	end
end

--- The server's saved answer, once, and never over a press (header).
function StealCinematicController._seed(self, preference: unknown)
	if self._seeded or self._touched then
		return
	end
	self._seeded = true
	self:setPreference(preference, false)
end

StealCinematicController:withRemoteEvents({
	StealJuiceConfig.Setting.RemoteName,
})

StealCinematicController:withLifecycle({
	init = function(self)
		self._preference = StealJuiceConfig.Setting.Default
		self._seeded = false
		self._touched = false
	end,

	start = function(self)
		if not StealJuiceConfig.Setting.Enabled then
			return
		end
		local player = Players.LocalPlayer
		local attribute = StealJuiceConfig.Setting.Attribute
		local existing = player:GetAttribute(attribute)
		if existing ~= nil then
			self:_seed(existing)
			return
		end
		local connection
		connection = player:GetAttributeChangedSignal(attribute):Connect(function()
			connection:Disconnect()
			self:_seed(player:GetAttribute(attribute))
		end)
		--- A profile that never lands leaves the player on the default, which they were already on.
		task.delay(StealJuiceConfig.Setting.SeedTimeout, function()
			if not self._seeded and not self._touched then
				connection:Disconnect()
				self:_seed(StealJuiceConfig.Setting.Default)
			end
		end)
	end,
})

return StealCinematicController
