--[[
	GamepadConfig
	-------------
	Console support: what the buttons on a controller do OUTSIDE the car, and how the game says so.

	THE DRIVING WAS ALREADY DONE and none of it is here. The stock CarBones `Keymap` maps
	Thumbstick1 to the steering rack, R2 to the throttle, L2 to the brake and ButtonY to the exit,
	and our own race verbs took their gamepad half at the time they were written — see
	`StealConfig.BailKeys` (ButtonA), `StealConfig.Prompt.Keys` (ButtonX) and `DriveConfig.ExitKeys`
	(ButtonY). A controller could always DRIVE this game. What it could not do was press anything on
	the screen, because every button in the UI was wired to a mouse.

	SO THIS FILE IS ABOUT THE CURSOR WE DON'T HAVE. Roblox's answer to that is a SELECTION: exactly
	one GuiObject is `GuiService.SelectedObject`, the DPad moves it between neighbours, and A
	activates it. Three decisions follow from that, and they are the three numbers below.

	  1. WHILE YOU ARE WALKING, NOTHING IS SELECTED. It has to be that way: a live selection eats
	     ButtonA, and ButtonA is jump. So the highlight is something you ASK for (`FocusKey`), and
	     `BackKey` gives it back.

	  2. THE ENGINE WOULD OTHERWISE GUESS. `GuiService.AutoSelectGuiEnabled` is true by default,
	     which means a DPad press with nothing selected makes the engine pick a button for you —
	     whichever one it likes the geometry of, including things that are not really buttons (the
	     cash counter is an ImageButton that does nothing). `Enabled` here switches that off and
	     `FocusKey` picks deliberately instead.

	  3. B IS BACK, EVERYWHERE. Out of a page, then out of the UI. Nothing in this game needs B for
	     anything else on foot, and a player who presses it twice ends up back where they started
	     rather than stuck in a menu with no mouse.

	`Enabled = false` reverts all of it: no focus key, no seeding, no glyphs, and the engine's own
	auto-select goes back to being in charge. The mouse and touch paths are untouched either way —
	nothing in this feature replaces a pointer binding, it only adds a second way in.
]]

local GamepadConfig = {}

-- The master A/B. Off = the game as it was before console support, engine defaults included.
GamepadConfig.Enabled = true

--[[ ASKING FOR THE HIGHLIGHT — THE DPAD OPENS THE RAIL.

	Pressed with nothing selected, any of these puts the highlight on the top of the left-hand rail;
	from there the same DPad moves it, and the engine does the moving. All four directions rather
	than just up, because the first press is "give me the menu" and no direction is wrong for that.

	The DPad and not a face button: those are all spoken for on foot (A jumps, B is our back, X is
	every proximity prompt in the lot, Y is the shortcut below) and this is the idiom besides — it
	is the key TopbarPlus reaches its icons with, so a player who has met one Roblox console game
	has already met this. They are only ever BOUND while nothing is selected — see
	`Components/GamepadNav` — so they can never steal a press from the engine's own navigation.

	`FocusGlyph` is the one that gets drawn. There is no KeyCode meaning "the whole DPad", so this
	is the badge's stand-in for all four. ]]
GamepadConfig.FocusKeys = {
	Enum.KeyCode.DPadUp,
	Enum.KeyCode.DPadDown,
	Enum.KeyCode.DPadLeft,
	Enum.KeyCode.DPadRight,
}
GamepadConfig.FocusGlyph = Enum.KeyCode.DPadUp

-- Back. Closes the page that is open, or drops the highlight and hands you back to walking.
GamepadConfig.BackKey = Enum.KeyCode.ButtonB

--[[ SHORTCUTS: A BUTTON THAT PRESSES ITSELF, declared where every other thing about a button is
	declared — as an attribute in the Explorer, not as a list in here.

	Tag a HUD button `UIButton`, give it `GamepadKey = "ButtonY"`, and that button answers to Y
	without the highlight ever having to be driven onto it. `MainUI.HUD.Play` carries it today, so
	PLAY is one press from walking around: Y opens the WORLDS screen with the highlight already on
	a card. Same bargain as `Page` and `Action` — the place file says which button, the code says
	what a press means (`UIController/ButtonPress`).

	WHY IT IS ONLY EVER THE HUD. A shortcut is a global keybind wearing a button's clothes, and the
	rules about when one may be live — not during a race, not under a modal screen, not while its
	button is hidden — are `Components/GamepadNav`'s, which only watches the HUD. A `GamepadKey` on
	a button inside a page is ignored rather than half-honoured.

	Y IS FREE ON FOOT AND NOT IN THE CAR, which is the whole reason the "not during a race" rule
	exists rather than being belt-and-braces: `DriveConfig.ExitKeys` gives Y to the driver's seat,
	and the stock kit's own scripts bind it too (they sit disabled until you are seated, which is
	why standing next to a car is not a conflict).

	THE NEW UI'S PLAY IS ON X, NOT Y (`MainUIV2.HUD.Play`, `BuildHudV2`'s `PLAY_GAMEPAD_KEY`), so it
	stays one press away from inside a lobby car. X is every proximity prompt's key too, and that
	is not a clash: a prompt in range takes its key ahead of a binding of ours (measured 2026-10-15
	with a sinking binding at High), so X at a podium is the podium and X anywhere else is PLAY. ]]
