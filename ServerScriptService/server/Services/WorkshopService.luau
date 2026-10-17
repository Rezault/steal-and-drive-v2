--[[
	WorkshopService  (server)
	-------------------------
	The customization bay's rules: what a repair, a repaint and a part cost, what each adds to the
	car's market value, and taking the money for them. `CustomizeConfig` has the design and every
	number; `GarageService` stores the result and says which podium is the workshop;
	`WorkshopController` draws the screen. Added 2026-09-28 with the dealership rework (card 3).

	=== EVERY NUMBER ON THE SCREEN IS WORKED OUT HERE ==========================================

	The screen is sent a finished STATE — each option's price and the value it would add, as
	dollars — rather than the rules to work them out. A client that priced its own repair would
	need `MarketValueConfig`, `CustomizeConfig` and the car's record to agree with this file to the
	dollar forever; sending the answer means the number on the button is the number charged, and a
	future change to the formula changes one file. `_state` is the only place a price is computed,
	and `_request` charges exactly what `_state` would have shown.

	"WHAT IT ADDS" IS MEASURED, NOT DERIVED: the value is priced twice through
	`MarketValueConfig.valueOf`, once as the car is and once as it would be, and the difference is
	the gain. So a part fitted to a battered car shows the smaller gain it really gets (parts ride on
	top of condition), and nothing here restates that formula.

	=== WHAT IT TRUSTS ========================================================================

	The client names an ACTION ("repair", "paint", "part", "change") and, for paint and part, WHICH
	colour or part. Nothing else. The car is whatever stands in the player's workshop right now —
	never an ID off the wire — so a request can only ever touch the car in the workshop, which is the
	card's "no two systems touch one car" lock from this side: buyers and tips are kept off the
	workshop by `GarageService.locationOf`, and this is kept off everything else. The price is
	recomputed at the press, the cash is checked, and a write that fails is refunded.

	What is knowingly NOT checked: that the player is standing at the workshop when they press. The
	screen opens off an owner-only prompt and could be kept open while they walk away; the most that
	buys is paying for your own car's upgrade from across your own lot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local MarketValueConfig = require(ReplicatedStorage.shared.Configs.MarketValueConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
--- `NoPaint` on a mutation (the ghost): a CONFIG and not `WeatherService`, the rule is static data.
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)

local WorkshopService = Shard.new("WorkshopService"):withDependencies({ "GarageService" })

--- (player: Player, cost: number, info: { kind: string, carId: string, part: string?, level: number? }) :
--- a workshop purchase landed. `kind` is "Repair", "Paint" or "Part". For `AnalyticsService`
--- (2026-10-15): the workshop is a cash sink, and customising is an engagement number.
WorkshopService:withSignals({ "Bought" })

--- Seconds between two requests from one player. A floor on writes, not a game rule: every accepted
--- request writes the profile and rebuilds the lot, and a held-down button should not do that sixty
--- times a second. The client's own `CustomizeConfig.Screen.Cooldown` is the courtesy in front of it.
local COOLDOWN = 0.25

WorkshopService:withRemoteEvents({
	--[[ server -> client (state | nil, refresh): open, or repaint, the workshop screen with this
		state; nil closes it (the car left the workshop). `state` is `_state`'s table — every price and
		gain already worked out, see the header. `refresh` is true for a send the player did not ask
		for (the lot changed under an open screen), and the client ignores one of those while its
		screen is shut — the client says nothing when it closes, so the server cannot know. ]]
	"WorkshopState",
	{
		--[[ client -> server (action, arg): the owner pressed something on the screen. `action` is
			"repair" | "paint" | "part" | "change"; `arg` is the palette index for paint and the part
			key for part. See "what it trusts". ]]
		WorkshopRequest = function(player: Player, action: unknown, arg: unknown)
			WorkshopService:_request(player, action, arg)
		end,
	},
})

-- === Pricing ================================================================

--[[ Everything the screen shows for the car in this player's workshop, or nil for an empty one.

	Pure over the save: it reads the car's record and prices it, writes nothing, and is what
	`_request` re-runs at the press to charge — so the shown price and the charged price are the same
	call. Every money figure is a whole dollar, rounded once here. ]]
function WorkshopService._state(self, player: Player)
	local Garage = Shard.get("GarageService")
	local id = Garage and Garage:workshopCar(player)
	if not id then
		return nil
	end
	local body, paint, mutation = GarageConfig.parseCarKey(id)
	local tier = body and GarageConfig.TierOfBody[body]
	if not tier then
		return nil
	end

	local record = Garage:getCarData(player, id)
	local base = GarageConfig.valueOf(tier, mutation)
	local value = MarketValueConfig.valueOf(tier, mutation, record)
	--- The value this car would have with one field of its record changed. The "measured, not
	--- derived" of the header.
	local function valueWith(field: string, fieldValue: any): number
		local changed = table.clone(record)
		changed[field] = fieldValue
		return MarketValueConfig.valueOf(tier, mutation, changed)
	end

	local condition = MarketValueConfig.conditionOf(record.Condition)
	local repairGain = valueWith("Condition", 1) - value
	local repair = if condition < 1 and repairGain > 0
		then { cost = math.max(1, math.round(repairGain * CustomizeConfig.Repair.CostOfGain)), gain = repairGain }
		else nil

	local parts = {}
	for _, part in CustomizeConfig.Parts do
		local level = CustomizeConfig.levelOf(record.Parts, part.Key)
		local entry = { key = part.Key, label = part.Label, level = level, max = CustomizeConfig.PartLevels }
		if level < CustomizeConfig.PartLevels then
			local fitted = table.clone(if type(record.Parts) == "table" then record.Parts else {})
			fitted[part.Key] = level + 1
			entry.gain = valueWith("Parts", fitted) - value
			entry.cost = CustomizeConfig.partCost(base, level + 1)
		end
		table.insert(parts, entry)
	end

	--- A body with one colour in its pool (a kept livery) cannot be repainted, and the screen says so
	--- rather than offering a palette of one.
	local pool = PaintConfig.poolFor(body)
	--- A mutation that hides the paint (`WeatherConfig` `NoPaint`, the ghost) locks it the same way.
	--- `_request` only sells a colour in `paints`, so an empty list is the server's refusal too.
	local mutated = mutation and WeatherConfig.mutationOf(mutation)
	local paintLocked = mutated ~= nil and mutated.NoPaint == true
	return {
		carId = id,
		body = body,
		paint = paint,
		value = value,
		condition = condition,
		repair = repair,
		paints = if #pool > 1 and not paintLocked then pool else {},
		--- The mutation's name when it is the reason, so the screen can say "GHOST cars can't be painted".
		paintLockedBy = if paintLocked then mutated.Name else nil,
		paintCost = math.max(1, math.round(base * CustomizeConfig.Paint.CostFraction)),
		parts = parts,
	}
end

--- Send the screen its state (or nil to close it). `refresh` as on the remote.
function WorkshopService._send(self, player: Player, refresh: boolean?)
	if player.Parent == Players then
		self:getRemoteEvent("WorkshopState"):Fire(player, self:_state(player), refresh == true)
	end
end

-- === Buying =================================================================

--[[ Take `cost` from the player and run `write`; refund if the write reports failure. Short of cash,
	nothing is taken and the cash top-up is offered, the same way the upgrade kiosks do it
	(`UpgradeService`). Returns whether the change landed. `info` rides on `Bought` when it does. ]]
function WorkshopService._charge(self, player: Player, cost: number, what: string, write: () -> boolean, info: { [string]: any }?): boolean
	local Garage = Shard.get("GarageService")
	local cash = Garage:getCash(player)
	if cash < cost then
		local CashService = Shard.get("CashService")
		if CashService then
			CashService:offerTopUp(player, cost - cash, what)
		end
		return false
	end
	Garage:addCash(player, -cost)
	if not write() then
		--- The profile went away, or the car did, between the check and the write. The money goes back
		--- rather than paying for a change that was never stored.
		Garage:addCash(player, cost)
		return false
	end
	self.log:info(string.format("%s paid %s for %s.", player.Name, GarageConfig.formatCash(cost), what))
	if info then
		self:getSignal("Bought"):Fire(player, cost, info)
	end
	return true
end

--[[ The screen's buttons. Header "what it trusts" is the rule; this is it in order: rate limit,
	find the car in the workshop, price it with `_state`, then charge and write. Every exit resends the
	state, so the screen always ends showing what is true — including after a refusal. ]]
function WorkshopService._request(self, player: Player, action: unknown, arg: unknown)
	if not CustomizeConfig.Enabled then
		return
	end
	local now = os.clock()
	if now < (self._cooldowns[player] or 0) then
		return
	end
	self._cooldowns[player] = now + COOLDOWN

	local Garage = Shard.get("GarageService")
	local state = self:_state(player)
	if not (Garage and state) then
		self:_send(player)
		return
	end
	local id = state.carId

	if action == "change" then
		local _, bay = Garage:workshopCar(player)
		if bay then
			Garage:openPicker(player, bay)
		end
		return
	elseif action == "repair" and state.repair then
		self:_charge(player, state.repair.cost, "a repair on " .. id, function()
			return Garage:setCarData(player, id, { Condition = 1 })
		end, { kind = "Repair", carId = id })
	elseif action == "paint" and type(arg) == "number" and table.find(state.paints, arg) then
		self:_charge(player, state.paintCost, "a repaint of " .. id, function()
			return (Garage:repaintCar(player, id, arg))
		end, { kind = "Paint", carId = id })
	elseif action == "part" then
		for _, part in state.parts do
			if part.key == arg and part.cost then
				local record = Garage:getCarData(player, id)
				local fitted = table.clone(if type(record.Parts) == "table" then record.Parts else {})
				fitted[part.key] = part.level + 1
				self:_charge(player, part.cost, string.format("%s level %d on %s", part.key, part.level + 1, id), function()
					return Garage:setCarData(player, id, { Parts = fitted })
				end, { kind = "Part", carId = id, part = part.key, level = part.level + 1 })
				break
			end
		end
	end

	self:_send(player)
end

-- === Lifecycle ==============================================================

WorkshopService:withLifecycle({
	init = function(self)
		self._trove = Trove.new()
		self._cooldowns = {} :: { [Player]: number }
		--- Players who have opened the workshop this session: the ones a lot change is worth resending
		--- to. Never cleared on close, because the server is never told of one (see `WorkshopState`).
		self._pressed = {} :: { [Player]: boolean }
	end,

	start = function(self)
		if not CustomizeConfig.Enabled then
			return
		end
		local Garage = Shard.get("GarageService")
		if not Garage then
			self.log:warn("GarageService unavailable; the workshop podium will open nothing.")
			return
		end

		self._trove:Add(Garage:getSignal("WorkshopPressed"):Connect(function(player: Player)
			self._pressed[player] = true
			self:_send(player)
		end))

		--[[ THE LOT CHANGED, so an open screen may be describing a car that has left the workshop, or a
			new car that has just been put there with CHANGE CAR. Resent as a REFRESH to anybody who has
			opened the workshop this session (the client drops it if its screen is shut), and a nil
			state closes an open one. Cheap: one pricing pass, only on a lot change, only for them. ]]
		self._trove:Add(Garage:getSignal("LotChanged"):Connect(function(player: Player)
			if self._pressed[player] then
				self:_send(player, true)
			end
		end))

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self._cooldowns[player] = nil
			self._pressed[player] = nil
		end))
	end,
})

WorkshopService:withCleanup(function()
	if WorkshopService._trove then
		WorkshopService._trove:Destroy()
	end
end)

return WorkshopService
