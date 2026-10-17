--[[
	CarHudController  (client)
	--------------------------
	The car's HP, drawn ON THE CAR, plus the WRECKED banner. This is the HP slice of the
	`CarController` sketched in the car-system handoff doc (§6) — hit/steal VFX will want to
	join it later.

	It reads `Health` / `MaxHealth` straight off the car's HitBox attributes. That's the
	whole point of keeping HP in attributes rather than a custom net message: the server
	writes them (ObstacleService), Roblox replicates them, and the bar just watches. No
	remote, no polling, and the bar can never disagree with the authoritative value.

	Driven by RaceService's remotes: RaceStart attaches it, RaceWrecked bangs the banner up,
	RaceEnd tears it down.

	=== THE BAR IS IN THE WORLD, NOT ON THE SCREEN ==============================================

	It used to be a pill at the top centre of the screen (`CarHud.HPBar`). It is now a
	`BillboardGui` floating over the roof of the car it belongs to, and there are three reasons
	that is the better place for it:

	  • IT IS ABOUT THE CAR. Everything else the player is reading during a race — traffic, props,
	    the lane they are threading — is out there on the road, and a number in the corner of the
	    screen asks them to look away from it to find out how the thing in the middle of the screen
	    is doing. Over the roof it is in the same glance as the hit that caused it.
	  • IT COSTS NO SCREEN. The race screen is claimed edge to edge (see the layout table in
	    `TutorialController`), and the top strip was the last band with any daylight in it.
	  • IT CAN BE SILENT. A screen bar has to be somewhere even at full health; a bar on the car can
	    simply not be there, which is most of what it does — see the visibility rules below.

	The old pill is still in the place, and `_bindBanner` hides it (Visible = false) on the PlayerGui
	copy so a place whose art still has it can't draw two of these. It can be deleted from the
	Explorer whenever; nothing here reads anything inside it.

	=== THE UI IS AUTHORED IN STUDIO, NOT HERE ==================================================

	`StarterGui.CarHpBar`, the same contract `DrivingHud` and `CarHud` are on: the art lives in the
	Explorer so its look can be nudged without opening an editor, and this file only ever FINDS the
	instances and animates them. It used to build the whole thing out of `Instance.new` rectangles.

	    CarHpBar         the BillboardGui. Its SIZE is the bar's size, and on a billboard the Scale
	                     component of Size is STUDS — so 8 x 1.3 is a physical object about 85% as
	                     wide as the car, and it stays that at every resolution and field of view.
	      Root           an empty frame holding the whole bar, so one UIScale can squash the lot
	        UIScale      THE POP. Made below if the art hasn't got one.
	        Trough       the track, and the only thing that has to be positioned
	          UIStroke   the outline
	          Chip       the pale tail a hit leaves behind    } widths driven from here; everything
	          Fill       THE READING                          } else about them is yours
	          Flash      the hit whiteout

	Corner radius, colours, stroke, transparency, layout, anything you want to add alongside — all
	yours. `Root`, `Trough` and `Fill` are the three this file cannot run without; `UIScale`, `Chip`,
	`Flash` and the stroke are each optional and animate if present. A place with no `CarHpBar` at
	all warns once and races without the bar rather than erroring per frame.

	WHAT THIS FILE WRITES, and therefore what you cannot own in the Explorer, is exactly: the widths
	of `Fill` and `Chip`, the colour of `Fill` (it has to say healthy/hurt/critical), the
	transparency of `Flash`, `UIScale.Scale`, and the transparency of everything while the bar fades
	in and out. The colour of the trough too, unless you set `TrackDim` to 0 — see below.

	ONE AUTHORING CATCH: the fade reads each layer's authored transparency ONCE, at bind, and treats
	it as that layer's "fully shown" value. Change a transparency in the Explorer mid-playtest and
	it lands on the next JOIN, not the next hit — unlike every other value here. Everything the fade
	does not drive (colours, radius, size, position, stroke thickness) is live.

	=== IT IS ONLY THERE WHEN IT HAS SOMETHING TO SAY ===========================================

	THREE RULES, and between them the bar is off screen for almost all of a run:

	  • FULL HP DRAWS NOTHING. It fades in on the hit that takes the first chip off, and fades out
	    the moment something puts the car back to full (a revive, or the refill a steal comes with).
	  • A QUIET STRETCH PUTS IT AWAY TOO. `IdleHide` seconds after the last hit it fades out even
	    though the car is still damaged, because by then it has stopped being news: the player has
	    read it, and what they want back is the road. The next hit brings it straight back with the
	    real number on it. Set `IdleHide` to 0 to keep it up for as long as the car is hurt.
	  • A WRECK TAKES IT AWAY ENTIRELY. At zero the bar drains, fades and is gone, rather than
	    hanging over the wreck as an empty box. Nothing is lost by that: the WRECKED banner and the
	    respawn screen behind it are both already saying the only thing an empty bar could, and the
	    wreck beat is the busiest second and a half in the game — ragdoll, camera swing, banner,
	    revive offer — which is the last place to spend attention restating something.

	Which also means the bar APPEARING is itself a hit reaction, so the pop that brings it in and the
	pop a later hit gives it are deliberately the same animation (`_punch`) — one entrance, one
	vocabulary, and no special-casing the first hit of a run.

	=== WHAT A HIT LOOKS LIKE ===================================================================

	Four things happen at once, and all four are scaled by how big the hit was (`lost / MaxHealth`
	against `BigHit`), because a cone and a lamp post should not read the same:

	    the fill    SNAPS to the new value. The hit has to be felt on the frame it lands.
	    the chip    a pale tail left behind at the OLD value, which then slides down to meet the
	                fill. This is the part that says how much it cost — the fill alone only ever
	                says how much is left.
	    the flash   a white-out across the whole bar, not just the full part: the flash is the car
	                being hit, not the HP remaining.
	    the knock   the whole bar is shoved down toward the roof and springs back.

	The knock rides `StudsOffset`, which is CAMERA space, and so does the bar's resting height. That
	is on purpose: a car leans into a lane change and barrel-rolls on a wreck, and an offset in the
	adornee's own frame would swing the bar out over the tarmac with it. Camera-space up is always up
	on the screen, and at this camera (28 back, 13 high — CameraConfig) it lands within a few percent
	of where world-up would have put it.

	=== THE LOOK & FEEL IS ATTRIBUTES ===========================================================

	The colours, the thresholds they switch at, how high it floats and every tween time read from
	attributes on `CarHpBar` itself — or on `CarHud`, which is checked second so the banner's two
	values have somewhere to live (see DEFAULTS below; the names match). They're read per use rather
	than cached, so dragging a colour swatch in the Properties panel during a playtest retints the
	bar on the very next hit. The table here is the fallback, not the source of truth: clear an
	attribute and its default applies, so a place that never had them set still behaves.

	The WRECKED banner is `TextScaled` with its pop driven through a `UIScale` — deliberately NOT a
	TextSize tween, which is what it used to be: TextScaled and a pixel TextSize can't coexist, and
	the fixed 42->56 tween was the last thing in the HUD that didn't track resolution.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local ObstacleConfig = require(ReplicatedStorage.shared.Configs.ObstacleConfig)
