# Graph Report - repo  (2026-11-01)

## Corpus Check
- 406 files · ~1,583,963 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 1 file(s) not represented in the graph (top: (none) 1)

## Summary
- 1156 nodes · 2599 edges · 99 communities (40 shown, 59 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 61 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `85cec23a`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- demoWindow + ShopConfig
- RaceConfig.luau
- FirstPlacementService + FirstPlacementController
- Settings + AudioConfig
- TestEngineController + BuyerOfferSign
- CarLightsController + HudClaimBadges
- widgets
- LivePrice + CollectEffectConfig
- TrafficCollectionCue + RewardConfig
- LobbyDriveController.luau
- collector/harness.luau
- Index + CarAura
- profilestore
- IMPLEMENTATION_PROGRESS
- WeatherConfig.luau
- ProfileStore
- FirstPersonCabin + FirstPersonWheel
- TutorialConfig.luau
- StealNudgeController + StealReminderSchedule
- ReplicaServer
- PerformanceSampler + ShowroomEconomy
- RareCarBannerController + ConvoyConfig
- HopController
- StealTagController + UpgradeCelebrationControlle
- Upgrades + BasicPage
- SellConfig + SellLot
- PlayerProfile
- ObstacleLayout + ObstacleController
- GuideTrailClassic + GuideTrailModern
- ArcadeTrafficImpact
- CarStats + CarConfig
- CollectorHudController.luau
- RoamingCarController.luau
- TutorialControlHighlight + ControlButtonScale
- FirstPersonCockpit
- Combo + Input
- ReplicaClient + Remote
- Window + widgets
- Plot
- LuckProgressController
- widgets (2)
- Signal + ProfileStore
- SaleTagController
- MobileMenuSizing
- AdminService.luau
- CodesService.luau
- RaceService.luau
- StarController
- GiftPicker
- TipsService.luau
- StealController.luau
- ProfileReset
- OfflineLabelController.luau
- run
- run (2)
- StealReminderSchedule.luau
- InventoryLimitController.luau
- CollectorWorld.luau
- collector/run.sh

## God Nodes (most connected - your core abstractions)
1. `Reference Video Analysis` - 11 edges
2. `Service._sync()` - 10 edges
3. `Controller._buildPower()` - 8 edges
4. `Controller._refreshStrip()` - 8 edges
5. `Controller._buildPanel()` - 7 edges
6. `Service._event()` - 7 edges
7. `Service.failed()` - 7 edges
8. `Controller._buildStrip()` - 6 edges
9. `Controller._buildLabel()` - 6 edges
10. `TestEngineController._sync()` - 6 edges

## Surprising Connections (you probably didn't know these)
- `Controller._step()` --calls--> `Feedback.play()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/GameplayFeedbackController.luau → ReplicatedStorage/shared/Modules/GameplayFeedback.luau
- `Highlight.new()` --calls--> `capture()`  [INFERRED]
  ReplicatedStorage/shared/Modules/TutorialControlHighlight.luau → tests/collector/harness.luau
- `UIRoot.wait()` --calls--> `claim()`  [INFERRED]
  ReplicatedStorage/shared/Modules/UIRoot.luau → tests/playtime/harness.luau
- `UIRoot.find()` --calls--> `claim()`  [INFERRED]
  ReplicatedStorage/shared/Modules/UIRoot.luau → tests/playtime/harness.luau
- `Controller.displayName()` --calls--> `CarNameConfig.nameOf()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/RoamingCarController.luau → ReplicatedStorage/shared/Configs/CarNameConfig.luau

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Collectible value descriptors on overhead label** — implementation_progress_overhead_label, implementation_progress_size_tags, implementation_progress_mutation_paint_system [EXTRACTED 1.00]
- **Capture Loop: herd → ⚡ check → capture → toast/tray → hotbar** — implementation_progress_roaming_herds, implementation_progress_power_stat, implementation_progress_capture_mechanic, implementation_progress_capture_toast_secured_tray, implementation_progress_hotbar [INFERRED 0.85]

## Communities (99 total, 59 thin omitted)

### Community 1 - "demoWindow + ShopConfig"
Cohesion: 0.12
Nodes (5): PassConfig.ownedAttribute(), ShopConfig.isSellable(), ShopConfig.visibleBundles(), ShopConfig.visiblePasses(), priceLabel()

### Community 2 - "RaceConfig.luau"
Cohesion: 0.14
Nodes (4): DiscoveryController._build(), DiscoveryController._next(), ShowroomSummaryController._build(), ShowroomSummaryController._onSummary()

### Community 3 - "FirstPlacementService + FirstPlacementController"
Cohesion: 0.09
Nodes (26): Controller._bind(), Controller._build(), Controller._deck(), Controller._input(), Controller._request(), Controller._result(), slotIndex(), Controller._step() (+18 more)

### Community 4 - "Settings + AudioConfig"
Cohesion: 0.06
Nodes (5): AudioConfig.clamp(), AudioConfig.isSet(), InterfaceConfig.isVisibility(), InterfaceConfig.resolve(), InterfaceConfig.statusFor()

### Community 5 - "TestEngineController + BuyerOfferSign"
Cohesion: 0.13
Nodes (11): approach(), TestEngineController._attach(), TestEngineController._bodyOf(), TestEngineController._clearTails(), TestEngineController._detach(), TestEngineController._driveSound(), TestEngineController._mute(), TestEngineController._replaceEngine() (+3 more)

### Community 6 - "CarLightsController + HudClaimBadges"
Cohesion: 0.06
Nodes (22): IndexRewardConfig.bonusFor(), IndexRewardConfig.parseClaimed(), IndexRewardConfig.percentFor(), CarLightsController._bind(), CarLightsController._onRaceEnd(), CarLightsController._onRaceStart(), CarLightsController._step(), CarLightsController._unbind() (+14 more)

### Community 8 - "widgets"
Cohesion: 0.07
Nodes (4): widgets.applyFrameStyle(), widgets.UICorner(), widgets.UIPadding(), widgets.UIStroke()

### Community 9 - "LivePrice + CollectEffectConfig"
Cohesion: 0.13
Nodes (3): keyOf(), LivePrice.fetch(), LivePrice.peek()

### Community 10 - "TrafficCollectionCue + RewardConfig"
Cohesion: 0.18
Nodes (8): CarConfig.maxSpeedOf(), RewardConfig.decodeLevels(), RewardConfig.levelOf(), Cue.describe(), Cue.new(), Cue.step(), label(), oneLine()

### Community 13 - "collector/harness.luau"
Cohesion: 0.09
Nodes (17): BuyerOfferSign.build(), BuyerOfferSign.buildDesign(), corner(), frame(), gradient(), stroke(), text(), UIRoot.find() (+9 more)

### Community 16 - "profilestore"
Cohesion: 0.13
Nodes (7): AcquireRunnerThreadAndCallEventHandler(), Profile:EndSession(), Profile:IsActive(), Profile:MessageHandler(), ProfileStore:VersionQuery(), ProfileVersionQuery.New(), RunEventHandlerInFreeThread()

### Community 17 - "IMPLEMENTATION_PROGRESS"
Cohesion: 0.18
Nodes (16): Open-World Collector Rework — Progress, Base Pen (passive income, pen/machine upgrades), IT'S YOURS Toast + N SECURED Tray, Third-Person Follow Camera, ALL HERDS RESET World Event (Secret spawns, ~5 min), Hotbar (~7 slots, Q key), Linear Corridor with 10 Zones (Plains→Cosmic), Mutation/Paint System (GOLDEN/SILVER) (+8 more)

### Community 20 - "ProfileStore"
Cohesion: 0.14
Nodes (5): Profile:EndSession(), Profile:IsActive(), Profile:MessageHandler(), ProfileStore:VersionQuery(), ProfileVersionQuery.New()

### Community 21 - "FirstPersonCabin + FirstPersonWheel"
Cohesion: 0.21
Nodes (3): FirstPersonCabin.destroy(), FirstPersonCabin._teardown(), FirstPersonCabin.update()

### Community 22 - "TutorialConfig.luau"
Cohesion: 0.12
Nodes (5): DealershipMarkerController._build(), UpgradeNudgeController._build(), UpgradeNudgeController._machine(), tiesToAnotherPart(), step()

### Community 24 - "StealNudgeController + StealReminderSchedule"
Cohesion: 0.36
Nodes (5): hex(), StealNudgeController._niceCarLine(), StealNudgeController._onRaceStart(), StealNudgeController._reset(), StealNudgeController._step()

### Community 26 - "PerformanceSampler + ShowroomEconomy"
Cohesion: 0.23
Nodes (10): laneWarningTemplate(), add(), histogram(), percentile(), Sampler.new(), Sampler.record(), Sampler.snapshot(), floorOf() (+2 more)

### Community 28 - "RareCarBannerController + ConvoyConfig"
Cohesion: 0.39
Nodes (5): RareCarBannerController._build(), RareCarBannerController._fit(), RareCarBannerController._present(), RareCarBannerController._show(), RareCarBannerController._showConvoy()

### Community 29 - "HopController"
Cohesion: 0.21
Nodes (5): HopController._bind(), HopController._fly(), HopController._setRacing(), HopController._step(), HopController._unbind()

### Community 31 - "StealTagController + UpgradeCelebrationControlle"
Cohesion: 0.26
Nodes (9): hitBoxOf(), roofOf(), screenScale(), StealTagController._build(), StealTagController._clear(), StealTagController._show(), banner(), UpgradeCelebrationController._play() (+1 more)

### Community 32 - "Upgrades + BasicPage"
Cohesion: 0.18
Nodes (6): findCloseButton(), Page.new(), KitPage.scaleTextCaps(), Page.initialize(), Page:_repaint(), Page:StartOpenThread()

### Community 34 - "SellConfig + SellLot"
Cohesion: 0.22
Nodes (4): GarageConfig.decodeConditions(), MarketValueConfig.broadcastRecord(), SellConfig.lotPriceForOwner(), SellConfig.lotPriceOf()

### Community 37 - "PlayerProfile"
Cohesion: 0.25
Nodes (5): PlayerProfile:Decrement(), PlayerProfile:Increment(), PlayerProfile:IsActive(), PlayerProfile:Set(), PlayerProfile:_setRecursive()

### Community 42 - "ArcadeTrafficImpact"
Cohesion: 0.27
Nodes (4): ArcadeTrafficImpact.step(), fade(), overlaps(), reach()

### Community 44 - "CarStats + CarConfig"
Cohesion: 0.23
Nodes (8): CarConfig.maxHealthOf(), CarConfig.statsFor(), CarStats.apply(), CarStats.bodyOf(), CarStats.maxHealthOf(), CarStats.reapply(), stamp(), FirstPersonCockpit.setCar()

### Community 45 - "CollectorHudController.luau"
Cohesion: 0.25
Nodes (14): CarNameConfig.nameOf(), button(), Controller._buildPanel(), Controller._buildPower(), Controller._buildStrip(), Controller._level(), Controller._refreshPower(), Controller._refreshStrip() (+6 more)

### Community 48 - "RoamingCarController.luau"
Cohesion: 0.12
Nodes (23): claimed(), GroupRewardController._bind(), GroupRewardController._dance(), GroupRewardController._paint(), GroupRewardController._press(), GroupRewardController._showStatus(), line(), Controller._buildLabel() (+15 more)

### Community 49 - "TutorialControlHighlight + ControlButtonScale"
Cohesion: 0.24
Nodes (5): ButtonScale.ensure(), ButtonScale.set(), Highlight.new(), Highlight.step(), capture()

### Community 50 - "FirstPersonCockpit"
Cohesion: 0.36
Nodes (6): FirstPersonCockpit._health(), FirstPersonCockpit._placeArms(), FirstPersonCockpit._placeWheel(), FirstPersonCockpit._showArms(), FirstPersonCockpit._showDash(), FirstPersonCockpit.update()

### Community 52 - "Combo + Input"
Cohesion: 0.29
Nodes (5): UpdateComboState(), widgets.getMouseLocation(), widgets.isPosInsideRect(), SliderMouseDown(), updateActiveSlider()

### Community 55 - "Window + widgets"
Cohesion: 0.33
Nodes (5): widgets.findBestWindowPosForPopup(), widgets.getScreenSizeForWindow(), fitPositionToWindowBounds(), fitSizeToWindowBounds(), relocateTooltips()

### Community 56 - "Plot"
Cohesion: 0.38
Nodes (4): clearBlock(), clearLine(), updateBlock(), updateLine()

### Community 57 - "LuckProgressController"
Cohesion: 0.47
Nodes (4): LuckProgressController._advance(), LuckProgressController._hide(), LuckProgressController._pause(), LuckProgressController._step()

### Community 58 - "widgets (2)"
Cohesion: 0.53
Nodes (6): widgets.applyInputBegan(), widgets.applyInputEnded(), widgets.applyInteractionHighlights(), widgets.applyInteractionHighlightsWithMultiHighlightee(), widgets.applyMouseEnter(), widgets.applyMouseLeave()

### Community 59 - "Signal + ProfileStore"
Cohesion: 0.33
Nodes (3): AcquireRunnerThreadAndCallEventHandler(), RunEventHandlerInFreeThread(), RunEventHandlerInFreeThread()

### Community 66 - "CodesService.luau"
Cohesion: 0.28
Nodes (3): amountFor(), CodesService._redeem(), CodesService._reply()

### Community 72 - "StealController.luau"
Cohesion: 0.16
Nodes (4): deletedName(), NpcFriends.isUsable(), ShellDoors.pose(), ShellDoors.restore()

### Community 77 - "OfflineLabelController.luau"
Cohesion: 0.53
Nodes (4): inLane(), OfflineLabelController._apply(), OfflineLabelController._watchRival(), OfflineLabelController._yielding()

### Community 92 - "InventoryLimitController.luau"
Cohesion: 0.70
Nodes (4): InventoryLimitController._build(), InventoryLimitController._fit(), InventoryLimitController._refresh(), InventoryLimitController._show()

### Community 96 - "CollectorWorld.luau"
Cohesion: 0.83
Nodes (3): CollectorWorld.build(), part(), sign()

## Knowledge Gaps
- **3 isolated node(s):** `IT'S YOURS Toast + N SECURED Tray`, `Third-Person Follow Camera`, `Zone Strip HUD with Distance Marker`
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 443 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **59 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Feedback.play()` connect `RoamingCarController.luau` to `WeatherConfig.luau`, `FirstPlacementService + FirstPlacementController`, `CollectorHudController.luau`?**
  _High betweenness centrality (0.037) - this node is a cross-community bridge._
- **What connects `IT'S YOURS Toast + N SECURED Tray`, `Third-Person Follow Camera`, `Zone Strip HUD with Distance Marker` to the rest of the system?**
  _3 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `c_users_razvan_documents_robloxprojects_steal_and_drive_v2_repo_replicatedstorage_packages_shard_luau` be split into smaller, more focused modules?**
  _Cohesion score 0.10121457489878542 - nodes in this community are weakly interconnected._
- **Why does `Controller._step()` connect `FirstPlacementService + FirstPlacementController` to `RoamingCarController.luau`?**
  _High betweenness centrality (0.036) - this node is a cross-community bridge._
- **Should `demoWindow + ShopConfig` be split into smaller, more focused modules?**
  _Cohesion score 0.11904761904761904 - nodes in this community are weakly interconnected._
- **Why does `laneWarningTemplate()` connect `PerformanceSampler + ShowroomEconomy` to `Index + CarAura`?**
  _High betweenness centrality (0.027) - this node is a cross-community bridge._
- **Should `RaceConfig.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.1380952380952381 - nodes in this community are weakly interconnected._