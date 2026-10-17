--[[
	RaceFreezeController  (client)
	------------------------------
	Stop the run. Really stop it — not slow it, not stop the parts of it that were easy.

	The onboarding is what needed this. Its beats hold a brand-new player at a standstill until they
	find the key the card is naming, and "held" has to mean the whole road: a pause that stopped the
	traffic but let the player's car coast, or stopped the cars but let the getaway truck arrive, is
	not a pause — it is a bug with a caption on it.

	=== A PAUSE IS TWO HALVES AND NEITHER IS THE WHOLE THING ===================================

	    THE SCRIPTS   `Modules/TimeScale`, one number, held at 0. Traffic, obstacles, the race
	                  camera, the getaway truck and the steal's own flight are all driven off
	                  `dt * TimeScale.get()`, so one hold stops all five with no wiring at all.
	    THE SOLVER    which has no such number. The player's car is a physics assembly running at
	                  240Hz on real time, and so is any traffic shell that has been knocked loose
	                  (`TrafficController._knock`). Those are ANCHORED for the length of the hold.

	This controller is the seam between them, and its whole job is that both halves go on and come
	off together and in the right order. Everything it calls already existed:

	    TimeScale.hold / release          the scripted world
	    DriveController:setFrozen         the player's car — anchor, suspend, restore
	    TrafficController:setFrozen       knocked shells, and the spawn cadence

	WHY IT IS A CONTROLLER AND `TimeScale` IS A MODULE. TimeScale is read by four controllers, so
	it has to be a leaf nobody depends on (its own header argues this). This is the opposite: it
	DEPENDS on two controllers, and it is the only thing in the game that does the whole pause. A
	caller wanting the world stopped should reach one name, not three in a particular order.

	=== IT IS REFCOUNTED BY NAME, AND THE NAMES ARE NOT DECORATION =============================

	`hold("TutorialBeat")` twice is one hold; `release("TutorialBeat")` once ends it. Two different
	reasons overlap correctly. The alternative — a boolean — breaks the first time two beats abut,
	which in this feature is most of them: the beat that pauses a steal mid-air is released by the
	steal completing, and the beat AFTER it wants the world held while the card changes.

	A name also survives a caller that cannot cheaply tell whether it already holds, which is every
	per-frame arm/disarm check in the director.

	=== AND A RACE ENDING RELEASES EVERYTHING =================================================

	Unconditionally, on `RaceEnd` and on a wreck's teardown. A hold is the strongest thing a client
	can do to its own game — it can stop the world until the player rejoins — so the one rule that
	matters more than balance is that it cannot outlive the thing it was holding. Every owner is
	written to tolerate having its hold pulled out from under it; none of them is trusted to be
	alive at the moment that matters.

	HOUSE RULE: no wiki-style double-bracket links in these comments — the closing pair ends the
	block comment early and the parse error points at the wrong line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local TimeScale = require(ReplicatedStorage.shared.Modules.TimeScale)

local RaceFreezeController = Shard.new("RaceFreezeController"):withDependencies({
	"DriveController",
	"TrafficController",
})

--[[ One name for every hold this controller places on the time scale, because from TimeScale's side
	this controller IS one holder however many reasons it is counting on its own. Stacking the
	caller's names through to TimeScale as well would give two refcounts that have to agree, and the
	one thing worse than a world that will not stop is a world that will not start. ]]
local HOLD_KEY = "RaceFreeze"

-- === Holding ================================================================

--[[ PUBLIC — stop the world under `reason` until that same reason releases it.

	Returns whether this was the hold that actually stopped things, which is the bit a caller needs
	if it also has something of its own to freeze. Holding under a name that is already held is a
	no-op rather than an error, so a per-frame check may simply hold every frame. ]]
function RaceFreezeController.hold(self, reason: string): boolean
	if type(reason) ~= "string" or reason == "" then
		self.log:warn("A freeze needs a reason to hold under; refusing an unnamed hold.")
		return false
	end
	if self._holds[reason] then
		return false
	end
	self._holds[reason] = true
	self._count += 1
	if self._count > 1 then
		return false
	end
	self:_apply(true)
	return true
end

--- PUBLIC — drop `reason`'s hold. Returns whether that was the last one, i.e. whether the world
--- just started moving again. Releasing a reason that never held is a no-op: teardown paths run in
--- orders nobody enumerated, and a release is always the safe direction.
function RaceFreezeController.release(self, reason: string): boolean
	if type(reason) ~= "string" or not self._holds[reason] then
		return false
	end
	self._holds[reason] = nil
	self._count -= 1
	if self._count > 0 then
		return false
	end
	self:_apply(false)
	return true
end

--- PUBLIC — is the world stopped right now?
function RaceFreezeController.isHeld(self): boolean
	return self._count > 0
end

--- PUBLIC — is this particular reason holding?
function RaceFreezeController.holds(self, reason: string): boolean
	return self._holds[reason] == true
end

--[[ PUBLIC — drop every hold, whoever placed it. The way out that does not depend on an owner
	still being alive, and the only one a race teardown may use: see the header.

	Deliberately not a loop over `release`, which would apply the unfreeze on the last name and do
	nothing on the others; this is one state change however many reasons were standing. ]]
function RaceFreezeController.releaseAll(self)
	if self._count == 0 then
		return
	end
	table.clear(self._holds)
	self._count = 0
	self:_apply(false)
end

-- === The two halves =========================================================

--[[ On and off. Ordered rather than incidental in both directions, and the order is the reverse of
	itself — which is what keeps a frame from existing in which one half is on and the other is not.

	FREEZING, the solver stops FIRST. `TimeScale` is read at the top of every scripted loop, so the
	frame a hold lands on is one where traffic has already been told to hold still; if the player's
	car were still live for that frame it would be driving into a road that had stopped without it.

	THAWING, the scripts start LAST. `DriveController:setFrozen(false)` restores the car's velocity,
	and a car handed back its 50 studs/s into a world whose traffic has already had a frame to move
	is a car that arrives a frame late rather than a frame early — the harmless direction. ]]
function RaceFreezeController._apply(self, frozen: boolean)
	local drive = Shard.get("DriveController")
	local traffic = Shard.get("TrafficController")

	if frozen then
		if drive then
			drive:setFrozen(true)
		end
		if traffic then
			traffic:setFrozen(true)
		end
		TimeScale.hold(HOLD_KEY)
		self._changed:Fire(true)
		return
	end

	TimeScale.release(HOLD_KEY)
	if traffic then
		traffic:setFrozen(false)
	end
	if drive then
		drive:setFrozen(false)
	end
	self._changed:Fire(false)
end

-- === Wiring =================================================================

RaceFreezeController:withSignals({
	--- Fired with `true` the moment the world stops and `false` the moment it starts again. For
	--- anything that has its own thing to hold — a sound, a HUD readout, a loop of its own.
	"FreezeChanged",
})

RaceFreezeController:withRemoteEvents({
	{
		--[[ Every way home. A hold must not outlive the race it was holding, and none of these is a
			place where an owner is guaranteed to still be listening — a wreck disconnects most of the
			run's handlers before the results screen is up. ]]
		RaceEnd = function()
			RaceFreezeController:releaseAll()
		end,
		RaceEntering = function()
			RaceFreezeController:releaseAll()
		end,
	},
})

RaceFreezeController:withLifecycle({
	init = function(self)
		self._holds = {}
		self._count = 0
		self._changed = self:getSignal("FreezeChanged")
	end,
})

return RaceFreezeController