--- For the one ending that puts a different word on this banner. See `_onWrecked`.
local PoliceConfig = require(ReplicatedStorage.shared.Configs.PoliceConfig)

local CarHudController = Shard.new("CarHudController"):withDependencies({ "RoadController" })

-- === Look & feel ============================================================
--[[ Defaults for the attributes of the same name on `StarterGui.CarHpBar` (or, checked second,
	`StarterGui.CarHud`). Every one of these is a taste value someone will want to nudge without
	opening an editor, which is the whole reason they're attributes; the plumbing timeouts below
	deliberately are not.

	NOTHING ABOUT THE BAR'S SIZE OR COLOURING-IN IS HERE any more. Its size, its corner radius, its
	stroke, the colour of the trough it rests in and the colour of the chip are all properties of
	the authored instances — see the contract in the header. What is left is behaviour: how it
	reacts, how long it stays, and the three colours it uses to say how bad things are. ]]
local DEFAULTS = {
	--[[ How high it floats, in STUDS, measured from the ROOF to the bar's bottom edge — half the
		bar's own authored height is added on top of this, so resizing the bar doesn't move it.

		KEEP IT SMALL. 0.7 studs is under 10 screen pixels at the race camera on a 620-tall
		viewport, and it is deliberately that tight: any further up and the bar stops reading as
		part of the car and starts reaching into the band the near-miss toast owns
		(`NearMissConfig.Ui`, y 0.25-0.35). It is also the one number here whose right answer is a
		matter of taste on a moving screen, which is exactly why it is an attribute. ]]
	BarLift = 0.7,

	--[[ Seconds after the last hit that the bar puts itself away, damaged or not. 0 disables it and
		the bar stays up for as long as the car is hurt. Long enough to read twice over, short
		enough that a clean stretch of road is a clean screen. ]]
	IdleHide = 3.5,

	ColorTime = 0.22, -- how long the fill takes to cross-fade between healthy/hurt/critical
	ChipTime = 0.4, -- how long the pale tail takes to slide down to the fill
	ChipHold = 0.1, -- ...and how long it sits at the old value first
	FlashTime = 0.18, -- and how long the white-out over the bar takes to fade
	FlashAlpha = 0.45, -- transparency the hit flash punches in at, at full severity

	ShowTime = 0.14, -- fade-in when the first chip comes off
	HideTime = 0.35, -- ...and the fade-out, on a refill or a quiet stretch
	HiddenScale = 0.55, -- UIScale the bar shrinks away to, so it doesn't just wink out

	--[[ The hit reaction. `BigHit` is the fraction of MaxHealth that earns the full-size reaction:
		obstacle damage runs 4-35 against a 100 HP car (ObstacleConfig.Kinds), so a quarter of the
		bar is a heavy hit and everything above it is already the loudest reaction we do. `MinPunch`
		stops the small end vanishing — a cone should be a flinch, not nothing. ]]
	BigHit = 0.25,
	MinPunch = 0.25,
	PunchScale = 0.3, -- extra UIScale a full-severity hit springs from
	PunchTime = 0.26,
	KnockStuds = 0.55, -- how far down a full-severity hit shoves the bar

	HealthyColor = Color3.fromRGB(84, 220, 130),
	HurtColor = Color3.fromRGB(255, 190, 62),
	CriticalColor = Color3.fromRGB(240, 78, 68),
	HurtBelow = 0.6, -- ratio at or under which the bar goes amber
	CriticalBelow = 0.3, -- ...and at or under which it goes red

	--[[ The trough is the fill's own colour at this fraction of its brightness, rather than the
		swatch it was authored with, so the empty half of the bar can't be advertising green while
		the full half has gone red. 0.28 is where the imported art sat (a 0,0.247,0 trough under a
		0,0.862,0 fill).

		SET IT TO 0 TO TURN THAT OFF and keep whatever colour `Trough` is authored with — the one
		property in the art this file overrules, and the one it will hand back on request. ]]
	TrackDim = 0.28,

	WreckPopTime = 0.25,
	WreckPopFrom = 0.75, -- UIScale the banner springs up from (was TextSize 42 of 56)
}

