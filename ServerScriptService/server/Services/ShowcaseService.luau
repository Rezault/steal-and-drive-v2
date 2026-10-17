--[[
	ShowcaseService  (server)
	-------------------------
	Keeps each player's BEST CAR record and tells their client when a car beats it, which is the cue
	for the NEW BEST cutscene (`ShowcaseController`). `ShowcaseConfig`'s header has what "best" means
	and why it is a saved record rather than a look at the collection.

	IT LISTENS, IT DOES NOT GET CALLED. Every way a car becomes a player's goes through
	`GarageService.awardCar`, and that fires `CarAwarded`; hanging off the signal is what makes a fifth
	way to get a car (a quest reward, a gift) show off without anybody remembering this file exists.

	TRUST. Nothing here reads the client. The tier and the weather come from the award, which has
	already checked them against the roster and the world's weather (`GetawayService`), and the
	remote only goes one way. The worst a forged `NewBestCar` could do is play a cutscene on the
	forger's own screen.

	SEEDING. A record of zero means "never measured", and the first award measured against it is
	compared with the best car the player ALREADY owns, not with zero — see the `BestCarValue` note in
	`Settings.luau`. A player with nothing owned has nothing to seed from, so their first car is a
	new best, which `ShowcaseConfig.Sources` says is wanted.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local MarketValueConfig = require(ReplicatedStorage.shared.Configs.MarketValueConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local ShowcaseConfig = require(ReplicatedStorage.shared.Configs.ShowcaseConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local Data = require(script.Parent.Parent.Data)

local ShowcaseService = Shard.new("ShowcaseService"):withDependencies({ "GarageService" })

ShowcaseService:withRemoteEvents({
	--[[ server -> client (body, paint, mutation, value, afterRun): play the stage for this car.
		`afterRun` is true for a bank, and the client holds the stage until the run's results have
		lifted (`ShowcaseConfig.ReturnTimeout`). Pictures only — see the header's trust note. ]]
	"NewBestCar",
})

-- === The record ================================================================

function ShowcaseService._profile(self, player: Player)
	local profile = self._profiles[player]
	return if profile and profile:IsActive() then profile else nil
end

--- What one owned car ID is worth by the record's measure (`ShowcaseConfig` header). 0 for a body
--- off the roster, the same answer `GarageConfig.valueOfCollection` gives it.
local function valueOfId(id: string): number
	local body, _paint, mutation = GarageConfig.parseCarKey(GarageConfig.modelKeyOf(id))
	return GarageConfig.valueOf(body and GarageConfig.TierOfBody[body], mutation)
end

--[[ The player's record, seeded when it has never been measured. `except` is the car being judged,
	left out of the seed — it is already in the collection by the time `CarAwarded` fires, and
	seeding from it would make it tie with itself and never be shown. ]]
function ShowcaseService._record(self, player: Player, except: string?): number
	local profile = self:_profile(player)
	local stored = profile and profile:Get(ShowcaseConfig.ProfileKey)
	if type(stored) == "number" and stored > 0 then
		return stored
	end
	local Garage = Shard.get("GarageService")
	local best = 0
	for _, id in Garage:ownedIds(player) do
		if id ~= except then
			best = math.max(best, valueOfId(id))
		end
	end
	return best
end

--[[ `CarAwarded`: does this car beat the record? Writes the new record whatever the source (a pulled
	car that beats your best IS your best) and only then decides whether to show it. Ties do not
	count — a second car exactly as good as your best is not a new one. ]]
function ShowcaseService._onAwarded(self, player: Player, id: string, tier: number, mutation: string?, paint: number?, source: string?)
	if not ShowcaseConfig.Enabled then
		return
	end
	local profile = self:_profile(player)
	if not profile then
		return -- no record to compare with: the car still counts next time, it just is not shown
	end
	local value = GarageConfig.valueOf(tier, mutation)
	local previous = self:_record(player, id)
	if value <= previous then
		if (profile:Get(ShowcaseConfig.ProfileKey) or 0) <= 0 and previous > 0 then
			profile:Set(ShowcaseConfig.ProfileKey, previous) -- the seed, kept, so it is measured once
		end
		return
	end
	profile:Set(ShowcaseConfig.ProfileKey, value)
	self.log:info(string.format("%s has a new best car: %s at %d (was %d).", player.Name, id, value, previous))

	if not ShowcaseConfig.shows(source) then
		return
	end
	local body = GarageConfig.parseCarKey(GarageConfig.modelKeyOf(id))
	self:getRemoteEvent("NewBestCar"):Fire(player, body, paint, mutation, self:_worthOf(player, id), source == "Bank")
end

--[[ What the stage PRINTS under the car's name (2026-10-15): this car's own worth, condition and
	parts included, which is the number its sign, the sell lot and a buyer all go by. The RECORD stays
	on the model's price (`ShowcaseConfig`, "what best means"), and that is still right for deciding
	whether to play. But printed, the model's price is a number nothing else in the game shows for
	this car: a GT banked at half HP was announced WORTH $180.0K and its sign then said $136.4K. ]]
function ShowcaseService._worthOf(_self, player: Player, id: string): number
	local Garage = Shard.get("GarageService")
	return MarketValueConfig.valueOfId(id, Garage:getCarData(player, id))
end

-- === Admin =====================================================================

--[[ Public (`AdminService`): play the stage now for the most valuable car this player owns, without
	touching the record. Returns `(ok, what)` in the shape every admin action reports. ]]
function ShowcaseService.playBest(self, player: Player): (boolean, string)
	local Garage = Shard.get("GarageService")
	local bestId, bestValue = nil, -1
	for _, id in Garage:ownedIds(player) do
		local value = valueOfId(id)
		if value > bestValue then
			bestId, bestValue = id, value
		end
	end
	if not bestId then
		return false, "they own no cars"
	end
	local body, paint, mutation = GarageConfig.parseCarKey(GarageConfig.modelKeyOf(bestId))
	self:getRemoteEvent("NewBestCar"):Fire(player, body, paint, mutation, self:_worthOf(player, bestId), false)
	return true, string.format("showing %s", bestId)
end

--[[ Public (`AdminService`): play the stage now for ANY car on the roster, owned or not, in the paint
	and weather given (2026-10-03, for recording every rarity's garage). Nothing is granted and the
	record is not touched; the price on screen is what the record would count it at. `paint` is a
	palette index, or anything else for a roll; `mutation` an unknown key for none. ]]
function ShowcaseService.playCar(self, player: Player, body: unknown, paint: unknown, mutation: unknown): (boolean, string)
	local tier = type(body) == "string" and GarageConfig.TierOfBody[body]
	if not tier then
		return false, string.format("no car named '%s' on any roster", tostring(body))
	end
	local colour = if type(paint) == "number" then PaintConfig.sanitize(body, paint) else PaintConfig.roll(self._random, body)
	local weather = WeatherConfig.sanitize(mutation)
	local value = GarageConfig.valueOf(tier, weather)
	self:getRemoteEvent("NewBestCar"):Fire(player, body, colour, weather, value, false)
	return true, string.format("showing a %s%s %s", if weather then WeatherConfig.nameOf(weather) .. " " else "", PaintConfig.nameOf(colour), body)
end

--[[ Public (`AdminService`): wipe the record to 1 dollar, so the next car of any worth is a new
	best. ONE, NOT ZERO: zero is "never measured" and would be re-seeded from the collection, which is
	exactly what this is for getting past. ]]
function ShowcaseService.forgetBest(self, player: Player): (boolean, string)
	local profile = self:_profile(player)
	if not profile then
		return false, "no profile loaded"
	end
	profile:Set(ShowcaseConfig.ProfileKey, 1)
	return true, "record wiped; their next car is a new best"
end

-- === Lifecycle ================================================================

ShowcaseService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		--- For the admin preview's paint roll (`playCar`), its own so nothing else's sequence moves.
		self._random = Random.new()
	end,

	start = function(self)
		local Garage = Shard.get("GarageService")
		--- The profile handle, off the moment `GarageService` says it is warm — `SpeedTrapService`'s
		--- pattern, for its reason: a second idea of when a player is ready is a race.
		Garage:getSignal("ProfileReady"):Connect(function(player: Player)
			task.spawn(function()
				local ok, profile = pcall(function()
					return Data:GetProfileAsync(player)
				end)
				if ok and profile and player.Parent == Players then
					self._profiles[player] = profile
				end
			end)
		end)
		Garage:getSignal("CarAwarded"):Connect(function(player, id, tier, mutation, paint, source)
			self:_onAwarded(player, id, tier, mutation, paint, source)
		end)
		Players.PlayerRemoving:Connect(function(player)
			self._profiles[player] = nil
		end)
	end,
})

return ShowcaseService
