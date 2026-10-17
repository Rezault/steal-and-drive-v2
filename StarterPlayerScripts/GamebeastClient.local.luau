--[[
	The Gamebeast SDK's client half. It reports device, input type, FPS and session info that the
	server cannot see, and the server's markers wait for it before sending (see `AnalyticsService`).

	No key on the client: the SDK asserts against one. The key lives server side in
	`AnalyticsService`. pcall so a Gamebeast failure never stops a player's client from booting.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ok, err = pcall(function()
	local Gamebeast = require(ReplicatedStorage:WaitForChild("Gamebeast"))
	Gamebeast:Setup()
end)
if not ok then
	warn("[Gamebeast] client setup failed:", err)
end
