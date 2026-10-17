--[[
	LivePrice  (client)
	-------------------
	WHAT ROBLOX SAYS THIS PLAYER PAYS for a product or a pass. One cache for every Robux label.

	Every config carries a `Price`, and it is what the product was priced at when it was written.
	Roblox can move it: a price changed on the dashboard, regional pricing, price optimisation. On
	2026-10-15 every product was cheaper than its label said (the random car read 99 while the
	purchase window said 24), and a label that asks more than the window charges reads as a bait and
	switch. `GetProductInfo` on the CLIENT answers for this player, so the label says what the window
	will say. The server's answer is the base price, which is why nothing here is sent from a service.

	ASKED ONCE PER ID PER SESSION. Requests for an id already in flight join it rather than asking
	again. A failed call is remembered as failed and the caller keeps its config price: a label that
	is briefly stale beats a blank one, and a screen must never wait on this to draw.

	  LivePrice.peek(id, infoType?)          the answer if Roblox has given one, else nil. Never yields.
	  LivePrice.fetch(id, infoType?, done?)  ask, and call `done(price)` when the answer lands (at once
	                                         if known); `price` is nil if the call failed.
	  LivePrice.get(id, infoType?)           ask and wait. Yields.

	`infoType` defaults to `Enum.InfoType.Product`; a pass is `Enum.InfoType.GamePass`.
]]

local MarketplaceService = game:GetService("MarketplaceService")

local LivePrice = {}

--- Price by key, or false once a call has failed.
local answers: { [string]: number | false } = {}
--- Callbacks waiting on a call in flight, by key.
local waiting: { [string]: { (number?) -> () } } = {}

local function keyOf(id: number, infoType: Enum.InfoType): string
	return infoType.Name .. ":" .. tostring(id)
end

function LivePrice.peek(id: number, infoType: Enum.InfoType?): number?
	local answer = answers[keyOf(id, infoType or Enum.InfoType.Product)]
	return if answer then answer else nil
end

function LivePrice.fetch(id: number, infoType: Enum.InfoType?, done: ((number?) -> ())?)
	if type(id) ~= "number" or id == 0 then
		if done then
			task.spawn(done, nil)
		end
		return
	end
	local kind = infoType or Enum.InfoType.Product
	local key = keyOf(id, kind)
	if answers[key] ~= nil then
		if done then
			task.spawn(done, LivePrice.peek(id, kind))
		end
		return
	end
	local queue = waiting[key]
	if queue then
		if done then
			table.insert(queue, done)
		end
		return
	end
	--- Queued BEFORE the call starts: a call that fails without yielding answers inside this spawn.
	queue = if done then { done } else {}
	waiting[key] = queue
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, kind)
		end)
		answers[key] = if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then info.PriceInRobux else false
		waiting[key] = nil
		local price = LivePrice.peek(id, kind)
		for _, callback in queue do
			task.spawn(callback, price)
		end
	end)
end

function LivePrice.get(id: number, infoType: Enum.InfoType?): number?
	local kind = infoType or Enum.InfoType.Product
	if type(id) ~= "number" or id == 0 or answers[keyOf(id, kind)] ~= nil then
		return LivePrice.peek(id, kind)
	end
	local thread = coroutine.running()
	LivePrice.fetch(id, kind, function(price)
		--- Deferred: a call that fails without yielding answers before this thread has yielded.
		task.defer(thread, price)
	end)
	return coroutine.yield()
end

return LivePrice
