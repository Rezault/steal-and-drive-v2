--[[
	PlotConfig
	----------
	The dealership plots players own while they are in the server (GDD §4, `docs/MapLayout.md`).

	Three things to know before editing:

	1. A PLOT IS A SEAT, NOT A SAVE. There are exactly six plots in the map and they are claimed for
	   the length of a session, like a seat at a table — you get whichever one is free, and it goes
	   back in the pool the moment you leave. Nothing about WHICH plot you had is worth persisting:
	   the six are geometrically identical (verified to 0.0003 studs in plot-local space), so plot 4
	   and plot 1 are the same lot in different rotations. What persists is your cars and your cash,
	   and that lives in the player profile, not here.

	2. THE MAP IS THE CONTRACT, exactly like the road and the truck. `PlotService` discovers plots by
	   walking `Map.Plots` — it never builds one, moves one, or assumes there are six. Numbered PlotN
	   models have their tag and PlotIndex repaired from N (2026-10-12); custom names still require
	   an explicit tag and unique index. This keeps duplicated lots claimable without admitting
	   backup copies outside the folder.

	3. SPAWNS ARE AUTHORED, NOT COMPUTED. Each plot owns a `PlotSpawn` SpawnLocation placed in the
	   place file so it can be dragged in Studio. `Fallback` below exists only so a plot that arrives
	   without one still works — it is a safety net for a bad import, not the normal path. If you
	   find yourself tuning `Fallback` to move a spawn, move the authored part instead.
]]

local PlotConfig = {}

-- Master switch. Off = nobody is assigned a plot and `Players.CharacterAutoLoads` is left alone,
-- so the game falls back to stock Roblox spawning. Useful when testing the race loop on its own.
PlotConfig.Enabled = true

-- === Finding the plots ======================================================

--[[ Where the claimable plots live. Scoped to a FOLDER PATH and not just to the tag on purpose.

	The backup copy of a plot that gets pasted into Workspace during map work carries the tag and
	the `PlotIndex` attribute with it — `workspace.Plot7` did exactly that, a full copy of Plot1
	sitting 478 studs off the island, tagged `Plot`, claiming index 1. A tag-only lookup finds it,
	hands it to a player, and spawns them in the sea. Requiring the path as well as the tag makes a
	stray copy inert no matter what it carries. ]]
PlotConfig.MapName = "Map"
PlotConfig.PlotsFolderName = "Plots"
PlotConfig.PlotTag = "Plot"

-- Attribute on each plot Model naming its stable 1..N identity; repaired from PlotN when numbered.
PlotConfig.IndexAttribute = "PlotIndex"

-- === Ownership ==============================================================

--[[ Attributes stamped on the plot Model while it is claimed, and cleared when it is released.

	Attributes rather than a server-side table alone, because attributes REPLICATE: a client can ask
	"is this lot mine?" straight off the model it is standing on, with no remote and no round trip.
	The server keeps its own table too — the attribute is the broadcast, not the source of truth. ]]
PlotConfig.OwnerUserIdAttribute = "OwnerUserId"
PlotConfig.OwnerNameAttribute = "OwnerName"

-- Attribute stamped on the Player naming the plot they hold, so client code can find its own lot
-- without a remote. Cleared on release.
PlotConfig.PlayerPlotAttribute = "PlotIndex"

-- Stable home bounds on the Player survive the plot streaming out on their client.
PlotConfig.PlayerFootprintAttribute = "PlotFootprint"
PlotConfig.PlayerFootprintSizeAttribute = "PlotFootprintSize"

-- === Spawning ===============================================================

-- Name of the SpawnLocation authored inside each plot Model.
PlotConfig.SpawnName = "PlotSpawn"

--[[ Take over character loading.

	`Players.CharacterAutoLoads` is switched OFF so the join order is deterministic: claim a plot,
	point `RespawnLocation` at its spawn, THEN load the character. Left on, Roblox loads the
	character the instant the player joins — which is a race the assignment usually loses, so the
	player's first spawn lands at whatever enabled SpawnLocation the engine picked and they have to
	die once to get to their own lot.

	The cost is that every path out of assignment MUST still load a character, including the failure
	paths, or a player sits at a black screen forever. `PlotService` treats that as invariant: the
	load is in the exit path, not in the success branch. ]]
PlotConfig.TakeOverCharacterLoading = true

