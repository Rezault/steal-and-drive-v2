-- Transition feedback, with no extra gameplay state or profile writes.
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Shard=require(RS.Packages.Shard)
local Feedback=require(RS.shared.Modules.GameplayFeedback)
local Schedule=require(RS.shared.Modules.StealReminderSchedule)
local Controller=Shard.new("GameplayFeedbackController"):withDependencies({"StealController","NitroController","NearMissController"})
function Controller._step(self)
 if not self._racing then return end
 local steal=self._steal:canSteal()
 if steal and self._canSteal==false then Feedback.play("StealReady") end
 self._canSteal=steal
 local ready=self._nitro:isRunning() and self._nitro:isEnabled() and self._nitro:canFire()
 if ready and self._nitroReady==false then Feedback.play("NitroReady") end
 self._nitroReady=ready
 local streak=self._nearMiss:getStreak()
 if self._streak and self._streak>=2 and streak==0 then Feedback.play("ComboLost") end
 self._streak=streak
end
Controller:withRemoteEvents({{
 CarParkedFeedback=function() Feedback.play("Parked") end,
 RaceStart=function()
  Controller._racing=true
  Controller._canSteal=nil;Controller._nitroReady=nil;Controller._streak=0
  Schedule.reset()
 end,
 RaceRevived=function()
  Controller._racing=true
  Controller._canSteal=nil;Controller._nitroReady=nil;Controller._streak=0
  Feedback.play("Revived")
 end,
 RaceWrecked=function() Controller._racing=false end,
 RaceEnd=function() Controller._racing=false;Schedule.reset() end,
 RaceEndPanel=function() Controller._racing=false end,
}})
Controller:withLifecycle({
 init=function(self) self._racing=false end,
 start=function(self)
  self._steal=Shard.get("StealController")
  self._nitro=Shard.get("NitroController")
  self._nearMiss=Shard.get("NearMissController")
  Feedback.preload()
  game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"):SetAttribute("GameplayFeedbackReady",true)
  self._heartbeat=RunService.Heartbeat:Connect(function() self:_step() end)
 end,
})
Controller:withCleanup(function()
 if Controller._heartbeat then Controller._heartbeat:Disconnect();Controller._heartbeat=nil end
end)
return Controller
