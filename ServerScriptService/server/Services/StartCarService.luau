--[[
	StartCarService  (server)
	-------------------------
	Which car each player wants to start a run in. That is the whole service, and it is small for the
	same reason `WorldService` is: the choice is one string, and everything downstream is a lookup
	off it — the body names the roster model `RaceService` clones, the colour names the palette index
	`CarPaint` puts on the clone.

	=== IT DECIDES NOTHING ABOUT OWNERSHIP =====================================================

	`GarageService` owns the collection, and every selection is checked against it — through
	`GarageService:owns`, which reads the PROFILE, not through `GarageConfig.OwnedAttribute`. That
	attribute is a broadcast of the profile, so validating a client's request against it would be
	validating it against something the client watched us send. Same reasoning, same call, as
	`LobbyCarService.setLobbyCar`.

	=== THE DEFAULT IS NEVER STORED ============================================================

	`StartCarConfig.DefaultKey` (the empty string) means "this world's own starter", and it is
	resolved at spawn rather than written down: `carFor` answers `WorldConfig.startBodyFor(world)` for
	it, in stock livery, which is exactly what every run did before this service existed. So

	  • a fresh profile, a profile that has not loaded, and a profile whose saved car has been
	    filtered out by a config change all give the player the car they always got, and
	  • retuning `WorldConfig.StartRung` moves every unchosen player onto the new car with no
	    migration, because there is nothing stored to migrate.

	=== A REFUSED CAR DOES NOT REFUSE THE RACE =================================================

	This is where it deliberately parts company with `WorldService`, whose refusal `RaceService`
	treats as fatal to the entry. A refused WORLD would drop the player into a world they did not
	ask for; a refused CAR drops them into the starter, which is a car they have always been able to
	drive and the one they would have got by not opening the screen. So `RaceService._onEnterRequest`
	logs the refusal and enters anyway.

	That matters for one honest case rather than for the dishonest one: a player who presses Play
	before their profile has arrived owns nothing as far as `GarageService` can tell, and refusing
	their race over it would be the worst possible reading of a slow load.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(script.Parent.Parent.Data)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local StartCarConfig = require(ReplicatedStorage.shared.Configs.StartCarConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local StartCarService = Shard.new("StartCarService"):withDependencies({ "GarageService" })

StartCarService:withSignals({
	--[[ (player: Player, key: string, previous: string) — this player is now starting runs in a
		different car. Nothing listens yet; it exists so that whatever eventually reacts to the choice
		(a quest, a lobby that re-dresses itself) does not have to watch the attribute. ]]
	"StartCarChanged",
})

--[[ No remotes. The choice rides along with `RequestEnterRace` — the entry request already carries
	the world for the reason written down in `RaceEntryController` ("two remotes would be two round
	trips whose order nothing guarantees"), and the car is the same kind of argument: something the
	run has to be built from, arriving in the message that asks for the run.

	`setStartCar` is therefore reached from `RaceService._onEnterRequest` and is public for any other
	trusted caller that turns up. ]]

-- === Reading ================================================================

--- The profile, or nil if it has not loaded yet. Non-yielding, same contract as WorldService's.
function StartCarService._profile(self, player: Player)
	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

--[[ The selection as stored, without asking whether it is still usable. A car key, or the default.

	Read off the PROFILE rather than the attribute so this agrees with `GarageService` about which
	copy of the truth it is working from — the attribute exists for the client. ]]
function StartCarService.selectionOf(self, player: Player): string
	local profile = self:_profile(player)
	local stored = profile and profile:Get(StartCarConfig.ProfileKey)
	return if type(stored) == "string" then stored else StartCarConfig.DefaultKey
end

--[[ Is this key something this player may start a run in, in this world? Returns false and a reason,
	so the caller can log which of the three it was.

	The three are the three ways a key can be wrong, and they are checked in this order on purpose:
	unreadable (a client sent junk, or a body was renamed out of the roster), not owned (the profile
	says no — or has not arrived, which reads the same and is why refusal is not fatal), and not on
	this road (only when `WorldLadderOnly` is on). ]]
function StartCarService.canDrive(self, player: Player, key: unknown, world: number?): (boolean, string?)
	if StartCarConfig.isDefault(key) then
		return true -- the world's own starter, always available to everybody
	end
	if type(key) ~= "string" then
		return false, "not a key"
	end

	local body = GarageConfig.parseCarKey(key)
	if not (body and GarageConfig.TierOfBody[body]) then
		return false, "not on the roster"
	end

	local GarageService = Shard.get("GarageService")
	if not GarageService then
		return false, "garage unavailable"
	end
	if not GarageService:owns(player, key) then
		return false, "not owned"
	end

	if StartCarConfig.WorldLadderOnly and world and WorldConfig.WorldOfBody[body] ~= world then
		return false, "wrong world"
	end

	return true
end

--[[ Public (RaceService): the body, paint and mutation this player's run in `world` should start in.

	ALWAYS ANSWERS. A selection that is missing, unreadable, sold, filtered out by a config change or
	blocked by a profile that has not loaded all resolve to the world's own starter in stock livery —
	the car every run started in before this feature — rather than to nil. `_spawnCar` has a fallback
	of its own for a body that is not in the place, and this must not be the thing that reaches it.

	Re-validated on every call rather than trusted from when it was stored, so a rule tightened today
	(a body dropped from the roster, `WorldLadderOnly` switched on) takes effect on the next race
	instead of on the next time somebody happens to open the screen. ]]
function StartCarService.carFor(self, player: Player, world: number?): (string, number, string?)
	local index = WorldConfig.resolve(world)
	local fallback = WorldConfig.startBodyFor(index)

	local key = self:selectionOf(player)
	if StartCarConfig.isDefault(key) then
		return fallback, PaintConfig.StockIndex
	end

	local ok, why = self:canDrive(player, key, index)
	if not ok then
		self.log:info(string.format(
			"%s's start car %s is not usable (%s); driving %s's starter instead.",
			player.Name, key, tostring(why), WorldConfig.displayName(index)))
		return fallback, PaintConfig.StockIndex
	end

	local body, paint, mutation = GarageConfig.parseCarKey(key)
	--[[ Sanitised on the way out for the same reason `GarageService._ownedList` sanitises on the way
		in: narrowing a body's palette pool tomorrow must not spawn somebody's car in a colour that
		body is no longer allowed to be. ]]
	return body :: string, PaintConfig.sanitize(body, paint), mutation
end

-- === Writing ================================================================

--- Put the key on the player and (if their profile is here) in it. The single write path.
function StartCarService._publish(self, player: Player, key: string, persist: boolean)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute(StartCarConfig.Attribute, key)
	if persist then
		local profile = self:_profile(player)
		if profile then
			profile:Set(StartCarConfig.ProfileKey, key)
		end
	end
end

--[[ Public: remember that this player wants to start runs in `key`. Returns whether it was taken and
	why not if it wasn't — the reason is for the log and for the caller's fallback, not for the
	client, which is told nothing beyond the attribute changing.

	Server-authoritative and safe to call from any trusted caller. Idempotent: choosing the car you
	already have chosen succeeds and writes nothing.

	`world` is what the choice is being made FOR and is only consulted by `WorldLadderOnly`. It is
	passed rather than read off the player because the caller is `_onEnterRequest`, which has just
	moved them: reading it here would race that move. ]]
function StartCarService.setStartCar(self, player: Player, key: unknown, world: number?): (boolean, string?)
	if not StartCarConfig.Enabled then
		return false, "disabled"
	end

	local wanted = if StartCarConfig.isDefault(key) then StartCarConfig.DefaultKey else key
	if type(wanted) ~= "string" then
		return false, "not a key"
	end

	local previous = self:selectionOf(player)
	if previous == wanted then
		return true
	end

	--[[ Refused mid-race for the same reason `WorldService.setWorld` is: the car under the player was
		cloned at `RaceStart` and there is no swapping it out from under a moving run. The screen this
		comes from is unreachable during a race anyway (`RaceEntryController` hides Play and shuts both
		of its pages), so this only ever answers a client that went looking. ]]
	local RaceService = Shard.get("RaceService")
	if RaceService and RaceService:isRacing(player) then
		return false, "mid-race"
	end

	local ok, why = self:canDrive(player, wanted, world)
	if not ok then
		return false, why
	end

	if not self:_profile(player) then
		--[[ Published but not stored, so the screen the player is looking at agrees with the car they
			are about to drive even though nothing can be saved yet. The alternative — refusing — would
			mean a player whose save is slow cannot choose a car they can plainly see. ]]
		self:_publish(player, wanted, false)
		return true, "not stored"
	end

	self:_publish(player, wanted, true)
	self.log:info(string.format("%s will start runs in %s.",
		player.Name, if wanted == StartCarConfig.DefaultKey then "the world's starter" else wanted))
	self:getSignal("StartCarChanged"):Fire(player, wanted, previous)
	return true
end

-- === Joining ================================================================

--[[ Publish the default now, the saved car when it arrives — the same ordering `WorldService` uses
	and for the same reason: the screen is reachable from the first frame, and "the world's starter"
	is the honest answer for a player whose save has not landed rather than a missing attribute the
	page would have to treat as a question.

	The re-check after the yield is the one GarageService documents: `GetProfileAsync` can take
	seconds and a player who joins and leaves inside that window must not have an attribute written
	onto a Player instance that has already been destroyed.

	NOT VALIDATED HERE, on purpose. A saved car whose body has left the roster is answered for by
	`carFor` on every race, so validating it again at join would only mean deciding whether to erase
	it — and erasing it would cost the player their choice the one time a body was renamed and put
	back. The stale key is harmless: it drives the starter until it is usable again. ]]
function StartCarService._onPlayerAdded(self, player: Player)
	self:_publish(player, StartCarConfig.DefaultKey, false)

	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players then
			return
		end
		self._profiles[player] = profile

		local saved = profile:Get(StartCarConfig.ProfileKey)
		if type(saved) == "string" and saved ~= StartCarConfig.DefaultKey then
			self:_publish(player, saved, false)
		end
	end)
end

StartCarService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
	end,

	start = function(self)
		self._trove = Trove.new()

		--[[ A car the player sold is no longer a car they can start in, so the selection goes back to
			the world's own starter.

			THE RACE WAS ALREADY SAFE WITHOUT THIS — `carFor` re-validates ownership on every call and
			falls back, which is what its own header means by "sold". What is not safe is the SCREEN:
			`StartCarConfig.Attribute` would still name the sold car, so the START CAR page would draw
			a tick on a card that is no longer in the list, and the player would set off in a different
			car from the one the UI told them they had chosen. This is the write that stops the two
			disagreeing.

			Reset rather than re-pointed at some other owned car: which car to drive instead is the
			player's call, and the starter is the answer the game already gives when it does not know. ]]
		local GarageService = Shard.get("GarageService")
		if GarageService then
			self._trove:Add(GarageService:getSignal("CarsSold"):Connect(function(player: Player, keys: { string })
				local current = self:selectionOf(player)
				if StartCarConfig.isDefault(current) then
					return
				end
				for _, sold in keys do
					if sold == current then
						self:_publish(player, StartCarConfig.DefaultKey, true)
						self.log:info(string.format(
							"%s sold %s, which was their start car; back to the world's starter.", player.Name, sold))
						return
					end
				end
			end))
			--[[ ...and one repainted in the workshop FOLLOWS its car (2026-09-28). A repaint re-keys the
				car (`GarageService.repaintCar`), so the stored ID stops being owned; without this the
				next run would quietly start in the world's starter, which reads as the choice being
				lost rather than the car being a new colour. ]]
			self._trove:Add(GarageService:getSignal("CarRekeyed"):Connect(function(player: Player, oldId: string, newId: string)
				if self:selectionOf(player) == oldId then
					self:_publish(player, newId, true)
				end
			end))
		else
			self.log:warn("GarageService unavailable; selling a start car will leave it selected.")
		end

		self._trove:Add(Players.PlayerAdded:Connect(function(player)
			self:_onPlayerAdded(player)
		end))
		self._trove:Add(Players.PlayerRemoving:Connect(function(player)
			self._profiles[player] = nil
		end))
		-- Anyone already in (Studio's own player joins before services start).
		for _, player in Players:GetPlayers() do
			self:_onPlayerAdded(player)
		end
	end,
})

return StartCarService
