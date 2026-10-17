--[[
	CarRarity  (shared)
	-------------------
	How RARE this car is in its world, in one word and one colour: COMMON / UNCOMMON / RARE / EPIC /
	LEGENDARY (car-type words until 2026-10-08 — `TrafficConfig.RarityWords` has why).

	THIS IS A LOOKUP, NOT A LADDER. It decides nothing. `TrafficConfig` already resamples its five
	hand-tuned bands onto however many rungs a world has and records the nearest one as `Rarity` on
	the tier — it says in as many words that it exists because a shop wants a rarity to print rather
	than a model name. All this file does is turn a body name into that word and give the word a
	colour, so move a car in `WorldConfig` and its rarity moves with it.

	IT LIVES HERE BECAUSE TWO SCREENS PRINT IT. The Index page was the first and had all of this
	inside it as a private roster walk plus a private colour table; the Cars Inventory is the second,
	and a second private copy is a second ladder to keep in step. Both now read this. A third caller
	needs no more than the two functions at the bottom.

	=== THE COLOUR IS THE ONLY THING THIS FILE ADDS ============================

	And it is keyed to the band's INDEX rather than its name — a band is a rung on a ramp, and the
	ramp is what the colour has to run along. `Colours` is one entry per band, bottom to top, and it
	is the one thing that has to grow if `TrafficConfig.Bands` ever does; a band past the end of it
	CLAMPS TO THE TOP rather than drawing white, which is wrong quietly instead of loudly.

	GREY, GREEN, BLUE, PURPLE, GOLD is not a taste call: it is the ramp every game with a rarity on a
	card has taught players to read, and a collection screen is the last place to be original about
	it. What IS a call is that all five are picked to hold against the kit's dark navy card face
	rather than against white — the greys are cool and light, the blue is well clear of the kit's own
	`#0066FF` title bar so a rarity never reads as a piece of chrome, and the top of the ramp is gold
	because the top of a world is the thing the player is pushing for.

	IT IS NOT A COLOUR ON THE CAR. `TrafficConfig` records at length why a tier stopped owning a
	paint pool — paint is per car and per spawn now, and a colour that meant "supercar" made two
	Chargers look like two different rungs. This is a colour on a WORD, in a panel, and it says what
	the word says. Nothing here reaches the road.

	HOUSE RULE: no wiki-style double-bracket links in this comment — the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local CarRarity = {}

-- One colour per band of `TrafficConfig.Bands`, bottom to top. See the header.
CarRarity.Colours = {
	Color3.fromRGB(154, 166, 191), -- Common
	Color3.fromRGB(85, 214, 122), -- Uncommon
	Color3.fromRGB(79, 168, 255), -- Rare
	Color3.fromRGB(192, 107, 255), -- Epic
	Color3.fromRGB(255, 197, 61), -- Legendary
}

--[[ body -> { band, name }, built once at load because it is a fact about the config and cannot
	change while a session is running.

	DEDUPED ACROSS WORLDS, FIRST WORLD WINS. No body appears twice today (8 + 7 + 7 + 7 = 29, and
	`TrafficConfig.AllBodies` agrees), but nothing stops a designer putting one car on two ladders,
	and a car would then have two rarities depending on which loop finished last.

	IT WALKS THE TIERS rather than `bodiesFor`, which is where the rarity comes from at all. Reading
	the tier is also what keeps the per-car escape hatch honest: a car whose `CarConfig` `Traffic`
	override moves it is moved here too, because the override is applied to the tier before this
	ever sees it. ]]
local BY_BODY: { [string]: { band: number, name: string } } = {}
do
	for index in WorldConfig.Worlds do
		for _, tier in TrafficConfig.tiersFor(index) do
			for _, body in tier.Bodies or {} do
				if not BY_BODY[body] then
					-- Both defaulted rather than assumed: a hand-written tier need not carry either,
					-- and a lookup that throws at load takes every page in the kit down with it.
					BY_BODY[body] = { band = tier.Band or 1, name = tier.Rarity or "" }
				end
			end
		end
	end
end

--- The band's colour, clamped to the ends of the ramp. Never nil.
function CarRarity.colourOf(band: unknown): Color3
	local index = if type(band) == "number" and band == band then math.clamp(math.floor(band), 1, #CarRarity.Colours) else 1
	return CarRarity.Colours[index]
end

--[[ A body's rarity: `("Legendary", 5)`.

	`("", 1)` for a body on no ladder — a car from a build that renamed it, a hand-edited profile.
	The EMPTY STRING rather than a word, so a caller can hide the line instead of printing a rarity
	this game does not have; the band still answers 1 so `colourOf` is safe to call unconditionally. ]]
function CarRarity.of(body: unknown): (string, number)
	local resolved = type(body) == "string" and (WorldConfig.LegacyBodies[body] or body)
	local entry = resolved and BY_BODY[resolved]
	if not entry then
		return "", 1
	end
	return entry.name, entry.band
end

--- The same answer as `of`, already coloured — for the common case of filling in one label.
function CarRarity.labelOf(body: unknown): (string, Color3)
	local name, band = CarRarity.of(body)
	return name, CarRarity.colourOf(band)
end

return CarRarity
