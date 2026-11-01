# Car Collector Rework — Progress

Branch: `feature/open-world-collector-rework` · remote `v2` = https://github.com/Rezault/steal-and-drive-v2
Studio place used for build/test: "steal car v2" (placeId 103274860383115). The owner confirmed it is safe to edit.
Studio playtests use the ProfileStore mock (`Data/Components/Settings.luau` `DEBUG_MOCK = true`), so no production saves are touched.
Nothing was published. Originals of every Studio script that was overwritten are in `ServerStorage.CollectorReworkBackup_2026_11_01`.

## Design now (owner direction, 2026-11-01)

History: on-foot herds were rejected ("nothing like the game in the video"). The PLAY-button race highway
with jump-to-steal came next. Then the owner asked to remove PLAY altogether: "theres just an area in the map
where dinos spawn and you go in and jump into one ... make that race area be one big lane". So:

1. **No PLAY button, no races.** `CollectorConfig.racesOn()` is false while `Enabled and Roaming`.
   - `RaceEntryController` hides PLAY.
   - `RaceService.enterRace` refuses every entry: button, lobby pad, admin.
2. **The highway.** The canyon corridor south of the plots is a six-lane road through the five zones, with
   lane paint from `CollectorWorld`.
   - Cars enter at each zone's arch and drive straight down their lane at 18 / 26 / 34 studs/s (outer lanes
     slowest).
   - A car is removed at the next arch. Secrets loop their zone.
   - Rarer cars prefer the fast middle lanes (`Road.FastRungs`, `LanePreference`).
   - Each zone holds about `Spawn.CarsPerZone` cars, spaced at least `Road.MinGap` apart per lane.
3. **Walk in and JUMP.** Within `Leap.Range` (42) of a car you have the ⚡ for, it gets a green outline
   and a "SPACE · JUMP!" tag. Jump leaps you in an arc with a front flip and lands you on its roof. The car
   goes into your hotbar (toast, "N SECURED" tray) **and you are put in its driver's seat** where it was.
   - The server re-checks distance against the car's deterministic lane position, ⚡, and the cooldown.
   - A weak jump shows "You need ⚡N".
   - **Drive and chain.** You keep driving the car you took. Space in the driver's seat with a car
     highlighted leaps from your car to that one, and it replaces yours. With nothing highlighted, Space
     exits the car as before. (Owner: "let me drive it until i decide to jump into another".)
   - **Starter car.** Anyone with no car gets their start car (`StartCarService:carFor`, world 1) parked
     beside them: on join, respawn, Back to Base, or selling theirs. It is free and never added to the
     inventory. This is `LobbyCarService`'s open-world car, one per player (`CollectorConfig.Drive`).
4. **Steal Power (⚡)** gates cars: every label shows "Required: ⚡N", green if you can, red if not. Zone arches
   block you until you meet the zone's minimum.
5. **Train ⚡ on the kiddie ride** at your plot. It rocks while ⚡ rises every half second. The **+** on the ⚡
   pill buys ride levels.
6. **Park cars on podiums** for $/s (unchanged).

The PLAY-mode road steal (`RoadSteal`) and the getaway truck are switched off but kept in code.

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
| 2. Vertical slice (highway → leap → hotbar) | Done, verified in Studio play. |
| 3. Dealership (park → $/s → collect) | Done (first build), reuses the podiums. |
| 4. Progression (⚡ gate + kiddie ride) | Done, verified in Studio play. |
| 5. Events & polish | Toast/tray, tips, red/green labels, reset and rush events, secret laps. |
| 6. Testing & hardening | Headless harness 172/172. Single-player Studio play only. |

### Files
New:
- `PowerTrainerService` / `PowerTrainerController`: kiddie rides, the ⚡ stat, its rocking and "+1" pops.
- From the first build: `CollectorConfig`, `RoamingCarService` (+ `CollectorWorld`), `RoamingCarController`, `CollectorHudController`, `tests/collector/`.

Changed for the highway:
- `CollectorConfig`: `Roaming = true`, `RoadSteal = false`, `racesOn()`, `Road` (lanes, speeds, gaps), `Leap`, linear `positionAt`.
- `RoamingCarService`: herds replaced by lane traffic (`_pickLane`, `_setLeg`, `_fill`, `_stepTraffic`).
- `CollectorWorld`: lane paint per zone. It also moves the authored median props (trees, rocks, bushes) that
  stand on the highway into `ServerStorage.CollectorRoadScenery` at boot (228 props). That is runtime only;
  the place file keeps them.
- `RoamingCarController`: rewritten for targeting, the leap, the landing ride and the capture poof.
- `RaceEntryController`: hides PLAY. `RaceService`: refuses entry while `racesOn()` is false.
- `GetawayConfig`: off while either collector steal mode is on. `TipsConfig`: tips teach the highway.

