--!strict

-- ReplicatedFirst can run before ReplicatedStorage and the client framework exist, so the level
-- loading screen's essential visuals are reproduced here with no module dependencies.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- This must be the first action after resolving engine services. Nothing below is allowed to wait
-- before Roblox's join overlay is removed.
ReplicatedFirst:RemoveDefaultLoadingScreen()
ReplicatedFirst:SetAttribute("JoinScreenRunning", true)

local OVERLAY_COLOR = Color3.fromRGB(8, 10, 14)
local ACCENT_COLOR = Color3.fromRGB(255, 255, 255)
local READY_ATTRIBUTE = "ShardClientStarted"
--- Set on ReplicatedFirst by the client bootstrap when the boot went wrong (`Modules/BootGuard`
--- spells it too; this script runs before any module can be required, so keep the two in step).
local FAILED_ATTRIBUTE = "BootFailed"
local CONTROLLERS_TIMEOUT = 45
-- Was 40 while the whole of ReplicatedStorage was preloaded (see "Loading assets" below, 2026-09-28).
-- The UI, the sound effects and one plot are a fraction of that; past 15s it is a slow connection,
-- and the engine finishes it in the background either way, so the screen stops waiting rather than
-- making the player wait for it.
local PRELOAD_TIMEOUT = 15
local HARD_TIMEOUT = 115
local MIN_HOLD = 1.2
local FADE_TIME = 0.5

-- Matches RaceUIController's level-loading geometry.
local SPINNER_Y = 0.40
local SPINNER_SIZE = 0.075
local SPINNER_THICKNESS = 0.005
local HEADLINE_Y = 0.492
local RULE_Y = 0.556
local RULE_WIDTH = 0.28
local TRACK_HEIGHT = 0.0075
local STATUS_Y = 0.59
local TIP_Y = 0.86
local TICK_COUNT = 5

-- Same car glyph used on the race loading bar. UIAssets is not available this early.
local CAR_MARKER = "rbxassetid://127499410859293"
local CAR_MARKER_ASPECT = 256 / 169

local TIPS = {
	"The throttle is automatic. You only steer",
	"Pull alongside a car and JUMP to steal it",
	"Drive into the back of the truck to keep the car",
	"Squeeze past traffic. Near misses pay",
	"Obstacles chip your car's HP, so thread the gaps",
	"Your parked cars earn cash while you drive",
}

while Players.LocalPlayer == nil do
	task.wait()
end
local player = Players.LocalPlayer :: Player
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "JoinScreen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = OVERLAY_COLOR
overlay.BorderSizePixel = 0
overlay.Parent = gui

local spinner = Instance.new("Frame")
spinner.Name = "Spinner"
spinner.AnchorPoint = Vector2.new(0.5, 0.5)
spinner.Position = UDim2.fromScale(0.5, SPINNER_Y)
spinner.Size = UDim2.fromScale(SPINNER_SIZE, SPINNER_SIZE)
spinner.BackgroundTransparency = 1
spinner.Parent = overlay

local spinnerAspect = Instance.new("UIAspectRatioConstraint")
spinnerAspect.AspectRatio = 1
spinnerAspect.Parent = spinner

local spinnerCorner = Instance.new("UICorner")
spinnerCorner.CornerRadius = UDim.new(1, 0)
spinnerCorner.Parent = spinner

local spinnerStroke = Instance.new("UIStroke")
spinnerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
spinnerStroke.Color = ACCENT_COLOR
spinnerStroke.Thickness = 4
spinnerStroke.Parent = spinner

local spinnerGradient = Instance.new("UIGradient")
spinnerGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0.75),
	NumberSequenceKeypoint.new(1, 0),
})
spinnerGradient.Parent = spinnerStroke

