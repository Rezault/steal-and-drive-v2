--[[
	PlaytimeRewardController  (client)
	----------------------------------
	Holds the playtime gift ladder the server sends (`PlaytimeRewardService`), counts down with this
	client's own clock, draws the FREE GIFTS panel, and publishes what the topbar button should say
	(`LabelEvent`); `TopbarController` owns the button itself, as it owns every topbar icon. It
	DECIDES nothing: a press is a request, and a gift opens off the server's reply, the same rule the
	daily calendar keeps (`DailyRewardController`).

	=== THE PANEL (2026-10-19) =================================================================

	A responsive grid of gifts below the day's 30-minute progress bar. Ready gifts turn green,
	opened gifts are muted, and the final car gift is gold. Gifts open in order; a ready card is
	tappable across its full area. Opened gifts show the exact server receipt, including cash
	conversions, while unopened gifts keep their contents hidden.

	THE CONTENTS ARE A SURPRISE FOR REAL. The server sends what is inside a gift only once it has been
	claimed (`PlaytimeRewardService._payload`), so the reveal is news to this client too.

	Built in code from the kit's parts (`Modules/ArcadeKit`), the way the trade panels and the shop's
	codes box are: there is no authored template for it, and the kit is what makes it look like the
	rest of the game. The button toggles it; X, the dim, or B on a pad close it.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local PlaytimeRewardConfig = require(ReplicatedStorage.shared.Configs.PlaytimeRewardConfig)
--- Only for the Play beckon the panel hands over to when the tutorial ended on it.
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local GameplayFeedback = require(ReplicatedStorage.shared.Modules.GameplayFeedback)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)

local PlaytimeRewardController = Shard.new("PlaytimeRewardController")

local REMOTES = PlaytimeRewardConfig.Remotes
local TEXT = PlaytimeRewardConfig.Text
local PAD_CLOSE = "PlaytimeGiftsClose"
local POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local GOLD = ArcadeKit.Gold
local WHITE = ArcadeKit.White

--- Published with `(label: string, ready: boolean)`; `TopbarController` draws it on the gift button.
PlaytimeRewardController.LabelEvent = "PlaytimeGiftLabel"

--- Seconds the "+$500" stays on the button after a claim before the countdown comes back.
local SHOW_REWARD = 3

-- === Reading the state ======================================================

function PlaytimeRewardController._played(self): number
	local state = self._state
	return if state then state.seconds + (os.clock() - state.receivedAt) else 0
end

local function clock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format(TEXT.Countdown, whole // 60, whole % 60)
end

--- What an opened gift paid, in words.
local function rewardText(gift): string
	if gift.Kind == "Legacy" then
		return "CLAIMED"
	elseif gift.Kind == "Cash" then
		return string.format(TEXT.Cash, GarageConfig.formatCash(gift.Amount))
	elseif gift.Kind == "Revive" then
		return string.format(TEXT.Revive, gift.Amount)
	end
	return string.format(TEXT.Car, GarageConfig.displayName(tostring(gift.Body)))
end

--- What the topbar button says right now, and whether a gift is waiting.
function PlaytimeRewardController._label(self): (string, boolean)
	local state = self._state
	local nextGift = state and state.gifts[state.claimed + 1]
	if not nextGift then
		return TEXT.Done, false
	end
	local left = nextGift.Minutes * 60 - self:_played()
	if left <= 0 then
		return TEXT.Ready, true
	end
	return clock(left), false
end

function PlaytimeRewardController._publish(self)
	if os.clock() < self._holdUntil then
		return
	end
	local label, ready = self:_label()
	if label ~= self._lastLabel or ready ~= self._lastReady then
		self._lastLabel, self._lastReady = label, ready
		Dispatcher:Publish(PlaytimeRewardController.LabelEvent, label, ready)
	end
end

-- === The panel ==============================================================

--- One tile: the card, the wrapped gift, what was inside (hidden until opened), and its line.
function PlaytimeRewardController._buildTile(self, row: GuiObject, index: number, count: number)
	local holder = Instance.new("Frame")
	holder.Name = "Gift" .. index
	holder.BackgroundTransparency = 1
	holder.Parent = row
	local face = ArcadeKit.card(holder, { face = if index == count then ArcadeKit.Faces.Gold else ArcadeKit.Faces.Blue, sunray = false })
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local minute = ArcadeKit.text(face, 0.06, 0.065, 0.4, 0.14, WHITE, true)
	minute.Name = "Minutes"
	minute.Text = string.format(TEXT.Minutes, PlaytimeRewardConfig.Gifts[index].Minutes)
	minute.TextXAlignment = Enum.TextXAlignment.Left
	local status = ArcadeKit.text(face, 0.52, 0.065, 0.42, 0.14, WHITE, true)
	status.Name = "Status"
	status.TextXAlignment = Enum.TextXAlignment.Right

	local wrapped = Instance.new("ImageLabel")
	wrapped.Name = "WrappedGift"
	wrapped.AnchorPoint = Vector2.new(0.5, 0.5)
	wrapped.Position = UDim2.fromScale(0.2, 0.56)
	wrapped.Size = UDim2.fromScale(0.31, 0.6)
	wrapped.BackgroundTransparency = 1
	wrapped.Image = UIAssets.url(UIAssets.GiftGlyph)
	wrapped.ScaleType = Enum.ScaleType.Fit
	wrapped.ZIndex = 4
	wrapped.Parent = face

	local icon = wrapped:Clone()
	icon.Name = "RewardIcon"
	icon.Visible = false
	icon.Parent = face
	local view = CarViewport.new(face, "Car")
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.Position = UDim2.fromScale(0.19, 0.56)
	view.Size = UDim2.fromScale(0.35, 0.57)
	view.ZIndex = 4
	view.Visible = false
	local prize = ArcadeKit.text(face, 0.37, 0.29, 0.57, 0.22, WHITE, true)
	prize.Name = "Prize"
	prize.TextXAlignment = Enum.TextXAlignment.Left
	prize.ZIndex = 5
	local note = ArcadeKit.text(face, 0.37, 0.52, 0.57, 0.13, WHITE, true)
	note.Name = "Detail"
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.ZIndex = 5
	local line = ArcadeKit.text(face, 0.37, 0.73, 0.57, 0.17, WHITE, true)
	line.Name = "Countdown"
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.ZIndex = 5
	local claim, caption = ArcadeKit.button(face, "Claim", 0.37, 0.7, 0.57, 0.23)
	claim.Name = "Claim"
	caption.Text = TEXT.Claim
	local hit = claim
	if not claim:IsA("GuiButton") then
		local cover = Instance.new("TextButton")
		cover.Text = ""
		cover.BackgroundTransparency = 1
		cover.Size = UDim2.fromScale(1, 1)
		cover.ZIndex = 10
		cover.Parent = claim
		hit = cover
	end
	local function requestClaim()
		if os.clock() < self._claimPending or self._revealing then return end
		self._claimPending = os.clock() + 3
		self:getRemoteEvent(REMOTES.Claim):Fire()
	end
	;(hit :: GuiButton).Selectable = true
	;(hit :: GuiButton).Activated:Connect(requestClaim)
	-- A ready card is a full touch target; the visible button stays the gamepad selection.
	local cardTap = Instance.new("TextButton")
	cardTap.Name = "OpenGift"
	cardTap.Text = ""
	cardTap.BackgroundTransparency = 1
	cardTap.Size = UDim2.fromScale(1, 1)
	cardTap.ZIndex = 12
	cardTap.Selectable = false
	cardTap.Visible = false
	cardTap.Parent = face
	cardTap.Activated:Connect(requestClaim)
	holder.MouseEnter:Connect(function()
		if not self._revealing then TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.025 }):Play() end
	end)
	holder.MouseLeave:Connect(function()
		if not self._revealing then TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play() end
	end)
	return { holder = holder, face = face, scale = scale, wrapped = wrapped, icon = icon, view = view,
		prize = prize, note = note, line = line, status = status, claim = claim, cardTap = cardTap, hit = hit, shown = nil }
