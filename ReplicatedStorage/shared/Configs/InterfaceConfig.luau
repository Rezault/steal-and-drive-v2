--[[
	InterfaceConfig
	---------------
	PUTTING THE GAME'S OWN UI AWAY, so the lobby can be looked at with nothing on top of it. Read by
	`InterfaceController`, which owns the hiding, and by `UIController/Pages/Settings`, which draws the row
	that turns it on.

	It is the second setting on that screen and it is arranged exactly like the first: this file owns
	the words, the answers and the default, and the screen owns only its own chrome. Adding this row
	was an edit here plus one call in the controller, which is what `SettingsConfig`'s header says a
	second setting should cost.

	=== WHY IT IS NOT SAVED ====================================================================

	The time of day rides in the player's profile and this deliberately does not, which is the one
	place the two settings on that screen disagree.

	A saved sky is a preference. A saved BLANK SCREEN is a support ticket: the player who hid the UI
	to photograph their car, left, and came back a week later has forgotten they did it, and what
	they are looking at is a game with no buttons in it. There is no recovery path that does not
	depend on them remembering a thing they did once, and "the game is broken" is what it looks like
	from the inside.

	So this lasts as long as the session and starts SHOWN every time. Nothing here needs a server
	side at all, which is also why there is no remote and no profile key below.

	=== THE WAY BACK IS PART OF THE FEATURE ====================================================

	Hiding every ScreenGui includes the topbar, and the topbar is the door the settings screen is
	behind. Something has to survive or the setting is a trap.

	IT IS A TOPBAR BUTTON RATHER THAN A PILL IN THE CORNER, and the corner is the whole argument.
	The Roblox menu button in the top left cannot be switched off by a game, so that corner is
	already in every screenshot anybody takes. A SHOW UI chip beside it costs the photograph nothing
	and reads as Roblox's own chrome, which is exactly what the floating pill this replaced could
	never manage: solid it sat in the shot, and faded to the point where it did not, players hunted
	for it on a phone.

	So the strip stays up carrying one button. `Keep` below is the topbar's four ScreenGuis,
	`TopbarController` builds the chip and owns it like every other icon in that strip, and while
	the UI is away it switches every OTHER icon off.

	There are two more ways back and neither replaces the chip: `RestoreKey` on a keyboard and
	`RestorePad` on a controller. A phone has neither, which is why the chip is the one that is
	always there.

	=== NOTHING BUT THE SETTINGS ROW CAN HIDE ==================================================

	All three ways back are ONE WAY. None of them hides, and that is the point rather than an
	omission: the only control that puts the UI away is the row on the settings screen, which is a
	place a player has to deliberately go.

	`RestoreKey` used to toggle, and the argument for it was a good one, so here is what was given
	up. A player photographing their car could press one key twice between shots instead of walking
	back through the settings screen each time. What that bought a handful of people, it charged to
	everybody else: H is one key away from nothing in particular, and a player who leans on it by
	accident is looking at a game with no buttons in it, having never opened the setting that
	explains what just happened. They do not know the word "interface", they did not read a caption
	they had no reason to look at, and what they see is a broken game.

	The photographer loses a shortcut. The player who never wanted this loses nothing, because they
	can no longer fall into it. That is the trade, and it is not close.

	=== A RUN TAKES IT BACK ====================================================================

	`InterfaceController` forces this to SHOWN when a race starts, and the reason is the same one
	that closes the settings panel on `RaceStart`: driving with no speedometer, no health and no
	steering controls is not a photograph, it is a broken run. Photo mode is a lobby thing.
]]

local InterfaceConfig = {}

--[[ Master switch. Off = no row on the settings screen and `InterfaceController` binds nothing,
	builds no chip and never touches a ScreenGui. The whole feature is cosmetic and reversible, so
	this is here to match the pattern the other settings follow rather than because it is expected
	to be pulled. ]]
InterfaceConfig.Enabled = true

--[[ The two answers, as stored keys rather than booleans.

	A BOOLEAN WOULD DO AND IS THE WRONG SHAPE. The settings screen walks a list of options and builds
	one pill per entry, which is what let this row be written without touching its layout code, and a
	list needs keys. It also leaves room for a third answer that is already easy to imagine (hide the
	HUD but keep the topbar), which a boolean would have to be rewritten to hold. ]]
InterfaceConfig.Visibility = {
	Shown = "shown",
	Hidden = "hidden",
}

--- Where every session starts. See the header for why this is not read from anywhere.
InterfaceConfig.Default = InterfaceConfig.Visibility.Shown

--[[ Raised on the player's `PlayerGui` while the UI is away.

	IT EXISTS TO BE READ BY THINGS THIS FILE DOES NOT KNOW ABOUT. Anything that is about to put
	something on screen can ask whether the player has asked for quiet, the same way
	`GamepadConfig.ModalAttribute` lets the rail know a panel is up. Nothing reads it today. ]]
InterfaceConfig.Attribute = "InterfaceHidden"

--- Published on the client whenever the answer moves, so the settings screen repaints from the
--- controller rather than from its own copy. Same contract as `DayNightConfig.StateEvent`.
InterfaceConfig.StateEvent = "InterfaceVisibilityState"

