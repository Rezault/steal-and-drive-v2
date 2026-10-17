--[[
	Button component  (client)
	--------------------------
	Tag any GuiButton `UIButton` and it gains hover feedback and a click sound. Give it a `Page`
	attribute and it opens that page. Nothing else has to know the button exists.

	WHAT THE ATTRIBUTES DO, all optional:

		Page           string   page name to open on press (`KeepPagesOpen` = comma-separated
		                        list of pages to leave open alongside it)
		Action         string   published on `Dispatcher` as `UIAction` on press, for a button
		                        that DOES something rather than opening a screen
		Scale          number   hover scale, default 1.05. Re-read live in Studio, so you can
		                        drag it in the Explorer during a playtest and feel the change.
		SelectStroke   Color3   UIStroke colour while hovered
		OriginalStroke Color3   UIStroke colour to go back to
		GamepadKey     string   a KeyCode name ("ButtonY") that presses this button outright on a
		                        controller, without the highlight having to be driven onto it
		                        first. Read and bound by `Components/GamepadNav`, which is where
		                        the rules about when a shortcut may be live live. HUD only.

	`Action` is `Page`'s other half and exists for the same reason: the HUD's Play button opens
	no screen, it starts a race. Without it that one button would be the single thing in the UI
	wired by a hard-coded path from a controller, and the first person to rename or re-parent it
	in the Explorer would break it silently. So it stays an attribute — the listener names the
	action, never the button. See `RaceEntryController` for the "EnterRace" end of it.

	A child named `Hint` is shown on hover and hidden on leave.

	THE SCALE IS ON TOP OF THE ART, NOT INSTEAD OF IT. Our buttons already carry a real hover
	image, which Roblox swaps in by itself — this adds the physical nudge underneath it. That is
	why the rail buttons are set to a smaller `Scale` than the 1.05 default: two full-strength
	reactions to one hover reads as the UI flinching. Tune it per button rather than here.

	THE NUDGE RIDES A `UIScale` NAMED `HoverScale`, made here, and NOT the button's `Size`. That is
	what makes the tag safe to put on anything: a pixel-sized button, a row in a list, a card whose
	size a `UIGridLayout` owns, a button under an aspect constraint. All four were broken by the old
	`Size` tween and all four are ordinary buttons somebody was always going to want to tag. The one
	exception, and the fallback that covers it, is written up in full at the `HoverScale` block below.

	A DEAD BUTTON DOES NOTHING — no swell, no sound, no press — whether it was switched off with
	`Interactable` or with `Active`. Both are in use in this project and they do not mean the same
	thing; see the `live()` note below.

	A GAMEPAD FIRES NONE OF THOSE EVENTS, which is the whole of console support at this layer.
	There is no cursor to enter or leave a button and no mouse to press one: the engine keeps a
	SELECTION (`GuiService.SelectedObject`, moved with the DPad — see `Components/GamepadNav`) and
	activates it with A. So every tagged button gains two more wires, both landing in the same two
	functions the mouse lands in:

	  • `SelectionGained` / `SelectionLost` ARE the hover. Same nudge, same stroke, same `Hint`,
	    same sound — a highlight that moved onto a button and a cursor that moved onto it are the
	    same news, and a console player who got no reaction would think the UI was dead.

	  • `Activated` IS the press, and it is bound alongside `MouseButton1Down` rather than instead
	    of it. Mouse and touch keep firing on the way DOWN, which is what makes the UI feel quick;
	    `Activated` is what a gamepad A press produces. The catch is that the engine raises
	    `Activated` for a mouse click TOO, so it is filtered on the InputObject it hands over and
	    takes only the controller half. `PRESS_GUARD` is the backstop underneath that, for a press
	    that arrives with no InputObject to identify it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ButtonPress = require(script.Parent.Parent.ButtonPress)
local UIControllerTypes = require(script.Parent.Parent.UIControllerTypes)
local Shard = require(ReplicatedStorage.Packages.Shard)
local observeTag = require(ReplicatedStorage.Packages.Observers).observeTag

local SoundController -- resolved lazily; sounds no-op until the controller exists

local function playUISound(groupName: string)
	SoundController = SoundController or Shard.get("SoundController")
	if SoundController then
		SoundController:PlayRandom(groupName)
	end
end

--[[ The UIScale the hover nudge is written to, made on the button the first time the tag lands.
	NAMED, and checked by name: a UIScale found there under any other name belongs to whoever built
	the button and this must not drive it. See the long note in the observer for what happens then. ]]
local HOVER_SCALE_NAME = "HoverScale"

--- Multiply a size on BOTH channels. The offset half is the whole point — see the observer's note on
--- the fallback path: dropping it is what used to collapse a pixel-sized button to nothing.
local function grow(size: UDim2, factor: number): UDim2
	return UDim2.new(
		size.X.Scale * factor,
		size.X.Offset * factor,
		size.Y.Scale * factor,
		size.Y.Offset * factor
	)
end

-- Seconds after a press in which a second one is ignored. See the header: one physical press can
-- arrive on both `MouseButton1Down` and `Activated`, and a page toggle that runs twice opens and
-- immediately shuts — a dead button, from the player's side. Short enough that no human double-tap
-- is swallowed, long enough to cover both wires of one press.
local PRESS_GUARD = 0.05

return function(UIController: UIControllerTypes.UIController)
	observeTag("UIButton", function(instance: GuiButton)
		if not instance:IsA("ImageButton") and not instance:IsA("TextButton") then
			return
		end

		local DEFAULT_SCALE = 1.05
		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		--[[ WHERE THE NUDGE IS WRITTEN, and it is not always the same place.

			It was `Size` for every button until 2026-08-19, which quietly disqualified three whole
			shapes of button from ever carrying this tag:

			  • A button sized in OFFSET pixels. The old tween multiplied the SCALE components and
			    threw the offset away, so a 120x40 button tweened to 0x0 the first time a cursor
			    touched it. That is the trap `DealershipSignController` and `LeaderboardController`
			    cite as their reason for binding by hand.
			  • A button a LAYOUT owns. A row in a `UIListLayout` that grows on hover pushes every row
			    under it down; a card in a `UIGridLayout` is drawn at the CELL's size whatever its own
			    `Size` says, so the tween is simply ignored. The inventory and start-car grids are both
			    the second kind, and both are lists of cards a player is meant to point at.
			  • A button under a `UIAspectRatioConstraint`, where the constraint re-fits the grown box
			    and the nudge comes out smaller on one axis than it was asked for.

			A `UIScale` has none of those problems: it multiplies the rendered element after layout, so
			the authored `Size` stays the one source of truth and no sibling moves. That is the channel
			this uses now.

			THE FALLBACK IS THE OLD PATH, for the one case a UIScale cannot have: only ONE UIScale on an
			instance takes effect (measured — a second is ignored, not multiplied), so a button whose
			owner already parked one there has its scale channel spoken for, and taking it over would
			make that owner's animation and this hover fight over one number. Those buttons keep the Size
			tween — now written so it carries the offset through rather than dropping it.

			THE FALLBACK IS ONLY SAFE ON A BUTTON WHOSE `Size` NOBODY REWRITES, because `originalSize` is
			taken once, here, when the tag lands. `ReviveController` was the example cited in this block
			until 2026-08-28 and is now the counter-example: it lays its two buttons out per viewport, so
			a stale copy of the size would have been restored under the next cursor. The way out is the
			one it took — park the owner's animation on a wrapper and leave the button's scale channel
			free for this — rather than anything in here. ]]
		local hoverScale: UIScale? = nil
		local existingScale = instance:FindFirstChildOfClass("UIScale")
		if existingScale then
			if existingScale.Name == HOVER_SCALE_NAME then
				hoverScale = existingScale
			end
		else
			hoverScale = Instance.new("UIScale")
			hoverScale.Name = HOVER_SCALE_NAME
			hoverScale.Parent = instance
		end

		local originalSize = instance.Size

		local function nudgeTo(factor: number)
			if hoverScale then
				TweenService:Create(hoverScale, tweenInfo, { Scale = factor }):Play()
			else
				TweenService:Create(instance, tweenInfo, { Size = grow(originalSize, factor) }):Play()
			end
		end

		--[[ A DEAD BUTTON REACTS TO NOTHING, which is the other half of being able to tag everything.
			Both properties are in use as an off switch in this project and they do not mean the same
			thing: `Interactable` is the engine's own — it suppresses the press and the hover art —
			while `Active` only governs whether the object consumes input (see the note in
			`Pages/Dealership` on why a dimmed button left live on `Active` alone still fired).
			`Pages/Teleport` dims a world you cannot travel to with `Active`, `Pages/Dealership` dims a
			bay the car is already on with `Interactable`, and neither should swell or chirp under a
			cursor. Before this, both did. ]]
		local function live(): boolean
			return instance.Interactable and instance.Active
		end

		-- The reaction to "the player is pointing at this", whichever device is doing the pointing.
		local function highlight(on: boolean)
			if on and not live() then
				return
			end

			local strokeColor = instance:GetAttribute(if on then "SelectStroke" else "OriginalStroke")
			if strokeColor then
				local stroke = instance:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = strokeColor
				end
			end

			local hint = instance:FindFirstChild("Hint")
			if hint then
				hint.Visible = on
			end

			if not on then
				nudgeTo(1)
				return
			end

			playUISound("UIHover")
			-- Re-read `Scale` on every hover rather than caching it once, so an attribute dragged in
			-- the Explorer during a playtest is felt on the next pass over the button.
			nudgeTo(instance:GetAttribute("Scale") or DEFAULT_SCALE)
		end

		local lastPressAt = 0
		local function press()
			if not live() then
				return
			end

			local now = os.clock()
			if now - lastPressAt < PRESS_GUARD then
				return -- the other wire of the same physical press; see PRESS_GUARD
			end
			lastPressAt = now

			-- What a press MEANS is `ButtonPress`, shared with the controller shortcut in
			-- `Components/GamepadNav` so a face button bound to Play does exactly what Play does.
			ButtonPress.press(UIController, instance)
		end

		instance.MouseEnter:Connect(function()
			highlight(true)
		end)
		instance.MouseLeave:Connect(function()
			highlight(false)
		end)
		instance.MouseButton1Down:Connect(function()
			press()
		end)

		-- The gamepad's two. `Selectable` is forced on because a button the highlight cannot land on
		-- is a button a controller can never press, and it is one property nobody remembers to tick
		-- in the Explorer — the tag is the statement of intent, so this follows from it.
		instance.Selectable = true
		instance.SelectionGained:Connect(function()
			highlight(true)
		end)
		instance.SelectionLost:Connect(function()
			highlight(false)
		end)
		--[[ `Activated` covers mouse, touch AND gamepad, and the pointer half already came in on
			`MouseButton1Down` — so this takes the press only when the input that raised it was a
			controller, read off the InputObject the event hands us. A press with no InputObject at
			all falls back to the time guard, which is the only case `PRESS_GUARD` is really for.

			Filtering by device rather than by time because a mouse click is not an instant: hold the
			button down for half a second and the `Down` and the `Activated` are half a second apart,
			which no guard short enough to be safe would ever cover. ]]
		instance.Activated:Connect(function(inputObject: InputObject?)
			if inputObject and inputObject.UserInputType.Name:sub(1, 7) ~= "Gamepad" then
				return
			end
			press()
		end)
	end)
end
