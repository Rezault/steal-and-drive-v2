--[[
	BuildRenameDealershipV2: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.RenameDealership`, the box a player names their dealership in,
	out of the Cartoony Kit's `CodesUI`. Phase 4 of `docs/NewUI-Migration-Plan.md`; the running record
	is `docs/NewUI-Migration-Notes.md`.

	Run `BuildMainUIV2` and `PrepKitTemplate` first. `Screens.RenameDealership` is destroyed and made
	again on every run, and nothing else on the shelf is touched, so this is safe beside the other
	Phase 4 commands.

	Nothing draws this where it is built. `Screens` is hidden, and `RenameController` clones the entry
	into a ScreenGui of its own at `DisplayOrder` 997, over a scrim it makes itself.

	`CodesUI` IS ALSO THE FRAME THE CODES FEATURE WILL USE. That is fine: this command clones it and
	edits the clone. The kit master is never renamed or touched, so do not "tidy" this into a move.

	=== THE KIT'S CODES SCREEN IS A RENAME BOX WITH ITS SOCIAL STRIP CHANGED ==================

	    CodesUI
	      Header{ Title, CloseBtn }
	      Main
	        XProfile{ BG, Avatar, Text{ Username, Desc }, Logo }   "find codes at @BespokeUI" and an X logo
	        Title                                                  the big sentence
	        CTAs{ Input{ TextBox }, RedeemBtn }                    a field and a green button, side by side
	      BG

	The shipping rename box has a title, a close, one sentence, a field with a character count under
	it, an answer line, SAVE and USE MY NAME. Every one of those has a place in that tree:

	  • THE STRIP BECOMES USE MY NAME. The kit's strip is a picture of a person, a small caption and a
	    big name, which is exactly what "put the sign back to my own name" needs to SAY: the player's
	    headshot, DEFAULT SIGN, and the title the sign will read if they press it. The X logo's slot
	    becomes the button. So the reset stops being a caption the player has to decode and becomes a
	    preview with a press on it.
	  • The sentence becomes the prompt (this name is public), set in the top half of the kit's band.
	  • The bottom half of that band becomes the ANSWER line, `Status`. It holds its space whether or
	    not it says anything, which is the shipping screen's rule: a message that pushed the buttons
	    down would move the thing the player is about to press.
	  • The field keeps the kit's box and gains `Count` at its right-hand end, inside the rim, where a
	    count belongs to the box rather than to the screen.
	  • `RedeemBtn` is SAVE, in the kit's green.

	=== WHAT IS RENAMED, AND WHY ==============================================================

	  • `XProfile` -> `Default`, `Text.Desc` -> `Text.Caption`, `Text.Username` -> `Text.SignName`,
	    `Avatar.ImageLabel` -> `Avatar.Headshot`: what each is now.
	  • `Main.Title` -> `Prompt`. `Title` is the header's word in every kit frame; two different
	    things called `Title` on one screen is a path nobody can read.
	  • `RedeemBtn` -> `SaveBtn`.

	=== WHAT IS ADDED =========================================================================

	  • `Default.ResetBtn`, a clone of `RedeemBtn` in the Logo's place, the same size as SAVE. It wears
	    the kit's orange (borrowed from `InventoryUI.TopBar.EquipBestBtn`, the kit's other shortcut
	    press), because green is SAVE's and a second green button reads as a second way to save.
	  • `Main.Status` and `CTAs.Input.Count`, both cloned from the kit's own type.

	=== WHAT IS REMOVED =======================================================================

	The Logo. The avatar keeps its ring and the strip keeps its colours.

	=== THE COPY IS PLACEHOLDER ===============================================================

	`RenameController` writes every string out of `PlotConfig.Rename` on every open, except the
	strip's caption, DEFAULT SIGN, which is authored here and nowhere else.
]]

local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local ENTRY_NAME = "RenameDealership"
local KIT_FRAME = "CodesUI"
local KIT_SHORTCUT_FRAME = "InventoryUI" -- where the orange face is borrowed from
local KIT_SHORTCUT_BUTTON = "EquipBestBtn"

local NBSP = utf8.char(0xA0) -- TextScaled wraps rather than shrinks

--[[ Where the panel stands, in the rename ScreenGui's full-screen space. The shipping box's own
	footprint (`PANEL_BOX` there): a text field is the one kit screen a phone player has to hit
	with a thumb and read while typing, so it gets more room than the kit's 0.42 of the height. The
	kit's `UIAspectRatioConstraint` is kept, so the height binds and the width follows. ]]
local PANEL_POSITION = UDim2.fromScale(0.5, 0.5)
local PANEL_SIZE = UDim2.fromScale(0.8, 0.5)

--[[ `Main`, top to bottom, in its own scale. The strip (0.07 to 0.31) and the field row (0.74 to
	0.93) are where the artist put them. The kit's sentence band (0.38 to 0.64) is split: the prompt
	takes its top half and the answer line its bottom half. ]]
local PROMPT_Y, PROMPT_HEIGHT = 0.43, 0.13
local STATUS_Y, STATUS_HEIGHT = 0.585, 0.1

--[[ The strip's name column, widened from the kit's 0.317 so a twenty-character dealership fits, and
	the reset button in the Logo's place.

	THE BUTTON IS SAVE'S SIZE. SAVE is 0.295 of a row as wide as the strip and exactly as tall as that
	row, which is 0.8 of the strip, so the two answers are one button twice. Its right margin is the
	same number of pixels as its top and bottom margins: 0.1 of the strip's height is 0.011 of its
	width, because `Main` is 2.32 times as wide as it is tall and the strip is 0.938 by 0.238 of it. ]]
local STRIP_TEXT_WIDTH = 0.52
local RESET_WIDTH, RESET_HEIGHT = 0.295, 0.8
local RESET_X = 1 - 0.011 - RESET_WIDTH / 2

--- The field's text and the count beside it, in the `Input` box's own scale.
local BOX_X, BOX_SIZE = 0.43, UDim2.fromScale(0.74, 0.56)
local COUNT_X, COUNT_SIZE = 0.88, UDim2.fromScale(0.17, 0.4)

--- The count and the placeholder are furniture rather than content: the shipping box's muted blue.
local MUTED = Color3.fromRGB(135, 146, 181)
local PLACEHOLDER = Color3.fromRGB(180, 188, 205)

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

--- Put a GuiObject centred at `y` in its parent with the given height, keeping its X.
local function band(gui: GuiObject, y: number, height: number)
	gui.AnchorPoint = Vector2.new(gui.AnchorPoint.X, 0.5)
	gui.Position = UDim2.new(gui.Position.X.Scale, gui.Position.X.Offset, y, 0)
	gui.Size = UDim2.new(gui.Size.X.Scale, gui.Size.X.Offset, height, 0)
end

local function caption(button: Instance, text: string)
	local title = button:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = text
	end
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.RenameDealership from the Cartoony Kit's CodesUI: the social strip becomes USE MY NAME with the player's headshot, the sentence splits into the prompt and an answer line, and the field gains a character count. Rebuilds the entry every run.",
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
		if not kitFrame then
			out:error(string.format("%s has no `%s` to build from.", container:GetFullName(), KIT_FRAME))
			return
		end

		local panel = kitFrame:Clone() :: GuiObject
		local header = panel:FindFirstChild("Header")
		local title = header and header:FindFirstChild("Title")
		local main = panel:FindFirstChild("Main")
		local strip = main and main:FindFirstChild("XProfile")
		local stripText = strip and strip:FindFirstChild("Text")
		local desc = stripText and stripText:FindFirstChild("Desc")
		local username = stripText and stripText:FindFirstChild("Username")
		local avatar = strip and strip:FindFirstChild("Avatar")
		local headshot = avatar and avatar:FindFirstChildOfClass("ImageLabel")
		local sentence = main and main:FindFirstChild("Title")
		local ctas = main and main:FindFirstChild("CTAs")
		local input = ctas and ctas:FindFirstChild("Input")
		local box = input and input:FindFirstChildOfClass("TextBox")
		local redeem = ctas and ctas:FindFirstChild("RedeemBtn")
		if
			not (
				title
				and title:IsA("TextLabel")
				and strip
				and stripText
				and desc
				and desc:IsA("TextLabel")
				and username
				and username:IsA("TextLabel")
				and headshot
				and sentence
				and sentence:IsA("TextLabel")
				and input
				and box
				and redeem
			)
		then
			out:error(
				string.format(
					"The kit's %s is not the shape this command expects (Header.Title, Main.XProfile{Avatar, Text{Desc, Username}}, Main.Title, Main.CTAs{Input.TextBox, RedeemBtn}).",
					KIT_FRAME
				)
			)
			panel:Destroy()
			return
		end

		local existing = shelf:FindFirstChild(ENTRY_NAME)
		if existing then
			existing:Destroy()
		end

		panel.Name = ENTRY_NAME
		panel.Visible = true -- the shelf is what is hidden; a template that is itself hidden would clone hidden
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = PANEL_POSITION
		panel.Size = PANEL_SIZE

		title.Text = "NAME" .. NBSP .. "YOUR" .. NBSP .. "DEALERSHIP"

		-- === The strip: USE MY NAME =============================================

		strip.Name = "Default"
		local logo = strip:FindFirstChild("Logo")
		if logo then
			logo:Destroy()
		end
		headshot.Name = "Headshot"
		stripText.Size = UDim2.new(STRIP_TEXT_WIDTH, 0, stripText.Size.Y.Scale, stripText.Size.Y.Offset)
		desc.Name = "Caption"
		desc.Text = "DEFAULT" .. NBSP .. "SIGN"
		username.Name = "SignName"
		username.Text = "Player's" .. NBSP .. "Dealership"

		local reset = redeem:Clone()
		reset.Name = "ResetBtn"
		reset.AnchorPoint = Vector2.new(0.5, 0.5)
		reset.Position = UDim2.fromScale(RESET_X, 0.5)
		reset.Size = UDim2.fromScale(RESET_WIDTH, RESET_HEIGHT)
		reset.ZIndex = math.max(reset.ZIndex, 2)
		caption(reset, "USE" .. NBSP .. "MY" .. NBSP .. "NAME")
		reset.Parent = strip

		local shortcut = container:FindFirstChild(KIT_SHORTCUT_FRAME)
		shortcut = shortcut and shortcut:FindFirstChild(KIT_SHORTCUT_BUTTON, true)
		local shortcutFace = shortcut and shortcut:FindFirstChildOfClass("UIGradient")
		local resetFace = reset:FindFirstChildOfClass("UIGradient")
		if shortcutFace and resetFace then
			resetFace.Color = shortcutFace.Color
		else
			out:warn(string.format("No %s.%s gradient to borrow; ResetBtn keeps SAVE's green.", KIT_SHORTCUT_FRAME, KIT_SHORTCUT_BUTTON))
		end

		-- === The sentence band: prompt and answer ===============================

		sentence.Name = "Prompt"
		sentence.Text = "Everyone on the plaza reads this off your sign."
		band(sentence, PROMPT_Y, PROMPT_HEIGHT)

		local status = sentence:Clone()
		status.Name = "Status"
		status.Text = "Sign updated."
		band(status, STATUS_Y, STATUS_HEIGHT)
		status.Parent = main

		-- === The field and SAVE =================================================

		box.Text = ""
		box.PlaceholderText = "Midnight Motors"
		box.PlaceholderColor3 = PLACEHOLDER
		--- Off, so a lot that already has a name opens with it in the box to be edited. The shipping
		--- box's reason: renaming is usually a tweak.
		box.ClearTextOnFocus = false
		box.MultiLine = false
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(BOX_X, 0.5)
		box.Size = BOX_SIZE

		local count = sentence:Clone()
		count.Name = "Count"
		count.Text = "0/20"
		count.TextColor3 = MUTED
		count.TextXAlignment = Enum.TextXAlignment.Right
		--- `TextScaled` stays on, and `TextWrapped` is left alone because writing it false switches
		--- `TextScaled` off (the Phase 5 device pass found the count stuck at 14px, spilling out of its
		--- box on a phone). "20/20" has no space, so there is nothing for a wrap to break on.
		count.TextScaled = true
		count.AnchorPoint = Vector2.new(0.5, 0.5)
		count.Position = UDim2.fromScale(COUNT_X, 0.5)
		count.Size = COUNT_SIZE
		count.Parent = input

		redeem.Name = "SaveBtn"
		caption(redeem, "SAVE")

		panel.Parent = shelf

		out:print(
			string.format(
				"Built %s.%s.%s from the kit's %s: Default{Headshot, Caption, SignName, ResetBtn (%s)}, Prompt, Status, CTAs{Input{TextBox, Count}, SaveBtn}.",
				SCREEN_NAME,
				SHELF_NAME,
				ENTRY_NAME,
				KIT_FRAME,
				if shortcutFace then "the kit's orange shortcut face" else "green, no shortcut face found"
			)
		)

		pcall(function()
			props:SetSelection({ panel })
		end)
	end,
} :: Types.ScriptModule
