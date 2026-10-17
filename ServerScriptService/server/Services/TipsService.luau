--[[
	TipsService  (server)
	---------------------
	The clock behind the chat tips: every few minutes, pick one nobody has seen lately and tell the
	room which one it is.

	=== IT DOES NOT WRITE THE MESSAGE, AND IT CANNOT ===========================================

	`TextChannel:DisplaySystemMessage` is a CLIENT call — `TipsConfig`'s header has the full reason
	and why `SendAsync` is not a substitute. So everything this file does ends at a `FireAll` of an
	index, and `TipsController` is what a player actually reads. If tips have stopped appearing, the
	log line below tells you which half to go and look at: this service says what it sent.

	=== THE SHUFFLED BAG =======================================================================

	Tips come out of a BAG, not a `math.random` per tick. Random-with-replacement over thirteen
	entries repeats within three draws about a third of the time, and a player who sees the same tip
	twice in seven minutes concludes there are two tips. So the whole list is shuffled, drawn down
	to empty, then reshuffled — every tip shows once per pass, in an order that changes each time.

	THE RESHUFFLE PROTECTS THE SEAM. Reshuffling naively can put the tip that just ended one pass at
	the head of the next, which is the one repeat the bag exists to prevent, so a new bag whose first
	entry is the last one drawn gets that entry swapped away.

	=== WHAT IT DELIBERATELY DOES NOT DO =======================================================

	No per-player state, no "seen" set on the profile, no catch-up for somebody who joined between
	two tips. A tip is ambient — it is the room being talked to, not a lesson anybody is being taken
	through — and the moment it needs to know who has read what it stops being this feature and
	starts being a tutorial, which `TutorialService` already is.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local TipsConfig = require(ReplicatedStorage.shared.Configs.TipsConfig)

local TipsService = Shard.new("TipsService")

TipsService:withRemoteEvents({
	--[[ server -> client (index): print this one. Broadcast, and carrying a number rather than the
		sentence for the reason in `TipsConfig`'s header. ]]
	"ChatTip",
})

-- === The bag ================================================================

--[[ Refill and shuffle, keeping the seam honest — see the header.

	Fisher-Yates, downward, which is the only shuffle worth writing: `table.sort` with a random
	comparator is not one, and on Luau it can error outright when the comparator disagrees with
	itself about two elements. ]]
function TipsService._refill(self)
	local bag = {}
	for index = 1, #TipsConfig.Tips do
		bag[index] = index
	end

	for index = #bag, 2, -1 do
		local swap = self._random:NextInteger(1, index)
		bag[index], bag[swap] = bag[swap], bag[index]
	end

	--[[ The seam: a fresh bag that opens on the tip the last one closed with would show it twice in
		a row, which is the single repeat this whole mechanism exists to avoid. Swapped with the far
		end rather than reshuffled, because one more shuffle can land in the same place. ]]
	if #bag > 1 and bag[#bag] == self._last then
		bag[#bag], bag[1] = bag[1], bag[#bag]
	end

	self._bag = bag
end

--- The next tip's index. Draws from the tail so the bag can shrink without a shift.
function TipsService._draw(self): number?
	if #TipsConfig.Tips == 0 then
		return nil
	end
	if #self._bag == 0 then
		self:_refill()
	end

	local index = table.remove(self._bag)
	self._last = index
	return index
end

-- === Sending ================================================================

--[[ One tip out to everybody, if there is anybody to send it to.

	THE EMPTY SERVER IS SKIPPED WITHOUT DRAWING. Drawing and discarding would burn a tip out of the
	bag that nobody saw, which over a quiet hour empties and reshuffles the whole list against an
	audience of nobody — and makes the log read as though tips are being sent when they are not. ]]
function TipsService._send(self)
	if #Players:GetPlayers() < TipsConfig.MinPlayers then
		return
	end

	local index = self:_draw()
	if not index then
		return
	end

	self:getRemoteEvent("ChatTip"):FireAll(index)

	--[[ Logged with the index AND the text, so "tips stopped" can be answered without a client
		attached: a log line with no tip in the window means the controller's half is where to look,
		and no log line at all means this loop is what died. `%d of %d` also makes a bag that is
		drawing the same entry twice visible at a glance. ]]
	self.log:info(string.format("Tip %d of %d: %s", index, #TipsConfig.Tips, TipsConfig.Tips[index]))
end

--[[ The loop. `task.delay` chained through a Trove-owned thread rather than a Heartbeat
	accumulator, which is what `OfflineService._touchLoop` uses — the difference is that this fires
	every few MINUTES, and a per-frame accumulator to measure three and a half minutes is sixty
	comparisons a second to answer a question a sleeping thread answers for free. ]]
function TipsService._loop(self)
	local running = true

	task.spawn(function()
		task.wait(TipsConfig.FirstDelay)
		while running do
			self:_send()
			task.wait(TipsConfig.Interval)
		end
	end)

	--[[ The flag rather than `task.cancel`: the thread is almost always parked inside a `task.wait`
		when a cleanup lands, and cancelling a thread mid-wait is how you get a Trove that throws
		during teardown. Checked after the wait, so a stopped loop exits at its next tick and sends
		nothing in between. ]]
	return function()
		running = false
	end
end

-- === Lifecycle ==============================================================

TipsService:withLifecycle({
	init = function(self)
		self._bag = {} :: { number }
		self._last = nil :: number?
		--[[ Its own `Random` rather than the global `math.random`, so the tip order cannot be
			perturbed by — or perturb — anything else that draws in this server. Unseeded, which
			means seeded from the clock: two servers starting together get different orders. ]]
		self._random = Random.new()
		self._trove = Trove.new()
	end,

	start = function(self)
		if not TipsConfig.Enabled then
			self.log:info("Disabled by config — no chat tips.")
			return
		end

		if #TipsConfig.Tips == 0 then
			self.log:warn("Enabled, but the tip list is empty — nothing will ever be sent.")
			return
		end

		self._trove:Add(self:_loop())
	end,
})

TipsService:withCleanup(function()
	if TipsService._trove then
		TipsService._trove:Destroy()
	end
end)

return TipsService
