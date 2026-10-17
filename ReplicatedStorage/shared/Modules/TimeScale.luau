--[[
	TimeScale  (shared, client-side in practice)
	--------------------------------------------
	Slow motion — and, since the tutorial, a full stop — as one number.

	Roblox has no global time dilation. `workspace.Gravity` is not a time scale, and neither is
	`AnimationTrack:AdjustSpeed` — they're two separate knobs that happen to look like one when the
	only thing on screen is a falling body. So slow-mo in this game means exactly this: EVERY
	SCRIPTED PER-FRAME SYSTEM MULTIPLIES ITS `dt` BY THIS NUMBER, and asks for it once per frame
	rather than being pushed at. One reader per system, no ordering problem, no event storm.

	At 1.0 — which is what it is whenever no flight and no hold is in progress — every consumer is
	bit-for-bit what it was before this module existed. That's the point: it's also how you A/B the
	effect.

	WHY THIS IS A MODULE AND NOT `StealController:getTimeScale()`. The plan named the controller,
	and functionally it's the same thing — but TrafficController and RaceCameraController both have
	to read it, and StealController has to depend on BOTH of them (it drives the flight camera and
	freezes the steal target). Routing the number through a leaf module nobody depends on breaks
	that cycle instead of teaching Shard to tolerate it.

	=== TWO WRITERS, TWO LAYERS, AND THEY DO NOT SHARE A NUMBER ================================

	There used to be one writer. There are now two, and they want opposite things at the same
	moment — the tutorial pauses the world mid-flight, which is precisely when the steal's slow-mo
	ramp is mid-ramp — so they are stacked rather than merged:

	    SCALE   the ramp. `set` / `reset`, StealController's, 0.05..1, a continuous dial.
	    HOLD    the stop. `hold` / `release`, TutorialController's, all-or-nothing, and it WINS.

	`get()` returns 0 while anything holds and the ramp's value otherwise. So a hold freezes every
	scripted system in the game at once and a release puts them back exactly where they were —
	including a ramp that was halfway down when the hold landed, which is why the hold does not
	simply write `scale = 0` and put a 1 back afterwards.

	It follows that ANYTHING RAMPING THE SCALE MUST READ `getRaw`, not `get`. A ramp that reads its
	own current value through the hold reads 0, steps from there, and comes out of the pause at the
	floor with the whole ramp to do again. `getRaw` is that value; nothing else should want it.

	THE HOLD IS REFCOUNTED BY NAME. Two systems can want the world stopped for overlapping reasons
	— the tutorial holds for a beat, a beat spans a steal, the steal's own teardown releases — and
	an unbalanced pair must not strand the world at zero. Holding twice under the same name is one
	hold, so a caller that cannot tell whether it already holds may simply hold again.

	WHAT CANNOT OBEY IT, and what to do instead:

	  • PHYSICS. The solver runs at 240Hz on real time and there is no lever. So nothing
	    physics-simulated may be VISIBLE during a slowed flight: the player's car is anchored for
	    the duration, and any traffic that's been knocked to physics (`TrafficController._knock`)
	    is already tumbling to a stop behind you. If a future effect wants simulated debris mid-air,
	    it has to be faked with scripted motion or culled.

	    A HOLD IS THE CASE WHERE THAT MATTERS MOST, because a hold is not brief: the tutorial can sit
	    at zero for as long as it takes somebody to find the W key. So `RaceFreezeController` — the
	    only thing that should ever call `hold` — anchors the player's car and every physical traffic
	    shell for the length of it. This module stops the SCRIPTS; that controller stops the SOLVER.
	    Neither is a whole pause on its own.
	  • TweenService. Real-time, always, with no scale input. So: no tweens during slow-mo, or
	    pre-divide their durations by the scale at the moment they're created. A UI tween across a
	    hold is fine and wanted — the card, the arrow and the dim all animate while the world does
	    not, which is the whole read of "the game is waiting on you".
	  • `task.wait` / `task.delay`. Real-time. Every beat inside a flight is driven off accumulated
	    SCALED time (see StealController's `_flight.t`), never off a delay.

	  • Animations DO obey, via `AnimationTrack:AdjustSpeed(scale)` — the one engine-side lever that
	    genuinely works. Author clips at 1x and let this scale them (plan §8). At 0 they hold their
	    pose, which is exactly what a paused mid-air steal should look like.
	  • Audio obeys via `Sound.PlaybackSpeed`, and the pitch-down is half the effect.
]]

local TimeScale = {}

local scale = 1

--- Who currently wants the world stopped, by name, and how many of them there are. Names rather
--- than a plain count so an unbalanced release can only ever undo its own hold.
local holds: { [string]: true } = {}
local holdCount = 0

--- The number. Ask once per frame, multiply your dt by it, and carry on.
function TimeScale.get(): number
	return if holdCount > 0 then 0 else scale
end

--- The RAMP's value, ignoring any hold. Only something that is easing the scale should read this —
--- see the header — and reading it to decide whether the world is moving is a bug: use `get`.
function TimeScale.getRaw(): number
	return scale
end

--- Is anything holding the world at a stop right now?
function TimeScale.isHeld(): boolean
	return holdCount > 0
end

--[[ Set the ramp. StealController owns this; nothing else should call it.

	Clamped rather than trusted: a negative scale would REVERSE every consumer's integration at once,
	and a scale above 1 is a fast-forward nobody asked for. The floor is low enough for anything
	dramatic and high enough that a bug can't stop the world — a genuine stop is what `hold` is for,
	and it is a separate layer precisely so that "slow" and "stopped" cannot be confused for each
	other by whoever is reading the number back. ]]
function TimeScale.set(value: number)
	if type(value) ~= "number" or value ~= value then
		return -- NaN fails every comparison, so it's checked before the clamp rather than by it
	end
	scale = math.clamp(value, 0.05, 1)
end

--[[ Stop the world under `reason`, and keep it stopped until that same reason releases.

	Idempotent per name, so a caller that cannot cheaply tell whether it already holds may hold
	again. Returns whether this was the hold that actually stopped things, which is the one bit a
	caller needs to decide whether it also has to anchor anything. ]]
function TimeScale.hold(reason: string): boolean
	if type(reason) ~= "string" or holds[reason] then
		return false
	end
	holds[reason] = true
	holdCount += 1
	return holdCount == 1
end

--- Drop `reason`'s hold. Returns whether that was the last one, i.e. whether the world just started
--- moving again. Releasing a reason that never held is a no-op rather than an error: teardown paths
--- run in orders nobody enumerated, and a release is always the safe direction.
function TimeScale.release(reason: string): boolean
	if type(reason) ~= "string" or not holds[reason] then
		return false
	end
	holds[reason] = nil
	holdCount -= 1
	return holdCount == 0
end

--[[ Back to real time, ramp and holds alike. Called on every teardown path, so a race that ends
	mid-flight — or mid-tutorial-beat — can never leave the world running slow or stopped for the
	rest of the session.

	IT CLEARS THE HOLDS TOO, and that is the point of putting it on the teardown paths: a beat whose
	release lives in a handler that a race teardown just disconnected would otherwise stop the world
	forever, and "forever" here means until the player rejoins. A hold is a strong enough thing to
	be worth an unconditional way out. ]]
function TimeScale.reset()
	scale = 1
	holds = {}
	holdCount = 0
end

return TimeScale
