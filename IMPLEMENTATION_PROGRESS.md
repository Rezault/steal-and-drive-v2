# Car Collector Rework — Progress

Branch: `feature/open-world-collector-rework` · remote `v2` = https://github.com/Rezault/steal-and-drive-v2
Studio place used for build/test: "steal car v2" (placeId 103274860383115) — owner confirmed safe to edit.
Studio playtests use the ProfileStore mock (`Data/Components/Settings.luau` `DEBUG_MOCK = true`), so no production saves are touched.
Nothing was published. Originals of every Studio script that was overwritten are in `ServerStorage.CollectorReworkBackup_2026_11_01`.

## Design now (owner direction, 2026-11-01)

The first build (walk into roaming herds on foot) was rejected in playtest: "nothing like the game in the
video". The loop was rebuilt around the existing race highway:

1. **Press PLAY.** Traffic spawns ahead on the one wide highway and drives straight.
2. **Catch a car and press SPACE.** The existing jump-and-land steal flies you into it. The car is yours
   instantly: "IT'S YOURS!" toast, SECURED tray, into the hotbar (`GarageService.awardCar`). You keep driving
   the stolen car. There is no getaway truck (`GetawayConfig.Enabled` is off while `RoadSteal` is on).
3. **Steal Power (⚡) gates which cars you can take.** Every traffic car shows "Required: ⚡N", green if you
   can, red if not. Cars above your ⚡ are never locked or offered as a jump target. The server re-checks.
4. **Train ⚡ on the kiddie ride** (our take on the reference's toy horse). Each plot has a coin-op kiddie
   ride car. Sit on it and ⚡ rises every second, with a bounce and "+0.2" pops. The **+** on the ⚡ pill buys
   kiddie ride levels (24) for a faster rate: 0.2 ⚡/s at level 0, ×1.277 per level.
5. **Park cars on podiums** for $/s (unchanged from the first build). Wrecking ends the run and returns home.

On-foot roaming herds are switched off (`CollectorConfig.Roaming = false`) but kept in code.

## Reference video analysis (Screen Recording 2026-11-01 113528.mp4, 26 s, 1 fps frames)

Confirmed from footage:
- Third-person follow camera; a long corridor split into zones with a top-centre zone strip and distance in metres.
- Overhead label per collectible: tags, rarity line in rarity colour, name, "Required: ⚡N" (green when you meet it).
- ⚡ stat bottom-left above cash, each with a green "+".
- Capture → heart burst, toast "IT'S YOURS! — <name> — Keep going!", "N SECURED" tray, unit in the hotbar at once.
- Base pen with `$N/s` labels (passive income). Players train ⚡ on a toy horse.
- World event: "ALL HERDS RESET!" banner with secret spawns.

## Status (2026-11-01)

| Milestone | State |
|---|---|
| 1. Audit | Done. 2,097 scripts mirrored from Studio; graphify graph built. |
| 2. Vertical slice (road → steal → hotbar) | Done, verified in Studio play. |
| 3. Dealership (park → $/s → collect) | Done (first build), reuses the podiums. |
| 4. Progression (⚡ gate + kiddie ride) | Done, verified in Studio play. |
| 5. Events & polish | Toast/tray, tips, red/green labels. Herd reset/secret events belong to the off Roaming mode. |
| 6. Testing & hardening | Headless harness 139/139. Single-player Studio play only. |

### Files
New:
- `ServerScriptService/server/Services/PowerTrainerService.luau`: builds the kiddie rides, loads/saves ⚡ (`StealPower` profile key), pays riders each second.
- `ReplicatedStorage/shared/Controllers/PowerTrainerController.luau`: ride bounce and "+⚡" pops (cosmetic).
- From the first build: `CollectorConfig`, `RoamingCarService` (+ `CollectorWorld`), `RoamingCarController`, `CollectorHudController`, `tests/collector/`.

Changed:
- `CollectorConfig`: `RoadSteal = true`, `Roaming = false`; ⚡ is now a stored stat (`Power`), trained by `Trainer` (rate, price ladder); `requiredForBody`.
- `StealController`: `_canTake` keeps cars above your ⚡ out of the lock and the jump target.
- `StealService`: after a successful steal, `RoamingCarService:awardRoadSteal` awards the car (server ⚡ check).
- `CarRarityBadge`: "Required: ⚡N" line, green/red, in road-steal mode.
- `GetawayConfig.Enabled = not (Collector.Enabled and Collector.RoadSteal)`: no truck.
- `UpgradeConfig`/`UpgradeService`: the `Trainer` upgrade ("KIDDIE RIDE"). The earlier `Power` key never shipped.
- `CollectorHudController`: ⚡ pill and kiddie ride panel; SECURED tray clears when a run starts.
- `TipsConfig`: tips teach the road + kiddie ride loop.

### Decisions
- **⚡ is its own saved number, not an upgrade level**, because it now grows continuously (riding), not in steps. New and old profiles start at 10, enough for every tier-1 car.
- **The landing is not gated.** Coming down on a car you are too weak for still puts you in it (no wreck), but the server does not award it and you get "You need ⚡N". The lock and jump target never offer such a car, so this only happens when one drifts under you.
- **Rates:** world 1's best car (tier 10, ⚡30) is about 100 s of riding at level 0; level 1 costs $600.

### Test results
- Headless harness (`sh tests/collector/run.sh`): **139 passed, 0 failed**. Covers the ⚡ ladder, ride rates and prices, `requiredForBody`, road-steal awards (weak, enough power, profile not ready), and the Roaming-mode capture validation.
- Studio play (single player, mock profile), all observed:
  - Boot clean; 6 kiddie rides built.
  - Sat on the ride: ⚡ 10 → 11 in 5 s (0.2/s), "+0.2" pops, prompt hidden while seated.
  - Bought kiddie ride level 1 for $600: rate rose to 0.255/s.
  - PLAY → drove → SPACE at a Civic 59 studs ahead: flew in, "Rezault banked a Red Civic (Tier 1) into their inventory", now driving it, tray "1 SECURED".
  - ⚡ forced to 5: every label turned red, the jump had no target (red reticle).
  - Driving into traffic wrecks; the run ends and returns home.

### Bugs found and fixed during play
- `PowerTrainerController` failed to load (Luau "ambiguous syntax" on a line starting with `(`).
- `StealController` is over Studio's 200K `Source` limit; synced with `ScriptEditorService:UpdateSourceAsync`.

### Not done / known gaps
- A weak landing (see Decisions) still refills health like any steal.
- The ⚡ pill overlaps the CONTROLS card for the first seconds of a run.
- The "+0.2 ⚡" pop drops the ⚡ glyph in Fredoka One.
- The wreck panel still shows the race payout line ("+$56 · kept 25%").
- Multiplayer, rejoin persistence of ⚡ (mock store), and mobile layout not checked in play.

### Next steps
1. Two-player Studio test (Test → Clients and Servers).
2. Tune `Trainer.BaseRate`/`RateGrowth` and prices against a real session.
3. Decide whether a weak landing should refuse the refill, and what the wreck panel should show.
