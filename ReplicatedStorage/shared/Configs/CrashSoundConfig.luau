--[[
	CrashSoundConfig
	----------------
	WHAT A COLLISION SOUNDS LIKE (2026-10-12). Played by `ObstacleController` from the two places that
	already know a crash happened: `applyImpact` (every hit: traffic, police, obstacles, wall rails) and
	`_onWrecked` (the car is done). Nothing else needs wiring: a new hazard that goes through
	`applyImpact` is heard for free, the same way it is shaken and smoked for free.

	THE CLIPS LIVE IN THE PLACE, as every SoundController group does: `SoundService.<Group>` holds one
	Sound per variation, and a variation is picked at random without an immediate repeat. A Sound may
	carry a `StartAt` attribute (seconds) to skip a clip's silent lead-in; see `SoundController.PlayRandomAt`.

	WHAT EACH GROUP IS, all Pro Sound Effects, picked by measurement (AudioAnalyzer, edit mode):

	    CrashHit     Vehicle Panel Impact 1/8/10/13. Peak on the first frame, 0.1 s body: a crunch
	                 that lands exactly on the hit.
	    CrashHeavy   Vehicle Crash 1 (metal and glass smash). Layered on top from `HeavyShake` up.
	                 The other "Vehicle Impact" clips start 0.24 to 0.59 s late and were rejected.
	    CrashScrape  Vehicle Door Curb Scrapes 2/3/6 (TradingPaint uses 1/4/9), StartAt 0.1. A wall
	                 tick repeats every `ObstacleConfig.Wall.Cooldown` while you ride the rail, so it
	                 is the quietest of the four.
	    CrashDramatic  Metal Crash 2/7, StartAt 0.12: a two-second crunch with debris. Layered on top
	                 of the heavy one for a FAST hit on something solid (`Speed`).
	    CrashWreck   Metal Crash 3/4/8: a big crunch with a debris tail, StartAt 0.12.

	FASTER IS MORE DRAMATIC (2026-10-12, the owner: "if its a faster collision maybe a more dramatic
	one"). `Shake` says what you hit and is capped by its kind: a traffic clip never passes 0.75 however
	fast you met it. So a hit is also scored on its IMPACT SPEED (`Speed`), weighted by how solid the
	thing is, and that score turns up the base clip and brings in the heavy and dramatic layers. The
	shake rules above stay as a floor, so nothing got quieter than it was.

	PLAYED ON THE CAR, positionally, so a hit on the left pans left. `RollOffMin` is past the chase
	camera's distance, so the car itself is never attenuated; the roll-off only matters to a
	listener who is somewhere else.

	`Enabled = false` is the game exactly as before: silent crashes.
]]

local CrashSoundConfig = {}

CrashSoundConfig.Enabled = true

--- Which group a hit plays, by `applyImpact`'s `source`. Unknown sources fall back to `Car`.
CrashSoundConfig.OnHit = {
	Car = "CrashHit",
	Obstacle = "CrashHit",
	Wall = "CrashScrape",
}

--[[ Layered on top of the `OnHit` clip once a hit's `Shake` reaches this, the same line
	`CrashVfxConfig.HeavyShake` draws for the heavy smoke (a Barrier is 1.2, Concrete 1.6). ]]
CrashSoundConfig.Heavy = {
	Group = "CrashHeavy",
	MinShake = 1.2,
}

--[[ THE SPEED SCORE, 0..1: `(speed - Slow) / (Fast - Slow)`, times the hit's solidity. Studs/s.

	Speed is the CLOSING speed. Traffic hands it over (`ImpactSpeed`, from `TrafficController._severity`),
	because traffic is moving too: rear-ending a 60 car at 85 is a 25 hit, not an 85 one. Everything
	else uses the car's own speed INTO the hit (velocity along the hit direction), which for a
	stationary obstacle is the closing speed, and for a wall rail is only the sideways part.

	Solidity is 1 for a car (`Solid` on the kind) and `Shake / SolidShake` capped at 1 for anything
	else, so a cone at full nitro (0.35 / 1.6, about 0.2) never sounds like a wall at full nitro.

	For scale: cruise is 85, nitro adds 46, traffic runs 35 to 73, so a rear-end at cruise closes at
	about 15 to 50 and one on nitro at 60 to 95. What that gives with the numbers below:
	    rear-end at cruise, slow car (50)    0.40  heavy
	    rear-end on nitro (80)                0.70  dramatic
	    Barrier at cruise (85)                0.56  heavy
	    Concrete at cruise (85)               0.75  dramatic ]]
CrashSoundConfig.Speed = {
	Enabled = true,
	Slow = 10,
	Fast = 110,
	SolidShake = 1.6,
	HeavyAt = 0.4,
	DramaticAt = 0.7,
}

CrashSoundConfig.Dramatic = {
	Group = "CrashDramatic",
	--- On top of the speed-scaled volume. Below 1 because this clip holds its loudest for two seconds.
	Volume = 0.85,
}

CrashSoundConfig.Wreck = {
	Group = "CrashWreck",
	Volume = 1,
	Pitch = 1,
}

--[[ Below this `Shake` a hit is silent. Some kinds (boost pads, slicks) go through `applyImpact` with
	a `Shake` of 0 because they are not crashes. ]]
CrashSoundConfig.MinShake = 0.05

--[[ Loudness and pitch by how hard the hit was: lerped from `Volume[1]` / `Pitch[1]` at `MinShake` to
	`Volume[2]` / `Pitch[2]` at `FullShake` (1.6, Concrete), or by the speed score when that is
	higher. Harder hits are louder and a little lower. `PitchJitter` is a random +- on top, so two cones in a row are not one sample twice. ]]
CrashSoundConfig.FullShake = 1.6
CrashSoundConfig.Volume = { 0.55, 1.15 }
CrashSoundConfig.Pitch = { 1.06, 0.92 }
CrashSoundConfig.PitchJitter = 0.05

--- Studs. See the header on why the minimum sits past the chase camera.
CrashSoundConfig.RollOffMin = 60
CrashSoundConfig.RollOffMax = 400

--[[ Two hits inside this many seconds play once. A traffic clip can report on consecutive frames and a
	stack of identical crunches reads as a stutter, not a bigger crash. The heavy layer and the wreck
	are not throttled. The dramatic layer has its own, longer one: its clip lasts two seconds and two
	of them over each other is mud. ]]
CrashSoundConfig.Cooldown = 0.08
CrashSoundConfig.DramaticCooldown = 0.6

return CrashSoundConfig
