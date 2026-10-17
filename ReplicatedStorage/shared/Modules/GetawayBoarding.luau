--[[
	GetawayBoarding (shared geometry)
	--------------------------------
	Scalar geometry for the getaway's assisted climb. Local +Z points out of the truck's rear;
	entering therefore DECREASES Z. Keeping the entry and support maths independent of Instances
	lets the swept crossing and the ramp-to-floor transition be checked outside Studio.

	This is presentation, not reward authority. GetawayController still checks its bay volume
	before sending the existing bank request, and GetawayService still owns the resulting award.
]]

local GetawayBoarding = {}

export type Sample = {
	x: number,
	y: number,
	nose: number,
	halfWidth: number,
	halfHeight: number,
}

export type EntryConfig = {
	MaxEntryGap: number,
	SideMargin: number,
	MinBottomHeight: number,
	MaxBottomHeight: number,
}

--[[ A crossing is swept so a quick car cannot skip a thin trigger between Heartbeats. The
	current AND crossing widths must fit: interpolating only the nose would admit a car that
	cut diagonally through the corner. A first sample may touch the foot, but cannot start deep
	inside the ramp; spawning or landing there is not evidence of an approach from behind. ]]
function GetawayBoarding.enters(previous: Sample?, current: Sample, foot: number, centreX: number,
	halfWidth: number, cfg: EntryConfig): boolean
	local gap = current.nose - foot
	if gap > cfg.MaxEntryGap then
		return false
	end
	local crossing = current
	if previous then
		local travel = previous.nose - current.nose
		if previous.nose < foot or travel <= 0 then
			return false
		end
		local t = math.clamp((previous.nose - foot) / travel, 0, 1)
		crossing = {
			x = previous.x + (current.x - previous.x) * t,
			y = previous.y + (current.y - previous.y) * t,
			nose = foot,
			halfWidth = math.max(previous.halfWidth, current.halfWidth),
			halfHeight = previous.halfHeight + (current.halfHeight - previous.halfHeight) * t,
		}
	elseif gap < -cfg.MaxEntryGap then
		return false
	end
	local available = halfWidth - cfg.SideMargin
	local bottom = crossing.y - crossing.halfHeight
	return math.abs(crossing.x - centreX) + crossing.halfWidth <= available
		and math.abs(current.x - centreX) + current.halfWidth <= available
		and bottom >= cfg.MinBottomHeight and bottom <= cfg.MaxBottomHeight
end

--[[ Front and rear axle heights produce a gradual pitch-in and pitch-out. Rotating the whole
	car to the ramp angle at the foot would recreate the visible snap this assist is removing.
	The height outside either end is flat, so both axles over the sill gives a level bay pose. ]]
function GetawayBoarding.support(z: number, wheelbase: number, nearZ: number, farZ: number,
	nearY: number, farY: number): (number, number)
	local function height(at: number): number
		local t = math.clamp((farZ - at) / (farZ - nearZ), 0, 1)
		return farY + (nearY - farY) * t
	end
	local front = height(z - wheelbase * 0.5)
	local rear = height(z + wheelbase * 0.5)
	return (front + rear) * 0.5, math.atan2(front - rear, wheelbase)
end

return GetawayBoarding