--[[ ScreenGuis that are never hidden, by name.

	FOUR ENTRIES AND THEY ARE ALL ONE THING: the topbar, which carries the way back. TopbarPlus
	spreads its strip over four ScreenGuis (a standard and a centred one, each with a clipped
	sibling for notices and dropdowns that hang outside a widget), and skipping them by name is
	cheaper and far more obvious than hiding everything and re-enabling some of it afterwards.

	The strip surviving is not the same as the strip being FULL. `TopbarController` switches every
	icon except SHOW UI off while this is on, so what is left up is one button on an otherwise empty
	bar. See its `setRestoreOnly`.

	Anything added here has to be something a player is content to see in a screenshot, because that
	is what this list means. It is not the place for "important" UI: a race forces the whole setting
	back rather than carving out exceptions, for the reason the header gives. ]]
InterfaceConfig.Keep = {
	TopbarStandard = true,
	TopbarStandardClipped = true,
	TopbarCentered = true,
	TopbarCenteredClipped = true,
}

--[[ The chip `TopbarController` builds, described here rather than there because the rest of this
	feature is described here.

	ORDER 0, so it lands to the left of the radio, settings and shop icons (1, 2 and 3). Nothing
	else in the strip is up at the same time, so the number is not deciding a layout: it is saying
	that if one ever is, the way back is the leftmost thing on the bar and not somewhere in a row. ]]
InterfaceConfig.RestoreIcon = {
	Name = "ShowUI",
	Order = 0,
}

--[[ The keyboard's way back. H for hide, which is the one this kind of control is always on, and
	free in this game: every other letter binding is taken (`E` to mount, `S`, `Q`, `W`, `N`, `O`).

	IT ONLY EVER UN-HIDES. Pressing it with the UI up does nothing at all, which is the whole of the
	section above and the reason this is called `RestoreKey` rather than `ToggleKey`. It is the same
	shape `RestorePad` has always had.

	It is still worth binding for a key that cannot hide, because it is the fast way back for the
	one player who does not want to aim at anything: `ButtonCaption` puts the letter on the chip, so
	the moment it is useful is also the moment it is advertised. ]]
InterfaceConfig.RestoreKey = Enum.KeyCode.H

--[[ ...and the controller's, bound only while the UI is away.

	B, which is BACK on every console this ships to, and free at the moment it is bound: every other
	claim on B in this game belongs to a panel, and no panel is reachable with the UI hidden. It is
	bound at a priority above all of them so that a modal which somehow survived cannot eat the way
	out. ]]
InterfaceConfig.RestorePad = Enum.KeyCode.ButtonB

--- Every word this feature puts on screen. See `DayNightConfig.Copy` for why a feature owns its own
--- copy and the screen that shows it owns none.
InterfaceConfig.Copy = {
	--[[ NAMED FOR THE THING THE PLAYER CAME LOOKING FOR. It read "Interface" and that is the word a
		developer uses: somebody scanning this screen for a way to take the HUD off a screenshot has
		no reason to open a row called that, and every reason to open one called this.

		It breaks the shape of the row above it, which is a noun ("Time of day") with a value beside
		it, and the options below are what pay for that: an instruction needs a switch, not a state,
		so they read OFF and ON rather than SHOWN and HIDDEN. "Hide UI: Shown" is a sentence that
		argues with itself. ]]
	Row = "Hide UI",

	--- The line under the row title: what the setting is doing, in a sentence. The hidden one names
	--- the key, because that is the moment a keyboard player wants to know it.
	OnShown = "Everything is on screen",
	OnHidden = "Press H or the button in the topbar to bring it back",

	--- On the chip itself. TWO SHORT WORDS, because the chip is as wide as its own label and a
	--- sentence there would be a bar across the top of the screenshot this feature exists to take.
	Button = "Show UI",

	--- Under the chip on hover, and on a gamepad when the highlight lands on it. It names the key
	--- rather than the state, which is the opposite of what the radio and settings captions do and
	--- is right here: with the UI away there is no state for a caption to report, and the key is
	--- the thing a player who found this chip once would rather not have to find it again for.
	ButtonCaption = "Show UI (H)",

	--- The answers, as the ROW's question rather than the screen's state: ON hides. The keys are
	--- untouched, so nothing downstream of this knows the words changed.
	Options = {
		{ Key = InterfaceConfig.Visibility.Shown, Name = "Off" },
		{ Key = InterfaceConfig.Visibility.Hidden, Name = "On" },
	},
}

-- === Reading it =============================================================

--- Whether `value` is one of the two answers.
function InterfaceConfig.isVisibility(value: unknown): boolean
	return value == InterfaceConfig.Visibility.Shown or value == InterfaceConfig.Visibility.Hidden
end

--- `value` as one of the two, with everything else folded into the default. The one place a wired
--- answer becomes something the rest of the code can switch on, and the reason nothing else has to
--- guard against a key from a future build.
function InterfaceConfig.resolve(value: unknown): string
	if InterfaceConfig.isVisibility(value) then
		return value :: string
	end
	return InterfaceConfig.Default
end

--- The sentence for the row's status line. One place, so the screen never switches on a key itself.
function InterfaceConfig.statusFor(visibility: unknown): string
	if InterfaceConfig.resolve(visibility) == InterfaceConfig.Visibility.Hidden then
		return InterfaceConfig.Copy.OnHidden
	end
	return InterfaceConfig.Copy.OnShown
end

return InterfaceConfig
