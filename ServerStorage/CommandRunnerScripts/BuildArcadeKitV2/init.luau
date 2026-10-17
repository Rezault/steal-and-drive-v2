--[[
	BuildArcadeKitV2: Command Runner command

	Builds `StarterGui.MainUIV2.Screens.ArcadeKit`, a folder of the Cartoony Kit's own parts that
	`Modules/ArcadeKit` clones on the client. Run `BuildMainUIV2` first: this fills in a shelf that
	already exists. `Screens.ArcadeKit` is destroyed and made again on every run, and nothing else on
	the shelf is touched.

	=== WHY THIS EXISTS, 2026-10-12 ===========================================================

	The small cards built in code (the daily reward days, NEW CAR DISCOVERED, the rare-car banner, the
	sale tag, the upgrade banner, "While you were driving") were all drawn from a hand-made imitation of
	the kit: a flat gradient, a 12-cell checker made of white Frames across the top, pixel strokes. Next
	to the real kit pages they read as a different game (Dylan, after a playtest: "the UIs that are made
	in code are just... something off. Maybe it's the slice or the checkers"). It was both: the kit's
	checker is a TEXTURE under a dark tint with a sunray over it, and its rims are two ScaledSize
	strokes, white inside navy, that no pixel stroke reproduces at every size.

	So the parts come from the kit itself, and the client only places them:

	    Card        DailyRewardsUI's day card: gradient, white and navy rims, the checker texture and
	                the sunray in a CanvasGroup. Text, icon and buttons stripped.
	    Panel       PromptUI: the panel, its header title and the white `Main` body. The question and
	                both buttons stripped, the close button stripped.
	    Claim       the green button (the day card's ClaimBtn), with its Container rims and slash.
	    Disabled    the grey one (a Frame, the kit's own "cannot press").
	    Decline     PromptUI's pink-to-red button.
	    Heading     the day card's "Day 1" line: white type under the kit's gold gradient.
	    Label       the day card's title line: white type, navy ScaledSize outline.
	    ProgressBar QuestsUI's bar: grey track, blue fill, both rims.

	Every `UIButton` tag is removed (a part on a shelf is not a button anyone presses; the caller
	decides), and so is every `UITextSizeConstraint` (the kit's caps are 1080p pixels and these parts
	land in boxes of every size, BillboardGuis included, where a cap is wrong at every distance).
]]

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SHELF_NAME = "Screens"
local KIT_NAME = "ArcadeKit" -- Modules/ArcadeKit's folder on the shelf
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage
local BUTTON_TAG = "UIButton" -- Components/Button

local function walk(root: Instance, path: { string }): Instance?
	local node: Instance? = root
	for _, step in path do
		node = node and node:FindFirstChild(step)
	end
	return node
end

--- The kit's frame container, or nil and why.
local function findContainer(): (Instance?, string?)
	local node = walk(ServerStorage, TEMPLATE_PATH)
	if not node then
		return nil, "ServerStorage." .. table.concat(TEMPLATE_PATH, ".") .. " is missing"
	end
	local screen = node:FindFirstChildWhichIsA("ScreenGui")
	local container = screen and screen:FindFirstChild("Container")
	if not container then
		return nil, node:GetFullName() .. " holds no ScreenGui with a Container"
	end
	return container, nil
end

--- A clone with no button tags and no text caps, positioned at the origin, visible.
local function take(source: Instance, name: string): GuiObject
	local part = source:Clone() :: GuiObject
	part.Name = name
	part.Visible = true
	part.AnchorPoint = Vector2.new(0.5, 0.5)
	part.Position = UDim2.fromScale(0.5, 0.5)
	for _, item in { part, table.unpack(part:GetDescendants()) } do
		if CollectionService:HasTag(item, BUTTON_TAG) then
			CollectionService:RemoveTag(item, BUTTON_TAG)
		end
		if item:IsA("UITextSizeConstraint") then
			item:Destroy()
		end
	end
	return part
end

local function strip(parent: Instance, names: { string })
	for _, name in names do
		local child = parent:FindFirstChild(name)
		if child then
			child:Destroy()
		end
	end
end

return {
	Description = "Build StarterGui.MainUIV2.Screens.ArcadeKit: the Cartoony Kit's day card, prompt panel, buttons, heading type and progress bar, for Modules/ArcadeKit to clone into the cards built in code. Rebuilds every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local shelf = screen and screen:FindFirstChild(SHELF_NAME)
		if not shelf then
			out:error(string.format("No StarterGui.%s.%s. Run BuildMainUIV2 first.", SCREEN_NAME, SHELF_NAME))
			return
		end
		local container, why = findContainer()
		if not container then
			out:error("The kit is not where it should be: " .. tostring(why))
			return
		end

		local day = walk(container, { "DailyRewardsUI", "Main", "TopRow", "Template" })
		local prompt = container:FindFirstChild("PromptUI")
		local decline = prompt and walk(prompt, { "Main", "Btns", "DeclineBtn" })
		local questRow = walk(container, { "QuestsUI", "Main" })
		local bar = questRow and questRow:FindFirstChild("ProgressBar", true)
		local missing = {}
		for label, item in { ["DailyRewardsUI day Template"] = day, PromptUI = prompt, ["PromptUI DeclineBtn"] = decline, ["QuestsUI ProgressBar"] = bar } do
			if not item then
				table.insert(missing, label)
			end
		end
		if #missing > 0 then
			out:error("The kit is missing: " .. table.concat(missing, ", "))
			return
		end

		local existing = shelf:FindFirstChild(KIT_NAME)
		if existing then
			existing:Destroy()
		end
		local folder = Instance.new("Folder")
		folder.Name = KIT_NAME

		-- The day card, bare: its chassis and its BG (checker + sunray).
		local card = take(day :: Instance, "Card")
		card.Size = UDim2.fromScale(0.15, 0.35)
		strip(card, { "Text", "Icon", "Btns" })
		card.Parent = folder

		-- The prompt panel: header title and the white body, nothing in the body.
		local panel = take(prompt :: Instance, "Panel")
		local header = panel:FindFirstChild("Header")
		if header then
			strip(header, { "CloseBtn" })
		end
		local main = panel:FindFirstChild("Main")
		if main then
			strip(main, { "Btns", "Title" })
		end
		strip(panel, { "UIAspectRatioConstraint" })
		panel.Parent = folder

		-- The buttons and the type, lifted off the day card (a fresh copy, not the stripped one).
		local buttons = (day :: Instance):FindFirstChild("Btns")
		local claim = buttons and buttons:FindFirstChild("ClaimBtn")
		local disabled = buttons and buttons:FindFirstChild("DisabledBtn")
		local text = (day :: Instance):FindFirstChild("Text")
		local heading = text and text:FindFirstChild("Day")
		local label = text and text:FindFirstChild("Title")
		for name, source in { Claim = claim, Disabled = disabled, Decline = decline, Heading = heading, Label = label, ProgressBar = bar } do
			if source then
				local part = take(source, name)
				part.Size = UDim2.fromScale(0.15, 0.06)
				part.Parent = folder
			else
				out:warn("No kit source for " .. name)
			end
		end

		folder.Parent = shelf
		local names = {}
		for _, child in folder:GetChildren() do
			table.insert(names, child.Name)
		end
		table.sort(names)
		out:print(string.format("Built %s.%s.%s: %s.", SCREEN_NAME, SHELF_NAME, KIT_NAME, table.concat(names, ", ")))
	end,
} :: Types.ScriptModule
