# Open-World Collector Rework — Progress

Branch: `feature/open-world-collector-rework` · remote `v2` = https://github.com/Rezault/steal-and-drive-v2
Studio place used for build/test: "steal car v2" (placeId 103274860383115) — owner confirmed safe to edit.
Studio playtests use the ProfileStore mock (`Data/Components/Settings.luau` `DEBUG_MOCK = true`), so no production saves are touched.

## Reference video analysis (Screen Recording 2026-11-01 113528.mp4, 26 s, 1 fps frames)

Confirmed from footage:
- Third-person follow camera, slightly high, ~15–20 studs back; bright saturated greens, blocky low-poly terrain, canyon walls bounding a long corridor.
- Base: fenced pen next to spawn; creatures stand on it with floating `$N/s` labels (passive income). "Upgrade Pen Level 2→3 $75M" and "Upgrade Machine" signs at the base.
- Leaving the base you cross a painted "START ZONE" line into a single linear corridor. Top-centre HUD: strip of 10 zone tiles (Plains, Forest, Desert, Jungle, Snow, …, Volcano, …, Cosmic) with a player marker and distance in metres (189 m → 1,079 m over ~15 s).
- Collectibles roam in small herds kicking up dust clouds, running across the corridor.
- Overhead label (scales with distance, visible ~150 studs): size tag (TINY / BIG / HUGE / GIANT) + mutation tag (GOLDEN / SILVER) + red "new!" when not yet in the Index; rarity line in rarity colour (Common grey-white, Uncommon green, Epic magenta); name; "Required: ⚡N" (green when you meet it).
- Player stat ⚡ (15.1K) bottom-left above cash ($3.1M), each with a green "+" (shop shortcut).
- Capture: the player runs into / alongside the creature; a green ring reticle sits ahead of the player; on success heart particles burst, a toast slides in top-left "IT'S YOURS! — GIANT Dilophosaurus — Keep going!", and a "N SECURED" tray under it lists this trip's captures with icons. The captured unit appears in the next free hotbar slot immediately.
- Hotbar: bottom-centre, ~7 square slots with portrait + short name; "Q" key slot on the left.
- World event: "ALL HERDS RESET!" banner + 3 lines "A Secret <name> spawned in <Zone>!" with zone names in zone colours; bottom-right moon icon countdown "in 4m 57s".
- Left rail: Shop, Index buttons with red "!" badges.

Assumptions (not determinable from 26 s of footage):
- Capture is effectively instant on contact when ⚡ ≥ Required (no visible progress bar). We use a short (0.45 s) stay-in-range capture with a fill bar, so it reads as an action on mobile but keeps the pace. No button: walking into the car is the input on every device.
- "SECURED" = captures made since leaving the base this trip; we use it purely as session feedback (cars are owned immediately, never lost).
- Herd reset cadence ≈ 5 min (countdown started at 4m57s).
- Size tags scale value; we map them onto the existing mutation/paint system rather than adding a new stat.

## Status (2026-11-01)

| Milestone | State |
|---|---|
| 1. Audit | Done. 2,097 scripts mirrored from Studio; graphify graph built. |
| 2. Vertical slice (roam → capture → hotbar) | Done, verified in Studio play. |
| 3. Dealership (park → $/s → collect) | Done, reuses the existing podiums. Verified in Studio play. |
| 4. Progression (Steal Power, 5 zones) | Done for the core ladder. Power purchase verified in play; the deeper zones were not playtested one by one. |
| 5. Events & polish | Partly done: 5-min reset with secret cars, Rush mutation event, announcements, toast/tray, lobby tips. See "Not done". |
| 6. Testing & hardening | Headless harness 178/178. Single-player Studio play only. |

### What the loop is now
1. Spawn at your plot. Walk south over the START ZONE line into a long corridor split into 5 zones (City, Desert, Forest Mountains, Arctic, Futuristic City), each with its own floor and a gate arch showing "⚡ N+ TO STEAL".
2. Herds of 2–4 cars roam each zone (14 per zone). Each car has a label: tags (SECRET / mutation / "new!"), rarity, name, "Required: ⚡N" (green if you can, red if not).
3. Stay next to a car for 0.45 s with enough ⚡ and it is yours: burst + "IT'S YOURS!" toast + SECURED tray, and it lands in the hotbar via `GarageService.awardCar` (source `"Capture"`).
4. Carry it home and park it on a podium: it earns value/240 $/s into the bay's pad; walk over the pad to collect.
5. Spend cash on STEAL POWER (+ on the ⚡ pill). Each level unlocks the next car tier; crossing a zone's minimum unlocks that zone (`WorldsUnlocked`) and drops its barrier.
6. Every 5 min every herd re-rolls and 1–3 SECRET cars (rung 9–10, Charged/Molten/Ghost) spawn, announced to everyone. A Rush event every 150 s gives one zone a mutation for 60 s.
7. Driving/racing is untouched and still starts from the PLAY button.

