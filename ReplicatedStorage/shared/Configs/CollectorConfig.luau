--[[ CollectorConfig — the open-world car collector (the 2026-11 rework)
	===================================================================

	Walk out of your dealership into one long corridor of five zones, find cars roaming in herds,
	and steal any car whose REQUIRED STEAL POWER you meet. Stolen cars go straight into the hotbar
	through `GarageService.awardCar`, park on your podiums, and earn passive income. Spend that income
	on more Steal Power, which is the only gate between you and the next car.

	WHO OWNS WHAT
	  RoamingCarService (server)  every roaming car: what it is, where it is, who stole it.
	  RoamingCarController        draws the cars, their labels, and the hold-to-steal ring.
	  CollectorHudController      power, zone strip, toast + SECURED tray, announcements, countdown.

	THIS MODULE REQUIRES NOTHING AT ITS TOP. `GarageConfig` and `TutorialConfig` read `Enabled` from
	here, and this file needs `GarageConfig` for prices — a top-level require either way round would
	be a cycle. Everything that needs another config requires it inside the function that uses it.

	`Enabled = false` puts the old drive-first game back: no roaming cars, the race gate is live
	again, the driving tutorial runs, and the dealership goes back to customer tips. ]]

local CollectorConfig = {}

CollectorConfig.Enabled = true

