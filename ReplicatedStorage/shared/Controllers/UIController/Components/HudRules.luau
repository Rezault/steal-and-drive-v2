--[[
	HudRules component  (client)
	----------------------------
	TAKES A HUD BUTTON DOWN WHEN THERE IS NOTHING BEHIND IT. One rule, applied once, at boot.

	The topbar has always done this for its own icons: no stock, no shop bag; no rows, no gear. The
	Cartoony Kit HUD moved one of those doors into the kit's side grid (`docs/NewUI-Migration-Plan.md`,
	"The new HUD"), so the grid needs the same answer the topbar gets, out of the same module. That
	module is `Modules/UIVisibility` and this file is the half of it that touches instances.

	=== IT KNOWS ABOUT PAGES, NOT ABOUT FEATURES ==============================================

	All this file reads is the `Page` attribute a button already carries for `Components/Button`, and
	all it asks is `UIVisibility.page(name)`. A button that carries an `Action` instead gets
	`UIVisibility.action(name)`, which is how the grid's Radio cell hides when the radio is off. It has no idea what a shop is or what would make one
	empty, which is what keeps the rule in one place: the day the shop's rule changes, it changes in
	`UIVisibility` and the topbar and the grid both follow.

	A page with no rule always answers yes, so the common case costs one table lookup and nothing is
	hidden. With the flag off this file is a no-op in practice: the old rail's five buttons are Index,
	Quest, Market, Dealership and Teleport, none of which has a rule, and the old UI's shop door is a
	topbar icon this never sees.

	=== WHAT IT HIDES IS THE CELL, NOT THE BUTTON =============================================

	A kit grid button is a `Main` TextButton inside a `BtnTemplate` cell that draws the rim around it,
	and the cell is what the `UIGridLayout` lays out. Hiding the button would leave an empty rim in the
	grid with a hole in the row; hiding the cell takes the slot out and lets the remaining five close
	up, because a layout skips children that are not visible.

	So: a button inside `Rail` hides the direct child of `Rail` it belongs to, and a button anywhere
	else in the HUD hides itself. The second half is not hypothetical — the cash block's green `+` is a
	door onto the shop too, and it is not in the rail.

	=== ONCE, AT BOOT =========================================================================

	Every input to every rule is config, settled before the player joined, which is set out in
	`UIVisibility`'s header. So this runs once and subscribes to nothing. If a rule ever becomes a live
	answer it needs a state event and this file needs to hear it, and the topbar needs the same
	treatment on the same day.

	The write is a plain `Visible = false` and nothing restores it, which is deliberate: this is the
	button not existing for this player in this build, not a button that is temporarily away. The
	things that hide a HUD member temporarily (a race, `InterfaceController`) put it back themselves,
	and they never turn on what this switched off, because they only restore what they took.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIControllerTypes = require(script.Parent.Parent.UIControllerTypes)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)
local UIVisibility = require(ReplicatedStorage.shared.Modules.UIVisibility)

--- Seconds to wait for the authored UI, matching `GamepadNav`: a StarterGui clone is there on the
--- first frame or not coming at all, so this only has to survive a slow join.
local GUI_WAIT = 10

--- The box the kit's grid buttons live in, and the one frame whose children are cells rather than
--- buttons. Named in `docs/NewUI-Migration-Notes.md` as one of the names Phase 2 had to hit.
local RAIL_NAME = "Rail"

--- The attribute a button carries to name the page it opens. A literal here because it is a literal
--- in `ButtonPress`, which is the file that acts on it; there is no `UIConfig` to put it in and
--- inventing one for a single string would put the name in two places instead of none.
local PAGE_ATTRIBUTE = "Page"
--- ...and its other half, for a door onto something that is not a page (the grid's Radio cell).
local ACTION_ATTRIBUTE = "Action"

--[[ The member to take down for this button: its cell if it is in the rail, itself if it is not. See
	the header. Walks up rather than down because the button is what carries the attribute and the
	cell is what the layout lays out, and there is no name shared by every cell to search for. ]]
local function member(button: GuiButton, rail: Instance?): GuiObject
	if not rail then
		return button
	end
	local node: Instance = button
	while node.Parent and node.Parent ~= rail do
		node = node.Parent
		if node == rail or not node:IsDescendantOf(rail) then
			return button -- not in the rail after all
		end
	end
	return if node.Parent == rail and node:IsA("GuiObject") then node else button
end

return function(UIController: UIControllerTypes.UIController)
	task.spawn(function()
		local mainUI = UIRoot.wait(UIController.PlayerGui, GUI_WAIT)
		local hud = mainUI and mainUI:FindFirstChild("HUD")
		if not hud then
			--- Silent. `GarageHudController` and `GamepadNav` both already say so when the UI is not
			--- in the place, and a third voice saying it adds nothing.
			return
		end

		local rail = hud:FindFirstChild(RAIL_NAME)
		local hidden = {}

		for _, descendant in hud:GetDescendants() do
			if descendant:IsA("GuiButton") then
				local page = descendant:GetAttribute(PAGE_ATTRIBUTE)
				local action = descendant:GetAttribute(ACTION_ATTRIBUTE)
				local door = if typeof(page) == "string" and not UIVisibility.page(page)
					then page
					elseif typeof(action) == "string" and not UIVisibility.action(action) then action
					else nil
				if door then
					local target = member(descendant, rail)
					target.Visible = false
					table.insert(hidden, string.format("%s (%s)", target.Name, door))
				end
			end
		end

		if #hidden > 0 then
			print(string.format("[HudRules] Nothing behind it, so it is not drawn: %s.", table.concat(hidden, ", ")))
		end
	end)
end