### Files
New:
- `ReplicatedStorage/shared/Configs/CollectorConfig.luau`: every number (corridor, zones, power ladder, spawn, movement, capture, events). `Enabled` turns the whole rework off.
- `ServerScriptService/server/Services/RoamingCarService/init.luau`: server authority for spawning, moving (deterministic legs), capture validation, resets and events.
- `ServerScriptService/server/Services/RoamingCarService/CollectorWorld.luau`: builds the zone floors, gates and start line at boot.
- `ReplicatedStorage/shared/Controllers/RoamingCarController.luau`: renders cars near the camera, labels, capture input, local zone barriers.
- `ReplicatedStorage/shared/Controllers/CollectorHudController.luau`: ⚡ pill + power panel, zone strip, toast/tray, announcements, reset timer, hints.
- `tests/collector/`: headless Luau harness (`sh tests/collector/run.sh`).

Changed (each is a small, flag-gated edit):
- `UpgradeConfig`: `Power` upgrade (priced by `CollectorConfig.powerCost`); `costOf` honours a `PriceOf`.
- `UpgradeService`: accepts `Power` even though it is not on the upgrade board.
- `GarageConfig.Income.Passive = CollectorConfig.Enabled`: bays pay $/s again.
- `TutorialConfig.Enabled = not CollectorConfig.Enabled`: the driving tutorial is off.
- `ShowcaseConfig.Sources.Capture = false`: no "NEW BEST!" cutscene on every steal.
- `TipsConfig`: collector tips replace the driving tips while the flag is on.

### Decisions
- **Passive income over tips.** Matches the reference's $/s pen, and `GarageService` already had the passive path behind a flag.
- **One Power level per car tier.** `requiredFor(tier)` is a smooth curve; price = factor × the value of the tier it unlocks, never less than 1.12× the previous price. Level 1 costs $600 (one Civic): the first playtest at $1,500 meant an 8-minute wait.
- **Zones are physically open.** The barrier is client-side; the server re-checks power on every capture, so walking past a barrier gains nothing.
- **`World`/`WorldsUnlocked` kept in sync** from the zone you stand in and your power, so existing systems (weather, Index, analytics) keep working.
- **Luck does not affect roaming spawns.** Spawns are shared by everyone on the server, so a per-player stat cannot weight them.
- **Size tags (video) mapped onto mutations** instead of a new stat.
- **Capture has no idempotency in `awardCar`**, so `RoamingCarService` claims and removes the car before any yield; the replay and two-player races are covered in the harness.

### Test results
- Headless harness: **178 passed, 0 failed**. Covers power ladder and price monotonicity, movement maths, zone lookup, and capture validation (happy path, replay, two players racing, too far, moving slack, weak then upgraded, malformed input, dead player, cooldown, profile not ready, secret announce).
- Studio play (single player, mock profile), all observed:
  - Boot clean; ~72 cars across 5 zones; zone floors and gates built.
  - 3 Civics captured in 5 s; each landed in the hotbar and the Index.
  - First car parked through the first-placement flow, three more through the podium prompt: $/s went 3.1 → 11.25.
  - Collected from the pads; bought Power 1 for $600; ⚡ pill shows 11 and labels re-coloured.
  - 5-min reset banner with secret-car lines fired; weak-power hint shows.

### Bugs found and fixed during play
- Car labels never drew: the billboard was created before its car was parented to the workspace. Now built after parenting and adorned to the car body.
- Zone strip overlapped the "earn while offline" line; moved below it.
- City floor (light concrete) read as snow; now asphalt grey.
- Old lobby tips taught the truck/race loop; replaced while the flag is on.

### Not done / known gaps
- Multiplayer not playtested (two-player capture races are covered only by the harness).
- Rejoin persistence not playtested in Studio (mock store). `Power` is a normal upgrade key, so old profiles read it as level 0.
- Zones 2–5 not walked one by one in play, and a zone unlock (barrier dropping at the zone minimum) has not been seen in play yet.
- Mobile layout not checked on a device emulator.
- The Daily Rewards popup still opens on join over the HUD (existing behaviour, untouched).
- Labels are depth-tested (hidden behind walls). Billboards set to always-on-top did not show in the Studio capture tool, so the always-on-top look could not be checked.

### Next steps
1. Two-player Studio test (Test → Clients and Servers) for capture races and announcements.
2. Walk each zone at its minimum power; tune `Power.EarlyFactors` and `Spawn.RungWeights` against a real session.
3. Mobile emulator pass on the HUD.
4. Decide whether the Daily Rewards popup should wait until after the first capture.
