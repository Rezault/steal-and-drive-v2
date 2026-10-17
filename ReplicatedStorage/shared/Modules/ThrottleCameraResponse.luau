-- Independent pedal response: releasing the accelerator is visible before road speed settles.
local Config = require(game:GetService("ReplicatedStorage").shared.Configs.CameraConfig)
local Response = {}

function Response.step(current: number, throttle: number, speedFraction: number, suppressed: boolean, dt: number): number
	local cfg = Config.ThrottleResponse
	local speed = math.clamp((speedFraction - cfg.StartFraction) / math.max(cfg.FullFraction - cfg.StartFraction, 0.001), 0, 1)
	local target = if cfg.Enabled and not suppressed then math.clamp((throttle - 0.1) / 0.9, 0, 1) * speed else 0
	local rate = if target > current then cfg.Rise else cfg.Fall
	return current + (target - current) * (1 - math.exp(-rate * math.max(dt, 0)))
end

function Response.offsets(amount: number): (number, number)
	local cfg = Config.ThrottleResponse
	local value = if cfg.Enabled then math.clamp(amount, 0, 1) else 0
	return cfg.FovDeg * value, cfg.PullbackStuds * value
end

return Response

