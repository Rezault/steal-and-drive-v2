# Graph Report - repo  (2026-11-01)

## Corpus Check
- Large corpus: 399 files · ~1,571,248 words. Semantic extraction will be expensive (many Claude tokens). Consider running on a subfolder.

## Summary
- 1096 nodes · 2459 edges · 91 communities (35 shown, 56 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 51 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- VIPController + MusicConfig
- demoWindow + ShopConfig
- OfflineLabelController + InventoryLimitControlle
- FirstPlacementService + FirstPlacementController
- Settings + AudioConfig
- TestEngineController + BuyerOfferSign
- CarLightsController + HudClaimBadges
- widgets
- LivePrice + CollectEffectConfig
- TrafficCollectionCue + RewardConfig
- LobbyDriveController + RadioConfig
- Index + CarAura
- Index + CarViewportGrid
- profilestore
- IMPLEMENTATION_PROGRESS
- ProfileStore
- FirstPersonCabin + FirstPersonWheel
- StealNudgeController + StealReminderSchedule
- ReplicaServer
- PerformanceSampler + ShowroomEconomy
- NpcFriends + TutorialConfig
- RareCarBannerController + ConvoyConfig
- HopController
- StealTagController + UpgradeCelebrationControlle
- Upgrades + BasicPage
- SellConfig + SellLot
- PlayerProfile
- GuideTrailClassic + GuideTrailModern
- ArcadeTrafficImpact
- CarStats + CarConfig
- PlotConfig + CarryController
- GroupRewardController
- TutorialControlHighlight + ControlButtonScale
- FirstPersonCockpit
- DiscoveryController + CarCatalogue
- Combo + Input
- ReplicaClient + Remote
- Window + widgets
- Plot
- LuckProgressController
- widgets (2)
- Signal + ProfileStore
- PickupController
- SaleTagController
- MobileMenuSizing
- IndexRewardConfig + IndexRewardController
- PlateConfig + CarPlate
- StarController
- GiftPicker
- ShellDoors
- ProfileReset
- HitchProbe
- run
- run (2)

## God Nodes (most connected - your core abstractions)
1. `Reference Video Analysis` - 11 edges
2. `Service._sync()` - 10 edges
3. `Service._event()` - 7 edges
4. `Service.failed()` - 7 edges
5. `TestEngineController._sync()` - 6 edges
6. `paint()` - 6 edges
7. `widgets.getMouseLocation()` - 6 edges
8. `BuyerOfferSign.build()` - 6 edges
9. `CarStats.bodyOf()` - 6 edges
10. `FirstPersonCockpit.update()` - 6 edges

## Surprising Connections (you probably didn't know these)
- `UIRoot.wait()` --calls--> `claim()`  [INFERRED]
  ReplicatedStorage/shared/Modules/UIRoot.luau → tests/playtime/harness.luau
- `UIRoot.find()` --calls--> `claim()`  [INFERRED]
  ReplicatedStorage/shared/Modules/UIRoot.luau → tests/playtime/harness.luau
- `Page:setProgress()` --calls--> `IndexRewardConfig.percentFor()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/UIController/Pages/Index.luau → ReplicatedStorage/shared/Configs/IndexRewardConfig.luau
- `CarLightsController._step()` --calls--> `CarHeadlights.set()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/CarLightsController.luau → ReplicatedStorage/shared/Modules/CarHeadlights.luau
- `HopController._step()` --calls--> `CarStats.bodyOf()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/HopController.luau → ReplicatedStorage/shared/Modules/CarStats.luau

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Capture Loop: herd → ⚡ check → capture → toast/tray → hotbar** — implementation_progress_roaming_herds, implementation_progress_power_stat, implementation_progress_capture_mechanic, implementation_progress_capture_toast_secured_tray, implementation_progress_hotbar [INFERRED 0.85]
- **Collectible value descriptors on overhead label** — implementation_progress_overhead_label, implementation_progress_size_tags, implementation_progress_mutation_paint_system [EXTRACTED 1.00]

## Communities (91 total, 56 thin omitted)

### Community 0 - "VIPController + MusicConfig"
Cohesion: 0.06
Nodes (3): Admins.isAdmin(), hex(), roleOf()

### Community 1 - "demoWindow + ShopConfig"
Cohesion: 0.06
Nodes (10): BalanceConfig.roadValue(), PassConfig.ownedAttribute(), RewardConfig.perStudFor(), ShopConfig.isSellable(), ShopConfig.visibleBundles(), ShopConfig.visiblePasses(), priceLabel(), amountFor() (+2 more)

### Community 2 - "OfflineLabelController + InventoryLimitControlle"
Cohesion: 0.06
Nodes (12): InventoryLimitController._build(), InventoryLimitController._fit(), InventoryLimitController._refresh(), InventoryLimitController._show(), inLane(), OfflineLabelController._apply(), OfflineLabelController._watchRival(), OfflineLabelController._yielding() (+4 more)

### Community 3 - "FirstPlacementService + FirstPlacementController"
Cohesion: 0.08
Nodes (27): Controller._bind(), Controller._build(), Controller._deck(), Controller._input(), Controller._request(), Controller._result(), slotIndex(), Controller._step() (+19 more)

### Community 4 - "Settings + AudioConfig"
Cohesion: 0.08
Nodes (5): AudioConfig.clamp(), AudioConfig.isSet(), InterfaceConfig.isVisibility(), InterfaceConfig.resolve(), InterfaceConfig.statusFor()

### Community 5 - "TestEngineController + BuyerOfferSign"
Cohesion: 0.09
Nodes (21): approach(), TestEngineController._attach(), TestEngineController._bodyOf(), TestEngineController._clearTails(), TestEngineController._detach(), TestEngineController._driveSound(), TestEngineController._mute(), TestEngineController._replaceEngine() (+13 more)

### Community 6 - "CarLightsController + HudClaimBadges"
Cohesion: 0.10
Nodes (15): IndexRewardConfig.parseClaimed(), CarLightsController._bind(), CarLightsController._onRaceEnd(), CarLightsController._onRaceStart(), CarLightsController._step(), CarLightsController._unbind(), indexClaims(), paint() (+7 more)

### Community 8 - "widgets"
Cohesion: 0.07
Nodes (4): widgets.applyFrameStyle(), widgets.UICorner(), widgets.UIPadding(), widgets.UIStroke()

### Community 9 - "LivePrice + CollectEffectConfig"
Cohesion: 0.13
Nodes (3): keyOf(), LivePrice.fetch(), LivePrice.peek()

### Community 10 - "TrafficCollectionCue + RewardConfig"
Cohesion: 0.12
Nodes (8): CarConfig.maxSpeedOf(), RewardConfig.decodeLevels(), RewardConfig.levelOf(), Cue.describe(), Cue.new(), Cue.step(), label(), oneLine()

### Community 15 - "Index + CarViewportGrid"
Cohesion: 0.16
Nodes (6): Page:setProgress(), tiesToAnotherPart(), CarViewportGrid:_drain(), CarViewportGrid:refresh(), CarViewportGrid:_release(), step()

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
Cohesion: 0.17
Nodes (3): FirstPersonCabin.destroy(), FirstPersonCabin._teardown(), FirstPersonCabin.update()

### Community 24 - "StealNudgeController + StealReminderSchedule"
Cohesion: 0.19
Nodes (7): hex(), StealNudgeController._niceCarLine(), StealNudgeController._onRaceStart(), StealNudgeController._reset(), StealNudgeController._step(), Schedule.canShow(), Schedule.claim()

### Community 26 - "PerformanceSampler + ShowroomEconomy"
Cohesion: 0.23
Nodes (10): laneWarningTemplate(), add(), histogram(), percentile(), Sampler.new(), Sampler.record(), Sampler.snapshot(), floorOf() (+2 more)

### Community 28 - "RareCarBannerController + ConvoyConfig"
Cohesion: 0.21
Nodes (5): RareCarBannerController._build(), RareCarBannerController._fit(), RareCarBannerController._present(), RareCarBannerController._show(), RareCarBannerController._showConvoy()

### Community 29 - "HopController"
Cohesion: 0.21
Nodes (5): HopController._bind(), HopController._fly(), HopController._setRacing(), HopController._step(), HopController._unbind()

### Community 31 - "StealTagController + UpgradeCelebrationControlle"
Cohesion: 0.26
Nodes (9): hitBoxOf(), roofOf(), screenScale(), StealTagController._build(), StealTagController._clear(), StealTagController._show(), banner(), UpgradeCelebrationController._play() (+1 more)

### Community 32 - "Upgrades + BasicPage"
Cohesion: 0.21
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
Cohesion: 0.31
Nodes (8): CarConfig.maxHealthOf(), CarConfig.statsFor(), CarStats.apply(), CarStats.bodyOf(), CarStats.maxHealthOf(), CarStats.reapply(), stamp(), FirstPersonCockpit.setCar()

### Community 48 - "GroupRewardController"
Cohesion: 0.39
Nodes (7): claimed(), GroupRewardController._bind(), GroupRewardController._dance(), GroupRewardController._paint(), GroupRewardController._press(), GroupRewardController._showStatus(), line()

### Community 49 - "TutorialControlHighlight + ControlButtonScale"
Cohesion: 0.28
Nodes (4): ButtonScale.ensure(), ButtonScale.set(), Highlight.new(), Highlight.step()

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

### Community 66 - "IndexRewardConfig + IndexRewardController"
Cohesion: 0.67
Nodes (3): IndexRewardConfig.bonusFor(), IndexRewardConfig.percentFor(), IndexRewardController._celebrate()

## Knowledge Gaps
- **3 isolated node(s):** `Third-Person Follow Camera`, `Zone Strip HUD with Distance Marker`, `IT'S YOURS Toast + N SECURED Tray`
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 427 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **56 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Feedback.play()` connect `FirstPlacementService + FirstPlacementController` to `DailyRewardController + PlaytimeRewardController`?**
  _High betweenness centrality (0.083) - this node is a cross-community bridge._
- **What connects `Third-Person Follow Camera`, `Zone Strip HUD with Distance Marker`, `IT'S YOURS Toast + N SECURED Tray` to the rest of the system?**
  _3 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `VIPController + MusicConfig` be split into smaller, more focused modules?**
  _Cohesion score 0.05714285714285714 - nodes in this community are weakly interconnected._
- **Why does `widgets.getMouseLocation()` connect `Combo + Input` to `widgets`, `Plot`, `Window + widgets`?**
  _High betweenness centrality (0.034) - this node is a cross-community bridge._
- **Should `demoWindow + ShopConfig` be split into smaller, more focused modules?**
  _Cohesion score 0.055272108843537414 - nodes in this community are weakly interconnected._
- **Should `OfflineLabelController + InventoryLimitControlle` be split into smaller, more focused modules?**
  _Cohesion score 0.05782312925170068 - nodes in this community are weakly interconnected._
- **Should `FirstPlacementService + FirstPlacementController` be split into smaller, more focused modules?**
  _Cohesion score 0.08233117483811286 - nodes in this community are weakly interconnected._