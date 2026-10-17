-- Forward confirmed showroom placement to its owner; feedback never changes the transaction.
local RS=game:GetService("ReplicatedStorage")
local Shard=require(RS.Packages.Shard)
local Service=Shard.new("GameplayFeedbackService"):withDependencies({"GarageService"})
Service:withRemoteEvents({"CarParkedFeedback"})
Service:withLifecycle({
 start=function(self)
  local garage=Shard.get("GarageService")
  workspace:SetAttribute("GameplayFeedbackServerReady",true)
  self._parked=garage:getSignal("CarParked"):Connect(function(player,_body,_tier,bay)
   if not garage:isWorkshopBay(bay) then self:getRemoteEvent("CarParkedFeedback"):Fire(player) end
  end)
 end,
})
Service:withCleanup(function()
 if Service._parked then Service._parked:Disconnect();Service._parked=nil end
end)
return Service
