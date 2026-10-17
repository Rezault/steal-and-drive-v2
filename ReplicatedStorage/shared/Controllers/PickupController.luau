--[[
	PickupController  (client)
	--------------------------
	The player's half of a road pickup: the slot on the screen, the key that spends it, and the beat
	that plays when a pack is collected.

	`ObstacleController` does the noticing — it is the only thing on this client that polls the car
	against the road — and calls `collected(name, hitBox)` on the frame the car drives through a
	pack. Everything after that is here.

	=== THE SLOT IS THE SERVER'S, AND THIS ONLY DRAWS IT ========================================

	Nothing in this file decides what you are carrying. `ObstacleService` validated the pickup and
	wrote the answer to a player attribute (`PickupConfig.SlotAttribute`); this watches that attribute
	and paints it. The key does not spend a pack either — it fires `UsePickup`, which carries no
	payload at all, and the server acts on its own record.

	That is not ceremony. The health pack moves HP, HP is server-authoritative, and this is the file a
	cheating client would replace. The rule it leaves behind is: the worst a compromised client can do
	is press the button it already had.

	`_autoUse` is the one place this file acts on the slot rather than drawing it, and it is inside
	that rule rather than an exception to it: a nitro pack collected on a depleted bottle presses the
	same button, on the same remote, carrying the same nothing. It lives here because the tank is a
	number no server can read (see below), so this is the only side that knows the pack was needed.
	The server still owns the slot, still refuses a wrecked race, and still fires the `PickupUsed`
	that pays. See `PickupConfig`'s "BANKED, EXCEPT WHEN YOU NEEDED IT".

	WATCHING AN ATTRIBUTE RATHER THAN A REMOTE is what makes the slot survive things no signal would.
	A respawn, a rejoin, a GUI rebuilt mid-race, a controller started after the pickup happened — all
	of them can read the current value, where a listener can only hear about changes it was present
	for. `PickupUsed` exists alongside it for the EVENT (the flash, the sound, the nitro payout),
	which is the thing an attribute cannot express.

	=== WHAT THE CLIENT ACTUALLY APPLIES =======================================================

	Exactly one thing: the nitro. `NitroController._tank` is a local number this client already owns
	outright (see `NitroConfig`), so the server clears the slot and fires `PickupUsed` and this tops
	the bottle up. The heal has already landed by the time that arrives — for a health pack this
	handler only plays the beat. `PickupConfig`'s header argues at length why that split is honest
	rather than a hole.

	The auto-use follows the same ownership. The health pack spends itself server-side, before a slot
	is ever set, so this file never sees one; the nitro pack banks, arrives, and `_autoUse` sends it
	back out on the next frame. That costs a round trip the health rule does not pay and it is the
	price of the tank being ours — the visible difference is the plate appearing for a moment before
	it fades, which is drawn without its punch for exactly that reason.

	=== THE SCREEN IS BUILT IN CODE, FOR NOW ===================================================

	The rest of the driving UI is authored in Studio so its layout can be nudged in the Explorer
	(`DrivingHudController`'s header). This is not, and `PickupConfig.Hud` says why: the slot is new,
	nobody has decided where it wants to live, and a feature that cannot ship without a Studio edit
	cannot be reviewed from the repository. Every number it is drawn from is in that config block, so
	moving it is a config change until the authored version lands.

	=== IT IS ONLY THERE WHILE IT IS HOLDING SOMETHING =========================================

	The slot is drawn when a pack lands in it and taken off the screen when the pack is spent. There
	is no empty resting plate, which is a reversal of how this first shipped, and `PickupConfig.Hud`
	carries the argument: a permanent dim square is furniture, a keycap under an empty box is a
	button advertised for a press that does nothing, and the first pack a player collects teaches
	both halves of the feature at the one moment the lesson is useful.

	Everything that follows from it lives in `_paint` and `_hide`. Nothing else on this client has to
	ask whether the slot is up: the attribute is still the single source of what is being held, and
	the visibility is only ever read off it.

	=== ONE BUTTON, THREE INPUT SURFACES =======================================================

	Q on a keyboard, the right bumper on a pad (beside the nitro's L1 — the two resources you spend
	sit under the two bumpers), and on touch the slot ITSELF is the button. That third one is why
	there is no separate touch control: a phone screen during a race already carries six
	(`DrivingHudController`), and a seventh is the one that finally crowds the steering.

	The pad glyph is not drawn here — `Modules/ControlLegend` draws it, via `LegendConfig`, which is
	how every other race verb reaches a console player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local PickupConfig = require(ReplicatedStorage.shared.Configs.PickupConfig)

local PickupController = Shard.new("PickupController")

-- The kit's font, as everywhere else this project builds a screen in code.
local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

local ACTION = "PickupUse"

-- === The screen =============================================================

--[[ The slot: a rounded plate, a stroke, the pack's glyph, and a keycap under it on desktop.

	SIZED OFF THE VIEWPORT'S HEIGHT on both axes (`RelativeYY`), which is the same treatment the gauge
	cluster gets and for the same reason: a width-relative square is a different physical size on a
	phone and an ultrawide, and this one has to sit in a fixed relationship to the cluster beside
	it. ]]
function PickupController._build(self)
	local hud = PickupConfig.Hud

	local gui = Instance.new("ScreenGui")
	gui.Name = "PickupHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	--- Beside the near-miss toast's 900 and under the respawn screen's 999: a slot still on screen
	--- when a wreck lands belongs behind the decision the player is being asked to make.
	gui.DisplayOrder = 900
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local slot = Instance.new("ImageButton")
	slot.Name = "Slot"
	slot.AnchorPoint = Vector2.new(0.5, 0.5)
	slot.Position = UDim2.fromScale(hud.Position.X, hud.Position.Y)
	--[[ BOTH axes off the viewport's HEIGHT, which is what `RelativeYY` means and is what makes this
		square without a `UIAspectRatioConstraint` at all. Equal scales against one axis ARE a
		square, at every aspect ratio, where equal scales against two axes are a rectangle that
		changes shape with the window.

		The constraint was the obvious way to write this and is the wrong one: its `DominantAxis`
		defaults to Width, so a zero-width `fromScale(0, h)` box would be squared to zero rather than
		grown to its height. ]]
	slot.Size = UDim2.fromScale(hud.Size, hud.Size)
	slot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	--- Built hidden and fully transparent, because an empty slot is not drawn at all (see `_paint`).
	--- The plate's colour is the pack's and is written when one arrives.
	slot.Visible = false
	slot.BackgroundTransparency = 1
	slot.Image = ""
	slot.AutoButtonColor = false
	--- Only clickable on touch: the slot is the touch BUTTON and nothing else. On desktop it is a
	--- readout, and a readout that eats a click in the middle of a race is a readout that steals a
	--- steering input from someone playing with a mouse.
	slot.Active = false
	slot.Parent = gui

	--[[ The punch when a pack lands rides a `UIScale` rather than the button's own Size, for
		`NearMissController`'s reason: the glyph inside is a scaled image and animating the box would
		re-flow it mid-pop. A UIScale scales the rendered result and re-flows nothing. ]]
	local scale = Instance.new("UIScale")
	scale.Parent = slot

	local corner = Instance.new("UICorner")
	--- Fractions of the slot's own height, so the plate keeps its proportions at every size rather
	--- than going square on a phone and round on a monitor.
	corner.CornerRadius = UDim.new(hud.CornerRadius, 0)
	corner.Parent = slot

	local stroke = Instance.new("UIStroke")
	stroke.Color = hud.StrokeColor
	stroke.Thickness = 2 -- resolved from the viewport; see `_resolveStroke`
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = slot

	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromScale(0.74, 0.74)
	glyph.BackgroundTransparency = 1
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.ImageTransparency = 1
	glyph.Parent = slot

	--- The keycap, on desktop only. Hidden on touch (the slot is the button) and on a console (the
	--- legend draws the pad glyph instead) — see `_syncCap`.
	local cap = Instance.new("TextLabel")
	cap.Name = "Cap"
	cap.AnchorPoint = Vector2.new(0.5, 0)
	cap.Position = UDim2.fromScale(0.5, 1.05)
	cap.Size = UDim2.fromScale(1, hud.CapHeight)
	cap.BackgroundTransparency = 1
	cap.FontFace = FONT
	cap.Text = hud.CapText
	cap.TextColor3 = Color3.new(1, 1, 1)
	cap.TextScaled = true
	cap.TextTransparency = 1
	cap.Parent = slot

	self._gui = gui
	self._slot = slot
	self._scale = scale
	self._stroke = stroke
	self._glyph = glyph
	self._cap = cap

	--- Tap-to-use on touch. Bound unconditionally and gated by `slot.Active`, so a device that
	--- gains touch mid-session (a detachable keyboard) needs no rebinding.
	slot.Activated:Connect(function()
		self:_use()
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

--[[ The stroke's thickness, which is the one measurement on this slot with no scale form.

	Re-resolved whenever the slot is shown rather than once at build, exactly as
	`NearMissController._resolveOutline` is and for the same reason: the viewport changes under a
	rotated phone or a resized window. ]]
function PickupController._resolveStroke(self)
	local camera = workspace.CurrentCamera
	if not (camera and self._stroke) then
		return
	end
	self._stroke.Thickness = math.max(1, camera.ViewportSize.Y * PickupConfig.Hud.Size * PickupConfig.Hud.StrokeThickness)
end

--[[ Who the slot is being drawn for. Three surfaces, and only one of them wants the keycap:

	  touch    the slot is the button, so it is Active and wears no cap — a keycap on a thing you
	           tap is a lie about how to use it.
	  gamepad  the cap is the wrong glyph and the right one is the legend's, which draws the pad's
	           own ButtonR1 mark (`LegendConfig`). No cap here either.
	  keyboard the cap, which is the only place Q is ever written down on screen.

	Asked every time the slot is shown rather than once at boot, because `TouchEnabled` lies at boot
	on some devices — a known trap in this project's driving control surface, and the reason
	`DrivingHudController` re-asks too. ]]
function PickupController._syncCap(self)
	if not self._slot then
		return
	end
	local touch = UserInputService.TouchEnabled
	local pad = UserInputService.GamepadEnabled
	self._slot.Active = touch
	self._capWanted = not touch and not pad
end

-- === Painting it ============================================================

--- Cancel anything still in flight rather than merely fencing it: a fade already running would go on
--- writing transparency over the top of the next pack's arrival. Same treatment as the near-miss
--- toast, and for the same reason.
function PickupController._tween(self, inst, time: number, props, style: Enum.EasingStyle?)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(inst, info, props)
	table.insert(self._tweens, tween)
	tween:Play()
	return tween
end

function PickupController._cancelTweens(self)
	for _, tween in self._tweens do
		tween:Cancel()
	end
	table.clear(self._tweens)
end

--[[ Repaint the slot for whatever the server says is in it.

	Called from the attribute watcher, so it is the ONE place the slot's look is decided and it is
	driven by the authority rather than by whatever this file last did. A pack arriving raises the
	plate and punches it; a slot with nothing in it is not drawn at all, so the other half of this
	is `_hide` rather than a resting state.

	`animate` is false when the slot is being repainted for a reason that is not a pack arriving or
	leaving: a race starting, a GUI rebuilt, a rejoin. Both animations belong to the event rather
	than to the state, so that case gets neither the punch on the way in nor the fade on the way
	out. ]]
function PickupController._paint(self, name: string?, animate: boolean)
	if not self._slot then
		return
	end
	local hud = PickupConfig.Hud
	local pack = PickupConfig.pack(name)
	self:_cancelTweens()
	--[[ Retires any fade still in flight, and it has to be done here rather than in `_hide` so that
		BOTH branches do it: a pack collected during a fade-out cancels that fade's tweens above, but
		the `Visible = false` it booked is a delayed thread that cancelling a tween cannot reach. The
		token is what that thread checks, and this is the only line that moves it. ]]
	self._hideToken += 1

	if pack then
		self._slot.Visible = true
		self._slot.BackgroundColor3 = pack.Color
		self._slot.BackgroundTransparency = 0
		self._stroke.Transparency = 0
		self._glyph.Image = "rbxassetid://" .. tostring(pack.Icon)
		self._glyph.ImageTransparency = 0
		self._cap.TextTransparency = if self._capWanted then 0 else 1
		if animate then
			self._scale.Scale = hud.FillScale
			self:_tween(self._scale, hud.FillTime, { Scale = 1 }, Enum.EasingStyle.Back)
		else
			self._scale.Scale = 1
		end
	else
		self:_hide(animate)
	end
end

--[[ Take the slot off the screen, because an empty one is not drawn (`PickupConfig.Hud`).

	FADED WHEN A PACK WAS JUST SPENT, CUT OTHERWISE. The fade is the tail of the player's own press
	and reads as the pack leaving; the same fade at a race start or on a wreck would be the HUD
	announcing a thing that did not just happen, and on a wreck it would play under the respawn
	screen that is arriving on top of it.

	`Visible` rather than a parent swap or a destroy: the slot keeps its place in the ScreenGui, so
	the toast beside it is untouched and the next pack is one property away from being back. The
	delayed hide is guarded on `_hideToken` rather than on the tween finishing, because a tween that
	is cancelled mid-fade still ends. ]]
function PickupController._hide(self, animate: boolean)
	local slot = self._slot
	if not slot then
		return
	end
	self._scale.Scale = 1

	--- Nothing to fade if it is already gone, which is the common case: every race starts here.
	if not (animate and slot.Visible) then
		slot.Visible = false
		slot.BackgroundTransparency = 1
		self._glyph.ImageTransparency = 1
		self._cap.TextTransparency = 1
		return
	end

	local fade = PickupConfig.Hud.EmptyFade
	local token = self._hideToken
	self:_tween(slot, fade, { BackgroundTransparency = 1 })
	self:_tween(self._stroke, fade, { Transparency = 1 })
	self:_tween(self._glyph, fade, { ImageTransparency = 1 })
	self:_tween(self._cap, fade, { TextTransparency = 1 })
	task.delay(fade, function()
		if self._hideToken == token and self._slot then
			self._slot.Visible = false
		end
	end)
end

--[[ The breath while the slot is full: the plate's transparency travels a little, on a slow sine.

	Runs off Heartbeat rather than a looping tween because it has to stop DEAD the frame the slot
	empties. A looping tween would keep writing the plate's transparency into the fade `_hide` is
	running over the top of it, and the two would fight for the same property all the way down.
	Nothing has to switch it off: it is gated on `_held`, which `_onSlotChanged` clears before it
	paints.

	A breath rather than a strobe, matching the nitro bar's own `BurnPulse` language. ]]
function PickupController._step(self, dt: number)
	if not (self._slot and self._held) then
		return
	end
	local hud = PickupConfig.Hud
	self._pulseClock += dt
	local wave = (math.sin(self._pulseClock * hud.PulseHz * 2 * math.pi) + 1) * 0.5
	self._slot.BackgroundTransparency = wave * hud.Pulse
end

-- === The toast ==============================================================

--[[ The card that says what you just picked up and what happened to it.

	Two lines, transparent, no panel — the same shape and the same argument as `NearMissController`'s
	near-miss toast, so a pickup and a near miss read as one language of "that went well". A race
	screen is something the player is looking THROUGH, and an opaque rectangle in the middle of it
	while they are threading traffic would cost them the thing it is congratulating them for.

	The second line is what distinguishes the two cases the owner's rule creates: STORED for a pack
	that went into the slot, APPLIED for a health pack that spent itself because you needed it. Those
	have to read differently or the auto-use looks like the slot failing to fill. ]]
function PickupController._buildToast(self)
	local ui = PickupConfig.Toast

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.AnchorPoint = Vector2.new(0.5, 0.5)
	toast.Position = UDim2.fromScale(ui.Position.X, ui.Position.Y)
	toast.Size = UDim2.fromScale(ui.Size.X, ui.Size.Y)
	toast.BackgroundTransparency = 1
	toast.Parent = self._gui

	local scale = Instance.new("UIScale")
	scale.Parent = toast

	local function line(name: string, y: number, height: number): (TextLabel, UIStroke)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, y)
		label.Size = UDim2.fromScale(1, height)
		label.BackgroundTransparency = 1
		label.FontFace = FONT
		label.Text = ""
		label.TextScaled = true
		label.TextTransparency = 1
		label.Parent = toast

		local stroke = Instance.new("UIStroke")
		stroke.Color = PickupConfig.Hud.StrokeColor
		stroke.Thickness = 2
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		--- Contextual, so a thin outline draws where the glyph meets the background without
		--- thickening the letterforms at phone resolutions. Same reasoning as the near-miss toast.
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label
		return label, stroke
	end

	self._toast = toast
	self._toastScale = scale
	self._toastTitle, self._toastTitleStroke = line("Title", 0.3, 0.5)
	self._toastSub, self._toastSubStroke = line("Sub", 0.78, 0.34)
end

function PickupController._showToast(self, name: string, banked: boolean)
	local ui = PickupConfig.Toast
	local pack = PickupConfig.pack(name)
	if not (ui.Enabled and self._toast and pack) then
		return
	end

	--- A fresh token per toast, as `RaceUIController` and the near-miss toast both do: a fade still
	--- running when a second pack is collected must not go on writing transparency over its arrival.
	local token = self._toastToken + 1
	self._toastToken = token

	local camera = workspace.CurrentCamera
	local thickness = if camera then math.max(1, camera.ViewportSize.Y * 0.0035) else 2
	self._toastTitleStroke.Thickness = thickness
	self._toastSubStroke.Thickness = thickness

	self._toastTitle.Text = pack.Label
	self._toastTitle.TextColor3 = pack.Color
	self._toastSub.Text = if banked then ui.BankedText else (pack.UsedText or ui.UsedText)
	self._toastSub.TextColor3 = Color3.new(1, 1, 1)

	for _, inst in { self._toastTitle, self._toastSub } do
		inst.TextTransparency = 0
	end
	self._toastTitleStroke.Transparency = 0
	self._toastSubStroke.Transparency = 0
	self._toastScale.Scale = 1.25
	TweenService:Create(
		self._toastScale,
		TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	task.delay(ui.HoldTime, function()
		if self._toastToken ~= token or not self._toast then
			return
		end
		local info = TweenInfo.new(ui.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(self._toastTitle, info, { TextTransparency = 1 }):Play()
		TweenService:Create(self._toastSub, info, { TextTransparency = 1 }):Play()
		TweenService:Create(self._toastTitleStroke, info, { Transparency = 1 }):Play()
		TweenService:Create(self._toastSubStroke, info, { Transparency = 1 }):Play()
	end)
end

-- === Input ==================================================================

function PickupController._bind(self)
	if self._bound then
		return
	end
	self._bound = true
	ContextActionService:BindActionAtPriority(
		ACTION,
		function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				self:_use()
			end
			--- Never sunk. Neither key is claimed by anything else in a race (see
			--- `PickupConfig.Keys` for the audit), and passing them through means a rig whose
			--- Keymap grows one tomorrow still gets it.
			return Enum.ContextActionResult.Pass
		end,
		false,
		PickupConfig.BindPriority,
		table.unpack(PickupConfig.Keys)
	)
end

function PickupController._unbind(self)
	if not self._bound then
		return
	end
	self._bound = false
	ContextActionService:UnbindAction(ACTION)
end

--[[ Ask the server to spend the slot. Carries nothing — see the header.

	Refused locally when the slot looks empty, which is a courtesy rather than a check: the server
	refuses it anyway, and this only saves a remote call per press on an empty slot. The mirror can
	briefly disagree with the authority (a pack collected on the same frame), and in that direction
	the server is right and this is one wasted call. ]]
function PickupController._use(self)
	if PickupConfig.InstantUse or not (self._active and self._held) then
		return
	end
	self:getRemoteEvent("UsePickup"):Fire()
end

-- === What ObstacleController calls ==========================================

--[[ PUBLIC (ObstacleController) — the car just drove through a pack.

	This is the LOCAL beat only. Nothing here banks or spends anything: the slot arrives a moment
	later on the attribute (and a spend comes back on `PickupUsed`), and `_onSlotChanged` is where the
	nitro pack's auto-use is taken. What happens here is the toast and the sound, which have to land
	on the frame of contact rather than a round trip later — the same argument `NearMissController`
	makes about pricing its toast locally.

	Which of the two lines the toast shows comes from `_wouldAutoUse`, the same predicate that will
	decide. For nitro it cannot be wrong, because this side owns the tank and this side acts on it.
	For health it is a prediction of the server's copy and can differ only in the window where the two
	disagree about HP, where the visible consequence is one word. Read live off the car rather than
	cached, because a steal changes which car you are in mid-run. ]]
function PickupController.collected(self, name: string, hitBox: BasePart?)
	local pack = PickupConfig.pack(name)
	if not (self._active and pack) then
		return
	end
	self:_showToast(name, not PickupConfig.InstantUse and not pack.Star and not self:_wouldAutoUse(pack, hitBox))

	local sound = pack.Sound or PickupConfig.Collect.Sound
	if sound then
		local sounds = Shard.get("SoundController")
		if sounds then
			sounds:PlayRandom(sound)
		end
	end
end

--[[ Is this pack about to spend itself rather than bank? The owner's rule, read here so the toast
	says APPLIED on the frame of contact instead of STORED a round trip before the slot empties.

	IT ANSWERS FOR BOTH PACKS AND IS AUTHORITATIVE FOR ONLY ONE, which is the asymmetry
	`PickupConfig`'s header sets out: the health rule belongs to `ObstacleService._onPickup` and this
	is a prediction of it, wrong only in the window where the two disagree about HP and visibly wrong
	only by one word; the nitro rule belongs HERE, because the tank is a number no server can read,
	and `_autoUse` acts on the very same answer.

	Both read `AutoUseBelow` out of the same config, so client and server can only ever differ about
	the resource, never about the rule. ]]
function PickupController._wouldAutoUse(self, pack, hitBox: BasePart?): boolean
	if pack.AutoUseBelow <= 0 then
		return false
	end
	--[[ WHICH RESOURCE the threshold is a fraction OF is the pack's payout field, not a flag of its
		own: a pack that fills the tank measures against the tank, a pack that heals measures against
		the bar. That keeps a third pack from having to remember to declare something it has already
		said, and it is the same pairing `_onUsed` and `ObstacleService._spend` read. ]]
	if pack.Tank then
		local nitro = Shard.get("NitroController")
		--[[ Not just `getTank`: a bottle that is not running reads 0 and would look permanently
			depleted, which would auto-spend every nitro pack in a place with the feature off. See
			`NitroController.isRunning`. ]]
		return nitro ~= nil and nitro:isRunning() and nitro:getTank() <= pack.AutoUseBelow
	end
	--[[ The HitBox is handed in by the caller rather than looked up here, and it is the RIGHT part
		rather than a convenient one: it is what `ObstacleService._healthHolder` writes Health to, so
		reading it here means both sides are reading the same two attributes off the same instance.
		A walk from the car Model would find the same part on every rig today and would silently
		start disagreeing the day one is rigged without one. ]]
	if not (hitBox and hitBox.Parent) then
		return false
	end
	local health = hitBox:GetAttribute("Health")
	local max = hitBox:GetAttribute("MaxHealth")
	if type(health) ~= "number" or type(max) ~= "number" or max <= 0 then
		return false
	end
	return health <= max * pack.AutoUseBelow
end

-- === Lifecycle ==============================================================

--[[ The attribute moved, or is being read for the first time: take what it says and draw it.

	`_held` is written BEFORE the paint on purpose. It is what gates the pulse in `_step`, and on the
	way out the pulse has to be off before `_hide` starts fading the same property. It is also what
	`_use` checks, so `_autoUse` below has to run after it too.

	THE AUTO-USE IS TAKEN OFF THE ARRIVAL RATHER THAN OFF `collected`, and it has to be: at contact
	the server has not banked the pack yet, and `ObstacleController` fires `ObstacleHit` AFTER it
	calls us — so a `UsePickup` sent from there would reach a slot that is still empty and be
	refused. The attribute changing is the earliest moment the thing we are asking to spend exists. ]]
function PickupController._onSlotChanged(self, animate: boolean)
	local name = Players.LocalPlayer:GetAttribute(PickupConfig.SlotAttribute)
	local pack = PickupConfig.pack(name)
	self._held = if pack then name else nil
	self._pulseClock = 0
	--[[ Only a pack that JUST ARRIVED during a live race may auto-use, which is exactly what
		`animate` means here (see `_paint`): the other callers are a race start, a revive and a GUI
		rebuild, and each of those is reading a slot the player has been carrying rather than
		watching one land. Spending a pack on a revive because the tank happens to be low would be
		the feature helping itself to something the player put away. ]]
	local auto = animate and pack ~= nil and self:_autoUse(pack)
	--- Painted without the punch when it is on its way straight back out. The scale-in belongs to a
	--- pack arriving to STAY; playing it over a plate that starts fading a round trip later is two
	--- animations fighting over 0.14 seconds. The plate is still drawn, because the attribute is the
	--- authority and this file's rule is that what is on screen is whatever the attribute says.
	self:_paint(self._held, animate and not auto)
end

--[[ THE CLIENT'S HALF OF THE OWNER'S RULE: a pack whose resource this side owns, collected while
	that resource is at or under its `AutoUseBelow`, goes straight back out.

	Only the nitro pack can reach this today and by construction it is the only KIND that can: the
	health rule is enforced server-side in `ObstacleService._onPickup` and a health pack that
	qualified never reached a slot for us to see. `_wouldAutoUse` is the single predicate both cases
	read, so the toast and this can never disagree about what is about to happen.

	It spends through `UsePickup` — the same remote, carrying the same nothing, that the key fires —
	rather than through any path of its own. That is the whole security argument for doing this on
	the client at all: the server still decides what is in the slot, still refuses a wrecked race and
	still fires the `PickupUsed` that actually pays the tank. This only presses the button.

	Returns whether it fired, so the caller can skip the arrival animation for a plate that is not
	staying. It does NOT clear `_held` or repaint: the slot emptying comes back off the attribute
	like every other change to it, and a second writer here is how the plate and the authority start
	disagreeing. If the server refuses (a wreck landing on the same frame is the only way in a live
	race), nothing was lost — the pack is still in the slot, still painted, and still spendable by
	hand. ]]
function PickupController._autoUse(self, pack): boolean
	--[[ `pack.Tank` is the guard that keeps this to the packs this side is allowed to decide for,
		and it is written out rather than left to fall out of `_wouldAutoUse` returning false for a
		health pack with no HitBox handed in. A silent false from a missing argument is not a rule,
		and the day a pack pays both resources it would be the wrong one. ]]
	if not (self._active and pack.Tank and self:_wouldAutoUse(pack)) then
		return false
	end
	self:getRemoteEvent("UsePickup"):Fire()
	return true
end

function PickupController._onRaceStart(self)
	self:_onRaceEnd() -- idempotent: a revive re-enters through here and must not stack a second loop
	if not (PickupConfig.Enabled and self._gui) then
		return
	end
	self._active = true
	self._gui.Enabled = true
	if PickupConfig.InstantUse then
		-- The GUI still owns the collection toast, but there is no inventory plate, input binding or
		-- heartbeat animation when contact itself spends the pack.
		self._held = nil
		self._slot.Visible = false
		return
	end
	self:_syncCap()
	self:_resolveStroke()
	--[[ Repainted WITHOUT the animations: a revive comes back through here holding whatever the run
		had in the slot when it wrecked, and punching the plate for a pack that was collected a
		minute ago would announce something that did not just happen. The far commoner case is an
		empty slot, which this leaves hidden with no fade for the same reason. ]]
	self:_onSlotChanged(false)
	self:_bind()

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end)
end

function PickupController._onRaceEnd(self)
	self._active = false
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self:_unbind()
	self:_cancelTweens()
	self._held = nil
	if self._gui then
		self._gui.Enabled = false
	end
end

PickupController:withRemoteEvents({
	--[[ client -> server: "spend my slot". Declared as a bare name because this side only ever
		FIRES it; the handler is `ObstacleService`'s.

		Remotes in this framework are paired by GLOBAL NAME rather than by owner (`SimpleNet`), which
		is why a controller called `PickupController` can talk to a service called `ObstacleService`
		at all — and why the two names below have to stay in step with that file's declarations. ]]
	"UsePickup",
	{
		--[[ A pack left the slot, by the key or by the owner's rule. The heal has already landed
			server-side; the NITRO has not, and this is where it lands — the tank is a client-owned
			number and this is the only side that can write it. See the header. ]]
		PickupUsed = function(name: any)
			PickupController:_onUsed(name)
		end,
		RaceStart = function()
			PickupController:_onRaceStart()
		end,
		--[[ A wreck takes the slot down with the rest of the race UI. It does NOT clear what is in
			it — the server keeps the run's slot through a wreck exactly as it keeps the seed and
			the consumed set, so a revive comes back holding what you were carrying. Punishing a
			paid revive by confiscating a pack would be the same mistake as handing it an empty
			tank. ]]
		RaceWrecked = function()
			PickupController:_onRaceEnd()
		end,
		RaceRevived = function()
			PickupController:_onRaceStart()
		end,
		RaceEnd = function()
			PickupController:_onRaceEnd()
		end,
	},
})

--[[ A pack was spent. For nitro this is the payout; for health it is only the cue, because the HP
	moved on the server before this was sent.

	Tolerates an unknown name rather than erroring: the message crossed a network boundary, and a
	client running a build where that pack no longer exists should lose the beat, not the race. ]]
function PickupController._onUsed(self, name: any)
	local pack = PickupConfig.pack(name)
	if not pack then
		return
	end
	if pack.Tank then
		local nitro = Shard.get("NitroController")
		if nitro then
			--- `always`: a pack pays mid-boost too, whatever `NitroConfig.Gain.WhileBurning` says.
			nitro:reward(pack.Tank, true)
		end
	end
	--- The Star: the server has armed the immunity, and everything you can see or feel of it is
	--- `StarController`'s.
	if pack.Star then
		local star = Shard.get("StarController")
		if star then
			star:start()
		end
	end
	--- The slot's own repaint comes from the attribute watcher a moment later, so nothing here
	--- touches it — one writer, driven by the authority.
end

PickupController:withLifecycle({
	init = function(self)
		self._active = false
		self._held = nil :: string?
		self._bound = false
		self._tweens = {}
		self._pulseClock = 0
		self._toastToken = 0
		--- Guards the delayed `Visible = false` that a fade-out books; see `_paint`.
		self._hideToken = 0
	end,

	start = function(self)
		if not PickupConfig.Enabled then
			-- No slot, no key, no toast. `ObstacleLayout` is not placing any packs either, so there
			-- is nothing for this to draw.
			return
		end

		--[[ The attribute is watched from boot rather than from the first race, so a slot filled
			before this controller's GUI existed — or before a respawn rebuilt it — is painted the
			moment it can be. `_paint` no-ops until `_build` has run, and `_onRaceStart` repaints
			from the live value, so the two orders both land correctly. ]]
		Players.LocalPlayer:GetAttributeChangedSignal(PickupConfig.SlotAttribute):Connect(function()
			if PickupConfig.InstantUse then
				return
			end
			--- Animated during a race and not otherwise: a change while one is running is a pack
			--- arriving or being spent, which are the two moments the plate is allowed to announce
			--- itself. Outside a race the attribute only ever moves as bookkeeping.
			self:_onSlotChanged(self._active)
		end)

		-- Spawned rather than awaited: `_build` waits on PlayerGui, and `Shard.start()` is the
		-- client's boot barrier. Same reason NearMissController spawns its build.
		task.spawn(function()
			self:_build()
			self:_buildToast()
			self:_onSlotChanged(false)
		end)
	end,
})

return PickupController
