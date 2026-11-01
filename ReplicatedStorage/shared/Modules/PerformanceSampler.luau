-- Bounded histogram and hitch ring; no allocation, sorting or remote calls per normal frame.
local Config = require(game.ReplicatedStorage.shared.Configs.PerformanceConfig)
local Sampler = {}
local function histogram()
	return { bins = table.create(Config.BucketCount, 0), frames = 0, total = 0, worst = 0, over50 = 0, over100 = 0, over250 = 0 }
end
local function add(h, ms)
	h.frames += 1 h.total += ms h.worst = math.max(h.worst, ms)
	local bin = math.clamp(math.ceil(ms / Config.BucketMs), 1, Config.BucketCount)
	h.bins[bin] += 1
	if ms > 50 then h.over50 += 1 end
	if ms > 100 then h.over100 += 1 end
	if ms > 250 then h.over250 += 1 end
end
local function percentile(h, fraction)
	if h.frames == 0 then return 0 end
	local target, count = math.ceil(h.frames * fraction), 0
	for i,n in h.bins do
		count += n
		if count >= target then return if i == Config.BucketCount then h.worst else math.min(h.worst, i * Config.BucketMs) end
	end
	return h.worst
end
function Sampler.new(now)
	local phases = {} for _,p in Config.Phases do phases[p] = histogram() end
	return { startedAt = now, all = histogram(), phases = phases, hitches = {}, cursor = 0, repeatPairs = 0, repeatStreak = 0, maxRepeatStreak = 0 }
end
function Sampler.record(s, dt, phase, now)
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 or dt == math.huge then return end
	local ms = math.min(dt * 1000, 60000)
	add(s.all, ms) add(s.phases[phase] or s.phases.lobby, ms)
	if ms > Config.HitchMs then
		local gap = if s.lastHitchAt then now - s.lastHitchAt else 0
		if gap >= 0.35 and gap <= 0.8 then
			s.repeatPairs += 1 s.repeatStreak += 1
		else s.repeatStreak = 0 end
		s.maxRepeatStreak = math.max(s.maxRepeatStreak, s.repeatStreak)
		s.lastHitchAt = now
		s.cursor = s.cursor % Config.RecentHitches + 1
		s.hitches[s.cursor] = { ms = math.round(ms), phase = phase, at = math.round((now - s.startedAt) * 1000) }
	end
end
function Sampler.snapshot(s, now)
	local h = s.all
	local data = {
		durationSeconds = math.max(0, now - s.startedAt), frames = h.frames,
		p50Ms = percentile(h, .5), p95Ms = percentile(h, .95), p99Ms = percentile(h, .99),
		worstMs = h.worst, over50 = h.over50, over100 = h.over100, over250 = h.over250,
		repeatHitchPairs = s.repeatPairs, maxRepeatStreak = s.maxRepeatStreak,
	}
	for name,p in s.phases do
		data[name.."Frames"] = p.frames data[name.."Seconds"] = p.total / 1000
		data[name.."P95Ms"] = percentile(p,.95) data[name.."WorstMs"] = p.worst
		data[name.."Over100"] = p.over100
	end
	local recent = {}
	for offset = 1, Config.RecentHitches do
		local h = s.hitches[(s.cursor + offset - 1) % Config.RecentHitches + 1]
		if h then table.insert(recent, string.format("%d:%s:%d", h.at,h.phase,h.ms)) end
	end
	data.recentHitches = table.concat(recent, ";")
	return data
end
return Sampler

