# Graph Report - steal and drive TS  (2026-10-22)

## Corpus Check
- 388 files · ~1,552,143 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 1 file(s) not represented in the graph (top: (none) 1)

## Summary
- 1017 nodes · 2305 edges · 89 communities (30 shown, 59 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 45 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `4b2bbf42`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- StealTagController.luau
- DriveConfig.luau
- Car Lights & Claim Badges
- DrivingHudController.luau
- TestEngineController.luau
- CarViewportGrid.luau
- NoticeLane.luau
- StealNudgeController.luau
- Iris Widget Core
- ShopConfig.luau
- ProfileStore (Packages)
- TrafficController.luau
- ProfileStore (Libraries)
- CarryController.luau
- ArcadeKit.luau
- Basic Page & Upgrades
- ReplicaServer
- Iris Input & Plot
- AudioConfig.luau
- TutorialController.luau
- Player Profile
- Group Rewards
- Guide Trail
- Arcade Traffic Impact
- CodesService.luau
- PaintConfig.luau
- SellConfig.luau
- ReplicaClient
- Tips
- Gameplay Feedback
- Iris Window Layout
- Iris Interaction Handlers
- Signal
- InterfaceConfig.luau
- InventoryConfig.luau
- SaleTagController.luau
- Mobile Menu Sizing
- CarStats.luau
- LivePrice.luau
- Gift Picker
- Showroom Economy
- Profile Reset
- CarRarity.luau
- ShowcaseController.luau
- convoy/run.sh
- StealController.luau
- ShellDoors.luau
- RareCarBannerController.luau
- run.sh

## God Nodes (most connected - your core abstractions)
1. `TestEngineController._sync()` - 6 edges
2. `paint()` - 6 edges
3. `widgets.getMouseLocation()` - 6 edges
4. `BuyerOfferSign.build()` - 6 edges
5. `CarStats.bodyOf()` - 6 edges
6. `FirstPersonCockpit.update()` - 6 edges
7. `CarLightsController._step()` - 5 edges
8. `StealTagController._show()` - 5 edges
9. `TestEngineController._attach()` - 5 edges
10. `widgets.applyInteractionHighlights()` - 5 edges

## Surprising Connections (you probably didn't know these)
- `UIRoot.wait()` --calls--> `claim()`  [INFERRED]
  ReplicatedStorage/shared/Modules/UIRoot.luau → tests/playtime/harness.luau
- `UIRoot.find()` --calls--> `claim()`  [INFERRED]
  ReplicatedStorage/shared/Modules/UIRoot.luau → tests/playtime/harness.luau
- `Cue.describe()` --calls--> `RewardConfig.levelOf()`  [INFERRED]
  ReplicatedStorage/shared/Modules/TrafficCollectionCue.luau → ReplicatedStorage/shared/Configs/RewardConfig.luau
- `CarLightsController._step()` --calls--> `CarHeadlights.set()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/CarLightsController.luau → ReplicatedStorage/shared/Modules/CarHeadlights.luau
- `hex()` --calls--> `CarStats.bodyOf()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/StealNudgeController.luau → ReplicatedStorage/shared/Modules/CarStats.luau

## Import Cycles
- None detected.

## Communities (89 total, 59 thin omitted)

### Community 0 - "StealTagController.luau"
Cohesion: 0.26
Nodes (9): hitBoxOf(), roofOf(), screenScale(), StealTagController._build(), StealTagController._clear(), StealTagController._show(), banner(), UpgradeCelebrationController._play() (+1 more)

### Community 1 - "DriveConfig.luau"
Cohesion: 0.05
Nodes (17): HopController._bind(), HopController._setRacing(), HopController._step(), HopController._unbind(), LobbyDriveController._teardown(), LobbyDriveController._watch(), CarStats.bodyOf(), FirstPersonCabin.destroy() (+9 more)

### Community 2 - "Car Lights & Claim Badges"
Cohesion: 0.07
Nodes (19): IndexRewardConfig.bonusFor(), IndexRewardConfig.parseClaimed(), IndexRewardConfig.percentFor(), CarLightsController._bind(), CarLightsController._onRaceEnd(), CarLightsController._onRaceStart(), CarLightsController._step(), CarLightsController._unbind() (+11 more)

### Community 3 - "DrivingHudController.luau"
Cohesion: 0.06
Nodes (8): PickupController._build(), PickupController._tween(), StarController.isActive(), StarController.remaining(), ButtonScale.ensure(), ButtonScale.set(), Highlight.new(), Highlight.step()

### Community 4 - "TestEngineController.luau"
Cohesion: 0.09
Nodes (21): approach(), TestEngineController._attach(), TestEngineController._bodyOf(), TestEngineController._clearTails(), TestEngineController._detach(), TestEngineController._driveSound(), TestEngineController._mute(), TestEngineController._replaceEngine() (+13 more)

### Community 5 - "CarViewportGrid.luau"
Cohesion: 0.47
Nodes (3): CarViewportGrid:_drain(), CarViewportGrid:refresh(), CarViewportGrid:_release()

### Community 6 - "NoticeLane.luau"
Cohesion: 0.10
Nodes (10): InventoryLimitController._build(), InventoryLimitController._fit(), InventoryLimitController._refresh(), InventoryLimitController._show(), inLane(), OfflineLabelController._apply(), OfflineLabelController._watchRival(), OfflineLabelController._yielding() (+2 more)

### Community 7 - "StealNudgeController.luau"
Cohesion: 0.10
Nodes (13): CarConfig.maxSpeedOf(), hex(), StealNudgeController._niceCarLine(), StealNudgeController._onRaceStart(), StealNudgeController._reset(), StealNudgeController._step(), Schedule.canShow(), Schedule.claim() (+5 more)

### Community 8 - "Iris Widget Core"
Cohesion: 0.07
Nodes (4): widgets.applyFrameStyle(), widgets.UICorner(), widgets.UIPadding(), widgets.UIStroke()

### Community 11 - "ShopConfig.luau"
Cohesion: 0.09
Nodes (5): PassConfig.ownedAttribute(), ShopConfig.isSellable(), ShopConfig.visibleBundles(), ShopConfig.visiblePasses(), priceLabel()

### Community 15 - "ProfileStore (Packages)"
Cohesion: 0.13
Nodes (7): AcquireRunnerThreadAndCallEventHandler(), Profile:EndSession(), Profile:IsActive(), Profile:MessageHandler(), ProfileStore:VersionQuery(), ProfileVersionQuery.New(), RunEventHandlerInFreeThread()

### Community 18 - "ProfileStore (Libraries)"
Cohesion: 0.14
Nodes (5): Profile:EndSession(), Profile:IsActive(), Profile:MessageHandler(), ProfileStore:VersionQuery(), ProfileVersionQuery.New()

### Community 20 - "CarryController.luau"
Cohesion: 0.16
Nodes (3): DealershipMarkerController._build(), UpgradeNudgeController._build(), UpgradeNudgeController._machine()

### Community 21 - "ArcadeKit.luau"
Cohesion: 0.17
Nodes (6): DiscoveryController._build(), DiscoveryController._next(), LuckProgressController._advance(), LuckProgressController._hide(), LuckProgressController._pause(), LuckProgressController._step()

### Community 26 - "Basic Page & Upgrades"
Cohesion: 0.18
Nodes (6): findCloseButton(), Page.new(), KitPage.scaleTextCaps(), Page.initialize(), Page:_repaint(), Page:StartOpenThread()

### Community 28 - "Iris Input & Plot"
Cohesion: 0.21
Nodes (9): UpdateComboState(), widgets.getMouseLocation(), widgets.isPosInsideRect(), SliderMouseDown(), updateActiveSlider(), clearBlock(), clearLine(), updateBlock() (+1 more)

### Community 35 - "Player Profile"
Cohesion: 0.25
Nodes (5): PlayerProfile:Decrement(), PlayerProfile:Increment(), PlayerProfile:IsActive(), PlayerProfile:Set(), PlayerProfile:_setRecursive()

### Community 37 - "Group Rewards"
Cohesion: 0.33
Nodes (7): claimed(), GroupRewardController._bind(), GroupRewardController._dance(), GroupRewardController._paint(), GroupRewardController._press(), GroupRewardController._showStatus(), line()

### Community 39 - "Arcade Traffic Impact"
Cohesion: 0.27
Nodes (4): ArcadeTrafficImpact.step(), fade(), overlaps(), reach()

### Community 41 - "CodesService.luau"
Cohesion: 0.28
Nodes (3): amountFor(), CodesService._redeem(), CodesService._reply()

### Community 44 - "SellConfig.luau"
Cohesion: 0.22
Nodes (4): GarageConfig.decodeConditions(), MarketValueConfig.broadcastRecord(), SellConfig.lotPriceForOwner(), SellConfig.lotPriceOf()

### Community 51 - "Iris Window Layout"
Cohesion: 0.33
Nodes (5): widgets.findBestWindowPosForPopup(), widgets.getScreenSizeForWindow(), fitPositionToWindowBounds(), fitSizeToWindowBounds(), relocateTooltips()

### Community 53 - "Iris Interaction Handlers"
Cohesion: 0.53
Nodes (6): widgets.applyInputBegan(), widgets.applyInputEnded(), widgets.applyInteractionHighlights(), widgets.applyInteractionHighlightsWithMultiHighlightee(), widgets.applyMouseEnter(), widgets.applyMouseLeave()

### Community 54 - "Signal"
Cohesion: 0.33
Nodes (3): AcquireRunnerThreadAndCallEventHandler(), RunEventHandlerInFreeThread(), RunEventHandlerInFreeThread()

### Community 57 - "InterfaceConfig.luau"
Cohesion: 0.38
Nodes (3): InterfaceConfig.isVisibility(), InterfaceConfig.resolve(), InterfaceConfig.statusFor()

### Community 58 - "InventoryConfig.luau"
Cohesion: 0.13
Nodes (4): BalanceConfig.roadValue(), RewardConfig.decodeLevels(), RewardConfig.levelOf(), RewardConfig.perStudFor()

### Community 63 - "CarStats.luau"
Cohesion: 0.33
Nodes (6): CarConfig.maxHealthOf(), CarConfig.statsFor(), CarStats.apply(), CarStats.maxHealthOf(), CarStats.reapply(), stamp()

### Community 64 - "LivePrice.luau"
Cohesion: 0.83
Nodes (3): keyOf(), LivePrice.fetch(), LivePrice.peek()

### Community 67 - "Showroom Economy"
Cohesion: 1.00
Nodes (3): floorOf(), sample(), ShowroomEconomy.estimate()

### Community 94 - "RareCarBannerController.luau"
Cohesion: 0.60
Nodes (5): RareCarBannerController._build(), RareCarBannerController._fit(), RareCarBannerController._present(), RareCarBannerController._show(), RareCarBannerController._showConvoy()

## Knowledge Gaps
- **59 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `widgets.getMouseLocation()` connect `Iris Input & Plot` to `Iris Widget Core`, `Iris Window Layout`?**
  _High betweenness centrality (0.033) - this node is a cross-community bridge._
- **Should `DriveConfig.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.053109713487071976 - nodes in this community are weakly interconnected._
- **Why does `UpdateComboState()` connect `Iris Input & Plot` to `Iris Widget Library`?**
  _High betweenness centrality (0.017) - this node is a cross-community bridge._
- **Should `Car Lights & Claim Badges` be split into smaller, more focused modules?**
  _Cohesion score 0.07073170731707316 - nodes in this community are weakly interconnected._
- **Why does `Feedback.play()` connect `Gameplay Feedback` to `ArcadeKit.luau`?**
  _High betweenness centrality (0.014) - this node is a cross-community bridge._
- **Should `DrivingHudController.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.05858585858585859 - nodes in this community are weakly interconnected._
- **Should `TestEngineController.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.08739495798319327 - nodes in this community are weakly interconnected._