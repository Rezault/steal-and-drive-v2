# Graph Report - repo  (2026-11-02)

## Corpus Check
- 408 files · ~1,593,830 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 1 file(s) not represented in the graph (top: (none) 1)

## Summary
- 1169 nodes · 2616 edges · 98 communities (38 shown, 60 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 58 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `fb44e8ec`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PlotConfig.luau
- CashConfig.luau
- CarryController.luau
- FirstPlacementService + FirstPlacementController
- TestEngineController.luau
- TrafficCollectionCue.luau
- CarLightsController + HudClaimBadges
- widgets
- TutorialConfig.luau
- collector/harness.luau
- Index + CarAura
- BuyerController.luau
- profilestore
- IMPLEMENTATION_PROGRESS
- ProfileStore
- ShopConfig.luau
- GroupRewardController.luau
- TestEngineController.luau
- ReplicaServer
- PerformanceSampler + ShowroomEconomy
- CodesService.luau
- CarStats.luau
- StealController.luau
- Upgrades + BasicPage
- SellConfig.luau
- PlayerProfile
- AdminPanelController.luau
- GuideTrailClassic + GuideTrailModern
- ArcadeTrafficImpact
- CarryConfig.luau
- CollectorHudController.luau
- ArcadeKit.luau
- LuckProgressController.luau
- Combo + Input
- ReplicaClient + Remote
- WorldConfig.luau
- Window + widgets
- Plot
- OfflineLabelController.luau
- widgets (2)
- Signal + ProfileStore
- SaleTagController.luau
- RareCarBannerController.luau
- MobileMenuSizing
- InventoryConfig.luau
- PowerTrainerService.luau
- CarViewport.luau
- CarViewportGrid.luau
- GiftPicker
- TipsService.luau
- UIRoot.find
- ProfileReset
- run
- run (2)
- InventoryLimitController.luau
- LivePrice.luau
- DiscoveryController.luau
- collector/run.sh
- HitchProbe.luau

## God Nodes (most connected - your core abstractions)
1. `Reference Video Analysis` - 11 edges
2. `Service._sync()` - 10 edges
3. `Controller._buildPower()` - 7 edges
4. `Service._event()` - 7 edges
5. `Service.failed()` - 7 edges
6. `Controller._buildPanel()` - 6 edges
7. `TestEngineController._sync()` - 6 edges
8. `paint()` - 6 edges
9. `widgets.getMouseLocation()` - 6 edges
10. `BuyerOfferSign.build()` - 6 edges

## Surprising Connections (you probably didn't know these)
- `Highlight.new()` --calls--> `capture()`  [INFERRED]
  ReplicatedStorage/shared/Modules/TutorialControlHighlight.luau → tests/collector/harness.luau
- `UIRoot.wait()` --calls--> `claim()`  [INFERRED]
  ReplicatedStorage/shared/Modules/UIRoot.luau → tests/playtime/harness.luau
- `UIRoot.find()` --calls--> `claim()`  [INFERRED]
  ReplicatedStorage/shared/Modules/UIRoot.luau → tests/playtime/harness.luau
- `CarLightsController._step()` --calls--> `CarHeadlights.set()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/CarLightsController.luau → ReplicatedStorage/shared/Modules/CarHeadlights.luau
- `StealTagController._show()` --calls--> `ArcadeKit.fade()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/StealTagController.luau → ReplicatedStorage/shared/Modules/ArcadeKit.luau

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Collectible value descriptors on overhead label** — implementation_progress_overhead_label, implementation_progress_size_tags, implementation_progress_mutation_paint_system [EXTRACTED 1.00]
- **Capture Loop: herd → ⚡ check → capture → toast/tray → hotbar** — implementation_progress_roaming_herds, implementation_progress_power_stat, implementation_progress_capture_mechanic, implementation_progress_capture_toast_secured_tray, implementation_progress_hotbar [INFERRED 0.85]

## Communities (98 total, 60 thin omitted)

### Community 3 - "FirstPlacementService + FirstPlacementController"
Cohesion: 0.10
Nodes (25): Controller._bind(), Controller._build(), Controller._deck(), Controller._input(), Controller._request(), Controller._result(), slotIndex(), Service._away() (+17 more)

### Community 4 - "TestEngineController.luau"
Cohesion: 0.06
Nodes (11): AudioConfig.clamp(), AudioConfig.isSet(), InterfaceConfig.isVisibility(), InterfaceConfig.resolve(), InterfaceConfig.statusFor(), hitBoxOf(), roofOf(), screenScale() (+3 more)

### Community 5 - "TrafficCollectionCue.luau"
Cohesion: 0.12
Nodes (10): CarConfig.maxSpeedOf(), RewardConfig.decodeLevels(), RewardConfig.levelOf(), Schedule.canShow(), Schedule.claim(), Cue.describe(), Cue.new(), Cue.step() (+2 more)

### Community 6 - "CarLightsController + HudClaimBadges"
Cohesion: 0.10
Nodes (15): IndexRewardConfig.parseClaimed(), CarLightsController._bind(), CarLightsController._onRaceEnd(), CarLightsController._onRaceStart(), CarLightsController._step(), CarLightsController._unbind(), indexClaims(), paint() (+7 more)

### Community 8 - "widgets"
Cohesion: 0.07
Nodes (4): widgets.applyFrameStyle(), widgets.UICorner(), widgets.UIPadding(), widgets.UIStroke()

### Community 13 - "collector/harness.luau"
Cohesion: 0.09
Nodes (12): ButtonScale.ensure(), ButtonScale.set(), Highlight.new(), Highlight.step(), capture(), env(), player(), proxy() (+4 more)

### Community 15 - "BuyerController.luau"
Cohesion: 0.23
Nodes (6): BuyerOfferSign.build(), corner(), frame(), gradient(), stroke(), text()

### Community 16 - "profilestore"
Cohesion: 0.13
Nodes (7): AcquireRunnerThreadAndCallEventHandler(), Profile:EndSession(), Profile:IsActive(), Profile:MessageHandler(), ProfileStore:VersionQuery(), ProfileVersionQuery.New(), RunEventHandlerInFreeThread()

### Community 17 - "IMPLEMENTATION_PROGRESS"
Cohesion: 0.18
Nodes (16): Open-World Collector Rework — Progress, Base Pen (passive income, pen/machine upgrades), IT'S YOURS Toast + N SECURED Tray, Third-Person Follow Camera, ALL HERDS RESET World Event (Secret spawns, ~5 min), Hotbar (~7 slots, Q key), Linear Corridor with 10 Zones (Plains→Cosmic), Mutation/Paint System (GOLDEN/SILVER) (+8 more)

### Community 20 - "ProfileStore"
Cohesion: 0.14
Nodes (5): Profile:EndSession(), Profile:IsActive(), Profile:MessageHandler(), ProfileStore:VersionQuery(), ProfileVersionQuery.New()

### Community 21 - "ShopConfig.luau"
Cohesion: 0.24
Nodes (5): PassConfig.ownedAttribute(), ShopConfig.isSellable(), ShopConfig.visibleBundles(), ShopConfig.visiblePasses(), priceLabel()

### Community 22 - "GroupRewardController.luau"
Cohesion: 0.33
Nodes (7): claimed(), GroupRewardController._bind(), GroupRewardController._dance(), GroupRewardController._paint(), GroupRewardController._press(), GroupRewardController._showStatus(), line()

### Community 24 - "TestEngineController.luau"
Cohesion: 0.08
Nodes (14): LobbyDriveController._leaveHighway(), LobbyDriveController._teardown(), LobbyDriveController._watch(), approach(), TestEngineController._attach(), TestEngineController._bodyOf(), TestEngineController._clearTails(), TestEngineController._detach() (+6 more)

### Community 26 - "PerformanceSampler + ShowroomEconomy"
Cohesion: 0.23
Nodes (10): laneWarningTemplate(), add(), histogram(), percentile(), Sampler.new(), Sampler.record(), Sampler.snapshot(), floorOf() (+2 more)

### Community 27 - "CodesService.luau"
Cohesion: 0.28
Nodes (3): amountFor(), CodesService._redeem(), CodesService._reply()

### Community 29 - "CarStats.luau"
Cohesion: 0.06
Nodes (27): CarConfig.maxHealthOf(), CarConfig.statsFor(), HopController._bind(), HopController._fly(), HopController._setRacing(), HopController._step(), HopController._unbind(), hex() (+19 more)

### Community 32 - "Upgrades + BasicPage"
Cohesion: 0.18
Nodes (6): findCloseButton(), Page.new(), KitPage.scaleTextCaps(), Page.initialize(), Page:_repaint(), Page:StartOpenThread()

### Community 34 - "SellConfig.luau"
Cohesion: 0.22
Nodes (4): GarageConfig.decodeConditions(), MarketValueConfig.broadcastRecord(), SellConfig.lotPriceForOwner(), SellConfig.lotPriceOf()

### Community 37 - "PlayerProfile"
Cohesion: 0.25
Nodes (5): PlayerProfile:Decrement(), PlayerProfile:Increment(), PlayerProfile:IsActive(), PlayerProfile:Set(), PlayerProfile:_setRecursive()

### Community 38 - "AdminPanelController.luau"
Cohesion: 0.05
Nodes (4): PickupController._build(), PickupController._tween(), StarController.isActive(), StarController.remaining()

### Community 42 - "ArcadeTrafficImpact"
Cohesion: 0.27
Nodes (4): ArcadeTrafficImpact.step(), fade(), overlaps(), reach()

### Community 45 - "CollectorHudController.luau"
Cohesion: 0.09
Nodes (25): CarNameConfig.nameOf(), button(), clock(), coloured(), Controller._buildPanel(), Controller._buildPower(), Controller._onAnnounce(), Controller._refreshPower() (+17 more)

### Community 48 - "ArcadeKit.luau"
Cohesion: 0.60
Nodes (3): banner(), UpgradeCelebrationController._play(), ArcadeKit.fade()

### Community 50 - "LuckProgressController.luau"
Cohesion: 0.47
Nodes (4): LuckProgressController._advance(), LuckProgressController._hide(), LuckProgressController._pause(), LuckProgressController._step()

### Community 52 - "Combo + Input"
Cohesion: 0.29
Nodes (5): UpdateComboState(), widgets.getMouseLocation(), widgets.isPosInsideRect(), SliderMouseDown(), updateActiveSlider()

### Community 54 - "WorldConfig.luau"
Cohesion: 0.18
Nodes (4): IndexRewardConfig.bonusFor(), IndexRewardConfig.percentFor(), IndexRewardController._celebrate(), Page:setProgress()

### Community 55 - "Window + widgets"
Cohesion: 0.33
Nodes (5): widgets.findBestWindowPosForPopup(), widgets.getScreenSizeForWindow(), fitPositionToWindowBounds(), fitSizeToWindowBounds(), relocateTooltips()

### Community 56 - "Plot"
Cohesion: 0.38
Nodes (4): clearBlock(), clearLine(), updateBlock(), updateLine()

### Community 57 - "OfflineLabelController.luau"
Cohesion: 0.53
Nodes (4): inLane(), OfflineLabelController._apply(), OfflineLabelController._watchRival(), OfflineLabelController._yielding()

### Community 58 - "widgets (2)"
Cohesion: 0.53
Nodes (6): widgets.applyInputBegan(), widgets.applyInputEnded(), widgets.applyInteractionHighlights(), widgets.applyInteractionHighlightsWithMultiHighlightee(), widgets.applyMouseEnter(), widgets.applyMouseLeave()

### Community 59 - "Signal + ProfileStore"
Cohesion: 0.33
Nodes (3): AcquireRunnerThreadAndCallEventHandler(), RunEventHandlerInFreeThread(), RunEventHandlerInFreeThread()

### Community 63 - "RareCarBannerController.luau"
Cohesion: 0.60
Nodes (5): RareCarBannerController._build(), RareCarBannerController._fit(), RareCarBannerController._present(), RareCarBannerController._show(), RareCarBannerController._showConvoy()

### Community 66 - "PowerTrainerService.luau"
Cohesion: 0.26
Nodes (9): part(), riderOf(), Service.addPower(), Service._load(), Service._profile(), Service._tick(), clearRoad(), CollectorWorld.build() (+1 more)

### Community 67 - "CarViewport.luau"
Cohesion: 0.15
Nodes (4): PlateConfig.roll(), CarPlate.roll(), tiesToAnotherPart(), step()

### Community 68 - "CarViewportGrid.luau"
Cohesion: 0.47
Nodes (3): CarViewportGrid:_drain(), CarViewportGrid:refresh(), CarViewportGrid:_release()

### Community 72 - "UIRoot.find"
Cohesion: 0.33
Nodes (4): BuyerOfferSign.buildDesign(), UIRoot.find(), UIRoot.wait(), claim()

### Community 91 - "InventoryLimitController.luau"
Cohesion: 0.70
Nodes (4): InventoryLimitController._build(), InventoryLimitController._fit(), InventoryLimitController._refresh(), InventoryLimitController._show()

### Community 93 - "LivePrice.luau"
Cohesion: 0.83
Nodes (3): keyOf(), LivePrice.fetch(), LivePrice.peek()

## Knowledge Gaps
- **3 isolated node(s):** `IT'S YOURS Toast + N SECURED Tray`, `Third-Person Follow Camera`, `Zone Strip HUD with Distance Marker`
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 451 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **60 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Feedback.play()` connect `CollectorHudController.luau` to `UIAssets.luau`?**
  _High betweenness centrality (0.034) - this node is a cross-community bridge._
- **What connects `IT'S YOURS Toast + N SECURED Tray`, `Third-Person Follow Camera`, `Zone Strip HUD with Distance Marker` to the rest of the system?**
  _3 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `CarryController.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.13725490196078433 - nodes in this community are weakly interconnected._
- **Why does `widgets.getMouseLocation()` connect `Combo + Input` to `widgets`, `Plot`, `Window + widgets`?**
  _High betweenness centrality (0.029) - this node is a cross-community bridge._
- **Should `FirstPlacementService + FirstPlacementController` be split into smaller, more focused modules?**
  _Cohesion score 0.0975609756097561 - nodes in this community are weakly interconnected._
- **Should `TestEngineController.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.05893719806763285 - nodes in this community are weakly interconnected._
- **Should `TrafficCollectionCue.luau` be split into smaller, more focused modules?**
  _Cohesion score 0.12280701754385964 - nodes in this community are weakly interconnected._