--[[
	TipsConfig
	----------
	The line that turns up in chat every few minutes: what it may say, how often it says it, and
	what it looks like when it lands.

	=== READ THIS FIRST: THE SERVER PICKS, THE CLIENT PRINTS ====================================

	`TextChannel:DisplaySystemMessage` IS A CLIENT-ONLY CALL. There is no server API that puts a
	system line into everybody's chat window. `TextChannel:SendAsync` exists and is not it — that
	posts as a SPEAKER, so the tip would arrive attributed to whoever the server is pretending to
	be, go through the text filter as if a player had typed it, and be muteable per-player like a
	person. A tip is chrome, not somebody talking.

	So this feature is two halves and has to be: `TipsService` owns the clock and the choice, and
	`TipsController` is the thing that actually writes the line into the local window. Neither half
	is optional and neither is where you would first look for it.

	=== THE WIRE CARRIES AN INDEX, NOT A SENTENCE ==============================================

	The server broadcasts `Tips[n]`'s number and the client looks the text up here. Both halves
	already hold this file, so nothing is saved by sending the string — what is bought is that THE
	COPY HAS EXACTLY ONE HOME. A wire that carried text would mean a tip could be changed without
	touching this list, and the first time somebody did that the config would stop being the answer
	to "what does the game tell players?".

	It also means an index this build does not have prints NOTHING rather than a blank line, which
	is the right failure for a mixed-version server during a soft deploy.

	The cost is that a tip cannot be personalised — no "you have 4 empty bays". That is deliberate
	for now: a per-player tip is a different feature with a different cadence, and it would want its
	own remote rather than this one broadcast.

	=== WHY THE SERVER OWNS THE CLOCK AT ALL ===================================================

	A client could perfectly well run its own timer and never involve the server. It is done this
	way round because everyone in the server reading the same tip at the same moment is the whole
	character of the thing — it is the room being told something, which is what makes it feel like
	the game talking rather than a hint bubble. It also means a future "server is restarting in 5
	minutes" line has a channel already built for it.

	=== THE COLOURS ARE NOT THE KIT'S ==========================================================

	`UpgradeConfig.Colors.Buy` is #0066FF and it is wrong here. The kit's blue was chosen to sit on
	the #364157 navy panels; the chat window is a near-black translucent sheet, and #0066FF on it is
	a dark blue on a dark grey that older monitors lose entirely. So the tag is the kit's blue
	LIFTED until it reads, and the body copy is `Colors.Muted` — which was already a light
	periwinkle chosen for exactly this job on the boards.
]]

local TipsConfig = {}

--- Master switch. Off = the service does not start, the controller binds nothing, and the chat
--- window is left exactly as Roblox ships it.
TipsConfig.Enabled = true

-- === Cadence ================================================================

--[[ Seconds between tips.

	THREE AND A HALF MINUTES, sized against a session rather than against a clock: this genre's
	sessions run ten to fifteen minutes, so a player sees three or four tips in a visit and no tip
	twice (`Tips` is longer than that and the service shuffles). Take it much below three and the
	chat window becomes a thing players learn to ignore, which costs more than the tips are worth.

	It is a WALL CLOCK, not a per-player one. A player who joins thirty seconds before a tip fires
	sees it thirty seconds in; that is the price of everyone reading the same line at the same
	moment, and it is the point rather than a rounding error. ]]
TipsConfig.Interval = 210

--[[ How long a fresh server waits before its first tip.

	Not zero, and the reason is the empty-window problem: the first player through the door has done
	nothing yet, has no lot and no cars, and a tip about STORAGE is advice about a screen they have
	not seen. Ninety seconds is roughly long enough to have banked something. ]]
TipsConfig.FirstDelay = 90

--[[ Don't post into a server nobody is in. Costs nothing to check and keeps the log honest — a
	tip fired at an empty server is a tip nobody was ever going to be shown, and counting it as
	"sent" makes the shuffle look like it is skipping entries. ]]
TipsConfig.MinPlayers = 1

-- === What it looks like =====================================================

