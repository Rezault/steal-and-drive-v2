--[[
	BuildMainUIV2: Command Runner command

	Creates `StarterGui.MainUIV2`, the ScreenGui the Cartoony Kit UI is authored into, with the
	frames every other file expects to find in a UI: `HUD`, `Pages`, and the hidden `Screens` shelf
	the Phase 4 screens are authored on (see `SECTIONS`). See
	`docs/NewUI-Migration-Plan.md` (Phase 0) and `Configs/NewUIConfig`.

	=== WHY A COMMAND AND NOT A FEW MINUTES IN THE EXPLORER ===================================

	`StarterGui` is not Rojo-tracked, so anything built by hand exists only in whichever `.rbxl`
	somebody happened to save. This file is the record of what the screen is: re-runnable, in git, and
	readable by the next person who wonders why the insets are set the way they are.

	=== THE PROPERTIES THAT ARE DECISIONS =====================================================

	`IgnoreGuiInset = false` with `ScreenInsets = CoreUISafeInsets`, which is the kit's own setting
	and NOT `MainUI`'s (that one ignores the inset). The kit's 24 frames were laid out in that space,
	so matching it means a frame cloned out of the pack lands where the artist put it. Nothing is lost
	by the two UIs disagreeing: `TutorialController` already works in its own root's space and
	converts (`_place`), which is what lets its card sit correctly beside a button belonging to a
	different ScreenGui with different insets.

	`ResetOnSpawn = false`, like `MainUI`, because every page module and both HUD controllers resolve
	the UI once and assume it outlives a respawn.

	`DisplayOrder` matches `MainUI` so the new UI sits in the same layer of the stack the old one did,
	under the driving HUD (895) and the car HUD (900).

	IDEMPOTENT. An existing `MainUIV2` keeps its children and has its properties re-asserted, so this
	can be re-run after a hand edit without throwing away a page somebody has started.
]]

local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local LEGACY_NAME = "MainUI" -- NewUIConfig.LegacyScreenGuiName

--- The frames the rest of the project names by path: `HUD.Play`, `HUD.Cash`, `HUD.Rail`,
--- `Pages.<name>`, `Screens.<name>`. All full-screen and invisible; they are coordinate spaces, not art.
local SECTIONS = { "HUD", "Pages", "Screens" }

--[[ `Screens` IS A SHELF, NOT A LAYER (Phase 4, 2026-09-16). The screens that used to be built in
	code (the welcome back panel, the sell prompt, the revive question, the race results and the rest)
	are authored here so they can be edited in the Explorer, but none of them is SHOWN here. Each one's
	controller clones its template into a ScreenGui of its own at runtime, because each of those sits
	at its own `DisplayOrder` (the revive question under the race fade, the welcome back panel under
	both) and a frame inside this ScreenGui would share its one layer with the HUD.

	So the shelf is created hidden and nothing on it is ever drawn from here. Tick it visible to author
	a template, and leave it how you like: a re-run keeps an existing frame as it is. It also hides
	from `GamepadNav`, which only walks `HUD` and `Pages`, and it goes with the rest of this ScreenGui
	when the flag is off, so no old-UI code path can ever find a template. ]]
local HIDDEN_SECTIONS = { Screens = true }

local function section(parent: Instance, name: string): (Frame, boolean)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Frame") then
		return existing, false
	end
	if existing then
		existing:Destroy() -- a StringValue or a Folder called HUD is not a coordinate space
	end

	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Visible = not HIDDEN_SECTIONS[name]
	frame.Parent = parent
	return frame, true
end

return {
	Description = "Create StarterGui.MainUIV2, the ScreenGui the Cartoony Kit UI is authored into, with empty HUD, Pages and Screens frames. Idempotent: an existing one keeps its children and has its properties re-asserted.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		local created = false
		if screen and not screen:IsA("ScreenGui") then
			out:error(string.format("StarterGui.%s exists and is a %s, not a ScreenGui.", SCREEN_NAME, screen.ClassName))
			return
		end
		if not screen then
			screen = Instance.new("ScreenGui")
			screen.Name = SCREEN_NAME
			screen.Parent = StarterGui
			created = true
		end
		local gui = screen :: ScreenGui

		gui.ResetOnSpawn = false
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		--- See the header: the kit's own space, not `MainUI`'s.
		gui.IgnoreGuiInset = false
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

		--[[ Both UIs are left enabled in the place on purpose. `Modules/UIRoot` enables the one in use
			and destroys the other at boot, so this property decides nothing at runtime and can be
			toggled freely while editing either screen. ]]
		gui.Enabled = true

		local legacy = StarterGui:FindFirstChild(LEGACY_NAME)
		if legacy and legacy:IsA("ScreenGui") then
			gui.DisplayOrder = legacy.DisplayOrder
		end

		local made = {}
		for _, name in SECTIONS do
			local _, isNew = section(gui, name)
			if isNew then
				table.insert(made, name)
			end
		end

		out:print(
			string.format(
				"%s StarterGui.%s (DisplayOrder %d, IgnoreGuiInset %s, %s). %s",
				if created then "Created" else "Re-asserted",
				SCREEN_NAME,
				gui.DisplayOrder,
				tostring(gui.IgnoreGuiInset),
				gui.ScreenInsets.Name,
				if #made > 0 then "Added " .. table.concat(made, " and ") .. "." else "HUD, Pages and Screens were already there."
			)
		)

		pcall(function()
			props:SetSelection({ gui })
		end)
	end,
} :: Types.ScriptModule