-- === Plumbing ===============================================================
local CAR_WAIT = 8 -- give up resolving our car after this long
local GUI_WAIT = 10 -- give up waiting for either authored GUI after this long
local BAR_NAME = "CarHpBar"

--- What the banner says for every ending but a police bust. The authored label already reads this;
--- it is written down here because `_onWrecked` has to be able to put it BACK after a bust has
--- changed it, and a label read for its own default would inherit whatever the last run left on it.
local WRECK_WORD = "WRECKED"

-- === Tuning ==================================================================

--[[ One tunable, attribute first: the bar, then the ScreenGui, then the table above. Read per call
	rather than cached at bind so a value edited in the Explorer mid-playtest lands on the next hit
	instead of the next join.

	TWO HOLDERS BECAUSE THERE ARE TWO WIDGETS. Everything about the bar belongs on the bar, and the
	banner's two values belong on the GUI that holds the banner — but neither is enforced, because
	the cost of guessing wrong should be nothing rather than a value that silently does nothing.

	The typeof() guard is the point of the whole helper: attributes are typed by whoever last
	touched them, so a colour swatch replaced with a number, or a time field left empty, would
	otherwise reach TweenService as garbage and throw on every frame of damage. Wrong type is
	treated as unset, and falls through to the next holder. ]]
function CarHudController._tune(self, name: string)
	local default = DEFAULTS[name]
	-- Written out rather than looped over a `{ self._bar, self._gui }` array: either handle can be
	-- nil, and a nil in the first slot of a table constructor is a hole that a generalized `for`
	-- may walk straight past — which would silently drop the second holder on any client whose
	-- bar hadn't bound yet.
	local fromBar = self._bar and self._bar:GetAttribute(name)
	if typeof(fromBar) == typeof(default) then
		return fromBar
	end
	local fromGui = self._gui and self._gui:GetAttribute(name)
	if typeof(fromGui) == typeof(default) then
		return fromGui
	end
	return default
end

function CarHudController._colorFor(self, ratio: number): Color3
	if ratio > self:_tune("HurtBelow") then
		return self:_tune("HealthyColor")
	elseif ratio > self:_tune("CriticalBelow") then
		return self:_tune("HurtColor")
	end
	return self:_tune("CriticalColor")
end

--[[ Every tween on the bar goes through here, under a name.

	TweenService cancels a running tween when a NEW one targets the same property, but it has
	nothing to say about a plain assignment — and this file assigns constantly (the fill snaps, the
	flash is punched in, the knock is reset). Without a handle to cancel, a bar hidden 0.05s into a
	0.4s chip slide keeps being written by that dead slide for the rest of it, and comes back next
	hit with a tail halfway to somewhere it no longer is. ]]
