-- Client performance observations are diagnostic only; no gameplay trusts these reports.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Shard = require(RS.Packages.Shard)
local Trove = require(RS.Packages.Trove)
local Config = require(RS.shared.Configs.PerformanceConfig)
local Service = Shard.new("PerformanceService"):withDependencies({ "RaceService", "AnalyticsService" })
local numeric = {
	durationSeconds=true,frames=true,p50Ms=true,p95Ms=true,p99Ms=true,worstMs=true,
	over50=true,over100=true,over250=true,repeatHitchPairs=true,maxRepeatStreak=true,
	freezeTransitions=true,memoryStartMb=true,memoryMaxMb=true,unfocusedFrames=true,unfocusedHitches=true,
	savedQualityLevel=true,roadOpeningFrames=true,roadOpeningMaxWorkMs=true,roadInlineTiles=true,
}
for _,p in Config.Phases do for _,suffix in { "Frames", "Seconds", "P95Ms", "WorstMs", "Over100" } do numeric[p..suffix]=true end end
local strings = { recentHitches=800,freezeReasons=160,inputMethod=20 }
function Service.sanitize(payload)
	if type(payload) ~= "table" then return nil end
	if not ({ lobby=true,run=true,entryAttempt=true })[payload.kind] then return nil end
	if not ({ lobby=true,nextRun=true,returned=true,endTimeout=true })[payload.reason] then return nil end
	local out = { kind=payload.kind,reason=payload.reason }
	local count=0
	for key,value in payload do
		count+=1 if count>96 then return nil end
		if numeric[key] then
			if type(value)~="number" or value~=value or value<0 or value==math.huge or value>20000000 then return nil end
			out[key]=value
		elseif strings[key] then
			if type(value)~="string" or #value>strings[key] then return nil end out[key]=value
		elseif key=="runId" then
			if type(value)~="string" or #value>40 then return nil end out.runId=value
		elseif key=="focusObserved" then
			if type(value)~="boolean" then return nil end out.focusObserved=value
		end
	end
	if not out.frames or out.frames<1 or not out.durationSeconds or out.durationSeconds>86400 then return nil end
	local frames=0 for _,p in Config.Phases do frames+=out[p.."Frames"] or 0 end
	if frames~=out.frames then return nil end
	if not(out.p50Ms and out.p95Ms and out.p99Ms and out.worstMs and out.over50 and out.over100 and out.over250) then return nil end
	if out.p50Ms>out.p95Ms or out.p95Ms>out.p99Ms or out.p99Ms>out.worstMs or out.worstMs>60000 then return nil end
	if out.over250>out.over100 or out.over100>out.over50 or out.over50>out.frames then return nil end
	return out
end
function Service._state(self, player)
	local s=self._states[player]
	if not s then s={contexts={},number=0,reports=0,nextAt=0} self._states[player]=s end
	return s
end
function Service._entered(self, player)
	local s=self:_state(player) s.number+=1
	local race=Shard.get("RaceService")
	local context={id=HttpService:GenerateGUID(false),number=s.number,world=race:worldForRun(player),startedAt=os.clock()}
	table.insert(s.contexts,context) if #s.contexts>2 then table.remove(s.contexts,1) end
	self:getRemoteEvent("PerformanceContext"):Fire(player,context.id)
end
function Service._report(self, player, payload)
	if not Config.Enabled or player.Parent~=Players then return false end
	local s=self:_state(player) local now=os.clock()
	if now<s.nextAt or s.reports>=Config.MaxReportsPerSession then return false end
	s.nextAt=now+Config.ReportCooldown
	local data=self.sanitize(payload) if not data then return false end
	if data.kind=="lobby" then if s.lobbySeen then return false end s.lobbySeen=true end
	local matched
	if data.kind=="run" then
		for _,c in s.contexts do if c.id==data.runId then matched=c break end end
		if not matched or matched.reported then return false end matched.reported=true
	end
	s.reports+=1
	data.schemaVersion=Config.Version data.placeVersion=game.PlaceVersion data.clientReported=true
	data.runNumber=matched and matched.number or 0 data.world=matched and matched.world or 0
	data.serverRunMatched=matched~=nil data.firstTileIncremental=require(RS.shared.Configs.RaceConfig).FirstTileIncremental~=false
	if RunService:IsStudio() then
		table.insert(self._diagnostics,data) if #self._diagnostics>20 then table.remove(self._diagnostics,1) end
	end
	local analytics=Shard.get("AnalyticsService")
	if analytics then pcall(function() analytics:Marker(player,"PerformanceSummary",data) end) end
	return true
end
Service:withRemoteEvents({ "PerformanceContext", { PerformanceReport=function(player,payload) Service:_report(player,payload) end } })
Service:withLifecycle({
	init=function(self) self._states={} self._diagnostics={} self._trove=Trove.new() end,
	start=function(self)
		if not Config.Enabled then return end
		self._trove:Add(Shard.get("RaceService"):getSignal("RaceEntered"):Connect(function(player) self:_entered(player) end))
		self._trove:Add(Players.PlayerRemoving:Connect(function(player) self._states[player]=nil end))
	end,
})
Service:withCleanup(function() if Service._trove then Service._trove:Destroy() end end)
return Service

