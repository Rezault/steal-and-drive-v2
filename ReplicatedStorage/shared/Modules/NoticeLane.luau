--[[
	NoticeLane  (client)
	--------------------
	One left-side lane that the lobby's notices share instead of each claiming the top centre
	(Leaf, 2026-10-06). `Configs/NoticeLaneConfig` has where it is, what is in it and why.

	A MEMBER KEEPS ITS OWN ScreenGui, its own layer and its own clock. The lane only decides WHERE
	the card is: a member calls `show` when it comes up and `hide` when it goes, and the lane slides
	it in or out and stacks every member that is up, in `Order`, down from the lane's top.

	ONE SPACE FOR EVERY MEMBER. Each card sits straight in its own ScreenGui, and those differ in
	`IgnoreGuiInset` and `ScreenInsets`. `AbsolutePosition` is one shared space for all of them (a
	ScreenGui that ignores the inset reports its own top as minus the inset), so the lane works in
	that space and writes each card's offset relative to its own ScreenGui's `AbsolutePosition`.

	THE TOP IS MEASURED OFF THE RAIL, not configured: the first visible rail button's top, and just
	right of the rail. The rail is a place edit that has moved before, and a lane pinned to numbers
	would quietly end up on top of it.

	On phones and short windows (2026-10-12), compact cards use the upper-right instead: stacking
	the desktop cards beside the rail covered the player's car and the Play button.

	=== A CAP AND A QUEUE, 2026-10-13 =========================================================
	WAS: every member that called `show` came up at once, so the trip home stacked three or four
	cards down the side (Aleafo: "this is excessive af"). IS: at most `NoticeLaneConfig.MaxVisible`
	cards are up (`MaxVisibleCompact` on a phone), and the rest WAIT, first come first served, for
	one to go. A waiting member has not been shown, so its clock must not run yet: `show` takes an
	`onShown` that the lane calls at the moment the card really comes up, and that is where a member
	starts its hold timer. A quiet member (`slide` false) is a line, not a card, and skips the queue.

	A member that is not PLACED (`join`'s `placed` false) still takes its turn in the queue but keeps
	its own spot on screen: the discovery card, which rests top-right on a PC. It counts against the
	cap because the cap is about how much is on screen at once, wherever it is.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local NoticeLaneConfig = require(ReplicatedStorage.shared.Configs.NoticeLaneConfig)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local NoticeLane = {}
NoticeLane.__index = NoticeLane

export type Member = typeof(setmetatable(
	{} :: {
		card: GuiObject,
		order: number,
		slide: boolean,
		up: boolean,
		fresh: boolean,
		token: number,
		tween: Tween?,
		compactAspect: number?,
		size: UDim2,
		placed: boolean,
		wanted: boolean,
		seq: number,
		onShown: (() -> ())?,
	},
	NoticeLane
))

local members: { Member } = {}
local hookedRail: GuiObject? = nil
local hookedCamera: Camera? = nil
local lastOrigin: Vector2? = nil
local queued = false
--- Arrival order for the queue: every `show` of a card that is down takes the next number.
local arrivals = 0

local layout: () -> ()

function NoticeLane.compact(): boolean
	local viewport = if workspace.CurrentCamera then workspace.CurrentCamera.ViewportSize else Vector2.new(1280, 720)
	return viewport.Y <= 600 or viewport.X <= 700
		or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
end

--- Re-run the layout once, on the next resumption, however many changes ask for it this frame.
local function requestLayout()
	if queued then
		return
	end
	queued = true
	task.defer(function()
		queued = false
		layout()
	end)
end

local function findRail(): GuiObject?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local root = playerGui and playerGui:FindFirstChild(UIRoot.name())
	local hud = root and root:FindFirstChild("HUD")
	local rail = hud and hud:FindFirstChild("Rail")
	return if rail and rail:IsA("GuiObject") then rail else nil
end

--- Follow the rail and the viewport, so a resize or a rail that lays itself out late re-stacks.
local function hook(rail: GuiObject?)
	if rail and rail ~= hookedRail then
		hookedRail = rail
		for _, property in { "AbsolutePosition", "AbsoluteSize", "Visible" } do
			rail:GetPropertyChangedSignal(property):Connect(requestLayout)
		end
	end
	local camera = workspace.CurrentCamera
	if camera and camera ~= hookedCamera then
		hookedCamera = camera
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(requestLayout)
	end
end

--[[ The lane's top-left, in the shared `AbsolutePosition` space. The rail's measurement when it is
	on screen, else the last one taken, else the configured fallback. ]]
local function origin(): Vector2
	local rail = findRail()
	hook(rail)
	-- On phones the rail starts beside the player's car; keep short notices above the jump area instead (2026-10-12).
	if NoticeLane.compact() then
		local viewport = if workspace.CurrentCamera then workspace.CurrentCamera.ViewportSize else Vector2.new(1280, 720)
		return Vector2.new(viewport.X - NoticeLane.width() - 12, math.max(70, viewport.Y * 0.12))
	end
	if rail and rail.Visible and rail.AbsoluteSize.X > 0 then
		local top = math.huge
		for _, child in rail:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				top = math.min(top, child.AbsolutePosition.Y)
			end
		end
		if top == math.huge then
			top = rail.AbsolutePosition.Y
		end
		lastOrigin = Vector2.new(rail.AbsolutePosition.X + rail.AbsoluteSize.X + NoticeLaneConfig.Gap, top)
	end
	if lastOrigin then
		return lastOrigin
	end
	local viewport = if workspace.CurrentCamera then workspace.CurrentCamera.ViewportSize else Vector2.new(1280, 720)
	return Vector2.new(viewport.X * NoticeLaneConfig.FallbackX, viewport.Y * NoticeLaneConfig.FallbackY)
end

--- Where a card's own ScreenGui starts in the shared space.
local function base(card: GuiObject): Vector2
	local gui = card:FindFirstAncestorOfClass("ScreenGui")
	return if gui then gui.AbsolutePosition else Vector2.zero
end

--- Off the left edge, at height `y`: the card's width plus a margin, measured if it can be.
local function offLeft(member: Member, y: number): UDim2
	local at = base(member.card)
	local width = member.card.AbsoluteSize.X
	if width <= 0 then
		width = NoticeLaneConfig.Width.Max
	end
	return UDim2.fromOffset(-width - 16 - at.X, y - at.Y)
end

local function tweenTo(member: Member, goal: UDim2, seconds: number, style: Enum.EasingStyle, direction: Enum.EasingDirection): Tween
	if member.tween then
		member.tween:Cancel()
	end
	local tween = TweenService:Create(member.card, TweenInfo.new(seconds, style, direction), { Position = goal })
	member.tween = tween
	tween:Play()
	return tween
end

function layout()
	local at = origin()
	table.sort(members, function(a, b)
		return a.order < b.order
	end)
	local y = at.Y
	for _, member in members do
		if member.up and member.placed then
			if member.compactAspect then
				member.card.Size = if NoticeLane.compact()
					then UDim2.fromOffset(NoticeLane.width(), NoticeLane.width() / member.compactAspect)
					else member.size
			end
			local own = base(member.card)
			local goal = UDim2.fromOffset(at.X - own.X, y - own.Y)
			if member.fresh then
				member.fresh = false
				if member.slide then
					member.card.Position = offLeft(member, y)
					tweenTo(member, goal, NoticeLaneConfig.SlideIn, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
				else
					member.card.Position = goal
				end
			elseif member.card.Position ~= goal then
				local tween = member.tween
				if tween and tween.PlaybackState == Enum.PlaybackState.Playing then
					--- Still sliding in: retarget the slide rather than cutting it short.
					tweenTo(member, goal, NoticeLaneConfig.Shift, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				elseif member.slide then
					tweenTo(member, goal, NoticeLaneConfig.Shift, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				else
					member.card.Position = goal
				end
			end
			local height = member.card.AbsoluteSize.Y
			if height > 0 then
				y += height + NoticeLaneConfig.Spacing
			end
		end
	end
end

--[[ Put `card` in the lane at slot `order` (`NoticeLaneConfig.Order`). It starts down: nothing moves
	until `show`. `slide` false places it without a tween, for a quiet line that is simply there.
	`placed` false queues it without moving it: the member positions the card itself. ]]
function NoticeLane.join(card: GuiObject, order: number, slide: boolean?, compactAspect: number?, placed: boolean?): Member
	local member = setmetatable({
		card = card,
		order = order,
		slide = slide ~= false,
		up = false,
		fresh = false,
		token = 0,
		tween = nil,
		compactAspect = compactAspect,
		size = card.Size,
		placed = placed ~= false,
		wanted = false,
		seq = 0,
		onShown = nil,
	}, NoticeLane)
	if member.placed then
		card.AnchorPoint = Vector2.zero
	end
	--- A card whose height lands late (a ScreenGui switched on this frame) re-stacks the ones below it.
	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if member.up then
			requestLayout()
		end
	end)
	table.insert(members, member)
	return member
end

--- The width a text member (one with no width rule of its own) should take, in pixels.
function NoticeLane.width(): number
	local spec = NoticeLaneConfig.Width
	local viewport = if workspace.CurrentCamera then workspace.CurrentCamera.ViewportSize else Vector2.new(1280, 720)
	if NoticeLane.compact() then
		local compact = NoticeLaneConfig.CompactWidth
		return math.clamp(math.round(viewport.X * compact.Scale), compact.Min, compact.Max)
	end
	return math.clamp(math.round(viewport.X * spec.Scale), spec.Min, spec.Max)
end

--- How many cards may be up at once on this screen.
function NoticeLane.cap(): number
	return if NoticeLane.compact() then NoticeLaneConfig.MaxVisibleCompact else NoticeLaneConfig.MaxVisible
end

--[[ Bring up every waiting member there is room for, oldest first, then lay the lane out. The
	`onShown`s run last, after the cards have their slots, and each runs once. ]]
local function pump()
	local room = NoticeLane.cap()
	for _, member in members do
		if member.up and member.slide then
			room -= 1
		end
	end
	local raised = {}
	while true do
		local pick: Member? = nil
		for _, member in members do
			if member.wanted and not member.up and (not member.slide or room > 0) then
				if pick == nil or member.seq < pick.seq then
					pick = member
				end
			end
		end
		if not pick then
			break
		end
		pick.up = true
		pick.fresh = true
		pick.token += 1
		if pick.slide then
			room -= 1
		end
		table.insert(raised, pick)
	end
	layout()
	for _, member in raised do
		local onShown = member.onShown
		member.onShown = nil
		if onShown then
			onShown()
		end
	end
end

--[[ Ask for the card to come up. It comes up now if the lane has room (`cap`), else it waits its
	turn; `onShown` runs at the moment it is really up, which is where a member starts its clock.
	Showing one that is already up keeps it where it is and runs `onShown` straight away; showing one
	that is waiting keeps its place in the queue and takes the newer `onShown`. ]]
function NoticeLane.show(self: Member, onShown: (() -> ())?)
	if self.up then
		self.token += 1
		layout()
		if onShown then
			onShown()
		end
		return
	end
	if not self.wanted then
		self.wanted = true
		arrivals += 1
		self.seq = arrivals
	end
	self.onShown = onShown
	pump()
end

--[[ Take the card down: it slides out to the left (or goes at once, for a quiet member) and the
	members under it close the gap straight away. `onHidden` runs once it is off screen, and only if
	nothing showed it again meanwhile, which is the moment a member switches its ScreenGui off. ]]
function NoticeLane.hide(self: Member, onHidden: (() -> ())?)
	--- Still waiting: it leaves the queue without ever having been on screen.
	self.wanted = false
	self.onShown = nil
	if not self.up then
		if onHidden then
			onHidden()
		end
		return
	end
	self.up = false
	self.fresh = false
	self.token += 1
	local token = self.token
	if self.slide and self.placed then
		local y = self.card.AbsolutePosition.Y
		local tween = tweenTo(self, offLeft(self, y), NoticeLaneConfig.SlideOut, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and self.token == token and onHidden then
				onHidden()
			end
		end)
	else
		if self.tween then
			self.tween:Cancel()
		end
		if onHidden then
			onHidden()
		end
	end
	--- Its slot is free the moment it starts out, so the next waiting card comes in as it goes.
	pump()
end

function NoticeLane.isUp(self: Member): boolean
	return self.up
end

--- Up, or waiting for its turn: anything a `hide` would still have to take down.
function NoticeLane.isPending(self: Member): boolean
	return self.up or self.wanted
end

return NoticeLane
