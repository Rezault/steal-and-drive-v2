--[[
	BuildRaceResultsV2: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.RaceResults`, the race results panel, out of the Cartoony
	Kit's `MatchLeaderboardUI`. Phase 4 of `docs/NewUI-Migration-Plan.md`; the running record is
	`docs/NewUI-Migration-Notes.md` ("Race results").

	Run `BuildMainUIV2` first: this fills in a shelf that already exists rather than creating one.
	`Screens.RaceResults` is destroyed and made again on every run, and nothing else on the shelf is
	touched, so it is safe beside the other Phase 4 commands and safe to re-run.

	=== A TEMPLATE, NOT A SCREEN ==============================================================

	Nothing draws this frame where it is built. `RaceUIController` clones it into its own
	`RaceTransition` ScreenGui, over the black of the return fade, which is where the shipping
	results have always been drawn. The fade, the spinner, the loading bar and the bust lights stay
	that controller's own and are not in here: this is only the panel the results are READ on. So the
	geometry below is the geometry of that ScreenGui, full screen with `IgnoreGuiInset = true`.

	=== WHAT THE KIT DREW, AND WHAT EACH PART BECOMES =========================================

	`MatchLeaderboardUI` is a header, a white card, a strip of two team pills across the top of the
	card, and two scrolling columns of player rows under it (a placement, an avatar, a name and a
	kill count on a blue card for one team and a pink card for the other). A race here has one
	player and three ways to end, so:

	  • THE HEADER is the headline, `STOLEN`, `WRECKED` or `BUSTED`, which the shipping screen already
	    printed as its one loud word. The X goes: the results have always held themselves up and
	    let themselves down, and a close button is a control nothing is behind.
	  • THE PILL STRIP becomes the LADDER, the shipping screen's progress bar, because it sits where
	    that bar sat (between the headline and the numbers) and a team caption has nothing to caption.
	    The track is the kit's own progress bar, lifted out of `QuestsUI`, with the tick container
	    and the car glyph (`UIAssets.Results.CarMarker`, tinted per ending by the controller) over it.
	  • THE LEFT COLUMN becomes the SHOWCASE: one player card, blown up to fill the column, with the
	    car standing in it (the trophy box holds the viewport; the sunburst turns in the card's own `BG`
	    group and the smoke rises in a `Plume` group, so both clip to the card).
	  • THE RIGHT COLUMN becomes the RECEIPTS: four rows cut from the same player card, `Cash`,
	    `Distance`, `Bonus` and `Level`. The name line is the `Figure` and the kill count is the
	    `Caption`; the placement and the avatar go, because there is no rank and no face to show.

	=== THE TWO TEAM COLOURS ARE THE TWO ENDINGS ==============================================

	The artist drew team one on a cyan-to-blue card and team two on a pink-to-red one. Those are the
	shipping screen's green and amber in the kit's palette: blue for a car you kept, red for a run
	that ended in a crash or a bust. Both ramps are parked on the root as `ColorSequence`
	attributes (`BankColor`, `CrashColor`), with the solid end of each (`BankTint`, `CrashTint`) for
	the car glyph, so the controller repaints the showcase, the rows and the ladder's fill from the
	art rather than from numbers of its own. Same trick as the Quest page's `DoneColor`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local ENTRY_NAME = "RaceResults"
local KIT_FRAME = "MatchLeaderboardUI"
local BAR_FRAME = "QuestsUI" -- where the kit's progress bar is drawn

local NBSP = utf8.char(0xA0)

--[[ The panel over the black. A little larger than the kit draws it: this is the one screen in the
	loop the player is looking at nothing else for, and it holds a car. The kit's aspect constraint
	(1.475:1) is kept, so the height binds on every landscape screen. ]]
local PANEL_SIZE = UDim2.fromScale(0.7, 0.66)

--[[ The card, top to bottom, in its own scale. The kit's pill strip was 0.027 to 0.133 and its
	columns 0.152 to 1.0; the strip is taller here because a car has to stand on the bar in it, and
	the columns stop short of the card's foot so the showcase card has a margin like its sides. ]]
local LADDER_Y, LADDER_HEIGHT = 0.1, 0.15
local COLUMN_BOTTOM, COLUMN_HEIGHT = 0.975, 0.775

--- Inside the ladder strip: the track along its lower half, the car standing on the track's top edge.
local TRACK_Y, TRACK_WIDTH, TRACK_HEIGHT = 0.8, 0.92, 0.22
local TICKS_HEIGHT = 2.1 -- of the track's height, so a tick stands a little proud of it
local MARKER_HEIGHT = 0.62 -- of the strip

--- The showcase card inside its column, and the trophy box inside the card.
local CARD_SIZE = UDim2.fromScale(0.97, 0.99)
local CARD_CORNER = UDim.new(0.06, 0) -- the kit row's 0.15 is a pill on a card this size
local TROPHY_REST = 0.92 -- `RaceUIController` reads this off the box as the size the car lands at
local SUNBURST_SCALE = 1.25

--- The receipts: row height and gap as fractions of the column, stacked from the middle.
local ROW_HEIGHT, ROW_GAP = 0.2, 0.04
local ROW_NAMES = { "Cash", "Distance", "Bonus", "Level" }
local ROW_PLACEHOLDER = {
	Cash = { "+$1,234", "Payout" },
	Distance = { "2,140m", "Driven" },
	Bonus = { "+$78", "7" .. NBSP .. "near" .. NBSP .. "misses" },
	Level = { "Level" .. NBSP .. "4", "Camaro" },
}
local FIGURE_MAX_TEXT = 40
local CAPTION_MAX_TEXT = 28

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

--- A bare, transparent frame at a rect in its parent's scale.
local function holder(name: string, parent: Instance, anchor: Vector2, position: UDim2, size: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = anchor
	frame.Position = position
	frame.Size = size
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

--- A kit player card with the leaderboard's parts taken off it: no placement, no avatar.
local function bareCard(source: Instance): Frame
	local card = source:Clone() :: Frame
	for _, name in { "Placement", "Avatar" } do
		local child = card:FindFirstChild(name)
		if child then
			child:Destroy()
		end
	end
	return card
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.RaceResults from the Cartoony Kit's MatchLeaderboardUI: the headline in the header, the ladder in the pill strip, the car in a showcase card and the payout in four receipt rows. Rebuilds the entry every run.",
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
		local barFrame = container:FindFirstChild(BAR_FRAME)
		if not (kitFrame and barFrame) then
			out:error(string.format("%s needs both `%s` and `%s` to build from.", container:GetFullName(), KIT_FRAME, BAR_FRAME))
			return
		end

		local questList = barFrame:FindFirstChild("Main") and barFrame.Main:FindFirstChildOfClass("ScrollingFrame")
		local questRow = questList and questList:FindFirstChild("Template")
		local kitBar = questRow and questRow:FindFirstChild("ProgressBar")
		if not (kitBar and kitBar:FindFirstChild("Progress")) then
			out:error(string.format("The kit's %s has no `Main.ScrollingFrame.Template.ProgressBar.Progress` to lift the ladder's track from.", BAR_FRAME))
			return
		end

		local panel = kitFrame:Clone() :: Frame
		local header = panel:FindFirstChild("Header")
		local main = panel:FindFirstChild("Main")
		local strip = main and main:FindFirstChild("TeamHeaders")
		local team1 = main and main:FindFirstChild("Team1")
		local team2 = main and main:FindFirstChild("Team2")
		local blueCard = team1 and team1:FindFirstChild("1")
		local redCard = team2 and team2:FindFirstChild("1")
		local title = header and header:FindFirstChild("Title")
		if not (strip and team1 and team2 and blueCard and redCard and title) then
			out:error(string.format("The kit's %s is not the shape this command expects (Header.Title, Main.TeamHeaders, Main.Team1/Team2 with a row `1` each).", KIT_FRAME))
			panel:Destroy()
			return
		end

		local blueRamp = blueCard:FindFirstChildOfClass("UIGradient")
		local redRamp = redCard:FindFirstChildOfClass("UIGradient")
		if not (blueRamp and redRamp) then
			out:error("The kit's team cards carry no UIGradient; there are no ending colours to harvest.")
			panel:Destroy()
			return
		end
		--[[ A copy of the player card taken BEFORE either column is destroyed. Every card below is cut
			from this one: `Destroy` empties an instance's children, so a card cloned from the column
			after it went comes out as a bare Frame with nothing in it (it did, the first run). ]]
		local cardSource = blueCard:Clone()

		local existing = shelf:FindFirstChild(ENTRY_NAME)
		if existing then
			existing:Destroy()
		end

		panel.Name = ENTRY_NAME
		panel.Visible = true -- the shelf is what is hidden
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromScale(0.5, 0.5)
		panel.Size = PANEL_SIZE

		--[[ The two endings, off the artist's two teams. The tint is the ramp's last stop, the deep
			end, because the car glyph is a flat silhouette and the light end of either ramp washes out
			on the white card. ]]
		local blueKeys, redKeys = blueRamp.Color.Keypoints, redRamp.Color.Keypoints
		panel:SetAttribute("BankColor", blueRamp.Color)
		panel:SetAttribute("CrashColor", redRamp.Color)
		panel:SetAttribute("BankTint", blueKeys[#blueKeys].Value)
		panel:SetAttribute("CrashTint", redKeys[#redKeys].Value)

		-- The headline. No X: see the header.
		local close = header:FindFirstChild("CloseBtn")
		if close then
			close:Destroy()
		end
		title.Text = "STOLEN"

		-- === The ladder, in the pill strip's place ========================================
		local ladder = holder("Ladder", main, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, LADDER_Y), UDim2.fromScale(strip.Size.X.Scale, LADDER_HEIGHT))
		ladder.ZIndex = strip.ZIndex
		strip:Destroy()

		local track = kitBar:Clone() :: Frame
		track.Name = "Track"
		track.AnchorPoint = Vector2.new(0.5, 0.5)
		track.Position = UDim2.fromScale(0.5, TRACK_Y)
		track.Size = UDim2.fromScale(TRACK_WIDTH, TRACK_HEIGHT)
		track.ZIndex = 1
		track.Parent = ladder

		local fill = track:FindFirstChild("Progress") :: Frame
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0.62, 1) -- a placeholder the controller overwrites

		local ticks = holder("Ticks", ladder, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, TRACK_Y), UDim2.fromScale(TRACK_WIDTH, TRACK_HEIGHT * TICKS_HEIGHT))
		ticks.ZIndex = 2

		local marker = Instance.new("ImageLabel")
		marker.Name = "Marker"
		marker.AnchorPoint = Vector2.new(0.5, 1)
		marker.Position = UDim2.fromScale(0.5 - TRACK_WIDTH / 2 + TRACK_WIDTH * 0.62, TRACK_Y - TRACK_HEIGHT / 2)
		-- Full width on purpose: the aspect constraint fits the glyph INSIDE the box, and the height binds.
		marker.Size = UDim2.fromScale(1, MARKER_HEIGHT)
		marker.BackgroundTransparency = 1
		marker.ImageColor3 = blueKeys[#blueKeys].Value
		marker.ZIndex = 3
		local ok, UIAssets = pcall(require, ReplicatedStorage.shared.Configs.UIAssets)
		if ok then
			marker.Image = UIAssets.url(UIAssets.Results.CarMarker)
			local aspect = Instance.new("UIAspectRatioConstraint")
			aspect.AspectRatio = UIAssets.ResultsSize.CarMarker.X / UIAssets.ResultsSize.CarMarker.Y
			aspect.Parent = marker
		else
			out:warn("Could not read UIAssets; the marker is left without its image (the controller sets it at runtime).")
		end
		marker.Parent = ladder

		-- === The showcase, in the left column's place ======================================
		local showcase = holder(
			"Showcase",
			main,
			Vector2.new(0.5, 1),
			UDim2.fromScale(team1.Position.X.Scale, COLUMN_BOTTOM),
			UDim2.fromScale(team1.Size.X.Scale, COLUMN_HEIGHT)
		)

		local card = bareCard(cardSource)
		card.Name = "Card"
		local text = card:FindFirstChild("Text")
		if text then
			text:Destroy()
		end
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
		card.Size = CARD_SIZE
		card.ClipsDescendants = true -- the car's landing overshoots its box; the turning art clips in groups below
		local cardCorner = card:FindFirstChildOfClass("UICorner")
		if cardCorner then
			cardCorner.CornerRadius = CARD_CORNER
		end
		local bg = card:FindFirstChild("BG")
		local bgCorner = bg and bg:FindFirstChildOfClass("UICorner")
		if bgCorner then
			bgCorner.CornerRadius = CARD_CORNER
		end

		--[[ THE KIT SIZES A CARD'S OUTLINE AND CHECKER OFF THE CARD, and this card is about five rows
			tall. Both strokes are `ScaledSize` and the checker is a multiple of its frame, so left as
			authored the outline came out a black band five times the row's and one checker cell grew
			to the size of the car, which read as a box drawn behind it. Measured in the first flag-on
			playtest. Shrunk by the row-to-card height ratio, both land back on the row's own weight. ]]
		local shrink = (cardSource.Size.Y.Scale * team1.Size.Y.Scale) / (CARD_SIZE.Y.Scale * COLUMN_HEIGHT)
		for _, child in card:GetChildren() do
			if child:IsA("UIStroke") then
				child.Thickness *= shrink
			end
		end
		local checker = bg and bg:FindFirstChild("CheckersBG")
		if checker and checker:IsA("GuiObject") then
			checker.Size = UDim2.fromScale(checker.Size.X.Scale, checker.Size.Y.Scale * shrink)
		end
		card.Parent = showcase

		-- The trophy box: square, sized off the card's shorter side, exactly as the shipping box is.
		local trophy = holder("Trophy", card, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(TROPHY_REST, TROPHY_REST))
		trophy.ZIndex = 2
		local trophyAspect = Instance.new("UIAspectRatioConstraint")
		trophyAspect.AspectRatio = 1
		trophyAspect.Parent = trophy

		--[[ THE BURST LIVES IN THE CARD'S OWN `BG` CANVASGROUP, over the checker and under the car.
			It turns, and `ClipsDescendants` does not clip a rotated descendant, so parented to the box
			its rays leaked past the card on both ends (seen in the flag-on playtest). A CanvasGroup
			renders to a texture and clips to its `UICorner`, so the rays stop exactly at the card's
			rounded edge. The cost is that group redrawing while it turns, on the banked screen only. ]]
		local burst = Instance.new("ImageLabel")
		burst.Name = "Sunburst"
		burst.AnchorPoint = Vector2.new(0.5, 0.5)
		burst.Position = UDim2.fromScale(0.5, 0.5)
		burst.Size = UDim2.fromScale(SUNBURST_SCALE * TROPHY_REST, SUNBURST_SCALE * TROPHY_REST)
		burst.BackgroundTransparency = 1
		burst.ZIndex = 2
		if ok then
			burst.Image = UIAssets.url(UIAssets.Results.Sunburst)
		end
		local burstAspect = Instance.new("UIAspectRatioConstraint")
		burstAspect.AspectRatio = 1
		burstAspect.Parent = burst
		burst.Parent = if bg then bg else trophy

		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "Car"
		viewport.AnchorPoint = Vector2.new(0.5, 0.5)
		viewport.Position = UDim2.fromScale(0.5, 0.5)
		viewport.Size = UDim2.fromScale(1, 1)
		viewport.BackgroundTransparency = 1
		viewport.BorderSizePixel = 0
		viewport.ZIndex = 2
		viewport.Parent = trophy

		--[[ THE PLUME GETS A GROUP OF ITS OWN, for the burst's reason: every puff turns as it rises,
			so `ClipsDescendants` let them drift out over the ladder as a grey smudge on the white card
			(seen in the second flag-on playtest). `Box` is the trophy box's rect, because the puffs are
			placed in the box's scales (`RaceUIController._buildSmoke`), and the group over the whole
			card clips them to its rounded edge. In front of the car, as on the overlay. ]]
		local plume = Instance.new("CanvasGroup")
		plume.Name = "Plume"
		plume.AnchorPoint = Vector2.new(0.5, 0.5)
		plume.Position = UDim2.fromScale(0.5, 0.5)
		plume.Size = UDim2.fromScale(1, 1)
		plume.BackgroundTransparency = 1
		plume.BorderSizePixel = 0
		plume.ZIndex = 3
		local plumeCorner = Instance.new("UICorner")
		plumeCorner.CornerRadius = CARD_CORNER
		plumeCorner.Parent = plume
		local plumeBox = holder("Box", plume, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(TROPHY_REST, TROPHY_REST))
		local plumeAspect = Instance.new("UIAspectRatioConstraint")
		plumeAspect.AspectRatio = 1
		plumeAspect.Parent = plumeBox
		plume.Parent = card

		team1:Destroy()

		-- === The receipts, in the right column's place =====================================
		local receipts = holder(
			"Receipts",
			main,
			Vector2.new(0.5, 1),
			UDim2.fromScale(team2.Position.X.Scale, COLUMN_BOTTOM),
			UDim2.fromScale(team2.Size.X.Scale, COLUMN_HEIGHT)
		)
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(ROW_GAP, 0)
		layout.Parent = receipts

		for index, name in ROW_NAMES do
			local row = bareCard(cardSource)
			row.Name = name
			row.LayoutOrder = index
			row.AnchorPoint = Vector2.new(0.5, 0.5)
			row.Size = UDim2.fromScale(cardSource.Size.X.Scale, ROW_HEIGHT)

			local lines = row:FindFirstChild("Text")
			local figure = lines and lines:FindFirstChild("Username")
			local caption = lines and lines:FindFirstChild("Kills")
			if not (lines and figure and caption) then
				out:warn(string.format("The kit's player card has no Text.Username/Kills; row `%s` has no lines.", name))
			else
				-- The text now runs the width of the card, where it used to start after the avatar.
				lines.Position = UDim2.fromScale(0.06, 0)
				lines.Size = UDim2.fromScale(0.9, 1)
				figure.Name = "Figure"
				caption.Name = "Caption"
				figure.Text = ROW_PLACEHOLDER[name][1]
				caption.Text = ROW_PLACEHOLDER[name][2]
				local figureLimit = figure:FindFirstChildOfClass("UITextSizeConstraint")
				if figureLimit then
					figureLimit.MaxTextSize = FIGURE_MAX_TEXT
				end
				local captionLimit = caption:FindFirstChildOfClass("UITextSizeConstraint")
				if captionLimit then
					captionLimit.MaxTextSize = CAPTION_MAX_TEXT
				end
			end
			row.Parent = receipts
		end

		team2:Destroy()
		cardSource:Destroy()

		panel.Parent = shelf

		out:print(
			string.format(
				"Built %s.%s.%s from the kit's %s: Ladder (track from %s), Showcase with its Trophy box, Receipts rows %s. Ending colours parked on the root as BankColor/CrashColor/BankTint/CrashTint.",
				SCREEN_NAME,
				SHELF_NAME,
				ENTRY_NAME,
				KIT_FRAME,
				BAR_FRAME,
				table.concat(ROW_NAMES, ", ")
			)
		)
		pcall(function()
			props:SetSelection({ panel })
		end)
	end,
} :: Types.ScriptModule
