--[[
	BuildDailyRewardsV2: Command Runner command

	Builds `StarterGui.MainUIV2.Pages.DailyRewards` (`DailyRewardConfig.PageName`) for
	`PagesV2/DailyRewards`, BY COPYING THE BUILT QUEST BOARD (`Pages.Quest`, from `BuildQuestV2`).

	WHY A COPY OF THE QUEST BOARD AND NOT A FRESH CUT OF THE KIT. The daily reward is the same kind of
	screen — a list of cards, each with a reward, a green CLAIM or a grey disabled button, and a clock
	under the panel — and the quest board is that screen already finished: the kit's `QuestsUI` cut
	down, the cards wrapped for their outros, the footer measured, `KitGrowth` applied. Copying it means
	the two screens are the same art to the pixel and a re-skin of one is a re-run of this for the other,
	instead of two builders that drift. So: run `BuildQuestV2` first; this refuses without it.

	WHAT CHANGES ON THE COPY:
	  • `Main.CategoryBtns` (Daily / Weekly / Monthly / All Time) is removed — a calendar has no tabs —
	    and the list is stretched up into the space it left, bottom edge unchanged.
	  • The header says DAILY REWARDS and the footer's placeholder reads as this screen's clock.
	Everything else (rows, buttons, note, spacer, footer) is the quest board's, unchanged.

	`Pages.DailyRewards` is destroyed and made again on every run; nothing else is touched.
]]

local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local SOURCE_PAGE = "Quest" -- QuestConfig.PageName, built by BuildQuestV2
local PAGE_NAME = "DailyRewards" -- DailyRewardConfig.PageName
local CATEGORY_STRIP = "CategoryBtns"
local TITLE_TEXT = "DAILY REWARDS"
local FOOTER_PLACEHOLDER = "Next reward in 12h 0m 0s"

--- A GuiObject's top and bottom edges in its parent's Y scale, anchor included (`BuildQuestV2`'s).
local function span(gui: GuiObject): (number, number)
	local top = gui.Position.Y.Scale - gui.AnchorPoint.Y * gui.Size.Y.Scale
	return top, top + gui.Size.Y.Scale
end

return {
	Description = "Build StarterGui.MainUIV2.Pages.DailyRewards as a copy of the built Quest page (run BuildQuestV2 first): tabs removed, list stretched into their space, retitled. Rebuilds the page every run.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, _arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local pages = screen and screen:FindFirstChild("Pages")
		if not pages then
			out:error(string.format("No StarterGui.%s.Pages. Run BuildMainUIV2 first.", SCREEN_NAME))
			return
		end
		local source = pages:FindFirstChild(SOURCE_PAGE)
		if not (source and source:IsA("GuiObject")) then
			out:error(string.format("No %s.Pages.%s to copy. Run BuildQuestV2 first.", SCREEN_NAME, SOURCE_PAGE))
			return
		end

		local existing = pages:FindFirstChild(PAGE_NAME)
		if existing then
			existing:Destroy()
		end

		local page = source:Clone()
		page.Name = PAGE_NAME
		page.Visible = false

		local header = page:FindFirstChild("Header", true)
		local title = header and header:FindFirstChild("Title")
		if title and title:IsA("TextLabel") then
			title.Text = TITLE_TEXT
		else
			out:warn("No Header.Title on the copy; the page will title itself at runtime.")
		end

		--- The tabs out, and the list up into their space with its bottom edge where it was.
		local main = page:FindFirstChild("Main")
		local strip = main and main:FindFirstChild(CATEGORY_STRIP)
		local list = main and main:FindFirstChildWhichIsA("ScrollingFrame")
		if strip and strip:IsA("GuiObject") and list then
			local stripTop = span(strip)
			local _, listBottom = span(list)
			local height = listBottom - stripTop
			list.Size = UDim2.new(list.Size.X, UDim.new(height, 0))
			list.Position = UDim2.new(list.Position.X, UDim.new(stripTop + list.AnchorPoint.Y * height, 0))
			strip:Destroy()
		else
			out:warn(string.format("No Main.%s or list on the copy; left the layout as it was.", CATEGORY_STRIP))
		end

		local footer = page:FindFirstChild("TimeLeft")
		local clock = footer and footer:FindFirstChild("Label")
		if clock and clock:IsA("TextLabel") then
			clock.Text = FOOTER_PLACEHOLDER
		end

		page.Parent = pages
		out:print(string.format("Built %s.Pages.%s from Pages.%s: tabs removed, list stretched, retitled %s.", SCREEN_NAME, PAGE_NAME, SOURCE_PAGE, TITLE_TEXT))
		pcall(function()
			props:SetSelection({ page })
		end)
	end,
} :: Types.ScriptModule
