--[[
	PlaytimeRewardController  (client)
	----------------------------------
	Holds the playtime gift ladder the server sends (`PlaytimeRewardService`), counts down with this
	client's own clock, draws the FREE GIFTS panel, and publishes what the topbar button should say
	(`LabelEvent`); `TopbarController` owns the button itself, as it owns every topbar icon. It
	DECIDES nothing: a press is a request, and a gift opens off the server's reply, the same rule the
	daily calendar keeps (`DailyRewardController`).

	=== THE PANEL (2026-10-19) =================================================================

	A row of wrapped gifts, each with what is left until it opens under it. The next gift that is due
	wears CLAIM; one due behind it says NEXT (they open in order, `PlaytimeRewardConfig` note 3); the
	rest count down. A claimed gift is OPENED: the wrapping gives way to what was inside — the cash,
	the revive, or the car turning in its tile.

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
	if gift.Kind == "Cash" then
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
	local gap = 0.02
	local width = (1 - gap * (count - 1)) / count
	local holder = Instance.new("Frame")
	holder.Position = UDim2.fromScale((index - 1) * (width + gap), 0)
	holder.Size = UDim2.fromScale(width, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = row
	local face = ArcadeKit.card(holder, { face = ArcadeKit.Faces.Purple, sunray = false })
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local wrapped = Instance.new("ImageLabel")
	wrapped.AnchorPoint = Vector2.new(0.5, 0.5)
	wrapped.Position = UDim2.fromScale(0.5, 0.36)
	wrapped.Size = UDim2.fromScale(0.75, 0.5)
	wrapped.BackgroundTransparency = 1
	wrapped.Image = UIAssets.url(UIAssets.GiftGlyph)
	wrapped.ScaleType = Enum.ScaleType.Fit
	wrapped.ZIndex = 4
	wrapped.Parent = face

	--- What was inside: a car turns in its tile; money and revives are said in big type.
	local view = CarViewport.new(face, "Car")
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.Position = UDim2.fromScale(0.5, 0.33)
	view.Size = UDim2.fromScale(0.95, 0.5)
	view.ZIndex = 4
	local prize = ArcadeKit.text(face, 0.05, 0.12, 0.9, 0.4, GOLD, true)
	prize.ZIndex = 5
	prize.Visible = false

	local line = ArcadeKit.text(face, 0.05, 0.64, 0.9, 0.14, WHITE, true)
	line.ZIndex = 5
	local claim, caption = ArcadeKit.button(face, "Claim", 0.08, 0.66, 0.84, 0.26)
	caption.Text = TEXT.Claim
	local hit = claim
	if not claim:IsA("GuiButton") then
		--- The kit's face may be a picture; a cover takes the press (`TradeController`'s button note).
		local cover = Instance.new("TextButton")
		cover.Text = ""
		cover.BackgroundTransparency = 1
		cover.Size = UDim2.fromScale(1, 1)
		cover.ZIndex = 10
		cover.Parent = claim
		hit = cover
	end
	;(hit :: GuiButton).Selectable = true
	;(hit :: GuiButton).Activated:Connect(function()
		self:getRemoteEvent(REMOTES.Claim):Fire()
	end)
	return { holder = holder, scale = scale, wrapped = wrapped, view = view, prize = prize, line = line, claim = claim, hit = hit, shown = nil }
end

function PlaytimeRewardController._build(self)
	local gui = Instance.new("ScreenGui")
	gui.Name = "PlaytimeGifts"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local dim = Instance.new("TextButton")
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Selectable = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.55
	dim.Parent = gui
	dim.Activated:Connect(function()
		self:close()
	end)

	--- A button that does nothing, so a click on the panel stops here and not on the dim under it.
	local holder = Instance.new("TextButton")
	holder.Text = ""
	holder.AutoButtonColor = false
	holder.Selectable = false
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(0.62, 0.5)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 2.3
	ratio.Parent = holder
	local bounds = Instance.new("UISizeConstraint")
	bounds.MinSize = Vector2.new(330, 0)
	bounds.MaxSize = Vector2.new(820, 360)
	bounds.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local panel, title, body = ArcadeKit.panel(holder, 0.2, 2.3)
	title.Text = TEXT.Title
	title.ZIndex = 6
	local close, x = ArcadeKit.button(panel, "Decline", 0.93, 0.03, 0.055, 0.14)
	x.Text = "X"
	local closeHit = if close:IsA("GuiButton") then close else nil
	if not closeHit then
		local cover = Instance.new("TextButton")
		cover.Text = ""
		cover.BackgroundTransparency = 1
		cover.Size = UDim2.fromScale(1, 1)
		cover.ZIndex = 10
		cover.Parent = close
		closeHit = cover
	end
	;(closeHit :: GuiButton).Activated:Connect(function()
		self:close()
	end)

	local subtitle = ArcadeKit.text(body, 0.03, 0.03, 0.94, 0.13, WHITE, true)
	subtitle.Text = TEXT.Subtitle
	subtitle.ZIndex = 6
	local row = Instance.new("Frame")
	row.Position = UDim2.fromScale(0.03, 0.2)
	row.Size = UDim2.fromScale(0.94, 0.76)
	row.BackgroundTransparency = 1
	row.Parent = body

	self._tiles = {}
	for index in PlaytimeRewardConfig.Gifts do
		self._tiles[index] = self:_buildTile(row, index, #PlaytimeRewardConfig.Gifts)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._gui, self._scale = gui, scale
end

--- Repaint every tile from the state: opened, claimable, next in line, or counting down.
function PlaytimeRewardController._paint(self)
	local state = self._state
	if not (self._gui and state) then
		return
	end
	local played = self:_played()
	for index, tile in self._tiles do
		local gift = state.gifts[index]
		local opened = index <= state.claimed and gift and gift.Kind ~= nil
		local left = (gift and gift.Minutes or 0) * 60 - played
		local isNext = index == state.claimed + 1
		tile.wrapped.Visible = not opened
		tile.prize.Visible = opened and gift.Kind ~= "Car"
		tile.claim.Visible = isNext and left <= 0
		tile.line.Visible = not tile.claim.Visible
		if opened then
			tile.line.Text = if gift.Kind == "Car" then rewardText(gift) else "OPENED"
			tile.prize.Text = rewardText(gift)
			if gift.Kind == "Car" and tile.shown ~= gift.Body then
				tile.shown = gift.Body
				CarViewport.set(tile.view, gift.Body)
			end
		else
			if tile.shown then
				tile.shown = nil
				CarViewport.clear(tile.view)
			end
			tile.line.Text = if left <= 0 then TEXT.Next else clock(left)
		end
		tile.line.TextColor3 = if left <= 0 and not opened then GOLD else WHITE
	end
end

--- The moment a gift opens: its tile pops and the wrapping gives way (the paint does the swap).
function PlaytimeRewardController._reveal(self, index: number)
	local tile = self._tiles and self._tiles[index]
	if tile then
		tile.scale.Scale = 1.25
		TweenService:Create(tile.scale, POP, { Scale = 1 }):Play()
	end
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
	local gift = type(state.justClaimed) == "number" and state.gifts[state.justClaimed]
	if gift and gift.Kind then
		--- The reply to a claim: the tile opens, and the button says what landed for a moment.
		self._holdUntil = os.clock() + SHOW_REWARD
		self._lastLabel = nil
		Dispatcher:Publish(PlaytimeRewardController.LabelEvent, rewardText(gift), false)
		GameplayFeedback.play("DailyClaimed")
		self:_paint()
		self:_reveal(state.justClaimed)
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local burst = Shard.get("CashBurstController")
		if gift.Kind == "Cash" and burst and root then
			burst:burst(gift.Amount, (root :: BasePart).Position + Vector3.new(0, 3, 0))
		end
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
