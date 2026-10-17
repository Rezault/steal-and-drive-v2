--[[
	GamepadNav component  (client)
	------------------------------
	The cursor a controller doesn't have.

	Roblox's answer to "no mouse" is a SELECTION: one GuiObject is `GuiService.SelectedObject`, the
	DPad (and the left stick) move it between neighbours, and A activates it. `Components/Button`
	already teaches every tagged button to react to that. This file decides WHERE the highlight is
	and WHEN there is one at all, which is the part with all the judgement in it.

	THREE RULES, and everything below is one of them.

	1. WHILE YOU ARE WALKING, NOTHING IS SELECTED. It cannot be otherwise: a live selection eats
	   ButtonA, and ButtonA is jump — and the engine drives selection with the LEFT STICK as well as
	   the DPad, which is the stick the car steers with. So the highlight is something you ask for
	   (`GamepadConfig.FocusKeys`, the DPad) and something you give back (`BackKey`, B). It is also
	   why `GuiService.AutoSelectGuiEnabled` is switched off: left on, the engine grabs a button of
	   its own choosing the first time a DPad is pressed, and its choice is a guess.

	2. FOCUS MEANS "GIVE ME THE HIGHLIGHT", and where it lands depends on what is on screen: into
	   the open page if there is one, onto the top of the rail if there isn't. One key, no modes to
	   explain.

	3. B IS BACK, AND IT IS THE ONLY WAY OUT OF A PAGE. Out of the page first, then out of the UI. A
	   player who presses it twice is back to walking around, which is the property that makes the
	   whole thing safe to hand to someone with no mouse to bail themselves out with — and an open
	   page traps the highlight inside itself (`trapSelection`) so the DPad cannot wander out
	   through the panel onto the rail behind it.

	AND ONE BUTTON SKIPS THE HIGHLIGHT ENTIRELY. The rail is a menu you go and open; PLAY is the
	thing you came to do, and making a console player drive a cursor onto it first is a step a
	console game would not ask for. So a HUD button may carry a `GamepadKey` attribute
	(`GamepadConfig.ShortcutAttribute`) and answer to that button outright — Y opens the WORLDS
	screen from walking around, with the highlight already on a card when it arrives. The shortcut
	presses the button through the same `ButtonPress` the mouse goes through, so it cannot drift
	from what clicking it does, and it stands down under exactly the same conditions the focus key
	does plus one more: its own button being hidden. That last one is what takes Y away for the
	length of a race, when it belongs to the driver's seat.

	WHAT IT REFUSES TO DO. While the driving HUD is up — the whole run, from the entry fade to the
	wreck — the focus key does nothing and any live selection is dropped. That is rule 1 again, in
	the one place it actually bites: the left stick belongs to the car, and a highlight on screen
	would have it steering and menu-browsing at the same time.

	The same refusal covers a MODAL screen, flagged by `GamepadConfig.ModalAttribute`. The revive
	question is the one that raises it today: it falls outside the racing window on purpose
	(`DrivingHudController` hides the HUD on `RaceWrecked`) because it is a question the player has
	seconds to answer, and it binds A and B for itself — so this steps off both.

	THE PAGES ARE WATCHED, NOT HOOKED. Nothing in `UIController` calls into this: it watches
	`Visible` on the frames under `MainUI.Pages`, so a page that defines its own `Open`/`Close` and
	never goes near the shared tween is handled by the same code as every other one. The page NAME
	is the frame's name, which is the same assumption `UIController.openPage` already makes when it
	compares `PageUI.Name` against its module keys.

	SEEDING IS A LOOP, NOT A LINE, and `GamepadConfig.SeedFrames` says why: pages fill in after they
	open, so the first frame of a dealership has nothing to select but its own X.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ButtonPress = require(script.Parent.Parent.ButtonPress)
local UIControllerTypes = require(script.Parent.Parent.UIControllerTypes)
local DriveConfig = require(ReplicatedStorage.shared.Configs.DriveConfig)
local GamepadConfig = require(ReplicatedStorage.shared.Configs.GamepadConfig)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local FOCUS_ACTION = "UIGamepadFocus"
local BACK_ACTION = "UIGamepadBack"
-- One action per shortcut button, named after the button that owns it.
local SHORTCUT_PREFIX = "UIGamepadShortcut_"

-- Seconds to wait for the authored UI. It is a StarterGui clone: there on the first frame or not
-- coming at all, so this is only generous enough to survive a slow join.
local GUI_WAIT = 10

return function(UIController: UIControllerTypes.UIController)
	if not GamepadConfig.Enabled then
		return
	end

	task.spawn(function()
		local playerGui = UIController.PlayerGui
		local mainUI = UIRoot.wait(playerGui, GUI_WAIT)
		if not mainUI then
			warn(string.format("[GamepadNav] No %s in this place; the UI is mouse-and-touch only.", UIRoot.name()))
			return
		end
		local hud = mainUI:WaitForChild("HUD", GUI_WAIT)
		local pages = mainUI:WaitForChild("Pages", GUI_WAIT)
		if not (hud and pages) then
			warn(string.format("[GamepadNav] %s has no HUD/Pages; nothing to navigate.", UIRoot.name()))
			return
		end

		-- Ours to place, from here on. See rule 1 in the header.
		GuiService.AutoSelectGuiEnabled = false

		-- === What counts as a race ==========================================
		--[[ The driving HUD's own switch, read rather than a second race flag of our own. It is
			already exactly the window we care about (up for the run, down for the wreck and the
			revive question), it costs no remote, and a place that has not imported the HUD yet
			simply never refuses — which is the right failure, since it has no race to protect. ]]
		local drivingHud = playerGui:FindFirstChild("DrivingHud")
		local function racing(): boolean
			return drivingHud ~= nil and drivingHud.Enabled
		end

		-- ...and a screen that has taken the face buttons for itself. See
		-- `GamepadConfig.ModalAttribute`: the revive question is the one that does this today.
		local function modal(): boolean
			return playerGui:GetAttribute(GamepadConfig.ModalAttribute) == true
		end

		--[[ === …AND A SEAT, WHICH OWNS ITS OWN KEYS ==========================

			A SHORTCUT MUST NEVER FIGHT THE CAR FOR A BUTTON. `DriveConfig.ExitKeys` is the canonical
			list of the keys the driver's seat owns — E and ButtonY, mirroring the stock kit's
			`Keymap.EnterVehicleKeyboard` / `EnterVehicleGamepad` — and while the player is sitting in
			anything, those keys are the seat's and not the HUD's.

			THIS IS THE RULE THE "HIDDEN" CONDITION BELOW WAS REACHING FOR AND MISSED. That note says
			the Play button going off screen for a race is what hands Y back to the driver's seat, and
			it is right about the race and wrong about the reason: the seat owns Y whenever you are IN
			one, and the lobby car is a seat with the whole HUD still up. Reported from the playtest as
			"can't exit the car — exit is the same button as Play", and it measured exactly that way —
			`UIGamepadShortcut_...HUD.Play` on ButtonY at priority 3000, over the stock
			`VehicleChassisExitVehicle` on ButtonY at 2000, both live while parked in the lobby.

			KEYED RATHER THAN BLANKET, so this costs nothing it does not have to. A shortcut on a
			button the seat has no claim to keeps working while seated, which is what lets Play sit on
			ButtonX and still be one press from inside your own car. Only a shortcut that would
			double-book a seat key stands down. ]]
		local seatKeys: { [Enum.KeyCode]: true } = {}
		for _, key in DriveConfig.ExitKeys do
			seatKeys[key] = true
		end

		local function seated(): boolean
			local character = Players.LocalPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			return humanoid ~= nil and humanoid.SeatPart ~= nil
		end

		-- === The HUD's selection chain ======================================
		--[[ Deterministic neighbours, rather than the engine's geometry.

			Automatic navigation picks whatever is nearest in the pressed direction, which across
			the gap between a left-hand rail and a bottom-centre Play button is a coin toss — and it
			happily lands on the cash pill, an ImageButton that is a readout with nothing behind it.
			So the members are sorted by where they actually are on screen and wired up/down to each
			other, and anything in the HUD that is not a tagged `UIButton` is taken out of the
			running entirely. The tag is what makes something pressable in this UI; this is the same
			statement read from the other end. ]]
		local isShown -- forward declared: defined with the other visibility questions below

		local function railButtons(): { GuiButton }
			local found: { GuiButton } = {}
			for _, descendant in hud:GetDescendants() do
				if descendant:IsA("GuiButton") then
					if CollectionService:HasTag(descendant, "UIButton") then
						if descendant.Visible then
							table.insert(found, descendant)
						end
					elseif descendant.Selectable then
						descendant.Selectable = false -- the cash pill and anything else like it
					end
				end
			end
			--[[ ...AND THE LOBBY BUTTONS THAT LIVE IN SCREENS OF THEIR OWN. The BACK TO BASE pill and
				the random car's offer card are each their own ScreenGui (for their DisplayOrder), so
				walking the HUD never finds them, and without this a controller had no way to press
				either. They opt in with `GamepadConfig.HudMemberTag` and join the rows by where they
				are drawn, exactly like a HUD button. Shown-ness is the whole chain up to their own
				ScreenGui, because they hide by a holder or by the gui, never by the button. ]]
			for _, member in CollectionService:GetTagged(GamepadConfig.HudMemberTag) do
				if member:IsA("GuiButton") and member:IsDescendantOf(playerGui) and isShown(member) then
					table.insert(found, member)
				end
			end
			table.sort(found, function(a, b)
				return a.AbsolutePosition.Y < b.AbsolutePosition.Y
			end)
			return found
		end

		--[[ Group the HUD's buttons into the rows they are actually drawn in.

			THE HUD IS NOT A COLUMN ANY MORE. The kit's side grid is two buttons wide, so a chain
			sorted by Y alone would zigzag across it: down from the left button would land on its own
			right-hand neighbour, and the order of two buttons at the SAME height is whatever the sort
			happened to do with them. A grid has to be read as a grid.

			SAME HEIGHT MEANS OVERLAPPING VERTICALLY, measured on centres against half the shorter
			button, rather than an exact Y: the grid's cells share a Y to the pixel, but the Play
			button and the cash pill's `+` do not, and a rule that needs them to would put each on a
			row of its own the moment a layout nudged one by a pixel. ]]
		local function centreY(button: GuiObject): number
			return button.AbsolutePosition.Y + button.AbsoluteSize.Y * 0.5
		end

		--- Do two buttons share any horizontal span? Then one is above the other, not beside it.
		local function overlapX(a: GuiObject, b: GuiObject): boolean
			local aLeft, bLeft = a.AbsolutePosition.X, b.AbsolutePosition.X
			return aLeft < bLeft + b.AbsoluteSize.X and bLeft < aLeft + a.AbsoluteSize.X
		end

		--[[ Where a member from another screen goes (`GamepadConfig.HudMemberTag`): BESIDE the row it is
			drawn level with, when it is level with one and nothing in that row is above or below it, so
			the random car's card at the right edge is Right from the rail button across from it rather
			than Up from the top of the rail; otherwise a row of its own, in height order, which is the
			BACK TO BASE pill stacked over PLAY. "Level with" is the centre of either lying inside the
			other's height, because the card is several rail buttons tall. ]]
		local function placeMember(rows: { { GuiButton } }, member: GuiButton)
			local best: { GuiButton }? = nil
			local bestGap = math.huge
			for _, row in rows do
				local gap = math.abs(centreY(row[1]) - centreY(member))
				local reach = math.max(row[1].AbsoluteSize.Y, member.AbsoluteSize.Y) * 0.5
				if gap < reach and gap < bestGap then
					local clear = true
					for _, button in row do
						if overlapX(button, member) then
							clear = false
							break
						end
					end
					if clear then
						best, bestGap = row, gap
					end
				end
			end
			if best then
				table.insert(best, member)
				return
			end
			table.insert(rows, { member })
			table.sort(rows, function(a, b)
				return centreY(a[1]) < centreY(b[1])
			end)
		end

		local function railRows(): { { GuiButton } }
			local rows: { { GuiButton } } = {}
			local members: { GuiButton } = {}
			for _, button in railButtons() do
				if not button:IsDescendantOf(hud) then
					table.insert(members, button)
					continue
				end
				local centre = button.AbsolutePosition.Y + button.AbsoluteSize.Y * 0.5
				local row = rows[#rows]
				local sameRow = false
				if row then
					local first = row[1]
					local firstCentre = first.AbsolutePosition.Y + first.AbsoluteSize.Y * 0.5
					local tolerance = math.min(first.AbsoluteSize.Y, button.AbsoluteSize.Y) * 0.5
					sameRow = math.abs(centre - firstCentre) < tolerance
				end
				if sameRow then
					table.insert(row, button)
				else
					table.insert(rows, { button })
				end
			end
			for _, member in members do
				placeMember(rows, member)
			end
			for _, row in rows do
				table.sort(row, function(a, b)
					return a.AbsolutePosition.X < b.AbsolutePosition.X
				end)
			end
			return rows
		end

		--- The button in `row` nearest `button` horizontally: where the highlight goes when it steps
		--- up or down out of a row into one with a different number of buttons in it.
		local function nearestInRow(row: { GuiButton }?, button: GuiButton): GuiButton?
			if not row then
				return nil
			end
			local centre = button.AbsolutePosition.X + button.AbsoluteSize.X * 0.5
			local best: GuiButton? = nil
			local bestGap = math.huge
			for _, candidate in row do
				local gap = math.abs((candidate.AbsolutePosition.X + candidate.AbsoluteSize.X * 0.5) - centre)
				if gap < bestGap then
					best, bestGap = candidate, gap
				end
			end
			return best
		end

		--[[ Wire every HUD button to its neighbours. Up and down step between rows, left and right
			move along one.

			AN UNSET DIRECTION FALLS BACK TO THE ENGINE'S GUESS, which is what the ends of the grid
			want: nothing above the top row or below the bottom one is worth reaching, and pointing
			those at themselves is how you say so without the highlight jumping somewhere odd. The
			ends of a ROW say it the same way, so a one-button row (the Play button, the cash `+`)
			comes out exactly as it did when this was a single chain. ]]
		local function linkChain(): { { GuiButton } }
			local rows = railRows()
			for index, row in rows do
				for column, button in row do
					button.NextSelectionUp = nearestInRow(rows[index - 1], button)
					button.NextSelectionDown = nearestInRow(rows[index + 1], button)
					button.NextSelectionLeft = row[column - 1] or button
					button.NextSelectionRight = row[column + 1] or button
				end
			end
			--- Handed back so a caller that needs the top of the rail does not walk the HUD twice.
			return rows
		end

		--[[ The top row that belongs to the HUD itself. Where focus lands and where its badge sits:
			a tagged member from another screen (`GamepadConfig.HudMemberTag`) can be drawn higher
			than the rail, and "give me the menu" should still mean the menu. ]]
		local function topRailRow(rows: { { GuiButton } }): { GuiButton }?
			for _, row in rows do
				if row[1]:IsDescendantOf(hud) then
					return row
				end
			end
			return rows[1]
		end

		-- === Is this thing actually on screen? ==============================
		-- A button under a hidden section is still `Visible` itself; the engine will not select it
		-- and neither will we. Walks up to the ScreenGui, which carries the last switch.
		function isShown(object: GuiObject): boolean
			local node: Instance? = object
			while node and node ~= mainUI.Parent do
				if node:IsA("GuiObject") and not node.Visible then
					return false
				end
				if node:IsA("ScreenGui") then
					return node.Enabled
				end
				node = node.Parent
			end
			return true
		end

		local function isSelectable(object: GuiObject?): boolean
			return object ~= nil
				and object.Parent ~= nil
				and object:IsDescendantOf(playerGui)
				and (object :: any).Selectable == true
				and isShown(object)
				and object.AbsoluteSize.X > 0
		end

		-- === Seeding a page =================================================
		local function isCloseButton(button: GuiButton): boolean
			for _, name in GamepadConfig.CloseButtonNames do
				if button.Name == name then
					return true
				end
			end
			return false
		end

		local function centreOf(object: GuiObject): Vector2
			return object.AbsolutePosition + object.AbsoluteSize * 0.5
		end

		--[[ The button a page should open on: topmost, and not the way out. See
			`GamepadConfig.CloseButtonNames` — a page's X is usually its highest button, so a naive
			"first thing found" would start every screen with the highlight on the exit.

			`near` is for putting a LOST highlight back (see `onSelectionChanged`): the button nearest
			the point it was lost at, rather than the top of the page, so claiming the third quest or
			starring the ninth car leaves the player standing where they were. ]]
		local function pickTarget(frame: GuiObject, near: Vector2?): (GuiButton?, boolean)
			local best: GuiButton? = nil
			local bestScore = math.huge
			local fallback: GuiButton? = nil
			local fallbackY = math.huge
			for _, descendant in frame:GetDescendants() do
				if descendant:IsA("GuiButton") and isSelectable(descendant) then
					local y = descendant.AbsolutePosition.Y
					if isCloseButton(descendant) then
						if y < fallbackY then
							fallback, fallbackY = descendant, y
						end
					else
						local score = if near then (centreOf(descendant) - near).Magnitude else y
						if score < bestScore then
							best, bestScore = descendant, score
						end
					end
				end
			end
			if best then
				return best, true
			end
			return fallback, false
		end

		local seedToken = 0

		--[[ Put the highlight in this page, and keep trying while it fills in.

			Three ways out, and all three matter. It stops when it has landed on a real button; it
			stops the moment the player moves the highlight themselves (anything selected in this
			page that we did not put there); and it gives up after `SeedFrames`. In between it
			re-picks every frame, so a page that opens empty and gets its cards a moment later
			upgrades from its own X to the first card without the player seeing the difference. ]]
		--- `from` is a selection to treat as nobody's: the list the engine parked a lost highlight on.
		local function seedPage(frame: GuiObject, near: Vector2?, from: GuiObject?)
			seedToken += 1
			local token = seedToken
			task.spawn(function()
				local settled: GuiButton? = nil
				for _ = 1, GamepadConfig.SeedFrames do
					task.wait()
					if token ~= seedToken or not frame.Visible then
						return
					end
					local current = GuiService.SelectedObject
					if current and current ~= settled and current ~= from and current:IsDescendantOf(frame) then
						return -- the player is already driving it
					end
					local target, isReal = pickTarget(frame, near)
					if target then
						if target ~= current then
							GuiService.SelectedObject = target
						end
						-- A set can be refused (the engine rejects a target that has not rendered
						-- yet), so believe the read-back rather than the write.
						if GuiService.SelectedObject == target then
							settled = target
							if isReal then
								return
							end
						end
					end
				end
			end)
		end

		-- === Which page is on top ===========================================
		local openPages: { GuiObject } = {}
		local selectionBefore: GuiObject? = nil

		local function topPage(): GuiObject?
			return openPages[#openPages]
		end

		local function closeButtonOf(frame: GuiObject): GuiObject?
			for _, name in GamepadConfig.CloseButtonNames do
				local button = frame:FindFirstChild(name, true)
				if button and button:IsA("GuiButton") and button.Visible then
					return button
				end
			end
			return nil
		end

		-- === The bindings ===================================================
		local syncBindings -- forward declared: focus() and back() both re-sync when they land
		local syncShortcuts -- ...and syncBindings calls this one, which is defined after it
		local warnedShortcuts: { [string]: boolean } = {} -- a bad GamepadKey is said once, not per frame

		local function focus()
			if racing() or modal() or not GamepadInput.isGamepadActive() then
				return
			end
			local page = topPage()
			if page then
				seedPage(page)
				return
			end
			local top = topRailRow(linkChain())
			if not top then
				return
			end
			-- The top of the rail, and its left-hand column where the rail is a grid. Not the Play
			-- button, even though it is in the chain: PLAY has a button of its own (see the header)
			-- and landing there would make the DPad's one job ambiguous. Down from here walks the
			-- rail and ends on Play anyway.
			GuiService.SelectedObject = top[1]
		end

		local function back()
			local page = topPage()
			if page then
				-- `closePage` is keyed by the page module's name, which is the frame's name — see
				-- the header. A frame with no module behind it (the parked `DealershipOld`) cannot
				-- be closed this way, so B at least hands the player back to walking.
				if not UIController:closePage(page.Name) then
					GuiService.SelectedObject = nil
				end
				return
			end
			GuiService.SelectedObject = nil
		end

		function syncBindings()
			local selected = GuiService.SelectedObject
			local page = topPage()

			--[[ FOCUS is live only with nothing selected, which is what keeps it out of the way of
				the engine's own navigation: the moment there is a highlight, the DPad belongs to
				moving it. It also passes rather than sinks, so nothing underneath is starved by a
				binding whose whole job is to exist when nothing else wants the key.

				The badge sits ABOVE the top of the rail, where it reads as a label for the column
				it opens — and it is only drawn when the rail is what the key would reach, so a page
				already being open (mouse player, pad picked up mid-session) shows nothing. ]]
			if selected == nil and not racing() and not modal() then
				if not GamepadInput.isBound(FOCUS_ACTION) then
					--- The top row's left-hand button, which is the one `focus` lands on. Read from the
					--- rows rather than a flat sort so the badge cannot end up over the wrong half of a
					--- grid row.
					local top = if page then nil else topRailRow(railRows())
					GamepadInput.bind({
						actionName = FOCUS_ACTION,
						keyCode = GamepadConfig.FocusGlyph,
						extraKeys = GamepadConfig.FocusKeys,
						callback = focus,
						parent = top and top[1],
						iconPlacement = "top",
						result = Enum.ContextActionResult.Pass,
					})
				end
			else
				GamepadInput.unbind(FOCUS_ACTION)
			end

			-- BACK is live whenever there is something to back out of: a page, or a highlight. Not
			-- while a modal screen is up — B is that screen's answer then, and two owners of one
			-- button is one owner too many.
			if (page or selected) and not modal() then
				local parent = if page then closeButtonOf(page) else nil
				local icon = GamepadInput.getIcon(BACK_ACTION)
				if not (GamepadInput.isBound(BACK_ACTION) and (icon and icon.Parent) == parent) then
					GamepadInput.bind({
						actionName = BACK_ACTION,
						keyCode = GamepadConfig.BackKey,
						callback = back,
						parent = parent,
						-- Lifted clear of the button's own stroke and decor.
						iconPosition = UDim2.new(0.5, 0, -0.4, 0),
					})
				end
			else
				GamepadInput.unbind(BACK_ACTION)
			end

			syncShortcuts()
		end

		--[[ THE BUTTONS THAT PRESS THEMSELVES. One action per HUD button carrying a `GamepadKey`,
			live while that button is on screen and the UI is the player's to drive.

			HIDDEN IS AN IMPORTANT CONDITION. `RaceEntryController` takes the Play button off the
			screen for the length of a race, so the shortcut follows its button's visibility rather
			than keeping a race flag of its own. The other two (racing, modal) are the same refusals
			the focus key makes, and they are there for the case where somebody switches
			`RaceConfig.HidePlayDuringRace` off.

			IT IS NOT WHAT PROTECTS THE DRIVER'S SEAT, though an earlier version of this note claimed
			it was. Visibility only ever covered the RACE; a player parked in a lobby car has the whole
			HUD up and was sharing a button with their own exit. `seated` is the condition that
			actually states the rule, and it is keyed by which button, so it takes nothing away that
			the seat has no claim to. ]]
		function syncShortcuts()
			for _, button in hud:GetDescendants() do
				if not button:IsA("GuiButton") then
					continue
				end
				local keyName = button:GetAttribute(GamepadConfig.ShortcutAttribute)
				if type(keyName) ~= "string" then
					continue
				end
				local keyCode = (Enum.KeyCode :: any)[keyName]
				local actionName = SHORTCUT_PREFIX .. button:GetFullName()

				if typeof(keyCode) ~= "EnumItem" then
					if not warnedShortcuts[actionName] then
						warnedShortcuts[actionName] = true
						warn(
							string.format(
								"[GamepadNav] %s has GamepadKey '%s', which is not a KeyCode name.",
								button:GetFullName(),
								keyName
							)
						)
					end
					continue
				end

				-- The seat's claim is per KEY, so it is asked here where the key is known. See `seated`.
				local contested = seatKeys[keyCode] ~= nil and seated()

				if button.Visible and isShown(button) and not racing() and not modal() and not contested then
					if not GamepadInput.isBound(actionName) then
						GamepadInput.bind({
							actionName = actionName,
							keyCode = keyCode,
							callback = function()
								ButtonPress.press(UIController, button)
							end,
							parent = button,
							iconPlacement = "right",
						})
					end
				else
					GamepadInput.unbind(actionName)
				end
			end
		end

		-- === Page open / close ==============================================
		local function onPageOpened(frame: GuiObject)
			if table.find(openPages, frame) == nil then
				table.insert(openPages, frame)
			end
			--[[ The device in use, OR the last press. A page that opens by itself (the daily reward, on
				join) opens before a console player has pressed anything, so the last-input test alone
				left it with nothing lit; `isGamepad` is the engine's settled answer and is a pad on a
				console from the first frame. The last-input test stays for a press that has not moved
				`PreferredInput` yet (see `GamepadInput.isGamepadActive`). ]]
			if (GamepadInput.isGamepadActive() or GamepadInput.isGamepad()) and not racing() then
				local current = GuiService.SelectedObject
				-- Only remember a selection from OUTSIDE this page: that is the rail button the
				-- player pressed to get here, and it is where B should put them back.
				if current and not current:IsDescendantOf(frame) then
					selectionBefore = current
				end
				seedPage(frame)
			end
			syncBindings()
		end

		local function onPageClosed(frame: GuiObject)
			local index = table.find(openPages, frame)
			if index then
				table.remove(openPages, index)
			end
			local selected = GuiService.SelectedObject
			if selected and selected:IsDescendantOf(frame) then
				--[[ Back where you came from, if it is still there. The rail button that opened the
					page is the one the player expects to be standing on when it shuts — and the
					fallback of nil is not a failure, it is "you were walking when this opened, so
					you are walking again now". ]]
				local restore = if isSelectable(selectionBefore) then selectionBefore else nil
				if restore then
					linkChain()
				end
				GuiService.SelectedObject = restore
			end
			if #openPages == 0 then
				selectionBefore = nil
			end
			syncBindings()
		end

		--[[ A PAGE IS A ROOM WITH NO DOORS. The highlight goes in when the page opens and comes out
			when it closes, and the DPad cannot walk it out in between.

			Without this the engine's automatic navigation reaches straight THROUGH an open panel to
			the rail behind it — press left on a world card and the highlight is suddenly on the
			Index button, with the page still up in front of it and no obvious way back in. Roblox's
			own answer is a selection group: mark the frame as one and tell each edge to Stop rather
			than Escape (the default), and navigation inside it stays inside it.

			Set once and left set. It only means anything while the frame is visible, so there is
			nothing to undo on close, and a page that is added later gets it on the way in. B is the
			door — see `back()`. ]]
		local function trapSelection(frame: GuiObject)
			frame.SelectionGroup = true
			frame.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
			frame.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
			frame.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
			frame.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
		end

		local function watchPage(frame: Instance)
			if not frame:IsA("GuiObject") then
				return
			end
			trapSelection(frame)
			frame:GetPropertyChangedSignal("Visible"):Connect(function()
				if frame.Visible then
					onPageOpened(frame)
				else
					onPageClosed(frame)
				end
			end)
			if frame.Visible then
				onPageOpened(frame)
			end
		end

		for _, frame in pages:GetChildren() do
			watchPage(frame)
		end
		pages.ChildAdded:Connect(watchPage)

		-- === The highlight going missing ====================================
		--[[ A PAGE THAT DELETES THE BUTTON YOU PRESSED HANDS THE HIGHLIGHT BACK. Claim a quest and
			its row leaves; star a car and the Cars grid is re-stamped; claim the day's reward and the
			button hides. The engine answers each by dropping the selection, and a console player was
			left on an open page with nothing lit and no glyph saying what to press.

			So a highlight lost from inside the page on top, while that page is still open and the pad
			is still the thing in use, is put back on the nearest button to where it was. Where the
			page was is recorded when the highlight lands, not read when it goes, because a destroyed
			button has no ancestry left to ask.

			Every other way of losing it is left alone, and those are the deliberate ones: a close (the
			page is no longer open), the mouse (`observePreferred`), a race, a modal.

			THE ENGINE DOES NOT ALWAYS DROP IT TO NIL. A button that hides inside a scrolling list hands
			the highlight to the LIST (measured 2026-10-15 on the Shop: the gift button went, the
			ScrollingFrame took it). So a highlight that lands on something that is not a button, in the
			same page, straight after the button it was on stopped being selectable, is the same loss
			and gets the same answer. Walking onto a list on purpose leaves the button behind still
			selectable, which is how the two are told apart. ]]
		local lastPage: GuiObject? = nil
		local lastPoint: Vector2? = nil
		local lastObject: GuiObject? = nil

		local function pageOf(object: GuiObject): GuiObject?
			for _, frame in openPages do
				if object:IsDescendantOf(frame) then
					return frame
				end
			end
			return nil
		end

		--- Still the page on top, still drawn, and not on its way out (a close keeps it `Visible`
		--- for the length of its tween).
		local function stillOpen(frame: GuiObject?): boolean
			return frame ~= nil and frame == topPage() and frame.Visible and UIController:isPageOpen(frame.Name)
		end

		local function mayReseed(page: GuiObject?): boolean
			return stillOpen(page) and GamepadInput.isGamepadActive() and not racing() and not modal()
		end

		local function onSelectionChanged()
			local selected = GuiService.SelectedObject
			local page, point, from = lastPage, lastPoint, lastObject
			if selected then
				lastObject = selected
				lastPage = pageOf(selected)
				lastPoint = if lastPage then centreOf(selected) else nil
				local fellBack = not selected:IsA("GuiButton")
					and page ~= nil
					and lastPage == page
					and from ~= nil
					and from:IsA("GuiButton")
					and not isSelectable(from)
				if fellBack and mayReseed(page) then
					seedPage(page :: GuiObject, point, selected)
				end
			else
				lastObject, lastPage, lastPoint = nil, nil, nil
				if mayReseed(page) then
					seedPage(page :: GuiObject, point)
				end
			end
			syncBindings()
		end

		-- === Live wiring ====================================================
		GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(onSelectionChanged)

		--[[ A device change is what decides whether any of this is advertised, and `refreshIcons`
			only re-reads badges that exist — so re-ask which bindings should exist as well.

			AND PUT THE HIGHLIGHT AWAY WHEN THE PAD IS. The engine does not: `SelectedObject` is a
			plain property and nothing clears it when the player reaches for the mouse, so the
			highlight sits there over a cursor-driven UI — with whichever button it is on still
			wearing the grown, stroked state `Components/Button` gave it, because `SelectionLost`
			only fires when the selection MOVES. Two pointers on one screen, one of which no longer
			answers to anything.

			Only ours is dropped (`MainUI`), never a selection something else put out, and the
			reverse is deliberately not symmetrical: picking a controller back up does NOT
			re-select anything, because rule 1 says the highlight is asked for. An open page stays
			open — it is the highlight that belongs to the device, not the screen. ]]
		GamepadInput.observePreferred(function(isGamepad: boolean)
			local selected = GuiService.SelectedObject
			if not isGamepad and selected and selected:IsDescendantOf(mainUI) then
				GuiService.SelectedObject = nil
			end
			syncBindings()
		end)

		-- The race, in both directions: drop the highlight when the run starts (rule 1 — the left
		-- stick is the car's), and re-offer the focus key when it ends.
		if drivingHud then
			drivingHud:GetPropertyChangedSignal("Enabled"):Connect(function()
				if drivingHud.Enabled and GuiService.SelectedObject then
					GuiService.SelectedObject = nil
				end
				syncBindings()
			end)
		end

		--[[ A modal screen going up takes the same two things away, for the same reason.

			ONLY OUR HIGHLIGHT, NEVER THE MODAL'S OWN. A modal that seeds its first button
			(the Workshop, the radio) does so in the same breath as it raises the attribute, and this
			listener is deferred, so it runs AFTER that seed. It used to clear whatever was selected,
			which wiped the modal's highlight the moment it landed and left those screens with nothing
			a controller could press. "Ours" is the HUD, the pages and the topbar icon that opened the
			screen (TopbarPlus marks each icon's click region with `CorrespondingIconUID`).

			AND ON THE WAY DOWN, THE PAGE UNDER IT GETS ITS HIGHLIGHT BACK. The sell popup goes up over
			SELECT CAR and the Welcome Back panel can go up over the daily reward; when either closes,
			the page is still open and was left with nothing lit. ]]
		local function isOurs(object: GuiObject): boolean
			return object:IsDescendantOf(mainUI) or object:GetAttribute("CorrespondingIconUID") ~= nil
		end

		local underModal: { page: GuiObject?, point: Vector2? }? = nil

		playerGui:GetAttributeChangedSignal(GamepadConfig.ModalAttribute):Connect(function()
			local selected = GuiService.SelectedObject
			if modal() then
				if selected and isOurs(selected) then
					local page = pageOf(selected)
					underModal = { page = page, point = if page then centreOf(selected) else nil }
					GuiService.SelectedObject = nil
				end
			else
				local held = underModal
				underModal = nil
				local page = topPage()
				-- A highlight still on the modal's own button is a screen on its way out (most fade),
				-- so it does not count as the player having gone somewhere else.
				local free = selected == nil or not isOurs(selected)
				if stillOpen(page) and free and GamepadInput.isGamepadActive() and not racing() then
					seedPage(page :: GuiObject, if held and held.page == page then held.point else nil)
				end
			end
			syncBindings()
		end)

		--[[ SITTING DOWN AND STANDING UP, which is what hands the seat keys over and takes them back.
			`seated` is only consulted inside `syncShortcuts`, so without this the rule would be right
			and never re-asked — the shortcut would keep whatever state it happened to be in when the
			player got into the car.

			Re-hooked per character because `SeatPart` lives on the Humanoid and a respawn brings a new
			one. Nothing is disconnected on the way out: the old Humanoid is destroyed with its
			character, which drops the connection with it. ]]
		local function watchSeat(character: Model)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
				or character:WaitForChild("Humanoid", GUI_WAIT) :: Humanoid?
			if not humanoid then
				return
			end
			humanoid:GetPropertyChangedSignal("SeatPart"):Connect(syncBindings)
			syncBindings()
		end

		if Players.LocalPlayer.Character then
			task.spawn(watchSeat, Players.LocalPlayer.Character)
		end
		Players.LocalPlayer.CharacterAdded:Connect(function(character)
			task.spawn(watchSeat, character)
		end)

		--[[ A HUD member appearing or disappearing (Play hides for the length of a race) re-shapes the
			chain, and a highlight standing on the one that went has to go with it.

			WATCHED ON THE BOXES AS WELL AS THE BUTTONS, which this file used not to do and was already
			wrong not to. A button under a frame that just went dark is still `Visible = true` itself,
			so watching buttons alone sees nothing at all when a whole section leaves —
			`RaceEntryController` has hidden the rail as one box the entire time, and the chain kept
			pointing at five buttons nobody could reach for the length of every race.

			The new UI is what made it visible: its grid cell is a frame with the button inside it, so
			`Components/HudRules` taking a cell away (a page with nothing behind it) moves a button
			without touching one. Same blind spot, one level further down.

			Only the boxes with a button somewhere inside them. The kit HUD is a few hundred labels,
			icons and gradients deep, and a connection on each would be hundreds of signals to answer
			a question about a dozen buttons.

			The dropped selection is decided by `isShown` rather than by the member's own `Visible`,
			for exactly the same reason: the highlight can be standing on a button that is still
			`Visible` under an ancestor that is not. ]]
		local function onVisibilityChanged()
			local selected = GuiService.SelectedObject
			local member = selected
				and (selected:IsDescendantOf(hud) or CollectionService:HasTag(selected, GamepadConfig.HudMemberTag))
			if member and not isShown(selected) then
				GuiService.SelectedObject = nil
			end
			linkChain()
			-- The Play button hiding for a race is what takes its shortcut away with it.
			syncBindings()
		end

		hud:GetPropertyChangedSignal("Visible"):Connect(onVisibilityChanged)
		for _, descendant in hud:GetDescendants() do
			local isBox = descendant:IsA("GuiObject")
				and not descendant:IsA("GuiButton")
				and descendant:FindFirstChildWhichIsA("GuiButton", true) ~= nil
			if descendant:IsA("GuiButton") or isBox then
				(descendant :: GuiObject):GetPropertyChangedSignal("Visible"):Connect(onVisibilityChanged)
			end
		end

		--[[ The tagged members from other screens (`GamepadConfig.HudMemberTag`) come and go the same
			way: a holder fades in, a gui switches on. Each one's switches, from the button up to its
			ScreenGui, are watched once when the tag lands. Nothing is disconnected; these are built once
			per session and live as long as the client does. ]]
		local function watchMember(member: Instance)
			if not member:IsA("GuiButton") then
				return
			end
			local node: Instance? = member
			while node and node ~= playerGui do
				if node:IsA("GuiObject") then
					node:GetPropertyChangedSignal("Visible"):Connect(onVisibilityChanged)
				elseif node:IsA("ScreenGui") then
					node:GetPropertyChangedSignal("Enabled"):Connect(onVisibilityChanged)
					break
				end
				node = node.Parent
			end
			onVisibilityChanged()
		end
		for _, member in CollectionService:GetTagged(GamepadConfig.HudMemberTag) do
			watchMember(member)
		end
		CollectionService:GetInstanceAddedSignal(GamepadConfig.HudMemberTag):Connect(watchMember)

		linkChain()
		syncBindings()
	end)
end