local headline = Instance.new("TextLabel")
headline.Name = "Headline"
headline.AnchorPoint = Vector2.new(0.5, 0.5)
headline.Position = UDim2.fromScale(0.5, HEADLINE_Y)
headline.Size = UDim2.fromScale(0.8, 0.045)
headline.BackgroundTransparency = 1
headline.Font = Enum.Font.GothamMedium
headline.Text = "STEAL AND DRIVE"
headline.TextColor3 = ACCENT_COLOR
headline.TextTransparency = 0.1
headline.TextScaled = true
headline.ZIndex = 2
headline.Parent = overlay

local track = Instance.new("Frame")
track.Name = "Rule"
track.AnchorPoint = Vector2.new(0.5, 0.5)
track.Position = UDim2.fromScale(0.5, RULE_Y)
track.Size = UDim2.fromScale(RULE_WIDTH, TRACK_HEIGHT)
track.BackgroundColor3 = ACCENT_COLOR
track.BackgroundTransparency = 0.72
track.BorderSizePixel = 0
track.ZIndex = 2
track.Parent = overlay

local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(1, 0)
trackCorner.Parent = track

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = ACCENT_COLOR
fill.BackgroundTransparency = 0.1
fill.BorderSizePixel = 0
fill.ZIndex = 3
fill.Parent = track

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

local ticks = {} :: { Frame }
for index = 1, TICK_COUNT do
	local tick = Instance.new("Frame")
	tick.Name = `Tick{index}`
	tick.AnchorPoint = Vector2.new(0.5, 0.5)
	tick.Position = UDim2.fromScale((index - 1) / (TICK_COUNT - 1), 0.5)
	tick.Size = UDim2.new(0, 2, 2.1, 0)
	tick.BackgroundColor3 = ACCENT_COLOR
	tick.BackgroundTransparency = if index == 1 then 0.15 else 0.72
	tick.BorderSizePixel = 0
	tick.ZIndex = 4
	tick.Parent = track
	table.insert(ticks, tick)
end

local marker = Instance.new("ImageLabel")
marker.Name = "Marker"
marker.AnchorPoint = Vector2.new(0.5, 1)
marker.Position = UDim2.fromScale(0.5 - RULE_WIDTH / 2, RULE_Y - TRACK_HEIGHT / 2)
marker.Size = UDim2.fromScale(1, 0.03)
marker.BackgroundTransparency = 1
marker.Image = CAR_MARKER
marker.ImageColor3 = ACCENT_COLOR
marker.ZIndex = 5
marker.Parent = overlay

local markerAspect = Instance.new("UIAspectRatioConstraint")
markerAspect.AspectRatio = CAR_MARKER_ASPECT
markerAspect.Parent = marker

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.Position = UDim2.fromScale(0.5, STATUS_Y)
status.Size = UDim2.fromScale(0.62, 0.024)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamMedium
status.Text = "Connecting…"
status.TextColor3 = ACCENT_COLOR
status.TextTransparency = 0.2
status.TextScaled = true
status.ZIndex = 2
status.Parent = overlay

