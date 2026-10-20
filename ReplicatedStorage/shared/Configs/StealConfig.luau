--[[
	StealConfig
	-----------
	Every knob for the signature mechanic (GDD §3.4, `docs/StealMechanic_Plan.md`): tap Space,
	your driver leaps out, you fall onto a car ahead, and you drive off in it.

	FOUR THINGS TO KNOW BEFORE TUNING ANY OF IT.

	1. THE PLAYER NEVER LEAVES THEIR SEAT. Not once, for the whole run. What you see in the air
	   is a *flight avatar* — a clone of the character, CFrame-driven — while the one real car
	   stays seated, network-owned, anchored, and flying invisibly under it. A steal is therefore
	   a REDRESS, not a spawn: `Handoff` below teleports that same car onto the target and swaps
	   its paint. Nothing unseats, nothing re-deploys the stock driver controls, nothing fades.
	   Plan §2 has the full derivation, and every bug it dodges is one this repo already paid for.

	2. THE ARC IS SCRIPTED, NOT SIMULATED. The avatar is anchored and integrated by hand in the
	   ROAD's frame (`along` down the drive direction, `cross` across it, `y` world-up) — the same
	   frame TrafficController keeps its cars in. That's what lets the touchdown point be RUN
	   FORWARD rather than waited for (the `Marker` block below reads it out, by stepping the very
	   same integrator), and it's what makes a world rebase mid-flight one addition, not a mystery.

	3. CURRENT PREDICTABILITY PASS: launch speed is clamped to 90–110% of the current car's ordinary
	   cruise, glide is a fraction of that same cruise, and progression expands forgiveness rather
	   than changing the trajectory. Brake, nitro, car swaps and upgrade levels therefore cannot
	   invalidate the core jump timing.

	   THE ARC WAS ORIGINALLY A POP AND A HOVER. You left at the car's speed and
	   keep it through the rise; then, from the apex on, `Flight.Glide` bleeds you down to a shade
	   above traffic pace and `Flight.Float` catches the fall, so the descent is long and slow. Most
	   of your closing therefore happens in the first half-second, and the rest of the flight is
	   spent hanging over the lane you picked, adjusting. Speeds are absolute studs/s against the
	   same numbers TrafficConfig uses: the driver cruises at ~52 and boosts to ~71, traffic runs
	   24–30 (Tier 1) up to 39–44 (Tier 5).

	   THE LEAP WAS LENGTHENED (`Launch.Up` 88 → 108, `Flight.Glide` 34/3.5 → 39/2.8): the first
	   pass read as a hop rather than a leap. At today's defaults hang time is ~2.0s (was 1.65) and
	   the arc covers ~89 studs of road (was ~69), so net closing over a whole flight is ~35 studs
	   on a Tier 1, ~21 on a Tier 3 and ~6 on a Tier 5 — a beater can be taken from well over a car
	   length back, while A SUPERCAR STILL HAS TO BE DRAWN ROUGHLY LEVEL WITH FIRST, which is what
	   boost is for. Re-tune the glide and the tier speeds together, never in isolation.

	   THE NUMBERS HERE ARE THE UNBOUGHT ARC. `UpgradeConfig.Jump` — the fourth tile on the dealership
	   billboard since 2026-08-14 — multiplies `Launch.Up` by up to 1.20 and `Flight.Glide.Speed` by up
	   to 1.40, applied in `StealController` off the player's own levels. So everything derived above is
	   the FLOOR: a maxed player hangs 2.26s and glides at 54.6, which takes net closing on a Tier 5
	   from +3 studs over a whole flight to +21 — "draw level first" becomes "reachable from about a
	   car length back". Tune against this block, not against a maxed save,
	   and read `UpgradeConfig.Jump` before moving either of the two numbers it scales — the split
	   between them (air is bought at half the rate reach is) is an argument about this arc.

	   HALF OF HOW FAR THE LEAP *LOOKS* IS NOT IN THIS BLOCK AT ALL, and it cost a tuning pass to
	   find that out: the road is a tiling texture with no landmarks, so the car you bailed out of
	   is the only thing on screen measuring the distance. While it held station behind the arc, no
	   amount of extra reach read as extra reach. See `BailedCar` — that is where the sense of
	   travelling somewhere actually comes from.

	4. SLOW-MO IS OFF IN THIS PASS. `SlowMo.Enabled = false`, so every scripted system multiplies
	   its dt by exactly 1.0 and behaves bit-for-bit as it did before this file existed. The wiring
	   is already in (Modules/TimeScale), so turning it on is one boolean — but read that module's
	   header first, because physics, TweenService and task.wait cannot obey it and there are rules
	   about what may be on screen while it runs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- For `TierStats` only: the global tier of every car, and what each of those cars is worth. See
-- that block — this file no longer holds a stat curve of its own.
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local CarConfig = require(ReplicatedStorage.shared.Configs.CarConfig)

local StealConfig = {}

-- Master switch. Off = Space does nothing and none of this loads. The rest of the game is
-- untouched, which is also how you A/B whether the mechanic is carrying its weight.
StealConfig.Enabled = true

-- === Input ==================================================================
--[[ What bails, and how hard we have to shout to get it.

	SPACE IS ALREADY SPOKEN FOR, and it's worth knowing by whom before changing this. The stock
	`Driver` LocalScript maps Space to the HANDBRAKE (`Keymap.Handbrake`) and binds its raw-input
	handler with `BindActionAtPriority(..., ContextActionPriority.High.Value, ...)` — 3000, above
	the PlayerModule's own movement actions — and that handler SINKS every key it recognises. Two
	consequences, both good for us:

	  • Roblox's seat-jump-to-exit never sees Space, so tapping it cannot unseat the player. There
	    is no stock behaviour racing our bail.
	  • `DriveConfig.AllowHandbrake` is false and DriveController already no-ops the handbrake, so
	    Space currently does *nothing at all*. Taking it costs the player no existing verb.

	So we bind above 3000 and sink. ButtonA comes along because it's the gamepad handbrake and is
	therefore free for the same reason; mobile gets a JUMP button in the HUD pass (plan §6, T18/T23). ]]
StealConfig.BailKeys = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA }
StealConfig.BindPriority = Enum.ContextActionPriority.High.Value + 500

-- Note Space ALWAYS bails, even with no car ahead worth landing on (plan §11.6). Commitment is the
-- drama, and a bail with nowhere to go is a wreck the player chose; the ground marker is what turns
-- that from a gamble into a read.

-- === The launch =============================================================
--[[ The brief `Bailing` beat before free flight: the avatar scrambles up out of the seat and is
	thrown. Purely scripted, and it exists mostly so the *Getting out of your car* / *Jumping*
	animations have a beat to live in — with no animation yet it reads as a short crouch-and-go.

	Set `Time` to 0 to launch on the frame you press, which is the tightest-feeling version and a
	useful A/B when tuning the arc: it takes this delay out of the reaction budget entirely. ]]
StealConfig.Launch = {
	Time = 0.05,
	-- Studs above the car's roof the avatar is lifted to across `Time`, before ballistics take over.
	-- Small: this is climbing out, not the jump.
	Rise = 3.5,

	--[[ Vertical launch speed, studs/s. Against `Flight.RiseGravity` at 285 this apexes in ~0.32s,
		about 15 studs above launch — over quickly because everything interesting
		happens on the way down. Both halves of that are one line each:
		    apex time = Up / RiseGravity        apex height = Up² / (2 * RiseGravity)
		Raising `Up` alone makes the jump both higher AND slower; raise `RiseGravity` with it to keep
		the snap. The way down is not symmetric and is not derived from these — see `Flight`.

		THIS IS THE MAIN DIAL FOR HOW BIG THE LEAP IS, and it does far more than its own 8 studs of
		extra height: the fall is gentle and speed-capped, so every stud of apex buys disproportionate
		hang, and every second of hang is spent travelling down the road. 88 → 108 lifted the apex by
		8 studs and the whole flight by 0.35s and ~20 studs of road. Keep `RiseGravity` in step if the
		throw ever starts reading as a float — the rise is meant to be a throw.

		2.0s of hang is about the ceiling for this: past it the player spends more of the mechanic
		watching than deciding, and `Flight.Reach` (0.92s to cross at full steer) stops being the
		thing that limits a correction. If more distance is wanted from here, take it from `Flight.
		Glide` or from `BailedCar.Drift`, not from more air.

		FIXED ACROSS PROGRESSION. Jump upgrades enlarge control and capture tolerance instead, so
		buying a level never changes the timing learned on the previous one. ]]
	--- 2026-10-20: WAS 92. The hang (`Flight.Hang`) carries the arc higher on its own, so the throw
	--- is lowered to keep the apex where players know it (~26 studs).
	Up = 80,

	--[[ Fraction of the car's along-road speed the avatar carries into the arc.

		1 means you keep exactly the speed you bailed at, so closing speed in the air is the same
		closing speed you had on the road — which is the promise the whole read rests on ("jump when
		the gap is about a car length"). Below 1 you shed speed the instant you leave, which makes
		high tiers unreachable fast; above 1 is a slingshot and stops the jump being a read. ]]
	ForwardKeep = 1,

	--[[ Clamp the inherited road speed around THIS car's ordinary cruise. The old unrestricted
		carry made the same button produce a different landing depending on whether it was pressed
		during a brake, cruise or nitro frame. A small 90..110% window preserves momentum as a skill
		without letting temporary speed effects rewrite the whole arc. FallbackCruise is used only
		before DriveController has resolved a car. ]]
	SpeedWindow = {
		MinCruiseFraction = 0.9,
		MaxCruiseFraction = 1.1,
		-- Scripted forward throw applied after the predictable entry-speed clamp. This creates the
		-- long arcade leap without letting nitro or a brake frame produce an arbitrary trajectory.
		ThrowScale = 1.5,
		FallbackCruise = 75,
	},
}

-- === The air ================================================================
--[[ THE ARC IS DELIBERATELY LOPSIDED: up very fast, then down at a controlled readable pace.

	A symmetric ballistic arc spends its longest, most controllable stretch at the TOP — a long way
	from the road, where nothing you can see matters yet — and arrives at the ground at its highest
	speed, which is the one moment you'd actually want to be able to correct. That's backwards. So
	the rise is pulled hard (`RiseGravity`, over in ~0.32s: you're just thrown), the fall is controlled
	(`FallGravity`), and `Float` puts a ceiling on descent speed that tightens the closer you get,
	so the last few studs are a hover. The time budget ends up where the decision is.

	None of these are `workspace.Gravity`, and none of them can be: the arc is ours, integrated by
	hand, and nothing physics-simulated may be visible during a flight because physics cannot obey
	the time scale. ]]
StealConfig.Flight = {
	-- Studs/s² on the way up. High, on purpose — the pop should read as a throw, not a lob.
	RiseGravity = 285,
	-- Studs/s² on the way down. Strong enough to keep the full mechanic near 1.1 seconds.
	FallGravity = 100,

	--[[ The catch. A cap on how fast you may be falling, as a function of height above the deck:
		    cap = Speed + Falloff * height
		So `Speed` is what you touch down at (a settle rather than a drop) and `Falloff` is how many
		studs/s of extra allowance each stud of altitude buys. The cap sits below free-fall speed
		until it engages, so there is no seam where it kicks in — just a fall that quietly stops
		getting faster.

		THIS IS THE DIAL FOR "give me time to pick a lane on the way down", and it was too tight to
		use. `Falloff` sets how much of the descent is floated and `Speed` sets how slow the very end
		of it gets; both were raised (15/1.8) so the descent ran 0.99s. Crossing the full steering
		`Reach` at `SteerSpeed` takes 0.92s — so the air control existed but there was no room to
		spend it, and a late correction meant arriving with the input still moving. Lowering them to
		10/1.0 tightened the cap and stretched the descent past that, and the taller launch since
		(`Launch.Up` 108) puts it at ~1.47s: a comfortable margin over the 0.92s, and you stay moving
		down the road the whole time you're choosing.

		Both directions have a floor and a ceiling worth knowing. Below about `Speed = 8` the
		touchdown starts reading as floating down on a wire rather than landing. Going much longer
		also quietly shifts the tier balance — hang time is how long the glide gets to close on
		traffic — though at this size the effect is a couple of studs either way, well inside the
		~35-stud Tier 1 / ~6 Tier 5 spread the header describes. ]]
	--- 2026-10-20: WAS 16 / 1.6. A slower, flatter descent, the second half of the glide (`Hang`).
	--- 9 stays above the ~8 floor this note gives for the touchdown still reading as a landing.
	Float = { Speed = 9, Falloff = 0.8 },

	--[[ HISTORICAL AIR-BRAKE DERIVATION. FROM THE APEX ON, along-road speed eases from whatever
		you bailed at toward `Speed` — a shade above the pace of mid-tier traffic.

		This is what keeps the ground marker honest as a thing DIRECTLY UNDER YOU rather than a dot
		far down the road (see `Marker.Lead`). Carrying a full 52 studs/s through a ~2.0s flight puts
		touchdown ~105 studs ahead of where you are, and no circle drawn there is readable as yours.
		Bleeding to near traffic pace means that once you're over a car, you roughly STAY over it —
		you hang above the lane and pick, which is the whole read.

		IT IS ALSO THE ONLY DIAL THAT MAKES THE LEAP REACH FARTHER, and that's why it moved with
		`Launch.Up` rather than after it. More hang alone buys distance over the TARMAC but almost
		none over the CARS: the extra second is flown at traffic pace, so a longer flight lands you
		on the same car it always did. Braking to 39 instead of 34 is what turns the bigger arc into
		a bigger reach (Tier 5 net closing +1 → +6 studs), and the slower `Ease` — 2.8, settled about
		halfway down instead of a third — is where most of that comes from, since it spends the
		carried speed while you are still high and choosing rather than dumping it at the apex.

		THE COST, and it is small but real: at 39 against a Tier 1 doing 27 you close ~12 studs/s all
		the way down, so the circle under you and the point the arc actually lands differ by ~15 studs
		IN THAT CAR'S FRAME by the end of a flight. The colour stays honest (it is read off the
		prediction, never off the circle's position), and 15 studs is half a padded hit volume, so it
		reads as forgiveness rather than a lie. If it ever starts reading as one, `Marker.Lead` is the
		compensation — but it cannot be exact, because the drift depends on the TARGET's speed (~0.3
		cancels it on a Tier 1, ~0 on a Tier 5). That asymmetry is the real ceiling on this number:
		much past 40 and no single `Lead` keeps the reticle honest across the tiers. Don't put `Speed`
		back without also putting `Launch.Up` back.

		It only ever slows you down: bail below `Speed` and nothing happens (a glide that accelerated
		you would be a second, invisible boost). Set `Ease = 0` to switch the brake off entirely and
		get the old carry-everything arc back, which is the honest A/B for whether this is an
		improvement.

		`Speed` IS SCALED PER PLAYER by `UpgradeConfig.Jump` (x1.40 maxed, so 54.6). That is the whole
		payload of that upgrade, for the reason this block already gives: reach over CARS is bought
		here and nowhere else. It also means the ~15-stud circle-vs-landing drift described above is a
		bought number too — about 26 studs maxed against a Tier 1, still under a padded hit volume, and
		`Marker.Lead` is still the only compensation and still cannot be exact across the tiers. ]]
	-- Relative to ordinary cruise so every car sheds the same SHARE of its speed. The absolute 39
	-- was authored for the old ~52 studs/s game and made the faster roster's jump wildly variable.
	Glide = { CruiseFraction = 1.0, Ease = 2.8 },

	-- Seconds per step of the marker's forward run of the arc (`StealController._predict`). It steps
	-- the identical integrator the flight itself does, so this is purely how finely: fine enough not
	-- to visibly stair-step the circle, coarse enough that a ~1.1s flight is ~50 iterations of
	-- arithmetic. Lower it and the only thing that changes is the cost.
	PredictStep = 1 / 45,

	-- Hard cap on a flight, seconds of scaled time. Nothing should ever reach it — the arc comes
	-- down on its own — so this is a fail-safe against a stuck state, not a tuning dial. Reaching
	-- it is treated as a whiff.
	MaxTime = 6,

	--[[ AIR CONTROL. A/D (or the steer stick, or the touch slider) moves you across the road, read
		straight off the same input the lane change uses — DriveController stashes the player's raw
		-1..1 even while it's suspended, so this needs no second keybind and works on every device
		the car already works on.

		`Speed` is the cross-road studs/s at full input. Lanes are 15 apart, so 38 retains a decisive
		one-lane correction inside the shorter flight without allowing a road-wide teleport. `Accel`
		eases it so a tap doesn't teleport you sideways. `Reach` caps total drift from where you
		bailed: past about one lane either side the jump stops being a read and becomes a search. ]]
	--- 2026-10-20 ("allow the player to move significantly while in the air"): WAS 38. A lane (15 studs)
	--- in about a quarter of a second of full input, the whole `Reach` in well under a second.
	--- ...then 55 to 95 the same day ("still make the movement faster, about 1.5x or double ... quick,
	--- responsive"). The whole `Reach` in about a third of a second.
	SteerSpeed = 70, -- and 95 back to 70 ("a bit too fast now"): ~1.3x the 55 it was before the speed-up
	--- 2026-10-20: WAS 14 ("switch directions + speed quickly"). 24 reaches ~90% of a new sideways
	--- speed in under a tenth of a second, so a reversal reads as instant without a teleport.
	SteerAccel = 36, -- then 24 to 36 with it: a reversal is ~90% done in ~0.06s
	--- 2026-10-20: WAS 20, about one lane. The longer glide (`Hang`) only buys options if there is
	--- somewhere else to go, so 30 reaches the lane two over (lanes are 15 apart). Not more: it is capped at
	--- `HalfWidth` by the assert at the bottom of this file (34 tripped it and the steal stopped loading).
	Reach = 30,

	-- Keep the avatar inside the drivable corridor. Same half-width DriveConfig.LaneHalfWidth uses,
	-- so you can't fly somewhere the car could never have driven.
	HalfWidth = 30,

	--[[ THE HANG AT THE TOP (2026-10-20, playtest: the jump "feels too fast / unpredictable", other
		games let you "kind of glide for a little bit to properly choose"). While vertical speed is
		inside `Window` studs/s of zero, gravity is scaled down: `RiseScale` on the way up, `FallScale`
		on the way down. So the throw still snaps and the landing still settles, and the top of the arc
		becomes a float. At 20 / 0.35 / 0.5 the stretch either side of the apex inside `Window` takes
		0.6s instead of 0.27s, a third of a second more hang, and the apex sits about a stud higher. Time is not slowed (`SlowMo` was tried, and read
		as the game slowing down): the traffic keeps its pace and the player hangs over it.
		IN `_advance`, SO THE MARKER KNOWS: the prediction runs the same integrator, so the circle and
		the landing still agree. It costs a little reach-down-the-road (the extra hang is flown at
		glide pace, so a couple of studs). `Window = 0` switches it off. ]]
	--- 2026-10-20 (second pass, "still not enough glide ... options instead of quickly having to guess"):
	--- WAS 20 / 0.35 / 0.5, which only added ~0.2s. With `Float` 9/0.8 and `Launch.Up` 80 the flight runs
	--- 2.6s (was 1.5s), ~2.1s of it slow and near level, apex about where it was (26 studs). Measured by
	--- stepping this integrator, not estimated.
	--[[ ...and `Hold` (2026-10-20: "the player should start falling down a bit later, to allow for a bit
		of movement", now that they can fly by hand): from the apex, `Hold` seconds at `HoldScale` of the
		gravity, a near-level glide before the fall. 0.8s moves the start of the fall from ~0.7s to ~1.5s
		into the jump and the whole jump from ~2.5s to ~3.3s (~4.2s with the jump upgrade maxed), stepped
		on this integrator. `Hold = 0`: the fall starts at the apex, as before. ]]
	Hang = { Window = 30, RiseScale = 0.2, FallScale = 0.2, Hold = 0.8, HoldScale = 0.05 },
}

--[[ THE TARGET LOCK (2026-10-20, "maybe have the target lock onto a car? then if you move to another car
	it locks to the other one ... we need to experiment"). Three switches, each its own A/B:

	  `Enabled`  the ground circle leaves the road and sits ON THE ROOF of the car the arc will take
	             (the same car the green outline names), sliding between cars at `Slide` per second.
	             No car in reach: back under the avatar, as before.
	  `Stick`    the lock keeps the car it has unless another is better by this many studs, so two
	             cars side by side do not trade the lock back and forth every frame.
	  `Assist`   with the stick centred (inside `DeadZone`), the flight eases across toward the locked
	             car's lane so it lands on the roof rather than beside it, at `AssistGain`. It never
	             picks a car you have not already earned (the lock only exists inside the real reach),
	             and any steering of your own switches it off for that frame. ]]
StealConfig.Lock = {
	Enabled = true,
	--[[ THE ONE TARGET (2026-10-20 rework: "jumping initially doesn't show ANY car", "it steals a
		different car than the highlighted one", "prioritise cars IN FRONT and closest ... then diagonal
		or side"). With this on, `StealController._pickLock` names ONE car from the first frame of the
		jump, the circle and outline show it, and E takes that car or nothing (a roof you land on
		becomes the target). The window it picks in, in studs from the player along the road frame:
		`Ahead` up the road, `Behind` back, `Side` either way. `FrontFrom`: a car this far up the road
		counts as IN FRONT, and in-front cars always win. `SideWeight` makes a stud sideways count for
		more than a stud ahead when ranking by nearness. `AimColor`: the circle and outline while the
		target is not in E's reach yet; green (`Marker.Hit`) once it is. ]]
	--- 2026-10-20, second pass ("she wanted the car in front of her but ... it prioritised some car on
	--- the side"): `SideWeight` WAS 1.6, so a car one lane over 20 studs up beat her own lane's car 35
	--- up; at 3 the own-lane car wins unless it is much further. `Ahead` WAS 90: a fast car covers it
	--- in under two seconds.
	--- ...and 120 THEN 75 (same day, "the distance feels like a lot"): the lock reaches the nearer cars,
	--- not one far up the road the homing then has to dash to.
	Ahead = 75,
	Behind = 20,
	Side = 42,
	FrontFrom = 6,
	SideWeight = 3,
	--- Seconds of the player's sideways drift added to where they are when ranking cars, so steering
	--- toward a car counts before you are over it.
	AimLead = 0.4,
	AimColor = Color3.fromRGB(255, 214, 64),
	--[[ HOMING ALONG THE ROAD (`StealController._stepAir`): with a car locked, the jump's along speed
		eases (`HomeEase` per second) to that car's speed plus `HomeGain` x the gap, at most `HomeMax`
		studs/s either way. This is what stops a fast car's jump overshooting the target ("got
		launched"): you glide in over the car you picked and come down on it. `Home = false`: the arc
		keeps its own pace, as before. ]]
	Home = true,
	--[[ FORWARD AND BACK IN THE AIR (2026-10-20: "allow players, while they're gliding, to move up and
		back as well ... how will we handle that on mobile?"). The car's own throttle: W/S on a keyboard,
		the on-screen gas and brake pedals on a phone or tablet, the triggers on a pad, all one value
		(`DriveController.getThrottleInput`). Full gas leans the glide `AlongSpeed` studs/s ahead of the
		target's pace (brake: behind), and leans where the lock looks by `AimAlong` studs, so holding it
		moves the lock to the next car up (or down) the road. `AlongSteer = false`: along stays automatic. ]]
	AlongSteer = true,
	--- 2026-10-20 ("move significantly while in the air"): WAS 16, and the homing pulled it back.
	--- With input the helpers stand down (`ManualHold`), so this is the real lean: 40 studs/s faster
	--- or slower than the car under you, eased in at `ManualEase` per second.
	AlongSpeed = 52, -- then 40 to 70, then 52 ("a bit too fast now")
	--- ...and back (2026-10-20: "let players move backwards too rather than merely stop in the air"):
	--- the car under you does ~30-45 studs/s, so 40 back only parked you; 75 flies you back down the
	--- road at ~30-45 studs/s, the same pace as the forward lean.
	AlongBack = 100, -- then 75 to 130, then 100: back down the road at ~55-70 studs/s
	--- WAS 6 ("really responsive, switch directions + speed quickly"): 12 is ~90% of a change in 0.2s.
	ManualEase = 18, -- then 12 to 18: ~90% of a change in ~0.13s
	--- Seconds after the last input before the homing and the assist take over again.
	ManualHold = 0.5,
	AimAlong = 30,
	--[[ THE HIGHLIGHTED CAR, TAKEN WITHOUT THE PRESS (2026-10-20: "we don't want them to wreck just cause
		they didn't click E"). With `Prompt.AutoSteal` the jump ending takes the car in reach on every
		device; a landing up to `LandReach` studs from the highlighted car (flat, road plane, scaled by
		the jump upgrade) still takes that one. Only coming down with no car near is a wreck now. ]]
	LandReach = 30,
	HomeGain = 0.9,
	--- 2026-10-20: WAS 30. A gentler catch-up, so closing on the target reads as gliding, not a dash.
	HomeMax = 18,
	HomeEase = 3,
	Slide = 14,
	--[[ HOW LOUD THE LOCKED CIRCLE IS (2026-10-20, "make the indicator more visible"). On a car it is
		drawn over the bodywork (`OnTop`, or the roof hides half of it), at full strength, a little
		bigger (`Grow`), and breathing: `Pulse` of its size either way, `PulseRate` times a second. ]]
	OnTop = true,
	Grow = 1.15,
	Pulse = 0.08,
	PulseRate = 2.5,
	Stick = 4,
	Assist = true,
	AssistGain = 0.6,
	DeadZone = 0.15,
}

-- === Landing ================================================================
--[[ What counts as TOUCHING DOWN on a car. Not what counts as stealing it — that is `Prompt` below,
	and the difference is the point of this whole section: coming down on a roof parks you on it, and
	E is what takes the car.

	Tested against each traffic shell's `Hit` volume IN LUA — a point-in-box test in that part's own
	frame — rather than with a spatial query, and that is a deliberate dodge rather than a shortcut.
	`CarCollision`'s whole matrix means an OverlapParams left in "Default" comes back empty for every
	traffic car on the road; a query would have to run as `PlayerGroup` to see anything, which has
	already bitten `TrafficController._checkClips` once. Twelve point-in-box tests per frame cost
	nothing and cannot be misconfigured.

	The volume is deliberately FATTER than the car (plan §3, and the GDD's own feel rule: "whiffing
	should always feel like the player's fault, never the hitbox's"). `Hit` is sized to the visible
	bodywork — 21.85 x 10.36 on the test body — so a 4-stud pad makes it 29.85 x 18.36.

	THAT IS WIDER THAN A LANE IS SPACED, on purpose. Lanes are 15 apart, so two cars side by side
	share about 3.4 studs of claimable road, and coming down in that strip is genuinely ambiguous —
	you are between two cars. It's resolved by taking the NEAREST volume rather than the first one
	found (StealController._boxDistance), and the ground marker asks the identical question of the
	predicted point, so the circle can never promise one car and deliver the other. Drop this below
	about 2.3 if you'd rather the lanes never overlap at all; it will cost forgiveness across the
	road, which is the axis a player is most likely to be slightly wrong on. ]]
StealConfig.Landing = {
	Pad = 4,

	-- Studs above the deck at which a flight with no car under it becomes a splat. Generous, because
	-- the avatar's origin is its root (roughly waist height) rather than its feet.
	DeckGrace = 3,
}

-- === The prompt (E · Steal) =================================================
--[[ THE STEAL IS A BUTTON PRESS, NOT A COLLISION. Get near a car in the air and a prompt reading
	`E · Steal` appears over it; press E and that car is yours. Nothing takes a car on its own.

	This replaced an auto-mount that fired the instant you touched a roof, and the reason is what it
	felt like rather than what it did: the signature mechanic — the one the game is named after —
	happened TO the player. You aimed, and then you watched. Putting the commit on E costs one input
	on a beat that already has your full attention, and it buys the moment back. Plan §4 called this
	one ahead of time and picked the same side, for the same reason.

	IT IS ALSO WHERE THE FORGIVENESS NOW LIVES, and that matters more than the input does. The old
	rule was a point-in-box test: land inside the padded volume or eat asphalt. `Range` is a plain
	radius around the padded box instead, so coming down BESIDE a car is a steal you can still take —
	you no longer have to hit it, only get to it.

	THE WINDOW IS ~1.3 SECONDS WIDE, and it is worth knowing which half is which before shortening
	either. `Flight.Float` caps descent at `Speed + Falloff * height`, so the last 18 studs take
	ln(31/13) ≈ 0.87s to fall — that is `Range` paying out as time, and it is why a radius in studs
	buys a window in seconds. `Grace` adds ~0.45s on the end after the arc is over. A press inside
	that is a decision; a press outside it was never coming.

	NOT A `ProximityPrompt`, and this is not a stylistic preference — it cannot work here:

	  1. The stock `Driver` LocalScript sets `ProximityPromptService.Enabled = false` for the whole
	     drive (see DriveController's cleanup note, which restores it). It's a GLOBAL switch on a
	     service, owned by place-side code we don't control. A real prompt would simply never draw.
	  2. Activation distance is measured from the CHARACTER — who is seated, hidden, inside a car that
	     is 22–70 studs behind the flight (`BailedCar`). It would measure from the wrong place all
	     race.
	  3. It would have to track a car doing 40 studs/s in the road frame, and obey the time scale.

	So we draw a billboard that looks like a prompt and bind the key ourselves — which costs nothing,
	because the bail already binds above the stock Driver's 3000 and sinks (see `BindPriority`). ]]
StealConfig.Prompt = {
	--[[ Off = the old behaviour, exactly: no prompt, no E, and touching a roof mounts you on contact.
		Kept as the A/B for whether the press is carrying its weight, and as the escape hatch if the
		billboard turns out to be in the way of the shot. ]]
	Enabled = true,

	--[[ E, taken from underneath the stock vehicle rather than found free — the earlier note here
		claimed nothing else binds it, and that was simply wrong. The deployed `Driver` LocalScript
		binds it to `VehicleChassisExitVehicle`, so before `DriveConfig.HoldSeatDuringRace` a press
		outside a flight unseated the driver and ended the run. Two bindings sit above that one now:
		this at 3500, live only while a flight is, and the swallow at 2500 that eats every other
		press for the length of the race.

		ButtonX is the gamepad equivalent (the stock exit is ButtonY, so they do not collide). A phone
		has neither, and the answer there is `Touch` below plus `DrivingHud.Controls.Jump` — the one
		on-screen button that reads JUMP in the seat and STEAL in the air. ]]
	Keys = { Enum.KeyCode.Space, Enum.KeyCode.E, Enum.KeyCode.ButtonX },

	--[[ AUTO-STEAL ON A PHONE (2026-10-14, Aleafo: "if you don't press the button and you are in the
		radius of a car it should auto steal, because the timed button is hard, the game is fast").
		On TOUCH only: a jump that comes down with a car in reach (this prompt's radius, the green ring)
		takes it, on the roof or in the grace window after, without the press. A tap in the air still
		steals early, exactly as before. Keyboard and gamepad keep the press. `false`: press-only. ]]
	TouchAutoSteal = true,
	--- ...and on EVERY device since 2026-10-20 (`Lock.LandReach` has the why): a missed press is never a
	--- wreck. E in the air still steals early, as before. `false`: touch only, as above.
	AutoSteal = true,
	--- Seconds after a touch JUMP in which the same button's STEAL is ignored (`StealController.bail`):
	--- the jump's own tap, landing twice, was stealing the first car the lock named (2026-10-20).
	BailGuard = 0.35,

	--[[ Studs from the car's PADDED volume — its bodywork plus `Landing.Pad`, in every direction
		including up — inside which the prompt lights and E works.

		18 is about a car length, and it is sized against the descent rather than against the car: you
		fall the last stretch at roughly `Flight.Float.Speed`, so this is ~1s of window on a clean
		approach and still open when you come down a lane off. Much smaller and it turns back into the
		hitbox test it replaced; much bigger and you can take a car you were never near, which reads
		as the game playing itself.

		Measured in 3D on purpose. A flat radius would arm the prompt while you were 20 studs directly
		above a car, i.e. at the apex, and E at the apex is a lock-on — the thing plan §4 rejected.

		IT IS A NUMBER THAT GETS DRAWN NOW, which it was not when it was written. The ground ring is
		sized from this plus `Landing.Pad` (`Marker.MatchReach`), so moving it changes what the
		player is shown as well as what E does, and the two cannot drift apart. ]]
	Range = 18,

	--[[ Seconds the prompt stays live AFTER the flight is over — parked on the roof you came down on,
		or standing on the tarmac beside a car you nearly got. This is "even if you miss, you can
		still grab it", and it is the difference between a mistimed press and a dead run.

		It is also what stops a no-press landing looking broken. Without it, a flight that comes down
		on a roof with nobody pressing anything has to keep falling, and the avatar sinks through the
		car it just landed on. Set to 0 and that returns; the window is then the air time only. ]]
	Grace = 0.55,

	-- A steal press made just before the candidate enters range is consumed when it becomes valid.
	-- This removes frame-perfect timing without choosing a car or extending the spatial reach.
	InputBuffer = 0.3,

	--[[ The words. `Key` goes in the cap and `Label` on the pill — two elements, so the key can be
		restyled per device without touching the wording.

		CAPS, BECAUSE IT IS A KIT PILL NOW and every caption on one of those is: BUY CAR on the
		plaza's stands, UPGRADE on the forecourt board, PLAY on the HUD. ]]
	Key = "E",
	Label = "STEAL",

	--[[ === THE THIRD DEVICE, AND THE BUG IT CLOSES ===========================================

		THIS PROMPT USED TO SAY "E" ON A PHONE. `_ensurePrompt` branched two ways — keyboard cap or
		controller glyph, off `GamepadInput.observePreferred` — and touch was simply not a case, so a
		mobile player in the air over a car worth taking was told to press a key their device does not
		have, on a pill that was a `Frame` and could not be pressed either. That is the whole of
		"Mobile: buttons to get into a different car do not work": the mechanic worked (the HUD's own
		JUMP/STEAL button drives the same `StealController:steal()` the key does, verified end to end
		on an emulated iPhone), but nothing on screen ever said so.

		SO THE CAP BECOMES THE BUTTON THE PLAYER ACTUALLY HAS. `Glyph` is the same art
		`DrivingHud.Controls.Jump` wears on its STEAL face, drawn where the keycap goes — exactly the
		trick the gamepad branch already plays with the controller button. The prompt over the car and
		the button under the thumb are then visibly the same thing, which is the only sentence a
		control prompt has to get across.

		AND THE PILL ITSELF IS PRESSABLE ON TOUCH, as a second target for the finger already reaching
		for it. Belt and braces on purpose: the corner button is still the answer and the art still
		points at it. (Until 2026-10-06 the billboard sat in the workspace, where a GUI button never
		takes input, so this half was dead and Leaf tapped a pill that did nothing. It lives in
		PlayerGui now; see `StealController._ensurePrompt`.)

		`Glyph` matches the `StealImage` attribute on that button in `StarterGui.DrivingHud` — the two
		are re-skinned together or the prompt starts pointing at a button that no longer looks like
		it. `Label` is shared with the other two devices; only the cap changes. ]]
	Touch = {
		Glyph = "rbxassetid://78505096430486",
		--- Tapping the pill is the same call `_onSteal` makes for E, guards and all. Off = the art
		--- still changes but only the HUD button presses, which is the safe half of this feature.
		--- 2026-10-20: OFF. With the thumbstick back for flying (`DrivingHudController.setFlying`), a thumb
		--- landing on the pill to start a drag stole the car mid-glide ("it automatically puts me in the
		--- car I'm over"). The landing takes the car anyway (`AutoSteal`) and the HUD button still presses.
		Pressable = false,
	},

	--[[ === IT IS MADE OF THE KIT NOW — 2026-08-25 =============================================

		WHAT IT WAS: a `#101218` `Frame` with a `UICorner` at radius 0.5, a 2px mint-green `UIStroke`
		round the outside, a mint-green rounded square for the keycap and GothamBold in both labels.
		Nothing in that sentence is from this game. `car ui (3).psd` is the kit, Ubuntu Bold is the
		typeface every sign and page in the place is set in, and the mint green
		(`Color3.fromRGB(84, 220, 130)`) existed in exactly two places: here, and the ground reticle
		it was rhyming with. A dark lozenge with a neon outline is what a prompt looks like when
		nobody has decided what it should look like, and that is what the bug card was reporting.

		WHAT IT IS: `UIAssets.Pill.Green` — the artist's own button face, shaded, bordered and
		checkered like everything else — with the keycap beside it rather than sunk into it. Which
		makes it the same object as the plaza's BUY CAR prompt (`CarDealController._buildPill`), and
		that is the point rather than a coincidence: this game now asks for a press in ONE shape, and
		a player who has bought a car on the roundabout already knows what a green pill with a key
		next to it wants from them.

		GREEN RATHER THAN BLUE for the reason the plaza's is: green is the one that means go, and it
		is the colour the reticle under you has just turned. See `Marker.Hit`.

		=== ONE NUMBER, AND THE REST IS ARITHMETIC ===============================================

		`Size` used to be a `Vector2` of two independent pixel counts, which is a thing that can be
		set wrong: the pill art is aspect-locked (`UIAssets.Slice`'s block on why no pill is ever
		9-sliced) and a box that does not match its 3.89:1 renders it as a lozenge. So the HEIGHT is
		configured and the width is derived from that aspect plus the cap and its gap — the prompt
		re-fits itself if the pill is ever re-cut, and there is no pair of numbers to keep in step.

		`KeyScale` and `KeyGap` are both fractions of `Height`, so the cap stays square at any size.
		A little shorter than the pill on purpose, and the same fraction the plaza's uses: it reads
		as sitting beside the button rather than as part of it. ]]
	Height = 46,
	KeyScale = 0.84,
	KeyGap = 0.18,

	-- Studs above the top of the car's `Hit` box the billboard floats. Clear of the roof, below where
	-- the flight avatar will be on the way in.
	Lift = 4.5,

	--[[ Seconds the prompt takes to scale up when it appears, and what it starts at. Small and
		deliberate: at 0 it pops, and a prompt that pops on and off as you drift between two cars'
		ranges is a flicker. Per `effect-intensity-taste` this is the restrained version — it eases
		in, it does not bounce. ]]
	PopTime = 0.12,
	PopScale = 0.72,

	--- Both captions: the pill's and the keycap's. Pure white, the same as every other kit pill's.
	Text = Color3.new(1, 1, 1),
}

-- === The mount ==============================================================
--[[ The beat between pressing E and being in the driver's seat: you drop onto the roof, the door
	swings, the driver goes over the side, and then you're behind the wheel.

	IT USED TO BE ONE NUMBER DOING TWO JOBS and the animations are what forced them apart. `Time` was
	both the lunge and the whole beat, at 0.3s, which was fine while the beat was dead air. It isn't
	any more: `Animations.Clips.Land` is 1.63s of landing-and-throwing, and cutting to the driver's
	seat a fifth of the way into it would show the arrival and none of the point.

	`LungeTime` IS THE DIVE. Since the steal fires off the prompt rather than off contact, E can be
	pressed from anywhere inside `Prompt.Range` — up to a car length out, and above the car as often
	as on it. So the avatar eases from wherever it was when you pressed onto the roof across this,
	which turns "E from 15 studs away" into a dive rather than a teleport. At 0 it teleports, which is
	the honest A/B for whether the dive is worth its 0.3s. It should stay well inside `Time`: the
	landing clip's own first beat is the arrival, so the body wants to be ON the roof by the time the
	clip gets to standing on it.

	`Time` IS THE WHOLE BEAT, and it is time the player isn't driving — the one real cost of the
	throw. The car keeps driving underneath (TrafficController._updateCars advances a frozen car), so
	this is spent riding a moving roof rather than parked, which is what makes it watchable. It is
	also the window `Driver.ReleaseAt` throws the NPC inside of, so shortening one without the other
	cuts the throw off mid-air.

	`MatchLandClip` PREFERS THE TRACK'S OWN LENGTH over the number above, so a re-uploaded landing
	clip re-times this beat on its own instead of being quietly truncated by a stale constant. `Time`
	is then the fallback for a clip that didn't load (and the value when animations are off), and it
	is kept in step with the measured length by hand — see `Animations.Clips`.

	`Anchor` IS THE ONE PLACEMENT NUMBER, and the landing clip is what decides it. THE CLIP MOVES THE
	BODY ITSELF: it is authored against a single fixed root, and across its 1.63s it walks the body
	3.8 studs onto the driver's side and 3.4 studs down — off the roof, out over the door and into
	the seat, because the last third of it is the player getting INTO the car. So the root must be
	pinned once and left alone. Anything that re-places it per frame is fighting the animation for
	control of the same body.

	Measured off the asset, in root-local studs (`RigAnimator` on a stationary rig, sampled across
	the clip):

	    clip t     0.0    0.1 – 1.2      1.33      1.43      1.53      1.63
	    sole      +1.74   +0.79 … +1.64  -0.06     -1.60     -2.29     -2.59
	    hip X     +0.03   0 → -3.64      -3.78     -2.96     -1.65     -0.93

	Two numbers fall out of that and they are the two below. The sole holds at about **+0.85** for
	the whole second the character is on the roof, so the root belongs **0.85 studs BELOW the roof**
	for the feet to be on it. And the body finishes **0.93 studs** to the driver's side of the root,
	while the driver's seat is 1.71 studs off the car's centreline — so the root belongs **0.78 studs
	toward the driver's side** for the seated end pose to land in the seat. Both ends line up from
	one anchor, which is what says the clip really was authored against a car.

	IN THE CAR'S OWN FRAME: -X is the driver's side and -Z is the nose on every body in this pack
	(CarDoorRig's `SIDES`). Y is measured from the ROOF — the top of the shell's `Hit` box — not from
	the deck, so a tall body and a low one both get a landing on their own roof.

	TWO EARLIER VERSIONS OF THIS WERE WRONG IN OPPOSITE DIRECTIONS, and both are worth knowing
	because the failure looks the same from the outside. A flat 2.5 studs of hip height assumed a rig
	standing up, so the tucked pose the clip opens with hung 1.5 studs clear of the roof. Measuring
	the pose every frame and planting the lowest point on the roof fixed the hover but then pinned
	the character to the roof plane through the part of the clip that is supposed to descend into the
	car — so they walked off the side of it and stood on the road. The clip owns the motion; this
	owns where the motion starts.

	WITH ANIMATIONS OFF the avatar is a static seated clone and this anchor sinks it into the roof by
	about two studs. That is the debug A/B path and it is not worth a second code path.

	`Reach` IS NOT A PLACEMENT AT ALL and never was, despite having shared a number with one: it is
	how far above a roof the arc still counts as having touched down (`_landingTarget`). It kept the
	old 2.5 through the rename because the landing test has not changed. ]]
StealConfig.Mount = {
	Time = 1.63,
	MatchLandClip = true,
	LungeTime = 0.3,
	Anchor = Vector3.new(-0.78, -0.85, 0),
	Reach = 2.5,

	--[[ How fast the landing beat plays: the `Land` clip on you and `DriverThrown` on the driver, as a
		matched pair, and the beat length with them (`_mountBeat` divides by this). 1 is the clip as
		authored (~1.63s on the roof); 1.35 is ~1.21s. The beat was the longest stretch of a steal spent
		at traffic pace, and trimming it is the cheapest half of keeping a steal's momentum. ]]
	PlaybackSpeed = 1.35,

	--[[ THE STOLEN CAR PICKS UP SPEED WHILE YOU TAKE IT. Without this you ride the roof at traffic pace
		for the whole beat and then take the wheel at that pace (`Handoff.InheritVelocity`), so a steal
		taken flat out felt like the whole game hitting the brakes — the road and the camera crawl past
		at a third of the speed you jumped at.

		So from the moment E commits, the car under you eases toward `Fraction` of the speed you BAILED
		at, at `Ease` per second. The handoff already inherits that car's speed, so you take the wheel
		already moving. It only ever speeds the car up — steal something faster than you and nothing
		changes — and it never drives THROUGH the car ahead in its lane: it may close on it, but no
		faster than `Horizon` seconds would take to reach `MinGap` behind it. A slow car right in front
		of your prize is still yours to dodge, but with room: the catch-up stops `MinGap` studs short of it.

		`Fraction` below 1 keeps trading down a real choice (the car still settles to its own top
		speed once driven) without making every steal a stop. `Enabled = false` is the old ride. ]]
	CatchUp = {
		Enabled = true,
		Fraction = 0.9,
		Ease = 2.6,
		-- Bumper studs the car will not close inside of the car ahead: at the handoff you want room to
		-- react to a slower car, not a crash a quarter of a second after you take the wheel.
		MinGap = 40,
		Horizon = 0.7,
		-- Studs between car centres that count as bumper to bumper, and studs across for "same lane".
		CarLength = 22,
		LaneWidth = 7.5,
	},
}

-- === Animation ==============================================================
--[[ The four clips the steal is built out of. All R15, all played on a rig with nothing else
	competing for it — the flight avatar's Humanoid has its state machine switched off, and the
	thrown driver is a bare rig — so `Action` priority (which is what they were uploaded at) is
	uncontested and nothing here has to fight a walk cycle.

	THE BEAT, END TO END:

	    Space ──► Bail (0.80s) ──────────► FreeFall (loops) ──► E ──► Land (1.63s) ──► driving
	              out of the seat,          the flip, held             onto the roof,
	              onto the roof, thrown     for as long as             the door, the throw
	                                        the arc lasts
	                                                              ╰─► DriverThrown (0.90s)
	                                                                  on the NPC, at the same time

	`Length` IS MEASURED, NOT GUESSED, and it is written down here for a reason: it is the fallback
	when a track fails to load, and it is what `Mount.Time` was sized against. Re-measure it whenever
	a clip is re-uploaded — `KeyframeSequenceProvider:GetKeyframeSequenceAsync` in an edit-mode
	command reads it straight off the asset without a playtest.

	`Looped` IS AUTHORED HERE AND NOT ON THE ASSET, deliberately. All four were uploaded with the
	animation editor's default `Loop = true`, which a freshly loaded `AnimationTrack` inherits — so
	left alone, the bail clip would climb out of the car on a loop for the whole flight and the
	landing would replay itself until the handoff. `RigAnimator` writes this onto every track it
	loads, so the asset's own flag never matters either way.

	THE HANDOVER FROM `Bail` TO `FreeFall` IS ON A CLOCK, not on the clip's `Stopped` event, and that
	is what keeps it correct in slow motion: the crossfade fires off `FALL_LEAD` seconds before the
	bail clip's end measured in FLIGHT time, which is the same scaled clock the arc integrates on, so
	dipping the time scale stretches the clip and the handover together. An event would fire on the
	track's own (engine) clock and arrive early.

	Against today's arc the timing lands about right on its own: the launch is 0.08s, the rise apexes
	at 0.45s, and the bail clip runs 0.80s — so the climb-out and the throw read over the pop and the
	flip takes over just as the fall settles in. If the arc is ever re-tuned hard, this is the pairing
	to re-check. ]]
StealConfig.Animations = {
	--[[ Off = the static-clone flight this shipped with: the avatar flies in whatever pose it was
		sitting in. Kept as the A/B, and as the escape hatch if an asset ever goes missing — every
		beat below is timed by the state machine rather than by the clips, so nothing else changes. ]]
	Enabled = true,

	-- Seconds of crossfade between clips. Short: these are cuts between poses that already roughly
	-- agree, and a long fade on a 0.8s clip eats most of it.
	Fade = 0.12,

	Clips = {
		-- Out of the seat, up onto the roof, and thrown. Plays across the launch and the rise.
		Bail = { Id = 72610014721331, Length = 0.80, Looped = false },
		-- The flip, on the way down. THE ONLY LOOPING ONE, and it has to be: hang time varies with
		-- where you bailed from and how long you leave the commit.
		FreeFall = { Id = 121892905890120, Length = 1.333, Looped = true },
		-- Down onto the roof and the driver goes over the side. Sizes `Mount.Time`.
		Land = { Id = 90422696552674, Length = 1.633, Looped = false },
		-- The other half of the throw, on the NPC. Runs alongside `Land`, on its own rig.
		DriverThrown = { Id = 95604426797231, Length = 0.90, Looped = false },
	},
}

-- === The driver you throw out ===============================================
--[[ There is a person in that car, and you take it off them.

	TRAFFIC SHELLS HAVE NO DRIVER (TrafficService._buildShell: 21 parts of welded visual mesh, no
	seat, no rig), and giving a dozen cars a full R15 each would be a dozen rigs of skinned mesh
	nobody looks at until they are standing on the roof. So the driver is spawned FOR THE THROW, on
	the one car being stolen, at the moment E commits — which is the first frame anybody is close
	enough to see one. Plan §5's two-tier scheme (a cheap silhouette in every car, the full rig only
	on the target) keeps the first tier for later; this is the second, which is the half the beat
	needs.

	THE RIG IS BUILT, NOT AUTHORED. `Players:CreateHumanoidModelFromDescription` makes a rig out of a
	`HumanoidDescription` with no model in the place and nothing in git to keep in sync — which
	matters here because a rig asset is exactly the kind of thing a fresh CarBones import or a place
	rollback quietly loses. A hand-coloured description gives the CLASSIC NOOB — yellow, blue and
	green — which is the right look for a nameless motorist and is the fallback the whole `Friends`
	block below degrades to. (An EMPTY description does not give a default avatar, it gives a black
	one; `StealController.NOOB_COLORS` has the measurement.) It is a WEB CALL and it YIELDS, so it is
	made once at start-up and cloned per throw; a throw that arrives before it has landed simply has
	no driver, which is why the whole block degrades to nothing rather than to an error.

	THE THROW IS TWO HALVES. For `ReleaseAt` of the clip the rig is anchored and pinned to the car's
	driver seat, so the animation plays out in the car's frame while the car keeps driving — an
	unanchored rig would be left standing in the road the instant it spawned. Then it is handed to
	physics as a ragdoll with the car's own velocity plus `Kick`, and tumbles away behind. Per
	`effect-intensity-taste` the kick is sized to read as a shove out of a door rather than as a
	cannon: outboard and up, with enough backward bias that the body clears the car it came out of. ]]
StealConfig.Driver = {
	--[[ Off = the car you take is empty, exactly as it was before this landed. The landing clip still
		plays — it reads as vaulting in — so this is a clean A/B for whether the NPC is worth its
		rig. ]]
	Enabled = true,

	--[[ THE PERSON IN THAT CAR IS ONE OF YOUR FRIENDS — their real avatar, built from their real
		`HumanoidDescription`, so the body that goes over the side is recognisably theirs down to the
		hat. Plan §5's goal, and GDD §8 open question 3 answered in the affirmative.

		WHOLLY CLIENT-SIDE, which is a simplification the plan didn't have: §5 costed this as a
		server-side fetch cached per player and replicated, because it assumed a shared road. There
		isn't one. Traffic, the steal and the driver exist only on the stealing player's machine, so
		the only friends list anybody needs is their own — no remote, no server cache, nothing another
		client has to be told, and no player data crossing between players.

		THREE WEB CALLS DEEP AND EVERY ONE OF THEM CAN FAIL: the friends list, each friend's
		description, and the rig build. Nothing in a race waits on any of it. The rigs are built once
		at start-up, and every failure — no friends, an unreachable endpoint, a throttle, Studio with
		no logged-in user — falls straight through to the blocky default above, which is exactly what
		shipped before this existed. A steal in the first seconds of a session gets whichever rigs
		have landed.

		BUILT AS R15 WHATEVER THE FRIEND WEARS. `Animations.Clips.DriverThrown` is authored on an R15
		skeleton, so the rig type is forced rather than taken from the description — a friend on an R6
		avatar still gets their shirt, face and hair on a skeleton the throw clip can actually drive.

		`Count` IS HOW MANY FACES A SESSION HAS, not how many friends are read. Rigs are kept for the
		whole session and cloned per throw, so the cost is a one-off `Count` rig builds — each a full
		avatar with layered clothing and accessories rather than the default's handful of parts.
		Three is enough that the throw doesn't read as the same person every time (the picker never
		repeats back to back) without turning start-up into a download. Avatar scales come along with
		the description, so a very tall or very small friend sits a little off `SeatOffset` for the
		0.7s the clip runs; that is them, and it is not worth a per-rig correction.

		`Scan` is how deep into the friends list we read before choosing, and the choice is a shuffle
		over everything read. So it is about variety across sessions rather than about finding
		anybody: one page covers most accounts, and a player with 200 friends shouldn't be throwing
		out the same three all week. ]]
	Friends = {
		Enabled = true,
		Count = 3,
		Scan = 60,
	},

	--[[ Where the rig's root sits relative to the shell's stamped driver-seat frame while the clip
		plays. Up, because a `VehicleSeat`'s own frame is at seat-pan height and an R15 root is
		roughly waist height on a seated body. Nudge this, not the clip, if the driver reads as
		sitting in the floor or hovering over the roof. ]]
	SeatOffset = CFrame.new(0, 1.2, 0),

	-- Fraction of the throw clip after which the rig stops being animated and becomes physics debris.
	-- Below 1 on purpose: the clip's own last beat is already airborne, so letting it run to the end
	-- means the body snaps from an animated pose into a limp one in mid-air.
	ReleaseAt = 0.75,

	--[[ Studs/s added to the car's own velocity at the release, IN THE CAR'S OWN FRAME. Driver's side
		is local -X on every body in this pack and the nose is -Z (CarDoorRig's `SIDES`), so this is
		"out through the open door, up, and a shade backward". Added to the car's velocity rather than
		replacing it, so a driver thrown out of a Tier 5 leaves faster than one thrown out of a
		beater.

		MEASURED AT THESE VALUES: the body clears the bodywork in about a fifth of a second and comes
		down roughly 20 studs outboard — a lane and a half over — around a second after the release,
		by which time the car has driven out from under it and the camera has moved on. `X` is the
		dial, and it is the one to reach for first: it is the difference between being shoved out of
		a door and being fired out of one. Below about 10 the body scrapes down the side of the car
		it came out of, which reads worse than either. ]]
	Kick = Vector3.new(-26, 18, 6),
	-- Random tumble, radians/s per axis. Same job as `Whiff.Spin`: no two throws land alike.
	Spin = 8,

	-- Ragdoll joint limits, degrees — the same pair and the same reasoning as `Whiff`: loose enough
	-- to look boneless, tight enough that a limb can't invert through the torso.
	JointAngle = 50,
	TwistAngle = 40,

	--[[ Seconds the body survives after the throw. It is behind the camera almost immediately (the
		car drives out from under it), so this is about not leaving rigs on the road for the rest of a
		run rather than about the shot. Anything still alive dies with the flight folder at the end of
		the race regardless. ]]
	DebrisTime = 4,
}

-- === The handoff ============================================================
StealConfig.Handoff = {
	-- 2026-10-04: Prepare invisible dress clones during the existing mount beat instead of doing
	-- every Clone on the final handoff frame. Four parts bounds each frame's allocation burst;
	-- any remainder is finished at handoff so low FPS cannot change the animation's duration.
	-- Disabling this restores synchronous preparation for a Studio profiler comparison.
	PrepareBody = true,
	PreparePartsPerFrame = 4,
	--[[ How much of the stolen car's momentum you inherit, 0..1.

		1 = you leave the roof doing exactly what that car was doing. That is the design: steal a
		Tier 1 beater and you drop from 52 studs/s to ~27 and have to wind back up (AutoThrottle does
		that for you in about a second), which is what makes trading DOWN a real mistake and trading
		up a real reward. 0 keeps your own speed and makes every steal free.

		Note this is speed along the ROAD only. The lateral component comes from the shell so the car
		lands already tracking its lane rather than crabbing. ]]
	InheritVelocity = 1,

	-- Studs the car's lowest bodywork is placed above the deck before physics settles the suspension.
	-- Same value and the same reason as RaceConfig.SpawnClearance: land it a shade high and let the
	-- springs take it down, rather than starting inside the road.
	Clearance = 0.5,

	--[[ Frames to hold the rider hidden after the teleport.

		The rider is welded to the seat, and a weld is resolved by the physics solver rather than
		instantly — so the frame after a teleport is the one frame where the character can visibly
		trail the car. Nobody should see that, and one frame of holding the existing hide is far
		cheaper than trying to move the character perfectly. (Two, to cover a dropped frame.) ]]
	SettleFrames = 2,

	--[[ Studs of slack in the "is anything else already parked where we're about to be" test that
		runs just before the car is handed back to the solver. Negative switches the test off.

		THE HANDOFF MATERIALISES A SOLID CAR IN AN OCCUPIED LANE. It teleports the player's car onto
		the shell they landed on, which is fine — that shell is recycled in the same frame, with no
		physics step in between, so the solver never sees the overlap. What the ordering does not
		cover is a SECOND car: traffic changes lane (`TrafficConfig.LaneChangeGap`), so the one
		beside your target can be halfway into its lane and overlapping the space you are about to
		appear in. Unanchor into that and the solver resolves two interpenetrating bodies the only
		way it can — it throws one of them — and the run ends with the player on their roof. That's
		observed, not theoretical.

		So anything genuinely overlapping is moved out of the way first, in the same no-physics-step
		window the target already uses — shoved sideways where that is enough, recycled where it is
		not (`MaxNudge`).

		0.5 is slack, not reach. Lanes are 15 apart and the two half-widths sum to ~9.9, so a car
		holding its lane is five studs clear and is never touched; only one that has come most of
		the way across qualifies. Widen it and you start disturbing cars you could have driven past.

		This is the cause fixed at source. DriveConfig.Upright is the general recovery behind it,
		for every other way a car can end up on its roof. ]]
	ClearMargin = 0.5,

	--[[ Studs of sideways shove a car in the landing spot may be given instead of being recycled.
		Beyond this it is deleted as before. Zero switches shoving off and restores that behaviour.

		THIS NUMBER EXISTS BECAUSE THE OLD COMMENT HERE WAS WRONG. It claimed losing a car from the
		road was "invisible in a way being flung is not". It is not invisible: it was reported from
		the 9 Aug playtest as cars vanishing, and the clip shows exactly why. `ClearMargin` is doing
		its job — the car it took was mid-lane-change, easing across into the space the handoff was
		about to occupy — but a lane change in progress does not READ as one. The player sees a car
		sitting in the next lane, in a gap they are plainly missing, evaporate. The test also compares
		BOXES, and a car body is rounded and tapers at the corners, so two boxes can overlap while the
		visible bodywork clearly does not.

		The margin is not the thing to change: shrink it and the flinging comes back, which is five
		reports against one. What was wrong was the RESPONSE — deleting a car is a drastic answer to a
		marginal overlap. So the response is proportional now. A car that has only just crossed the
		line is shoved clear of it and drives on, which is what a player expects to happen when you
		drop a car into traffic beside someone. A car genuinely deep inside the bodywork still goes,
		because shoving it that far is a teleport and would look worse than the deletion does.

		6 is a bit over half the ~9.4-stud reach, so the common case — a car a few studs into the
		line — is shoved, and only one most of the way into your lane is recycled. Raise it and the
		shoves start reading as teleports; drop it to 0 and every one of them goes back to vanishing. ]]
	MaxNudge = 6,
}

--[[ The car you just jumped out of, while you are in the air.

	It drops away behind you and then out of the shot entirely. Nothing separates the two on its own:
	with `Launch.ForwardKeep = 1` you leave at exactly the speed the car is doing, so a car that holds
	its speed sits parked under you for the whole flight and the jump reads as the car following you
	rather than as you leaving it. The car sheds speed instead — driverless, throttle released — and
	you coast out in front of it.

	THIS IS AN AUTHORED GAP, NOT A SIMULATED ONE, and the first attempt went the other way for
	good-looking reasons — give the car a deceleration and let the distance fall out of it. Measured
	across a whole flight, that produced 0.33 studs. THE PLAYER IS SLOWING DOWN TOO: `Flight.Glide`
	bleeds the arc from the ~52 studs/s you bailed at down to 39 from the apex on. A decel therefore
	only opens a gap with whatever it sheds ON TOP of the player's own glide, and one sized by eye
	against the car's speed mostly just re-drew the glide curve — both slowed together and neither
	pulled away. Tuning it properly would mean tuning the car against a moving target that is itself
	tuned for the closing read (`Flight.Glide` is load-bearing for which tiers are reachable, and the
	header says to re-tune it with the tier speeds, never in isolation). That is a lot of coupling to
	buy a piece of set dressing. An offset is independent of all of it.

	IT USED TO SETTLE, AND THAT WAS THE BUG IN THE SHOT. The gap eased out to one car length and then
	held there for the rest of the flight, which meant the car tracked the arc exactly — a reference
	object moving WITH the player, parked in frame at a constant size for the whole jump. The read
	that produces is "the world is sliding past a bit" rather than "I have covered ground", and it is
	why the leap looked short no matter what the arc was actually doing. The road can't fix that: it
	is a tiling texture with no landmarks, so the car you left is the ONLY thing on screen that says
	how far you went. It has to keep receding to say anything at all.

	So the gap now has two parts, and they do different jobs. `Lag` is the SHOVE — the fast ease-out
	that separates you from the car in the first half second, while both are still in frame and the
	door is up, which is the beat you actually watch. `Drift` is the RECEDE: from there the car keeps
	falling back for the rest of the flight, so it shrinks, slides off the bottom of the shot and is
	gone by about a second in. You see the door open and the car drop away, and then you are alone in
	the air, which is what the distance is measured against.

	`MaxLag` IS THE SAFETY BOUND THAT `Lag` USED TO BE. The car is still what `RoadController._loop`,
	`TrafficController._playerAlong` and the camera read to decide where the world is, so a gap that
	grows without limit would stream the road, and cull traffic, around a point behind the player.
	Bounded, it is a non-event, and the margins are worth writing down because they are what makes
	this safe: traffic spawns 260+ studs ahead and despawns 260 behind (`TrafficConfig`), and the road
	keeps `SegmentsBehind = 2` whole tiles behind the anchor. A 55-stud trail is a fifth of the
	nearest of those. Do not push `MaxLag` toward 260 without re-reading both. ]]
StealConfig.BailedCar = {
	-- Studs the car drops back in the first `LagTime` — the shove, and the part anyone sees. About one
	-- car length (the body is ~21.8 studs) is the point where it reads as left-behind while both are
	-- still comfortably in frame.
	Lag = 22,

	-- Seconds of FLIGHT time to ease across that gap. Flight time, not real time, so it keeps its
	-- meaning inside the slow motion — the same reason the arc itself integrates on scaled dt.
	LagTime = 0.5,

	--[[ Studs/s the gap keeps opening at afterwards, for the rest of the flight. A car length per
		second: at the current arc that is ~55 studs by touchdown, and it puts the car's own world
		speed at ~23 studs/s — slower than traffic, which is the right read for a car whose driver
		just left, and academic anyway because it is behind the camera long before then.

		Set this to 0 to get the old hold-station behaviour back, which is the A/B for whether the
		recede is what sold the distance. ]]
	--- 2026-10-20: WAS 22. Over the 2.6s glide (`Flight.Hang`) 22 opened ~68 studs, right at `MaxLag`, and
	--- every leap looked half as far again ("we're jumping too far"). 10 ends it ~43 back, where the
	--- 1.5s jump used to.
	Drift = 10,

	-- Hard ceiling on the whole gap, studs. Nothing normal reaches it — a full flight lands ~55 — so
	-- like `Flight.MaxTime` this is a fail-safe against a stuck state, not a tuning dial. It is the
	-- one number here the road anchor actually depends on; see above.
	MaxLag = 70,
}

--[[ The doors across the bail.

	The door goes up as you leave and is back down as you arrive: it swings open at the jump, stays up
	while the car you left drops away behind you, and is already shutting through the mount so you
	drop into a closed car. This is the only thing in the game that drives the door rig (see
	Modules/CarDoors for why nothing stock does).

	IN PRACTICE ONLY THE OPEN IS SEEN NOW. `BailedCar.Drift` takes the car out of frame about a second
	into the flight, so the door's whole readable life is the half second where it flings up and the
	car falls back under you — which is the beat worth having, and the reason `OpenSpeed` is the fast
	one. The shut is no longer an animation anybody watches; it stays because `_unanchorCar` needs the
	door on its shut pose before physics gets the car back, and driving it down through the mount is
	how it gets there without a snap.

	IT IS POSED, NOT SIMULATED, and that constraint shapes everything here. The bail anchors every
	part of the car so it can be moved by CFrame without the solver flinging it, and an anchored door
	is one the servo cannot turn — so `_flyCar` rotates the door geometrically instead
	(`CarDoors.poseFrozen`) and `_unanchorCar` unwinds that rotation before physics is handed the car
	back. The practical consequence for tuning: these speeds are pure animation rates, so nothing
	here can push the door through the bodywork or upset the car's handling no matter what it is set
	to. The angle is the one number that still has to be physically sane.

	THE JUMP-OUT ANIMATION HAS LANDED and the timing it was written against still holds: the door
	LEADS. `OpenSpeed` at 6 rad/s reaches 55° in ~0.16s while `Animations.Clips.Bail` takes 0.80s to
	get the body out, so the door is already up before the avatar has cleared the sill — which is what
	makes it read as the cause of the jump rather than as a reaction to it.

	`Target` IS THE OTHER DOOR: the one on the car you are stealing, swung as you land on it. It is a
	separate block because it is a completely different mechanism — the car you bail out of is a real
	CarBones rig with a hinge and a latch (`Modules/CarDoors`), while the one you land on is a traffic
	shell with neither, so its panel is turned by hand off a plan the server stamped at publish time
	(`Modules/ShellDoors`). Same beat, same angle, two implementations, and the shell's is the one
	that has to be unwound before the redress copies its meshes onto your car.

	Set `Enabled = false` to drop the whole beat; the doors still work, nothing just drives them. ]]
StealConfig.Doors = {
	Enabled = true,

	-- Matches the stock CarBones `DOOR_OPEN_ANGLE`, so a door driven from here and a door driven
	-- by the stock prompt handler land in the same place. On the Lambo's scissor rig this is a
	-- lift, not a swing-out — it clears the road by a comfortable margin at full travel.
	Angle = 55,

	-- Radians/second, matching the servo's `AngularSpeed` units so these read the same as they would
	-- if physics were turning the door. Deliberately faster open than close: the open has to beat
	-- the player out of the car to read as the cause of the jump rather than a reaction to it, while
	-- the close has a whole mount beat to finish in and is left at the stock 2.15.
	OpenSpeed = 6,
	CloseSpeed = 2.15,

	--[[ The stolen car's door, over the landing. Not shut again by anything: the shell is recycled at
		the handoff and the panel is unwound in the same frame (`ShellDoors.restore`), so the only
		thing that would ever watch it close is a bail that was abandoned.

		SLOWER TO OPEN THAN YOUR OWN, and that is the whole difference in what the two doors are
		saying. Yours is flung open by you and wants to beat you out of the car. This one is being
		opened FOR the driver, from the outside, in the middle of a 1.63s landing — it should be
		swinging while the throw happens, not finished before the body has touched the roof. At 3.2
		rad/s it reaches 55° in ~0.3s, which puts it wide open right as `Driver.ReleaseAt` lets go.

		`Enabled = false` here leaves the car you land on shut, and the driver comes out through it.
		Which is the state before this landed, and is not as bad as it sounds at speed — but it is
		what the beat looks like if a shell is missing its stamped door plan (an old published body,
		or one of the three in the pack with no separable panel), so it is worth knowing the shape
		of. ]]
	Target = {
		Enabled = true,
		Angle = 55,
		OpenSpeed = 3.2,
	},
}

-- === Missing (the whiff) ====================================================
--[[ You came down on tarmac. The flight avatar goes limp and hits the road, the camera drops to
	look at you lying there, and then the normal wreck-and-return beat takes you home.

	THE CAR IS NOT PART OF THIS SHOT. It stays hidden and anchored exactly where the flight left it —
	which, since `BailedCar.Drift`, is ~55 studs back up the road rather than on top of you — so
	nothing coasts through the body, nothing smokes out of thin air beside it, and there is exactly
	one thing on screen to look at. The rider stays hidden
	with it (they're still welded into that car), or you'd be looking at two copies of yourself.
	`RaceWrecked` carries the `"badLanding"` cause so ObstacleController knows to skip the engine
	plume and the coast it would otherwise give a dead car.

	A REAL RAGDOLL, not a tumbling mannequin. The avatar's Motor6Ds are swapped for
	BallSocketConstraints, which is about thirty lines and is the whole difference between a body
	and a plank — and the failure is the read the player gets when they mistime the signature
	mechanic, so it's worth the thirty lines. Style per GDD §5: exaggerated and cartoon-physical. ]]
StealConfig.Whiff = {
	Ragdoll = true,

	--[[ Fraction of the flight's velocity the body keeps when it goes limp. Was 0.75, to stop a body
		arriving at 80 studs/s from skipping down the road like a stone — but `Flight.Float` now sets
		you down at about 20 and `Flight.Glide` has already taken the along speed to traffic pace, so
		there is nothing left to take off. 1 is the physical answer at these speeds; if the splat
		starts to read as limp, the fix is the arc, not a number above 1 here. ]]
	VelocityKeep = 1,
	-- Random tumble, radians/s on each axis, so no two splats land the same way.
	Spin = 9,

	-- Joint limits, degrees. Loose enough to look boneless, tight enough that limbs don't invert
	-- through the torso — which is the difference between funny and unpleasant.
	JointAngle = 50,
	TwistAngle = 40,
}

-- === What a tier is worth ===================================================
--[[ The payoff. Landing on a Tier 5 has to make you measurably faster and tougher, or the whole
	mechanic is a lateral move with extra steps.

	THE NUMBERS ARE NOT HERE ANY MORE — THEY ARE IN `CarConfig`, one row per car. This table is a
	lookup BY GLOBAL TIER over those rows, kept because a steal arrives over the wire as a tier and
	three callers (StealService, GetawayService, StealController) hold a number rather than a name.

	Why it moved. This used to be five `SpeedScale`/`MaxHealth` bands resampled onto each world's
	rungs, and `SpeedScale` was a MULTIPLIER on whatever `MaxSpeed` the rig happened to be authored
	with in the place file. Since all 49 rigs carried an identical 40, that scalar was the only
	thing distinguishing a supercar from a beater — every car in the game drove the same and
	differed by a ratio. `CarConfig` makes each car's speed an absolute number you can read, and
	adds the handling that a scalar could never express, so the scalar has nothing left to do.

	  • `MaxSpeed` is now ABSOLUTE, in the same mph-ish unit the chassis converts (CarConfig's
	    header). Anything that wants "how fast is a Tier 7" reads it straight; nothing multiplies.
	  • `MaxHealth` is unchanged in meaning: re-stamped server-side on the steal (StealService →
	    ObstacleService) and HP refilled to it, so a steal is still the only heal in the game.
	  • `Body` rides along because a tier is exactly one car now, and the callers that log a steal
	    would otherwise have to go back to `WorldConfig` for its name.

	THE CURVE RESTARTING PER WORLD IS UNCHANGED and is now visible rather than derived: world 2's
	beater is as slow as world 1's, because the ladder you are climbing is your own world's
	(`WorldConfig` note 4). So this table is NOT monotonic across its 29 keys and nothing may read
	it as an ordering — a global tier is a NAME for a car, which is why the garage can price one
	from any world. To change that, change the rows in `CarConfig`; there is no longer a curve in
	the way. ]]
StealConfig.TierStats = {}
do
	--[[ A RUNG CAN BE WORN BY MORE THAN ONE CAR NOW (`WorldConfig` note 8), so `TierOfBody` is no
		longer one body per tier and `pairs` order would otherwise decide which of them a tier
		reported. A VARIANT NEVER OVERWRITES ITS RUNG'S LADDER CAR.

		The two stats are the same either way — a variant carries an exact copy of its rung's
		`CarConfig` row, by construction — so this is not protecting a number. It is protecting
		`Body`, which is a NAME, and a name gets logged: a tier that reports "Charger" in one session
		and "GNX" in the next is a puzzle nobody reading the output can solve. The ladder car is the
		one the rung is named after, so it is the one that answers.

		Order-independent on purpose: whichever arrives first, the primary is what is left. ]]
	for body, tier in WorldConfig.TierOfBody do
		if not (StealConfig.TierStats[tier] and WorldConfig.VariantOfBody[body]) then
			StealConfig.TierStats[tier] = {
				MaxSpeed = CarConfig.maxSpeedOf(body),
				MaxHealth = CarConfig.maxHealthOf(body),
				Body = body,
			}
		end
	end
end

-- === Reading the air ========================================================
--[[ Two dashed ground circles: a quiet shadow directly below the avatar and a brighter ring at
	the arc's exact predicted touchdown. THE RING IS DRAWN AT THE WIDTH E ACTUALLY REACHES
	(`Marker.MatchReach`), so the ring goes green and the target car is outlined when the solve puts a
	car IN REACH, not only when it puts one underfoot.

	NONE OF THIS IS AUTO-AIM. The reticle, colour and highlight only report the scripted integrator;
	they never alter the flight or choose a different car.

	It costs almost nothing here and is unusually exact, for two reasons that are both properties of
	this codebase rather than luck: `RoadController._deckY` is a single number for a whole race (every
	tile is a clone of one template, and recycling and rebasing only ever translate ALONG the road),
	so the circle needs no raycast; and the arc is scripted, so the touchdown point is solved rather
	than simulated.

	When the candidate markers and the `E · Steal` billboard land (plan §4, S31/S32) this moves into
	its own `StealUIController`. One circle doesn't justify a controller yet. ]]
StealConfig.Marker = {
	Enabled = true,

	--[[ DRAW THE RING AS WIDE AS THE STEAL ACTUALLY REACHES: `Prompt.Range` plus `Landing.Pad`,
		doubled, both taken after the player's own forgiveness multiplier. About 44 studs stock, and
		it grows with the jump upgrade and with the tutorial's wider reach (`TutorialConfig.Rig`).

		OFF, AND IT IS A DELIBERATE STEP BACK FROM AN ACCURATE PICTURE. It went on for a day
		(2026-09-18) after a playtester took a car sitting off to one side and reported that their
		circle was "not anywhere near it", which is true of a 16-stud circle drawn in the middle of a
		44-stud reach. The ring it produced was honest — if it touched a car, E took that car — and
		it was too much graphic: 44 studs is three lanes of road painted over at the moment the
		player is trying to read one roof, and the honest ring needed a second, quieter circle under
		the avatar to say where they actually were. Dylan's call the same day was that the complaint
		was really about SIZE, and the answer is one circle, under you, a little bigger, rather than
		two circles and a rule to learn.

		On puts the derived ring back, and `Lead` below wants to go back to 1 with it, since a ring
		that wide is only worth drawing where the landing really is. That pair is the A/B. ]]
	MatchReach = false,

	--[[ Studs across, and with `MatchReach` off this is the whole answer.

		22 RATHER THAN THE 16 THIS SHIPPED AT. Half the true reach instead of a bit over a third, so
		a car the arc can still take is nearer to being under the circle, while the circle stays a
		reticle you carry: at 16 it was a dot on a roof, and much past this it stops being a thing
		you steer and starts being a thing the road is wearing. It is not a promise about what E can
		reach — `TargetHighlight` below is what makes that promise, by naming the car outright. ]]
	Diameter = 22,

	-- Studs above the deck, so it doesn't z-fight the road surface.
	Lift = 0.15,

	--[[ How faint the reticle is drawn. It went UP from 0.45 when the marker stopped being a filled
		disc (`UIAssets.Steal.Marker`, 2026-08-25): a solid circle of colour had to be knocked back
		or it hid the roof you were steering onto, and an outline does not, so it can afford to be
		read. ]]
	Transparency = 0.2,

	--[[ WHERE THE CIRCLE IS DRAWN, 0..1: 0 is directly under the avatar, 1 is the exact touchdown.

		THERE IS ONLY THE ONE CIRCLE AGAIN. While `MatchReach` was on this sat at 1, out on the
		solved landing, and a second quieter circle was drawn under the avatar to say where the
		player was — two circles, two questions, and a pairing nobody asked for. The reach ring went
		back off on 2026-09-18 and the twin went with it.

		0 is the default and it's a legibility call, not a simplification. A circle 90 studs down the
		road is a dot near the horizon: you cannot tell which lane it's in, you cannot tell it apart
		from the road markings, and nothing about your body language on screen connects you to it.
		Under you it's a reticle — you carry it, you steer it over a roof, it goes green. `Flight.
		Glide` is what makes that honest rather than a lie of convenience: braking to near traffic
		pace collapses the gap between "under me" and "where I land" to ~15 studs in the frame of the
		car you're aiming at — half a padded hit volume — so the circle and the solve are near enough
		the same answer. Turn the glide off and turn this up together, or not at all.

		Values in between drag the circle out ahead of you by that fraction, which is a real look.
		Note it CANNOT be tuned to cancel the residual lead exactly, because that lead depends on how
		fast the target is: ~0.3 cancels it on a Tier 1, ~0 on a Tier 5. Anything non-zero is
		therefore a compromise across the tiers, which is the other half of why 0 won. ]]
	Lead = 0,

	--[[ Outline the car the prediction currently names. This is presentation only; it neither locks
		the trajectory nor changes the candidate selected by the normal landing/prompt rules.

		IT IS WHAT CARRIES THE REACH NOW that the circle has stopped trying to. It asks exactly what
		`_findCandidate` asks, so a car off to one side that E will still take is lit before the
		player presses anything, which is the half of the playtester's complaint that was about
		information rather than about size. ]]
	--- 2026-10-20: WAS 0.9 / 0.12 ("make the indicator more visible"): a real green wash on the car
	--- and a solid outline, so the car E will take reads from the corner of the eye.
	TargetHighlight = {
		Enabled = true,
		FillTransparency = 0.6,
		OutlineTransparency = 0,
	},

	Neutral = Color3.fromRGB(236, 240, 246), -- over tarmac, nothing under you
	Miss = Color3.fromRGB(240, 78, 68), -- over tarmac, and you're committed
	--[[ Snapped onto a car: you've got it. It rhymes with `Prompt`'s pill going green in the same
		moment — the circle and the prompt are one piece of news — but it is NOT the pill's own
		`#1F9906`, and that is a legibility call rather than a slip. The pill is a lit button read
		at arm's length; this is a wide outline laid flat on asphalt and read at a glancing angle
		from 40 studs up. The artist's green goes to mud down there. ]]
	Hit = Color3.fromRGB(84, 220, 130),

	--[[ Degrees per second the reticle turns, or 0 to nail it down. Slow — a full turn takes most
		of a minute and a whole flight is about 45 degrees of it — because the job is to say the
		sight is live, not to spin. It is driven off flight `dt`, so it obeys the time scale with
		everything else in this file.

		It also makes the reticle's alignment a non-question: the four ticks would otherwise sit on
		the world axes rather than the road's, which is the same thing only while the road happens
		to run down one. ]]
	Spin = 22,

	--[[ Thickness of the part the reticle is drawn on. It is a MOUNT, not the marker: the part
		itself is invisible and a `SurfaceGui` on its top face does the drawing, which is what buys
		`LightInfluence = 0` — the unlit, always-full-brightness read the old `Neon` cylinder had for
		free. Thin, so `Lift` means what it says. ]]
	Thickness = 0.05,

	-- Fraction of the flight after which a tarmac prediction turns from neutral to red. Early on
	-- you can still steer out of it, so shouting about it is noise.
	CommitAt = 0.45,
}

-- Load-time invariants for the deterministic parts of the mechanic. These fail beside the config
-- edit that caused them rather than surfacing later as a jump that changes with nitro or cannot
-- reach the road before its fail-safe.
do
	local launchWindow = StealConfig.Launch.SpeedWindow
	assert(launchWindow.MinCruiseFraction > 0, "jump launch minimum must remain forward")
	assert(
		launchWindow.MinCruiseFraction <= 1 and launchWindow.MaxCruiseFraction >= 1,
		"jump launch window must contain ordinary cruise"
	)
	assert(launchWindow.MaxCruiseFraction <= 1.2, "temporary speed effects must not dominate jump reach")
	assert(launchWindow.ThrowScale >= 1 and launchWindow.ThrowScale <= 1.75, "jump throw must stay arcade-fast but bounded")
	assert(
		StealConfig.Flight.Glide.CruiseFraction > 0 and StealConfig.Flight.Glide.CruiseFraction <= 1,
		"jump glide must remain forward and no faster than cruise"
	)
	assert(
		StealConfig.Flight.SteerSpeed > 0 and StealConfig.Flight.SteerAccel > 0,
		"air steering must remain responsive"
	)
	assert(
		StealConfig.Flight.Reach <= StealConfig.Flight.HalfWidth,
		"air reach cannot exceed the road corridor"
	)
	assert(
		StealConfig.Prompt.InputBuffer >= 0 and StealConfig.Prompt.InputBuffer <= 0.35,
		"steal input buffer must stay short"
	)
	--- `Lead` is a taste dial again rather than a rule. It was pinned at 1 while `Marker.MatchReach`
	--- drew the full reach, because a ring that wide has to be sitting on the real landing to be
	--- worth drawing; with the reach ring off, a circle under the avatar is the shipped look.
	assert(
		StealConfig.Marker.Lead >= 0 and StealConfig.Marker.Lead <= 1,
		"the jump reticle is drawn somewhere between the avatar and the touchdown"
	)
end

-- === Slow motion ============================================================
--[[ OFF for this pass, on purpose. Get the transfer feeling right first, then dip time.

	Roblox has no global time dilation, so this is one client-side number every scripted per-frame
	system multiplies its dt by (see Modules/TimeScale, which publishes it). At 1.0 every one of
	those systems is bit-for-bit what it is today, which is also how you A/B the effect.

	Per `effect-intensity-taste`: keep it SHORT and let it vary. A flat dramatic wash on every jump
	is the failure mode — the plan's suggestion is to scale the depth with the tier being chased, so
	a Tier 1 grab barely dips and a Tier 5 at full stretch gets the full treatment. `Scale` below is
	the flat version; build that first, then make it a function of the target. ]]
--[[ TRIED ON 2026-10-20 at 0.7 for "the jump feels too fast", and turned back off the same day: slowing
	the whole world read as the game slowing down, not as the player gliding ("I want it to still be a
	smooth jump, I just want the player to glide at the top a little more"). The glide is
	`Flight.Hang` now. ]]
StealConfig.SlowMo = {
	Enabled = false,
	Scale = 0.4,
	-- Seconds of REAL time the scale eases over. A hard cut in either direction reads as a hitch.
	EaseIn = 0.15,
	EaseOut = 0.12,
}

-- === The thumb button's pulse ===============================================
--[[ `DrivingHud.Controls.Jump` breathes while it is offering STEAL (2026-10-06, Leaf on a phone:
	"button is too small and not obvious"). The face swap alone happens in the corner of the eye
	while the player is watching the car below them, and a swap is one frame of news. A slow swell
	keeps saying it for as long as the steal is on.

	Restrained on purpose: a few percent of size, about one and a half beats a second, eased in and
	out of. Driven by `DrivingHudController._pulseAction` through a `UIScale` on the button, and the
	button is anchored at its centre, so it grows in place. Off = the button never scales. ]]
StealConfig.ThumbPulse = {
	Enabled = true,
	--- Peak scale over the button's authored size.
	Scale = 1.1,
	--- Swells per second.
	Rate = 1.5,
}

return StealConfig
