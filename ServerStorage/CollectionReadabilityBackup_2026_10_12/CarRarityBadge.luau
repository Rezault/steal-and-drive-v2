--[[
	CarRarityBadge  (client)
	------------------------
	The writing over a traffic car: its band's word in that band's colour, the odds of the road
	giving you one underneath, and no panel behind either. `RarityBadgeConfig` is every number and
	the argument for each, including why there is no box; this file builds the thing and fills it in.

	=== ONE MARKER PER POOLED SHELL, BUILT ONCE AND REPAINTED =================================

	The same contract `CarMutation`'s badge and `TrafficController`'s lane-change arrow are on, and
	for the same reason: one shell is dressed as forty different cars over a race, and none of those
	forty may allocate. `build` is called once, from `_buildRecord`, on a clone that is not in the
	workspace yet. `set` and `hide` are property writes on instances that already exist.

	So there are exactly three calls, and the pooling rules fall out of them:

	    build(car)                        once, when the shell is made
	    set(car, tier, body, world, luck) per spawn, after the mutation has been applied
	    hide(car)                         on release, so a recycled shell cannot come back out of the
	                                      pool still claiming to be the supercar it used to be

	`hide` matters more than it looks. A shell that reached the pool still saying "1 IN 43" would
	come back out as the next ordinary Civic still saying it, which is the class of bug the mutation,
	the paint and the give-mass all carry their own reset for.

	=== EVERY SIZE IS SCALE, AND THAT IS NOT A STYLE CHOICE ===================================

	A billboard's children are laid out in a pixel box the engine resizes with range, so anything
	measured in pixels is a part of the marker that stays put while the rest of it shrinks. Two
	things are pixels and both are avoided here:

	  • `UIStroke.Thickness`. The outline that looks right on a car twenty studs away swallows the
	    letters whole on one at three hundred. The type is outlined with Roblox's own text stroke
	    instead, which is rendered WITH the glyphs and so holds its proportion at every range.
	  • the Offset half of any `UDim2`. Nothing here has one.

	This is also most of why the panel version of this marker was never going to keep the kit's
	chunky rims: a kit rim is a `UIStroke`, and a `UIStroke` cannot ride a billboard.

	=== IT STACKS ABOVE THE MUTATION BADGE, AND ONLY THIS FILE KNOWS THAT =====================

	A mutated car can wear both. The mutation badge sits at `WeatherConfig.Badge.Clearance` above the
	roof and this goes above IT, which keeps the dependency one way: `CarMutation` has no idea this
	file exists and cannot be broken by it. The cost is that `set` has to run after
	`CarMutation.apply` has stamped the attribute, which `TrafficController._spawn` does.

	=== THE ODDS ARE THE ROLL, CACHED PER WORLD AND PER LUCK ==================================

	`TrafficConfig.chancesFor` is a resample plus two passes over the ladder, so calling it per spawn
	would be a table built for every car the road produces. It is cached on (world, luck) instead,
	which is one entry for almost every session: a player is in one world, and luck only moves when
	a pass is bought mid-race. The cache is a fact about the config and the player, so nothing about
	a race invalidates it.

	HOUSE RULE: no wiki-style double-bracket links in this comment. The closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RarityBadgeConfig = require(ReplicatedStorage.shared.Configs.RarityBadgeConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local CarMutation = require(ReplicatedStorage.shared.Modules.CarMutation)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)

local CarRarityBadge = {}

--- The name the marker is built under, so a strip finds what a build left and anything walking a car
--- in the Explorer can tell what it is looking at.
CarRarityBadge.Name = "RarityBadge"

--- Where `build` parks the roof height it measured, so `set` never has to walk the model again. A
--- pooled shell is one body for the whole session, so the answer cannot change.
local ROOF_ATTRIBUTE = "RarityRoof"

--- `TextScaled` would sooner break a caption onto a second line than pick a smaller font, so every
--- space in a word becomes an unbreakable one. The project's standing answer; see `CarMutation`.
local NBSP = utf8.char(0xA0)

--[[ The bob tween driving each marker, so a re-arm can cancel the one it replaces. WEAK-KEYED, like
	`CarMutation`'s: a marker destroyed with the race it belonged to drops out of here on its own,
	which is what stops a module-level table outliving every race in the session. ]]
local bobs: { [BillboardGui]: Tween } = setmetatable({}, { __mode = "k" }) :: any

-- === The odds ===============================================================

--[[ body -> chance, for one world at one luck. See the header on why it is cached and not computed.

	The guard on the table's size is not really about memory, it is about a build that starts writing
	a float into the key: twelve entries is far more than a session can legitimately produce, so
	passing it means something upstream has changed and the cache should stop growing rather than
	quietly become a leak. ]]
local oddsCache: { [string]: { [string]: number } } = {}
local oddsCacheCount = 0

local function chanceTable(world: unknown, luck: number): { [string]: number }
	local index = WorldConfig.resolve(world)
	local key = string.format("%d:%.3f", index, luck)
	local cached = oddsCache[key]
	if cached then
		return cached
	end

	local map = {}
	for _, chance in TrafficConfig.chancesFor(index, luck) do
		map[chance.Body] = chance.Chance
	end

	if oddsCacheCount >= 12 then
		oddsCache = {}
		oddsCacheCount = 0
	end
	oddsCache[key] = map
	oddsCacheCount += 1
	return map
end

--[[ "43", "1,200". Grouped in threes because the top of a long ladder can run into four figures and
	an ungrouped one is a number nobody reads at speed.

	Floored at 1: a car the road gives you more often than every other car is still "1 in 1" rather
	than "1 in 0", which is not a sentence. ]]
local function grouped(value: number): string
	local text = tostring(math.max(1, math.round(value)))
	while true do
		local replaced
		text, replaced = string.gsub(text, "^(%-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return text
end

--[[ PUBLIC. What this body's odds say, already written out: "1 IN 43", or the empty string for a
	body this world's road cannot produce at all.

	The empty string rather than a zero or a dash, so a caller can drop the line instead of printing
	odds the game does not have. `CarRarity.of` answers the same way for the same reason. ]]
function CarRarityBadge.oddsText(body: unknown, world: unknown, luck: number?): string
	if type(body) ~= "string" then
		return RarityBadgeConfig.UnknownOdds
	end
	local factor = if RarityBadgeConfig.Luck then (tonumber(luck) or 1) else 1
	local chance = chanceTable(world, factor)[body]
	if not chance or chance <= 0 then
		return RarityBadgeConfig.UnknownOdds
	end
	return string.format(RarityBadgeConfig.OddsFormat, grouped(1 / chance))
end

-- === Finding somewhere to put it ============================================

--[[ The part the marker hangs off, best first.

	`Hit` is a traffic shell's hull, which is the common case by a distance and is ideal: it is a
	car-sized box whose centre is the car's centre, so the lift arithmetic below and the mutation
	badge's agree about where the roof is. Everything after it is a fallback for a model that is not
	a traffic shell, and the last one is the LARGEST part rather than the first found, because the
	first part of a stripped body is as often a wing mirror as a roof. ]]
local function hostOf(car: Model): BasePart?
	local hit = car:FindFirstChild("Hit")
	if hit and hit:IsA("BasePart") then
		return hit
	end
	if car.PrimaryPart then
		return car.PrimaryPart
	end

	local best, bestVolume = nil, 0
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") then
			local size = part.Size
			local volume = size.X * size.Y * size.Z
			if volume > bestVolume then
				best, bestVolume = part, volume
			end
		end
	end
	return best
end

--- The marker on this car, if it has one. Never builds; `build` is the only thing that does.
local function badgeOf(car: Model): BillboardGui?
	local host = hostOf(car)
	local existing = host and host:FindFirstChild(CarRarityBadge.Name)
	return if existing and existing:IsA("BillboardGui") then existing else nil
end

-- === Building ===============================================================

--[[ Two lines of type over a car, hidden, and never rebuilt. See the header.

	THERE IS NOTHING TO DRAW BUT THE LETTERS. No frame carries a colour, nothing has a `UICorner` and
	the billboard's `Size` is a box the type is fitted into rather than a shape anybody sees. That is
	the point of the marker and it is also what makes this function short: the whole look is a font,
	a colour per line and an outline, and all three are properties `set` writes.

	Both labels are built whatever `Lines` says. That setting is meant to be flipped in a playtest
	and looked at, and a mode change that had to rebuild instances would not survive a pooled shell. ]]
function CarRarityBadge.build(car: Instance?): BillboardGui?
	if not (RarityBadgeConfig.Enabled and car and car:IsA("Model")) then
		return nil
	end
	local model = car :: Model
	local existing = badgeOf(model)
	if existing then
		return existing
	end
	local host = hostOf(model)
	if not host then
		return nil
	end

	local cfg = RarityBadgeConfig

	local billboard = Instance.new("BillboardGui")
	billboard.Name = CarRarityBadge.Name
	--- The Scale component of a billboard's `Size` is STUDS. See the config's note on `Size`.
	billboard.Size = UDim2.fromScale(cfg.Size.X, cfg.Size.Y)
	billboard.SizeOffset = Vector2.new(0, 0)
	billboard.AlwaysOnTop = cfg.AlwaysOnTop
	billboard.LightInfluence = 0
	billboard.MaxDistance = cfg.MaxDistance
	billboard.ResetOnSpawn = false
	--- Born hidden AND born without a lift. Nothing shows it but `set`, and a marker enabled before
	--- it has been told which car it is on is a gold "1 IN 43" over whatever came out of the pool.
	billboard.Enabled = false

	for _, name in { "Rarity", "Odds" } do
		local label = Instance.new("TextLabel")
		label.Name = name
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(cfg.TextWidth, 0.3)
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.FontFace = cfg.FontFace
		--[[ Roblox's own text stroke rather than a `UIStroke`, and with no panel behind the letters
			it is the only thing holding them apart from the sky. The header has the measurement that
			forced it. ]]
		label.TextStrokeColor3 = cfg.TextStroke
		label.TextStrokeTransparency = cfg.TextStrokeTransparency
		label.RichText = cfg.RichText == true
		label.TextScaled = true
		label.Text = ""
		label.Parent = billboard
	end

	--[[ The roof, measured once. `GetExtentsSize` and not `GetBoundingBox`: the height is all that
		is wanted, and the pivot-relative frame the latter measures in has caught this project out
		before. Stored on the instance rather than in a table here so a marker carries its own answer
		and nothing has to be pruned when a race ends. ]]
	billboard:SetAttribute(ROOF_ATTRIBUTE, model:GetExtentsSize().Y * 0.5)

	billboard.Parent = host
	return billboard
end

-- === Filling it in ==========================================================

--- Put a line where the config says, in one write each. Called per spawn: `Lines` is live-tunable.
local function placeRow(label: TextLabel?, row: { Centre: number, Height: number })
	if not label then
		return
	end
	label.Position = UDim2.fromScale(0.5, row.Centre)
	label.Size = UDim2.fromScale(RarityBadgeConfig.TextWidth, row.Height)
	label.Visible = true
end

--[[ How high the type floats, in studs above the adornee.

	TWO CASES, and the config's `Clearance` and `Stack` are the two gaps. On a plain car the bottom of
	the box sits `Clearance` above the roof. On a mutated one it sits `Stack` above the top of the
	mutation badge, which is itself `WeatherConfig.Badge.Clearance` above the roof measured to its
	CENTRE. The two files express their gap differently and that is exactly the sort of difference
	that produces two markers inside each other, so the arithmetic is written out rather than shared.

	AND THE MUTATION BADGE MOVES. It floats on a looping tween of `Bob` studs, so the clearance it
	rests at is its LOWEST position and not its highest. Measured on a Molten Mustang: the badge read
	2.71 above the roof against a configured 2.4, which is most of the way up a 0.35 bob, and a gap
	worked out against the resting value alone would have closed to a fifth of what it says. So the
	whole bob is added, which costs nothing when it is switched off.

	A billboard is centred on its offset, so every case adds half this box's own height at the end. ]]
local function liftFor(model: Model, badge: BillboardGui): number
	local cfg = RarityBadgeConfig
	local roof = tonumber(badge:GetAttribute(ROOF_ATTRIBUTE)) or (model:GetExtentsSize().Y * 0.5)

	local mutated = model:GetAttribute(CarMutation.Attribute) ~= nil
	if mutated and WeatherConfig.Badge.Enabled then
		local mutation = WeatherConfig.Badge
		local mutationTop = roof + mutation.Clearance + mutation.Size.Y * 0.5 + math.max(mutation.Bob or 0, 0)
		return mutationTop + cfg.Stack + cfg.Size.Y * 0.5
	end
	return roof + cfg.Clearance + cfg.Size.Y * 0.5
end

--- The bob, armed once per height, cancelling the one it replaces. `CarMutation.setBadge`'s
--- mechanism exactly: two looping tweens on the same property do not blend, they fight.
local function applyLift(badge: BillboardGui, lift: number)
	local cfg = RarityBadgeConfig
	if not (cfg.Bob > 0 and lift > 0) then
		badge.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
		return
	end
	if badge:GetAttribute("BobLift") == lift then
		return
	end
	local previous = bobs[badge]
	if previous then
		previous:Cancel()
	end
	badge:SetAttribute("BobLift", lift)
	badge.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
	local tween = TweenService:Create(
		badge,
		TweenInfo.new(cfg.BobPeriod * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffsetWorldSpace = Vector3.new(0, lift + cfg.Bob, 0) }
	)
	bobs[badge] = tween
	tween:Play()
end

--[[ PUBLIC. Write the car this shell has just become over its roof, or put the writing away.

	`tier` is the rung the spawn rolled and `body` the car on it, and both are needed because they
	answer different halves: the BAND is a property of the rung (a variant shares its ladder car's
	band), and the ODDS are a property of the body (a variant is rarer than the car it stands beside).
	Passing the tier rather than looking the band up off the body also means a car moved between
	ladders cannot disagree with the road that just rolled it.

	Called AFTER `CarMutation.apply`, because the lift depends on whether the car wears a mutation
	badge. See the header. ]]
function CarRarityBadge.set(car: Instance?, tier: any, body: unknown, world: unknown, luck: number?)
	if not (car and car:IsA("Model")) then
		return
	end
	local model = car :: Model
	local cfg = RarityBadgeConfig

	local badge = badgeOf(model)
	if not (cfg.Enabled and badge) then
		if badge then
			badge.Enabled = false
		end
		return
	end

	--[[ The band, off the tier when there is one and off the body otherwise. `CarRarity.of` is the
		fallback rather than the source: it dedupes across worlds and first world wins, so a body on
		two ladders would read as the wrong band on one of them. A tier cannot be wrong that way. ]]
	local word, band
	if type(tier) == "table" and tier.Band then
		word, band = tostring(tier.Rarity or ""), tier.Band
	else
		word, band = CarRarity.of(body)
	end

	if band < cfg.MinBand then
		badge.Enabled = false
		return
	end

	local rarity = badge:FindFirstChild("Rarity") :: TextLabel?
	local odds = badge:FindFirstChild("Odds") :: TextLabel?
	if not (rarity or odds) then
		badge.Enabled = false
		return
	end

	local oddsText = CarRarityBadge.oddsText(body, world, luck)
	local wantRarity = cfg.Lines ~= "Odds" and word ~= ""
	local wantOdds = cfg.Lines ~= "Rarity" and oddsText ~= ""

	--[[ THE BAND'S COLOUR GOES IN THE LETTERS. That is the whole advert, and with no panel it is the
		only place left to put it. The number stays white under it so the two lines separate into
		"what it is" and "how rare" rather than reading as one coloured block. ]]
	local colour = CarRarity.colourOf(band)
	if rarity then
		rarity.Text = (string.gsub(string.upper(word), " ", NBSP))
		rarity.TextColor3 = colour
		rarity.Visible = wantRarity
	end
	if odds then
		odds.Text = oddsText
		--- White when the word is there to carry the band, the band's own colour when it is not:
		--- a lone number in white would say nothing about the car at all.
		odds.TextColor3 = if wantRarity then cfg.OddsColour else colour
		odds.Visible = wantOdds
	end

	--[[ One line or two. A marker whose second line has nothing to say centres the first over the car
		rather than leaving it parked high with empty air under it, which is what a car on no ladder
		and a `Lines` of "Odds" both produce. ]]
	if wantRarity and wantOdds then
		placeRow(rarity, cfg.RarityRow)
		placeRow(odds, cfg.OddsRow)
	elseif wantRarity then
		placeRow(rarity, cfg.SoloRow)
	elseif wantOdds then
		placeRow(odds, cfg.SoloRow)
	else
		--- Nothing to say at all, so say nothing.
		badge.Enabled = false
		return
	end

	applyLift(badge, liftFor(model, badge))
	badge.Enabled = true
end

--[[ PUBLIC. Put the writing away. Called on release, and it is not optional: see the header on what
	a shell that reaches the pool still naming a supercar comes back out as.

	IT TAKES THE BOB DOWN WITH IT, which matters only when `Bob` is switched on and matters a lot
	then: a looping tween keeps running on a disabled billboard, so a full pool of shells would sit
	in ReplicatedStorage animating markers nobody can see. Cancelling clears `BobLift` too, because
	that attribute is what `applyLift` uses to decide it has already armed this height. ]]
function CarRarityBadge.hide(car: Instance?)
	if not (car and car:IsA("Model")) then
		return
	end
	local badge = badgeOf(car :: Model)
	if not badge then
		return
	end
	badge.Enabled = false
	local tween = bobs[badge]
	if tween then
		tween:Cancel()
		bobs[badge] = nil
		badge:SetAttribute("BobLift", nil)
	end
end

return CarRarityBadge