--[[ Load a fresh character after a death, since switching auto-loads off also switched off Roblox's
	respawn.

	THIS IS NOT AN EXTRA FEATURE, IT IS THE OTHER HALF OF THE FLAG ABOVE, and leaving it out cost a
	whole playtest. `CharacterAutoLoads = false` does not only skip the FIRST character — it means
	the engine never loads one again, so a player who dies stays dead permanently: the Humanoid goes
	to the Dead state, the camera keeps pointing at a subject that no longer has a root, and the run
	is over in the only sense that matters. Nothing in this game respawns them, because until now
	nothing had to.

	It bit on a car falling out of the world. `Workspace.FallenPartsDestroyHeight` destroyed every
	part of the character, the Humanoid entered Dead with its Health untouched at 100, `RaceService`
	heard `Died` and tore the race down — correctly — and then there was simply nobody left to play.
	The steal that caused the fall is its own bug (see RaceConfig.VoidDropStuds), but ANY death would
	have done it.

	`RespawnLocation` is already pointed at the player's own plot pad by `_assign`, so a respawn puts
	them back on their lot rather than at the map's ordinary spawn. ]]
PlotConfig.RespawnOnDeath = true

--[[ What happens to player 7 when all six plots are taken.

	"lobby" - they join with no plot and spawn at the map's ordinary spawn. They can walk around and
	          watch, they just have no lot. Nothing breaks; the race loop does not need a plot.
	"kick"  - they are removed with `FullMessage` below.

	Lobby is the default because kicking on a full server is a terrible first impression for a
	problem the player did not cause, and because `Players.MaxPlayers` is the real fix — set it to
	the plot count and the engine stops letting a seventh player in at all. ]]
PlotConfig.WhenFull = "lobby"
PlotConfig.FullMessage = "All dealership plots in this server are taken. Please rejoin."

-- === The dealership sign ====================================================

--[[ The owner sign on the header beam over each showroom entrance.

	AUTHORED, NOT COMPUTED — same rule as the spawn (note 3). The plate and its SurfaceGui are built
	into the place by the `BuildDealershipSigns` Command Runner command, and `PlotService` only ever
	writes TEXT and an IMAGE into it. That split is deliberate: the service runs on every join, and
	nothing on the join path should be constructing UI it could instead be filling in.

	WHY THERE IS A SEPARATE PLATE AT ALL. The beam is `Cube.080`, a Blender MeshPart whose bounding
	box is much bigger than its mesh — 28.47 x 6.32 x 1.48 of box around a plate that really measures
	about 23.1 x 6.31 x 0.79, and the front face is a TRAPEZOID with the top corners cut off. A
	SurfaceGui parented straight to it renders on the BOX face: 0.35 studs floating in front of the
	mesh and overhanging 2.7 studs of thin air off each end. So the sign gets its own invisible plate,
	sized and placed to sit inside the real silhouette. See the memory note on MeshPart Size.

	NO REPLICA, ON PURPOSE. A SurfaceGui in Workspace replicates from the server to everyone already,
	and a sign is supposed to be public — the whole point is that OTHER players read whose lot this
	is. Replica is per-player scoped data and would be the wrong tool. The player's profile only
	comes into it for the custom name (below), which is genuinely per-player and persistent. ]]

-- Name of the invisible plate the command builds, found recursively inside the plot Model.
PlotConfig.SignName = "DealershipSign"

-- Names inside the SurfaceGui that PlotService writes to. Changing one here means changing it in
-- the Command Runner command too — they are the two halves of one contract.
PlotConfig.SignGuiName = "Sign"
PlotConfig.SignTitleName = "Title"
PlotConfig.SignHeadshotName = "Headshot"
PlotConfig.SignEditButtonName = "EditButton"

--[[ The likes pill on the valuation row, and the two labels inside it.

	OPTIONAL IN THE SAME SENSE `SignValueName` IS — read that note first; it is the whole reason a
	widget added after the signs were authored does not strip the nameplate off every plot in a place
	whose `BuildDealershipSigns` has not been re-run.

	IT IS ONE WIDGET DOING TWO JOBS, and that is deliberate rather than tidy: the pill is a READOUT of
	how many likes this dealership has, which every viewer including the owner should be able to see,
	and it is also the BUTTON a visitor presses. Making them one thing is what removes the per-viewer
	visibility question entirely — there is no state in which the sign shows a different NUMBER of
	widgets to different people, so there is no frame in which two of them can be on top of each other
	while a client works out which of them it was supposed to hide. Compare the pencil, which does
	have that problem and gets away with it because it is alone in its slot.

	The two labels split by WHO WRITES THEM, which is the same split the title makes:

	  * `Count` is public — a number, nobody typed it — so the SERVER writes it straight onto the
	    replicated SurfaceGui and every player reads the same figure.
	  * `Icon` is per-viewer — a filled heart means "you have liked this one" — so the server paints
	    the un-liked default and each CLIENT writes its own answer over the top locally.

	A label does not sink input (`GuiObject.Active` is false on one by default), so both of these sit
	inside the button and clicks still reach it. ]]
PlotConfig.SignLikeButtonName = "LikeButton"
PlotConfig.SignLikeIconName = "Icon"
PlotConfig.SignLikeCountName = "Count"

--[[ The valuation under the title — "WORTH $2,880".

	OPTIONAL, UNLIKE THE THREE ABOVE, and that is load-bearing rather than lazy. It was added after
	the signs were first authored, so every plot in a place whose `BuildDealershipSigns` has not been
	re-run has no such label. `PlotService._resolveSign` requires the other three and merely LOOKS FOR
	this one — a sign without it keeps working exactly as it did, minus the line. Promote it to
	required and every un-rebuilt plot loses its nameplate entirely, which is a far worse trade than
	a missing line of copy. ]]
PlotConfig.SignValueName = "Value"

--[[ `%s` is `GarageConfig.formatCash` of the whole collection — see `GarageConfig.valueOfCollection`
	for what is being counted (every car KEY, so two colours of one body are two cars).

	THE WORD IS HERE AND NOT IN THE COMMAND that builds the label, because the command writes the
	widget once and `PlotService` writes the text on every claim: putting the copy anywhere else
	would mean a wording change needed a Studio re-run to take effect. ]]
PlotConfig.SignValueFormat = "WORTH %s"

--[[ The DEFAULT sign title, used when the owner has not named their dealership themselves.

	`"%s"` is the player's display name. A custom name from the profile does not go through this
	format at all — it replaces the whole title, because the player is naming their business, not
	themselves, and "Midnight Motors's Dealership" is not what they asked for. ]]
PlotConfig.SignTitleFormat = "%s's Dealership"

-- Shown while nobody owns the lot. The headshot and the pencil are hidden in this state.
PlotConfig.SignVacantText = "Available Lot"

--[[ U+00A0, substituted for every space before the title is written to the sign.

	It is the only thing keeping a long name on ONE line, and it is not optional.

	The title label is TextScaled, and TextScaled maximises text size subject to the laid-out text
	fitting its box — it will WRAP to get there rather than shrink. Measured on the real sign,
	"SuperCoolGamer1234x's Dealership" laid out as two lines at 37px in preference to one line at
	the same size, which on a banner this shape reads as a mistake. Roblox only breaks lines at
	spaces, so a title with no breakable spaces leaves shrinking as the only option.

	Two fixes that look right and are not: `TextWrapped = false` silently clears `TextScaled` and
	the label falls back to the default TextSize of 8; and raising a UITextSizeConstraint's
	MinTextSize above the two-line threshold does nothing, because the wrap happens first and the
	constraint is applied to the result. ]]
PlotConfig.SignNonBreakingSpace = utf8.char(0x00A0)

--[[ Profile key holding a custom dealership name, set by the pencil button.

	Empty string means "not set" and the sign falls back to `SignTitleFormat`. The read is
	deliberately ASYNC and off the join path — `Data:GetProfileAsync` yields until the profile
	loads, and yielding inside plot assignment would delay `LoadCharacter`, which is the one
	ordering this service is not allowed to break (see the PlotService header).

	WHAT IS STORED IS WHAT THE PLAYER TYPED, unfiltered. That is deliberate and it is Roblox's own
	guidance: a filter verdict is a moment in time and belongs to a VIEWER, so a name is filtered
	on the way out to each player rather than on the way into the save. See the Rename block. ]]
PlotConfig.DealershipNameKey = "DealershipName"

-- === Naming your dealership =================================================

--[[ The pencil on the sign, and everything behind it.

	=== WHY THE FILTER IS PER-VIEWER AND NOT PER-NAME ==========================================

	This is text one player writes and every other player reads, so it has to go through
	`TextService`. There are two ways to do that and they are not equivalent:

	  * `GetNonChatStringForBroadcastAsync` gives ONE string safe for everybody. It is the
	    strictest pass — it has to be, since it does not know who is reading — so it hashes out
	    names that are fine for most of the server.
	  * `GetNonChatStringForUserAsync(viewerId)` gives a string filtered for ONE reader, which is
	    how Roblox intends user-authored text that is shown to specific people to be handled: an
	    adult sees more than a child does, and neither sees something they should not.

	We use the second. The cost is that the sign's title can no longer be a server-side write —
	a SurfaceGui in Workspace shows every player the same text — so the SERVER only ever writes
	the safe default (`SignTitleFormat` over a Roblox display name, which is already moderated),
	and each client is sent ITS OWN filtered copy and writes that over the top locally. That is
	`PlotService` (filtering, one call per viewer) and `DealershipSignController` (painting).

	IF A NAME COMES BACK HASHED FOR A VIEWER, THAT VIEWER GETS THE DEFAULT. Not the hashes: a sign
	reading "#### Motors" tells the reader nothing except that somebody was moderated, and it looks
	like a bug. They see "<Owner>'s Dealership" — a correct sign — while everyone the name passed
	for reads the name. The owner is not told which players got the fallback, and there is nothing
	useful they could do with that if they were.

	FAIL CLOSED, EVERYWHERE. A filter call that errors (Roblox rate limit, a service blip) is
	treated exactly like a hashed result: the default. There is no path in this feature where text
	nobody has filtered reaches another player's screen.

	=== WHAT A NAME MAY BE ====================================================================

	`sanitize` below is a gate in FRONT of the filter, not a substitute for one. It exists for two
	reasons the filter does not cover: the sign is a fixed-width banner with one line on it, so
	length has to be bounded; and the character whitelist keeps out the control codes, zero-width
	joiners and right-to-left overrides that render as garbage or as a name that is not what it
	looks like. Anything about MEANING is the filter's job and only the filter's. ]]
PlotConfig.Rename = {
	Enabled = true,

	--[[ Graphemes, not bytes, and both ends matter. The floor stops single-character signs, which
		read as an unfinished feature rather than as a name. The ceiling is what the banner can show:
		the title box is 676 px of a 1080 px canvas with a 24 px floor on the text size, and 20
		characters of Ubuntu Bold is about where a name stops being legible from the plaza. ]]
	MinLength = 3,
	MaxLength = 20,

	--[[ Seconds between one player's rename requests. This is a WEB CALL rate limit before it is a
		spam limit: `FilterStringAsync` is rate-limited per server by Roblox, and a held-down button
		would spend that budget on one player and start failing renames for everyone else. ]]
	CooldownSeconds = 5,

	--[[ A CONTROLLER'S WAY IN (2026-10-15). The pencil is a button on a SurfaceGui in the world, which
		a pad can neither point at nor select, so on a pad the rename box could never be opened. For a
		pad player, at their own sign, the sign also carries Roblox's own prompt, and pressing it is
		pressing the pencil (`DealershipSignController._bind`). Y, as the workshop sign's is: X belongs
		to the podiums. `MaxDistance` is from the sign, which hangs about 13 studs over the forecourt. ]]
	PadPrompt = {
		Key = Enum.KeyCode.ButtonY,
		MaxDistance = 20,
		ActionText = "Rename",
		ObjectText = "Dealership",
	},

	-- The modal's copy. Everything the rename screen says is here rather than in the controller, so
	-- the wording can be changed without opening client code.
	Title = "Name your dealership",
	--[[ Under the title bar. It is the one line on the screen that says the quiet part — this name
		goes on a sign in a public place — and it is why the modal has room for a sentence at all. ]]
	Prompt = "Everyone on the plaza reads this off your sign.",
	Placeholder = "Midnight Motors",
	ConfirmText = "Save",
	ResetText = "Use my name",
	-- `%d/%d` — characters typed over the ceiling, under the box.
	CountFormat = "%d/%d",

	--[[ What the modal says back. `Saved` and `Cleared` are the only two that are not a refusal;
		the rest are shown in the kit's warn amber and leave the box open with the text still in it,
		so a rejected name can be edited rather than retyped. ]]
	Messages = {
		Saved = "Sign updated.",
		Cleared = "Back to your own name.",
		TooShort = "That's too short. Use %d characters or more.",
		TooLong = "That's too long. Use %d characters or fewer.",
		BadCharacter = "Letters, numbers and basic punctuation only.",
		NeedsLetters = "Use at least one letter or number.",
		Filtered = "That name didn't pass the filter.",
		FilterFailed = "Couldn't check that name. Try again in a moment.",
		NotYours = "You don't have a dealership in this server.",
		TooFast = "Give it a second.",
	},
}

-- === Liking somebody else's dealership ======================================

--[[ The heart on the sign. Press it once on a lot that is not yours and that player's lifetime like
	count goes up by one, on their save, forever.

	=== A LIKE BELONGS TO THE PLAYER, NOT TO THE PLOT ==========================================

	Note 1 at the top of this file is the reason: a plot is a SEAT, held for a session and handed to
	whoever sits down next. Counting likes against plot 4 would mean a player walks away from a lot
	they had built up and the next person to join inherits their reputation. So the count lives in the
	OWNER'S PROFILE and the plot is only where it is displayed.

	Which also settles a question that looks harder than it is: a like can only ever be given to a
	player who is IN THIS SERVER, because a sign with no owner has no heart on it. Both profiles are
	therefore loaded and session-locked here, and there is no cross-server write, no offline save to
	reach into, and no ordered store to reconcile. That is a real constraint and not just a
	convenience — see `LeaderboardService` for what it costs to read a number belonging to somebody
	who is not here.

	=== IT IS ONE-WAY, AND ONCE ===============================================================

	There is no un-like. Two reasons, and the second is the one that decides it:

	  * The number is meant to be a lifetime brag, in the same family as `Stats.Steals` — a figure
	    that only goes up is a figure worth showing on a sign. A count that can be taken away turns
	    every visitor into somebody who might cost you something.
	  * A toggle is a griefing surface for free. Like/un-like/like is a loop somebody will hold down,
	    and it would land on ANOTHER player's save. One irreversible press per pair cannot be spammed
	    into anything at all.

	The cost is that a mis-tap is permanent. That is an acceptable cost because of what the mis-tap
	does: it says something nice about a stranger.

	=== WHERE THE "ALREADY LIKED" ANSWER IS STORED ============================================

	On the LIKER, as `GivenKey` — a map of the user ids whose dealership they have liked. It could
	equally be a list of likers on the OWNER's profile, and that shape is the one to avoid: a popular
	player's save would grow one entry per person who ever walked past, without bound, against a
	4 MB datastore key. Keeping it on the giver bounds the table by how many DISTINCT dealerships one
	player has ever visited, which is bounded by how much they have played.

	The price of splitting it is that the count and the set can drift if one of the two writes is lost
	to a crash — the two profiles are different keys and there is no transaction across them. Both
	writes are therefore made back to back with no yield between them, and the residual risk is that a
	like is silently dropped, which nobody can see. The ordering is chosen so the failure is that way
	round rather than a double count; see `PlotService._onLike`. ]]
PlotConfig.Likes = {
	Enabled = true,

	--[[ Seconds between one player's like ATTEMPTS. Unlike the rename's cooldown this is not
		protecting a Roblox web budget — nothing here calls out — it is protecting two profiles from a
		held-down button, and the "you already liked this one" check is the real gate. So it is short
		enough to be invisible to a player pressing hearts down a row of six signs. ]]
	CooldownSeconds = 1,

	-- Profile key on the RECEIVER holding their lifetime count. Absent is zero.
	ProfileKey = "Likes",
	-- Profile key on the GIVER: `{ ["12345"] = true }`, the dealerships they have already liked.
	GivenKey = "LikesGiven",

	--[[ Mirrored onto the owner's Player so the sign can be painted from an attribute change rather
		than from a service call, exactly as the valuation is (`GarageConfig.ValueAttribute`).
		Attributes replicate, so this is also how any other screen gets the number for free.

		NO ATTRIBUTE IS NOT ZERO: it is stamped when the profile lands, which is after the claim, so a
		nil here means "not known yet" and the pill stays hidden rather than claiming a zero. ]]
	Attribute = "DealershipLikes",

	--[[ The heart, in its two states. Emoji rather than an uploaded image for the same reason the
		pencil is one: it needs no asset id, it is the same size on every sign, and the filled version
		renders red on its own so the state survives a `TextColor3` nobody remembered to set.

		The hollow heart is the LIKEABLE state and the filled one means "already yours" — which is
		also what the owner sees on their own sign, because their own count is a readout and there was
		never anything for them to press. ]]
	Icon = "🤍",
	LikedIcon = "❤️",
}

--[[ Keep a title on ONE line. Every space becomes a non-breaking one — see SignNonBreakingSpace
	for why that is required and why the two obvious alternatives silently do not work.

	Shared rather than duplicated because BOTH sides write the sign now: the server paints the
	default, the client paints the filtered custom name over it, and a title that was one-lined by
	one of them and not the other would wrap for exactly the players whose filter let the name
	through. ]]
function PlotConfig.oneLine(text: string): string
	return (string.gsub(text, " ", PlotConfig.SignNonBreakingSpace))
end

--[[ The sign a player gets when they have not named their lot — or when the name they chose did
	not pass the filter for whoever is reading it.

	Falls back to `Name` because a title reading "'s Dealership" is worse than any name it could
	possibly show. A player with no display name set has `DisplayName == Name`, so this is only
	reached if the first is somehow blank. ]]
function PlotConfig.defaultTitle(displayName: string?, userName: string?): string
	local name = displayName
	if not name or name == "" then
		name = userName
	end
	if not name or name == "" then
		return PlotConfig.SignVacantText
	end
	return string.format(PlotConfig.SignTitleFormat, name)
end

--[[ Clean up what the player typed and decide whether it is a name at all. Returns the cleaned
	string and nil, or nil and one of `Rename.Messages`.

	AN EMPTY RESULT IS A VALID ANSWER, not a rejection: clearing the box is how a player goes back
	to "<Name>'s Dealership", and the modal's RESET button sends exactly that. So `""` comes back
	with no error and the caller reads it as "clear the name".

	Runs on the SERVER as well as in the modal, and the server's answer is the one that counts —
	the client copy is there so a refusal is instant and does not cost a round trip, not because
	anything trusts it. ]]
function PlotConfig.sanitize(text: unknown): (string?, string?)
	local messages = PlotConfig.Rename.Messages
	if type(text) ~= "string" then
		return nil, messages.BadCharacter
	end

	--[[ Collapse whitespace before anything else measures the string. `%s` covers the tab and
		newline a paste can carry in, and the collapse means "Midnight   Motors" is the same name as
		"Midnight Motors" rather than a second one that looks identical on the sign. ]]
	local clean = string.gsub(text, "%s+", " ")
	clean = string.match(clean, "^%s*(.-)%s*$") or ""

	if clean == "" then
		return "", nil -- clearing the name; see the note above
	end

	--[[ The whitelist. Anything outside it is refused rather than stripped, because stripping turns
		a typo into a different name the player did not choose and would have to notice on the sign.

		It is ASCII by construction, which also settles the direction-override and zero-width-joiner
		class of problem outright: `%w` in Luau is ASCII letters and digits, so every byte over 127
		lands here. The apostrophe is in because "Bob's Motors" is the most obvious name anyone will
		type; `#` is deliberately OUT, because a `#` in a filtered result is how we know the filter
		hashed something (see `isFiltered`). ]]
	if string.find(clean, "[^%w '&%.%,%-%!%?]") then
		return nil, messages.BadCharacter
	end

	-- ...and at least one character that is not punctuation, so "..." and "---" are not signs.
	if not string.find(clean, "%w") then
		return nil, messages.NeedsLetters
	end

	--[[ Graphemes rather than `#clean`, so the length the player is held to is the length they can
		count on the screen. With the ASCII whitelist above the two agree today — this is here so
		that widening the whitelist later cannot silently change what the limits mean. ]]
	local length = utf8.len(clean) or #clean
	if length < PlotConfig.Rename.MinLength then
		return nil, string.format(messages.TooShort, PlotConfig.Rename.MinLength)
	end
	if length > PlotConfig.Rename.MaxLength then
		return nil, string.format(messages.TooLong, PlotConfig.Rename.MaxLength)
	end

	return clean, nil
end

--[[ Did the filter hash any of this? `TextService` replaces what it censors with `#`, and the
	whitelist above guarantees a name can never contain one of its own — so a single `#` anywhere
	means this viewer is not allowed to read this name, and they get the default instead.

	An empty result counts as filtered too: a name that came back with nothing left of it is not a
	sign, it is a blank banner. ]]
function PlotConfig.isFiltered(text: unknown): boolean
	if type(text) ~= "string" or text == "" then
		return true
	end
	return string.find(text, "#", 1, true) ~= nil
end

--[[ A like count for the pill. Grouped in thousands, and given a suffix once grouping stops helping.

	IT IS NOT `GarageConfig.formatCash` WITHOUT THE DOLLAR SIGN, and the difference is the band each
	one switches at. Cash goes to a suffix at 100,000 because the pill it lives in is narrow and
	nobody watches the hundreds digit of a six-figure balance tick over. A like count is a small
	number for a long time and every digit of it matters to the person it belongs to — "1,284" is a
	figure somebody earned one press at a time, and "1.2K" throws away the last three of them. So the
	suffix does not start until a million, which is a count no sign is ever going to have to show and
	is here so that the label cannot be overflowed by one either.

	Shared with the command that builds the sign only in spirit — the SERVER is the one writer of this
	text (see `SignLikeCountName`), so unlike the title there is no second painter to disagree with. ]]
function PlotConfig.formatLikes(count: number?): string
	local whole = math.max(0, math.floor(count or 0))
	if whole >= 1e6 then
		return string.format("%.1fM", whole / 1e6)
	end

	local grouped = tostring(whole)
	local replaced
	repeat
		grouped, replaced = string.gsub(grouped, "^(%d+)(%d%d%d)", "%1,%2")
	until replaced == 0
	return grouped
end

-- Headshot source. `rbxthumb` resolves client-side with no web call and, unlike
-- `Players:GetUserThumbnailAsync`, does not yield — so the sign can be filled in synchronously.
PlotConfig.SignHeadshotFormat = "rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420"

-- === Finding your way back to it ============================================

--[[ THE WAYPOINT OVER YOUR OWN LOT. Drive off into the city in the lobby and a pin carrying your
	own headshot fades up over your dealership; drive back and it fades away again. It is drawn by
	`DealershipMarkerController` and by nothing else, and only ever for the player who owns the lot.

	WHY IT EXISTS. Six plots, all built from the same reference layout, spread over about 1,200
	studs of plaza. Standing on your own forecourt the sign tells you whose it is; two streets away
	every lot is the same building, and the only way back was to read six signs. The sign answers
	"whose is this?" for a visitor. This answers "where is mine?" for the owner, which is a
	different question and needs a different widget.

	FOUR THINGS SHAPE THE CODE THAT DRAWS IT.

	1. IT IS PURELY CLIENT SIDE, and that is not an optimisation. A marker saying "yours" is per
	   viewer by definition, and there is no per-viewer value of a replicated property (the same
	   reasoning the custom name and the heart are built on, further up this file). So it is one
	   `BillboardGui` in the owner's own `PlayerGui`, and the server is not involved at all: the
	   plot's index is already on the Player as `PlayerPlotAttribute` and the headshot is a
	   `rbxthumb` URL, which is everything the client needs.

	2. THE POSITION IS CACHED, BECAUSE THE PLOT STREAMS OUT. `StreamingEnabled` is on, so the lot
	   you are trying to find your way back to is frequently NOT in your DataModel, which is the
	   exact moment the marker is wanted. So the controller records where the plot is the first
	   time it sees it, adorns to an anchor of its own, and never needs the model again. A marker
	   adorned to a part of the plot would switch itself off at range and be a marker that works
	   only when you can already see the building.

	3. IT STANDS DOWN FOR A RACE. `RaceStart` hides it and `RaceEnd` brings it back, the same
	   bracket the play button and the cash pill use, for the reason `RaceEntryController` states:
	   a race is the one part of this game the player has to read, and the lobby's furniture has no
	   business over the road. It would also be pointing several thousand studs sideways.

	4. IT GETS OUT OF THE WAY WHEN YOU ARE THERE. Below `HideStuds` it is gone entirely. The lot is
	   in front of you at that range and its sign is readable, so a pin over the roof is covering
	   the showroom you came back to look at.

	ONE THING IT DELIBERATELY DOES NOT DO: there is no off-screen edge arrow. A billboard draws
	only where its anchor is in frame, so a dealership behind you shows nothing and you turn around
	to find it. That is the ordinary bargain for a world marker and the alternative is a
	screen-space compass, which is a much larger feature than the question being answered here. ]]
PlotConfig.Marker = {
	-- Master switch. Off = the controller builds nothing and connects nothing.
	Enabled = true,

	--[[ The distance band the pin fades across, measured from the player's own root to the plot's
		anchor. Gone below `HideStuds`, full strength above `ShowStuds`, linear between.

		A RAMP RATHER THAN A THRESHOLD WITH HYSTERESIS. Two thresholds would need the controller to
		remember which side it was last on, and the state that buys you is a marker that pops. A
		ramp cannot flicker at the boundary because there is no boundary to sit on.

		THE NUMBERS COME OFF THE PLOT'S OWN FOOTPRINT, which is 157 by 138 studs. Standing at the
		far corner of your own lot is about 105 studs from its centre, so `HideStuds` has to clear
		that or the pin turns up while you are still parked on your own forecourt. ]]
	HideStuds = 140,
	ShowStuds = 210,

	--[[ Studs of clear air between the top of the plot's bounding box and the tip of the pin's
		tail. Measured against the box rather than a fixed height because a plot with its second
		floor bought is 24 studs taller (`FloorSpacing`), and a marker that sank into the roof the
		day somebody upgraded would be a bug nobody could reproduce on a fresh save. ]]
	Clear = 10,

	--[[ The float, as a FRACTION OF THE PIN'S OWN HEIGHT and a period in seconds. A pin that sat
		dead still reads as a decal painted on the roof rather than as something hanging above it.

		A fraction and not the studs the getaway marker's bob is quoted in, because that marker is
		over a truck at most 460 studs away and this one lives out to about 1,200. Half a stud of
		world-space movement at that range is less than a pixel, so a bob in studs would simply
		stop existing at the ranges this thing is for. ]]
	BobFraction = 0.035,
	BobPeriod = 2.6,

	--[[ Pixels at `RefStuds`, shrinking with distance between `MinScale` and full size.

		Offset and not scale, for `GetawayConfig.Hud.Marker`'s reason: a billboard sized in studs is
		unreadable at the ranges this thing exists for. The mild shrink on top of that is what stops
		it reading as a HUD element pasted over the world. Full size as you pull off your own
		forecourt, settling to about two thirds of that once you are across the plaza.

		The height is the texture's own 1024/700 aspect at this width. Keep the two in step or the
		headshot, which is a circle, draws as an ellipse. ]]
	Size = Vector2.new(104, 152),
	RefStuds = 260,
	MinScale = 0.62,

	--[[ How solid it gets at full strength.

		THE PLATE IS THE ONLY THING HELD OFF OPAQUE. The headshot is the answer to the question
		being asked and is drawn at full strength; the navy plate behind it is a backing board, and
		a little of the street showing through it is what keeps a waypoint from reading as a hole
		punched in the world. The house note on effect intensity applies: this is a thing you
		noticed, not a thing that announced itself. ]]
	PinTransparency = 0.1,
	CaptionTransparency = 0.15,

	--[[ The line under the face. `%d` is whole studs, and the wording is
		`GetawayConfig.Hud.Marker.DistanceFormat`'s and the tutorial chip's, so the three of them
		cannot quote the same gap in three different units. See `UIAssets.MarkerBox` for why this
		can be a sentence with a space in it without `TextScaled` wrapping it. ]]
	DistanceFormat = "%d studs",
	CaptionColor = Color3.fromRGB(238, 242, 255),
	--- Quoted at the full marker and scaled down with it, so the outline never thickens into the
	--- glyphs as the pin shrinks. `Contextual`, like every other outlined label in this game.
	CaptionStrokeThickness = 1.5,
	CaptionStrokeColor = Color3.fromRGB(6, 8, 12),

	--[[ THE BAND IT USES WHILE YOUR HANDS ARE FULL, and closing a hole rather than adding a feature.

		A carried car (`CarryConfig`) has to be taken somewhere, and the somewhere is the thing this
		pin already points at. Shipped, though, the pin is gone below `HideStuds` (140) and the bays
		only glow within `CarryConfig.Glow.Studs` (90), which leaves a fifty stud ring around your own
		lot where a player holding a car is told nothing by anything.

		BOTH NUMBERS WERE RIGHT ON THEIR OWN. 140 clears the far corner of your own forecourt, so the
		pin does not hang over you while you are standing on the thing it is pointing at. 90 is close
		enough that a lit deck reads as an invitation rather than as signage. They were simply never
		asked to meet, because until the carry existed there was nothing that had to cross from one
		to the other in a single walk.

		SO THE HANDOVER IS INSIDE THE GLOW'S RANGE, not at the edge of it. Twenty studs of overlap,
		during which both are up: an overlap cannot flicker, and a gap can.

		THE FACE AND THE LINE UNDER IT DO NOT CHANGE. There is one line on this plate and it is
		already carrying the only number worth having on the walk in, which is how far there is
		left to go. What to do when you arrive is the glow's job, then the podium prompt's, then
		the card's. A waypoint that tried to say all of it would be saying it in nine pixels.

		ON FOR EVERY CARRY RATHER THAN THE FIRST. `CarryConfig.Guide` is the first-timer's half and
		it is deliberately only words; nobody stops needing to know which of six identical buildings
		is theirs. ]]
	Carry = {
		--- Off = the pin keeps the ordinary band whatever is in the player's hands, which is exactly
		--- what it did before this table existed.
		Enabled = true,
		HideStuds = 70,
		ShowStuds = 120,
	},

	--[[ PRESS THE FACE, GO HOME (2026-10-12). The headshot on the pin is a button: one press puts the
		player back on their own `PlotSpawn` pad (`PlotService._onGoHome`).

		Refused mid-race and during the trip home after one, which is also when the pin is not drawn.
		A player sitting in a seat is stood up first and moved only once the seat has let go; if that
		seat is in their OWN lobby car, the car is put away behind them. Somebody else's car is only
		got out of, never despawned. ]]
	Home = {
		--- Off = the face is a plain picture again, exactly as before this table existed.
		Enabled = true,
		--- Per player, stamped on the ATTEMPT, the same rule as the rename and the heart.
		CooldownSeconds = 2,
		--- How long the server waits for the lot to stream in on that client before moving them.
		StreamTimeout = 3,
		--- Studs above the pad the character is set down at. `RaceService._returnCFrame` uses 4 too.
		Lift = 4,

		--[[ THE TOUCH LAYOUT (2026-10-13, punch list M1). On a phone the BACK TO BASE card's bottom-left
			spot is the thumbstick, and its 150x62 floor is a fifth of an iPhone 7's height. On touch
			it becomes a one-line pill docked centred over the Play button instead, sized off the
			screen's height and measured off where Play actually is, so it follows Play when the
			hotbar lifts it. It hides whenever Play does (a page open, a race) and while the tutorial
			is still running, because the tutorial's arrow points at Play from exactly that spot.

			=== EVERY DEVICE, NO HEADSHOT, SMALLER — 2026-10-13 ===
			The owner: "move it on top of the Play button, maybe remove the player headshot and make it
			more compact". WAS touch-only, with the headshot, HeightShare 0.1 / Max 50 / Aspect 4.4. IS
			on keyboard and gamepad too (`DealershipMarkerController._touchHome`), caption only, and
			smaller: 0.07 of the screen's height, at most 40px, 3.2 wide per high — the caption with
			breathing room and nothing else. Off = the bottom-left card on every device, as before.

			=== IT GROWS ON A BIG SCREEN — 2026-10-14 ===
			The owner, on a large monitor: "this Back to Base button is pretty small". WAS 0.07 of the
			height capped at 40px, so every screen over ~570px tall drew the same 40px pill, a
			third of Play's height at 1142px. IS 0.05 capped at 64: a phone still sits on the 34px
			floor (0.05 of 414 is 21), a 1080p screen gets 54, and 1440p and up get 64. ]]
		Touch = {
			Enabled = true,
			--- The pill's height as a share of the screen's height, then clamped to these pixels.
			--- 34 is the smallest that still takes a thumb; iPhone 7 lands on it.
			HeightShare = 0.05,
			MinHeight = 34,
			MaxHeight = 64,
			--- Pixels wide per pixel high: one line of caption with a little room either side.
			Aspect = 3.2,
			--- Pixels between the pill's bottom edge and the top of Play.
			Gap = 6,
			--- How far below its resting spot it slides in from, in pixels.
			Slide = 10,
			Title = "BACK TO BASE",
		},
	},
}

--[[ Fallback spawn placement, used ONLY when a plot has no authored `PlotSpawn` (see note 3).

	Expressed in PLOT-LOCAL space, which is the frame `docs/MapLayout.md` §3.3 defines: origin at
	the ground centre of the plot, local +X across the frontage, local +Y up, and local +Z DEEPER
	INTO the showroom, away from the plaza. So a negative Z sits out on the forecourt in front of
	the building, which is where you want to arrive — outside, looking in at your own cars.

	`Y` is not configured: the creator raycasts for the forecourt surface and sits the pad on it,
	because the deck heights are derived from the floor mesh everywhere else in this map too and a
	hardcoded Y is the one number that silently breaks if the slab ever moves. ]]
PlotConfig.Fallback = {
	LocalX = 0,
	LocalZ = -30,

	-- Rotate to face local +Z, i.e. turn around and look at the showroom rather than out at the
	-- plaza. The whole point of arriving on your own lot is seeing what is parked on it.
	FaceShowroom = true,

	Size = Vector3.new(10, 1, 10),
}

return PlotConfig
