# Graph Report - steal and drive TS  (2026-10-22)

## Corpus Check
- Large corpus: 379 files · ~1,537,345 words. Semantic extraction will be expensive (many Claude tokens). Consider running on a subfolder.

## Summary
- 992 nodes · 2255 edges · 88 communities (27 shown, 61 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 42 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Audio & Settings Config
- First-Person Cockpit Camera
- Car Lights & Claim Badges
- Engine Audio & Seller
- Paint, Start Car & Dealership UI
- Notice Lane Controllers
- Iris Widget Core
- Shop, Codes & Passes
- Race Config & Interface
- Sell Lot & Market Value
- ProfileStore (Packages)
- ProfileStore (Libraries)
- Plot & Dealership Markers
- Basic Page & Upgrades
- ReplicaServer
- Iris Input & Plot
- Car Stats Config
- Plates & Showcase
- Player Profile
- Carry & Upgrade Nudge
- Group Rewards
- Guide Trail
- Arcade Traffic Impact
- Traffic Collection Cue
- Live Price & Rename
- Tutorial Control Highlight
- Reward Levels
- Steal Nudge
- ReplicaClient
- Tips
- Gameplay Feedback
- Iris Window Layout
- VIP Tags
- Iris Interaction Handlers
- Signal
- Steal Reminder Schedule
- Pickup Controller
- Sale Tag
- Mobile Menu Sizing
- Star Controller
- Gift Picker
- Showroom Economy
- NPC Friends
- Shell Doors
- Profile Reset
- Car Rarity Label
- Hitch Probe

## God Nodes (most connected - your core abstractions)
1. `TestEngineController._sync()` - 6 edges
2. `paint()` - 6 edges
3. `widgets.getMouseLocation()` - 6 edges
4. `BuyerOfferSign.build()` - 6 edges
5. `FirstPersonCockpit.update()` - 6 edges
6. `CarLightsController._step()` - 5 edges
7. `StealTagController._show()` - 5 edges
8. `TestEngineController._attach()` - 5 edges
9. `widgets.applyInteractionHighlights()` - 5 edges
10. `widgets.applyInteractionHighlightsWithMultiHighlightee()` - 5 edges

## Surprising Connections (you probably didn't know these)
- `CarLightsController._step()` --calls--> `CarHeadlights.set()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/CarLightsController.luau → ReplicatedStorage/shared/Modules/CarHeadlights.luau
- `hex()` --calls--> `CarStats.bodyOf()`  [INFERRED]
  ReplicatedStorage/shared/Controllers/StealNudgeController.luau → ReplicatedStorage/shared/Modules/CarStats.luau
- `CarBrakeLights.off()` --calls--> `paint()`  [INFERRED]
  ReplicatedStorage/shared/Modules/CarBrakeLights.luau → ReplicatedStorage/shared/Controllers/UIController/Components/HudClaimBadges.luau
- `relocateTooltips()` --calls--> `widgets.getMouseLocation()`  [INFERRED]
  ReplicatedStorage/shared/Libraries/iris/widgets/Window.luau → ReplicatedStorage/shared/Libraries/iris/widgets/init.luau
- `FirstPersonCabin.update()` --calls--> `CarStats.bodyOf()`  [INFERRED]
  ReplicatedStorage/shared/Modules/FirstPersonCabin.luau → ReplicatedStorage/shared/Modules/CarStats.luau

## Import Cycles
- None detected.

## Communities (88 total, 61 thin omitted)

### Community 0 - "Audio & Settings Config"
Cohesion: 0.05
Nodes (14): AudioConfig.clamp(), AudioConfig.isSet(), InterfaceConfig.isVisibility(), InterfaceConfig.resolve(), InterfaceConfig.statusFor(), hitBoxOf(), roofOf(), screenScale() (+6 more)

### Community 1 - "First-Person Cockpit Camera"
Cohesion: 0.07
Nodes (11): LobbyDriveController._teardown(), LobbyDriveController._watch(), FirstPersonCabin.destroy(), FirstPersonCabin._teardown(), FirstPersonCabin.update(), FirstPersonCockpit._health(), FirstPersonCockpit._placeArms(), FirstPersonCockpit._placeWheel() (+3 more)

### Community 2 - "Car Lights & Claim Badges"
Cohesion: 0.07
Nodes (19): IndexRewardConfig.bonusFor(), IndexRewardConfig.parseClaimed(), IndexRewardConfig.percentFor(), CarLightsController._bind(), CarLightsController._onRaceEnd(), CarLightsController._onRaceStart(), CarLightsController._step(), CarLightsController._unbind() (+11 more)

### Community 4 - "Engine Audio & Seller"
Cohesion: 0.09
Nodes (19): approach(), TestEngineController._attach(), TestEngineController._bodyOf(), TestEngineController._clearTails(), TestEngineController._detach(), TestEngineController._driveSound(), TestEngineController._mute(), TestEngineController._replaceEngine() (+11 more)

### Community 5 - "Paint, Start Car & Dealership UI"
Cohesion: 0.12
Nodes (3): CarViewportGrid:_drain(), CarViewportGrid:refresh(), CarViewportGrid:_release()

### Community 6 - "Notice Lane Controllers"
Cohesion: 0.09
Nodes (17): DiscoveryController._build(), DiscoveryController._next(), InventoryLimitController._build(), InventoryLimitController._fit(), InventoryLimitController._refresh(), InventoryLimitController._show(), LuckProgressController._advance(), LuckProgressController._hide() (+9 more)

### Community 8 - "Iris Widget Core"
Cohesion: 0.07
Nodes (4): widgets.applyFrameStyle(), widgets.UICorner(), widgets.UIPadding(), widgets.UIStroke()

### Community 11 - "Shop, Codes & Passes"
Cohesion: 0.12
Nodes (8): PassConfig.ownedAttribute(), ShopConfig.isSellable(), ShopConfig.visibleBundles(), ShopConfig.visiblePasses(), priceLabel(), amountFor(), CodesService._redeem(), CodesService._reply()

### Community 13 - "Sell Lot & Market Value"
Cohesion: 0.13
Nodes (4): GarageConfig.decodeConditions(), MarketValueConfig.broadcastRecord(), SellConfig.lotPriceForOwner(), SellConfig.lotPriceOf()

### Community 15 - "ProfileStore (Packages)"
Cohesion: 0.13
Nodes (7): AcquireRunnerThreadAndCallEventHandler(), Profile:EndSession(), Profile:IsActive(), Profile:MessageHandler(), ProfileStore:VersionQuery(), ProfileVersionQuery.New(), RunEventHandlerInFreeThread()

### Community 18 - "ProfileStore (Libraries)"
Cohesion: 0.14
Nodes (5): Profile:EndSession(), Profile:IsActive(), Profile:MessageHandler(), ProfileStore:VersionQuery(), ProfileVersionQuery.New()

### Community 26 - "Basic Page & Upgrades"
Cohesion: 0.18
Nodes (6): findCloseButton(), Page.new(), KitPage.scaleTextCaps(), Page.initialize(), Page:_repaint(), Page:StartOpenThread()

### Community 28 - "Iris Input & Plot"
Cohesion: 0.21
Nodes (9): UpdateComboState(), widgets.getMouseLocation(), widgets.isPosInsideRect(), SliderMouseDown(), updateActiveSlider(), clearBlock(), clearLine(), updateBlock() (+1 more)

### Community 30 - "Car Stats Config"
Cohesion: 0.27
Nodes (8): CarConfig.maxHealthOf(), CarConfig.statsFor(), CarStats.apply(), CarStats.bodyOf(), CarStats.maxHealthOf(), CarStats.reapply(), stamp(), FirstPersonCockpit.setCar()

### Community 33 - "Plates & Showcase"
Cohesion: 0.22
Nodes (4): PlateConfig.roll(), CarPlate.roll(), tiesToAnotherPart(), step()

### Community 35 - "Player Profile"
Cohesion: 0.25
Nodes (5): PlayerProfile:Decrement(), PlayerProfile:Increment(), PlayerProfile:IsActive(), PlayerProfile:Set(), PlayerProfile:_setRecursive()

### Community 37 - "Group Rewards"
Cohesion: 0.33
Nodes (7): claimed(), GroupRewardController._bind(), GroupRewardController._dance(), GroupRewardController._paint(), GroupRewardController._press(), GroupRewardController._showStatus(), line()

### Community 39 - "Arcade Traffic Impact"
Cohesion: 0.27
Nodes (4): ArcadeTrafficImpact.step(), fade(), overlaps(), reach()

### Community 41 - "Traffic Collection Cue"
Cohesion: 0.28
Nodes (4): Cue.new(), Cue.step(), label(), oneLine()

### Community 42 - "Live Price & Rename"
Cohesion: 0.28
Nodes (3): keyOf(), LivePrice.fetch(), LivePrice.peek()

### Community 43 - "Tutorial Control Highlight"
Cohesion: 0.28
Nodes (4): ButtonScale.ensure(), ButtonScale.set(), Highlight.new(), Highlight.step()

### Community 44 - "Reward Levels"
Cohesion: 0.29
Nodes (6): BalanceConfig.roadValue(), CarConfig.maxSpeedOf(), RewardConfig.decodeLevels(), RewardConfig.levelOf(), RewardConfig.perStudFor(), Cue.describe()

### Community 45 - "Steal Nudge"
Cohesion: 0.36
Nodes (5): hex(), StealNudgeController._niceCarLine(), StealNudgeController._onRaceStart(), StealNudgeController._reset(), StealNudgeController._step()

### Community 51 - "Iris Window Layout"
Cohesion: 0.33
Nodes (5): widgets.findBestWindowPosForPopup(), widgets.getScreenSizeForWindow(), fitPositionToWindowBounds(), fitSizeToWindowBounds(), relocateTooltips()

### Community 53 - "Iris Interaction Handlers"
Cohesion: 0.53
Nodes (6): widgets.applyInputBegan(), widgets.applyInputEnded(), widgets.applyInteractionHighlights(), widgets.applyInteractionHighlightsWithMultiHighlightee(), widgets.applyMouseEnter(), widgets.applyMouseLeave()

### Community 54 - "Signal"
Cohesion: 0.33
Nodes (3): AcquireRunnerThreadAndCallEventHandler(), RunEventHandlerInFreeThread(), RunEventHandlerInFreeThread()

### Community 67 - "Showroom Economy"
Cohesion: 1.00
Nodes (3): floorOf(), sample(), ShowroomEconomy.estimate()

## Knowledge Gaps
- **61 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `widgets.getMouseLocation()` connect `Iris Input & Plot` to `Iris Widget Core`, `Iris Window Layout`?**
  _High betweenness centrality (0.037) - this node is a cross-community bridge._
- **Should `Audio & Settings Config` be split into smaller, more focused modules?**
  _Cohesion score 0.054693877551020405 - nodes in this community are weakly interconnected._
- **Why does `widgets.getScreenSizeForWindow()` connect `Iris Window Layout` to `Iris Widget Core`?**
  _High betweenness centrality (0.012) - this node is a cross-community bridge._
- **Should `First-Person Cockpit Camera` be split into smaller, more focused modules?**
  _Cohesion score 0.06755260243632337 - nodes in this community are weakly interconnected._
- **Why does `Feedback.play()` connect `Gameplay Feedback` to `Daily Rewards`?**
  _High betweenness centrality (0.011) - this node is a cross-community bridge._
- **Should `Car Lights & Claim Badges` be split into smaller, more focused modules?**
  _Cohesion score 0.06852497096399536 - nodes in this community are weakly interconnected._
- **Should `Passes, Obstacles & Teleport` be split into smaller, more focused modules?**
  _Cohesion score 0.10084033613445378 - nodes in this community are weakly interconnected._