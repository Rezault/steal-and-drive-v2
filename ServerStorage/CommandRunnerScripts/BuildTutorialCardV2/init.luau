--[[
	BuildTutorialCardV2: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.TutorialCard`, the onboarding's objective card, out of the
	Cartoony Kit's `TutorialUI`. Phase 4 of `docs/NewUI-Migration-Plan.md`; the running record is
	`docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` first: this fills in a shelf that already exists rather than creating one.
	`Screens.TutorialCard` is destroyed and made again on every run, and nothing else on the shelf is
	touched, so it is safe beside the other Phase 4 commands and safe to re-run.

	=== A TEMPLATE, NOT A SCREEN ==============================================================

	Nothing draws this where it is built. `Screens` is hidden, and `TutorialController` clones the
	template into its own `Tutorial` ScreenGui at boot, because that gui sits at `DisplayOrder` 950,
	over the driving HUD and under the revive question, and a frame inside `MainUIV2` would share the
	HUD's one layer. The dim and the arrow stay built in code beside it. Only the card moved.

	=== WHAT THE KIT DREW ====================================================================

	`TutorialUI` is a speech card:

	    TutorialUI          a cyan-to-blue checker rim, 3.625:1
	      Profile           a portrait standing on the rim's top left edge (the artist's capybara)
	      Name              "Tutorial Man", the speaker, straddling the top edge
	      Main              the white body
	        Title           "In order to start playing this game, please walk up to the man in black."
	        SkipBtn         orange, bottom left
	        MainBtns        pink "No." and green "Okay, Ig", bottom right

	=== WHAT IT BECOMES ======================================================================

	The label on the rim is the OBJECTIVE and the sentence in the body is the HINT. That is the kit's
	own reading order (a heading on the edge, then what it says) and it is exactly the card's two
	lines, so nothing about the composition is invented:

	    TutorialCard        a CanvasGroup the card fades as one piece; see below
	      Panel             the kit frame, renamed
	        Objective       was `Name`. One line, shouted, where the speaker's name was and half again
	                        its height (`OBJECTIVE_H`)
	        Main
	          Hint          was `Title`, grown into the room the buttons leave
	          Done          the DONE stamp, a copy of the hint's type in the payout green, hidden

	THE THREE BUTTONS GO. The card takes no press and must not: it sits over a live race, and a card
	that ate a touch would occasionally cost somebody a steal (`TutorialController._build`). The kit's
	Skip is the SKIP word `TutorialConfig` took off this card on purpose, and Okay and No have no
	question to answer. A button that leads nowhere is worse than no button.

	THE PORTRAIT GOES. There is no tutor character in this game to put in it, the artist's capybara is
	a placeholder, and a face on a card that interrupts a run is a second thing to look at before the
	line that matters. The slot is a picture's height above the rim, so if a character is ever drawn
	this is the command to put it back in; `TutorialController._place` would need to know about the
	overhang (see the margins below).

	=== WHY A CanvasGroup AROUND IT ==========================================================

	The card fades in and out, and the kit's card is five layers of art: the gradient rim, its
	checker, the white body, and outlined text on top. Faded part by part, the half-transparent body
	shows the blue rim through it and the text strokes outlast their letters. A CanvasGroup
	composites the card first and fades the picture, which is one tween and looks like a card leaving
	rather than a card coming apart.

	A CanvasGroup CLIPS to its own box, so the box is the panel plus margins: the objective straddles
	the panel's top edge, the rim's stroke is drawn outside the panel, and the objective's punch
	(`TutorialController._punch`, up to 1.12) swings its first letter past the panel's left edge. The
	margins are that overhang and no more, and they are in the box `_place` keeps clear of things.

	=== THE SIZE IS AUTHORED HERE ============================================================

	`CARD_WIDTH` of the screen's width, height from the aspect. Width-led, so the card is the same size
	in `MainUIV2`'s inset space (where it is authored) and in the tutorial gui's full-screen root
	(where it is drawn): the inset changes a screen's height and never its width. Edit the
	`UIAspectRatioConstraint` and the `Size.X` in the Explorer and the controller follows; it reads
	`AbsoluteSize` and nothing else.
]]

local StarterGui = game:GetService("StarterGui")
local ServerStorage = game:GetService("ServerStorage")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local ENTRY_NAME = "TutorialCard"
local KIT_FRAME = "TutorialUI"

--- The kit's names, and ours. Ours are what `TutorialController._useKitCard` finds by name.
local PANEL_NAME = "Panel"
local KIT_SPEAKER = "Name"
local OBJECTIVE_NAME = "Objective"
local KIT_BODY_TEXT = "Title"
local HINT_NAME = "Hint"
local DONE_NAME = "Done"
local KIT_PORTRAIT = "Profile"
local KIT_BUTTON_ROWS = { "SkipBtn", "MainBtns" }

--[[ Of the screen's width, and the code-built card's own number, so the card covers about as much of
	a race as it always did. The kit's type is bigger at that width than the old card's was, because
	the objective's band below is taller than the old title's box. ]]
local CARD_WIDTH = 0.27

--- The kit's aspect, if its constraint is ever missing.
local KIT_ASPECT = 3.625

--[[ The objective's band, as a fraction of the panel's height. The kit drew a speaker's name there
	at 0.214, and at that size the objective, which is the line the card exists to shout, came out
	smaller than the hint under it could be. Set side by side in an edit-mode render against the other
	layout (the objective as a headline inside the body) this read best: the kit's composition, with
	the heading promoted. Still centred on the rim's top edge. ]]
local OBJECTIVE_H = 0.32

--[[ The kit caps its labels in PIXELS (the speaker's name at 48), which is right at the size the
	artist drew and holds the objective back on a 1440p screen while the hint, capped off the band's
	rendered height at runtime, keeps growing. Raised to the engine's own ceiling (a higher number is
	clamped to 100), which is past anything the band reaches, so the box decides. ]]
local TEXT_CAP = 100

--[[ The CanvasGroup's margins round the panel, as fractions of the PANEL'S HEIGHT. See the header.

	TOP is the objective's overhang (it is centred on the edge, so half its band) plus its text stroke
	and the punch's growth. SIDE is the punch: at 1.12 the band's left end moves 0.013 of the panel's
	WIDTH past the panel, which at 3.6:1 is about 0.05 of its height, doubled for the stroke. BOTTOM is
	the rim's own stroke. ]]
local MARGIN_TOP = OBJECTIVE_H * 0.5 + 0.1
local MARGIN_SIDE = 0.1
local MARGIN_BOTTOM = 0.06

--[[ The hint's box inside `Main`, now that the buttons have gone. It starts clear of the objective's
	band (which reaches 0.1 into the body) and stops short of the body's bottom edge, and the text is
	centred in it, so a one-line hint sits in the middle of the card and a two-line one fills it. ]]
local HINT_Y = 0.56
local HINT_H = 0.66

--- The stamp, centred in the body. One line, so a smaller box than the hint's: `TextScaled` fills
--- the height it is given, and DONE is a word rather than a sentence.
local DONE_Y = 0.56
local DONE_H = 0.46

--- `TutorialController`'s `CASH_GREEN`, the payout green, for one word.
local DONE_COLOR = Color3.fromRGB(126, 217, 87)

--- Placeholders, so the freshly built template reads as the finished card in the Explorer. All of
--- them are overwritten on the first paint.
local OBJECTIVE_PLACEHOLDER = "HOLD W TO BOOST"
local HINT_PLACEHOLDER = "The throttle drives itself. W is your extra"
local DONE_PLACEHOLDER = "DONE"

--- The kit template, or nil and a sentence saying which step of the path was missing.
local function findTemplate(): (Instance?, string?)
	local node: Instance = ServerStorage
	for _, step in TEMPLATE_PATH do
		local child = node:FindFirstChild(step)
		if not child then
			return nil, string.format("%s has no child `%s`.", node:GetFullName(), step)
		end
		node = child
	end
	local screen = node:FindFirstChildWhichIsA("ScreenGui")
	if not screen then
		return nil, string.format("%s holds no ScreenGui.", node:GetFullName())
	end
	local container = screen:FindFirstChild("Container")
	if not container then
		return nil, string.format("%s has no `Container` of frames.", screen:GetFullName())
	end
	return container, nil
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.TutorialCard (the onboarding's objective card) from the Cartoony Kit's TutorialUI: the speaker label becomes the objective, the body the hint, a DONE stamp is added, and the portrait and the three buttons go. Rebuilds the shelf entry every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local shelf = screen and screen:FindFirstChild(SHELF_NAME)
		if not (shelf and shelf:IsA("GuiObject")) then
			out:error(string.format("No StarterGui.%s.%s. Run BuildMainUIV2 first.", SCREEN_NAME, SHELF_NAME))
			return
		end

		local container, why = findTemplate()
		if not container then
			out:error(string.format("The kit is not where it should be: %s", why))
			return
		end

		local kitFrame = container:FindFirstChild(KIT_FRAME)
		if not (kitFrame and kitFrame:IsA("GuiObject")) then
			out:error(string.format("%s has no `%s` to build from.", container:GetFullName(), KIT_FRAME))
			return
		end

		--- Checked on the kit before anything is destroyed, so a re-imported frame with different names
		--- stops the build with the entry it already had still standing.
		local kitMain = kitFrame:FindFirstChild("Main")
		local kitSpeaker = kitFrame:FindFirstChild(KIT_SPEAKER)
		local kitBody = kitMain and kitMain:FindFirstChild(KIT_BODY_TEXT)
		if not (kitMain and kitSpeaker and kitSpeaker:IsA("TextLabel") and kitBody and kitBody:IsA("TextLabel")) then
			out:error(string.format("The kit's %s is missing `%s`, `Main` or `Main.%s`.", KIT_FRAME, KIT_SPEAKER, KIT_BODY_TEXT))
			return
		end

		local existing = shelf:FindFirstChild(ENTRY_NAME)
		if existing then
			existing:Destroy()
		end

		local panel = kitFrame:Clone() :: GuiObject
		panel.Name = PANEL_NAME
		panel.Visible = true
		local main = panel:FindFirstChild("Main") :: GuiObject

		-- === What goes ======================================================
		local removed = {}
		local portrait = panel:FindFirstChild(KIT_PORTRAIT)
		if portrait then
			portrait:Destroy()
			table.insert(removed, KIT_PORTRAIT)
		end
		for _, name in KIT_BUTTON_ROWS do
			local row = main:FindFirstChild(name)
			if row then
				row:Destroy()
				table.insert(removed, name)
			end
		end

		--[[ The aspect moves up to the CanvasGroup, which is the box the controller places. Left on the
			panel as well it would be a second opinion about a size the group already decides. ]]
		local aspect = KIT_ASPECT
		local constraint = panel:FindFirstChildOfClass("UIAspectRatioConstraint")
		if constraint then
			aspect = constraint.AspectRatio
			constraint:Destroy()
		end

		-- === The two lines ==================================================
		local objective = panel:FindFirstChild(KIT_SPEAKER) :: TextLabel
		objective.Name = OBJECTIVE_NAME
		objective.Text = OBJECTIVE_PLACEHOLDER
		objective.Size = UDim2.new(objective.Size.X, UDim.new(OBJECTIVE_H, 0))
		local objectiveCap = objective:FindFirstChildOfClass("UITextSizeConstraint")
		if objectiveCap then
			objectiveCap.MaxTextSize = TEXT_CAP
		end

		local hint = main:FindFirstChild(KIT_BODY_TEXT) :: TextLabel
		hint.Name = HINT_NAME
		hint.Text = HINT_PLACEHOLDER
		hint.AnchorPoint = Vector2.new(0.5, 0.5)
		hint.Position = UDim2.fromScale(0.5, HINT_Y)
		hint.Size = UDim2.new(hint.Size.X, UDim.new(HINT_H, 0))
		--- It is the line that wraps, and the kit authored it that way. Asserted rather than trusted,
		--- because `TextWrapped = false` quietly clears `TextScaled`.
		hint.TextWrapped = true
		hint.TextScaled = true

		--[[ The stamp is the hint's type, centred and green, so it is the kit's face, rim and size cap
			without a style of its own to keep in step. ]]
		local done = hint:Clone()
		done.Name = DONE_NAME
		done.Text = DONE_PLACEHOLDER
		done.TextColor3 = DONE_COLOR
		done.TextXAlignment = Enum.TextXAlignment.Center
		done.Position = UDim2.fromScale(0.5, DONE_Y)
		done.Size = UDim2.new(hint.Size.X, UDim.new(DONE_H, 0))
		done.ZIndex = hint.ZIndex + 1
		done.Visible = false
		local doneCap = done:FindFirstChildOfClass("UITextSizeConstraint")
		if doneCap then
			doneCap.MaxTextSize = TEXT_CAP
		end
		done.Parent = main

		--[[ NOTHING ON THE CARD TAKES INPUT. The kit's buttons are gone above; this is the rest of the
			rule, stated rather than left to each class's default, because an Active frame over a race
			sinks a touch meant for the pedal under it. ]]
		for _, object in panel:GetDescendants() do
			if object:IsA("GuiObject") then
				object.Active = false
			end
		end
		panel.Active = false

		-- === The group ======================================================
		local width = aspect + 2 * MARGIN_SIDE
		local height = 1 + MARGIN_TOP + MARGIN_BOTTOM

		local card = Instance.new("CanvasGroup")
		card.Name = ENTRY_NAME
		card.BackgroundTransparency = 1
		card.BorderSizePixel = 0
		--- Top-left, because `_place` writes the card's top-left corner in pixels.
		card.AnchorPoint = Vector2.new(0, 0)
		--- The resting corner, so a shelf ticked visible shows the card where a player first sees it.
		--- Left since 2026-10-06 (`TutorialConfig.CardSide`); the controller overwrites it either way.
		card.Position = UDim2.fromScale(0.017, 0.1)
		--- Width-led; the height scale is only a ceiling the aspect never reaches. See the header.
		card.Size = UDim2.fromScale(CARD_WIDTH, 1)
		card.GroupTransparency = 0
		card.Active = false

		local cardAspect = Instance.new("UIAspectRatioConstraint")
		cardAspect.AspectRatio = width / height
		cardAspect.AspectType = Enum.AspectType.FitWithinMaxSize
		cardAspect.DominantAxis = Enum.DominantAxis.Width
		cardAspect.Parent = card

		panel.AnchorPoint = Vector2.new(0.5, 1)
		panel.Position = UDim2.fromScale(0.5, 1 - MARGIN_BOTTOM / height)
		panel.Size = UDim2.fromScale(aspect / width, 1 / height)
		panel.Parent = card

		card.Parent = shelf

		out:print(string.format("Built %s.%s.%s from the kit's %s.", SCREEN_NAME, SHELF_NAME, ENTRY_NAME, KIT_FRAME))
		out:print(
			string.format(
				"`%s` -> `%s`, `Main.%s` -> `Main.%s`, `Main.%s` added. Removed: %s. Card %.2f of the screen wide at %.3f:1 (panel %.3f:1 inside its margins).",
				KIT_SPEAKER,
				OBJECTIVE_NAME,
				KIT_BODY_TEXT,
				HINT_NAME,
				DONE_NAME,
				if #removed > 0 then table.concat(removed, ", ") else "nothing (the kit had changed)",
				CARD_WIDTH,
				width / height,
				aspect
			)
		)

		pcall(function()
			props:SetSelection({ card })
		end)
	end,
} :: Types.ScriptModule
