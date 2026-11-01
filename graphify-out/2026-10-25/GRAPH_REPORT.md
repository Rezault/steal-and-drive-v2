# Graph Report - steal and drive TS  (2026-10-25)

## Corpus Check
- 389 files · ~1,559,161 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 1 file(s) not represented in the graph (top: (none) 1)

## Summary
- 1029 nodes · 2336 edges · 90 communities (32 shown, 58 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 46 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `4b2bbf42`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- RaceCameraController.luau
- Car Lights & Claim Badges
- TestEngineController.luau
- ArcadeKit.luau
- StealNudgeController.luau
- Iris Widget Core
- RewardConfig.luau
- GarageConfig.luau
- ShopConfig.luau
- GarageService.luau
- ProfileStore (Packages)
- AudioConfig.luau
- ObstacleConfig.luau
- ProfileStore (Libraries)
- TutorialControlHighlight.luau
- LobbyDriveController.luau
- BuyerOfferSign.luau
- StealController.luau
- HudClaimBadges.luau
- Basic Page & Upgrades
- ReplicaServer
- Iris Input & Plot
- InterfaceConfig.luau
- Player Profile
- Group Rewards
- CarViewportGrid.luau
- Arcade Traffic Impact
- SellConfig.luau
- ReplicaClient
- c_users_razvan_documents_robloxprojects_steal_and_drive_ts_replicatedstorage_packages_shard_luau
- Tips
- Gameplay Feedback
- Iris Window Layout
- Iris Interaction Handlers
- Signal
- HopController.luau
- CarRarity.luau
- CarStats.luau
- Mobile Menu Sizing
- GuideTrailController.luau
- ReviveController.luau
- Gift Picker
- Showroom Economy
- Profile Reset
- IndexRewardConfig.luau
- TrafficConfig.luau
- convoy/run.sh
- StealNudgeController.luau
- StealReminderSchedule.luau
- run.sh
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
- `indexClaims()` --calls--> `IndexRewardConfig.parseClaimed()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/UIController/Components/HudClaimBadges.luau → ReplicatedStorage/shared/Configs/IndexRewardConfig.luau
- `SellConfig.lotPriceForOwner()` --calls--> `MarketValueConfig.broadcastRecord()`  [INFERRED]
  ReplicatedStorage/shared/Configs/SellConfig.luau → ReplicatedStorage/shared/Configs/MarketValueConfig.luau
- `CarLightsController._step()` --calls--> `CarBrakeLights.set()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/CarLightsController.luau → ReplicatedStorage/shared/Modules/CarBrakeLights.luau

## Import Cycles
- None detected.

## Communities (90 total, 58 thin omitted)

### Community 1 - "RaceCameraController.luau"
Cohesion: 0.11
Nodes (9): FirstPersonCabin.destroy(), FirstPersonCabin._teardown(), FirstPersonCabin.update(), FirstPersonCockpit._health(), FirstPersonCockpit._placeArms(), FirstPersonCockpit._placeWheel(), FirstPersonCockpit._showArms(), FirstPersonCockpit._showDash() (+1 more)

### Community 2 - "Car Lights & Claim Badges"
Cohesion: 0.16
Nodes (7): CarLightsController._bind(), CarLightsController._onRaceEnd(), CarLightsController._onRaceStart(), CarLightsController._step(), CarLightsController._unbind(), CarBlinkers.signal(), CarHeadlights.set()

### Community 4 - "TestEngineController.luau"
Cohesion: 0.21
Nodes (11): approach(), TestEngineController._attach(), TestEngineController._bodyOf(), TestEngineController._clearTails(), TestEngineController._detach(), TestEngineController._driveSound(), TestEngineController._mute(), TestEngineController._replaceEngine() (+3 more)

### Community 6 - "ArcadeKit.luau"
Cohesion: 0.05
Nodes (34): DiscoveryController._build(), DiscoveryController._next(), InventoryLimitController._build(), InventoryLimitController._fit(), InventoryLimitController._refresh(), InventoryLimitController._show(), LuckProgressController._advance(), LuckProgressController._hide() (+26 more)

### Community 7 - "StealNudgeController.luau"
Cohesion: 0.28
Nodes (4): Cue.new(), Cue.step(), label(), oneLine()

### Community 8 - "Iris Widget Core"
Cohesion: 0.07
Nodes (4): widgets.applyFrameStyle(), widgets.UICorner(), widgets.UIPadding(), widgets.UIStroke()

### Community 9 - "RewardConfig.luau"
Cohesion: 0.22
Nodes (4): CarConfig.maxSpeedOf(), RewardConfig.decodeLevels(), RewardConfig.levelOf(), Cue.describe()

### Community 10 - "GarageConfig.luau"
Cohesion: 0.13
Nodes (4): PlateConfig.roll(), CarPlate.roll(), tiesToAnotherPart(), step()

### Community 11 - "ShopConfig.luau"
Cohesion: 0.06
Nodes (12): Admins.isAdmin(), BalanceConfig.roadValue(), PassConfig.ownedAttribute(), RewardConfig.perStudFor(), ShopConfig.isSellable(), ShopConfig.visibleBundles(), ShopConfig.visiblePasses(), priceLabel() (+4 more)

### Community 15 - "ProfileStore (Packages)"
Cohesion: 0.13
Nodes (7): AcquireRunnerThreadAndCallEventHandler(), Profile:EndSession(), Profile:IsActive(), Profile:MessageHandler(), ProfileStore:VersionQuery(), ProfileVersionQuery.New(), RunEventHandlerInFreeThread()

### Community 17 - "ObstacleConfig.luau"
Cohesion: 0.08
Nodes (4): PickupController._build(), PickupController._tween(), StarController.isActive(), StarController.remaining()

### Community 18 - "ProfileStore (Libraries)"
Cohesion: 0.14
Nodes (5): Profile:EndSession(), Profile:IsActive(), Profile:MessageHandler(), ProfileStore:VersionQuery(), ProfileVersionQuery.New()

### Community 19 - "TutorialControlHighlight.luau"
Cohesion: 0.28
Nodes (4): ButtonScale.ensure(), ButtonScale.set(), Highlight.new(), Highlight.step()

### Community 22 - "BuyerOfferSign.luau"
Cohesion: 0.20
Nodes (10): BuyerOfferSign.build(), BuyerOfferSign.buildDesign(), corner(), frame(), gradient(), stroke(), text(), UIRoot.find() (+2 more)

### Community 24 - "HudClaimBadges.luau"
Cohesion: 0.27
Nodes (7): indexClaims(), paint(), paintIndex(), paintQuests(), questClaims(), CarBrakeLights.off(), CarBrakeLights.set()

### Community 26 - "Basic Page & Upgrades"
Cohesion: 0.18
Nodes (6): findCloseButton(), Page.new(), KitPage.scaleTextCaps(), Page.initialize(), Page:_repaint(), Page:StartOpenThread()

### Community 28 - "Iris Input & Plot"
Cohesion: 0.21
Nodes (9): UpdateComboState(), widgets.getMouseLocation(), widgets.isPosInsideRect(), SliderMouseDown(), updateActiveSlider(), clearBlock(), clearLine(), updateBlock() (+1 more)

### Community 33 - "InterfaceConfig.luau"
Cohesion: 0.38
Nodes (3): InterfaceConfig.isVisibility(), InterfaceConfig.resolve(), InterfaceConfig.statusFor()

### Community 35 - "Player Profile"
Cohesion: 0.25
Nodes (5): PlayerProfile:Decrement(), PlayerProfile:Increment(), PlayerProfile:IsActive(), PlayerProfile:Set(), PlayerProfile:_setRecursive()

### Community 37 - "Group Rewards"
Cohesion: 0.33
Nodes (7): claimed(), GroupRewardController._bind(), GroupRewardController._dance(), GroupRewardController._paint(), GroupRewardController._press(), GroupRewardController._showStatus(), line()

### Community 38 - "CarViewportGrid.luau"
Cohesion: 0.83
Nodes (3): CarViewportGrid:_drain(), CarViewportGrid:refresh(), CarViewportGrid:_release()

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

### Community 58 - "CarRarity.luau"
Cohesion: 0.12
Nodes (8): StartCarConfig.isDefault(), Page:_drive(), Page:_paint(), Page:_selectedCar(), Page:_showHeroCar(), Page:StartOpenThread(), line(), CarRarity.labelOf()

### Community 59 - "CarStats.luau"
Cohesion: 0.27
Nodes (8): CarConfig.maxHealthOf(), CarConfig.statsFor(), CarStats.apply(), CarStats.bodyOf(), CarStats.maxHealthOf(), CarStats.reapply(), stamp(), FirstPersonCockpit.setCar()

### Community 64 - "ReviveController.luau"
Cohesion: 0.83
Nodes (3): keyOf(), LivePrice.fetch(), LivePrice.peek()

### Community 67 - "Showroom Economy"
Cohesion: 1.00
Nodes (3): floorOf(), sample(), ShowroomEconomy.estimate()

### Community 77 - "IndexRewardConfig.luau"
Cohesion: 0.21
Nodes (5): IndexRewardConfig.bonusFor(), IndexRewardConfig.parseClaimed(), IndexRewardConfig.percentFor(), IndexRewardController._celebrate(), Page:setProgress()

### Community 90 - "StealNudgeController.luau"
Cohesion: 0.36
Nodes (5): hex(), StealNudgeController._niceCarLine(), StealNudgeController._onRaceStart(), StealNudgeController._reset(), StealNudgeController._step()

## Knowledge Gaps
- **58 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `widgets.getMouseLocation()` connect `Iris Input & Plot` to `Iris Widget Core`, `Iris Window Layout`?**
  _High betweenness centrality (0.039) - this node is a cross-community bridge._
- **Should `RaceCameraController.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.10826210826210826 - nodes in this community are weakly interconnected._
- **Why does `widgets.getScreenSizeForWindow()` connect `Iris Window Layout` to `Iris Widget Core`?**
  _High betweenness centrality (0.014) - this node is a cross-community bridge._
- **Should `ArcadeKit.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.05310734463276836 - nodes in this community are weakly interconnected._
- **Why does `relocateTooltips()` connect `Iris Window Layout` to `Iris Input & Plot`?**
  _High betweenness centrality (0.012) - this node is a cross-community bridge._
- **Should `Iris Widget Core` be split into smaller, more focused modules?**
  _Cohesion score 0.0735632183908046 - nodes in this community are weakly interconnected._
- **Should `GarageConfig.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.12554112554112554 - nodes in this community are weakly interconnected._