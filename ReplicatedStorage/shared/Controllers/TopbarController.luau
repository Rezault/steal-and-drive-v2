--[[
	TopbarController  (client)
	--------------------------
	Everything the game puts in ROBLOX'S topbar. Three doors: the RADIO button, which opens
	`RadioPanelController`, the SETTINGS button, which opens the `Settings` page, and the SHOP
	button, which opens the `Shop` page. Named for the strip rather than for any of them because the
	strip is the shared resource: the DPad negotiation below is settled once, for whatever ends up
	living here, and another icon should join this file rather than requiring TopbarPlus again.

	THE SHOP DOOR IS A STOPGAP AND IS MARKED AS ONE. It is here so the shop page can be opened and
	looked at while the real way in is drawn; the owner is importing a menu HUD button to carry it.
	It is also the only door onto a `UIController` PAGE rather than onto a panel controller, which
	is why `_buildPageDoor` exists next to `_buildDoor`. See both.

	That button now exists: it is a cell of the new HUD's grid, and this door stands down when the new
	UI is the one in play. The split was `docs/NewUI-Migration-Plan.md`, "The new HUD": the topbar
	keeps what a player reaches for mid-run, because the grid leaves the screen for a race.

	SOUND AND DAILY REWARDS ARE LOBBY-ONLY (2026-10-12), keeping the driving screen clear. Settings
	retains the older grid-dependent rule: race-only when its grid cell exists, otherwise always up.
	`_setRacing` applies both rules, including while SHOW UI holds the strip.

	WHEN EACH ICON IS WORTH BUILDING IS NOT DECIDED HERE ANY MORE. The four rules moved to
	`Modules/UIVisibility` when the shop's rule acquired a second reader, so that the grid and the
	strip cannot end up disagreeing about whether there is a shop. The rules did not change; see that
	file's header for each of them.

	=== AND ONE THING THAT IS NOT A DOOR: SHOW UI ===============================

	`InterfaceController` hides every ScreenGui in the game and has to leave a way back. That way
	back is now a button in this strip, so it is built here (`_buildRestore`) like everything else
	that appears in the topbar, and `setRestoreOnly` is how that file asks for it: SHOW UI on, every
	other icon off, the strip itself left up.

	IT IS THE ONE ICON IN HERE WITH WORDS ON IT and the one that is normally invisible. Both follow
	from where it is met: an empty screen, by a player who may have forgotten they cleared it. The
	reasoning for the button existing at all, and for it being in the topbar rather than floating in
	a corner, is in `InterfaceConfig`'s header rather than repeated here.

	=== THE MUTE USED TO BE HERE, AND IS NOT ANY MORE ===========================

	The music toggle was the first thing in this strip and it is now a pill on the radio panel, which
	is the screen a player thinking about sound is already on: four stations, a track box, and the
	soundtrack switch, all under one title bar. That freed the leftmost slot for settings.

	IT IS STILL BUILT HERE IN ONE CASE, and the case is not hypothetical: `RadioConfig.sellable()`
	covers a radio that has been switched off or never synced, and if the panel cannot be opened then
	the mute has nowhere else to live. So the music icon appears exactly when its new home does not,
	which is the same rule that has always governed this strip: a button onto something that cannot
	answer is worse than no button. `UIAssets.Topbar.MusicOn` and `MusicOff` are live for that path
	and `_paint` below is the whole of it.

	=== THE TWO DOORS ARE NOT THE SAME KIND OF BUTTON AS THE MUTE ===============

	Worth being exact about, because they all look identical in the strip. The radio, settings and
	shop icons are DOORS: their selected/deselected is the panel being open or shut, and the state of
	what is behind them lives elsewhere and appears only in the caption. The music icon IS a state:
	its selected/deselected is the mute, drawn from `MusicController` and never the other way round
	(see "THE ICON IS DRAWN FROM THE CONTROLLER" below). So `_paint` has an `_applying` guard.

	THE SHOP DOOR NEEDS A GUARD TOO, and it is the exception to what this section used to say. The
	radio and settings panels only ever close through their own button, so nothing but a press moves
	those icons. A page does not have that property: its X, another page opening over it and
	`closeAllPages` all shut it without the topbar hearing, so the shop icon is repainted from the
	page's `Visible` and therefore moves in code. `_applyingPage` is that guard and it is there for
	exactly the reason `_applying` is.

	NOT PART OF THE UI KIT, AND DELIBERATELY SO. Every other button in this game is authored art
	tagged `UIButton` with a `Page` attribute, drawn by `UIController` (see that folder's header for
	why nothing opens a page from code). These are not: the topbar is a strip Roblox owns and
	positions, it survives every page and the whole of a race, and TopbarPlus already solves the
	inset, the safe area, the console cursor and the phone layout for it. Rebuilding that inside
	`MainUI` to keep the pattern pure would be the more expensive mistake.

	=== THE DPAD BELONGS TO THE RAIL ===========================================

	`Icon.highlightKey = false` is the load-bearing line in this file.

	Left alone, TopbarPlus listens for DPadUp on a raw `UserInputService.InputBegan` and answers it
	by writing `GuiService.SelectedObject` to its own icon. This game already spends that key:
	`GamepadConfig.FocusKeys` is all four DPad directions and `Components/GamepadNav` answers them
	by putting the highlight on the left-hand rail, the "ask for the menu" gesture that file's
	header describes.

	Two writers of `SelectedObject` on one key is a race, and it is not confined to the first press.
	GamepadNav unbinds its focus action once something IS selected, but TopbarPlus's listener is
	unconditional and never stops, so every DPadUp made while navigating the rail would yank the
	highlight up to the topbar. That is not a conflict to tune, it is rail navigation not working.

	So the topbar gives the key up, and a pad still reaches these buttons, by NAVIGATION rather than
	by a key of their own: with the highlight on the top of the rail, Up moves it onto the leftmost
	icon (the engine's own geometry does it, measured 2026-10-15), Left and Right walk the strip, and
	A on an icon presses it (the engine's activation fires the `MouseButton1Click` TopbarPlus listens
	for). A page opened from an icon gives the highlight back to that icon when B shuts it. This used
	to say the way in was ButtonSelect and Roblox's gamepad cursor; Select is the hotbar's backpack
	now, so do not plan anything around that route.

	=== THE ICON IS DRAWN FROM THE CONTROLLER, NEVER THE OTHER WAY ==============

	This is about the fallback music icon, and it is the reason that icon is not simply a TopbarPlus
	selection. Its selected/deselected state would be very easy to let BE the mute (press, it
	selects, music stops) and it is not, because of the seed: the server's saved answer can arrive a
	second after the topbar is up, and when it does the button has to move without a press. There is
	exactly one truth (`MusicController._muted`), the button publishes presses into it, and `_paint`
	moves the icon to match whatever it says, which is the same bargain the world cards make with
	`WorldConfig.StateEvent`.

	`_applying` is what keeps that one-way. Moving the icon in code fires its own selected and
	deselected events, so without the flag a repaint would look exactly like a press, call back into
	the controller, and save a preference the player never expressed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Icon = require(ReplicatedStorage.Packages.TopbarPlus)
local Shard = require(ReplicatedStorage.Packages.Shard)
local DayNightConfig = require(ReplicatedStorage.shared.Configs.DayNightConfig)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local InterfaceConfig = require(ReplicatedStorage.shared.Configs.InterfaceConfig)
local MusicConfig = require(ReplicatedStorage.shared.Configs.MusicConfig)
local NewUIConfig = require(ReplicatedStorage.shared.Configs.NewUIConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local RadioConfig = require(ReplicatedStorage.shared.Configs.RadioConfig)
local SettingsConfig = require(ReplicatedStorage.shared.Configs.SettingsConfig)
--- The daily reward's door (`DailyRewardConfig.Topbar`). A config; it requires nothing.
local DailyRewardConfig = require(ReplicatedStorage.shared.Configs.DailyRewardConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)
local UIVisibility = require(ReplicatedStorage.shared.Modules.UIVisibility)

local TopbarController = Shard.new("TopbarController")

--[[ Where each icon sits in the strip. Left, which is where TopbarPlus puts developer icons and
	where a Roblox player looks for them: the game's own rail is lower down and does not reach the
	topbar, and the HUD's top-centre HP bar hangs below the inset, so nothing is under any of them.

	THE RADIO IS FIRST because it is the one with something to sell and the one a player has no
	other way of finding out about. Settings is second because it is where settings always are: last
	in a row of utilities, and a thing people go looking for rather than a thing that has to catch
	them.

	The music fallback is third and is almost never built (see the header). Third rather than first
	so that on the one build where it does appear, the two doors do not move. ]]
local RADIO_ORDER = 1
local SETTINGS_ORDER = 2
--[[ SHOP, 2026-09-02. THIRD RATHER THAN FIRST, WHICH THIS FILE'S OWN RULE ARGUES AGAINST, and it is
	worth saying why. Radio is first because it is "the one with something to sell", and a shop is
	more that than the radio is, so a permanent shop button belongs at the front of this strip.

	This one is not permanent. It exists so the page can be opened and looked at while the real way
	in is drawn: the owner is importing a menu HUD button that will take this over. Putting it third
	leaves the two doors players have already learned exactly where they are, and costs nothing,
	because the thing that will actually carry the shop is not this icon. Move it to 1 (and shift the
	rest) if it outlives that plan. ]]
local SHOP_ORDER = 3
local MUSIC_ORDER = 4

--[[ SHOW UI's order is not here, it is `InterfaceConfig.RestoreIcon.Order`, and that is deliberate:
	everything else about that button (its words, when it appears, what a press means) is owned by
	the hide feature, so the one number that decides where it sits belongs with the rest of it
	rather than split across two files. It is 0, in front of these. ]]

--- Move the music icon to match the controller. Never called from a press. See the header.
function TopbarController._paint(self, muted: boolean)
	local icon = self._icon
	if not icon then
		return
	end

	self._applying = true
	if muted then
		icon:select()
	else
		icon:deselect()
	end
	self._applying = false

	--[[ The caption names the STATE, matching the glyph ("a struck-through note means muted"),
		rather than the action a press would perform. Both readings are defensible and every media
		player the player has ever used picks this one. ]]
	icon:setCaption(if muted then "Music: Off" else "Music: On")
end

--- A press on the music icon. The only thing in this file that writes anything.
function TopbarController._onPressed(self, muted: boolean)
	if self._applying then
		return -- this is `_paint` moving the icon, not the player moving it
	end

	local MusicController = Shard.get("MusicController")
	if not MusicController then
		self.log:warn("MusicController is not up; the music button cannot do anything.")
		return
	end
	MusicController:setMuted(muted, true)
end

--[[ The radio button's caption: what this player's own car is playing, or the invitation to open the
	panel and find out. Drawn from `RadioController`, which reads it off the car, which is the same
	one-way arrangement `_paint` has with `MusicController` and for the same reason.

	IT NAMES THE STATION RATHER THAN THE ACTION, which is also what the music button's caption does
	on the rare build that has one. ]]
function TopbarController._paintRadio(self)
	local icon = self._radio
	if not icon then
		return
	end

	local RadioController = Shard.get("RadioController")
	local station = RadioController and RadioController:station()
	local found = RadioConfig.stationByKey(station)

	icon:setCaption(
		if found then "Radio: " .. found.Name
		elseif station == RadioConfig.CustomStation then "Radio: your track"
		else "Radio"
	)
end

--[[ The settings button's caption: which sky this player is on, or the plain word when they have
	not chosen. Drawn from `DayNightController` through the same state event the settings screen
	uses, so the strip and the screen cannot disagree.

	IT NAMES A SETTING RATHER THAN THE SCREEN, for the reason the radio's caption names a station:
	the caption is the only thing in the strip that can say anything, and "Settings" said twice is a
	sentence with nothing in it. On AUTO there is nothing to report, so it says the word. ]]
function TopbarController._paintSettings(self)
	local icon = self._settings
	if not icon then
		return
	end

	local controller = Shard.get("DayNightController")
	local preference = controller and controller:preference() or DayNightConfig.Preference.Auto

	icon:setCaption(
		if preference == DayNightConfig.Preference.Day then "Settings: day"
		elseif preference == DayNightConfig.Preference.Night then "Settings: night"
		else "Settings"
	)
end

--[[ Before the first `Icon.new()`, because TopbarPlus reads `highlightKey` once when its Gamepad
	feature starts and that is driven by the first icon being created. See the header: this is the
	whole DPad negotiation, and it is conditional so that switching console support off in
	`GamepadConfig` hands the key back rather than leaving it disabled for nobody's benefit.

	Its own job is one line; it is a function so that no build order can decide whether it ran. ]]
function TopbarController._settleGamepad(self)
	if self._settled then
		return
	end
	self._settled = true
	if GamepadConfig.Enabled then
		Icon.highlightKey = false
	end
end

--[[ One door. Both events do the same thing, because a TopbarPlus icon toggles its own selection on
	a press and the panel is what has to follow.

	THE PANEL IS ASKED WHETHER IT IS OPEN rather than told to toggle, because the icon and the panel
	can fall out of step in one direction that actually happens: the panel closes on its own (the X,
	B on a pad, a modal opening over it) and the icon does not know. Reading the panel's answer and
	acting on it means a press always does the thing the player can see is missing.

	AND THE ICON IS DRAWN FROM THE PANEL, off `openEvent`, which asking alone did not cover. A panel
	shut by its X left this icon SELECTED, and TopbarPlus deselects every other icon the moment one
	is selected (`deselectWhenOtherIconSelected`, on by default). So pressing SETTINGS deselected the
	radio icon, the deselect ran `press`, `press` found the panel shut, and opened it: the radio came
	up every time the player went for the gear. Kept in step, there is no stale selection for that
	auto-deselect to find, and when the panel really is open it closes it, which is right.

	`applying` is the same guard `_buildPageDoor` has, for the same reason: moving the icon fires its
	own events, and a repaint must not read as a press. ]]
function TopbarController._buildDoor(
	self,
	name: string,
	order: number,
	image: number,
	caption: string,
	panelName: string,
	openEvent: string
)
	self:_settleGamepad()

	local icon = Icon.new():setName(name):setOrder(order):setLeft():setImage(UIAssets.url(image)):setCaption(caption)
	local applying = false

	local function press()
		if applying then
			return -- the repaint below moving the icon, not the player moving it
		end
		local panel = Shard.get(panelName)
		if not panel then
			self.log:warn(string.format("%s is not up; the %s button cannot do anything.", panelName, name))
			return
		end
		if panel:isOpen() then
			panel:close()
		else
			panel:open()
		end
	end

	icon:bindEvent("selected", press)
	icon:bindEvent("deselected", press)

	Dispatcher:Subscribe(openEvent, function(open: boolean)
		applying = true
		if open then
			icon:select()
		else
			icon:deselect()
		end
		applying = false
	end)

	return icon
end

--[[ A door onto a UIController PAGE rather than onto a panel controller.

	`_buildDoor` above asks a Shard controller `isOpen`/`open`/`close`, which the radio and settings
	panels answer because each owns its own screen. A page does not: `UIController` owns all of them,
	and the thing that knows whether one is up is the page frame's own `Visible`.

	THE PRESS DOES NOT TOGGLE, IT ASKS AND THEN ACTS, for the same reason `_buildDoor` does: the icon
	and the page fall out of step in one direction that actually happens, which is the page closing
	without the icon hearing (its X, a rail button opening something else, `closeAllPages`). Reading
	`Visible` and acting on it means a press always does the thing the player can see is missing.

	`openPage` would in fact toggle on its own (it closes a page whose own button is pressed again),
	but relying on that would make this the one door in the file whose behaviour is a side effect of
	another module's convenience. Asking is one line and cannot drift.

	THE ICON IS THEN DRAWN FROM THE PAGE, never the other way round, which is the bargain the header
	sets out for the music button and the reason `_applying` exists. A page closed by its X has to
	deselect the icon, and that is a repaint rather than a press: without the guard it would call
	straight back into `openPage` and reopen the thing the player just shut. ]]
function TopbarController._buildPageDoor(self, name: string, order: number, image: number, caption: string, pageName: string)
	self:_settleGamepad()

	local icon = Icon.new():setName(name):setOrder(order):setLeft():setImage(UIAssets.url(image)):setCaption(caption)

	local function pageFrame(): Instance?
		local UIController = Shard.get("UIController")
		local page = UIController and UIController.pages and UIController.pages[pageName]
		return page and page.PageUI
	end

	local function press()
		if self._applyingPage then
			return -- this is the repaint below moving the icon, not the player moving it
		end
		local UIController = Shard.get("UIController")
		local frame = pageFrame()
		if not UIController or not frame then
			self.log:warn(string.format("The %s page is not up; the %s button cannot do anything.", pageName, name))
			return
		end
		if frame.Visible then
			UIController:closePage(pageName)
		else
			UIController:openPage(pageName)
		end
	end

	icon:bindEvent("selected", press)
	icon:bindEvent("deselected", press)

	-- Keep the icon on whatever the page actually is. Deferred once so the page exists to watch:
	-- `UIController` builds its pages in `start` too and the order of two Shards is not settled.
	task.defer(function()
		local frame = pageFrame()
		if not frame then
			return
		end
		local function repaint()
			self._applyingPage = true
			if frame.Visible then
				icon:select()
			else
				icon:deselect()
			end
			self._applyingPage = false
		end
		frame:GetPropertyChangedSignal("Visible"):Connect(repaint)
		repaint()
	end)

	return icon
end

--- The music fallback, which is a state rather than a door and therefore not `_buildDoor`.
function TopbarController._buildMusic(self)
	self:_settleGamepad()

	local icon = Icon.new()
		:setName("MusicToggle")
		:setOrder(MUSIC_ORDER)
		:setLeft()
		-- Deselected is the resting state and therefore the unmuted one: a plain note, music
		-- playing, nothing engaged.
		:setImage(UIAssets.url(UIAssets.Topbar.MusicOn), "deselected")
		:setImage(UIAssets.url(UIAssets.Topbar.MusicOff), "selected")
		:setCaption("Music: On")

	icon:bindEvent("selected", function()
		self:_onPressed(true)
	end)
	icon:bindEvent("deselected", function()
		self:_onPressed(false)
	end)

	self._icon = icon
end

--[[ SHOW UI: the one button left on the bar while the game's own UI is hidden.

	IT IS BUILT ALWAYS AND SHOWN ALMOST NEVER, which is the opposite of every other icon in this
	file. The three doors are conditional because a door onto something that cannot answer is worse
	than no door; this one has nothing to be conditional about, because the thing it answers to is
	the player having just hidden everything, and at that moment it is the only control on screen
	that is ours. Built up front rather than on the first hide so that the strip it appears in is
	already laid out and nothing has to be measured while the screen is empty.

	NO IMAGE ON A KEYBOARD, and the pad glyph on a pad. `InterfaceController` binds B to the same
	thing and deliberately draws no badge for it (the topbar's holder clips anything hanging below a
	widget), so the glyph lives here, as the icon's own image, where it is inside the chip and safe.

	A LABEL RATHER THAN A PICTURE, which no other icon in this strip has. The three doors are
	glyphs because a player meets them with the rest of the UI around them and can afford to learn
	what they are; this one is met on an empty screen by somebody who may not remember doing it, and
	two words that say what a press does is the whole point of it. ]]
function TopbarController._buildRestore(self)
	self:_settleGamepad()

	local icon = Icon.new()
		:setName(InterfaceConfig.RestoreIcon.Name)
		:setOrder(InterfaceConfig.RestoreIcon.Order)
		:setLeft()
		:setLabel(InterfaceConfig.Copy.Button)
		:setCaption(InterfaceConfig.Copy.ButtonCaption)
		--- A button, not a state: it deselects itself the instant it is pressed, so it never sits
		--- there looking engaged with nothing behind it to be engaged with.
		:oneClick(true)
		:setEnabled(false)

	--- `selected` only. `oneClick` above deselects on the same press, and answering both would run
	--- this twice; the second call is a no-op inside `setVisibility` but the wire is clearer.
	icon:bindEvent("selected", function()
		local controller = Shard.get("InterfaceController")
		if not controller then
			self.log:warn("InterfaceController is not up; the SHOW UI button cannot do anything.")
			return
		end
		controller:setVisibility(InterfaceConfig.Visibility.Shown)
	end)

	GamepadInput.observePreferred(function(isGamepad)
		icon:setImage(if isGamepad then GamepadInput.getButtonImage(InterfaceConfig.RestorePad) else "")
	end)

	self._restore = icon
end

--[[ Public (`InterfaceController`): leave SHOW UI up and take everything else in the strip down.

	PER ICON RATHER THAN `Icon.setTopbarEnabled`, which is what this used to be and cannot be any
	more: that switches the four container ScreenGuis off, and one of them is now carrying the way
	back. So the strip stays up and its contents are emptied around the one button.

	WHAT EACH ICON WAS IS RECORDED, for the same reason the ScreenGui sweep records what it found:
	an icon can be switched off for its own reasons (a menu closing, an overflow) and a restore that
	turned the whole strip on would be deciding something this file has no business deciding.

	The restore reads the CURRENT register rather than the saved table, so an icon destroyed while
	the UI was away is simply dropped instead of being written to after its widget has gone. ]]
function TopbarController.setRestoreOnly(self, only: boolean)
	local restore = self._restore
	if not restore then
		return
	end
	self._restoreOnly = only

	if only then
		self._stripWas = {}
		for _, icon in Icon.getIcons() do
			if icon ~= restore then
				self._stripWas[icon] = icon.isEnabled
				icon:setEnabled(false)
			end
		end
		restore:setEnabled(true)
		return
	end

	restore:setEnabled(false)
	for _, icon in Icon.getIcons() do
		local was = self._stripWas[icon]
		if was ~= nil then
			icon:setEnabled(was)
		end
	end
	self._stripWas = {}
end

--[[ Settings follows the grid's visibility rule; sound and rewards stay out of a run (2026-10-12).
	The fallback music icon follows the radio icon, so a build without radio gets the same clear HUD.

	WHILE SHOW UI HOLDS THE STRIP, THE ANSWER GOES INTO `_stripWas` AND NOT ONTO THE ICON. A run
	starting takes the UI back (`InterfaceController`), and the two `RaceStart` handlers run in no
	settled order.
	Written onto the icon, this would be undone by that restore if the restore ran second, and would
	light a chip in an emptied strip if it ran first. Written into the record, the restore applies it. ]]
function TopbarController._setRacing(self, racing: boolean)
	self._racing = racing
	-- Keep sound and rewards in the lobby; settings retains its existing availability (2026-10-12).
	for _, entry in {
		{ self._radio, not racing },
		{ self._icon, not racing },
		{ self._daily, not racing },
		{ self._settings, not self._raceOnly or racing },
	} do
		local icon, enabled = entry[1], entry[2]
		if icon then
			if self._restoreOnly then
				self._stripWas[icon] = enabled
			else
				icon:setEnabled(enabled)
			end
		end
	end
end

TopbarController:withRemoteEvents({
	{
		RaceStart = function()
			TopbarController:_setRacing(true)
		end,
		RaceEnd = function()
			TopbarController:_setRacing(false)
		end,
	},
})

TopbarController:withLifecycle({
	init = function(self)
		self._icon = nil :: any
		self._radio = nil :: any
		self._settings = nil :: any
		self._shop = nil :: any
		self._restore = nil :: any
		--- What each other icon's `isEnabled` was when SHOW UI took the strip. See `setRestoreOnly`.
		self._stripWas = {} :: { [any]: boolean }
		--- True while SHOW UI holds the strip. See `setRestoreOnly` and `_setRacing`.
		self._restoreOnly = false
		--- Settings is race-only when its new-UI grid cell exists. See `_setRacing`.
		self._raceOnly = false
		self._racing = false
		self._applying = false
		self._applyingPage = false
		self._settled = false
	end,

	start = function(self)
		--[[ EACH BUTTON ANSWERS TO ITS OWN SWITCH AND NOTHING ELSE. Written as independent blocks
			rather than one early return, because they are features that happen to share a strip:
			switching the soundtrack off must not take the radio button with it, and an unsynced pass
			must not take settings with it. An early return at the top of this function would do
			both. ]]

		--[[ THE RADIO BUTTON IS THERE WHETHER OR NOT THE PLAYER OWNS THE PASS, and that is a
			monetisation decision rather than an oversight: the panel is where the pass is sold, so
			hiding the way into it until they already own it would leave nothing anywhere in the game
			that says the radio exists. What IS hidden is a feature that has been switched off or
			never synced, which `sellable()` covers both of, and a button onto a panel that can only
			refuse is worse than no button. ]]
		local radioReachable = UIVisibility.radio()
		if radioReachable then
			self._radio = self:_buildDoor(
				"RadioToggle",
				RADIO_ORDER,
				UIAssets.Topbar.Radio,
				"Radio",
				"RadioPanelController",
				RadioConfig.PanelEvent
			)
			self:_paintRadio()
			Dispatcher:Subscribe(RadioConfig.StateEvent, function()
				self:_paintRadio()
			end)
		end

		--[[ Settings needs a screen with something on it. `hasRows` is that check and it is the
			reason a build with the day and night cycle switched off gets no gear rather than an
			empty panel: same rule as the radio's, one line up. ]]
		if UIVisibility.settings() then
			--- A PAGE DOOR, not a panel one: the settings screen is authored in `MainUI.Pages` and
			--- owned by `UIController` like every other page. See `_buildPageDoor` above.
			self._settings = self:_buildPageDoor(
				"SettingsToggle",
				SETTINGS_ORDER,
				UIAssets.Topbar.Settings,
				"Settings",
				SettingsConfig.PageName
			)
			self:_paintSettings()
			Dispatcher:Subscribe(DayNightConfig.StateEvent, function()
				self:_paintSettings()
			end)
		end

		-- Settings only needs its race copy when the lobby already has a grid cell for it.
		self._raceOnly = UIRoot.isNewUI()
			and RaceConfig.HideRailDuringRace == true
			and NewUIConfig.TopbarRadioSettings ~= true
		self:_setRacing(self._racing)

		--[[ THE SHOP, and it is there only if there is something in it. Same rule as the two doors
			above, and the rule itself is now `UIVisibility.shop()`, because the new UI asks it too.

			...AND ONLY WHILE THE OLD UI IS THE ONE IN PLAY. This is the door the stopgap note at the
			top of the file was waiting on: the menu HUD button it describes is built, it is the kit
			grid's Shop cell, and `Components/HudRules` gives it this same rule. So with the new UI on
			there is a shop button and it is not here, and the topbar is left holding exactly what a
			driver reaches for mid-run (and, since 2026-09-16, holding it only mid-run). See
			`docs/NewUI-Migration-Plan.md`, "The new HUD": a robux shop is not a mid-race errand, which
			is the whole argument for which layer it belongs to. ]]
		if UIVisibility.shop() and not UIRoot.isNewUI() then
			self._shop = self:_buildPageDoor("ShopToggle", SHOP_ORDER, UIAssets.Topbar.Shop, "Shop", "Shop")
		end

		--[[ THE DAILY REWARD (2026-10-06, `DailyRewardConfig.Topbar`), a page door like the two above,
			wearing the shop's gift — the BARE glyph (`UIAssets.GiftGlyph`), not the framed button, since
			the topbar draws its own plate. A present is what a daily reward is, and it is art the player
			already reads as "something free". New UI only, because the page is a
			Cartoony Kit page (`BuildDailyRewardsV2`); a place where that command has not been run gets a
			button that warns once and opens nothing. ]]
		local daily = DailyRewardConfig.Topbar
		if DailyRewardConfig.Enabled and daily.Enabled and UIRoot.isNewUI() then
			self._daily = self:_buildPageDoor("DailyRewardToggle", daily.Order, daily.Icon or UIAssets.GiftGlyph, daily.Caption, DailyRewardConfig.PageName)
		end

		--[[ ...and the mute, ONLY when the radio panel it now lives on cannot be reached. The header
			has the whole of this. No music, no mute button either: the switch in `MusicConfig` is
			meant to take the whole feature out, and a mute button on a game with nothing to mute is
			worse than no button. ]]
		if UIVisibility.music() then
			self:_buildMusic()

			--[[ Draw it from the controller now and on every change. The `now` matters as much as
				the subscription: a player whose saved answer arrived before this controller started
				would otherwise have a muted game and an un-muted-looking button until they pressed
				it. ]]
			local MusicController = Shard.get("MusicController")
			self:_paint(MusicController ~= nil and MusicController:isMuted())

			Dispatcher:Subscribe(MusicConfig.StateEvent, function(muted: boolean)
				self:_paint(muted == true)
			end)
		end

		--[[ ...and SHOW UI, built last and hidden, so that everything above it is already in the
			strip when `setRestoreOnly` first walks it. Its own switch is the hide feature's, which
			is the same rule the three doors follow: no feature, no button. ]]
		if InterfaceConfig.Enabled then
			self:_buildRestore()
		end
		self:_setRacing(self._racing)
	end,
})

return TopbarController
