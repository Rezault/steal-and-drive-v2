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

--[[ WHERE THE CARS ARE. Three owner calls on 2026-11-01, in order:
	  1. on-foot herds in the canyon south of the plots ("nothing like the video");
	  2. the race highway behind the PLAY button, stealing traffic with the race's jump-and-land;
	  3. "remove the play button altogether … in the video there's just an area in the map where dinos
	     spawn and you go in and jump into one" — the one in force.

	`Roaming` is (3): the canyon is ONE WIDE HIGHWAY (`Road`), cars drive straight down its lanes out of
	each zone's arch, and you walk in and LEAP onto one (`Leap`). Nothing teleports you anywhere and
	there is no race: `RaceService.enterRace` refuses while this is on, and the PLAY button is hidden.

	`RoadSteal` is (2), kept switchable: the race traffic is stolen with the race's own jump and awarded
	by `RoamingCarService.awardRoadSteal`. Turn `Roaming` off and this on to go back to it. ]]
CollectorConfig.RoadSteal = false
CollectorConfig.Roaming = true

--- Whether the race (PLAY, the lobby pad, the getaway truck) exists at all.
function CollectorConfig.racesOn(): boolean
	return not (CollectorConfig.Enabled and CollectorConfig.Roaming)
end

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
	level multiplies the rate by that, and level L is "the ride for tier ~2L". Level 0 pays +1 every
	half second, so world 1's top car (30) is ten seconds of riding: the owner wanted the number to
	visibly race (0.2/s ticking once a second, the first version, read as broken).
	PRICES follow the car the level is for, like the old Power ladder: `factor` x the market value of
	tier 2L, never less than `MinStep` x the previous price. The first level costs one Civic. ]]