function CarHudController._retween(self, key: string, inst: Instance, info: TweenInfo, goal: { [string]: any })
	self:_stopTween(key)
	local tween = TweenService:Create(inst, info, goal)
	self._tweens[key] = tween
	tween:Play()
end

function CarHudController._stopTween(self, key: string)
	local live = self._tweens[key]
	if live then
		live:Cancel()
		self._tweens[key] = nil
	end
end

-- === Binding =================================================================

--[[ Resolve the authored bar.

	WaitForChild per hop on the three that are load-bearing, and deliberately with no timeout on
	them. The BillboardGui resolving does NOT mean its subtree has: the PlayerGui copy can still be
	filling in when this runs, and a lookup that landed one frame early would disable the bar for
	the rest of the session — on the slower clients only, which is the worst shape a bug like this
	can take. Yielding costs nothing here because nothing waits on this thread, and it means there
	is no "missing art" warn to keep in step with the Explorer: rename `Trough` and Roblox says
	`Infinite yield possible on CarHpBar.Root:WaitForChild("Trough")`, which names the offender
	better than a warn here could.

	The rest are optional and simply animate if they exist, because none of them is the reading —
	they are the reaction to it, and a place whose art predates one should still show HP. ]]
function CarHudController._bindBar(self): boolean
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(BAR_NAME, GUI_WAIT)
	if not gui then
		self.log:warn("No StarterGui.CarHpBar to bind; racing without the HP bar.")
		return false
	end

	local root = gui:WaitForChild("Root")
	local trough = root:WaitForChild("Trough")
	local fill = trough:WaitForChild("Fill")

	local scale = root:FindFirstChildOfClass("UIScale")
	if not scale then
		-- Made rather than demanded, because it isn't art: it's the moving part of the pop.
		scale = Instance.new("UIScale")
		scale.Parent = root
	end

	--[[ The fade is one alpha across every layer, but the layers do NOT share a value — the trough
		is a shade off opaque, the chip further still, the flash invisible until it is punched. So
		each entry carries the transparency it was AUTHORED with as its fully-shown value, snapshot
		here, which is what makes the fade respect the art instead of flattening it.

		Snapshot rather than re-read because this file writes those same properties: after the first
		fade, reading them back would be reading our own output. That is the authoring catch in the
		header, and it is the price of not putting a CanvasGroup in the middle of the bar. ]]
	local fadeSet = {}
	local function fades(inst: Instance?, prop: string)
		if inst then
			table.insert(fadeSet, { inst, prop, (inst :: any)[prop] })
		end
	end
	fades(trough, "BackgroundTransparency")
	fades(trough:FindFirstChildOfClass("UIStroke"), "Transparency")
	local chip = trough:FindFirstChild("Chip")
	fades(chip, "BackgroundTransparency")
	fades(fill, "BackgroundTransparency")

	local flash = trough:FindFirstChild("Flash")
	if flash then
		flash.BackgroundTransparency = 1 -- whatever it was left at in the Explorer, it starts clear
	end

	--[[ Roblox nils an Adornee when the thing it pointed at is destroyed, and a billboard with no
		adornee draws AT THE WORLD ORIGIN — which is where the road starts, so a car destroyed
		mid-race would leave this hanging over the start line in full view. Cheaper to watch the
		property than to police every teardown path that could have got there first. ]]
	gui:GetPropertyChangedSignal("Adornee"):Connect(function()
		if not gui.Adornee then
			gui.Enabled = false
		end
	end)

	gui.Enabled = false
	self._bar = gui
	self._scale = scale
	self._trough = trough
	self._chip = chip
	self._fill = fill
	self._flash = flash
	self._fadeSet = fadeSet
	self._barShown = false
	return true
end

--[[ Resolve the Studio-authored ScreenGui, which today holds only the WRECKED banner.

	IT IS OPTIONAL, and so is the bar: the two bind independently and a place missing either one
	still races. Everything after this point treats `self._gui` as fully wired or nil. ]]
function CarHudController._bindBanner(self): boolean
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("CarHud", GUI_WAIT)
	if not gui then
		self.log:warn("No StarterGui.CarHud to bind; racing without the WRECKED banner.")
		return false
	end

	local wrecked = gui:WaitForChild("Wrecked")
	local wreckScale = wrecked:FindFirstChildOfClass("UIScale")
	if not wreckScale then
		wreckScale = Instance.new("UIScale")
		wreckScale.Parent = wrecked
	end

	--[[ The retired screen pill, and the older `Health` bar under it. Put away on the PlayerGui copy
		so StarterGui is untouched and this is not an edit anyone has to notice — but two HP bars is
		a worse outcome than one in the wrong place, and the art still ships with the pill in it.
		Both can be deleted from the Explorer whenever; nothing here reads inside either. ]]
	for _, retired in { "HPBar", "Health" } do
		local old = gui:FindFirstChild(retired)
		if old and old:IsA("GuiObject") then
			old.Visible = false
		end
	end

	gui.Enabled = false
	self._gui = gui
	self._wreckLabel = wrecked
	self._wreckScale = wreckScale
	return true
