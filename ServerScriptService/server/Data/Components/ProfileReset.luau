-- One-time global progress reset. Applied before replication or gameplay services read a save.
local Reset = {}
Reset.Version = "2026-10-14-02"
Reset.VersionKey = "GlobalResetVersion"

-- Receipt deduplication, gifted entitlements, and unspent paid products survive progress resets.
Reset.Preserve = { "PurchaseIdCache", "Passes", "ExtraLives", "OfflineBoosts", "RandomCarPulls", "PendingGifts" }

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, child in value do result[key] = copy(child) end
	return result
end

function Reset.apply(data, template): boolean
	if data[Reset.VersionKey] == Reset.Version then return false end
	local preserved = {}
	for _, key in Reset.Preserve do preserved[key] = copy(data[key]) end
	local fresh = copy(template)
	for key, value in preserved do fresh[key] = value end
	fresh[Reset.VersionKey] = Reset.Version
	table.clear(data)
	for key, value in fresh do data[key] = value end
	return true
end

return Reset

