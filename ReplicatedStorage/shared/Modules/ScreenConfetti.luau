--[[
	ScreenConfetti
	--------------
	Paper confetti drawn as Frames on a screen layer: a burst from both bottom corners, then a rain
	from the top. Lifted out of `ShowcaseController` on 2026-10-06 so the tutorial's finish card can
	fire the same paper as the NEW BEST reveal. `ShowcaseConfig.Reveal.Confetti` has the tuning notes;
	every field of that table is read here, under the same names.

	ON THE SCREEN, NOT IN THE WORLD, for the reveal's reason: frames are crisp at any resolution, take
	a colour each, and flip like paper (width x |cos|), which a particle cannot.

	    local handle = ScreenConfetti.start(layer, cfg, rainSeconds)
	    handle.stop()   -- disconnects and clears every piece

	`rainSeconds` nil rains until `stop`. A number stops the rain after that long and lets the last
	pieces fall out, then disconnects on its own; `stop` is still safe to call.
]]

local RunService = game:GetService("RunService")

local ScreenConfetti = {}

export type Config = {
	Burst: number,
	RainPerSecond: number,
	MaxPieces: number,
	SizeMin: number,
	SizeMax: number,
	Gravity: number,
	Drag: number,
	Colors: { Color3 },
}

export type Handle = {
	stop: () -> (),
}

--- One piece of paper. Positions and velocities are in screen fractions.
type Piece = {
	frame: Frame,
	x: number,
	y: number,
	vx: number,
	vy: number,
	rotation: number,
	spin: number,
	flip: number, -- the paper's tumble phase; drawn width is width x |cos(flip)|
	flipSpeed: number,
	sway: number,
	phase: number,
	width: number,
	height: number,
}

function ScreenConfetti.start(layer: GuiObject, cfg: Config, rainSeconds: number?): Handle
	local rng = Random.new()
	--- Sizes are pixels at a 900-pixel-tall screen, scaled to the real one.
	local unit = math.max(layer.AbsoluteSize.Y / 900, 0.5)
	local pieces: { Piece } = {}
	local owed = 0
	local raining = rainSeconds or math.huge
	local conn: RBXScriptConnection? = nil

	local function piece(x: number, y: number, vx: number, vy: number)
		if #pieces >= cfg.MaxPieces then
			return
		end
		local width = rng:NextNumber(cfg.SizeMin, cfg.SizeMax) * unit
		local height = width * rng:NextNumber(0.4, 0.7)
		local frame = Instance.new("Frame")
		frame.Name = "Confetti"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = cfg.Colors[rng:NextInteger(1, #cfg.Colors)]
		frame.Size = UDim2.fromOffset(width, height)
		frame.Position = UDim2.fromScale(x, y)
		frame.ZIndex = layer.ZIndex
		frame.Parent = layer
		table.insert(pieces, {
			frame = frame,
			x = x,
			y = y,
			vx = vx,
			vy = vy,
			rotation = rng:NextNumber(0, 360),
			spin = rng:NextNumber(-360, 360),
			flip = rng:NextNumber(0, math.pi * 2),
			flipSpeed = rng:NextNumber(5, 13),
			sway = rng:NextNumber(0.02, 0.06),
			phase = rng:NextNumber(0, math.pi * 2),
			width = width,
			height = height,
		})
	end

	local function stop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		for _, p in pieces do
			p.frame:Destroy()
		end
		table.clear(pieces)
	end

	--[[ A frame: the rain owed since last frame, then every piece moved. Drag is applied as
		exp(-Drag * dt) so it is the same fall at 30 and 240 frames a second. A piece is gone once it
		is below the screen. ]]
	local function step(dt: number)
		raining -= dt
		if raining > 0 then
			owed += cfg.RainPerSecond * dt
			while owed >= 1 do
				owed -= 1
				piece(rng:NextNumber(0, 1), -0.04, rng:NextNumber(-0.05, 0.05), rng:NextNumber(0.05, 0.2))
			end
		elseif #pieces == 0 then
			stop()
			return
		end
		local drag = math.exp(-cfg.Drag * dt)
		for i = #pieces, 1, -1 do
			local p = pieces[i]
			p.vy += cfg.Gravity * dt
			p.vx *= drag
			p.vy *= drag
			p.phase += dt * 2.5
			p.x += (p.vx + math.sin(p.phase) * p.sway) * dt
			p.y += p.vy * dt
			p.rotation += p.spin * dt
			p.flip += p.flipSpeed * dt
			if p.y > 1.08 then
				p.frame:Destroy()
				table.remove(pieces, i)
			else
				p.frame.Position = UDim2.fromScale(p.x, p.y)
				p.frame.Rotation = p.rotation
				p.frame.Size = UDim2.fromOffset(p.width * math.max(math.abs(math.cos(p.flip)), 0.15), p.height)
			end
		end
	end

	--- Both corner cannons at once.
	for _, side in { -1, 1 } do
		local x = if side < 0 then 0.02 else 0.98
		for _ = 1, cfg.Burst do
			piece(x, 1.02, -side * rng:NextNumber(0.3, 1.6), -rng:NextNumber(1.6, 3))
		end
	end
	conn = RunService.RenderStepped:Connect(step)

	return { stop = stop }
end

return ScreenConfetti