--[[ Rich text markup in the line. Off = the tag and the copy both arrive in the chat's default
	colour, which is a perfectly readable fallback rather than a broken state.

	Worth knowing it exists: if a future `ChatWindowConfiguration` ever turns rich text off, every
	tip would otherwise print its `<font>` tags literally, and the fix is this switch and not a
	rewrite of the list. ]]
TipsConfig.RichText = true

--- The bit in brackets at the front. Short on purpose — it is a label, not a sentence.
TipsConfig.Tag = "TIP"

--[[ Chosen against the CHAT WINDOW's near-black sheet, not the kit's navy panels — see the header.
	`Body` is `UpgradeConfig.Colors.Muted` exactly; `Tag` is the kit's #0066FF lifted to clear the
	dark background it has to sit on. ]]
TipsConfig.TagColor = Color3.fromRGB(77, 155, 255)
TipsConfig.BodyColor = Color3.fromRGB(168, 179, 208)

--[[ Colour3 -> "#4D9BFF". Written here rather than inlined so the two colours above stay real
	`Color3`s — a hex string in a config is a value nobody can nudge in the Studio picker. ]]
local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

-- === The tips ===============================================================

--[[ One string per line, in no particular order — the service shuffles, so position here means
	nothing and a new tip can go at the bottom.

	EVERY ONE OF THESE IS A CLAIM ABOUT THE GAME, and the bar for adding one is that it is true of
	the build it ships in. A tip that describes a mechanic as it was last month is worse than no tip
	at all: it is the game itself telling a player something they will then fail to reproduce, and
	they have no reason to doubt it. A tip that quotes a number formats it from the config that owns
	it rather than typing it out, so retuning cannot leave the chat lying.

	=== FOUR WENT FOR BEING UNTRUE — 2026-10-16 ===
	The duplicate-sells tip (`GarageConfig.Banking.SellDuplicates` is false: a duplicate is kept),
	the bays-stop-filling/STORAGE and AUTO COLLECT tips (`GarageConfig.Income.Passive` is false: bays
	hold no cash, and neither upgrade is on `UpgradeConfig.Order`), and "bays pay by the car's tier"
	(customers tip off market value now). If `Passive` ever comes back, so can those three.

	SENTENCE CASE, not the kit's upper case. The UI shouts because its labels are two words wide;
	a chat line is prose and reads as shouting if it is set that way. Where a tip names an upgrade
	it uses the tile's own upper-case title, which is what the player is looking for on the board. ]]
TipsConfig.Tips = {
	"Drive into the truck to keep your car. It ends the run, but it's the only way to bank it.",

	"Same car, new colour? That's a new car for your collection.",

	"Your cars keep earning while you're offline.",

	"LUCK puts better cars on the road.",

	"JUMP gives you more reach and more steering in the air.",

	"CUSTOMERS brings more browsers to your lot. More browsers, more tips.",

	"Use the pencil on your dealership sign to rename it.",

	"Banking a car gives it XP for the distance you drove. Levels make it faster.",

	"Tap the brake to slip into a gap. Let go and you speed back up.",
}

-- === Formatting =============================================================

--[[ Index -> the finished line, or nil if there is no such tip.

	NIL RATHER THAN A PLACEHOLDER for an index this build does not have — see the header. The client
	prints nothing at all in that case, which is invisible, where a "(missing tip 14)" would be a
	bug report from a player who did nothing wrong.

	Formatting lives here rather than in the controller for the reason `LeaderboardConfig` gives for
	the same split: the wording and the thing that draws it should be one file, so nobody has to
	read a controller to find out why a line has a bracket in it. ]]
function TipsConfig.line(index: unknown): string?
	local n = tonumber(index)
	if not n or n % 1 ~= 0 then
		return nil
	end

	local tip = TipsConfig.Tips[n]
	if not tip then
		return nil
	end

	if not TipsConfig.RichText then
		return string.format("[%s] %s", TipsConfig.Tag, tip)
	end

	return string.format(
		'<font color="%s">[%s]</font> <font color="%s">%s</font>',
		hex(TipsConfig.TagColor),
		TipsConfig.Tag,
		hex(TipsConfig.BodyColor),
		tip
	)
end

return TipsConfig
