-- Free Floater traffic availability. Owned cars retain their ability after the event.
-- One calendar month, America/New_York. End is exclusive (DST ends during this window).
local RoadsterEventConfig = {}
RoadsterEventConfig.StartsAt = 1792987200 -- Oct 26, 2026, 00:00 EDT
RoadsterEventConfig.EndsAt = 1795669200 -- Nov 26, 2026, 00:00 EST
function RoadsterEventConfig.isActive(now: number?): boolean
	local timestamp = if now ~= nil then now else os.time()
	return timestamp >= RoadsterEventConfig.StartsAt and timestamp < RoadsterEventConfig.EndsAt
end
return RoadsterEventConfig
