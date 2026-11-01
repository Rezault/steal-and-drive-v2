# Graph Report - steal and drive TS  (2026-10-23)

## Corpus Check
- 388 files · ~1,555,510 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 1 file(s) not represented in the graph (top: (none) 1)

## Summary
- 1022 nodes · 2313 edges · 102 communities (34 shown, 68 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 45 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `4b2bbf42`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- StealTagController.luau
- RaceCameraController.luau
- Car Lights & Claim Badges
- TestEngineController.luau
- RaceConfig.luau
- StealNudgeController.luau
- Iris Widget Core
- WeatherConfig.luau
- GarageConfig.luau
- ShopConfig.luau
- CustomizeConfig.luau
- ProfileStore (Packages)
- ProfileStore (Libraries)
- TutorialControlHighlight.luau
- DriveConfig.luau
- TutorialConfig.luau
- StealTagController.luau
- Basic Page & Upgrades
- ReplicaServer
- Iris Input & Plot
- CarViewport.luau
- LuckProgressController.luau
- OfflineLabelController.luau
- Player Profile
- Group Rewards
- CarryConfig.luau
- Arcade Traffic Impact
- PickupController.luau
- VIPController.luau
- SellConfig.luau
- ReplicaClient
- c_users_razvan_documents_robloxprojects_steal_and_drive_ts_replicatedstorage_packages_dispatcher_luau
- Tips
- Gameplay Feedback
- Iris Window Layout
- StarController.luau
- Iris Interaction Handlers
- Signal
- HopController.luau
- PagesV2/Dealership.luau
- CarStats.luau
- SaleTagController.luau
- Mobile Menu Sizing
- GuideTrailController.luau
- ReviveController.luau
- Gift Picker
- Showroom Economy
- CodesService.luau
- FirstPersonCockpit.luau
- Profile Reset
- IndexRewardConfig.luau
- CarRarity.luau
- ShowcaseController.luau
- convoy/run.sh
- StealNudgeController.luau
- RareCarBannerController.luau
- StealReminderSchedule.luau
- BalanceConfig.luau
- run.sh
- Upgrades.luau
- ShellDoors.luau

## God Nodes (most connected - your core abstractions)
1. `TestEngineController._sync()` - 6 edges
2. `paint()` - 6 edges
3. `widgets.getMouseLocation()` - 6 edges
4. `BuyerOfferSign.build()` - 6 edges
5. `CarStats.bodyOf()` - 6 edges
6. `FirstPersonCockpit.update()` - 6 edges
7. `CarLightsController._step()` - 5 edges
8. `HopController._step()` - 5 edges
9. `StealTagController._show()` - 5 edges
10. `TestEngineController._attach()` - 5 edges

## Surprising Connections (you probably didn't know these)
- `UIRoot.wait()` --calls--> `claim()`  [INFERRED]
  ReplicatedStorage/shared/Modules/UIRoot.luau → tests/playtime/harness.luau
- `UIRoot.find()` --calls--> `claim()`  [INFERRED]
  ReplicatedStorage/shared/Modules/UIRoot.luau → tests/playtime/harness.luau
- `SellConfig.lotPriceForOwner()` --calls--> `MarketValueConfig.broadcastRecord()`  [INFERRED]
  ReplicatedStorage/shared/Configs/SellConfig.luau → ReplicatedStorage/shared/Configs/MarketValueConfig.luau
- `Cue.describe()` --calls--> `RewardConfig.levelOf()`  [INFERRED]
  ReplicatedStorage/shared/Modules/TrafficCollectionCue.luau → ReplicatedStorage/shared/Configs/RewardConfig.luau
- `CarLightsController._step()` --calls--> `CarHeadlights.set()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/CarLightsController.luau → ReplicatedStorage/shared/Modules/CarHeadlights.luau

## Import Cycles
- None detected.

## Communities (102 total, 68 thin omitted)

### Community 0 - "StealTagController.luau"
Cohesion: 0.06
Nodes (5): AudioConfig.clamp(), AudioConfig.isSet(), InterfaceConfig.isVisibility(), InterfaceConfig.resolve(), InterfaceConfig.statusFor()

### Community 1 - "RaceCameraController.luau"
Cohesion: 0.15
Nodes (3): FirstPersonCabin.destroy(), FirstPersonCabin._teardown(), FirstPersonCabin.update()

### Community 2 - "Car Lights & Claim Badges"
Cohesion: 0.10
Nodes (15): IndexRewardConfig.parseClaimed(), CarLightsController._bind(), CarLightsController._onRaceEnd(), CarLightsController._onRaceStart(), CarLightsController._step(), CarLightsController._unbind(), indexClaims(), paint() (+7 more)

### Community 4 - "TestEngineController.luau"
Cohesion: 0.08
Nodes (21): approach(), TestEngineController._attach(), TestEngineController._bodyOf(), TestEngineController._clearTails(), TestEngineController._detach(), TestEngineController._driveSound(), TestEngineController._mute(), TestEngineController._replaceEngine() (+13 more)

### Community 6 - "RaceConfig.luau"
Cohesion: 0.14
Nodes (4): DiscoveryController._build(), DiscoveryController._next(), UpgradeNudgeController._build(), UpgradeNudgeController._machine()

### Community 7 - "StealNudgeController.luau"
Cohesion: 0.22
Nodes (6): CarConfig.maxSpeedOf(), Cue.describe(), Cue.new(), Cue.step(), label(), oneLine()

### Community 8 - "Iris Widget Core"
Cohesion: 0.07
Nodes (4): widgets.applyFrameStyle(), widgets.UICorner(), widgets.UIPadding(), widgets.UIStroke()

### Community 11 - "ShopConfig.luau"
Cohesion: 0.15
Nodes (5): PassConfig.ownedAttribute(), ShopConfig.isSellable(), ShopConfig.visibleBundles(), ShopConfig.visiblePasses(), priceLabel()

### Community 15 - "ProfileStore (Packages)"
Cohesion: 0.13
Nodes (7): AcquireRunnerThreadAndCallEventHandler(), Profile:EndSession(), Profile:IsActive(), Profile:MessageHandler(), ProfileStore:VersionQuery(), ProfileVersionQuery.New(), RunEventHandlerInFreeThread()

### Community 18 - "ProfileStore (Libraries)"
Cohesion: 0.14
Nodes (5): Profile:EndSession(), Profile:IsActive(), Profile:MessageHandler(), ProfileStore:VersionQuery(), ProfileVersionQuery.New()

### Community 19 - "TutorialControlHighlight.luau"
Cohesion: 0.28
Nodes (4): ButtonScale.ensure(), ButtonScale.set(), Highlight.new(), Highlight.step()

### Community 24 - "StealTagController.luau"
Cohesion: 0.26
Nodes (9): hitBoxOf(), roofOf(), screenScale(), StealTagController._build(), StealTagController._clear(), StealTagController._show(), banner(), UpgradeCelebrationController._play() (+1 more)

### Community 26 - "Basic Page & Upgrades"
Cohesion: 0.25
Nodes (3): findCloseButton(), Page.new(), KitPage.scaleTextCaps()

### Community 28 - "Iris Input & Plot"
Cohesion: 0.21
Nodes (9): UpdateComboState(), widgets.getMouseLocation(), widgets.isPosInsideRect(), SliderMouseDown(), updateActiveSlider(), clearBlock(), clearLine(), updateBlock() (+1 more)

### Community 33 - "LuckProgressController.luau"
Cohesion: 0.47
Nodes (4): LuckProgressController._advance(), LuckProgressController._hide(), LuckProgressController._pause(), LuckProgressController._step()

### Community 34 - "OfflineLabelController.luau"
Cohesion: 0.53
Nodes (4): inLane(), OfflineLabelController._apply(), OfflineLabelController._watchRival(), OfflineLabelController._yielding()

### Community 35 - "Player Profile"
Cohesion: 0.25
Nodes (5): PlayerProfile:Decrement(), PlayerProfile:Increment(), PlayerProfile:IsActive(), PlayerProfile:Set(), PlayerProfile:_setRecursive()

### Community 37 - "Group Rewards"
Cohesion: 0.33
Nodes (7): claimed(), GroupRewardController._bind(), GroupRewardController._dance(), GroupRewardController._paint(), GroupRewardController._press(), GroupRewardController._showStatus(), line()

### Community 38 - "CarryConfig.luau"
Cohesion: 0.27
Nodes (5): DealershipMarkerController._build(), InventoryLimitController._build(), InventoryLimitController._fit(), InventoryLimitController._refresh(), InventoryLimitController._show()

### Community 39 - "Arcade Traffic Impact"
Cohesion: 0.27
Nodes (4): ArcadeTrafficImpact.step(), fade(), overlaps(), reach()

### Community 51 - "Iris Window Layout"
Cohesion: 0.33
Nodes (5): widgets.findBestWindowPosForPopup(), widgets.getScreenSizeForWindow(), fitPositionToWindowBounds(), fitSizeToWindowBounds(), relocateTooltips()

### Community 53 - "Iris Interaction Handlers"
Cohesion: 0.53
Nodes (6): widgets.applyInputBegan(), widgets.applyInputEnded(), widgets.applyInteractionHighlights(), widgets.applyInteractionHighlightsWithMultiHighlightee(), widgets.applyMouseEnter(), widgets.applyMouseLeave()

### Community 54 - "Signal"
Cohesion: 0.33
Nodes (3): AcquireRunnerThreadAndCallEventHandler(), RunEventHandlerInFreeThread(), RunEventHandlerInFreeThread()

### Community 57 - "HopController.luau"
Cohesion: 0.23
Nodes (5): HopController._bind(), HopController._fly(), HopController._setRacing(), HopController._step(), HopController._unbind()

### Community 58 - "PagesV2/Dealership.luau"
Cohesion: 0.16
Nodes (3): CarViewportGrid:_drain(), CarViewportGrid:refresh(), CarViewportGrid:_release()

### Community 59 - "CarStats.luau"
Cohesion: 0.27
Nodes (8): CarConfig.maxHealthOf(), CarConfig.statsFor(), CarStats.apply(), CarStats.bodyOf(), CarStats.maxHealthOf(), CarStats.reapply(), stamp(), FirstPersonCockpit.setCar()

### Community 64 - "ReviveController.luau"
Cohesion: 0.38
Nodes (4): watching(), keyOf(), LivePrice.fetch(), LivePrice.peek()

### Community 67 - "Showroom Economy"
Cohesion: 1.00
Nodes (3): floorOf(), sample(), ShowroomEconomy.estimate()

### Community 69 - "CodesService.luau"
Cohesion: 0.28
Nodes (3): amountFor(), CodesService._redeem(), CodesService._reply()

### Community 72 - "FirstPersonCockpit.luau"
Cohesion: 0.36
Nodes (6): FirstPersonCockpit._health(), FirstPersonCockpit._placeArms(), FirstPersonCockpit._placeWheel(), FirstPersonCockpit._showArms(), FirstPersonCockpit._showDash(), FirstPersonCockpit.update()

### Community 77 - "IndexRewardConfig.luau"
Cohesion: 0.32
Nodes (4): IndexRewardConfig.bonusFor(), IndexRewardConfig.percentFor(), IndexRewardController._celebrate(), Page:setProgress()

### Community 90 - "StealNudgeController.luau"
Cohesion: 0.36
Nodes (5): hex(), StealNudgeController._niceCarLine(), StealNudgeController._onRaceStart(), StealNudgeController._reset(), StealNudgeController._step()

### Community 94 - "RareCarBannerController.luau"
Cohesion: 0.39
Nodes (5): RareCarBannerController._build(), RareCarBannerController._fit(), RareCarBannerController._present(), RareCarBannerController._show(), RareCarBannerController._showConvoy()

### Community 98 - "Upgrades.luau"
Cohesion: 0.60
Nodes (3): Page.initialize(), Page:_repaint(), Page:StartOpenThread()

## Knowledge Gaps
- **68 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `widgets.getMouseLocation()` connect `Iris Input & Plot` to `Iris Widget Core`, `Iris Window Layout`?**
  _High betweenness centrality (0.029) - this node is a cross-community bridge._
- **Should `StealTagController.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.057004830917874394 - nodes in this community are weakly interconnected._
- **Why does `Feedback.play()` connect `Gameplay Feedback` to `TutorialController.luau`?**
  _High betweenness centrality (0.014) - this node is a cross-community bridge._
- **Should `Car Lights & Claim Badges` be split into smaller, more focused modules?**
  _Cohesion score 0.10114942528735632 - nodes in this community are weakly interconnected._
- **Should `TestEngineController.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.07823613086770982 - nodes in this community are weakly interconnected._
- **Should `RaceConfig.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.1368421052631579 - nodes in this community are weakly interconnected._
- **Should `Iris Widget Core` be split into smaller, more focused modules?**
  _Cohesion score 0.0735632183908046 - nodes in this community are weakly interconnected._