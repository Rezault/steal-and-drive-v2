--[[
	ButtonBeckon  (client)
	----------------------
	A button calling for its next press. Every `Interval` seconds it does one beat: a quick swell, a
	short rock either side, and a sheen across its face. `start` begins the loop and hands back the
	function that ends it. Asked for by the owner for the Play button after the tutorial: "make it
	feel like oh i gotta click it again".

	EACH PART OF THE BEAT WRITES A CHANNEL NOBODY ELSE ON A TAGGED BUTTON IS USING, or shares one
	politely. That is the whole design, because a `UIButton` already has two owners:

	  • SCALE belongs to the hover nudge. `Components/Button` parks a `UIScale` named `HoverScale` on
	    every tagged button, and only one UIScale on an instance takes effect. So the swell borrows
	    that one, and only while it is resting at 1: a button under a cursor or a gamepad highlight
	    is already being pointed at and is skipped. A hover that lands mid-swell simply wins, since
	    TweenService hands a property to the newest tween, and the swell's way down is only chained
	    off a way up that COMPLETED, so it can never pull a hovered button back down.
	  • POSITION belongs to whoever slides the button (`RaceEntryController` for Play). Nothing here
	    moves it.
	  • ROTATION is free, and the rock is written there.
	  • The sheen is a child Frame of its own, under the button's text (ZIndex 2 against Title's 3),
	    cut to the button's `UICorner`. It is skipped on an ImageButton with no UICorner, whose
	    outline is drawn by its image, because a rectangle of light would show its corners.

	Everything is undone by the stop: rotation back to 0, the sheen destroyed, and the scale put back
	to 1 only if the swell was still the thing driving it.
]]

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local HOVER_SCALE_NAME = "HoverScale" -- `Components/Button`'s; see the header
local SHINE_NAME = "BeckonShine"

export type Config = {
	Interval: number, -- seconds from one beat's start to the next
	FirstDelay: number, -- seconds before the first beat
	Pop: number, -- the swell's peak scale; 1 turns it off
	Rock: number, -- the rock's first swing, in degrees; 0 turns it off
	Shine: boolean,
	ShineTime: number, -- seconds for the sheen to cross the face
	ShineAlpha: number, -- the band's opacity at its brightest, 0..1
}

local POP_UP = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_DOWN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
--- The rock's swings as fractions of `Rock`, each one smaller and the other way, ending level.
local ROCK_STEPS = { -1, 0.75, -0.45, 0.2, 0 }
local ROCK_STEP = TweenInfo.new(0.075, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
--- Where the sheen starts and ends, past either edge so its band is fully off the face at both.
local SHINE_FROM = Vector2.new(-1.2, 0)
local SHINE_TO = Vector2.new(1.2, 0)

local ButtonBeckon = {}

local function makeShine(button: GuiButton, cfg: Config): Frame?
	local corner = button:FindFirstChildOfClass("UICorner")
	if not corner and button:IsA("ImageButton") and button.Image ~= "" then
		return nil
	end

	local shine = Instance.new("Frame")
	shine.Name = SHINE_NAME
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(0.5, 0.5)
	shine.Size = UDim2.fromScale(1, 1)
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BorderSizePixel = 0
	shine.ZIndex = 2
	shine.Active = false

	if corner then
		corner:Clone().Parent = shine
	end

	local peak = 1 - math.clamp(cfg.ShineAlpha, 0, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 20
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.36, 1),
		NumberSequenceKeypoint.new(0.5, peak),
		NumberSequenceKeypoint.new(0.64, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Offset = SHINE_FROM
	gradient.Parent = shine

	shine.Parent = button
	return shine
end

--[[ Start beckoning. Returns the stop, which is safe to call more than once. The loop also ends by
	itself if the button leaves the tree. ]]
function ButtonBeckon.start(button: GuiButton, cfg: Config): () -> ()
	local alive = true
	local popTween: Tween? = nil
	local rockTween: Tween? = nil
	local shineTween: Tween? = nil
	local shine = if cfg.Shine then makeShine(button, cfg) else nil

	local function pop()
		local scale = button:FindFirstChild(HOVER_SCALE_NAME)
		if not (scale and scale:IsA("UIScale")) or cfg.Pop <= 1 then
			return
		end
		-- Being pointed at already, by a cursor or a gamepad highlight. See the header.
		if math.abs(scale.Scale - 1) > 0.001 or GuiService.SelectedObject == button then
			return
		end
		local up = TweenService:Create(scale, POP_UP, { Scale = cfg.Pop })
		popTween = up
		up.Completed:Once(function(state: Enum.PlaybackState)
			if alive and state == Enum.PlaybackState.Completed and popTween == up then
				popTween = TweenService:Create(scale, POP_DOWN, { Scale = 1 })
				popTween:Play()
			end
		end)
		up:Play()
	end

	local function rock()
		if cfg.Rock <= 0 then
			return
		end
		local i = 0
		local function swing()
			i += 1
			local step = ROCK_STEPS[i]
			if not (alive and step) then
				return
			end
			local tween = TweenService:Create(button, ROCK_STEP, { Rotation = step * cfg.Rock })
			rockTween = tween
			tween.Completed:Once(function(state: Enum.PlaybackState)
				if state == Enum.PlaybackState.Completed and rockTween == tween then
					swing()
				end
			end)
			tween:Play()
		end
		swing()
	end

	local function sweep()
		local gradient = shine and shine:FindFirstChildOfClass("UIGradient")
		if not gradient then
			return
		end
		gradient.Offset = SHINE_FROM
		shineTween = TweenService:Create(
			gradient,
			TweenInfo.new(cfg.ShineTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Offset = SHINE_TO }
		)
		shineTween:Play()
	end

	local function stop()
		if not alive then
			return
		end
		alive = false
		if popTween and popTween.PlaybackState == Enum.PlaybackState.Playing then
			-- Still ours, so nothing has hovered since; put the hover's resting value back.
			popTween:Cancel()
			local scale = button:FindFirstChild(HOVER_SCALE_NAME)
			if scale and scale:IsA("UIScale") then
				scale.Scale = 1
			end
		end
		if rockTween then
			rockTween:Cancel()
		end
		if cfg.Rock > 0 then
			button.Rotation = 0
		end
		if shineTween then
			shineTween:Cancel()
		end
		if shine then
			shine:Destroy()
		end
	end

	task.spawn(function()
		task.wait(cfg.FirstDelay)
		while alive do
			if not button:IsDescendantOf(game) then
				stop()
				return
			end
			pop()
			rock()
			sweep()
			task.wait(cfg.Interval)
		end
	end)

	return stop
end

return ButtonBeckon