Changed for driving:
- `CollectorConfig.Drive` (Starter, StarterDelay, Swap, SeatDelay).
- `RoamingCarService`:
  - `_driveCaptured` swaps you into the captured car;
  - `_ensureCar` / `_watchStarter` give the starter (on CharacterAdded and on `LobbyCarService.CarDespawned`).
- `LobbyCarService`: a server-only `free` spawn option that skips the ownership check. The client remote
  still carries only a key.
- `LobbyCarController._jumpExit` calls `RoamingCarController:leapFromSeat()` after exiting.
- `RoamingCarController`: `leapFromSeat`; an accepted capture no longer hops you off the roof.

### Decisions
- **The leap is client-animated, server-judged.** The client flies the character (PlatformStand + per-frame
  CFrame) and fires the capture on landing. The server checks the player against the car's position, which
  both sides compute from the same lane leg (A, B, T0, T1), with slack for latency.
- **Cars never stop or swerve.** Each one is one straight leg, so there is no physics and no network traffic per car.
- **⚡ is its own saved number** that grows continuously while riding. New and old profiles start at 10.
- **The median is moved, not deleted**, so turning the collector off brings the authored map back as it was.

### Test results
- Headless harness (`sh tests/collector/run.sh`): **165 passed, 0 failed**. Includes:
  - lanes centred and mirrored, and zone road ends;
  - spawn interval, lane preference and MinGap;
  - arch blocking and reopening;
  - removal at the far arch and secret laps;
  - `_fill` spacing;
  - linear `positionAt`;
  - plus the earlier ⚡, ride and capture-validation tests.
- Studio play (single player, mock profile), all observed this build:
  - Boot clean, no errors. 7–9 cars per zone; 228 median props moved off the road.
  - PLAY hidden (`MainUIV2.HUD.Play.Visible = false`).
  - Standing on zone 1: the nearest car with ⚡10 needed got the green outline within 4 s.
  - SPACE: flew an arc onto a red Civaro's roof. Server log "banked a Stock Civic (Tier 1) into their inventory",
    then the "Discovered! CIVARO" toast, "1 SECURED" tray, and the car in hotbar slot 2.
  - A car needing ⚡11 showed red and was never targeted.
- Studio play, driving build:
  - On join, a starter Civic was parked beside the player at their plot.
  - On-foot leap onto a Civic: banked as `Civic:8#1`, the starter was replaced, and I was seated in the new
    car on the highway.
  - Held W: it drove about 170 studs in 2.5 s. With a target highlighted, Space in the driver's seat leapt
    onto a GNX: banked `GNX:1#2`, the Civic was removed, I was seated in the GNX, and the tray showed
    "2 SECURED".
  - Died: after respawn, a fresh starter Civic was parked 14 studs away.
- Harness: **172 passed, 0 failed** (adds the swap: key, seated, facing down the lane, standing where the
  car was; and the starter: given when carless, not when you have a car or are dead).

### Bugs found and fixed during play
- PLAY stayed up: nothing restated its visibility at boot. Fixed: `_watchPlayRoom` restates it.
- `CollectorHudController:474` errored when an announcement arrived before the HUD was built at join. Fixed: guarded.
- Highway traffic drove through the authored tree median. Fixed: the median props are moved aside (see Files).
- Earlier builds:
  - `PowerTrainerController` Luau "ambiguous syntax".
  - `StealController` was over the 200K `Source` limit (synced with `UpdateSourceAsync`).
  - The kiddie ride never rocked (streaming; now `Atomic`).
  - "Required" labels were hidden behind the hint row (now three rows).

### Not done / known gaps
- Multiplayer (two players leaping at one car), rejoin persistence of ⚡ (mock store), and mobile/gamepad
  jump not checked in play.
- Zones 2–5 and the arch barriers were not walked through in this build's play test.
- The gamepad X shortcut for the hidden PLAY may still be bound; the server refuses the race anyway.
- The old race HUD pieces (zone distance strip "▲ 60 m") still show on the highway.
- A captured car starts from rest; it does not inherit the roaming car's speed.
- Respawning gives the starter back, not the last car you drove (that one is in your inventory).
- Mobile: no on-screen jump button was checked while driving; the leap from a seat is bound to Space and
  gamepad A only (`LobbyCarConfig.JumpExit.Keys`).
- If a roaming body has no rig in `CarSystem`, the swap fails (logged) and you keep your old car.

### Next steps
1. Two-player Studio test (Test → Clients and Servers).
2. Tune lane speeds, `CarsPerZone` and `Leap.Range` against a real session.
3. Walk every zone with enough ⚡ and check arches, secrets and the rush event.
