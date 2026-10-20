--[[
	GuideTrailClassic
	-----------------
	THE SIMULATOR QUEST BEAM: one camera-facing Beam from the player's waist to the bay, wearing a row
	of chevrons that scroll towards it, white where it leaves the player and gold where it lands.
	`GuideTrailConfig` has the why and the numbers; `GuideTrailController` decides when it is drawn and
	at which bay. This file only draws it.

	BOTH ENDS ARE ATTACHMENTS ON `workspace.Terrain`, and neither is on the character. An attachment
	welded into the root part would turn with the player, and the arch below is aimed by the
	attachments' own +X, so a line hung off the character would swing every time they turned round.
	Terrain never streams out and never turns, and both ends are simply written every frame.

	THE ARCH IS THE BEZIER'S OWN. A Beam is a cubic Bezier whose two inner control points sit
	`CurveSize0` along Attachment0's +X and `CurveSize1` back along Attachment1's -X. Aiming each end a
	third of the way along the line and up by `k` lifts the midpoint by three quarters of `k`, which is
	where the `/ 0.75` comes from.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GuideTrailConfig = require(ReplicatedStorage.shared.Configs.GuideTrailConfig)

local GuideTrailClassic = {}
GuideTrailClassic.__index = GuideTrailClassic

--- Opacity changes smaller than this are not written: a NumberSequence is an allocation, and the
--- fade is the only thing that changes it.
local ALPHA_STEP = 0.02

--- A CFrame at `position` whose +X is `x`. The other two axes are any pair that completes it, because
--- a camera-facing beam takes its width from the camera and only its curve from the attachment.
local function aimedX(position: Vector3, x: Vector3): CFrame
	local right = x.Unit
	local other = if math.abs(right.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local back = right:Cross(other).Unit
	return CFrame.fromMatrix(position, right, back:Cross(right))
end

function GuideTrailClassic.new()
	local cfg = GuideTrailConfig.Classic

	local start = Instance.new("Attachment")
	start.Name = "GuideTrailStart"
	start.Parent = workspace.Terrain

	local finish = Instance.new("Attachment")
	finish.Name = "GuideTrailEnd"
	finish.Parent = workspace.Terrain

	local beam = Instance.new("Beam")
	beam.Name = "GuideTrail"
	beam.Attachment0 = start
	beam.Attachment1 = finish
	beam.FaceCamera = true
	beam.Texture = cfg.Texture
	--[[ WRAP, SO THE ARROWS KEEP THEIR SIZE: one tile every `Spacing` studs however long the line is.
		Stretch would fit a fixed count into the line and squash them as the player walks up to it. ]]
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = cfg.Spacing
	--- Cycles a second, and one cycle is one tile.
	beam.TextureSpeed = cfg.Speed / cfg.Spacing
	beam.Width0 = cfg.Width
	beam.Width1 = cfg.Width
	beam.Color = ColorSequence.new(cfg.NearColor, cfg.FarColor)
	--- Unlit, so it reads the same in the showroom's shade as out on the forecourt.
	beam.LightInfluence = 0
	beam.LightEmission = 0
	beam.Segments = 24
	beam.Enabled = false
	beam.Parent = start

	return setmetatable({
		_start = start,
		_finish = finish,
		_beam = beam,
		_alpha = -1,
	}, GuideTrailClassic)
end

--[[ Draw the line from a character whose root is at `root` to `deck`, at overall opacity `alpha`.
	Called every frame while it is up; `hide` takes it down. `toPoint` replaces the point over the
	deck when the line is going to a person instead, and brings that line's taller arch with it
	(`GuideTrailConfig.Person`). ]]
function GuideTrailClassic.draw(self, root: Vector3, _feet: Vector3, deck: BasePart, alpha: number, _dt: number?, toPoint: Vector3?)
	local cfg = GuideTrailConfig.Classic
	local goal = toPoint or deck.Position + Vector3.yAxis * (deck.Size.Y / 2 + cfg.EndLift)

	local flat = Vector3.new(goal.X - root.X, 0, goal.Z - root.Z)
	local heading = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local from = root - Vector3.yAxis * cfg.Drop + heading * cfg.Lead

	local span = goal - from
	local length = span.Magnitude
	if length < 0.5 then
		self:hide()
		return
	end

	local along = span / length
	local bend = if toPoint then GuideTrailConfig.Person else cfg
	local lift = Vector3.yAxis * (math.min(length * bend.Arc, bend.ArcMax) / 0.75)
	local third = along * (length / 3)
	local out = third + lift
	local back = third - lift

	self._start.CFrame = aimedX(from, out)
	self._finish.CFrame = aimedX(goal, back)
	self._beam.CurveSize0 = out.Magnitude
	self._beam.CurveSize1 = back.Magnitude

	if math.abs(alpha - self._alpha) >= ALPHA_STEP or (alpha == 1 and self._alpha ~= 1) then
		self._alpha = alpha
		local clear = 1 - alpha
		self._beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(cfg.FadeStart, clear),
			NumberSequenceKeypoint.new(1, clear),
		})
	end
	self._beam.Enabled = true
end

function GuideTrailClassic.hide(self)
	self._beam.Enabled = false
	self._alpha = -1
end

function GuideTrailClassic.destroy(self)
	self._start:Destroy()
	self._finish:Destroy()
end

return GuideTrailClassic