local tip = Instance.new("TextLabel")
tip.Name = "Tip"
tip.AnchorPoint = Vector2.new(0.5, 0.5)
tip.Position = UDim2.fromScale(0.5, TIP_Y)
tip.Size = UDim2.fromScale(0.84, 0.021)
tip.BackgroundTransparency = 1
tip.Font = Enum.Font.GothamMedium
tip.Text = TIPS[math.random(1, #TIPS)]
tip.TextColor3 = ACCENT_COLOR
tip.TextTransparency = 0.5
tip.TextScaled = true
tip.ZIndex = 2
tip.Parent = overlay

local shownAt = os.clock()
local target = 0.08
local shown = 0
local alive = true

local renderConnection = RunService.RenderStepped:Connect(function(dt)
	spinner.Rotation = (spinner.Rotation + dt * 320) % 360
	local camera = workspace.CurrentCamera
	if camera then
		spinnerStroke.Thickness = math.max(2, camera.ViewportSize.Y * SPINNER_THICKNESS)
	end

	shown += (target - shown) * (1 - math.exp(-dt / 0.35))
	shown = math.clamp(shown, 0, 1)
	fill.Size = UDim2.fromScale(shown, 1)
	marker.Position = UDim2.fromScale(0.5 - RULE_WIDTH / 2 + RULE_WIDTH * shown, RULE_Y - TRACK_HEIGHT / 2)

	for index, tick in ticks do
		local mark = (index - 1) / (TICK_COUNT - 1)
		tick.BackgroundTransparency = if shown >= mark then 0.15 else 0.72
	end
end)

local function setStep(text: string, progress: number)
	status.Text = text
	target = math.max(target, progress)
end

local function await(predicate: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not predicate() do
		if os.clock() >= deadline then
			return false
		end
		task.wait(0.1)
	end
	return true
end

--[[ THE BOOT WENT WRONG: SAY SO, AND STAY UP (2026-10-14). It used to fade out regardless and leave
	the player on a black screen with no game behind it (a tester on an iPhone: "after the loading
	fully loads it takes me to this black screen"). Now it keeps the overlay and asks them to rejoin.
	If the controllers do come up after all, `finish` still runs (`erred` lets it). ]]
local erred = false
local function showError()
	if erred then
		return
	end
	erred = true
	headline.Text = "COULDN'T LOAD"
	status.Text = "Something went wrong starting the game. Please rejoin."
	warn("[JoinScreen] Boot failed (" .. tostring(ReplicatedFirst:GetAttribute(FAILED_ATTRIBUTE)) .. "); asking the player to rejoin.")
end

local function finish()
	if not alive then
		return
	end
	alive = false
	target = 1
	status.Text = "Ready"
	task.wait(0.4)

	local remaining = MIN_HOLD - (os.clock() - shownAt)
	if remaining > 0 then
		task.wait(remaining)
	end

	local info = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(overlay, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(spinnerStroke, info, { Transparency = 1 }):Play()
	TweenService:Create(headline, info, { TextTransparency = 1 }):Play()
	TweenService:Create(track, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(fill, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(marker, info, { ImageTransparency = 1 }):Play()
	TweenService:Create(tip, info, { TextTransparency = 1 }):Play()
	local last = TweenService:Create(status, info, { TextTransparency = 1 })
	last:Play()
	last.Completed:Wait()

	renderConnection:Disconnect()
	gui:Destroy()
end

task.spawn(function()
	-- Seconds each phase took, printed once at the end. The screen is a sum of three waits and
	-- "it takes too long" is only fixable once it is known which one is long.
	local phaseStart = os.clock()
	local timings = {} :: { string }
	local function lap(name: string)
		local now = os.clock()
		table.insert(timings, string.format("%s %.1fs", name, now - phaseStart))
		phaseStart = now
	end

	setStep("Connecting…", 0.15)
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	lap("loaded")

	setStep("Starting the game…", 0.35)
	local function started(): boolean
		return workspace:GetAttribute(READY_ATTRIBUTE) == true
	end
	local function broken(): boolean
		return ReplicatedFirst:GetAttribute(FAILED_ATTRIBUTE) ~= nil
	end
	--[[ Started, failed, or slow. Slow keeps waiting (a slow phone is still a working one) up to the
		hard timeout; failed, or never started at all, is the rejoin message rather than a black screen.
		A failure that still let the controllers start (one broken system, the rest guarded) is only a
		log line: the game is there to play. ]]
	if not await(function()
		return started() or broken()
	end, CONTROLLERS_TIMEOUT) then
		setStep("Still starting…", 0.4)
		await(function()
			return started() or broken()
		end, HARD_TIMEOUT - CONTROLLERS_TIMEOUT - 5)
	end
	if not started() then
		showError()
		--- Lift anyway if the controllers come up late; otherwise the message stays.
		workspace:GetAttributeChangedSignal(READY_ATTRIBUTE):Once(function()
			if started() then
				finish()
			end
		end)
		return
	end
	lap("controllers")

	--[[ ONLY WHAT THE PLAYER MEETS THE MOMENT THE OVERLAY LIFTS (2026-09-28). This used to gather
		ReplicatedStorage, which is every car mesh and texture in the game and none of it on screen at
		join — the bulk of the wait, for things the engine fetches on first use anyway. What is gathered
		instead is the three things the owner named: the UI, the sound effects, and the player's own
		base, which is where they spawn. ]]
	setStep("Loading assets…", 0.55)
	local assets = {} :: { Instance }
	local function gather(root: Instance)
		for _, descendant in root:GetDescendants() do
			if
				descendant:IsA("ImageLabel")
				or descendant:IsA("ImageButton")
				or descendant:IsA("Decal")
				or descendant:IsA("Texture")
				or descendant:IsA("MeshPart")
				or descendant:IsA("SpecialMesh")
				or descendant:IsA("SurfaceAppearance")
				or descendant:IsA("Sound")
			then
				table.insert(assets, descendant)
			end
		end
	end
	gather(playerGui)

	--[[ THE SOUND EFFECTS: every Sound in SoundService's groups BUT the soundtrack's and the radio's.
		Those two are whole songs, the largest downloads in the game, and a track that starts a second
		late is not a problem the way a click with no click is. The group names are
		`AudioConfig.Sfx.Exclude` — spelled here because this script runs before any module can be
		required; keep the two in step. ]]
	local LONG_AUDIO_GROUPS = { Music = true, Radio = true }
	for _, descendant in game:GetService("SoundService"):GetDescendants() do
		if descendant:IsA("Sound") then
			local group = descendant:FindFirstAncestorWhichIsA("SoundGroup")
			if not (group and LONG_AUDIO_GROUPS[group.Name]) then
				table.insert(assets, descendant)
			end
		end
	end

	--[[ THE PLAYER'S OWN BASE, which is where they spawn and the first thing on screen. Found by the
		owner stamp the server writes on the plot (`PlotConfig.OwnerUserIdAttribute`) under
		`workspace.Map.Plots` (`PlotConfig.MapName` / `PlotsFolderName`) — same spelling caveat as the
		sounds. The place streams, so the plot is asked for by position first; a plot that has not
		been assigned within a few seconds is simply left to stream in normally rather than holding the
		screen up for it. ]]
	local plots = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Plots")
	local myPlot: Instance? = nil
	await(function()
		for _, plot in (if plots then plots:GetChildren() else {}) do
			if plot:GetAttribute("OwnerUserId") == player.UserId then
				myPlot = plot
				return true
			end
		end
		return false
	end, 5)
	if myPlot and myPlot:IsA("Model") then
		pcall(function()
			player:RequestStreamAroundAsync(myPlot:GetPivot().Position, 5)
		end)
		gather(myPlot)
	end

	local total = #assets
	local loaded = 0
	local preloadFinished = total == 0
	if total > 0 then
		task.spawn(function()
			local ok, err = pcall(function()
				ContentProvider:PreloadAsync(assets, function()
					loaded += 1
					-- One Instance can resolve more than one content ID (for example, a MeshPart's
					-- mesh and texture), so callback count is not guaranteed to stop at #assets.
					local ratio = math.clamp(loaded / total, 0, 1)
					target = math.max(target, 0.55 + 0.42 * ratio)
					status.Text = string.format("Loading assets…  %d%%", math.floor(ratio * 100))
				end)
			end)
			if not ok then
				warn("[JoinScreen] Preload failed:", err)
			end
			preloadFinished = true
		end)

		if not await(function()
			return preloadFinished
		end, PRELOAD_TIMEOUT) then
			warn(string.format("[JoinScreen] Preload hit its cap with %d/%d fetched.", loaded, total))
		end
	end
	lap(string.format("assets(%d)", total))
	print("[JoinScreen] " .. table.concat(timings, ", "))

	finish()
end)

task.delay(HARD_TIMEOUT, function()
	if alive and not erred then
		--- Lifted onto a game only if there is one; with no controllers it is the rejoin message.
		if workspace:GetAttribute(READY_ATTRIBUTE) == true then
			warn("[JoinScreen] Hard timeout; removing the join screen.")
			finish()
		else
			showError()
		end
	end
end)
