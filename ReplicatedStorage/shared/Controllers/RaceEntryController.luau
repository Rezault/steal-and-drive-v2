--[[
	RaceEntryController  (client)
	-----------------------------
	The HUD's Play button, the request it eventually turns into, and the lobby UI standing down for
	the length of the run. Playing is THREE presses now: Play opens the world-select screen, the
	world you press there opens the car screen, and the car you press THERE is the one you drive
	into that world.

	  • WHY IT IS THREE. Two of them are the boss's call — "when they click play, they choose a
	    world" — and the Trello's flow for the third: PLAY → SELECT WORLD → ALLOW USER TO CHANGE CAR.
	    Four worlds existed and the only door to them was a button on the rail nobody presses, and a
	    collection of stolen cars existed that changed nothing about driving; putting both choices on
	    the way in makes the ladder you are climbing and the car you climb it in things you pick
	    rather than things you inherit. `RaceConfig.PlayOpensWorldSelect` and `StartCarConfig.Enabled`
	    are the switches back, independently.

	    THE PADS ARE GONE (2026-08-16). There used to be a second door — an "ENTER RACE" pad on each
	    plot's forecourt that dropped you into the world you were already in, in the car you chose
	    last. All six, and the old dev slab, were deleted from the place: this button is now the only
	    way into a race. RaceService's tag-driven trigger still exists and still works, so re-tagging
	    a part brings that route back with no code change.

	  • THE BUTTON IS NOT NAMED HERE. `MainUI.HUD.Play` carries an `Action` attribute
	    ("EnterRace", from `RaceConfig.EnterRaceAction`); `Components/Button` publishes that
	    string on Dispatcher and this subscribes to it. Same bargain as the `Page` attribute the
	    rail buttons use — the place file decides which button does this, code decides what it
	    means — so re-parenting or renaming the button in the Explorer cannot break it, and a
	    second Play button somewhere else costs one attribute.

	    A Play button that carries a `Page` attribute as well opens the screen ITSELF (that is
	    the house rule: a button says which page it opens). This steps aside when it sees one,
	    because `openPage` toggles — opening the same page twice off one press would open it and
	    immediately shut it again, which reads as a dead button.

	  • THE SERVER DECIDES. The press only fires `RequestEnterRace`; RaceService owns every
	    guard and can refuse. So the local checks here (`_racing`, the cooldown) are courtesy —
	    they stop the obvious spam at the source instead of paying for a round trip to be told
	    no. Nothing here is a permission check, and nothing downstream trusts it as one.

	  • THE WORLD RIDES ALONG WITH THE REQUEST rather than being set first by a separate remote.
	    Two remotes would be two round trips whose order nothing guarantees, and a race that
	    started before the world landed would build the wrong road. One message, one decision:
	    `RaceService._onEnterRequest` moves the player and refuses the race if it cannot.

	=== AND THE LOBBY'S UI GOES AWAY FOR THE RUN ===============================================

	A race is the one part of this game the player has to READ — traffic closing, an obstacle they
	have half a second to steer around, the HP bar telling them whether the next hit ends it. Every
	pixel of lobby UI over that is either noise or a trap, so the screen is handed to the driving
	HUD (`DrivingHudController`, `CarHudController`) and the lobby's own furniture stands down:

	    the Play button      here                    a button that cannot do anything mid-run
	    the rail             here                    five screens, none of them about this run
	    every open page      here (`closeAllPages`)  a full-screen panel over the road
	    the cash pill        `GarageHudController`   the one number that cannot change during a run

	What is deliberately LEFT is as much of the statement as what goes. The music toggle stays,
	because it is in Roblox's topbar rather than on our screen and it survives every other screen
	too (`TopbarController`). The revive question stays — it is its own ScreenGui and it is the one
	thing on screen that IS about the run. Nothing here touches Roblox's own CoreGui.

	IT IS FOUR SEPARATE HIDES AND NOT ONE, i.e. nobody hides `MainUI.HUD` wholesale even though its
	three children are exactly the three things going. Each element keeps ONE writer and one switch:
	the pill is `GarageConfig.Hud.HideDuringRace` and is hidden by the controller that owns it, and
	blanking the parent would silently override both that switch and `RaceConfig.HidePlayDuringRace`
	while leaving them looking live in the config.

	=== THE BRACKET ============================================================================

	`RaceStart`/`RaceEnd` (not `RaceEntering`/`RaceLive`) bracket the run, matching what
	CarHudController and GarageHudController hide against. That pairing is the one that always
	closes: the failure paths in `enterRace` — no car template, no VehicleSeat — bail after
	`RaceEntering` and fire only `RaceLive`, so hiding on `RaceEntering` would leave a player
	with the Play button gone and no race to show for it. It is also why the world screen is put
	away on `RaceStart` and not on the press: a refused press leaves it open, which is correct —
	you have not gone anywhere and the screen is where you would pick again.

It is also why a WRECK does not bring any of it back. `RaceEnd` is fired by `leaveRace` and
	nowhere else, and a wreck with a revive on offer stops short of it — `RaceService.wreckRace`
	hands the beat to `ReviveService` and only reaches `endWreckedRun` once the offer is declined or
	times out. So the rail stays down over the question rather than flickering back for the seconds
	the player is deciding, and comes back once, behind the fade, when the run is genuinely over.

	=== AND THE FOURTH PRESS IS THE ONE THAT ISN'T =============================================

	RACE AGAIN, on the results screen, is the same request with nothing named on it — same world,
	same car, straight back out — and it exists because the three presses at the top of this file
	are the wrong price for a run somebody has just decided they want again. `RaceUIController`
	draws the button and publishes `RaceConfig.ReplayEvent`; this file is what turns that into the
	one request it already knows how to send. Nothing about the Play route changes, and nothing here
	decides whether the offer was still open — that is the screen's, and the server re-checks all of
	it either way.

	IT IS QUEUED RATHER THAN SENT WHEN A RUN IS STILL LIVE. `_racing` is the bracket above, and in
	practice it is long since false by the time a replay can be pressed: `RaceEnd` lands at the top
	of the results hold, seconds before the button arrives. But "in practice" is not a guarantee,
	and an entry request fired inside a live run is one the server throws away silently. Holding it
	for `RaceEnd` costs one field and makes the press unlosable.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
--- The beckon arrow's bob (`_beckonArrow`).
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local CarryConfig = require(ReplicatedStorage.shared.Configs.CarryConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local CollectorConfig = require(ReplicatedStorage.shared.Configs.CollectorConfig)
--- The tutorial's arrow art, reused over Play (`_beckonArrow`).
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local ButtonBeckon = require(ReplicatedStorage.shared.Modules.ButtonBeckon)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

--[[ === THE PLAY BUTTON'S SLIDE ==============================================================

	Play leaves and returns by dropping off the bottom of the screen rather than blinking, because
	the thing it is making room for arrives the same way — `Pages/Dealership`'s `Done` stands in
	exactly its pixels and slides up into them. Two buttons swapping places reads as one object
	changing; two buttons blinking reads as a flicker.

	IT IS A `Position` TWEEN AND NOT A SCALE ONE, and that is not a style choice: Play is tagged
	`UIButton`, so `Components/Button` has already parked a `UIScale` named `HoverScale` on it, and
	only ONE UIScale on an instance takes effect. A second one here would be silently ignored and
	the hover nudge would be fighting the entrance for the one channel that is left.

	`PLAY_DROP` is a fraction of the SCREEN. The button is centre-anchored at y 0.91 and 0.075 tall,
	so its top edge sits at 0.8725 and 0.1275 is the exact drop that clears the bottom. The margin
	above that covers the two windows where it is not exact: the aspect constraint on this button is
	`FitWithinMaxSize`, so the box can be taller than what renders, and a device with a bottom
	safe-area inset moves the edge up. `Pages/Dealership.DONE_DROP` carries the same number for the
	same rectangle.

	THE OUT IS FASTER THAN THE IN on purpose. Leaving is not the beat the player is waiting on; the
	thing arriving is. `Pages/Dealership` times its own `Done` against these two numbers — its
	`DONE_IN_DELAY` starts just after the out finishes — so they are read together. ]]
--[[ === PLAY MOVED UP — 2026-09-30 ==========================================================
	WAS 0.16, exact for a button at 0.91. The owner moved Play up to stand on the hotbar (which now
	owns the bottom edge, `CarryConfig.Hotbar`), to about 0.83; from there 0.16 would leave its top
	third on screen at the bottom of the slide. 0.26 clears a centre anywhere down from 0.78 with the
	same margin the old number had — raise it if Play ever goes higher than that. ]]
local PLAY_DROP = 0.26

--[[ === PLAY STANDS ON THE HOTBAR, ON EVERY SCREEN — 2026-10-01 ==============================
	Play's authored home is a SHARE of the screen (0.83) and the hotbar is PIXELS (64px tiles, 10px
	off the bottom, `CarryConfig.Hotbar`), so the two only agree on a tall window. On a short phone
	the bar reaches higher up the screen than Play's bottom edge and slots draw over the button.

	So the home Play rests on is the authored one, or higher by exactly the overlap when the bar
	would reach it (`_playRest`). Only ever higher: on a screen with room the authored spot stands.
	The lift is an OFFSET on the authored UDim2, so the slide above still drops it by `PLAY_DROP`.
	`PLAY_BAR_GAP` is the daylight kept between Play's bottom edge and the bar's top, in pixels. ]]
local PLAY_BAR_GAP = 6
local PLAY_OUT_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PLAY_IN_TWEEN = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local RaceEntryController = Shard.new("RaceEntryController")

--[[ Public: ask the server for a race, optionally in a particular world (nil = the one we are
	already in) and optionally in a particular car (nil = whatever was chosen last time). The
	world-select screen's cards come through here, and so do the car screen's — see `WorldController`
	and `StartCarController`.

	BOTH RIDE ON THE ONE REQUEST for the reason in the header: two remotes would be two round trips
	whose order nothing guarantees, and a race that started before its car landed would be a race in
	the wrong car. The server stores the car (so the lobby pad honours it next time) and then reads it
	back once, exactly as it does the world.

	Cheap local refusals first; the server re-checks all of it. ]]
function RaceEntryController.play(self, world: number?, carKey: string?)
	if self._racing then
		return
	end
	local now = os.clock()
	if now < self._nextRequestAt then
		return
	end
	self._nextRequestAt = now + RaceConfig.EnterRequestCooldown

	self:getRemoteEvent("RequestEnterRace"):Fire(world, carKey)
end

--[[ The results screen's RACE AGAIN, which is `play` with nothing named on it.

	NEITHER A WORLD NOR A CAR, and the omission is the feature. Both are stored server-side from the
	entry that started the run that just ended (`RaceService._onEnterRequest` writes them through
	`WorldService` and `StartCarService`), so a request that names neither is read back as exactly
	the run the player has just been reporting on. Naming them here would mean the client holding a
	second copy of two values it does not own, and a replay that disagreed with the screen it was
	pressed on about which car was in the picture.

	IT DOES NOT GO THROUGH THE WORLD SCREEN, whatever `PlayOpensWorldSelect` says. That switch is
	about what the Play BUTTON means, and this is not it: a player who wanted to pick a world would
	have let the offer close and pressed Play, which is two seconds away and still does exactly that.

	QUEUED IF A RUN IS SOMEHOW STILL LIVE; see the header. `_replayPending` is cleared by the send,
	so a queued press cannot be spent twice. ]]
function RaceEntryController.replay(self)
	if self._racing then
		self._replayPending = true
		return
	end
	self._replayPending = false
	self:play()
end

--[[ The Play button's press: open the world screen, or go straight in if that step is switched
	off. `instance` is the button, so a Play button authored with its own `Page` attribute is left
	alone — `Components/Button` has already opened the screen by the time this runs. ]]
function RaceEntryController._onPlayPressed(self, instance: Instance?)
	-- It was asking for exactly this press, so it is done for the session. See `_applyBeckon`.
	self._beckonArmed = false
	self:_applyBeckon()

	if not RaceConfig.PlayOpensWorldSelect then
		self:play()
		return
	end
	if instance and instance:GetAttribute("Page") then
		return
	end
	local startCar = Shard.get("StartCarController")
	if startCar and startCar:oneScreen() then
		startCar:openPlay()
		return
	end
	Dispatcher:Publish("OpenPage", WorldConfig.PageName)
end

--[[ Resolve the Play button, once, for the hide-during-a-race pass.

	Found by its `Action` attribute rather than by path, so this agrees with the Dispatcher half
	about which button is the Play button even if it moves. Cached, and re-resolved if the
	cached one has left the tree (a page rebuild, a ResetOnSpawn), so a stale reference can
	never leave the real button hidden. ]]
function RaceEntryController._playButton(self): GuiButton?
	if self._button and self._button:IsDescendantOf(game) then
		return self._button
	end
	--[[ A different button means a different authored home. `_playHome` is latched off the FIRST
		sight of a button and everything below moves it, so it has to be dropped here or a rebuilt
		HUD would be animated back to the old one's position. ]]
	self._button = nil
	self._playHome = nil
	self._playShown = nil

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local mainUI = playerGui and UIRoot.find(playerGui)
	if not mainUI then
		return nil
	end
	for _, descendant in mainUI:GetDescendants() do
		if descendant:IsA("GuiButton") and descendant:GetAttribute("Action") == RaceConfig.EnterRaceAction then
			self._button = descendant
			return descendant
		end
	end
	return nil
end

--- Play, and whether it is up rather than hidden for a race or stepped aside for a page. For lobby
--- chrome that docks against it: the touch BACK TO BASE pill in `DealershipMarkerController`.
function RaceEntryController.playButton(self): (GuiButton?, boolean)
	local button = self:_playButton()
	return button, button ~= nil and button.Visible and self._playShown ~= false
end

--[[ THE ONE WRITER OF `Play.Visible`, and it is written from two facts rather than from two
	callers. The race is the first: a button that cannot do anything mid-run is noise over the road.
	The second is the Cars Inventory, which stands its own `Done` button in exactly the pixels Play
	occupies (see `Pages/Dealership`, header note 7) and asks Play to step aside for as long as it
	is open — over `SuppressPlayButton`, because a page that wrote the property itself would fight
	this one.

	IT HAS TO BE A COMPUTED PROPERTY AND NOT TWO SETTERS. `RaceStart` hides the button and THEN
	publishes `CloseAllPages`, so the inventory's own close lands after the race has already hidden
	it; a close that simply set `Visible = true` would put the Play button back up over the road.
	Restating both facts on every change is the only shape where the order of the two cannot matter.

	`RaceConfig.HidePlayDuringRace` gates only the RACE half. The page's request is not a tuning
	switch — the two buttons genuinely overlap — so it is honoured either way. ]]
function RaceEntryController._applyButtonVisible(self, animate: boolean?)
	local button = self:_playButton()
	if not button then
		return
	end

	-- The authored home, read before anything has had a chance to move it. Play rests on
	-- `_playRest`, which is this lifted clear of the hotbar when the screen is short.
	if self._playHome == nil then
		self._playHome = button.Position
	end

	local hiddenForRace = self._racing and RaceConfig.HidePlayDuringRace
	-- No PLAY at all while the collector highway is the game: you walk in instead.
	local shown = CollectorConfig.racesOn() and not (hiddenForRace or self._playSuppressed)
	--[[ Nothing to do, and it has to be checked BEFORE the tween rather than left to look like a
		no-op: re-running the entrance on a button that is already home would replay the animation
		every time either fact was restated. `RaceEnd` restates both. ]]
	if self._playShown == shown then
		return
	end
	self._playShown = shown
	self:_applyBeckon()

	if self._playTween then
		self._playTween:Cancel()
		self._playTween = nil
	end

	local home = self:_playRest(button)
	local away = UDim2.new(home.X.Scale, home.X.Offset, home.Y.Scale + PLAY_DROP, home.Y.Offset)

	--[[ THE RACE DOES NOT ANIMATE. It is hidden behind the entry fade and the player is being moved
		to another part of the map — a button politely sliding away under a black screen is work
		nobody sees. Only the page swap asks for the slide, because only the page swap is watched. ]]
	if not animate then
		button.Position = home
		button.Visible = shown
		return
	end

	if shown then
		button.Position = away
		button.Visible = true
		self._playTween = TweenService:Create(button, PLAY_IN_TWEEN, { Position = home })
		self._playTween:Play()
	else
		self._playTween = TweenService:Create(button, PLAY_OUT_TWEEN, { Position = away })
		self._playTween:Play()
		--[[ Hidden only once it is off screen, and put back on its home the same instant, so the
			next `Visible = true` from the un-animated path lands on the authored position rather
			than on wherever this tween stopped. Guarded on `_playShown` because a race can start
			mid-slide and will have already decided the answer. ]]
		self._playTween.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed and self._playShown == false then
				button.Visible = false
				button.Position = home
			end
		end)
	end
end

--[[ THE ONE SWITCH FOR PLAY'S BECKON (`RaceConfig.PlayBeckon`), computed from two facts like
	`_applyButtonVisible` and for the same reason: somebody asked for it (`_beckonArmed`, set by the
	request and cleared by a press or a run) and Play is actually up. A page standing in Play's place
	pauses it and the button picks it back up when it slides home; the first beat waits `FirstDelay`,
	which is longer than that slide.

	Keyed to the button it was started on, so a rebuilt HUD moves it to the new one rather than
	leaving it running on a destroyed copy. ]]
function RaceEntryController._applyBeckon(self)
	local button = self:_playButton()
	local want = self._beckonArmed and button ~= nil and self._playShown ~= false
	if self._beckonStop and (not want or self._beckonOn ~= button) then
		self._beckonStop()
		self._beckonStop = nil
		self._beckonOn = nil
	end
	if want and button and not self._beckonStop then
		local stopBeckon = ButtonBeckon.start(button, RaceConfig.PlayBeckon)
		local stopArrow = self:_beckonArrow(button)
		self._beckonStop = function()
			stopBeckon()
			stopArrow()
		end
		self._beckonOn = button
	end
end

--[[ The tutorial's arrow over Play while it beckons (`RaceConfig.PlayBeckon.Arrow`). Answers the
	undo. Sized and bobbed in SCALE of the button, the tutorial arrow's own reason (`_arrowPos`): an
	offset bob moves in whole pixels and stutters. ]]
function RaceEntryController._beckonArrow(self, button: GuiObject): () -> ()
	local cfg = RaceConfig.PlayBeckon
	if not cfg.Arrow then
		return function() end
	end
	local arrow = Instance.new("ImageLabel")
	arrow.Name = "BeckonArrow"
	arrow.AnchorPoint = Vector2.new(0.5, 1)
	arrow.BackgroundTransparency = 1
	--- The art points DOWN at whatever is under it (`TutorialController._build`'s note).
	arrow.Image = UIAssets.url(UIAssets.Tutorial.Arrow)
	arrow.ScaleType = Enum.ScaleType.Stretch
	arrow.Size = UDim2.fromScale(cfg.ArrowSize, cfg.ArrowSize)
	arrow.ZIndex = button.ZIndex + 5
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.DominantAxis = Enum.DominantAxis.Height
	square.Parent = arrow
	arrow.Parent = button
	local started = os.clock()
	local bob = RunService.RenderStepped:Connect(function()
		local swing = (1 + math.sin((os.clock() - started) * 2 * math.pi / cfg.ArrowBobPeriod)) / 2
		arrow.Position = UDim2.fromScale(0.5, -0.05 - swing * cfg.ArrowBob)
	end)
	return function()
		bob:Disconnect()
		arrow:Destroy()
	end
end

--[[ Where Play rests: the authored home, lifted clear of the hotbar if the bar would reach it. See
	`PLAY_BAR_GAP`.

	READ OFF THE BAR ITSELF rather than re-derived from `CarryConfig.Hotbar`, so a bar that is ever
	built differently is still the bar Play clears. Both `AbsolutePosition`s are in the one shared
	space whatever each gui's `IgnoreGuiInset` says, so the two compare directly. No bar (it is
	switched off, or not built yet) is no lift.

	THE HEIGHT COMES FROM `Size`, NOT `AbsoluteSize`, because `Components/Button`'s `HoverScale`
	grows `AbsoluteSize` under the cursor and a hover must not move the button's home. The aspect
	constraint is applied by hand for the same reason. ]]
function RaceEntryController._playRest(self, button: GuiObject): UDim2
	local home = self._playHome
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local hotbarGui = CarryConfig.Hotbar.Enabled and playerGui and playerGui:FindFirstChild("CarryHotbar")
	local bar = hotbarGui and hotbarGui:FindFirstChild("Bar")
	local parent = button.Parent
	if not (bar and bar:IsA("GuiObject") and parent and parent:IsA("GuiBase2d")) then
		return home
	end
	local barTop = bar.AbsolutePosition.Y
	if barTop <= 0 then
		return home -- not laid out yet; the bar's own AbsolutePosition change will call back
	end

	local box = parent.AbsoluteSize
	local width = button.Size.X.Scale * box.X + button.Size.X.Offset
	local height = button.Size.Y.Scale * box.Y + button.Size.Y.Offset
	local aspect = button:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect and aspect.AspectRatio > 0 then
		height = math.min(height, width / aspect.AspectRatio)
	end
	local bottom = parent.AbsolutePosition.Y + home.Y.Scale * box.Y + home.Y.Offset + (1 - button.AnchorPoint.Y) * height

	local overlap = bottom - (barTop - PLAY_BAR_GAP)
	if overlap <= 0 then
		return home
	end
	return UDim2.new(home.X.Scale, home.X.Offset, home.Y.Scale, home.Y.Offset - math.ceil(overlap))
end

--[[ Put a resting Play back on `_playRest`, after the screen or the bar has moved. A Play that is
	hidden or mid-slide is left alone: both paths in `_applyButtonVisible` ask `_playRest` again on
	their way back in. ]]
function RaceEntryController._placePlay(self)
	local button = self:_playButton()
	if not button then
		return
	end
	if self._playHome == nil then
		self._playHome = button.Position
	end
	if self._playShown == false then
		return
	end
	if self._playTween and self._playTween.PlaybackState == Enum.PlaybackState.Playing then
		return
	end
	button.Position = self:_playRest(button)
end

--[[ Everything that can change whether the bar reaches Play: the window, the menu UI arriving, and
	the bar being built or laid out. The bar's `AbsolutePosition` is the one that matters most, since
	it is the first moment the bar has a real position to measure. ]]
function RaceEntryController._watchPlayRoom(self)
	local function place()
		self:_placePlay()
		-- Nothing else restates Play at boot, so the authored Visible = true would stand.
		if not CollectorConfig.racesOn() then
			self:_applyButtonVisible()
		end
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(place)
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function watch(child: Instance)
		if child.Name == "CarryHotbar" then
			local bar = child:WaitForChild("Bar", 10)
			if bar and bar:IsA("GuiObject") then
				bar:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
			end
		end
		task.defer(place)
	end
	playerGui.ChildAdded:Connect(watch)
	for _, child in playerGui:GetChildren() do
		task.spawn(watch, child)
	end
end

--[[ Resolve the rail — the column of page buttons down the left of the HUD — for the same pass.

	BY NAME, unlike the Play button above. The rail is one box the artist drew around its own
	buttons and `MainUI.HUD.Rail` is what every other file that reasons about it already calls it
	(`Components/GamepadNav` walks it, `TutorialController._obstacles` dodges it as a single
	rectangle). There is no attribute to find it by, and inventing one to make the two resolvers
	match would put a second name on a thing that already has one.

	THE BOX, NOT ITS BUTTONS. Hiding the frame takes the whole column off screen in one write and
	leaves each button's own `Visible` untouched, so nothing here can strand a button that some
	other pass had hidden for a reason of its own — a `false` we never set is a `false` we never
	have to put back. It is also what `GamepadNav.isShown` already walks ancestors to check.

	Cached and re-resolved on the same terms as the Play button: `MainUI` is `ResetOnSpawn = false`
	so this should be resolved once for the session, and the `IsDescendantOf` check is what stops a
	rebuilt HUD leaving the real rail hidden for the rest of the run. ]]
function RaceEntryController._rail(self): GuiObject?
	if self._railFrame and self._railFrame:IsDescendantOf(game) then
		return self._railFrame
	end
	self._railFrame = nil

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	--- The new UI's side grid is authored under the same two names (`HUD.Rail`), which is what keeps
	--- the race's four hides out of the migration. See `docs/NewUI-Migration-Notes.md`.
	local mainUI = playerGui and UIRoot.find(playerGui)
	local hud = mainUI and mainUI:FindFirstChild("HUD")
	local rail = hud and hud:FindFirstChild("Rail")
	if rail and rail:IsA("GuiObject") then
		self._railFrame = rail
		return rail
	end
	return nil
end

--[[ THE ONE WRITER OF `Rail.Visible`, and like the Play button it is written from facts rather than
	by callers. There are two of them now.

	THE RACE is the first: a column of lobby screens over the road is noise, and `RaceConfig
	.HideRailDuringRace` is its switch.

	THE CAR DETAIL WINGS are the second (2026-09-17). They stand either side of a centred kit page,
	and the rail's icon grid is in the room the left one needs — `BuildCarDetailV2`'s header has the
	arithmetic, and the short version is that nothing readable fits in the ninety pixels between the
	page and the grid. So the wings ASK, over `SuppressRail`, exactly as the Cars page asks for Play's
	pixels. `CarDetailConfig.HideRail` is that half's switch and it is checked by the asker, so the
	request never arrives when it is off.

	COMPUTED FROM BOTH, never two setters: `RaceStart` hides the rail and THEN publishes
	`CloseAllPages`, so a page's own close lands after the race has already taken it away, and a close
	that simply wrote `true` would put the rail back up over the road. Same trap, same shape, same
	reason as `_applyButtonVisible`. ]]
function RaceEntryController._applyRailVisible(self)
	local rail = self:_rail()
	if not rail then
		return
	end
	local hiddenForRace = self._racing and RaceConfig.HideRailDuringRace
	rail.Visible = not (hiddenForRace or self._railSuppressed)
end

function RaceEntryController._onRaceStart(self)
	self._racing = true
	-- Out on the road is what the beckon was asking for, however they got there.
	self._beckonArmed = false
	self:_applyButtonVisible()
	self:_applyBeckon()
	self:_applyRailVisible()
	--[[ ...and every panel with them, behind the entry fade.

		EVERY page rather than the two the run was chosen on. Those two — the world screen and the
		car screen — are the ones that are normally up at this moment and were the whole of this
		call for that reason. But they were never the whole of what could be: the rail's five
		screens open over the road as readily as they do over the lobby, and the pad-and-tag entry
		route `RaceService` still supports opens neither of them, so naming two pages here was a
		list that happened to be complete rather than one that was. `closeAllPages` is the statement
		that was meant — no page belongs on screen during a run — and it is a no-op tween for every
		page that is already shut. ]]
	Dispatcher:Publish("CloseAllPages")
end

function RaceEntryController._onRaceEnd(self)
	self._racing = false
	-- Straight back on: the fade is still up over it (RaceUIController holds the overlay through
	-- the teleport home), so the HUD is already on screen by the time the player can see it.
	self:_applyButtonVisible()
	self:_applyRailVisible()

	--- ...and a replay that arrived while the run was still closing down goes out now, which is the
	--- first moment the server will look at it. See `replay`: this should never fire in practice.
	if self._replayPending then
		self:replay()
	end
end

RaceEntryController:withRemoteEvents({
	{
		RaceStart = function()
			RaceEntryController:_onRaceStart()
		end,
		RaceEnd = function()
			RaceEntryController:_onRaceEnd()
		end,
	},
	"RequestEnterRace",
})

RaceEntryController:withLifecycle({
	init = function(self)
		self._racing = false
		self._nextRequestAt = 0
		self._button = nil
		self._railFrame = nil
		-- Set by whichever screen is standing where Play stands; see `_applyButtonVisible`.
		self._playSuppressed = false
		-- Who is asking, by source; `_playSuppressed` is whether anyone is. See `SuppressPlayButton`.
		self._playSuppressors = {} :: { [string]: boolean }
		self._playHome = nil
		self._playShown = nil
		self._playTween = nil
		-- Whether anything has asked for the rail's room, and who. See `SuppressRail`.
		self._railSuppressed = false
		self._railSuppressors = {} :: { [string]: boolean }
		--- A RACE AGAIN press that landed before `RaceEnd` did, waiting for it. See `replay`.
		self._replayPending = false
		--- Play calling for its next press: asked for, and the stop for the run in progress. See `_applyBeckon`.
		self._beckonArmed = false
		self._beckonStop = nil :: (() -> ())?
		self._beckonOn = nil :: GuiButton?
	end,

	start = function(self)
		task.spawn(self._watchPlayRoom, self)

		Dispatcher:Subscribe("UIAction", function(action: string, instance: Instance?)
			if action == RaceConfig.EnterRaceAction then
				self:_onPlayPressed(instance)
			end
		end)

		--[[ "A screen is standing in Play's place." Published by `Pages/Dealership` on either side of
			its open, and on the new UI by `UIController` while any page is open. It is a REQUEST and
			not a write: see `_applyButtonVisible` for why that distinction is what keeps a race and a
			page close from disagreeing about the button.

			EACH ASKER IS COUNTED ON ITS OWN, by the `source` it names, so the first of two to let go
			cannot bring Play back up under the other. The old Dealership names none and has the
			default key to itself. ]]
		Dispatcher:Subscribe("SuppressPlayButton", function(suppressed: boolean, source: string?)
			self._playSuppressors[source or "default"] = if suppressed == true then true else nil
			self._playSuppressed = next(self._playSuppressors) ~= nil
			self:_applyButtonVisible(true)
		end)

		--[[ "A panel needs the room the rail is standing in." Published by `Components/CarDetailV2`
			on either side of the car screens' detail wings, and a REQUEST rather than a write for the
			same reason Play's is — see `_applyRailVisible`.

			COUNTED PER SOURCE, and the two car screens each name their own page, because both can be
			mid-close at once (opening one closes the other) and the first to let go must not put the
			rail back under the second. ]]
		Dispatcher:Subscribe("SuppressRail", function(suppressed: boolean, source: string?)
			self._railSuppressors[source or "default"] = if suppressed == true then true else nil
			self._railSuppressed = next(self._railSuppressors) ~= nil
			self:_applyRailVisible()
		end)

		--- "The results screen's RACE AGAIN was pressed." Published by `RaceUIController._pressReplay`
		--- and answered by the one function above that knows what another run costs to ask for.
		Dispatcher:Subscribe(RaceConfig.ReplayEvent, function()
			self:replay()
		end)

		--- "Send the player back out": Play beckons until it is pressed. Published by the tutorial's
		--- finish card. See `RaceConfig.PlayBeckon`.
		Dispatcher:Subscribe(RaceConfig.PlayBeckon.Event, function()
			if not RaceConfig.PlayBeckon.Enabled or self._racing then
				return
			end
			self._beckonArmed = true
			self:_applyBeckon()
		end)
	end,
})

return RaceEntryController