end

-- === Showing and hiding ======================================================

-- One alpha, every layer: 1 is fully drawn, 0 is gone. A `time` of nil sets it outright.
function CarHudController._fade(self, alpha: number, time: number?)
	for index, entry in ipairs(self._fadeSet or {}) do
		local inst, prop, shown = entry[1], entry[2], entry[3]
		local value = 1 + (shown - 1) * alpha
		local key = "fade" .. index
		if time and time > 0 then
			self:_retween(key, inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { [prop] = value })
		else
			self:_stopTween(key)
			;(inst :: any)[prop] = value
		end
	end
end

--[[ How high over the car the bar rests, in studs, measured off the car this race rather than
	assumed: the bodies on this chassis run 6.1 to 7.0 studs tall (and a steal changes which one you
	are in), so a constant lift would either clip the tall ones or float over the short ones.

	`GetBoundingBox` measures in the model's PIVOT frame, so its Size is only world height while the
	car is level — hence projecting the box's top onto world up rather than taking Size.Y neat. The
	car is level for all of the run that matters here; the projection is what keeps the answer sane
	on the frame it isn't. ]]
function CarHudController._liftFor(self, car: Model?, hitBox: BasePart): number
	-- Half the bar's own authored height, so `BarLift` can mean the gap over the roof whatever size
	-- the bar has been dragged to. A bar sized in pixels rather than studs contributes nothing here.
	local clearance = self:_tune("BarLift") + self._bar.Size.Y.Scale * 0.5
	local ok, cf, size = pcall(function()
		return (car :: Model):GetBoundingBox()
	end)
	if not (car and ok and typeof(cf) == "CFrame" and typeof(size) == "Vector3") then
		return hitBox.Size.Y * 0.5 + clearance
	end
	local top = cf.Position + cf.UpVector * (size.Y * 0.5)
	return math.max((top - hitBox.Position):Dot(Vector3.yAxis), 0) + clearance
end

function CarHudController._showBar(self)
	local gui = self._bar
	if not (gui and self._hitBox) or self._barShown then
		return
	end
	self._barShown = true

	--[[ Re-measured on the way in rather than at attach: a steal swaps the bodywork under us and
		refills the car on the way through, so every appearance of this bar is the first one after
		whatever the car currently is. One bounding box per hit-that-breaks-a-lull. Note it does not
		touch Size — that is the artist's, and reading it is as far as this goes. ]]
	self._lift = self:_liftFor(self._car, self._hitBox)
	-- Stopped, not just overwritten: a knock left running by the hide that put the bar away is still
	-- easing StudsOffset toward the OLD lift, and would drag the fresh one back down under it.
	self:_stopTween("knock")
	gui.StudsOffset = Vector3.new(0, self._lift, 0)

	if self._flash then
		self:_stopTween("flash")
		self._flash.BackgroundTransparency = 1
	end
	--[[ The scale is put back to rest HERE rather than at the end of the fade-out that hid it. The
		fade-out's own tween and the timer that switches the bar off both land on the same frame, so
		resetting there is a coin flip over which of the two writes last — and losing it parks the
		bar at HiddenScale for the next show. Resetting on the way IN cannot race anything. ]]
	self:_stopTween("scale")
	self._scale.Scale = 1
	self._fadeToken += 1
	gui.Enabled = true
	self:_fade(0, nil)
	self:_fade(1, self:_tune("ShowTime"))
	-- Beyond that the UIScale is left alone: `_punch` owns it, and the punch that comes with this
	-- hit IS the entrance. See the header.
end

function CarHudController._hideBar(self, instant: boolean?)
	local gui = self._bar
	if not gui then
		return
	end
	self._barShown = false
	self._idleToken += 1 -- any quiet-stretch timer still out there is now about a bar that is gone
	self._fadeToken += 1
	local token = self._fadeToken

	if self._flash then
		self:_stopTween("flash")
		self._flash.BackgroundTransparency = 1
	end
	if instant or not gui.Enabled then
		self:_fade(0, nil)
		self:_stopTween("scale")
		self:_stopTween("knock")
		self._scale.Scale = 1
		gui.Enabled = false
		return
	end

	local time = self:_tune("HideTime")
	self:_fade(0, time)
	self:_retween(
		"scale",
		self._scale,
		TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = self:_tune("HiddenScale") }
	)
	--[[ Switched off at the END of the fade rather than the start of it, and behind the token so a
		hit landing mid-fade — which puts the bar straight back up — isn't switched off a moment
		later by the tail of the fade it interrupted. ]]
	task.delay(time, function()
		if self._fadeToken ~= token or not self._bar then
			return
		end
		self._bar.Enabled = false
	end)
end

--[[ Start the clock on the quiet stretch — see the second visibility rule in the header.

	A token rather than a cancellable timer, because hits arrive in bursts and every one of them
	restarts this: the token is what makes the four countdowns a run of cones leaves behind
	harmless, since only the last one still matches. `_hideBar` bumps it too, so a bar put away by a
	refill can't be put away a second time by a stale countdown from before it. ]]
function CarHudController._armIdleHide(self)
	self._idleToken += 1
	local wait = self:_tune("IdleHide")
	if wait <= 0 then
		return -- kept up for as long as the car is damaged
	end
	local token = self._idleToken
	task.delay(wait, function()
		if self._idleToken == token and self._barShown then
			self:_hideBar()
		end
	end)
end

--[[ The hit reaction, sized by how big the hit was. `severity` is the fraction of MaxHealth lost;
	everything here is scaled by it, which is the whole point — a cone and a lamp post cost 5 and 35
	and should not read the same. ]]
function CarHudController._punch(self, severity: number)
	local gui = self._bar
	if not gui then
		return
	end
	local big = math.max(self:_tune("BigHit"), 1e-3)
	local weight = math.clamp(severity / big, self:_tune("MinPunch"), 1)
	local time = self:_tune("PunchTime")
	-- Back/Out overshoots the target, so a scale falling from 1.3 dips under 1 and settles back up:
	-- the squash after the pop is free, and it is what stops this reading as a size change.
	local spring = TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	self._scale.Scale = 1 + self:_tune("PunchScale") * weight
	self:_retween("scale", self._scale, spring, { Scale = 1 })

	if self._flash then
		self._flash.BackgroundTransparency = 1 - (1 - self:_tune("FlashAlpha")) * weight
		self:_retween(
			"flash",
			self._flash,
			TweenInfo.new(self:_tune("FlashTime"), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		)
	end

	local lift = self._lift or 0
	gui.StudsOffset = Vector3.new(0, lift - self:_tune("KnockStuds") * weight, 0)
	self:_retween("knock", gui, spring, { StudsOffset = Vector3.new(0, lift, 0) })
end

-- === Rendering ===============================================================

function CarHudController._render(self, health: number, max: number, animate: boolean)
	if not self._bar then
		return
	end
	local ratio = if max > 0 then math.clamp(health / max, 0, 1) else 0
	local color = self:_colorFor(ratio)
	local size = UDim2.fromScale(ratio, 1)

	-- The empty part of the bar is the full part, dimmed — unless TrackDim says to leave the
	-- authored colour alone. See TrackDim.
	local dim = self:_tune("TrackDim")
	local trackColor = if dim > 0 then Color3.new(color.R * dim, color.G * dim, color.B * dim) else nil

	--[[ THE FILL NEVER SLIDES. It is the reading, and a reading that takes a fifth of a second to
		arrive is a fifth of a second in which the bar disagrees with the car. What slides is the
		CHIP behind it, which is not a reading at all — it is the size of the hit, and it can only
		say that by taking its time.

		Only the colour is tweened, because a bar that snaps from green to amber on one cone reads as
		a glitch rather than as a threshold being crossed. ]]
	self:_stopTween("chip")
	self._fill.Size = size
	if animate then
		local info = TweenInfo.new(self:_tune("ColorTime"), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		self:_retween("fill", self._fill, info, { BackgroundColor3 = color })
		if trackColor then
			self:_retween("track", self._trough, info, { BackgroundColor3 = trackColor })
		end
		if self._chip then
			-- Healing snaps the tail up with the fill; only damage leaves one behind.
			if ratio >= self._chip.Size.X.Scale then
				self._chip.Size = size
			else
				self:_retween(
					"chip",
					self._chip,
					TweenInfo.new(
						self:_tune("ChipTime"),
						Enum.EasingStyle.Quad,
						Enum.EasingDirection.Out,
						0,
						false,
						self:_tune("ChipHold")
					),
					{ Size = size }
				)
			end
		end
	else
		self:_stopTween("fill")
		self:_stopTween("track")
		self._fill.BackgroundColor3 = color
		if trackColor then
			self._trough.BackgroundColor3 = trackColor
		end
		if self._chip then
			self._chip.Size = size
		end
	end
end

function CarHudController._onHealthChanged(self)
	local hitBox = self._hitBox
	if not (hitBox and self._bar) then
		return
	end
	local health = hitBox:GetAttribute("Health")
	if type(health) ~= "number" then
		return
	end
	local max = self._maxHealth or ObstacleConfig.DefaultMaxHealth
	local lost = (self._lastHealth or health) - health
	self._lastHealth = health

	--[[ BOTH ENDS ARE SILENT, and this is the only place either is decided: a full car has nothing
		to report and a wrecked one has too much of it reported elsewhere. Note each renders BEFORE
		hiding, so the bar fades out reading the value it actually ended on rather than reading
		whatever the hit before it left — a revive that fills the car back up should look like it
		did, and the killing blow should be seen to empty the bar on its way out.

		The zero case is caught HERE rather than only in `_onWrecked` because this fires first: the
		server writes Health before it runs the wreck beat, so leaving it to the remote would flash
		a full-size hit reaction on screen for the frames in between. ]]
	if health >= max or health <= 0 then
		self:_render(health, max, false)
		self:_hideBar()
		return
	end

	self:_showBar()
	self:_render(health, max, true)
	if lost > 0 then
		self:_punch(lost / math.max(max, 1))
	end
	self:_armIdleHide() -- ...and the second rule: this hit is the one the quiet stretch runs from
end

-- === Lifecycle ===============================================================

-- Wait for our car to exist (RoadController resolves it from the seat we get welded to),
-- then watch its HitBox. Bails quietly if this race got torn down while we waited.
function CarHudController._attach(self, token: number)
	task.spawn(function()
		local road = self._road
		local deadline = os.clock() + CAR_WAIT
		local car, hitBox
		repeat
			car = road and road:getCar()
			hitBox = car and car:FindFirstChild(ObstacleConfig.HitBoxName, true)
			if not hitBox then
				task.wait(0.1)
			end
		until hitBox or self._token ~= token or os.clock() > deadline

		if self._token ~= token then
			return
		end
		if not hitBox then
			self.log:warn("Never found the car's HitBox; the HP bar will stay hidden.")
			return
		end

		local max = hitBox:GetAttribute("MaxHealth")
		if type(max) ~= "number" or max <= 0 then
			max = ObstacleConfig.DefaultMaxHealth
		end
		self._car = car
		self._hitBox = hitBox
		self._maxHealth = max
		self._lastHealth = hitBox:GetAttribute("Health") or max

		if self._bar then
			self._lift = self:_liftFor(car, hitBox)
			self._bar.StudsOffset = Vector3.new(0, self._lift, 0)
			self._bar.Adornee = hitBox
			--[[ Painted, then shown only if there is something to show. A run always starts full, so
				this is the silent path every time — but a revive comes back through here too, and
				one day a race may not start you at full. ]]
			self:_render(self._lastHealth, max, false)
			if self._lastHealth > 0 and self._lastHealth < max then
				self:_showBar()
				self:_armIdleHide()
			end
		end

		self._healthConn = hitBox:GetAttributeChangedSignal("Health"):Connect(function()
			self:_onHealthChanged()
		end)

		--[[ MaxHealth used to be a constant for a whole race, and isn't any more: a steal re-stamps
			it from the stolen car's tier (StealService → ObstacleService). Latching the value at
			attach would leave the bar drawing a Tier 5's 130 HP as a ratio of the beater's 80 and
			showing a permanently overfull bar. Cheap to watch, and it fires about once a steal. ]]
		self._maxConn = hitBox:GetAttributeChangedSignal("MaxHealth"):Connect(function()
			local value = hitBox:GetAttribute("MaxHealth")
			if type(value) == "number" and value > 0 then
				self._maxHealth = value
				self:_onHealthChanged()
			end
		end)
	end)
end

function CarHudController._onRaceStart(self)
	self:_hide()
	self._token += 1
	if self._gui then
		self._gui.Enabled = true
	end
	self:_attach(self._token)
end

function CarHudController._onWrecked(self, cause: string?)
	--[[ The bar goes, on the third visibility rule in the header. `_onHealthChanged` has almost
		certainly done this already off the Health write that caused the wreck; this is the same call
		again for the paths that reach a wreck without one — and it is a no-op when the bar is
		already down, so there is no cost to covering them. ]]
	self:_hideBar()

	local label = self._wreckLabel
	if not label then
		return -- no authored GUI in this place; the race still runs
	end

	--[[ WHAT THE BANNER SAYS, and it is the only thing about a police bust that differs here.

		The authored label reads WRECKED, and a bust is a wreck: same beat, same fade, same payout
		split, same offer. What it is not is a CRASH, and telling a player their car is wrecked when
		it is sitting undamaged with two cruisers either side of it is the game misreading its own
		ending back to them. One word covers the whole difference.

		Read off the cause rather than latched, and reset on every wreck rather than only on a bust,
		because this label is reused for the rest of the session: a run that was busted and a run
		that hit a wall must not be able to inherit each other's headline. ]]
	label.Text = if cause == PoliceConfig.Cause then PoliceConfig.BustedWord else WRECK_WORD
	label.Visible = true
	label.TextTransparency = 1

	--[[ Two tweens, not one, because they drive different objects now: the fade is on the label
		and the pop is on its UIScale. Both share the same TweenInfo so they still land together —
		the Back easing overshooting past 1 is what gives the banner its snap. ]]
	local info = TweenInfo.new(self:_tune("WreckPopTime"), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	self._wreckScale.Scale = self:_tune("WreckPopFrom")
	TweenService:Create(label, info, { TextTransparency = 0 }):Play()
	TweenService:Create(self._wreckScale, info, { Scale = 1 }):Play()
end

--[[ Take the WRECKED banner down — the respawn screen has taken over saying so (`ReviveController`).

	THE BAR IS ALREADY GONE by the time this runs — the wreck took it (third visibility rule). So
	this is only about the banner, and the banner goes for two reasons:

	  • IT IS THE SAME SENTENCE TWICE. The respawn screen's headline is the QUESTION ("KEEP GOING?")
	    precisely because the news is already on screen; leaving a second announcement of it above
	    the question spends the player's attention on something they had a second and a half ago.
	  • THE TWO CANNOT BE STACKED RELIABLY ANYWAY. This GUI honours the Roblox top-bar inset and a
	    full-screen overlay cannot — so the gap between this banner and anything drawn on one is a
	    different gap on every device, and on some of them it is a collision. Laying them out
	    together would be laying out against a number neither file owns.

	Nothing puts it back, and nothing needs to: `_hide` clears it when the race ends, and a revive
	comes through `_onRaceStart`, which clears it too. ]]
function CarHudController.hideBanner(self)
	if not self._wreckLabel then
		return
	end
	self._wreckLabel.Visible = false
	self._wreckLabel.TextTransparency = 1
	self._wreckScale.Scale = 1 -- a banner taken down mid-pop must not spring from there next time
end

function CarHudController._hide(self)
	self._token += 1
	if self._healthConn then
		self._healthConn:Disconnect()
		self._healthConn = nil
	end
	if self._maxConn then
		self._maxConn:Disconnect()
		self._maxConn = nil
	end
	self._hitBox = nil
	self._car = nil
	self._lastHealth = nil
	self._maxHealth = nil

	--[[ Instant, and the Adornee dropped with it. A fade here would be a bar easing out over a car
		that has already been taken away, and an adornee left pointing at a destroyed part is the
		world-origin case the property watcher in `_bindBar` exists to catch — no reason to hand it
		one on the path we control. ]]
	self:_hideBar(true)
	if self._bar then
		self._bar.Adornee = nil
	end

	if self._gui then
		self._gui.Enabled = false
		self._wreckLabel.Visible = false
		self._wreckLabel.TextTransparency = 1
		-- A race torn down mid-pop would otherwise leave the banner parked at WreckPopFrom,
		-- and the next wreck would spring from there to 1 with no travel left in it.
		self._wreckScale.Scale = 1
	end
end

CarHudController:withRemoteEvents({
	{
		RaceStart = function()
			CarHudController:_onRaceStart()
		end,
		RaceWrecked = function(cause)
			CarHudController:_onWrecked(cause)
		end,
		-- `ReviveService` is putting the respawn screen up over this wreck — see `hideBanner`.
		ReviveOffer = function()
			CarHudController:hideBanner()
		end,
		--[[ ...and the wreck was paid out of (`ReviveService`). `_onRaceStart` IS the inverse here —
			it hides first, which clears the WRECKED banner and its half-finished pop, then re-attaches
			to the car's Health attribute. The car's HP has genuinely been refilled by then
			(`ObstacleService.clearWreck`), so the bar comes back attached to a full car and therefore
			comes back invisible, which is the correct amount to say about a car that is fine. ]]
		RaceRevived = function()
			CarHudController:_onRaceStart()
		end,
		RaceEnd = function()
			CarHudController:_hide()
		end,
	},
})

CarHudController:withLifecycle({
	init = function(self)
		self._token = 0
		self._fadeToken = 0
		self._idleToken = 0
		self._tweens = {}
	end,

	start = function(self)
		self._road = Shard.get("RoadController")
		--[[ Spawned rather than awaited: both binds wait on PlayerGui, and Shard.start() is the
			client's boot barrier — blocking it would hold up every other controller. Spawned
			SEPARATELY, too, so a place missing one widget doesn't hold the other behind its
			ten-second timeout. ]]
		task.spawn(function()
			self:_bindBar()
		end)
		task.spawn(function()
			self:_bindBanner()
		end)
	end,
})

return CarHudController
