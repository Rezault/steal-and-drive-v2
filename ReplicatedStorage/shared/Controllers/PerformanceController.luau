-- One bounded local sample per run, including entry and return; one initial lobby sample.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Stats = game:GetService("Stats")
local Shard = require(RS.Packages.Shard)
local Dispatcher = require(RS.Packages.Dispatcher)
local Trove = require(RS.Packages.Trove)
local Config = require(RS.shared.Configs.PerformanceConfig)
local RaceConfig = require(RS.shared.Configs.RaceConfig)
local Sampler = require(RS.shared.Modules.PerformanceSampler)
local Controller = Shard.new("PerformanceController"):withDependencies({ "RaceFreezeController" })

function Controller._begin(self, kind)
	self._sample = Sampler.new(os.clock())
	self._sample.kind, self._sample.freezeTransitions = kind, 0
	self._sample.reasons = {}
	self._sample.unfocusedFrames, self._sample.unfocusedHitches = 0, 0
	self._phase = if kind == "lobby" then "lobby" else "loading"
	self._ended = false
	self:_memory()
end
function Controller._memory(self)
	local sample = self._sample if not sample then return end
	local ok, mb = pcall(Stats.GetTotalMemoryUsageMb, Stats)
	if ok then
		sample.memoryStartMb = sample.memoryStartMb or math.round(mb)
		sample.memoryMaxMb = math.max(sample.memoryMaxMb or 0, math.round(mb))
	end
end
function Controller._flush(self, reason)
	local sample = self._sample if not sample then return end
	self._sample = nil -- Cancel timers and duplicate lifecycle messages before firing anything.
	if sample.all.frames == 0 then return end
	local data = Sampler.snapshot(sample, os.clock())
	data.kind = if sample.kind == "run" and not sample.runId then "entryAttempt" else sample.kind
	data.runId, data.reason = sample.runId or "", reason
	data.freezeTransitions = sample.freezeTransitions
	local reasons = {} for k in sample.reasons do table.insert(reasons, k) end table.sort(reasons)
	data.freezeReasons = string.sub(table.concat(reasons, ","), 1, 160)
	data.memoryStartMb, data.memoryMaxMb = sample.memoryStartMb or 0, sample.memoryMaxMb or 0
	data.unfocusedFrames, data.unfocusedHitches = sample.unfocusedFrames, sample.unfocusedHitches
	data.focusObserved = self._focusObserved == true
	data.savedQualityLevel = UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	data.inputMethod = tostring(UIS.PreferredInput.Name)
	local road = Shard.get("RoadController")
	local perf = sample.kind == "run" and road and road._roadPerf
	data.roadOpeningFrames = perf and perf.openingFrames or 0
	data.roadOpeningMaxWorkMs = perf and perf.openingMaxWorkMs or 0
	data.roadInlineTiles = perf and perf.inlineTiles or 0
	pcall(function() self:getRemoteEvent("PerformanceReport"):Fire(data) end)
end
function Controller._entering(self)
	if not Config.Enabled then return end
	self:_flush("nextRun")
	self:_begin("run")
end
function Controller._freezeChanged(self, frozen)
	local sample = self._sample if not sample then return end
	sample.freezeTransitions += 1
	if frozen then
		for reason in self._freeze._holds do
			if type(reason) == "string" then sample.reasons[string.sub(reason, 1, 40)] = true end
		end
	end
end
function Controller._endedRun(self)
	self._phase = "results" self._ended = true
	local sample = self._sample
	if not sample then return end
	-- Direct abort/admin/teardown paths can omit the UI's Returned notification.
	task.delay(Config.EndTailSeconds, function() if self._sample == sample then self:_flush("endTimeout") end end)
end
Controller:withRemoteEvents({ "PerformanceReport", {
	PerformanceContext = function(runId)
		local sample = Controller._sample
		if sample and sample.kind == "run" and not sample.runId and type(runId) == "string" then sample.runId = runId end
	end,
	RaceEntering = function() Controller:_entering() end,
	RaceStart = function()
		if not Controller._sample or Controller._sample.kind ~= "run" then Controller:_entering() end
	end,
	RaceLive = function()
		if Controller._sample and Controller._sample.kind == "run" and not Controller._ended then
			Controller._phase = "driving"
		end
	end,
	RaceWrecked = function() Controller._phase = "results" end,
	RaceRevived = function() Controller._phase = "loading" end,
	RaceEnd = function() Controller:_endedRun() end,
} })
Controller:withLifecycle({
	init = function(self)
		self._trove = Trove.new() self._focused = true self._focusObserved = false
	end,
	start = function(self)
		if not Config.Enabled then return end
		self._freeze = Shard.get("RaceFreezeController")
		self:_begin("lobby")
		local lobby = self._sample
		task.delay(Config.LobbySeconds, function() if self._sample == lobby then self:_flush("lobby") end end)
		self._trove:Add(self._freeze:getSignal("FreezeChanged"):Connect(function(value) self:_freezeChanged(value) end))
		self._trove:Add(UIS.WindowFocused:Connect(function() self._focused = true self._focusObserved = true end))
		self._trove:Add(UIS.WindowFocusReleased:Connect(function() self._focused = false self._focusObserved = true end))
		self._trove:Add(RunService.RenderStepped:Connect(function(dt)
			local sample = self._sample if not sample then return end
			local phase = self._phase
			if phase == "driving" and self._freeze:isHeld() then phase = "paused" end
			Sampler.record(sample, dt, phase, os.clock())
			if not self._focused then
				sample.unfocusedFrames += 1
				if dt * 1000 > Config.HitchMs then sample.unfocusedHitches += 1 end
			end
		end))
		local elapsed = 0
		self._trove:Add(RunService.Heartbeat:Connect(function(dt)
			elapsed += dt if elapsed < 5 then return end elapsed = 0 self:_memory()
		end))
		Dispatcher:Subscribe(RaceConfig.LiftingEvent, function() if self._sample and self._ended then self._phase = "returning" end end)
		Dispatcher:Subscribe(RaceConfig.ReturnedEvent, function()
			local sample = self._sample if not sample or sample.kind ~= "run" then return end
			self._phase = "home"
			task.delay(Config.HomeTailSeconds, function() if self._sample == sample then self:_flush("returned") end end)
		end)
	end,
})
Controller:withCleanup(function() if Controller._trove then Controller._trove:Destroy() end end)
return Controller

