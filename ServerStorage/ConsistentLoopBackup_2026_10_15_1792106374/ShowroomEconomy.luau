-- Deterministic offline estimator for distinct-bay visits, exclusive reservations,
-- customer slots, arrival throttling, walking and dwell time. Geometry and 1.2
-- route factor match the reviewed scenario model; this is not live pathfinding.
local ShowroomEconomy = {}
local cache = {}
local cacheCount = 0
local positions = {
 Vector2.new(-24.008, -6), Vector2.new(-24.008, 11), Vector2.new(-26.750, 22.050),
 Vector2.new(-15.600, 18.808), Vector2.new(1.400, 18.808), Vector2.new(18.400, 18.808),
}

local function sample(cfg, values, slots, indices, efficiencies, seed)
 local rng = Random.new(seed)
 local busy, events = {}, {}
 local active, nextSpawn, sequence, earnings, visitors = 0, 0, 0, 0, 0
 local warmup, horizon = 60, 960
 local entrance = Vector2.new(cfg.Arrival.LocalX, cfg.Arrival.LocalZ)
 local function add(time, kind, npc, bay)
  sequence += 1
  local event = {time = time, kind = kind, npc = npc, bay = bay, sequence = sequence}
  local i = #events + 1
  events[i] = event
  while i > 1 do
   local parent = math.floor(i / 2)
   if events[parent].time < time or (events[parent].time == time and events[parent].sequence < sequence) then break end
   events[i], events[parent] = events[parent], events[i]
   i = parent
  end
 end
 local function pop()
  local first = events[1]
  local last = table.remove(events)
  if #events > 0 then
   events[1] = last
   local i = 1
   while i * 2 <= #events do
    local left, right = i * 2, i * 2 + 1
    local j = left
    if right <= #events and (events[right].time < events[left].time or (events[right].time == events[left].time and events[right].sequence < events[left].sequence)) then j = right end
    local a, b = events[i], events[j]
    if a.time < b.time or (a.time == b.time and a.sequence <= b.sequence) then break end
    events[i], events[j] = b, a
    i = j
   end
  end
  return first
 end
 local function travel(a, b) return (a - b).Magnitude * 1.2 / math.max(1, cfg.Walk.Speed) end
 local function choose(time, npc)
  local total, pool = 0, {}
  for i, value in values do
   if value > 0 and not busy[i] and not npc.seen[i] then
    total += value
    table.insert(pool, i)
   end
  end
  if #pool == 0 or npc.left <= 0 then
   add(time + travel(npc.position, entrance) + cfg.Visit.TurnSeconds, "leave", npc)
   return
  end
  local roll, bay = rng:NextNumber() * total, pool[#pool]
  for _, i in pool do
   roll -= values[i]
   if roll <= 0 then bay = i; break end
  end
  busy[bay], npc.seen[bay] = true, true
  npc.left -= 1
  local index = if indices then indices[bay] else bay
  index = math.max(1, index or bay)
  local target = positions[(index - 1) % 6 + 1]
  local walk = travel(npc.position, target) + (if index > 6 then 8 else 0)
  npc.position = target
  add(time + walk + cfg.Visit.TurnSeconds + cfg.rollRange(cfg.Visit.LookSeconds, rng), "look", npc, bay)
 end
 add(0, "spawn")
 while #events > 0 and events[1].time <= horizon do
  local event = pop()
  local time, npc, bay = event.time, event.npc, event.bay
  if event.kind == "spawn" then
   if active < math.min(slots, #values) and time >= nextSpawn then
    active += 1
    if time >= warmup then visitors += 1 end
    nextSpawn = time + cfg.rollRange(cfg.Crowd.ArrivalGap, rng)
    choose(time, {seen = {}, left = rng:NextInteger(cfg.Visit.PerBay.Min, cfg.Visit.PerBay.Max), position = entrance + Vector2.new(rng:NextNumber(-cfg.Arrival.Spread, cfg.Arrival.Spread), 0)})
   end
   add(time + cfg.Crowd.CheckInterval, "spawn")
  elseif event.kind == "look" then
   local liked = rng:NextNumber() < cfg.Visit.LikeChance
   if liked then
    local amount = cfg.tipFor(values[bay], rng)
    if time >= warmup then earnings += amount * (if efficiencies then efficiencies[bay] else cfg.Offline.Efficiency) end
   end
   local react = if liked or rng:NextNumber() < cfg.Visit.BrowseChance then cfg.Visit.ReactSeconds else 0
   add(time + react, "release", npc, bay)
  elseif event.kind == "release" then
   busy[bay] = nil
   choose(time, npc)
  else
   active -= 1
  end
 end
 return earnings / (horizon - warmup), visitors / (horizon - warmup)
end

function ShowroomEconomy.estimate(cfg, values: {number}, slots: number, seconds: number, indices: {number}?, efficiencies: {number}?): (number, number)
 if #values == 0 or slots <= 0 or seconds <= 0 or seconds ~= seconds then return 0, 0 end
 local entries = {tostring(slots)}
 for i, value in values do
  if value ~= value or value < 0 or value == math.huge then return 0, 0 end
  local efficiency = if efficiencies then efficiencies[i] else cfg.Offline.Efficiency
  if type(efficiency) ~= "number" or efficiency ~= efficiency or efficiency < 0 or efficiency > 1 then return 0, 0 end
  table.insert(entries, tostring(value) .. "@" .. tostring(if indices then indices[i] else i) .. "*" .. tostring(efficiency))
 end
 local key = table.concat(entries, ";")
 local result = cache[key]
 if not result then
  local rate, visitors = 0, 0
  for seed = 1, 8 do
   local cashRate, visitRate = sample(cfg, values, slots, indices, efficiencies, 300000 + seed)
   rate += cashRate / 8
   visitors += visitRate / 8
  end
  result = {rate = rate, visitors = visitors}
  if cacheCount >= 128 then table.clear(cache); cacheCount = 0 end
  cache[key] = result
  cacheCount += 1
 end
 local counted = math.clamp(seconds, 0, cfg.Offline.CapSeconds)
 return math.floor(result.rate * counted), math.floor(result.visitors * counted)
end
return ShowroomEconomy
