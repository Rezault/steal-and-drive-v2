--[[
	GlassPromptConfig
	-----------------
	THE IN-WORLD PROMPT CARD (2026-10-07). Every `ProximityPrompt` tagged `Tag` is drawn by
	`GlassPromptController` instead of by Roblox, and the prompts that share a PART are drawn as ONE
	card with a row per prompt:

	        ┌──────────────────────────┐
	        │ BAY 3                    │
	        │ [E]  Pick Up       HOLD  │
	        │ [F]  Change Car          │
	        └──────────────────────────┘

	IT IS GLASS, NOT THE KIT, ON PURPOSE. Every menu in this game is the Cartoony Kit (navy, checker,
	Ubuntu Bold). A prompt is not a menu, it is a label hanging in the world, so it wears a dark
	frosted pane with a light rim and Builder Sans: one step away from the kit, so it reads as "the
	world is offering you something" rather than "a screen opened". Roblox cannot blur what is behind
	a gui, so the frost is faked: a translucent tint, a sheen across the top half, and a rim that is
	brighter along the top edge, as if lit from above.

	=== WHAT THE SERVER WRITES, AND WHAT IT MUST NOT ==========================================

	The server creates each prompt with `Style = Custom`, the tag, and the attributes below. It must
	NOT write `Enabled` after creation: the client owns `Enabled` locally to pick which part's card
	is up (`Focus`), and a replicated write would overwrite that choice.

	=== ONE CARD AT A TIME, CHOSEN BY US ======================================================

	The engine draws one prompt per KEY (`Exclusivity = OnePerButton`) and does not pick the nearest
	(see the `one-prompt-per-car` note), so between two podiums it can show bay 1's E and bay 2's F
	at once, which would be a card promising one podium and pressing another. So the controller
	picks the nearest tagged part itself and switches every OTHER tagged prompt off locally. Only
	the focused part's prompts can then be drawn or pressed.
]]

local GlassPromptConfig = {}

GlassPromptConfig.Enabled = true

--[[ WHICH LOOK (2026-10-07). True on the new UI: the card is the Cartoony Kit's own PromptUI, cut by
	`BuildWorldPromptV2` into `MainUIV2.Screens.WorldPrompt`: blue header with the bay's name, white
	body, the main action on the kit's green button and the rest on the legendary orange (the workshop
	screen's CHANGE CAR colour), each with a white keycap. False, the old UI, or a place without that
	template draws the glass described above. Dylan tried the glass first and asked to see it in the
	game's own UI. ]]
GlassPromptConfig.KitStyle = true

GlassPromptConfig.Kit = {
	Shelf = "Screens",
	Entry = "WorldPrompt",
	--- The kit card is authored 300px wide at 1080p; this draws it at that times the viewport scale.
	Scale = 0.8,
	--- White light over the green/orange face while a row is held, and the flash when it fires.
	FillTransparency = 0.55,
	--- On touch (no keycap) the caption starts this share of the row in from the left.
	TouchInset = 0.06,
}

--- The CollectionService tag the server puts on a prompt to have it drawn here.
GlassPromptConfig.Tag = "GlassPrompt"

GlassPromptConfig.Attributes = {
	--- Number. Row order on the card, low first. The main action is 1.
	Order = "GlassOrder",
	--- Number, a UserId. Set, only that player is offered the prompt; everybody else never sees it.
	Owner = "GlassOwner",
	--- Boolean. True takes the row off the card (and the prompt off its key) without the server
	--- touching `Enabled`.
	Hidden = "GlassHidden",
}

GlassPromptConfig.Focus = {
	--- Seconds between re-picking the focused part. The answer only changes as you walk.
	Interval = 0.1,
	--[[ Studs a rival part has to be NEARER by before focus moves to it, so standing halfway between
		two podiums does not flip the card back and forth. Same 1 stud `VehiclePromptGui.seatOnOffer`
		settled on for the car doors. ]]
	Hysteresis = 1,
}

--[[ WHERE THE CARD HANGS, in studs above the prompt's part, in WORLD space. The podium deck sits
	under the car, so this lifts the card clear of the roof; `AlwaysOnTop` draws it through the
	bodywork. ]]
GlassPromptConfig.Offset = Vector3.new(0, 6.5, 0)

--[[ === SIZE ================================================================================
	Pixels at a 1080p-tall viewport, scaled by the viewport's height and clamped, so the card is the
	same share of the screen on a laptop and a 4K monitor and never shrinks under a thumb on a phone.
	A prompt is a fixed-size label like the stock one, NOT a world object that shrinks with range. ]]
GlassPromptConfig.Size = {
	Reference = 1080,
	MinScale = 0.8,
	MaxScale = 1.6,

	Width = 236,
	Padding = 9,
	HeaderHeight = 20,
	RowHeight = 42,
	RowGap = 5,
	CornerRadius = 14,
	RowCorner = 10,
	Key = 30,
	KeyCorner = 8,
	--- The keycap's lip: the darker plate under the cap, showing this many pixels below it.
	KeyDepth = 2,
	ActionText = 17,
	HeaderText = 12,
	HintText = 11,
}

GlassPromptConfig.Font = {
	Action = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	Header = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold),
	Key = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold),
}

GlassPromptConfig.Colors = {
	--- The pane: a cool near-black, so white type sits on it on a bright lobby and a dark one.
	Tint = Color3.fromRGB(14, 20, 34),
	TintTransparency = 0.22,
	--- The sheen across the top half: white, fading out downwards from this transparency.
	SheenTransparency = 0.88,
	--- The rim: white, this transparent along the top edge, `RimBottom` along the bottom.
	Rim = Color3.fromRGB(255, 255, 255),
	RimTop = 0.35,
	RimBottom = 0.82,
	--- The soft shadow under the pane.
	Shadow = Color3.fromRGB(0, 0, 0),
	ShadowTransparency = 0.78,

	Text = Color3.fromRGB(255, 255, 255),
	--- The header and the HOLD tag: the same white, quieter.
	TextMuted = 0.42,

	--- A row's own inset, faint, so the rows read as separate pressable things inside the pane.
	Row = Color3.fromRGB(255, 255, 255),
	RowTransparency = 0.93,
	--- On touch the whole row is the button, so it is drawn a little more solid.
	RowTouchTransparency = 0.86,
	--- The fill that sweeps a row while it is held, and the flash when it fires. The game's blue,
	--- lifted so it reads as light on the glass rather than as paint.
	Fill = Color3.fromRGB(96, 170, 255),
	FillTransparency = 0.45,

	Key = Color3.fromRGB(245, 248, 255),
	KeyLip = Color3.fromRGB(150, 162, 190),
	KeyText = Color3.fromRGB(14, 20, 34),
}

GlassPromptConfig.Text = {
	--- The tag at a hold row's right end.
	Hold = "HOLD",
}

GlassPromptConfig.Motion = {
	--- The card's entrance: a small scale-up, restrained like the rest of the game's juice.
	PopFrom = 0.9,
	PopIn = 0.16,
	PopOut = 0.1,
	--- The keycap's press dip, and how long the row's flash takes to fade after a trigger.
	PressScale = 0.88,
	Flash = 0.35,
}

return GlassPromptConfig
