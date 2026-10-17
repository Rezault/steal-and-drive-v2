local PlayerProfile = {}
PlayerProfile.__index = PlayerProfile

--[[ PROFILESTORE MESSAGES ("global updates"), by kind.

	A message is a table whose FIRST ELEMENT NAMES IT — `{ "Cash", 25000, "Gvistic" }` — and the
	handler for a name is registered by whichever service owns the thing being written. That is what
	makes this worth having as a registry rather than as an if-chain in `new`: the data layer never
	learns what a cash grant is, and `GarageService` stays the only thing in the game that writes
	`Cash` even when the write arrives from another server.

	Register at REQUIRE TIME. `Data:initialize()` opens the first session, and a session replays its
	queued messages the instant it opens, so a handler registered in a service's `init` is a handler
	that might miss the first delivery.

	A handler answers TRUE when the message has landed and may be discarded. Anything else leaves it
	in the queue, and ProfileStore replays it the next time this player's profile opens a session —
	which is exactly what "give this to them when they are next on" has to mean. ]]
local Handlers: { [string]: (profile: any, message: { any }) -> boolean } = {}

--- Register the handler for one kind of ProfileStore message. See the block above.
function PlayerProfile.OnMessage(kind: string, handler: (profile: any, message: { any }) -> boolean)
	Handlers[kind] = handler
end

function PlayerProfile.new(player, profile, replica)
	local self = setmetatable({}, PlayerProfile)

	self._player = player
	self._profile = profile
	self._replica = replica

	--[[ ProfileStore runs this in its own thread (`task.spawn`), so a handler may yield — and the
		cash one does, because a message queued in the datastore is replayed before the services
		that apply it have finished wiring the player up.

		An unknown kind is deliberately NOT processed: it is either a message from a newer build or
		one whose handler has not registered, and both are better replayed than eaten. ]]
	self._profile:MessageHandler(function(message, processed)
		local kind = if type(message) == "table" then message[1] else nil
		local handler = if type(kind) == "string" then Handlers[kind] else nil
		if handler and handler(self, message) == true then
			processed()
		end
	end)

	return self
end

-- Define custom player profile functions here:

--[[```lua
-- Example:
function PlayerProfile:addCash(amount: number)
	if not self:IsActive() then return end -- Check if the profile is still active

	local retrieved = self:Get("Cash")
	local newAmount = retrieved + amount

	if newAmount < 0 then
		newAmount = 0
	end

	self:Set("Cash", newAmount)
end
```]]

-- INTERNAL API

--[[ A string path is a RECURSIVE KEY SEARCH; an array path is an exact walk.

	Prefer the array form for anything nested. The search is convenient for a unique top-level key
	and genuinely ambiguous below that — it returns whichever matching key it reaches first, and
	table iteration order is not something to build on. ]]
function PlayerProfile:Get(path: string | { string }, tableToSearch: {}?): any
	if not self:IsActive() then
		return
	end

	if typeof(path) == "string" then
		return self:_getRecursive(path, tableToSearch)
	elseif typeof(path) == "table" then
		local currentTable = self._profile.Data
		for _, key in path do
			if currentTable[key] == nil then
				return nil
			end
			currentTable = currentTable[key]
		end
		return currentTable
	end
	return nil
end

function PlayerProfile:_getRecursive(keyToGet: string, tableToSearch: {}): any
	tableToSearch = tableToSearch or self._profile.Data
	for key, value in tableToSearch do
		if key == keyToGet then
			return value
		end

		--[[ Recurse into `_getRecursive` DIRECTLY, not back through `Get`.

			`Get(path, tableToSearch)` used to be called here with two arguments while its signature
			took one, so the sub-table was dropped and the search restarted from the profile root —
			an infinite recursion the first time a template held a nested table before the key being
			looked for. The template was flat until the garage landed, which is the only reason it
			had never fired. ]]
		if typeof(value) == "table" then
			local result = self:_getRecursive(keyToGet, value)
			if result ~= nil then
				return result
			end
		end
	end

	return nil
end

-- Same two forms, and the same advice, as `Get` above.
function PlayerProfile:Set(path: string | { string }, value: any, tableToSearch: {}?, keyPath: { string }?): any
	if not self:IsActive() then
		return nil
	end

	if typeof(path) == "string" then
		return if self:_setRecursive(path, value, tableToSearch, keyPath) then value else nil
	elseif typeof(path) == "table" then
		self._replica:Set(path, value)
		return value
	end

	return nil
end

function PlayerProfile:_setRecursive(keyToSet: string, valueToSet: any, tableToSearch: {}, path: { string })
	tableToSearch = tableToSearch or self._profile.Data
	path = path or {}

	for key, currentValue in tableToSearch do
		local newPath = { unpack(path) }
		table.insert(newPath, key)

		if key == keyToSet then
			-- tableToSearch[key] = valueToSet
			self._replica:Set(newPath, valueToSet)
			return true
		end

		-- Directly, not back through `Set` — see the note in `_getRecursive`. The same dropped
		-- arguments made this restart from the profile root and recurse forever.
		if typeof(currentValue) == "table" then
			if self:_setRecursive(keyToSet, valueToSet, currentValue, newPath) then
				return true
			end
		end
	end

	return false
end

function PlayerProfile:Increment(currencyPath: string | { string }, amount: number): any
	local retrieved = self:Get(currencyPath)
	local newAmount = retrieved + amount

	if newAmount < 0 then
		newAmount = 0
	end

	return self:Set(currencyPath, newAmount)
end

function PlayerProfile:Decrement(currencyPath: string | { string }, amount: number): any
	local retrieved = self:Get(currencyPath)
	local newAmount = retrieved - amount

	if newAmount < 0 then
		newAmount = 0
	end

	return self:Set(currencyPath, newAmount)
end

function PlayerProfile:CanAfford(currencyPath: string | { string }, cost: number): boolean
	local currentAmount = self:Get(currencyPath) or 0
	return currentAmount >= cost
end

function PlayerProfile:GetPlayer()
	return self._player
end

function PlayerProfile:GetUserId()
	return self._userId
end

function PlayerProfile:GetProfile()
	return self._profile
end

function PlayerProfile:GetReplica()
	return self._replica
end

function PlayerProfile:IsActive()
	return self._profile:IsActive()
end


return PlayerProfile
