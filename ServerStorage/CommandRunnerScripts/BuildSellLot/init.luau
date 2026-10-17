--[[
	BuildSellLot — Command Runner command

	Authors the sell square into the place: the painted pad, its border, the wall of light round all
	four edges and the SELL YOUR CAR board on its pole behind it. Run it once, save the place, and
	`SellService` binds it every server after that.

	=== WHY THIS EXISTS ========================================================

	The lot was derived at run time first — a bearing, a radius, a raycast — which made it immune to
	a map swap and impossible to restyle. The owner asked for it to be authored so it can be changed
	by hand, and this is the half that makes that possible: it puts a real, saveable model in
	Workspace using the same code the service would have used, so nothing is hand-placed and nothing
	is a one-off.

	After it runs, the lot is ORDINARY GEOMETRY. Move it, repaint it, swap the beams for the
	modeller's own art, drag the pad somewhere else entirely. Three names are the contract and
	everything else is yours — see `Modules/SellLot`'s header:

	    SellPad          THE VOLUME. Move or resize it and the sell area moves with it.
	    SellBubbleAnchor an Attachment on the pad; the client's price sign hangs off it.

	It was three names until 2026-08-31. `SellButton` held the prompt you used to hold to sell a car;
	getting out of the car is the gesture now and a panel asks, so there is nothing pressable on the
	lot at all. `SellService` strips both the attachment and the prompt off any lot authored before
	that date — so a place saved earlier keeps working and RE-RUNNING THIS COMMAND AND SAVING is what
	makes the removal permanent.

	=== WHAT IT DOES ===========================================================

	  1. Finds the lot already in the place, if there is one.
	  2. Works out where the new one goes — see `KeepPlacement`, which is the argument that matters.
	  3. Deletes the old one and parents a fresh build in its place, inside `Workspace.SellLot`.

	`KeepPlacement` IS ON BY DEFAULT AND THAT IS THE WHOLE POINT OF RE-RUNNING. A re-run is normally
	"I changed a number in `SellConfig`, redraw it" — and if that moved the lot back to the derived
	bearing every time, a lot somebody had dragged to a better spot would be silently undone by a
	colour change. On, the rebuild lands on the existing lot's own pivot. Off, it re-derives from
	`Bearing`/`Radius` and probes for a clear spot exactly as the run-time fallback does.

	IT IS NOT PARENTED INSIDE `Workspace.Map`, and that is deliberate. The map has been swapped once
	already (`docs/MapLayout.md` §6) and the swap takes everything under it with it — that is how the
	forecourt upgrade billboards vanished without a word. At the Workspace root the lot survives the
	next island; a lot that ends up under the new map is a lot somebody has to rebuild.

	=== AFTER RUNNING IT =======================================================

	SAVE THE PLACE. This writes to the edit DataModel; nothing is persisted until you save. Then a
	playtest should log `Bound the sell lot at (…)` rather than the fallback's warning — if you see
	the warning, the model did not save, or its tag came off.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Types)

--- Where the config's own numbers are read from, so the argument defaults below cannot drift from
--- what the service would derive. Nil-safe: the command reports a missing config rather than
--- building something arbitrary.
local function requireShared(name: string, folder: string)
	local shared = ReplicatedStorage:FindFirstChild("shared")
	local parent = shared and shared:FindFirstChild(folder)
	local module = parent and parent:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, value = pcall(require, module)
	return if ok then value else nil
end

--[[ The argument defaults are READ FROM THE CONFIG, not typed here, because the plugin shows them
	before `Run` is ever called and a stale default is a command that quietly offers to move the lot
	back to a spot nobody uses any more. The literals are only the answer when `SellConfig` cannot be
	required at all — at which point `Run` refuses anyway and these are never used. ]]
local BOOT_CONFIG = requireShared("SellConfig", "Configs")
local DEFAULT_BEARING = if type(BOOT_CONFIG) == "table" then BOOT_CONFIG.Lot.Bearing else 101
local DEFAULT_RADIUS = if type(BOOT_CONFIG) == "table" then BOOT_CONFIG.Lot.Radius else 206

return {
	AutoRecordChanges = true,
	Description = "Author the sell square into the place: the pad, its border, the wall of light round it and the SELL YOUR CAR board. Re-run after changing SellConfig; keeps where you dragged it unless you untick KeepPlacement.",
	Tags = { "Plaza", "Garage", "UI" },
	Arguments = {
		Bearing = {
			Type = "number",
			Default = DEFAULT_BEARING,
			Min = 0,
			Max = 359,
			LayoutOrder = 1,
			Description = "WHERE the lot stands: compass bearing from the plaza centre, 0 = +Z and clockwise, the same way docs/MapLayout.md measures a plot. 101 puts it beside the plaza entry road. Which way it FACES is SellConfig.Lot.EntranceBearing and is not an argument, because a lot that fronts a road has one right answer. IGNORED while KeepPlacement is ticked and a lot already exists.",
		},
		Radius = {
			Type = "number",
			Default = DEFAULT_RADIUS,
			Min = 60,
			Max = 400,
			LayoutOrder = 2,
			Description = "Studs from the plaza centre. 206 sits the square in the clean asphalt north of the crosswalk, clear of the plaza trim on one side and the ring road median on the other; that window is only about 40 studs wide, so this is not a number to nudge by eye. A height profile, not the clearance test, is what tells you whether a new one is clean. IGNORED while KeepPlacement is ticked and a lot already exists.",
		},
		KeepPlacement = {
			Type = "boolean",
			Default = true,
			LayoutOrder = 3,
			Description = "Rebuild on the existing lot's own pivot instead of re-deriving from Bearing/Radius. On, so a redraw after a config change never undoes a lot you dragged somewhere better. Untick to move it back onto the derived spot.",
		},
		DryRun = {
			Type = "boolean",
			Default = false,
			LayoutOrder = 4,
			Description = "Report what would happen and touch nothing.",
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		--[[ REQUIRED, not copied. Every number and every instance name this builds comes from the
			same two modules the game reads, so an authored lot cannot disagree with the service about
			what a pad is called. The cost is edit mode's require cache: change either module and the
			Command Runner has to be reconnected before this sees it. ]]
		local SellConfig = requireShared("SellConfig", "Configs")
		local SellLot = requireShared("SellLot", "Modules")
		if not (type(SellConfig) == "table" and type(SellLot) == "table" and SellLot.build) then
			out:error("Could not require ReplicatedStorage.shared.Configs.SellConfig and shared.Modules.SellLot. Is Rojo syncing? Reconnect the Command Runner after a config change.")
			return
		end

		local existing = SellLot.existing()
		local keep = arguments.KeepPlacement ~= false
		local dry = arguments.DryRun == true

		--[[ WHERE IT GOES. Keeping the placement takes the existing model's PIVOT, which for a lot
			this command built is the pad's own CFrame (`PrimaryPart` is the pad) — so a rebuild lands
			exactly where the old one stood even if somebody has rotated it. With nothing to keep, or
			with the box unticked, it probes for a clear bearing the way the run-time fallback does. ]]
		local frame: CFrame?
		local note: string
		if keep and existing[1] then
			frame = existing[1]:GetPivot()
			note = string.format("kept the existing lot's placement at (%.0f, %.0f, %.0f)", frame.Position.X, frame.Position.Y, frame.Position.Z)
		else
			--- The lot standing there must not count as its own obstruction on a re-derive.
			local ignore = {}
			for _, lot in existing do
				table.insert(ignore, lot)
			end
			local found, clear, why = SellLot.findPose(arguments.Bearing, arguments.Radius, ignore)
			if not found then
				out:error(why)
				return
			end
			if not clear then
				out:warn(why)
			else
				out:print(why)
			end
			frame = found
			note = string.format("derived a spot at (%.0f, %.0f, %.0f)", found.Position.X, found.Position.Y, found.Position.Z)
		end

		if dry then
			out:print(string.format(
				"DRY RUN — would replace %d existing lot(s) and %s.",
				#existing,
				note
			))
			return
		end

		for _, lot in existing do
			lot:Destroy()
		end

		--[[ A folder of its own at the Workspace root, created on demand — see the header for why it
			is not inside `Map`. Reused if it is already there, so re-running does not stack folders. ]]
		local folder = workspace:FindFirstChild(SellConfig.FolderName)
		if not (folder and folder:IsA("Folder")) then
			folder = Instance.new("Folder")
			folder.Name = SellConfig.FolderName
			folder.Parent = workspace
		end

		local model = SellLot.build(frame :: CFrame)
		model.Parent = folder

		out:print(string.format(
			"Built the sell lot in Workspace.%s (%s). Replaced %d. SAVE THE PLACE — nothing is persisted until you do.",
			SellConfig.FolderName,
			note,
			#existing
		))
		if #CollectionService:GetTagged(SellConfig.Tag) ~= 1 then
			out:print(string.format("There are now %d instances tagged %s. Every one of them is bound at run time and is a real place to sell a car, so this is only a problem if a copy was left somewhere by accident.", #CollectionService:GetTagged(SellConfig.Tag), SellConfig.Tag))
		end

		pcall(function()
			props:SetSelection({ model })
			props:FocusView(model)
		end)
	end,
} :: Types.ScriptModule