--[[ WHERE THE CARS ARE (2026-11-01, owner after the first playtest: "one wide road with cars spawning
	from the start of the road, and I need to drive and catch and jump into them"; "I'm not able to do
	the satisfying jump and land in a car").

	`RoadSteal`: the race highway is the collector. Its traffic is what you steal, with the existing
	jump-and-land, and a landed car is YOURS on the spot (`StealService` -> `RoamingCarService.
	awardRoadSteal`): straight to the hotbar, no getaway truck, keep driving it to the next one. A car
	whose ⚡ requirement you do not meet cannot be locked or taken.

	`Roaming`: the first build's on-foot herds in the canyon south of the plots. Off; kept because it
	works and the corridor may come back as a lobby feature. ]]
CollectorConfig.RoadSteal = true
CollectorConfig.Roaming = false

-- === The corridor ============================================================
--[[ Measured in the place, 2026-11-01: the canyon south of the plots is flat at Y = -90 from the
	RACE gate (Z ~ -1000) to the end of the floor (Z ~ -2900), between walls at X ~ 7200 and 7780.
	Zones are laid along -Z in world order, so walking further means better cars — the reference's
	single runway. `HalfWidth` stays 30 studs inside the walls so a car never clips into the cliff. ]]
CollectorConfig.Corridor = {
	CenterX = 7490,
	HalfWidth = 230,
	FloorY = -89.5, -- the TOP of the authored ground (a raycast floored to -90 hid the half stud)
	StartZ = -1060, -- the START ZONE line; the hub is everything north of it
	ZoneLength = 360,
}

--[[ One per `WorldConfig.Worlds` entry, same index. Colours are the zone strip tile, the ground
	tint and the name in announcements. ]]
CollectorConfig.Zones = {
	-- City is asphalt: the lobby's own road grey. Light concrete read as snow under the bright sky.
	{ Ground = Color3.fromRGB(88, 92, 102), Material = Enum.Material.Asphalt, Color = Color3.fromRGB(120, 200, 255) },
	{ Ground = Color3.fromRGB(236, 205, 140), Material = Enum.Material.Sand, Color = Color3.fromRGB(255, 186, 74) },
	{ Ground = Color3.fromRGB(96, 178, 84), Material = Enum.Material.Grass, Color = Color3.fromRGB(110, 220, 96) },
	{ Ground = Color3.fromRGB(232, 244, 255), Material = Enum.Material.Snow, Color = Color3.fromRGB(170, 230, 255) },
	{ Ground = Color3.fromRGB(70, 52, 120), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(205, 120, 255) },
}

--- The zone index (1..5) a world position stands in, or 0 in the hub / out of bounds.
function CollectorConfig.zoneAt(position: Vector3): number
	local c = CollectorConfig.Corridor
	if math.abs(position.X - c.CenterX) > c.HalfWidth + 40 then
		return 0
	end
	local into = c.StartZ - position.Z
	if into < 0 then
		return 0
	end
	local index = math.floor(into / c.ZoneLength) + 1
	return if index <= #CollectorConfig.Zones then index else 0
end

--- The rectangle cars roam in for a zone: (centre, half size X, half size Z), with a margin so herds
--- do not sit on a zone line.
function CollectorConfig.zoneRect(index: number): (Vector3, number, number)
	local c = CollectorConfig.Corridor
	local z0 = c.StartZ - (index - 1) * c.ZoneLength
	local centre = Vector3.new(c.CenterX, c.FloorY, z0 - c.ZoneLength / 2)
	return centre, c.HalfWidth, c.ZoneLength / 2 - 24
end

--- Metres from the start line, for the zone strip readout (studs / `Meter`).
CollectorConfig.StudsPerMeter = 1.5

-- === Steal Power =============================================================
--[[ A STAT YOU TRAIN, NOT A LEVEL YOU BUY (2026-11-01, owner: "steal power should be able to train
	passively, like the other game has a toy horse you ride for energy"). ⚡ is a number on the
	profile that only goes up, while you sit on the KIDDIE RIDE at your plot (`Trainer` below). Cash
	buys Trainer levels, which make the ride pay faster. Every car has a REQUIRED power fixed by its
	tier (`GarageConfig.TierOfBody`, 1..50 across the five worlds); you can only steal a car whose
	requirement you meet.

	THE CURVE IS GEOMETRIC (x`Growth` per tier) so the number reads like the reference's ⚡ — 10, 11,
	13 … ~4,000 — and later worlds look harder at a glance, not by a constant. ]]
CollectorConfig.Power = {
	Base = 10,
	Growth = 1.13,
	Attribute = "StealPower", -- server-written, replicated to the owner
	ProfileKey = "StealPower", -- under the profile's Garage table; absent reads as `Start`
	Start = 10, -- exactly the Civic's requirement, so a new player can steal from the first second
}

--[[ The kiddie ride: the coin-op bouncing car outside a supermarket, one per plot. Sit on it and ⚡
	rises by `rateAt(level)` every second, AFK included — that is the point of the reference's horse.

	THE RATE TRACKS THE LADDER. Requirements grow x1.13 a tier, so x1.277 is two tiers; each Trainer
	level multiplies the rate by that, and level L is "the ride for tier ~2L". Level 0 trains the
	Civic -> Golf step (10 -> 11) in five seconds and world 1's top car (30) in under two minutes.
	PRICES follow the car the level is for, like the old Power ladder: `factor` x the market value of
	tier 2L, never less than `MinStep` x the previous price. The first level costs one Civic. ]]
CollectorConfig.Trainer = {
	UpgradeKey = "Trainer",
	MaxLevel = 24,
	BaseRate = 0.2, -- ⚡ per second at level 0
	RateGrowth = 1.277,
	TickSeconds = 1,
	EarlyFactors = { 0.1, 0.25, 0.4, 0.6 },
	CostFactor = 0.8,
	MinStep = 1.15,
}

--- ⚡ per second on the ride at Trainer `level`.
function CollectorConfig.rateAt(level: number): number
	local t = CollectorConfig.Trainer
	return t.BaseRate * t.RateGrowth ^ math.clamp(level, 0, t.MaxLevel)
end

--- A player's ⚡ (server: the authoritative attribute it wrote; client: the replicated copy).
function CollectorConfig.powerOf(player: Player): number
	local value = player:GetAttribute(CollectorConfig.Power.Attribute)
	return if type(value) == "number" then value else CollectorConfig.Power.Start
end

--- How ⚡ is shown: whole numbers, then 1.2K / 3.4M.
function CollectorConfig.formatPower(value: number): string
	if value >= 1e6 then
		return string.format("%.1fM", value / 1e6)
	elseif value >= 1e4 then
		return string.format("%.1fK", value / 1e3)
	end
	return tostring(math.floor(value))
end

local _required = {}
--- The steal power a car of `tier` needs.
function CollectorConfig.requiredFor(tier: number): number
	tier = math.clamp(math.floor(tonumber(tier) or 1), 1, 60)
	local cached = _required[tier]
	if not cached then
		local p = CollectorConfig.Power
		local raw = p.Base * p.Growth ^ (tier - 1)
		-- Two significant figures past 100, so the label reads 1,400 rather than 1,397.
		local unit = if raw >= 1000 then 100 elseif raw >= 100 then 10 else 1
		cached = math.max(1, math.round(raw / unit) * unit)
		_required[tier] = cached
	end
	return cached
end

--- The steal power a body needs, by its place on the world ladders (`WorldConfig.TierOfBody`), or
--- nil for a body on no ladder. By BODY because the road's own records carry a rung table, not a tier.
function CollectorConfig.requiredForBody(body: unknown): number?
	local tier = type(body) == "string" and require(script.Parent.WorldConfig).TierOfBody[body]
	return if tier then CollectorConfig.requiredFor(tier) else nil
end

local _prices: { number }? = nil
--- What buying Trainer level `level + 1` costs, or nil at the top. Read through `UpgradeConfig.costOf`.
function CollectorConfig.trainerCost(level: number): number?
	local p = CollectorConfig.Trainer
	if level >= p.MaxLevel then
		return nil
	end
	if not _prices then
		local GarageConfig = require(script.Parent.GarageConfig)
		local list = {}
		local previous = 0
		for l = 1, p.MaxLevel do
			local factor = p.EarlyFactors[l] or p.CostFactor
			local forTier = math.min(50, 2 * l) -- level l is the ride for tier ~2l
			local price = factor * (GarageConfig.valueOf(forTier) or 0)
			price = math.max(price, previous * p.MinStep, 100)
			-- Round to 2 significant figures: prices are read, not computed with.
			local unit = 10 ^ math.max(0, math.floor(math.log10(price)) - 1)
			price = math.round(price / unit) * unit
			list[l] = price
			previous = price
		end
		_prices = list
	end
	return (_prices :: { number })[level + 1]
end

--- The lowest requirement of any car in zone `world` — what you need to steal anything there.
function CollectorConfig.zoneMinimum(world: number): number
	return CollectorConfig.requiredFor((world - 1) * 10 + 1)
end

-- === Spawning ================================================================
CollectorConfig.Spawn = {
	CarsPerZone = 14,
	HerdSize = { 2, 4 }, -- inclusive
	--[[ Rung odds inside a zone (rung 1 = the world's cheapest car). NOT `BalanceConfig.RungWeights`:
		those are tuned for a road that throws hundreds of cars a run, where a 1-in-2,000 Legendary is
		still seen. A zone holds fourteen cars at a time, so the top rungs are lifted until a
		Legendary is a few-minutes sight rather than a never. ]]
	RungWeights = { 30, 25, 16, 12, 7, 4, 2.6, 1.6, 1.0, 0.6 },
	RespawnDelay = { 6, 12 }, -- seconds before a stolen car's slot refills
	MutationChance = 1, -- x `WeatherConfig.roll`'s own odds; 1 = the road's odds
}

-- === Movement ================================================================
--[[ Herds move in LEGS: pick a point, run to it, idle, repeat. A leg is replicated once as
	(from, to, startTime, endTime) and every client — and the server, for distance checks — computes
	the position from the shared clock, so a moving car costs one attribute write per leg, not per
	frame. Rarer cars run faster so the best ones need chasing; all of them stay under a player's
	`WalkSpeed` (16) on average because a leg is followed by an idle. ]]
CollectorConfig.Move = {
	LegDistance = { 30, 90 },
	Speed = { 10, 18 }, -- rung 1 .. rung 10
	Idle = { 1.5, 4.5 },
	FormationSpacing = 16,
	Lift = 0.35, -- studs between the floor and a shell's lowest point: clears the zone overlay
}

--[[ Where a car on leg (a -> b, t0 -> t1) is at server time `now`. THE ONE COPY: the server's
	distance check and every client's drawing call this, so they cannot disagree about where a car
	is. Smoothstep, so a herd sets off and pulls up rather than snapping to speed. ]]
function CollectorConfig.positionAt(a: Vector3, b: Vector3, t0: number, t1: number, now: number): Vector3
	if now >= t1 or t1 <= t0 then
		return b
	end
	if now <= t0 then
		return a
	end
	local x = (now - t0) / (t1 - t0)
	return a:Lerp(b, x * x * (3 - 2 * x))
end

-- === Capturing ===============================================================
CollectorConfig.Capture = {
	--[[ Stand within `Radius` of a car you can steal and a ring fills over `HoldSeconds`; leave and
		it drains. The reference reads as instant-on-contact; a half-second fill keeps that pace but
		gives the moment a beat and makes it deliberate on mobile, where there is no key to press. ]]
	Radius = 13,
	HoldSeconds = 0.45,
	--[[ SERVER SLACK. The server checks the distance between the character and where the car is
		NOW by the shared clock. The client measured it up to a ping ago against a car that has since
		moved, so the server allows `Radius + Slack + speed x LatencySeconds`. ]]
	Slack = 8,
	LatencySeconds = 0.6,
	Cooldown = 0.35, -- per player, between accepted requests
	Source = "Capture", -- the `awardCar` source; not a carry source, so the car lands in the hotbar
}

-- === World events ============================================================
CollectorConfig.Events = {
	ResetPeriod = 300, -- "ALL CARS RESET!" — every zone re-rolled
	FirstResetDelay = 120,
	--[[ SECRET CARS: on each reset, each of 1..`SecretsMax` random zones gets one car from its top
		two rungs, guaranteed mutated (`SecretMutations`), and announced to the server. They never
		respawn when stolen. ]]
	SecretsMin = 1,
	SecretsMax = 3,
	SecretMutations = { "Charged", "Molten", "Ghost" },
	SecretRungs = { 9, 10 },
	--[[ A RUSH between resets: one zone's spawns roll mutations at x`RushMutation` for `RushSeconds`.
		Announced, counted down on the HUD, and the reason to walk to a zone you were not in. ]]
	RushEvery = 150,
	RushSeconds = 60,
	RushMutation = 6,
}

-- === Replication names =======================================================
CollectorConfig.FolderName = "RoamingCars" -- ReplicatedStorage, so StreamingEnabled never hides one
CollectorConfig.NextResetAttribute = "CollectorNextReset" -- workspace, server time
CollectorConfig.RushAttribute = "CollectorRush" -- workspace, "zone|endsAt" or ""
CollectorConfig.Remotes = {
	Capture = "RoamCapture", -- client -> server (id)
	Captured = "RoamCaptured", -- server -> capturer (result table)
	Announce = "CollectorAnnounce", -- server -> all (payload table)
}

-- === Presentation ============================================================
CollectorConfig.Label = {
	MaxDistance = 140, -- studs; the label floats just over each car's roof (RoamingCarController)
}

CollectorConfig.Toast = {
	Seconds = 2.6,
	TrayMax = 6,
}

return CollectorConfig