GamepadConfig.ShortcutAttribute = "GamepadKey"

--[[ A LOBBY BUTTON THAT IS NOT IN THE HUD, BUT SHOULD BE IN ITS CHAIN.

	`Components/GamepadNav` walks `HUD` for the buttons the DPad steps between. A few lobby buttons
	are drawn in ScreenGuis of their own because they need their own `DisplayOrder` (the BACK TO BASE
	pill, the random car's offer card), so that walk never found them and a controller could not press
	them at all. Tag such a button with this, after its gui is parented, and it joins the HUD's rows by
	where it is drawn. Its press is its own `Activated`, which an A on the highlight fires. ]]
GamepadConfig.HudMemberTag = "GamepadHudMember"

--[[ The page buttons that mean "shut this", which the seeder must not treat as a destination.

	A page's X is almost always its topmost button, so a naive "select the first thing" starts every
	screen with the highlight on the way out of it. The seeder therefore prefers anything else and
	settles for one of these only when a page genuinely has nothing else to press yet (a Cars
	Inventory whose cards have not landed). `Done` is here because the imported dealership panel
	names its confirm button that.

	`CloseBtn` IS THE KIT'S X (`KitPage`'s own first choice), and every page on the new UI has one.
	Without it here (until 2026-10-15) every V2 page opened with the highlight on its X, so the A that
	was meant for the first card shut the page, and the B glyph had no X to sit on. ]]
GamepadConfig.CloseButtonNames = { "CloseBtn", "Close", "Done" }

--[[ "SOMETHING ELSE OWNS THE CONTROLLER RIGHT NOW", written as an attribute on the PlayerGui.

	A screen that binds its own face buttons — the revive question is the first, and there will be
	more — has to be able to say so, or the UI's own focus key would let the player pull the
	highlight onto the HUD behind it and hand B to two owners at once. Whoever puts such a screen up
	sets this true and clears it on the way down; `Components/GamepadNav` then refuses to focus and
	drops any highlight that is already out.

	An attribute rather than a call because it is the only shape that does not make every modal
	screen depend on the navigation component, or the component keep a list of screens it has never
	heard of. ]]
GamepadConfig.ModalAttribute = "GamepadModal"

--[[ How many frames the seeder keeps trying for.

	It has to keep trying at all because pages fill in AFTER they open — the dealership's cards are
	cloned in over a server round trip, and a page seeded on the frame it turned visible has nothing
	but its X to choose from. So the seeder re-picks every frame across this window and upgrades its
	choice the moment a real row shows up, stopping early once it has landed on something that is
	not a close button, or the instant the player moves the highlight themselves.

	20 frames is about a third of a second, which covers a card list that arrives with the page and
	gives up long before a player would notice it trying. ]]
GamepadConfig.SeedFrames = 20

--[[ Glyph badges: the little controller buttons drawn next to the thing they press.

	`Size` is in REFERENCE pixels at 1080p and normalised to the live viewport (see
	`Modules/GamepadInput`), so one number reads the same on a phone-sized window and a TV. The
	palette is the UI kit's: the navy card face behind white line-art, which is what the stock
	glyphs are drawn for. ]]
GamepadConfig.Icon = {
	Size = 36,
	Background = Color3.fromRGB(40, 51, 75), -- #28334B, the kit's card face
	Stroke = Color3.fromRGB(12, 16, 26),
	StrokeThickness = 2,
}

return GamepadConfig
