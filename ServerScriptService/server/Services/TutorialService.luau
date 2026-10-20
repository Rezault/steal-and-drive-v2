--[[
	TutorialService  (server)
	-------------------------
	The onboarding's server half: which beat each player is on, when it is done, and the funnel.

	=== IT OWNS THE SEQUENCE AND NOTHING ELSE =================================================

	Eight beats, in order, one at a time, stored on the profile and mirrored onto the Player. What
	finishes each one comes from somewhere else entirely — see `TutorialConfig`'s note 2 — and this
	file's whole job is to be the single place that decides "that was the beat you were on".

	Two kinds of thing can finish a beat:

	    Signal   a signal some service already fires for its own reasons. Four of the eight:
	                 play      RaceService.RaceEntered
	                 airborne  StealService.CarStolen
	                 bank      RewardService.RunSettled        -- filtered on `banked`
	                 collect   GarageService.CashCollected
	             The wiring is DERIVED from the beat list (`_bind`), so a beat naming a signal that
	             does not exist warns at boot with its own id in the message, rather than being a
	             hole a player discovers.

	    Input    something only the client can witness — a key held, two lanes changed, eight
	             seconds survived. The client reports it over `TutorialBeat` and this file checks
	             that the beat named IS the one that is live before it counts.

	=== WHY A CLIENT IS NOW ALLOWED TO SAY "I DID IT", HAVING NEVER BEEN =======================

	The old five-step version had an absolute rule: no client message anywhere may advance a step.
	It could afford that rule because every one of its steps was a thing the server could see.

	Half of the new ones are not. "Held W", "changed lane twice", "survived eight seconds" happen
	entirely inside a client that owns its own road (driving is solo — see `TrafficController`), and
	the alternatives are both worse than trusting the report: invent a per-player server counter for
	inputs the server does not receive, or delete the beats that teach the controls.

	SO THE RULE MOVED RATHER THAN BROKE. What a client may say is "the beat you told me to run is
	finished", never "put me on beat six" — `_onBeat` takes an id, compares it to the live one and
	refuses anything else. A forged report therefore skips exactly one beat that the player could
	have skipped anyway by pressing SKIP, which is one button and takes the whole feature away. It
	buys nothing, and it cannot desynchronise the sequence.

	The four signal beats are untouched by any of this, and they are deliberately the four that
	MATTER — entered a race, stole a car, banked it, collected the cash. The loop cannot be claimed;
	only the lessons can.

	=== THE FUNNEL ============================================================================

	Every beat carries a `Funnel` number and every completion is reported to
	`AnalyticsService:LogOnboardingFunnelStepEvent`, which is Roblox's own first-class onboarding
	funnel and shows up in the creator dashboard without anything being built. The board card asks
	for this in as many words ("track every single step with funnels ofc").

	Reported on ARRIVAL at a beat rather than on finishing it, which is the convention that funnel
	is built around: stage N's count is "how many players reached stage N", so the drop-off between
	N and N+1 is the number who saw beat N and never finished it. Reporting on completion would
	shift every bar by one and make the last beat unreadable.

	It is fired through `pcall` and its failure is ignored. Analytics is not allowed to be the
	reason a tutorial stops working, and in Studio the endpoint is frequently not there at all.

	=== THE STEP IS A STRING, AND IT IS ON THE PLAYER =========================================

	`TutorialConfig.StepAttribute` carries the live beat id, empty when there is nothing to do. That
	is deliberately the broadest publish this file makes: it is how `GetawayController` knows to put
	a first-timer's truck out early, and how `TutorialDirector` knows to stage the road, without
	either of them knowing this service exists.

	The screen gets a richer payload over `TutorialState` — the index, the total, the bay to point
	at, and which beat was just finished so the card can stamp DONE over it. Both are published from
	one place (`_publish`) so they cannot disagree.

	=== WHY THE CLIENT PINGS ==================================================================

	The profile lands on the join path, comfortably before the client's controllers have finished
	starting, so a state fired the moment it is known is a state nobody hears. The first payload is
	therefore PARKED and sent when the card says it exists — the identical resolution
	`OfflineService` uses, and for the identical reason. Everything after that is sent live.

	HOUSE RULE: no wiki-style double-bracket links in these comments — the closing pair ends the
	block comment early and the parse error points at the wrong line.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)

local Data = require(script.Parent.Parent.Data)

--[[ What the card is sent. One payload rather than five arguments, the same call
	`OfflineService`'s offer and `ReviveService`'s make, and for the same reason: every field is
	drawn by one screen at one moment, and a positional list is one nobody can add a sixth to. ]]
type State = {
	step: string, -- the live beat's id, or "" for nothing to do
	index: number, -- 1-based position in `TutorialConfig.Steps`, 0 when there is no beat
	total: number, -- how many beats there are, so the card can say "2/9"
	bay: number?, -- the bay to point at, for the collect mat
	completed: string?, -- the beat that was just finished, so the card can stamp DONE
	finished: boolean?, -- ...and whether that was the last one
}

local TutorialService = Shard.new("TutorialService"):withDependencies({ "GarageService" })

TutorialService:withRemoteEvents({
	-- server -> client: this is your objective. Sent on resume and after every advance.
	"TutorialState",
	{
		--[[ client -> server: my card exists, so a state sent now will be heard. Carries nothing —
			the player is the whole message. See the header on why either order has to work. ]]
		TutorialReady = function(player: Player)
			TutorialService:_onReady(player)
		end,
		--[[ client -> server: the input beat you put me on is finished. The id is checked against
			the live beat and anything else is dropped — see the header on why this is allowed to
			exist at all. ]]
		TutorialBeat = function(player: Player, stepId: unknown)
			TutorialService:_onBeat(player, stepId)
		end,
		-- client -> server: they pressed SKIP.
		TutorialSkip = function(player: Player)
			TutorialService:_onSkip(player)
		end,
		--[[ client -> server (stepId): the card for this beat is on screen with nothing over it. Only
			for a beat marked `Watched`; the SELL beat's buyer waits for it (`watchingSince`). A forged
			one only brings a player's own buyer a few seconds early. ]]
		TutorialWatching = function(player: Player, stepId: unknown)
			TutorialService:_onWatching(player, stepId)
		end,
	},
})

-- === The profile ============================================================

--[[ NON-YIELDING, like `GarageService._profile`, `OfflineService._profile` and
	`ReviveService._profile`, and for the same reason: this is reached from remote handlers and from
	other services' signal callbacks, none of which may stall for the seconds `GetProfileAsync` can
	take. The handle is cached off the join path; until it lands every read answers "not yet", which
	every caller here handles. ]]
function TutorialService._profile(self, player: Player)
	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

--[[ The stored record, always as a whole table with both fields present.

	Read defensively because this key changes shape more than any other in the profile: a save
	written before it existed has no table at all, and one written by an older build has a step id
	this build has retired. Both are ordinary here and neither is a warning — see `_resume`. ]]
function TutorialService._record(self, player: Player): { Step: string, Done: boolean }
	local profile = self:_profile(player)
	local stored = profile and profile:Get(TutorialConfig.ProfileKey)
	if type(stored) ~= "table" then
		return { Step = "", Done = false }
	end
	return {
		Step = if type(stored.Step) == "string" then stored.Step else "",
		Done = stored.Done == true,
	}
end

function TutorialService._store(self, player: Player, step: string, done: boolean)
	local profile = self:_profile(player)
	if profile then
		profile:Set(TutorialConfig.ProfileKey, { Step = step, Done = done })
	end
end

-- === Where they are =========================================================

--[[ The live beat for a player, as an index into `TutorialConfig.Steps`, or nil for "no objective".

	Held in memory as well as on the profile because it is read on every one of the signals above —
	which fire many times a second between them for a lot of players — and a recursive profile
	search per steal is a cost with nothing to buy it. The profile is the record; this is the
	answer. ]]
function TutorialService._index(self, player: Player): number?
	return self._live[player]
end

--[[ Work out where a returning player stands, and stamp it.

	FIVE CASES now, and the two new ones are both about a beat list that has been rewritten under
	live profiles:

	  1. Done (finished or skipped) — no objective, ever again.
	  2. No record at all — a fresh player, or one whose profile predates this feature. Beat one.
	  3. A beat this build knows — resume exactly there.
	  4. A beat this build has RENAMED, which `TutorialConfig.Renamed` translates. That table is the
	     whole migration for the eight-beat rewrite: everybody mid-tutorial on the old five-step list
	     lands on the nearest new beat rather than being restarted or written off.
	  5. A beat this build has never heard of and cannot translate. Read as beat one rather than as
	     "done", because the two wrong answers are not equally wrong: repeating an objective costs a
	     player twenty seconds, and skipping the rest of the tutorial costs them the reason to come
	     back. Logged, since the only way it happens is somebody editing `Steps` without editing
	     `Renamed`. ]]
function TutorialService._resume(self, player: Player)
	local record = self:_record(player)
	if record.Done then
		self._live[player] = nil
		self:_publish(player)
		return
	end

	if record.Step == "" then
		self:_enter(player, 1)
		return
	end

	local index = TutorialConfig.indexOf(record.Step)
	--[[ Left mid-attempt (a rejoin from mid-air): resume on the beat that STARTS the attempt, for the
		reason `rewindAttempt` gives. `TutorialConfig.Unlosable`, 2026-10-05. ]]
	local back = TutorialConfig.Unlosable.Enabled and TutorialConfig.Rewind[record.Step]
	if back and TutorialConfig.indexOf(back) then
		index = TutorialConfig.indexOf(back)
	end

	if not index then
		local moved = TutorialConfig.Renamed[record.Step]
		if moved == TutorialConfig.RenamedDone then
			--- A beat that was the END of an older list. Somebody who reached it finished the
			--- tutorial that existed at the time, and re-running them through a longer one would be
			--- punishing them for having played early.
			self._live[player] = nil
			self:_store(player, record.Step, true)
			self:_publish(player)
			return
		end
		index = if moved then TutorialConfig.indexOf(moved) else nil
	end

	if not index then
		self.log:warn(
			string.format(
				"%s's profile is on tutorial beat '%s', which is neither in TutorialConfig.Steps nor in Renamed — starting them again from the top.",
				player.Name,
				record.Step
			)
		)
		index = 1
	end

	self:_enter(player, index)
end

--[[ Put a player ON a beat: remember it, store it, report the funnel stage, publish it.

	ONE DOOR IN, so that the funnel cannot be missed by a path that forgot to call it. Every way a
	player arrives at a beat — a fresh join, a resume, a migration, an advance — comes through here,
	which is also why `completed` and `finished` are parameters rather than a separate publish. ]]
function TutorialService._enter(self, player: Player, index: number, completed: string?)
	local step = TutorialConfig.stepAt(index)
	if not step then
		return
	end
	self._live[player] = index
	self._watchingAt[player] = nil
	self:_store(player, step.Id, false)
	self:_funnel(player, step)
	self:_publish(player, completed, false)
	--- A player who reaches PLACE already holding the car (a rejoin, a Replay) is parked for too.
	if TutorialConfig.AutoPark.Enabled and step.Id == TutorialConfig.AutoPark.Beat then
		task.delay(TutorialConfig.AutoPark.After, self._autoPark, self, player)
	end
end

--[[ Tell BOTH funnels that this player has REACHED this stage. See the header on why arrival
	rather than completion.

	TWO OF THEM, deliberately. Roblox's own onboarding funnel is free, needs no keys, and shows up in
	the Creator Dashboard where a Roblox-native reader looks for it — but it is eight numbered stages
	and nothing else. GameAnalytics gets the same arrival, plus a matching COMPLETE event from
	`_advance`, plus the skip, which is what makes a real per-beat drop-off chart. Neither is a
	fallback for the other; they answer to different audiences.

	ONCE PER SESSION PER STAGE. The endpoint tolerates repeats, but a player who rejoins mid-beat
	would otherwise re-report the stage they are resuming onto and inflate it against the stages
	after it — which is the one distortion that would make the drop-off chart lie in the direction
	somebody would act on.

	`pcall` because analytics may be off, unavailable in Studio, or rate-limited, and none of those
	is a reason for a tutorial to stop working. ]]
function TutorialService._funnel(self, player: Player, step)
	local stage = tonumber(step.Funnel)
	if not stage then
		return
	end
	local seen = self._funnelled[player]
	if not seen then
		seen = {}
		self._funnelled[player] = seen
	end
	if seen[stage] then
		return
	end
	seen[stage] = true

	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, stage, step.Id)
	end)

	local Analytics = Shard.get("AnalyticsService")
	if Analytics then
		Analytics:TutorialReached(player, stage, step.Id)
	end
end

-- === Advancing ==============================================================

--[[ One beat done. Writes the next one, or finishes.

	`completed` rides on the payload rather than being a second remote, so the card gets "you
	finished X, here is Y" as one message and can never draw the new objective before the beat that
	says the old one is over. ]]
function TutorialService._advance(self, player: Player)
	local index = self:_index(player)
	if not index then
		return
	end

	local done = TutorialConfig.stepAt(index)
	local doneId = if done then done.Id else nil

	--[[ The other half of the funnel: this beat is FINISHED, as opposed to merely reached. The gap
		between the two is the whole point of tracking it per beat — a step everybody reaches and
		nobody finishes is a step that is broken, and one event cannot tell you that. ]]
	local Analytics = Shard.get("AnalyticsService")
	if Analytics and done then
		Analytics:TutorialFinished(player, tonumber(done.Funnel) or index, done.Id)
	end

	if TutorialConfig.stepAt(index + 1) then
		self:_enter(player, index + 1, doneId)
		self.log:info(
			string.format(
				"%s finished tutorial beat '%s'; next is '%s'.",
				player.Name,
				doneId or "?",
				TutorialConfig.stepAt(index + 1).Id
			)
		)
		return
	end

	--[[ The last one. `Done` is written before the publish so that a player who leaves inside the
		finish card's four seconds is still finished — the screen is the celebration, not the
		record. ]]
	self._live[player] = nil
	self:_store(player, doneId or "", true)
	self:_publish(player, doneId, true)
	--- The stage after the last beat, which nothing else would report (`TutorialConfig.FinishFunnel`).
	local finish = TutorialConfig.FinishFunnel
	if finish and finish.Stage then
		self:_funnel(player, { Funnel = finish.Stage, Id = finish.Id })
	end
	if Analytics then
		Analytics:TutorialComplete(player)
	end
	self.log:info(string.format("%s finished the tutorial.", player.Name))
end

--[[ PLACE, done for them (`TutorialConfig.AutoPark`): the car in their hands goes on the lowest empty
	showroom bay, through `GarageService.placeCarried`, the same call a press at a podium makes, so the
	park, the `CarParked` this beat advances on and the FirstCar funnel all happen exactly as they do
	for a player who walked it there.

	DELAYED BY EVERY CALLER, never run inside `CarryChanged`. The bank fires that signal as it puts the
	car in the hands, and parking inside it would fire the empty-hands `CarryChanged` while later
	listeners were still to hear the full one, so they would hear the two in the wrong order and build
	a car in the hands after it had gone.

	AND NOT IN THE SAME FRAME EITHER, which `task.defer` was (`TutorialConfig.AutoPark.After`): Gamebeast
	stamps markers to the millisecond and cannot order two with the same stamp, so FirstCarCarried and
	FirstCarPlaced, and BANK done and PLACE done, would each read as nobody making it to the second.

	Nothing happens without an empty showroom bay; the car stays in the hands and the beat is taught
	the old way. ]]
function TutorialService._autoPark(self, player: Player)
	local step = self:_liveStep(player)
	if not (TutorialConfig.AutoPark.Enabled and step and step.Id == TutorialConfig.AutoPark.Beat) then
		return
	end
	local Garage = Shard.get("GarageService")
	if not (Garage and Garage:getCarriedCar(player)) then
		return
	end
	local free: number? = nil
	for _, bay in Garage:getBays(player) do
		if not Garage:isWorkshopBay(bay.index) and not Garage:getBayCar(player, bay.index)
			and (not free or bay.index < free) then
			free = bay.index
		end
	end
	if not free then
		self.log:info(string.format("%s has no empty showroom bay, so their car stays in their hands.", player.Name))
		return
	end
	local ok, reason = Garage:placeCarried(player, free)
	self.log:info(string.format("Parked %s's car on bay %d for them: %s.", player.Name, free, if ok then "done" else tostring(reason)))
end

--[[ The client says the card for `stepId` is up with nothing over it. Kept only for the live beat, and
	only for one marked `Watched`; cleared whenever the beat changes (`_enter`). ]]
function TutorialService._onWatching(self, player: Player, stepId: unknown)
	local step = self:_liveStep(player)
	if not (step and step.Watched and step.Id == stepId) then
		return
	end
	if not self._watchingAt[player] then
		self._watchingAt[player] = os.clock()
	end
end

--[[ PUBLIC (BuyerService) - since when, by `os.clock()`, this player's client has had the card for
	`stepId` on screen with nothing over it, or nil if it has not said so on this beat. ]]
function TutorialService.watchingSince(self, player: Player, stepId: string): number?
	local step = self:_liveStep(player)
	if not (step and step.Id == stepId) then
		return nil
	end
	return self._watchingAt[player]
end

--[[ PUBLIC (RaceService.wreckRace) — the attempt this beat is part of has failed; put the player
	back on the beat that starts it (`TutorialConfig.Rewind`: AIRBORNE -> BAIL). A beat with no rewind
	is left alone, so this is safe to call on every wreck. Through `_enter`, the one door in, so the
	card, the attribute and the staged road all follow; the funnel is not re-reported (`_funnel`). ]]
function TutorialService.rewindAttempt(self, player: Player)
	local step = self:_liveStep(player)
	local back = step and TutorialConfig.Rewind[step.Id]
	local index = back and TutorialConfig.indexOf(back)
	if not index then
		return
	end
	self:_enter(player, index)
	self.log:info(string.format("%s failed tutorial beat '%s'; back to '%s'.", player.Name, step.Id, back))
end

--[[ PUBLIC (AnalyticsService) — has this player finished the tutorial?

	One fact, no control, and read off the PROFILE rather than the live index: a player who finished
	in an earlier session has no live beat, and "no live beat" is also what a player looks like in
	the frames before their profile loads. Only the record can tell those apart. ]]
function TutorialService.isFinished(self, player: Player): boolean
	return self:_record(player).Done == true
end

--[[ PUBLIC (BuyerService) - the showroom bay this player's tutorial car was parked on, or nil. The
	tutorial's buyer is sent to the car on it, the one the player has just watched land. ]]
function TutorialService.pointedBay(self, player: Player): number?
	return self:_bay(player)
end

--[[ PUBLIC (BuyerService) - finish `stepId` for this player when there is nothing for them to do on it
	(the SELL beat with no car on a bay for sale). Only the live beat, so a late call cannot skip the
	one after it. Goes through `_advance`, so the funnel counts it like any other finish. ]]
function TutorialService.passBeat(self, player: Player, stepId: string, why: string?)
	local step = self:_liveStep(player)
	if not step or step.Id ~= stepId then
		return
	end
	self.log:info(string.format("%s passed tutorial beat '%s' with nothing to do on it (%s).", player.Name, stepId, why or "?"))
	self:_advance(player)
end

--[[ PUBLIC (AdminService) - put a player back on beat one, as though they had never seen it.

	It is the admin panel's Replay, and it exists so the onboarding can be played again without a
	fresh account: on a live server, on the save you already have, with no rejoin. The record is
	simply entered at beat one through `_enter`, the same door a first join uses, so the card, the
	attribute, the staged road and the rigged truck all follow exactly as they do for a new player.

	IN A STUDIO PLACE CARRYING THE BYPASS TICK there is no tutorial running to put anyone on, so this
	lifts the tick for the session first and boots. That is a Workspace attribute written from a
	server, so it replicates to every client (whose own halves come up off `TutorialConfig.whenOn`)
	and never reaches the place file. It is also server-wide by nature: everybody else in the
	playtest resumes onto their own beat too, which the answer says.

	THE FUNNEL IS NOT RE-REPORTED for stages this session already reported (`_funnel`), so replaying
	on a live server costs the dashboards nothing past what the first pass already counted.

	Answers `(ok, sentence)` for the panel to print. It does not end a run in progress; the caller
	does that, because it is a yield this file has no business owning. ]]
function TutorialService.restart(self, player: Player): (boolean, string)
	if not TutorialConfig.Enabled then
		return false, "TutorialConfig.Enabled is false, so there is no tutorial in this build"
	end

	local lifted = false
	if TutorialConfig.isBypassed() then
		Workspace:SetAttribute(TutorialConfig.BypassAttribute, false)
		lifted = true
	end
	--- Called directly rather than left to the attribute signal, which is deferred: the beat below has
	--- to find a booted service in THIS frame.
	if not self:_boot() then
		return false, "the tutorial could not boot (no GarageService)"
	end
	if not self:_profile(player) then
		return false, "their profile has not loaded yet"
	end

	--- A bay remembered from the first pass is not where the replay's car will park.
	self._parkedBay[player] = nil
	self:_enter(player, 1)

	self.log:info(string.format("%s's tutorial was restarted from the top.", player.Name))
	return true,
		string.format(
			"on beat 1 of %d (%s)%s",
			#TutorialConfig.Steps,
			TutorialConfig.Steps[1].Id,
			if lifted
				then string.format(
					". Workspace.%s was lifted for this session, so everyone here is back on their own beat",
					TutorialConfig.BypassAttribute
				)
				else ""
		)
end

--- The beat a player is on, or nil. Both `_onSignal` and `_onBeat` open with this, and both re-read
--- it rather than trusting anything held by their caller: one connection serves every player.
function TutorialService._liveStep(self, player: Player)
	if not (player and player.Parent) then
		return nil
	end
	local index = self:_index(player)
	return if index then TutorialConfig.stepAt(index) else nil
end

--[[ A signal fired. Advance this player if it was the one their current beat is waiting for.

	THE BEAT IS RE-READ HERE rather than trusted from the connection, because one connection serves
	every beat that names the same signal and every player on the server at once. What decides
	anything is "is THIS player's live beat waiting for THIS signal", which is exactly what this
	asks. ]]
function TutorialService._onSignal(self, player: Player, serviceName: string, signalName: string, ...)
	local step = self:_liveStep(player)
	if not step then
		return
	end

	local advance = step.Advance
	if advance.Kind ~= "Signal" or advance.Service ~= serviceName or advance.Signal ~= signalName then
		return
	end

	--[[ `Accept` is the per-signal filter — `RunSettled` fires for a wreck as well as a bank and
		only one of those is getting away with a car. A beat with no filter takes the signal as proof
		on its own. ]]
	if advance.Accept and not advance.Accept(...) then
		return
	end
	-- 2026-10-04: PLACE leads into earning from the showroom. The workshop accepts cars too,
	-- but completing PLACE there strands the next beat at a car that cannot earn customer tips.
	if serviceName == "GarageService" and signalName == "CarParked" then
		local Garage = Shard.get("GarageService")
		local bay = select(3, ...)
		if not Garage or Garage:isWorkshopBay(bay) then
			return
		end
	end

	self:_advance(player)
end

--[[ The client says the input beat it was given is finished.

	THE ID IS THE WHOLE CHECK, and it is enough: a report naming anything but the live beat is
	dropped, so this can only ever complete the beat the server had already chosen to serve. See the
	header for why that is a boundary rather than a hole.

	SIGNAL BEATS ARE REFUSED HERE outright, even when the id matches. Those four are the ones a
	server can see for itself, and letting a client close one would hand it "I stole a car" — which
	is a claim about the game rather than about a keypress. ]]
function TutorialService._onBeat(self, player: Player, stepId: unknown)
	if not TutorialConfig.isOn() or type(stepId) ~= "string" then
		return
	end
	local step = self:_liveStep(player)
	if not step or step.Id ~= stepId then
		return
	end
	if step.Advance.Kind == "Signal" then
		self.log:warn(
			string.format("%s reported tutorial beat '%s', which only the server may close.", player.Name, stepId)
		)
		return
	end
	self:_advance(player)
end

-- === Publishing =============================================================

--- Does this beat's pointer need to be told which bay? The collect mat is one podium's furniture;
--- nothing else the tutorial points at is.
local function wantsBay(step): boolean
	return step.Target ~= nil and step.Target.What == "Bay"
end

--[[ Say where this player is — on the Player as an attribute, and to their card as a payload.

	ONE FUNCTION FOR BOTH so the two can never disagree, which matters more than it looks: the
	attribute is what the getaway truck reads to decide whether to come out early and what the
	director reads to decide whether to stage the road, and a screen saying JUMP OUT over a run
	using the shipped traffic would be a bug nobody could see from either side.

	A player whose card has not pinged yet gets the attribute written anyway and the payload parked.
	That order is deliberate: the attribute has readers that are not the card. ]]
function TutorialService._publish(self, player: Player, completed: string?, finished: boolean?)
	local index = self:_index(player)
	local step = if index then TutorialConfig.stepAt(index) else nil

	player:SetAttribute(TutorialConfig.StepAttribute, if step then step.Id else "")

	local state: State = {
		step = if step then step.Id else "",
		index = index or 0,
		total = #TutorialConfig.Steps,
		bay = if step and wantsBay(step) then self:_bay(player) else nil,
		completed = completed,
		finished = finished,
	}

	--- What the pointer was last told, so `CarParked` can tell a correction from a repeat.
	self._sentBay[player] = state.bay

	if self._ready[player] then
		self:getRemoteEvent("TutorialState"):Fire(player, state)
	else
		self._parked[player] = state
	end
end

--[[ Which bay the pointer should point at: the one their car is standing on.

	The car the player has just banked, when we saw it park (`CarParked` carries the bay `awardCar`
	picked, which is the only place that decision is made). Otherwise the lowest bay with anything
	on it — which is what a player rejoining onto this beat needs, since the parking happened in a
	session that is over.

	nil is a perfectly good answer and means "point at nothing": a player who reached this beat with
	an empty lot has sold their car back or is standing somewhere strange, and the card still says
	what to do. A missing target is never a missing objective. ]]
function TutorialService._bay(self, player: Player): number?
	local remembered = self._parkedBay[player]

	local Garage = Shard.get("GarageService")
	if not Garage then
		return nil
	end
	if remembered and not Garage:isWorkshopBay(remembered) and Garage:getBayCar(player, remembered) then
		return remembered
	end
	local lowest: number? = nil
	for _, bay in Garage:getBays(player) do
		if not Garage:isWorkshopBay(bay.index) and Garage:getBayCar(player, bay.index)
			and (not lowest or bay.index < lowest) then
			lowest = bay.index
		end
	end
	return lowest
end

-- === The client's end =======================================================

function TutorialService._onReady(self, player: Player)
	if not TutorialConfig.isOn() or self._ready[player] then
		return
	end
	self._ready[player] = true

	local parked = self._parked[player]
	self._parked[player] = nil
	if parked then
		self:getRemoteEvent("TutorialState"):Fire(player, parked)
	end
end

--[[ They pressed SKIP.

	IT IS PERMANENT, not "not now", and that is the one editorial decision on this file. A dismiss
	that comes back is a dismiss that did not work — a player who has said they do not want to be
	told how to play has said it, and the objectives are eight things they can do anyway, in any
	order, whenever they like. Nothing in the game is gated on this having been finished, so there
	is nothing for a re-offer to protect.

	IT IS ALSO THE ONE WAY OUT OF A CAGE, which the old tracker version did not have to think about.
	Three of these beats stop the world and two of them gate the lobby's buttons, so SKIP is not
	only a preference — it is the release valve for a player who cannot make the input the card is
	asking for. That is why it is on every beat, why it takes one press, and why the client drops
	every freeze and gate the moment the server's answer comes back.

	It writes the beat they were on rather than blanking it, so the save records how far somebody got
	before they gave up — which, with the funnel, is the pair of numbers worth having. ]]
function TutorialService._onSkip(self, player: Player)
	if not TutorialConfig.isOn() then
		return
	end
	local index = self:_index(player)
	if not index then
		return -- already finished or already skipped; a second press is a no-op, not a second write
	end

	local step = TutorialConfig.stepAt(index)
	self._live[player] = nil
	self:_store(player, step and step.Id or "", true)
	self:_publish(player)

	--[[ WHERE they gave up, not just that they did. A skip button with one undifferentiated event
		tells you the tutorial is unpopular; a skip event carrying the beat tells you WHICH beat is
		driving people to press it, which is the only version of that number anybody can act on. ]]
	local Analytics = Shard.get("AnalyticsService")
	if Analytics then
		Analytics:TutorialSkipped(player, if step then tonumber(step.Funnel) or index else index, step and step.Id)
	end

	self.log:info(string.format("%s skipped the tutorial on beat '%s'.", player.Name, step and step.Id or "?"))
end

-- === Wiring =================================================================

--[[ Connect every signal the beat list names, once each.

	DERIVED FROM `TutorialConfig.Steps`, not written out here — see the header. The connection set
	is de-duplicated so that two beats naming the same signal cannot produce two connections and
	therefore two advances for one event.

	A named service that is not running is a WARNING and not an error, because it is a legitimate
	state — a config switch can take a whole service's feature out of the game — and the right
	behaviour then is a tutorial with a beat nobody can finish rather than a server that failed to
	start. The warning names the beat so it is obvious which objective has gone dead. ]]
function TutorialService._bind(self)
	local seen: { [string]: boolean } = {}

	for _, step in TutorialConfig.Steps do
		local advance = step.Advance
		if advance.Kind ~= "Signal" then
			continue -- an input or a timer; the client closes it (`_onBeat`)
		end

		local key = advance.Service .. "." .. advance.Signal
		if seen[key] then
			continue
		end
		seen[key] = true

		local service = Shard.get(advance.Service)
		if not service then
			self.log:warn(string.format("No %s, so tutorial beat '%s' can never complete.", advance.Service, step.Id))
			continue
		end

		local ok, signal = pcall(function()
			return service:getSignal(advance.Signal)
		end)
		if not ok or not signal then
			self.log:warn(
				string.format(
					"%s has no signal '%s'; tutorial beat '%s' can never complete.",
					advance.Service,
					advance.Signal,
					step.Id
				)
			)
			continue
		end

		local serviceName, signalName = advance.Service, advance.Signal
		self._trove:Add(signal:Connect(function(player: Player, ...)
			self:_onSignal(player, serviceName, signalName, ...)
		end))
	end
end

--- Cache the profile off the join path, then work out where they stand. Same shape as
--- `OfflineService._watch`, including the re-check after the yield: a player who joins and leaves
--- inside that window must not have a beat written after they have gone.
function TutorialService._watch(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players then
			return
		end

		self._profiles[player] = profile
		self:_resume(player)
	end)
end

--- Drop everything held for a player, on leaving and on a hot reload.
function TutorialService._forget(self, player: Player)
	self._profiles[player] = nil
	self._live[player] = nil
	self._ready[player] = nil
	self._parked[player] = nil
	self._parkedBay[player] = nil
	self._sentBay[player] = nil
	self._funnelled[player] = nil
	self._watchingAt[player] = nil
end

--[[ Bring the tutorial up: bind the beats, watch the joins, catch up whoever is already here.

	ONCE, and callable from more than one place, which is why it is not simply the body of `start`.
	`start` calls it on an ordinary boot; `TutorialConfig.whenOn` and `restart` call it when a
	session that booted under the developer bypass has it lifted part way through. A second call is
	a no-op that still answers whether the tutorial is running.

	Answers false only when there is no GarageService, which is the one thing it cannot run without. ]]
function TutorialService._boot(self): boolean
	if self._booted then
		return true
	end

	local Garage = Shard.get("GarageService")
	if not Garage then
		self.log:warn("No GarageService — there is no join signal to hang the tutorial off.")
		return false
	end
	self._booted = true

	self:_bind()

	--[[ Which bay the banked car landed on, so the collect objective can point at the right mat.
		Remembered rather than looked up, because `awardCar` picks the bay and this is the only
		message that carries its choice.

		=== AND RE-PUBLISHED, BECAUSE THIS MESSAGE ARRIVES AFTER THE BEAT THAT WANTED IT =====

		COLLECT is served off `RewardService.RunSettled`, and the order those two land in is not
		the order this file would have picked: `GetawayService._onBanked` calls
		`RaceService.bankRun` FIRST (which settles the run, which fires the signal, which enters
		this beat and publishes it) and only then `GarageService.awardCar`, which is what picks
		the bay and fires this. The whole of the collect beat was therefore published before the
		bay it points at existed.

		`_bay`'s fallback covers a rejoin and cannot cover this: it answers "the lowest bay with
		a car on it", and a first-timer banking their first car had an EMPTY lot a moment ago. So
		the beat went out with `bay = nil`, the client had nothing to resolve, and the last
		objective in the tutorial — walk to the money — was taught by a card with no arrow.

		Only when it actually changes what the card was told, so an ordinary park during some
		other beat (or a second car landing on the same bay) costs nothing. ]]
	self._trove:Add(Garage:getSignal("CarParked"):Connect(function(player: Player, _body, _tier, bay: number)
		if Garage:isWorkshopBay(bay) then
			return
		end
		self._parkedBay[player] = bay

		local step = self:_liveStep(player)
		if step and wantsBay(step) and self._sentBay[player] ~= bay then
			self:_publish(player)
		end
	end))

	--- A car landing in the hands on PLACE is parked for them, a moment later (`_autoPark` says why).
	self._trove:Add(Garage:getSignal("CarryChanged"):Connect(function(player: Player, key: string?)
		if TutorialConfig.AutoPark.Enabled and type(key) == "string" and key ~= "" then
			task.delay(TutorialConfig.AutoPark.After, self._autoPark, self, player)
		end
	end))

	self._trove:Add(Garage:getSignal("ProfileReady"):Connect(function(player: Player)
		self:_watch(player)
	end))

	--[[ Catch up on anyone already warm. `ProfileReady` fires off the join path, so on a hot
		reload — or simply if GarageService starts first — a player can be past it by the time
		this connects, and would otherwise never be looked at. Same catch-up `OfflineService`
		makes. It is also what a mid-session boot leans on, since everybody is warm by then. ]]
	for _, player in Players:GetPlayers() do
		if Garage:isProfileReady(player) then
			self:_watch(player)
		end
	end

	self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
		self:_forget(player)
	end))
	return true
end

-- === Lifecycle ==============================================================

TutorialService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		self._live = {} :: { [Player]: number }
		self._ready = {} :: { [Player]: boolean }
		self._parked = {} :: { [Player]: State }
		self._parkedBay = {} :: { [Player]: number }
		--- The bay the last publish named, per player. See `_publish` and the `CarParked` binding.
		self._sentBay = {} :: { [Player]: number }
		--- Which funnel stages this session has already reported, per player. See `_funnel`.
		self._funnelled = {} :: { [Player]: { [number]: boolean } }
		--- When the client said the live beat's card was up with nothing over it. See `watchingSince`.
		self._watchingAt = {} :: { [Player]: number }
		self._trove = Trove.new()
	end,

	start = function(self)
		if not TutorialConfig.Enabled then
			self.log:info("Disabled by config — no onboarding. Every beat it watches is something else's event anyway.")
			return
		end

		--[[ The developer bypass (`TutorialConfig.BypassAttribute` on Workspace). Same silence as the
			line above and a different meaning, so it says so rather than sharing the message: this
			one is somebody's playtest, not the shipped game, and NOTHING IS WRITTEN (no profile key,
			no attribute, no funnel stage), so untick it and every player resumes on the beat they
			were on. ]]
		if TutorialConfig.isBypassed() then
			self.log:info(
				string.format(
					"Bypassed for this session: Workspace.%s is on. No profile is touched, so unticking it puts everybody back on the beat they were on.",
					TutorialConfig.BypassAttribute
				)
			)
			--- ...including mid-session, which is what the admin panel's Replay does. See `restart`.
			TutorialConfig.whenOn(function()
				self:_boot()
			end)
			return
		end

		--[[ ...and the case that makes the Studio-only rule safe to rely on: the attribute is saved
			into the place and published with it, so this is a live server carrying a tick somebody
			left behind. It is IGNORED (see the config), and said out loud once at boot so that the
			flag is findable from a log rather than only from the Properties panel. ]]
		if Workspace:GetAttribute(TutorialConfig.BypassAttribute) == true then
			self.log:warn(
				string.format(
					"Workspace.%s is on in a published server and is being IGNORED; the tutorial is running. Untick it in the place, or use TutorialConfig.Enabled if the intent was to ship without onboarding.",
					TutorialConfig.BypassAttribute
				)
			)
		end

		self:_boot()
	end,
})

TutorialService:withCleanup(function()
	for _, player in Players:GetPlayers() do
		TutorialService:_forget(player)
	end
	if TutorialService._trove then
		TutorialService._trove:Destroy()
	end
end)

return TutorialService
