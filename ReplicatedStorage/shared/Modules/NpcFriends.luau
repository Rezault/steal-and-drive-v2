-- Friends-list APIs can return deleted-account placeholders with a loadable blank avatar.
-- Reject those before requesting avatars for customers, dealers or traffic drivers.
local NpcFriends = {}

local function deletedName(name: unknown): boolean
	if type(name) ~= "string" then
		return false
	end
	local normalized = string.gsub(string.lower(name), "[%s%p]", "")
	return normalized == "accountdeleted" or normalized == "contentdeleted" or normalized == "deletedaccount"
end

function NpcFriends.isUsable(item): boolean
	if type(item) ~= "table" then
		return false
	end
	local id = tonumber(item.Id)
	return id ~= nil and id > 0 and id < math.huge and id % 1 == 0
		and not deletedName(item.Username) and not deletedName(item.DisplayName)
end

return NpcFriends
