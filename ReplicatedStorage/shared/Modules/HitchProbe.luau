--[[
	HitchProbe  (shared)
	--------------------
	A DIAGNOSTIC, added 2026-10-05 for "there's lag when banking a car — only the first time". The
	bank is a dozen systems reacting to one moment on both sides of the wire, and reading the code
	could not say which of them owns the hitch, so this measures them instead of guessing.

	HOW TO READ IT. Suspect functions are wrapped (`wrap`); each run that takes `WorkMs` or more is
	noted. A moment worth watching is marked (`mark`, at the bank), and for `WindowSeconds` after it:
	  • CLIENT: any frame longer than `FrameMs` prints its length and the wrapped work done in it. A
	    long frame with NO work listed is the engine's (asset loading, a first render, a GC pause),
	    which is itself the answer that it is none of ours.
	  • SERVER: there are no frames to watch, so slow wrapped work prints on its own.
	Every wrapped call is also a `debug.profilebegin` label, so the MicroProfiler names it too.

	`Enabled = false` makes every wrapper call straight through and prints nothing. It is meant to be
	switched off — or this file and its wraps removed — once the hitch is found.
]]

local RunService = game:GetService("RunService")

local HitchProbe = {}

HitchProbe.Enabled = true
--- A client frame at least this long, inside the window, is reported. 50ms is three frames at 60.
HitchProbe.FrameMs = 50
--- Wrapped work at least this long is noted; anything shorter cannot be the hitch.
HitchProbe.WorkMs = 4
--- Seconds after a `mark` that frames and work are reported. The bank's whole aftermath (results,
--- carry, hotbar, the trip home) fits inside 12.
HitchProbe.WindowSeconds = 12

local IS_SERVER = RunService:IsServer()
local work: { string } = {}
local markedAt = -math.huge
local markLabel = ""

local function watching(): boolean
	return os.clock() - markedAt <= HitchProbe.WindowSeconds
end

--- Open the reporting window, named for what just happened.
function HitchProbe.mark(label: string)
	if not HitchProbe.Enabled then
		return
	end
	markedAt = os.clock()
	markLabel = label
	print(string.format("[HitchProbe] mark: %s", label))
end

--- `fn`, timed. Use as `Thing._method = HitchProbe.wrap("Thing._method", Thing._method)`.
function HitchProbe.wrap<A..., R...>(label: string, fn: (A...) -> R...): (A...) -> R...
	return function(...)
		if not HitchProbe.Enabled then
			return fn(...)
		end
		local started = os.clock()
		debug.profilebegin(label)
		local results = table.pack(fn(...))
		debug.profileend()
		local ms = (os.clock() - started) * 1000
		--[[ ON THE CLIENT EVERY CALL IN THE WINDOW IS LISTED, however fast (2026-10-07). The first-bank
			freeze turned out to be the engine's, with only milliseconds of ours in the frame — so what
			matters is not what was slow but what HAPPENED in that frame, because that is what the engine
			was busy loading for. The server still only reports slow work. ]]
		if watching() then
			local line = string.format("%s %.1fms", label, ms)
			if IS_SERVER then
				if ms >= HitchProbe.WorkMs then
					print(string.format("[HitchProbe] server, %.1fs after %s: %s", os.clock() - markedAt, markLabel, line))
				end
			else
				table.insert(work, line)
			end
		end
		return table.unpack(results, 1, results.n)
	end :: any
end

--- Something that happened, with no time of its own: listed in its frame's report like a wrapped call.
function HitchProbe.note(label: string)
	if HitchProbe.Enabled and not IS_SERVER and watching() then
		table.insert(work, label)
	end
end

--[[ WHICH STAGE OF THE FRAME (2026-10-07). A slow frame's own Lua was measured at a few milliseconds,
	so the lost time is the engine's — and the engine runs a frame in fixed stages, each opened by a
	RunService event in this order: PreRender (then the render itself), PreAnimation, PreSimulation
	(then physics), PostSimulation/Heartbeat (then scripts that resumed). Stamping each and reporting the
	widest gap in a slow frame names the stage — "render" is drawing/mesh/texture work, "physics" is an
	assembly or ownership rebuild, and the gap ending at PreRender is scripts, replication and GC. ]]
local STAGES = { "PreRender", "PreAnimation", "PreSimulation", "PostSimulation" }
local stamps: { [string]: number } = {}
local lastStage, lastStamp = nil, os.clock()
local widest, widestFrom, widestTo = 0, "", ""

local function widestGap(): string
	if widest <= 0 then
		return "unknown"
	end
	return string.format("%.0fms between %s and %s", widest * 1000, widestFrom, widestTo)
end

if not IS_SERVER then
	for _, stage in STAGES do
		(RunService :: any)[stage]:Connect(function()
			local now = os.clock()
			local gap = now - lastStamp
			if gap > widest then
				widest, widestFrom, widestTo = gap, lastStage or "?", stage
			end
			lastStage, lastStamp = stage, now
			stamps[stage] = now
		end)
	end
end

if not IS_SERVER then
	RunService.Heartbeat:Connect(function(dt: number)
		if HitchProbe.Enabled and watching() and dt * 1000 >= HitchProbe.FrameMs then
			print(
				string.format(
					"[HitchProbe] %.0fms frame, %.1fs after %s. Work in it: %s",
					dt * 1000,
					os.clock() - markedAt,
					markLabel,
					if #work > 0 then table.concat(work, ", ") else "none of ours (engine: loading/render/GC)"
				)
			)
			print(string.format("[HitchProbe]   ...the widest stage gap in it: %s", widestGap()))
		end
		table.clear(work)
		widest = 0
	end)
end

return HitchProbe
