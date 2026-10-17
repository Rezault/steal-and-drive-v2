--[[
	AnalyticsController  (client)
	-----------------------------
	The one thing analytics needs from a client: which screens players open (2026-10-15). Everything
	else `AnalyticsService` counts happens on the server, and the Gamebeast SDK has no client-side
	markers, so a screen opening has to be told to the server to be counted at all.

	It LISTENS, it is never called. `UIController:openPage` already publishes `PageOpened` on the
	`Dispatcher` for every page that opens, by whatever button or prompt, so this subscribes to that
	and nothing in the UI has to know analytics exists.

	`Dispatcher:Publish` runs subscribers inline on the publisher's thread, and one that throws stops
	`openPage` mid-way (`Packages/Dispatcher`). So the send is pcall'd: analytics is allowed to fail,
	a page is not allowed to stop opening because of it.

	The server decides what counts (`AnalyticsService._onPageOpened`): which pages, how often, and how
	many a session. This sends every open and lets it.

	AND THE END OF A RUN: RACE AGAIN OR HOME (2026-10-15). Asked for to settle whether RACE AGAIN
	should stay on the end panel, in the tutorial above all. The panel (`ReviveController`) already
	announces its answer on `RaceConfig.WreckAnsweredEvent` for `RaceUIController`, with how it was
	given (a press, or the countdown) and which panel it was ("revive", "bank", "wreck"), and the
	server never learns which button it was, so this passes it on. Same pcall, same reason.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)

local AnalyticsController = Shard.new("AnalyticsController")

AnalyticsController:withRemoteEvents({ "AnalyticsPageOpened", "AnalyticsEndChoice" })

AnalyticsController:withLifecycle({
	start = function(self)
		Dispatcher:Subscribe("PageOpened", function(pageName: string)
			pcall(function()
				self:getRemoteEvent("AnalyticsPageOpened"):Fire(pageName)
			end)
		end)
		Dispatcher:Subscribe(RaceConfig.WreckAnsweredEvent, function(answer: string, how: string?, panel: string?)
			pcall(function()
				self:getRemoteEvent("AnalyticsEndChoice"):Fire(answer, how, panel)
			end)
		end)
	end,
})

return AnalyticsController
