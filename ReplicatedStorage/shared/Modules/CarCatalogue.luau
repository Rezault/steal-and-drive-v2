--[[
	CarCatalogue  (shared)
	----------------------
	EVERY CAR THERE IS TO STEAL, in the order a collection screen lists them, and which of them a
	player has. No instances, no drawing: the roster, one parse and one caption, read by both index
	pages.

	It was `Pages/Index`'s private half until the kit migration needed a second collection screen to
	agree with it (`docs/NewUI-Migration-Plan.md`, "Shared logic"). A second screen deriving its own
	roster is how two screens end up counting "23/43 STOLEN" and "23/42 STOLEN" for the same player,
	and there is one trap in here that a fresh copy would walk straight into (note 2).

	THREE THINGS TO KNOW.

	1. THE ROSTER IS EVERY CAR IN EVERY WORLD, world order and then ladder order, variants beside the
	   rung they share. It walks `TrafficConfig.tiersFor` for each world, which is the same list the
	   road rolls its traffic off, so a car added to a world is on the collection with no edit here.

	   DEDUPED ACROSS WORLDS, FIRST WORLD WINS. No body appears twice today, but nothing stops a
	   designer putting one car on two ladders, and two slots for one car would count it twice.

	   Built once at load, because it is a fact about the config and cannot change while a session is
	   running. `Modules/CarRarity` walks the same tiers in the same order for the word and the colour;
	   this one keeps the WORLD, which is the one fact about a car only a collection screen wants.

	2. "STOLEN" IS `InventoryConfig.FoundAttribute`, NOT `GarageConfig.OwnedAttribute`, and that is
	   the trap. `FoundAttribute` ("CarsSeen") is every BODY a player has ever banked and it never
	   shrinks. `OwnedAttribute` is the collection as it stands, car KEYS, and it gets shorter when a
	   car is sold. A catalogue reading the second would un-tick a slot the moment somebody cashed in
	   their only Camaro, which is a completion meter that punishes you for using a feature. The two
	   names are confusingly close for historical reasons `InventoryConfig` spells out.

	   `parseFound` still goes through `GarageConfig.parseCarKey`, so it is right about a car key as
	   well as a body, and it throws the colour away: one slot is one body, and a Camaro in four
	   colours is one slot filled.

	3. THE RATE IS THE BASE RATE, the Dealership card's number to the character: `GarageConfig.rateOf`
	   off the body's tier, printed through `formatRate`. No bay level and no lot-wide upgrade, because
	   a car on a collection screen is a car that exists rather than a car parked somewhere earning.
	   A body the garage cannot price answers the EMPTY STRING, which is "print nothing" rather than
	   `$0.0/s`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local TrafficConfig = require(ReplicatedStorage.shared.Configs.TrafficConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local CarCatalogue = {}

export type Entry = {
	body: string,
	world: number,
}

--- Note 2. The player attribute a collection screen counts, as a name, so a page never spells it.
CarCatalogue.FoundAttribute = InventoryConfig.FoundAttribute

--[[ What a car you have not stolen is called on its card.

	THREE MARKS RATHER THAN ONE PER LETTER. Matching the name's length would leak it against a roster
	this small, and it would draw at a different size on every locked card, because those labels are
	TextScaled and a short string is limited by the box's height rather than its width. ]]
CarCatalogue.LockedText = "???"

--- Note 1. Every car, in listing order. Read-only by contract: two pages share this one table.
CarCatalogue.Roster = {} :: { Entry }
do
	local seen = {}
	for world in WorldConfig.Worlds do
		for _, tier in TrafficConfig.tiersFor(world) do
			for _, body in tier.Bodies or {} do
				if not seen[body] then
					seen[body] = true
					table.insert(CarCatalogue.Roster, { body = body, world = world })
				end
			end
		end
	end
end

--[[ A `FoundAttribute` value as a set of BODIES. Note 2. Anything unparseable reads as "nothing
	found", and a name that is not on the roster is simply a key nobody asks about. ]]
function CarCatalogue.parseFound(raw: unknown): { [string]: boolean }
	local found = {}
	for _, key in GarageConfig.split(raw) do
		local body = GarageConfig.parseCarKey(key)
		if body then
			found[body] = true
		end
	end
	return found
end

--[[ Note 3. `"$47/s"`, or `""` for a body the garage has no price for.

	WITHOUT PASSIVE INCOME (2026-09-28) it is the model's VALUE, `"$11,280"`, because a parked car no
	longer earns per second and a catalogue that still said so would be describing a game that is
	gone. The name stays: both Index pages call it, and it is still "the one money number the
	catalogue prints about a body". ]]
function CarCatalogue.rateText(body: string): string
	if not GarageConfig.Income.Passive then
		local value = GarageConfig.valueOf(GarageConfig.TierOfBody[body])
		return if value > 0 then GarageConfig.formatCash(value) else ""
	end
	local rate = GarageConfig.rateOf(GarageConfig.TierOfBody[body])
	return if rate > 0 then string.format("%s/s", GarageConfig.formatRate(rate)) else ""
end

return CarCatalogue