end

--- Three columns on a wide screen; two on portrait phones. No fixed minimum can push it off-screen.
function PlaytimeRewardController._layout(self)
	if not (self._canvas and self._holder) then return end
	local size = self._canvas.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return end
	local portrait = size.X < 620 and size.X < size.Y
	local columns = if portrait then 2 else 3
	local width = math.min(size.X * 0.92, 960)
	local height = math.min(size.Y * 0.84, if portrait then 680 else 550)
	self._holder.Size = UDim2.fromOffset(width, height)
	local rows = math.ceil(#self._tiles / columns)
	local gapX, gapY = 0.022, 0.045
	local tileW = (1 - gapX * (columns - 1)) / columns
	local tileH = (1 - gapY * (rows - 1)) / rows
	for index, tile in self._tiles do
		local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
		tile.holder.Position = UDim2.fromScale(column * (tileW + gapX), row * (tileH + gapY))
		tile.holder.Size = UDim2.fromScale(tileW, tileH)
	end
end

function PlaytimeRewardController._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "PlaytimeGifts"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 970 -- Above driving/tutorial HUD; below transitions and purchase reveals.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Selectable = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(5, 13, 31)
	dim.BackgroundTransparency = 0.3
	dim.Parent = gui
	dim.Activated:Connect(function() self:close() end)

	local holder = Instance.new("TextButton")
	holder.Name = "Panel"
	holder.Text = ""
	holder.AutoButtonColor = false
	holder.Selectable = false
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local panel, title, body = ArcadeKit.panel(holder, 0.15)
	title.Text = TEXT.Title
	title.ZIndex = 6
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.fromScale(0.7, 0.8)
	local close, x = ArcadeKit.button(panel, "Decline", 0.923, 0.03, 0.05, 0.09)
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.DominantAxis = Enum.DominantAxis.Height
	square.Parent = close
	x.Text = "X"
	-- Keep the small visual X, with a minimum 44-pixel touch target.
	close.ClipsDescendants = false
	local closeHit = Instance.new("TextButton")
	closeHit.Name = "CloseHit"
	closeHit.Text = ""
	closeHit.BackgroundTransparency = 1
	closeHit.AnchorPoint = Vector2.new(0.5, 0.5)
	closeHit.Position = UDim2.fromScale(0.5, 0.5)
	closeHit.Size = UDim2.new(1, 10, 1, 10)
	closeHit.ZIndex = 12
	closeHit.Parent = close
	local hitBounds = Instance.new("UISizeConstraint")
	hitBounds.MinSize = Vector2.new(44, 44)
	hitBounds.Parent = closeHit
	closeHit.Activated:Connect(function() self:close() end)
	self._closeButton = closeHit

	local subtitle = ArcadeKit.text(body, 0.035, 0.025, 0.93, 0.08, ArcadeKit.Navy, false)
	subtitle.Name = "Goal"
	subtitle.Text = TEXT.Subtitle
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.ZIndex = 6
	local bar, fill = ArcadeKit.bar(body, 0.035, 0.125, 0.93, 0.043)
	bar.Name = "PlaytimeProgress"
	fill.Size = UDim2.fromScale(0, 1)
	local progress = ArcadeKit.text(body, 0.035, 0.185, 0.53, 0.047, ArcadeKit.Navy, false)
	progress.Name = "PlayedToday"
	progress.TextXAlignment = Enum.TextXAlignment.Left
	local nextLabel = ArcadeKit.text(body, 0.57, 0.185, 0.395, 0.047, ArcadeKit.Navy, false)
	nextLabel.Name = "NextGift"
	nextLabel.TextXAlignment = Enum.TextXAlignment.Right
	local row = Instance.new("Frame")
	row.Name = "Gifts"
	row.Position = UDim2.fromScale(0.035, 0.275)
	row.Size = UDim2.fromScale(0.93, 0.685)
	row.BackgroundTransparency = 1
	row.Parent = body

	self._tiles = {}
	for index in PlaytimeRewardConfig.Gifts do
		self._tiles[index] = self:_buildTile(row, index, #PlaytimeRewardConfig.Gifts)
	end
	self._gui, self._scale, self._holder, self._canvas = gui, scale, holder, dim
	self._progressFill, self._progressLabel, self._nextLabel = fill, progress, nextLabel
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	dim:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:_layout() end)
	self:_layout()
end

--- Server receipts determine rewards; only availability and the overall clock are predicted locally.
function PlaytimeRewardController._paint(self)
	local state = self._state
	if not (self._gui and state) then return end
	local played = self:_played()
	local finalMinutes = PlaytimeRewardConfig.Gifts[#PlaytimeRewardConfig.Gifts].Minutes
	local duration = finalMinutes * 60
	self._progressFill.Size = UDim2.fromScale(math.clamp(played / duration, 0, 1), 1)
	self._progressLabel.Text = string.format(TEXT.PlayedToday, clock(math.min(played, duration)), finalMinutes)
	local nextGift = state.gifts[state.claimed + 1]
	if not nextGift then
		self._nextLabel.Text = TEXT.AllOpened
	elseif nextGift.Minutes * 60 <= played then
		self._nextLabel.Text = TEXT.GiftReady
	else
		self._nextLabel.Text = string.format(TEXT.NextIn, clock(nextGift.Minutes * 60 - played))
	end
	for index, tile in self._tiles do
		local gift = state.gifts[index]
		local opened = index <= state.claimed and gift and gift.Kind ~= nil
		local left = (gift and gift.Minutes or 0) * 60 - played
		local isNext = index == state.claimed + 1
		local ready = isNext and left <= 0
		local final = index == #self._tiles
		local converted = opened and gift.Kind == "Cash" and type(gift.ConvertedFrom) == "string"
		local colours = if final then ArcadeKit.Faces.Gold
			elseif opened then ArcadeKit.Faces.Grey
			elseif ready then ArcadeKit.Faces.Green
			elseif isNext then ArcadeKit.Faces.Purple else ArcadeKit.Faces.Blue
		ArcadeKit.paint(tile.face, colours)
		tile.wrapped.Visible = not opened
		tile.view.Visible = opened and gift.Kind == "Car"
		tile.icon.Visible = opened and (gift.Kind == "Cash" or gift.Kind == "Revive")
		tile.icon.Image = UIAssets.url(if gift and gift.Kind == "Cash" then UIAssets.Page.CashIcon else UIAssets.GiftGlyph)
		tile.prize.Visible = true
		tile.note.Visible = true
		tile.claim.Visible = ready
		tile.cardTap.Visible = ready
		tile.line.Visible = not ready
		tile.status.Text = if opened then TEXT.Opened elseif ready then TEXT.Available elseif final then TEXT.FinalGift else TEXT.Wrapped
		if opened then
			tile.prize.Text = rewardText(gift)
			tile.note.Text = if converted then string.format(TEXT.ConvertedTile, GarageConfig.displayName(gift.ConvertedFrom))
				elseif gift.Kind == "Car" then TEXT.CarAdded
				elseif gift.Kind == "Cash" then TEXT.CashAdded
				elseif gift.Kind == "Revive" then TEXT.ReviveAdded else TEXT.Opened
			tile.line.Text = if converted then (if gift.Reason == "Full" then TEXT.InventoryFull else TEXT.Duplicate) else TEXT.Opened
			if gift.Kind == "Car" and tile.shown ~= gift.Body then
				tile.shown = gift.Body
				CarViewport.set(tile.view, gift.Body)
			end
		else
			tile.prize.Text = if final then TEXT.FinalTitle else TEXT.MysteryGift
			tile.note.Text = if final then TEXT.FinalDetail else TEXT.Surprise
			tile.line.Text = if left <= 0 then TEXT.ClaimEarlier else string.format(TEXT.OpensIn, clock(left))
		end
		if not (opened and gift.Kind == "Car") and tile.shown then
			tile.shown = nil
			CarViewport.clear(tile.view)
		end
	end
end

local CONFETTI = {
	Color3.fromRGB(255, 214, 82),
	Color3.fromRGB(255, 107, 116),
	Color3.fromRGB(104, 220, 255),
	Color3.fromRGB(162, 112, 255),
	Color3.fromRGB(116, 235, 142),
}

--- Spray flat UI confetti from the reward. It is brief, local, and destroyed with the reveal layer.
local function confetti(layer: GuiObject)
	local random = Random.new()
	for index = 1, 42 do
		local piece = Instance.new("Frame")
		piece.Name = "Confetti"
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(0.5, 0.5)
		piece.Size = UDim2.fromScale(random:NextNumber(0.006, 0.012), random:NextNumber(0.014, 0.026))
		piece.BackgroundColor3 = CONFETTI[(index - 1) % #CONFETTI + 1]
		piece.BorderSizePixel = 0
		piece.Rotation = random:NextNumber(-180, 180)
		piece.ZIndex = 54
		piece.Parent = layer

		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(0.2, 0.48)
		TweenService:Create(piece, TweenInfo.new(random:NextNumber(0.85, 1.25), Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(
				0.5 + math.cos(angle) * distance,
				0.5 + math.sin(angle) * distance * 0.65 + 0.1
			),
			Rotation = piece.Rotation + random:NextNumber(240, 720),
			BackgroundTransparency = 1,
		}):Play()
	end
end

--[[ The confirmed claim: anticipation on the wrapped gift, then a full-screen resolve and the
	actual prize landing in its tile. Nothing is shown until the server has named the reward. ]]
function PlaytimeRewardController._reveal(self, index: number, gift)
	local tile = self._tiles and self._tiles[index]
	if not (tile and self._gui) then
		return
	end
	if self._celebration then
		self._celebration:Destroy()
	end

	local layer = Instance.new("CanvasGroup")
	layer.Name = "GiftReveal"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.ZIndex = 50
	layer.Parent = self._gui
	self._celebration = layer

	local scrim = Instance.new("Frame")
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Color3.fromRGB(7, 9, 20)
	scrim.BackgroundTransparency = 1
	scrim.BorderSizePixel = 0
	scrim.ZIndex = 50
	scrim.Parent = layer

	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = GOLD
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 51
	flash.Parent = layer

	local stage = Instance.new("Frame")
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.48)
	stage.Size = UDim2.fromScale(0.34, 0.52)
	stage.BackgroundTransparency = 1
	stage.ZIndex = 52
	stage.Parent = layer
	local bounds = Instance.new("UISizeConstraint")
	bounds.MinSize = Vector2.new(230, 260)
	bounds.MaxSize = Vector2.new(540, 560)
	bounds.Parent = stage

	local burst = Instance.new("ImageLabel")
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromScale(0.08, 0.08)
	burst.BackgroundTransparency = 1
	burst.Image = UIAssets.url(UIAssets.Results.Sunburst)
	burst.ImageColor3 = GOLD
	burst.ImageTransparency = 1
	burst.ScaleType = Enum.ScaleType.Fit
	burst.ZIndex = 52
	burst.Parent = stage
	local burstRatio = Instance.new("UIAspectRatioConstraint")
	burstRatio.AspectRatio = 1
	burstRatio.Parent = burst

	local wrapped = Instance.new("ImageLabel")
	wrapped.AnchorPoint = Vector2.new(0.5, 0.5)
	wrapped.Position = UDim2.fromScale(0.5, 0.5)
	wrapped.Size = UDim2.fromScale(0.7, 0.7)
	wrapped.BackgroundTransparency = 1
	wrapped.Image = UIAssets.url(UIAssets.GiftGlyph)
	wrapped.ScaleType = Enum.ScaleType.Fit
	wrapped.ZIndex = 55
	wrapped.Parent = stage
	local wrappedScale = Instance.new("UIScale")
	wrappedScale.Scale = 0.15
	wrappedScale.Parent = wrapped

	local heading = ArcadeKit.text(stage, 0.05, 0.02, 0.9, 0.18, GOLD, true)
	local converted = gift.Kind == "Cash" and type(gift.ConvertedFrom) == "string"
	heading.Text = if converted then TEXT.Converted else TEXT.Unwrapped
	heading.TextTransparency = 1
	heading.ZIndex = 55
	local headingScale = Instance.new("UIScale")
	headingScale.Scale = 0.4
	headingScale.Parent = heading

	local prize = ArcadeKit.text(stage, 0.02, 0.75, 0.96, 0.18, WHITE, true)
	prize.Text = rewardText(gift)
	prize.TextTransparency = 1
	prize.ZIndex = 55
	local prizeScale = Instance.new("UIScale")
	prizeScale.Scale = 0.4
	prizeScale.Parent = prize

	local detail = ArcadeKit.text(stage, 0, 0.94, 1, 0.1, WHITE, true)
	detail.Name = "ConversionDetail"
	detail.Text = if converted then string.format(
		if gift.Reason == "Full" then TEXT.ConvertedFull else TEXT.ConvertedDuplicate,
		GarageConfig.displayName(gift.ConvertedFrom)
	) else ""
	detail.TextTransparency = 1
	detail.ZIndex = 55

	local hero: GuiObject
	if gift.Kind == "Car" then
		local view = CarViewport.new(stage, "RewardCar")
		view.AnchorPoint = Vector2.new(0.5, 0.5)
		view.Position = UDim2.fromScale(0.5, 0.5)
		view.Size = UDim2.fromScale(1, 0.52)
		view.ZIndex = 54
		CarViewport.set(view, gift.Body)
		hero = view
	else
		local icon = Instance.new("ImageLabel")
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(0.62, 0.5)
		icon.BackgroundTransparency = 1
		icon.Image = UIAssets.url(if gift.Kind == "Cash" then UIAssets.Page.CashIcon else UIAssets.GiftGlyph)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 54
		icon.Parent = stage
		hero = icon
	end
	hero.Visible = false
	local heroScale = Instance.new("UIScale")
	heroScale.Scale = 0.15
	heroScale.Parent = hero

	--- Only now, with everything built: an error above must not leave the claim button dead for the session.
	self._revealing = true
	TweenService:Create(scrim, TweenInfo.new(0.18), { BackgroundTransparency = 0.18 }):Play()
	TweenService:Create(wrappedScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local function finish()
		if self._celebration == layer then
			self._celebration = nil
			self._revealing = false
		end
		layer:Destroy()
	end
	--- xpcall: an error mid-reveal must still clear `_revealing`, or the claim button is dead for the session.
	task.spawn(xpcall, function()
		task.wait(0.28)
		for _, rotation in { -10, 12, -8, 7, 0 } do
			TweenService:Create(wrapped, TweenInfo.new(0.065, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Rotation = rotation }):Play()
			task.wait(0.065)
		end
		TweenService:Create(wrappedScale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		TweenService:Create(flash, TweenInfo.new(0.08), { BackgroundTransparency = 0.08 }):Play()
		task.wait(0.1)
		wrapped.Visible = false
		hero.Visible = true
		--- The topbar names the prize as it lands, not before the gift has opened.
		Dispatcher:Publish(PlaytimeRewardController.LabelEvent, rewardText(gift), false)
		GameplayFeedback.play("DailyClaimed")
		confetti(layer)
		TweenService:Create(flash, TweenInfo.new(0.32), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(burst, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1.65, 1.65),
			ImageTransparency = 0.28,
		}):Play()
		TweenService:Create(burst, TweenInfo.new(1.45, Enum.EasingStyle.Linear), { Rotation = 150 }):Play()
		for _, pop in { heroScale, headingScale, prizeScale } do
			TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		TweenService:Create(heading, TweenInfo.new(0.16), { TextTransparency = 0 }):Play()
		TweenService:Create(prize, TweenInfo.new(0.16), { TextTransparency = 0 }):Play()
		TweenService:Create(detail, TweenInfo.new(0.16), { TextTransparency = 0 }):Play()

		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local cashBurst = Shard.get("CashBurstController")
		if gift.Kind == "Cash" and cashBurst and root then
			cashBurst:burst(gift.Amount, (root :: BasePart).Position + Vector3.new(0, 3, 0))
		end

		task.wait(1.35)
		TweenService:Create(layer, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1 }):Play()
		tile.scale.Scale = 1.3
		TweenService:Create(tile.scale, POP, { Scale = 1 }):Play()
		task.wait(0.32)
		finish()
	end, function(err)
		warn("PlaytimeRewardController reveal failed: " .. tostring(err))
		finish()
	end)
end

--- Public (the topbar button): open the panel, or shut it if it is up.
function PlaytimeRewardController.toggle(self)
	if self._gui and self._gui.Enabled then
		self:close()
	else
		self:open()
	end
end

function PlaytimeRewardController.open(self)
	if not self._gui then
		return
	end
	Dispatcher:Publish("CloseAllPages")
	self._gui.Enabled = true
	self._scale.Scale = 0.9
	TweenService:Create(self._scale, POP, { Scale = 1 }):Play()
	self:_paint()
	GamepadInput.setModal("PlaytimeRewardController", true)
	GamepadInput.bind({ actionName = PAD_CLOSE, keyCode = Enum.KeyCode.ButtonB, callback = function()
		self:close()
	end })
	self._previousSelection = GuiService.SelectedObject
	local state = self._state
	local nextTile = state and self._tiles[state.claimed + 1]
	if nextTile and GamepadInput.isGamepadActive() then
		GuiService.SelectedObject = nextTile.hit
	end
end

function PlaytimeRewardController.close(self)
	if not (self._gui and self._gui.Enabled) then
		return
	end
	self._gui.Enabled = false
	GamepadInput.unbind(PAD_CLOSE)
	GamepadInput.setModal("PlaytimeRewardController", false)
	local previous = self._previousSelection
	GuiService.SelectedObject = if previous and previous:IsDescendantOf(game) then previous else nil
	self._previousSelection = nil
	self:_handBackToPlay()
end

--[[ The panel the tutorial ended on has been shut: NOW Play calls for the next run, arrow and all
	(`PlaytimeRewardConfig.ShowAfterTutorial`). Once. A start of a run counts as shutting it too —
	that is the press the beckon was going to ask for. ]]
function PlaytimeRewardController._handBackToPlay(self)
	if self._afterTutorial then
		self._afterTutorial = false
		Dispatcher:Publish(RaceConfig.PlayBeckon.Event)
	end
end

--- The tutorial is over (`PlaytimeRewardConfig.AfterTutorialEvent`): open the panel, and remember
--- that Play is waiting on it. No panel to open (not built) hands straight back to Play.
function PlaytimeRewardController._onTutorialDone(self)
	self._afterTutorial = true
	if self._gui then
		self:open()
	else
		self:_handBackToPlay()
	end
end

--[[ `PlaytimeRewardConfig.JoinOpen`: a gift was ready on join, so open the panel once the daily
	screen has had its turn (`DailyRewardController.joinOpenPending`) and nothing else is up (its
	`busy`). Re-checks the gift at the moment of opening; a claim from the button meanwhile is fine. ]]
function PlaytimeRewardController._joinOpen(self)
	local Daily = Shard.get("DailyRewardController")
	local deadline = os.clock() + PlaytimeRewardConfig.JoinOpen.MaxWait
	while os.clock() < deadline do
		local waiting = Daily ~= nil and (Daily:joinOpenPending() or Daily:busy() ~= nil)
		if not waiting and self._gui and not self._gui.Enabled then
			local _, ready = self:_label()
			if ready then
				self:open()
			end
			return
		end
		task.wait(1)
	end
end

-- === The server's word ======================================================

function PlaytimeRewardController._onState(self, payload: unknown)
	if type(payload) ~= "table" or type((payload :: any).gifts) ~= "table" then
		return
	end
	local state = payload :: any
	state.receivedAt = os.clock()
	self._state = state
	self._claimPending = 0
	local gift = type(state.justClaimed) == "number" and state.gifts[state.justClaimed]
	if gift and gift.Kind then
		--- The reply to a claim: the tile opens, and the button says what landed for a moment
		--- (published by `_reveal` as the wrapping gives way).
		self._holdUntil = os.clock() + SHOW_REWARD
		self._lastLabel = nil
		self:_paint()
		self:_reveal(state.justClaimed, gift)
		return
	end
	self:_paint()
	self:_publish()
	--- The first ladder of the session is the join: one panel, only if a gift is already waiting.
	if not self._joinChecked then
		self._joinChecked = true
		local _, ready = self:_label()
		if ready and PlaytimeRewardConfig.JoinOpen.Enabled then
			task.spawn(self._joinOpen, self)
		end
	end
end

PlaytimeRewardController:withRemoteEvents({
	REMOTES.Claim,
	{
		[REMOTES.State] = function(payload: unknown)
			PlaytimeRewardController:_onState(payload)
		end,
		--- A run puts the panel away; the button comes back with the lobby.
		RaceStart = function()
			--- They found Play on their own; nothing is left to beckon them to. Cleared BEFORE the
			--- close, which would otherwise hand back to Play as the run starts.
			PlaytimeRewardController._afterTutorial = false
			PlaytimeRewardController:close()
		end,
	},
})

PlaytimeRewardController:withLifecycle({
	init = function(self)
		self._state = nil
		self._holdUntil = 0
		self._lastLabel = nil :: string?
		self._lastReady = nil :: boolean?
		self._tiles = {}
		self._joinChecked = false
		self._claimPending = 0 -- os.clock() deadline while a claim is in flight
		self._revealing = false
		self._celebration = nil
	end,
	start = function(self)
		if not PlaytimeRewardConfig.Enabled then
			return
		end
		Dispatcher:Subscribe(PlaytimeRewardConfig.AfterTutorialEvent, function()
			self:_onTutorialDone()
		end)
		task.spawn(function()
			--- Off the start thread: the kit's shelf waits for the UI to land (`ArcadeKit.shelf`).
			self:_build()
			self:_paint()
			while true do
				task.wait(1)
				if self._state then
					self:_publish()
					if self._gui.Enabled then
						self:_paint()
					end
				end
			end
		end)
	end,
})

return PlaytimeRewardController
