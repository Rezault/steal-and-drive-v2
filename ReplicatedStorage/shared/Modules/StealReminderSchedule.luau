-- Shared scheduling for the two steal reminders. One message owns the teaching slot.
local Schedule = {}
local untilAt, nextAt, owner = 0, 0, nil
function Schedule.reset()
 untilAt, nextAt, owner = 0, 0, nil
end
function Schedule.canShow(who, now)
 now = now or os.clock()
 return now >= untilAt and now >= nextAt
end
function Schedule.claim(who, duration, cooldown, now)
 now = now or os.clock()
 if not Schedule.canShow(who, now) then return false end
 owner, untilAt, nextAt = who, now + duration, now + cooldown
 return true
end
function Schedule.dismiss(who)
 if owner == who then untilAt = 0 end
end
function Schedule.isShowing(who, now)
 return owner == who and (now or os.clock()) < untilAt
end
return Schedule
