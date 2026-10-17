-- Named one-shot feedback. Clips use existing place audio and are independently replaceable.
local Config = { Enabled = true, MaximumActive = 3 }
Config.Cues = {
 TutorialStep = { Name="TutorialStep", Cooldown=0.4, Duration=0.8 },
 TutorialComplete = { Name="TutorialComplete", Cooldown=2, Duration=1.5 },
 Parked = { Name="Parked", Cooldown=0.8, Duration=0.65 },
 OfferArrived = { Name="OfferArrived", Cooldown=8, Duration=0.5 },
 -- A seller at the kerb (`SellerConfig.Sound`); silent until a clip named SellerArrived is added.
 SellerArrived = { Name="SellerArrived", Cooldown=8, Duration=1.5 },
 StealReady = { Name="StealReady", Cooldown=2, Duration=0.6 },
 NitroReady = { Name="NitroReady", Cooldown=4, Duration=0.6 },
 RampCaptured = { Name="RampCaptured", Cooldown=2, Duration=0.65 },
 Docked = { Name="Docked", Cooldown=2, Duration=0.65 },
 ComboLost = { Name="ComboLost", Cooldown=3, Duration=0.4 },
 LuckRaised = { Name="LuckRaised", Cooldown=4, Duration=1.2, Priority=true },
 EventStarted = { Name="EventStarted", Cooldown=15, Duration=1 },
 Revived = { Name="Revived", Cooldown=2, Duration=1 },
 RandomResolved = { Name="RandomResolved", Cooldown=1, Duration=1.2 },
 DailyClaimed = { Name="DailyClaimed", Cooldown=1, Duration=1 },
}
Config.NamedCooldown = {
 ["Collection:Discovered"]=1, ["Steal:RareSpotted"]=10,
 ["Upgrade:Upgraded"]=0.5, ["Buyer:GreatOffer"]=8, ["Buyer:Sold"]=0.5, ["UI:Denied"]=0.7,
}
return Config
