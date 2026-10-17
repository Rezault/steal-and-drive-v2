--[[
	BuildCarDetailV2: Command Runner command

	Adds the DETAIL WINGS to both of the new UI's car screens — `MainUIV2.Pages.Dealership` (the cars
	inventory) and `MainUIV2.Pages.StartCar` (the car picker) — and the halo to each one's card.

	Run `BuildDealershipV2` and `BuildStartCarV2` first: this fills in pages that already exist. Both
	of those call `Panel` themselves at the end of their own run, so a page rebuild keeps its wings
	and this command is the one to run when only the PANEL has changed.

	The shape, the arithmetic and every part harvested are in `Panel`'s header; the behaviour is
	`Components/CarDetailV2` and the switches are `CarDetailConfig`. Nothing here decides anything —
	it is the two page lookups and the report.

	Safe to re-run: `Panel.build` destroys the wings it finds before it makes its own.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)
local Panel = require(script.Panel)
local StartCarConfig = require(ReplicatedStorage.shared.Configs.StartCarConfig)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName

--- The two car screens, in the order the player meets them.
local PAGES = { "Dealership", StartCarConfig.PageName }

return {
	Description = "Add the car detail wings (a turning car and its name on the left, its four stats and the verb on the right) to MainUIV2's cars inventory and car picker, plus the selected-card halo. Re-runnable; BuildDealershipV2 and BuildStartCarV2 call the same builder themselves.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local pages = screen and screen:FindFirstChild("Pages")
		if not (pages and pages:IsA("GuiObject")) then
			out:error(string.format("No StarterGui.%s.Pages. Run BuildMainUIV2 first.", SCREEN_NAME))
			return
		end

		local built = {}
		for _, name in PAGES do
			local page = pages:FindFirstChild(name)
			if not (page and page:IsA("GuiObject")) then
				out:warn(string.format("No `%s` page. Run Build%sV2 first; the other page is unaffected.", name, name))
				continue
			end

			local ok, message = Panel.build(page)
			if ok then
				out:print(message)
				table.insert(built, page)
			else
				out:error(message)
			end
		end

		if #built == 0 then
			return
		end

		pcall(function()
			props:SetSelection(built)
		end)
	end,
} :: Types.ScriptModule
