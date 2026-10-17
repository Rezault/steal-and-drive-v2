--[[
	PrepKitTemplate: Command Runner command

	Makes the Cartoony Kit master copy ready to clone pages out of. It runs over
	`ServerStorage.UIImports.NewUITemplate` (the pack's own ScreenGui, parked out of `StarterGui` so
	its 7,616 instances are not copied into every PlayerGui on every respawn) and does two things:

	  1. TAGS EVERY BUTTON `UIButton`. That one tag is how a button becomes a button in this project:
	     `UIController/Components/Button` gives it the hover swell, the click sound, the gamepad
	     highlight and the press, and a `Page` or `Action` attribute typed into the Explorer is then
	     the whole of wiring it up. Tagging the MASTER means every page cloned out of the kit arrives
	     already alive, because a clone carries its tags.

	  2. PUTS EVERY LABEL IN THE KIT'S OWN FACE. The pack draws its visible text in Fredoka One and
	     leaves Roblox's default on the parts nobody sees (the invisible `Text` on a TextButton, which
	     is a hit area with an icon on top). Those turn up the moment a page reuses one as a real
	     label, and a single face across the kit is one less thing to notice later. The face is read
	     off the kit's own header rather than named here, so this command cannot disagree with the
	     art about which Fredoka it is.

	IDEMPOTENT, and cheap to re-run after the artist re-imports a frame.

	=== WHAT IT DOES NOT DO ===================================================================

	It does not touch `StarterGui`. Pages are cloned into `MainUIV2` by their own commands in Phase 3;
	this only prepares the stamp they are cut from.

	It does not tag anything OUTSIDE a button. The tag is a statement that a thing is pressable, and
	`Components/GamepadNav` reads it as exactly that when it decides what a DPad may land on.
]]

local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Types = require(script.Types)

local IMPORTS_FOLDER = "UIImports"
local TEMPLATE_NAME = "NewUITemplate" -- NewUIConfig.TemplatePath
local BUTTON_TAG = "UIButton"

--- Where to read the kit's face from: the first label under a page header. Any would do; a header
--- title is the one that is certain to be in the kit's display face rather than a body face.
local function kitFont(root: Instance): Font?
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("TextLabel") and descendant.Name == "Title" and descendant.Parent then
			if descendant.Parent.Name == "Header" then
				return descendant.FontFace
			end
		end
	end
	return nil
end

return {
	Description = "Prepare ServerStorage.UIImports.NewUITemplate for the new UI: tag every GuiButton UIButton so clones arrive pressable, and put every label in the kit's own Fredoka face. Idempotent.",
	Tags = { "UI", "NewUI" },
	AutoRecordChanges = true,

	Arguments = {
		TagButtons = {
			Type = "boolean",
			Default = true,
			Description = "Tag every GuiButton in the kit UIButton.",
			LayoutOrder = 1,
		},
		UnifyFont = {
			Type = "boolean",
			Default = true,
			Description = "Set every TextLabel, TextButton and TextBox to the face the kit's headers use.",
			LayoutOrder = 2,
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		local imports = ServerStorage:FindFirstChild(IMPORTS_FOLDER)
		local template = imports and imports:FindFirstChild(TEMPLATE_NAME)
		if not template then
			out:error(
				string.format(
					"No ServerStorage.%s.%s. The kit lives there; move it back, or fix NewUIConfig.TemplatePath and this command together.",
					IMPORTS_FOLDER,
					TEMPLATE_NAME
				)
			)
			return
		end

		local tagged, alreadyTagged = 0, 0
		if arguments.TagButtons then
			for _, descendant in template:GetDescendants() do
				if descendant:IsA("GuiButton") then
					if CollectionService:HasTag(descendant, BUTTON_TAG) then
						alreadyTagged += 1
					else
						CollectionService:AddTag(descendant, BUTTON_TAG)
						tagged += 1
					end
				end
			end
		end

		local face = if arguments.UnifyFont then kitFont(template) else nil
		local refaced, alreadyFaced = 0, 0
		if face then
			for _, descendant in template:GetDescendants() do
				if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
					if descendant.FontFace == face then
						alreadyFaced += 1
					else
						descendant.FontFace = face
						refaced += 1
					end
				end
			end
		elseif arguments.UnifyFont then
			out:warn("No Header.Title label found in the kit, so the face could not be read. Fonts left alone.")
		end

		out:print(
			string.format(
				"%s: tagged %d button%s %s (%d already), reset %d label%s to %s (%d already).",
				template:GetFullName(),
				tagged,
				if tagged == 1 then "" else "s",
				BUTTON_TAG,
				alreadyTagged,
				refaced,
				if refaced == 1 then "" else "s",
				if face then (string.match(face.Family, "[^/]+$") or face.Family) else "nothing",
				alreadyFaced
			)
		)
	end,
} :: Types.ScriptModule
