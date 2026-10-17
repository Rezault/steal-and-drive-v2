--[[
	MiterKitStrokes: Command Runner command

	Sets `LineJoinMode = Miter` on every TEXT outline in the Cartoony Kit master
	(`ServerStorage.UIImports.NewUITemplate`) and in the screen built from it (`StarterGui.MainUIV2`,
	its `Screens` shelf included). Idempotent: a stroke already mitered is counted and left alone.

	=== WHY (Dylan, 2026-09-16) ===============================================================

	The kit ships its strokes `Round`. On the outlined type, at the kit's thick 0.11 `ScaledSize`, that
	closes up the small shapes: the Robux mark on a price pill goes soft and the counter in a "9" fills
	with a stray dot of the button's colour. Miter keeps the corners, so the mark and the digits read
	clean. The artist's own spin wheel already uses Miter on its outlined numbers.

	=== TEXT ONLY, AND THAT WAS MEASURED THE HARD WAY ========================================

	A rim is a stroke on a frame, and every kit rim sits on a frame with a `UICorner`. It looks as if
	the join could not matter on a rounded corner. IT DOES: the kit's rims are thicker than their
	corner radius, and with Miter the stroke's OUTER edge comes out square. The first run mitered all
	of them and every price pill and gift button in the shop turned into a sharp-cornered box (zoomed
	render, same day). So a stroke is mitered only when it outlines type: `Contextual` on a
	`TextLabel`, `TextButton` or `TextBox`. A `Border` stroke on a text object is a rim too and is
	left alone.

	=== WHY THE MASTER TOO ===================================================================

	Every `Build*V2` command clones its frame out of the master, so fixing the master is what makes a
	rebuild come out mitered without nineteen builders each carrying the same loop. The master is not
	in git: if the kit is ever re-imported, run this again.

	Strokes made in code are not touched and are not the kit's: the `Round` ones in
	`RadioPanelController`, `RandomCarController` and `TutorialController` belong to the old UI.
]]

local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local Types = require(script.Types)

local SCREEN_NAME = "MainUIV2" -- NewUIConfig.ScreenGuiName
local TEMPLATE_PATH = { "UIImports", "NewUITemplate" } -- NewUIConfig.TemplatePath, under ServerStorage

local JOIN = Enum.LineJoinMode.Miter

local function findTemplate(): Instance?
	local node: Instance = ServerStorage
	for _, step in TEMPLATE_PATH do
		local child = node:FindFirstChild(step)
		if not child then
			return nil
		end
		node = child
	end
	return node
end

--- Whether a stroke draws round the letters rather than round a box. See "TEXT ONLY" in the header.
local function outlinesText(stroke: UIStroke): boolean
	local parent = stroke.Parent
	return stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual
		and parent ~= nil
		and (parent:IsA("TextLabel") or parent:IsA("TextButton") or parent:IsA("TextBox"))
end

--- Miter every text outline under `root`. Returns how many changed and how many already were.
local function miter(root: Instance): (number, number)
	local changed, already = 0, 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("UIStroke") and outlinesText(descendant) then
			if descendant.LineJoinMode == JOIN then
				already += 1
			else
				descendant.LineJoinMode = JOIN
				changed += 1
			end
		end
	end
	return changed, already
end

return {
	Description = "Set LineJoinMode = Miter on every text outline (Contextual UIStroke on a text object) in the Cartoony Kit master (ServerStorage.UIImports.NewUITemplate) and in StarterGui.MainUIV2, so outlined type keeps its corners. Rims stay Round. Idempotent; re-run after a kit re-import.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local roots = {}
		local template = findTemplate()
		if template then
			table.insert(roots, template)
		else
			out:warn(string.format("No ServerStorage.%s; only the built screen is mitered, and the next rebuild will bring Round back.", table.concat(TEMPLATE_PATH, ".")))
		end
		local screen = StarterGui:FindFirstChild(SCREEN_NAME)
		if screen then
			table.insert(roots, screen)
		else
			out:warn(string.format("No StarterGui.%s to miter.", SCREEN_NAME))
		end

		for _, root in roots do
			local changed, already = miter(root)
			out:print(string.format("%s: %d text outline(s) set to Miter, %d already were. Rims left Round.", root:GetFullName(), changed, already))
		end
	end,
} :: Types.ScriptModule