CollectorConfig.Trainer = {
	UpgradeKey = "Trainer",
	MaxLevel = 24,
	BaseRate = 2, -- ⚡ per second at level 0
	RateGrowth = 1.277,
	TickSeconds = 0.5,
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
	CarsPerZone = 14, -- roughly how many are on a zone's road at once (`Road.SpawnEvery` is derived from it)
	--[[ Rung odds inside a zone (rung 1 = the world's cheapest car). NOT `BalanceConfig.RungWeights`:
		those are tuned for a road that throws hundreds of cars a run, where a 1-in-2,000 Legendary is
		still seen. A zone holds fourteen cars at a time, so the top rungs are lifted until a
		Legendary is a few-minutes sight rather than a never. ]]
	RungWeights = { 30, 25, 16, 12, 7, 4, 2.6, 1.6, 1.0, 0.6 },
	MutationChance = 1, -- x `WeatherConfig.roll`'s own odds; 1 = the road's odds
}

-- === The road ================================================================
--[[ ONE WIDE HIGHWAY down the middle of the canyon. Each zone runs its own traffic: a car comes out of
	the zone's arch (`StartZ` side), drives straight down its lane at its lane's speed, and goes into the
	next arch, where it is removed — so the zone line is where cars appear and disappear, under the arch
	that hides it.

	LANES HAVE SPEEDS, CARS DO NOT, so nothing in a lane ever drives through the car ahead of it. The
	outer lanes run just over walking pace (`WalkSpeed` 16), so a car there can be walked alongside;
	the middle ones need a run-up and a good jump. Rarer cars prefer faster lanes (`laneFor`), so the
	best car on the road is also the hardest one to land on. ]]
CollectorConfig.Road = {
	LaneWidth = 20,
	LaneSpeeds = { 18, 26, 34, 34, 26, 18 }, -- studs/s, lane 1 is the west edge (-X)
	EndMargin = 14, -- studs inside each arch where a car appears / disappears
	MinGap = 45, -- studs between consecutive cars in one lane
	FastRungs = { 5, 9 }, -- rung >= [1] prefers the 26 lanes, >= [2] the 34 lanes
	LanePreference = 0.7, -- chance a car takes its preferred speed, otherwise any lane
	Lift = 0.45, -- studs between the floor and a shell's lowest point: clears the road paint
}

--- How far the lanes reach either side of the corridor's centre.
function CollectorConfig.roadHalfWidth(): number
	local r = CollectorConfig.Road
	return #r.LaneSpeeds * r.LaneWidth / 2
end

--- The X of lane `lane`'s centre line.
function CollectorConfig.laneX(lane: number): number
	local r = CollectorConfig.Road
	return CollectorConfig.Corridor.CenterX - CollectorConfig.roadHalfWidth() + (lane - 0.5) * r.LaneWidth
end

--- Where a zone's traffic starts and ends (Z), arch to arch.
function CollectorConfig.zoneRoad(zone: number): (number, number)
	local c = CollectorConfig.Corridor
	local z0 = c.StartZ - (zone - 1) * c.ZoneLength
	local margin = CollectorConfig.Road.EndMargin
	return z0 - margin, z0 - c.ZoneLength + margin
end

--[[ Where a car on leg (a -> b, t0 -> t1) is at server time `now`. THE ONE COPY: the server's
	distance check, every client's drawing and the leap's landing prediction call this, so they cannot
	disagree about where a car is. Linear: a car on the highway is already at speed. ]]
function CollectorConfig.positionAt(a: Vector3, b: Vector3, t0: number, t1: number, now: number): Vector3
	if now >= t1 or t1 <= t0 then
		return b
	end
	if now <= t0 then
		return a
	end
	return a:Lerp(b, (now - t0) / (t1 - t0))
end

-- === Capturing ===============================================================
--[[ THE LEAP (owner: "you go in and jump into one"). With a car you can steal inside `Range`, it is
	outlined and tagged JUMP!; press jump (Space, the mobile jump button, gamepad A) and you leap in an
	arc with a front flip and land on its roof, aimed at where the car WILL be when you come down (the
	leg is deterministic, so the prediction is exact). On the roof the client asks the server; the car
	goes into the hotbar on "ok", and you are put in its driver's seat (`Drive`).

	The arc is all client-side presentation. What the server checks is unchanged: the character is
	where the car is, give or take `Radius + Slack + speed x LatencySeconds`. ]]
CollectorConfig.Leap = {
	Range = 42, -- studs, flat, from you to the car at the moment you press jump
	Speed = 60, -- studs/s along the ground: sets the flight time from the distance
	Time = { 0.5, 0.85 }, -- flight seconds, clamped
	Height = { 9, 16 }, -- arc peak over the straight line, short jump .. long jump
	Ride = 0.45, -- seconds on the roof waiting for the server before letting go regardless
	Fov = 8, -- degrees added to the camera FOV mid-flight
}

CollectorConfig.Capture = {
	Radius = 13,
	--[[ SERVER SLACK. The server checks the distance between the character and where the car is
		NOW by the shared clock. The client measured it up to a ping ago against a car that has since
		moved, so the server allows `Radius + Slack + speed x LatencySeconds`. ]]
	Slack = 8,
	LatencySeconds = 0.6,
	Cooldown = 0.35, -- per player, between accepted requests
	Source = "Capture", -- the `awardCar` source; not a carry source, so the car lands in the hotbar
}

--[[ DRIVING (owner: "give me a starter car ... let me drive it until i decide to jump into another").
	Both halves are `LobbyCarService`'s open-world car, one per player:
	  • Starter: whenever you have no car (join, respawn, Back to Base, sold it), your start car
	    (`StartCarService:carFor`, world 1) is parked beside you a moment later. Free; not added to the
	    inventory.
	  • Swap: a capture also replaces your car with the one you landed on, where it was, and seats you.
	    Space in the driver's seat with a car highlighted leaps from your car to it. ]]
CollectorConfig.Drive = {
	Starter = true,
	StarterDelay = 1.5, -- seconds after spawn / despawn, so LobbyCarService's own respawn clean-up runs first
	Swap = true,
	SeatDelay = 0.1,
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
