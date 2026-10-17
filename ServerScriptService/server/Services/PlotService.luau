--[[
	PlotService  (server)
	---------------------
	Owns WHO HAS WHICH DEALERSHIP for the length of a session. One job, deliberately: claim a free
	plot when a player joins, point their spawn at it, and put it back in the pool when they leave.

	It is called PlotService and not TycoonService because it owns the LOT, not the economy. Income
	per second, bay upgrades, rebirth and the rest are a separate service's problem — they need this
	one to answer "which plot is this player's?" and nothing more. Keeping the claim separate from
	the economy is what lets the economy be rewritten without touching spawning.

	THE JOIN ORDER IS THE WHOLE SERVICE:

	  1. `Players.CharacterAutoLoads` is turned OFF at init, so no character exists yet.
	  2. observePlayer fires -> claim the lowest-numbered free plot.
	  3. Stamp ownership (server table + replicated attributes) and set `player.RespawnLocation`
	     to that plot's spawn pad.
	  4. THEN `player:LoadCharacter()`.

	Steps 3 and 4 are in that order for one reason: `RespawnLocation` only decides where a character
	lands if it is set BEFORE the character loads. Left on auto-load, Roblox spawns the character the
	instant the player joins, which beats the assignment — the player's first life starts at whatever
	enabled SpawnLocation the engine felt like, and they have to die once to reach their own lot.

	The cost of taking over loading is that EVERY exit from assignment has to end in a character,
	including the failures. A player with no plot, a player who joined a full server, a player whose
	plot lookup threw — all of them still get `LoadCharacter`. That is why the load sits at the end
	of `_onPlayerAdded` rather than inside the success branch: there is no path where forgetting it
	leaves someone staring at a grey screen.

	AND THAT COST INCLUDES RESPAWNING (`_watchDeath`), which is not obvious and was missed for long
	enough to cost a playtest. Switching auto-loads off does not merely delay the first character —
	the engine never loads one again, so before this every death in the game was permanent. The
	player kept a Humanoid with no parts, the camera stayed locked on it, and the only way back was
	rejoining the server.

	WHY DISCOVERY IS PATH-SCOPED AND NOT TAG-ONLY. Map work leaves tagged copies of plots lying
	around Workspace — `workspace.Plot7` is a full copy of Plot1, 478 studs off the island, tagged
	`Plot` and claiming `PlotIndex` 1. A tag-only lookup finds it, hands it to a player and spawns
	them in the sea, and the duplicate index silently shadows the real plot 1. So a plot has to be a
	descendant of `Map.Plots` AND carry a unique index. Numbered plots inside that folder have their
	metadata repaired on discovery; tagged copies outside it remain ineligible. See PlotConfig note 1.

	THE SIGN IS FILLED IN, NOT BUILT. Each plot carries an authored owner sign over its showroom
	entrance — an invisible plate and a SurfaceGui put there by the `BuildDealershipSigns` Command
	Runner command. This service only writes text and a headshot into it on claim and blanks it on
	release. It needs no remote and no Replica to do that: a SurfaceGui in Workspace replicates to
	everyone already, which is exactly right for a sign whose job is telling OTHER players whose lot
	they are standing on.

	=== THE CUSTOM NAME IS THE ONE THING THE SERVER DOES NOT WRITE =============================

	The pencil on the sign lets the owner name their dealership, and that is text one player writes
	and every other player reads — so it goes through `TextService`, and it is filtered PER VIEWER
	(`GetNonChatStringForUserAsync`) rather than once for the whole server. The reasoning is in
	`PlotConfig.Rename`; what it means HERE is the shape of the code below:

	  * the server writes only the SAFE DEFAULT onto the sign — "<DisplayName>'s Dealership" over a
	    display name Roblox has already moderated — because one SurfaceGui shows everybody the same
	    string and there is no per-viewer version of a replicated property;
	  * each client is sent its own filtered copy over `DealershipName` and paints it locally
	    (`DealershipSignController`), or is sent nothing and leaves the default standing;
	  * a filter call that hashes the name OR ERRORS is the same answer — that viewer gets the
	    default. There is no path here where unfiltered text reaches another player's screen.

	The profile stores what the player TYPED, unfiltered, which is Roblox's own guidance: a verdict
	belongs to a viewer and a moment, not to a save file. So it is re-filtered on every claim.

	Every filter call yields, so every one of them is off the join path in its own thread, and each
	one re-checks `record.owner` and `record.token` on the way out — a name that arrives after the
	plot changed hands must never land on the new owner's sign.

	=== AND THE HEART IS THE ONE THING THAT WRITES TO SOMEBODY ELSE'S SAVE =====================

	The pill on the sign lets a visitor like the lot they are standing on, which moves a number in the
	OWNER'S profile — the only place in this game where one player's press reaches another player's
	data. `PlotConfig.Likes` has the design; three things about it shape the code below.

	  * A like belongs to the PLAYER, not to the plot, because a plot is a seat (PlotConfig note 1).
	    So it can only ever be given to somebody who is in this server — a vacant sign has no heart —
	    and both profiles are therefore loaded, session-locked and writable here. No cross-server
	    write, no offline save, nothing to reconcile.
	  * It is one-way and once. What stops a second one is a set of user ids on the GIVER's profile,
	    not a list of likers on the receiver's, so a popular player's save does not grow with their
	    popularity.
	  * The two writes land back to back with no yield between them, and the giver is marked before
	    the receiver is credited, so the failure mode is a lost like rather than a repeatable one.

	The COUNT is public and goes straight onto the replicated sign, like the valuation. What is
	per-viewer is only which heart you are looking at, and that goes over `DealershipLike` and is
	painted locally — the same split as the custom name, for the same reason.

	Cleanup is Trove throughout: one service-level trove for the things that live as long as the
	service (the player observer, the CharacterAutoLoads override), and one trove per assignment that
	holds everything stamped onto the world for that claim. Releasing a plot is `trove:Destroy()` —
	which matters more than it looks, because the list of things an assignment touches is going to
	grow (owner billboard, claim barrier, the bays themselves), and every one of those is a leak on
	`PlayerRemoving` if release is a hand-written list of undo statements instead of a trove.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Observers = require(ReplicatedStorage.Packages.Observers)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)
--[[ A CONFIG, NOT `GarageService`, the same call `OfflineService` makes about `UpgradeConfig`: all
	the sign needs is the attribute's name and how to format money, both of which are pure. Taking
	the service would add a dependency edge for two lookups. ]]
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local Data = require(script.Parent.Parent.Data)

-- The three widgets inside an authored sign, resolved once at discovery so the paint path is
-- straight-line property writes and a malformed sign is reported at startup, not on someone's join.
type SignParts = {
	title: TextLabel,
	headshot: ImageLabel,
	edit: GuiButton,
	-- Optional: absent on any sign built before the valuation shipped. See `_resolveSign`.
	value: TextLabel?,
	--[[ Optional for the same reason, and as a PAIR — the pill and the number inside it arrived
		together and a sign that has one without the other is a sign somebody hand-edited. ]]
	like: GuiButton?,
	likeCount: TextLabel?,
}

type PlotRecord = {
	index: number,
	model: Model,
	spawn: SpawnLocation,
	sign: SignParts?,
	owner: Player?,

	--[[ The owner's custom name as they typed it, and the `TextFilterResult` it produced. The result
		is kept for the session because it is what answers "what may THIS viewer read?" — one call
		per viewer, rather than one filter pass per player who walks past.

		`token` is bumped on every change to either, and every thread that yields to filter something
		compares it on the way back. Without it a broadcast that started before a rename (or before
		the lot changed hands) would wake up and send the old name for a plot that no longer has it. ]]
	name: string?,
	filter: any?,
	token: number,
}

local PlotService = Shard.new("PlotService")

PlotService:withSignals({
	"PlotAssigned", -- (player: Player, plot: Model, index: number)
	"PlotReleased", -- (player: Player, plot: Model, index: number)
	"DealershipRenamed", -- (player: Player, index: number, name: string?)  nil = back to the default
	--[[ (liker: Player, owner: Player, count: number): somebody pressed the heart on `owner`'s sign
		and it counted. Fired once per like that is actually banked — never for a refusal, a repeat
		or a press on your own lot — so anything hanging off it (a quest, a board, a chat line) can
		treat it as one player thanking another. ]]
	"DealershipLiked",
})

PlotService:withRemoteEvents({
	--[[ server -> client (index: number, name: string?): what THIS player may read as the title of
		plot `index`. `nil` means "no custom name for you" and the client leaves the owner's default
		standing — either because the lot has no custom name or because the filter hashed it for
		this particular reader. The client is never told which. ]]
	"DealershipName",
	-- server -> client (ok: boolean, message: string): the answer to this player's own rename.
	"DealershipNameResult",

	--[[ server -> client (ownerUserId: number, liked: boolean): whether THIS player has already
		liked that player's dealership. The count on the sign is not in here — it is a public number
		on a replicated SurfaceGui and every viewer reads the same one; what is per-viewer is only
		which heart you are looking at.

		KEYED BY THE OWNER AND NOT BY THE PLOT, which is the detail that makes the whole thing cheap:
		a like belongs to a player (see `PlotConfig.Likes`), so this answer stays true no matter how
		many times the lot changes hands, no client cache is ever invalidated by a claim, and a
		message that arrives late is still correct rather than merely stale.

		It is also THE ANSWER TO EVERY REQUEST, including the refusals. A client disables its heart
		while a press is in flight and re-enables it on this, so a refusal that said nothing would
		leave a dead button — a "no" here is simply the truth re-asserted. ]]
	"DealershipLike",
	{
		--[[ client -> server (text: string): the pencil on their own sign. An empty string is a
			valid request and means "put it back to my name". Everything about it is re-checked
			here — ownership, length, characters, the filter — because the client's copy of those
			rules exists to make a refusal instant, not to be trusted. ]]
		RequestDealershipName = function(player: Player, text: unknown)
			PlotService:_onRename(player, text)
		end,

		--[[ client -> server (index: number): the heart on plot `index`. THE PLOT IS NAMED, NOT THE
			PLAYER, deliberately — the server resolves who is behind that sign itself, so a client
			cannot aim a like at a user id that is not currently standing behind one. Everything else
			is re-checked too: that the lot is claimed, that it is not the presser's own, and that
			they have not already liked that player in this or any past session. ]]
		RequestDealershipLike = function(player: Player, index: unknown)
			PlotService:_onLike(player, index)
		end,

		--[[ client -> server: my sign controller is bound, so anything sent now will be painted.
			Fired once from the controller's `start`, and answered with every named plot in the
			server and every current owner's like state. Without the handshake the answer is a
			race — a name broadcast while the client was still requiring its controllers is a name
			nobody hears, and the sign silently reads the default for the rest of that session.

			IT COVERS BOTH FEATURES rather than each having its own ping, because it is one fact
			being reported ("my signs are bound") and the two answers go to the same widgets. It was
			called `DealershipNameReady` when the name was the only per-viewer thing on a sign. ]]
		DealershipSignReady = function(player: Player)
			PlotService:_onReady(player)
		end,

		--[[ client -> server: the headshot on the dealership pin was pressed. Take me home. Carries
			nothing, so there is nothing to check but the player's own state; see `_onGoHome`. ]]
		RequestGoHome = function(player: Player)
			PlotService:_onGoHome(player)
		end,
	},
})

-- === Discovery ==============================================================

--[[ Find the claimable plots, lowest index first.

	2026-10-12: duplicating Plot1 also duplicates its index and can leave only one claimable lot.
	Inside the authored folder, PlotN is an unambiguous identity: repair its tag/index from that
	name before validating uniqueness. Other names still need explicit metadata, and copies outside
	Map.Plots remain excluded. Duplicate identities are refused rather than handed to two players. ]]
function PlotService._discoverPlots(self): { PlotRecord }
	local map = workspace:FindFirstChild(PlotConfig.MapName)
	local folder = map and map:FindFirstChild(PlotConfig.PlotsFolderName)
	if not folder then
		self.log:warn(
			string.format("No %s.%s in Workspace — no plots can be claimed.", PlotConfig.MapName, PlotConfig.PlotsFolderName)
		)
		return {}
	end

	local records: { PlotRecord } = {}
	local seen: { [number]: Model } = {}
	local models = folder:GetChildren()
	-- Named lots reserve their identities before custom tagged models can claim the same number.
	table.sort(models, function(a, b)
		local aNamed = a:IsA("Model") and a.Name:match("^Plot([1-9]%d*)$") ~= nil
		local bNamed = b:IsA("Model") and b.Name:match("^Plot([1-9]%d*)$") ~= nil
		return if aNamed ~= bNamed then aNamed else a.Name < b.Name
	end)

	for _, model in models do
		if not model:IsA("Model") then
			continue
		end
		local namedIndex = tonumber(model.Name:match("^Plot([1-9]%d*)$"))
		if namedIndex then
			if model:GetAttribute(PlotConfig.IndexAttribute) ~= namedIndex or not CollectionService:HasTag(model, PlotConfig.PlotTag) then
				self.log:warn(string.format("%s had copied or missing plot metadata — repaired as plot %d.", model.Name, namedIndex))
				model:SetAttribute(PlotConfig.IndexAttribute, namedIndex)
				CollectionService:AddTag(model, PlotConfig.PlotTag)
			end
		end
		if not CollectionService:HasTag(model, PlotConfig.PlotTag) then
			continue
		end
		local index = model:GetAttribute(PlotConfig.IndexAttribute)
		if type(index) ~= "number" or index ~= index or index % 1 ~= 0 then
			self.log:warn(string.format("%s has no usable %s attribute — skipped.", model.Name, PlotConfig.IndexAttribute))
			continue
		end
		if seen[index] then
			self.log:warn(
				string.format("%s claims %s %d, already held by %s — skipped.", model.Name, PlotConfig.IndexAttribute, index, seen[index].Name)
			)
			continue
		end
		seen[index] = model

		local spawn = self:_resolveSpawn(model)
		if spawn then
			-- The sign is cosmetic: a plot without one is still perfectly claimable.
			table.insert(records, {
				index = index,
				model = model,
				spawn = spawn,
				sign = self:_resolveSign(model),
				owner = nil,
				name = nil,
				filter = nil,
				token = 0,
			})
		end
	end

	table.sort(records, function(a, b)
		return a.index < b.index
	end)
	return records
end

--[[ The plot's spawn pad. Authored in the place (PlotConfig note 3); built here only if missing.

	The fallback cast runs from plot-local Y 8 — under the roof, which tops out near 28, and over
	the forecourt slab, which sits near 1.4. Casting from above the building instead would land on
	the roof and put the pad on top of the showroom. ]]
function PlotService._resolveSpawn(self, plot: Model): SpawnLocation?
	local existing = plot:FindFirstChild(PlotConfig.SpawnName, true)
	if existing and existing:IsA("SpawnLocation") then
		-- A copied team-only/disabled pad makes Roblox ignore this player's RespawnLocation.
		existing.Enabled = true
		existing.Neutral = true
		existing.AllowTeamChangeOnTouch = false
		return existing
	end

	local originPart = plot.PrimaryPart
	if not originPart then
		self.log:warn(string.format("%s has no PrimaryPart — cannot place a spawn.", plot.Name))
		return nil
	end
	local origin = originPart.CFrame

	local fb = PlotConfig.Fallback
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { plot }

	local hit = workspace:Raycast(origin * Vector3.new(fb.LocalX, 8, fb.LocalZ), -origin.UpVector * 20, params)
	local groundY = if hit then (origin:Inverse() * hit.Position).Y else 1.5

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = PlotConfig.SpawnName
	spawn.Size = fb.Size
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Transparency = 1
	spawn.Enabled = true
	spawn.Neutral = true
	spawn.Duration = 0 -- no forcefield; this is a hub, not a spawn camp
	spawn.CFrame = origin
		* CFrame.new(fb.LocalX, groundY + fb.Size.Y / 2, fb.LocalZ)
		* (if fb.FaceShowroom then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
	spawn.Parent = plot

	self.log:warn(string.format("%s had no authored %s — built a fallback one.", plot.Name, PlotConfig.SpawnName))
	return spawn
end

-- === The dealership sign ====================================================

--[[ Find the authored sign widgets on this plot, or nil if it has no usable sign.

	AUTHORED, NEVER BUILT — unlike the spawn above, there is no fallback that constructs one. The
	plate's size and placement are derived from the beam mesh's real silhouette (see the
	`BuildDealershipSigns` command), and a guessed sign would be a rectangle floating in the wrong
	place on the wrong building. A missing sign costs a player nothing, so the honest answer is to
	warn and carry on rather than invent geometry.

	Resolved once here rather than per-claim so that a sign that is present but malformed — renamed
	child, GUI stripped by a bad merge — is one startup warning naming the plot, instead of a silent
	no-op every time someone joins. ]]
function PlotService._resolveSign(self, plot: Model): SignParts?
	local part = plot:FindFirstChild(PlotConfig.SignName, true)
	if not part then
		self.log:warn(string.format("%s has no %s — run the BuildDealershipSigns command.", plot.Name, PlotConfig.SignName))
		return nil
	end

	local gui = part:FindFirstChild(PlotConfig.SignGuiName)
	local panel = gui and gui:FindFirstChildWhichIsA("GuiObject")
	if not panel then
		self.log:warn(string.format("%s.%s has no %s panel — sign skipped.", plot.Name, PlotConfig.SignName, PlotConfig.SignGuiName))
		return nil
	end

	local title = panel:FindFirstChild(PlotConfig.SignTitleName, true)
	local headshot = panel:FindFirstChild(PlotConfig.SignHeadshotName, true)
	local edit = panel:FindFirstChild(PlotConfig.SignEditButtonName, true)
	if not (title and title:IsA("TextLabel") and headshot and headshot:IsA("ImageLabel") and edit and edit:IsA("GuiButton")) then
		self.log:warn(string.format("%s.%s is missing a Title/Headshot/EditButton — sign skipped.", plot.Name, PlotConfig.SignName))
		return nil
	end

	--[[ OPTIONAL, AND NOT PART OF THE TEST ABOVE. `PlotConfig.SignValueName` explains why at length;
		the short version is that this label landed after the signs were authored, so requiring it
		would strip the nameplate off every plot in a place whose `BuildDealershipSigns` has not been
		re-run. A sign without it is a working sign that does not show a valuation.

		Not warned about either, for the same reason: it would be six startup warnings on a place
		that is behaving exactly as designed, and a warning nobody can act on is one people learn to
		scroll past. The command's own header is where the "re-run me" note lives. ]]
	local value = panel:FindFirstChild(PlotConfig.SignValueName, true)
	if value and not value:IsA("TextLabel") then
		value = nil
	end

	--[[ The likes pill, optional on exactly the same terms as the valuation above and for the same
		reason — it shipped after these signs were authored, and requiring it would strip the whole
		nameplate off every plot in a place that has not had the command re-run.

		RESOLVED AS A PAIR: the button is the hit area and the label inside it is the number, and half
		of that is not a feature. Either both are found or this sign simply has no likes on it, which
		is a state `_paintLikes` and `_onLike` both already handle. ]]
	local like = panel:FindFirstChild(PlotConfig.SignLikeButtonName, true)
	local likeCount = like and like:FindFirstChild(PlotConfig.SignLikeCountName, true)
	if not (like and like:IsA("GuiButton") and likeCount and likeCount:IsA("TextLabel")) then
		like, likeCount = nil, nil
	end

	return { title = title, headshot = headshot, edit = edit, value = value, like = like, likeCount = likeCount }
end

--[[ Write the sign. `player` nil paints the vacant state.

	No remote and no Replica: a SurfaceGui in Workspace already replicates to everyone, which is the
	behaviour a public nameplate wants — every player on the plaza should be able to read whose lot
	this is. See the note in PlotConfig.

	IT ONLY EVER WRITES THE DEFAULT TITLE, never the owner's custom name, and that is the whole
	server half of the filtering design (see the header). A Roblox display name has already been
	moderated, so it is safe to show every player at once; a name somebody typed has not, and there
	is no such thing as a per-viewer value of a replicated property. The custom name is painted over
	the top of this, locally, by each client that is allowed to read it.

	Which also makes this the FALLBACK STATE in the exact sense the feature needs: a viewer whose
	filter hashed the name is simply a viewer nobody paints over, and what they are left looking at
	is a correct sign. ]]
function PlotService._paintSign(self, record: PlotRecord, player: Player?)
	local sign = record.sign
	if not sign then
		return
	end

	if not player then
		sign.title.Text = PlotConfig.oneLine(PlotConfig.SignVacantText)
		sign.headshot.Image = ""
		sign.headshot.Visible = false
		sign.edit.Visible = false
		if sign.value then
			sign.value.Visible = false
		end
		-- An empty lot belongs to nobody, so there is nobody to like and nothing to count.
		if sign.like then
			sign.like.Visible = false
		end
		return
	end

	sign.title.Text = PlotConfig.oneLine(PlotConfig.defaultTitle(player.DisplayName, player.Name))
	sign.headshot.Image = string.format(PlotConfig.SignHeadshotFormat, player.UserId)
	sign.headshot.Visible = true
	self:_paintValue(record, player)
	self:_paintLikes(record, player)
	--[[ Visible to EVERYONE standing on the lot, not only the owner — the same rule the upgrade
		boards follow. The client hides it on lots that are not yours because a pencil on somebody
		else's sign is a lie, but that is cosmetic: a hidden button is not access control, and
		`_onRename` refuses a request from anyone who does not hold the plot. ]]
	sign.edit.Visible = true
end

--[[ Write the valuation line — what everything in this player's dealership would sell for.

	IT READS THE PLAYER ATTRIBUTE, NOT `GarageService`, and that is the point rather than a shortcut.
	`GarageService._publishOwned` writes `DealershipValue` on the same call that writes the
	collection, so the attribute is the published form of exactly the number this wants; taking the
	service instead would add a dependency edge to this file for a value already sitting on the
	Player, and would let the sign and the leaderboard reach the same total by two different routes.

	NO ATTRIBUTE YET IS NOT ZERO. A plot is claimed off the join path and the garage publishes off
	the profile, and those two do not have a guaranteed order — so a nil here means "the profile has
	not landed", and the honest thing to draw for it is nothing at all. `_watchValue` puts the line
	up the moment the real number arrives, which is the same beat the cash pill fills in on.

	Silent no-op on a sign with no `Value` label, which is every sign in a place whose
	`BuildDealershipSigns` has not been re-run — see `_resolveSign`. ]]
function PlotService._paintValue(self, record: PlotRecord, player: Player?)
	local label = record.sign and record.sign.value
	if not label then
		return
	end

	local amount = player and player:GetAttribute(GarageConfig.ValueAttribute)
	if type(amount) ~= "number" then
		label.Visible = false
		return
	end

	label.Text = string.format(PlotConfig.SignValueFormat, GarageConfig.formatCash(amount))
	label.Visible = true
end

--[[ Keep that line current for as long as this player holds this plot.

	Hung off the attribute rather than off a garage signal because the attribute IS the signal: it
	changes exactly once per change to the collection, which is the only thing that can move the
	number. Banking a car, selling a duplicate and the profile landing all arrive here as one event
	with no special case for any of them.

	Returned rather than connected-and-forgotten so `_assign` can put it in the assignment's trove —
	the sign belongs to the plot, but this connection belongs to the CLAIM, and a lot that changes
	hands must not keep repainting itself from the last owner's collection. ]]
function PlotService._watchValue(self, record: PlotRecord, player: Player)
	return player:GetAttributeChangedSignal(GarageConfig.ValueAttribute):Connect(function()
		--[[ Re-checked rather than trusted: this fires on a Player who may have been released from
			the plot in the same frame the attribute moved, and painting then would put the outgoing
			owner's valuation onto a lot somebody else now holds. ]]
		if record.owner == player then
			self:_paintValue(record, player)
		end
	end)
end

-- === Profiles and lookups ===================================================

--[[ This player's profile, or nil. YIELDS until it loads — `Data:GetProfileAsync` blocks for as long
	as the session lock takes — so every caller is in its own thread and re-checks whatever it cared
	about on the way out.

	`pcall`ed because a profile that failed to load takes the player's session with it, and a service
	drawing a sign has no business being the thing that errors on the way past. ]]
function PlotService._profileOf(self, player: Player)
	local ok, profile = pcall(function()
		return Data:GetProfileAsync(player)
	end)
	if not ok or not profile then
		return nil
	end
	return profile
end

--- The plot carrying this 1..N index, or nil. Linear over six records; `_discoverPlots` has already
--- guaranteed the index is unique, so the first hit is the only hit.
function PlotService._recordAt(self, index: number): PlotRecord?
	for _, record in self._plots do
		if record.index == index then
			return record
		end
	end
	return nil
end

-- === Likes ==================================================================

--[[ Write the like count into the pill on this player's sign.

	IT READS THE PLAYER ATTRIBUTE, exactly as `_paintValue` does and for the same reason: the number
	is published onto the Player by `_loadLikes` and bumped by `_onLike`, so painting from the
	attribute means the sign, and anything else that ever wants the figure, reach it by one route.

	NO ATTRIBUTE YET IS NOT ZERO — it lands a moment after the claim, once the profile has loaded —
	so the honest thing to draw for a nil is nothing at all, and `_watchLikes` puts the pill up when
	the real number arrives. That matters more here than it does for the valuation: "0" on a pill is
	a number a player will read as their score, and showing it before we know is telling them
	something we have not checked.

	Silent no-op on a sign with no pill, which is every sign in a place whose `BuildDealershipSigns`
	has not been re-run — see `_resolveSign`. ]]
function PlotService._paintLikes(self, record: PlotRecord, player: Player?)
	local sign = record.sign
	local button = sign and sign.like
	if not button then
		return
	end

	local count = if PlotConfig.Likes.Enabled and player
		then player:GetAttribute(PlotConfig.Likes.Attribute)
		else nil
	if type(count) ~= "number" then
		button.Visible = false
		return
	end

	if sign.likeCount then
		sign.likeCount.Text = PlotConfig.formatLikes(count)
	end
	button.Visible = true
end

--[[ Keep the pill current for as long as this player holds this plot. The twin of `_watchValue`,
	down to the `record.owner` re-check — this fires on a Player who may have been released from the
	lot in the same frame the attribute moved, and painting then would put the outgoing owner's count
	onto a sign somebody else now holds.

	Returned rather than connected-and-forgotten so `_assign` can put it in the ASSIGNMENT's trove.
	The likes belong to the player and outlive the claim; this connection does not. ]]
function PlotService._watchLikes(self, record: PlotRecord, player: Player)
	return player:GetAttributeChangedSignal(PlotConfig.Likes.Attribute):Connect(function()
		if record.owner == player then
			self:_paintLikes(record, player)
		end
	end)
end

--[[ Publish this player's lifetime like count onto them, off the join path in its own thread because
	`GetProfileAsync` yields until the profile lands and `LoadCharacter` is waiting behind it.

	PER PLAYER AND NOT PER CLAIM, which is why it takes no record: the number is a fact about the
	player, not about the lot they happen to be sitting on, and a player who joined a full server has
	one too. It is never cleared on release for the same reason — the attribute is not part of the
	claim and nothing about it goes stale when the lot goes back in the pool. ]]
function PlotService._loadLikes(self, player: Player)
	if not PlotConfig.Likes.Enabled then
		return
	end
	task.spawn(function()
		local profile = self:_profileOf(player)
		if not profile or player.Parent ~= Players then
			return
		end
		local count = profile:Get({ PlotConfig.Likes.ProfileKey })
		player:SetAttribute(PlotConfig.Likes.Attribute, if type(count) == "number" then count else 0)
	end)
end

--- The set of user ids this player has already liked, or nil if their profile could not be read.
--- Yields.
function PlotService._likesGiven(self, player: Player): { [string]: boolean }?
	local profile = self:_profileOf(player)
	if not profile then
		return nil
	end
	local given = profile:Get({ PlotConfig.Likes.GivenKey })
	return if type(given) == "table" then given else {}
end

--[[ Tell one viewer whether they have already liked one owner. Never yields the caller.

	NO TOKEN AND NO RE-CHECK ON THE FAR SIDE OF THE YIELD, unlike `_sendName` — and that is the
	payoff for keying the answer by user id rather than by plot index. "Has this viewer liked user
	12345" cannot be made wrong by the lot changing hands while the profile loads; there is no
	version of it that goes stale, so a late reply is simply a late correct reply. ]]
function PlotService._sendLiked(self, owner: Player, viewer: Player)
	if not PlotConfig.Likes.Enabled then
		return
	end
	local userId = owner.UserId
	task.spawn(function()
		local given = self:_likesGiven(viewer)
		if not given or viewer.Parent ~= Players then
			return
		end
		self:getRemoteEvent("DealershipLike"):Fire(viewer, userId, given[tostring(userId)] == true)
	end)
end

--[[ One plot has just been claimed, so tell everybody where they stand with its new owner.

	This is the half the handshake cannot cover. `_onReady` answers a client that has just booted;
	this answers the clients that were already standing there when somebody new walked up to a lot —
	including the ones who liked that player months ago in another server, whose heart should come up
	already filled. ]]
function PlotService._broadcastLiked(self, record: PlotRecord)
	local owner = record.owner
	if not owner then
		return
	end
	for _, viewer in Players:GetPlayers() do
		-- Your own sign is a readout, never a button, so there is nothing to tell you about it.
		if viewer ~= owner then
			self:_sendLiked(owner, viewer)
		end
	end
end

--[[ The heart. Resolve who is behind that sign, refuse everything that is not a first like from a
	visitor, then move both profiles.

	=== THE TWO WRITES ARE THE WHOLE FUNCTION ==================================================

	A like touches two different datastore keys — the giver's "who have I liked" set and the
	receiver's count — and there is no transaction across them, so the only protection available is
	to leave no yield between them. Both profiles are therefore fetched and checked FIRST, and the
	writes happen back to back at the end.

	THE GIVER IS MARKED BEFORE THE RECEIVER IS CREDITED, and the order is chosen by which failure is
	worse. Marked-but-not-credited loses one like, which nobody can see and nobody can repeat.
	Credited-but-not-marked leaves a press that can be given again, which is the one thing that would
	make the number on the sign mean nothing. So the invisible failure is the one this takes.

	EVERY EXIT ANSWERS THE CLIENT, including the refusals — the heart is disabled while a press is in
	flight and it is that reply which re-enables it. See the `DealershipLike` note above. ]]
function PlotService._onLike(self, player: Player, index: unknown)
	local likes = PlotConfig.Likes
	if not (PlotConfig.Enabled and likes.Enabled) then
		return
	end
	if type(index) ~= "number" then
		return
	end

	local record = self:_recordAt(index)
	local owner = record and record.owner
	--[[ No answer on these two, deliberately: a vacant lot and your own lot are both states in which
		the client is not showing a pressable heart at all, so a request naming one did not come from
		a button this game drew. There is nothing to re-enable. ]]
	if not (record and owner) or owner == player then
		return
	end

	local now = os.clock()
	local last = self._likedAt[player]
	if last and now - last < likes.CooldownSeconds then
		self:_sendLiked(owner, player)
		return
	end
	--[[ Spent by an ATTEMPT rather than by a success, the same call `_onRename` makes: what the
		cooldown is holding off is a held-down button reaching two profiles, and a refused press costs
		exactly as much of that as an accepted one. ]]
	self._likedAt[player] = now

	local userId = owner.UserId
	task.spawn(function()
		local giver = self:_profileOf(player)
		local receiver = self:_profileOf(owner)

		--[[ Both fetches yield, so everything is re-checked here. Note that the OWNER'S CLAIM IS NOT
			among the things re-checked, and that is not an oversight: the like was aimed at a person,
			the person is captured above, and it stays the right person even if they released the lot
			while their profile was loading. What must still be true is that both saves are live. ]]
		if not (giver and receiver and giver:IsActive() and receiver:IsActive()) then
			return
		end
		if player.Parent ~= Players or owner.Parent ~= Players then
			return
		end

		local key = tostring(userId)
		local given = giver:Get({ likes.GivenKey })
		given = if type(given) == "table" then given else {}
		if given[key] then
			-- Already theirs. Re-assert it rather than staying quiet, so a client that had somehow
			-- lost the state gets it back and its heart stops being pressable.
			self:getRemoteEvent("DealershipLike"):Fire(player, userId, true)
			return
		end

		--[[ Written as a whole table rather than as one nested key, which is the idiom every other
			map in this profile follows (`Garage.BayLevels`, `Quests.Progress`) — the write goes
			through Replica by path, and handing it the finished table is one statement whose shape
			the reader can see. Cloned rather than mutated in place because what `Get` handed back is
			the profile's own table. ]]
		local next_ = table.clone(given)
		next_[key] = true
		giver:Set({ likes.GivenKey }, next_)

		local count = receiver:Get({ likes.ProfileKey })
		count = (if type(count) == "number" then count else 0) + 1
		receiver:Set({ likes.ProfileKey }, count)
		--[[ The broadcast, and it is what repaints the sign: `_watchLikes` is listening to this
			attribute, so every player looking at that lot sees the number move without a remote. ]]
		owner:SetAttribute(likes.Attribute, count)

		self:getRemoteEvent("DealershipLike"):Fire(player, userId, true)
		self.log:info(string.format("%s liked %s's dealership (%d).", player.Name, owner.Name, count))
		self:getSignal("DealershipLiked"):Fire(player, owner, count)
	end)
end

-- === The custom name ========================================================

--[[ What ONE viewer may read of a filtered name, or nil if the answer is "the default".

	FAILS CLOSED IN BOTH DIRECTIONS. A hashed result is nil (see `PlotConfig.isFiltered`) and so is
	an errored call — `GetNonChatStringForUserAsync` is a web call and can rate-limit or blip, and a
	blip must not be the thing that shows unfiltered text to a stranger. Yields. ]]
function PlotService._readFor(self, result: any, viewer: Player): string?
	if not result then
		return nil
	end
	local ok, text = pcall(function()
		return result:GetNonChatStringForUserAsync(viewer.UserId)
	end)
	if not ok then
		self.log:warn(string.format("Filter read failed for %s: %s", viewer.Name, tostring(text)))
		return nil
	end
	if PlotConfig.isFiltered(text) then
		return nil
	end
	return text
end

--[[ Send one plot's name to one viewer, filtered for them. Never yields the caller.

	The token and the `Parent` check on the far side of the yield are what make this safe to fire
	off freely: by the time a filter call comes back the plot may have been renamed, released and
	reclaimed, and the viewer may have left. Either way the payload is dropped rather than sent. ]]
function PlotService._sendName(self, record: PlotRecord, viewer: Player)
	local token = record.token
	local index = record.index
	task.spawn(function()
		local text = self:_readFor(record.filter, viewer)
		if record.token ~= token or viewer.Parent ~= Players then
			return
		end
		self:getRemoteEvent("DealershipName"):Fire(viewer, index, text)
	end)
end

--- One plot's name to everyone in the server, each filtered for themselves.
function PlotService._broadcastName(self, record: PlotRecord)
	for _, viewer in Players:GetPlayers() do
		self:_sendName(record, viewer)
	end
end

--- Drop a plot's name. Used on release and on a rename back to the default; the broadcast tells
--- every client to put the owner's default title back where the custom one was.
function PlotService._clearName(self, record: PlotRecord)
	record.name = nil
	record.filter = nil
	record.token += 1
	self:_broadcastName(record)
end

--[[ Their sign controller is up. Answer with everything about this server's signs that is theirs
	alone to know:

	  * every named plot — including their own, which is how the modal knows what to put in the box
	    when they open it;
	  * whether they have already liked each current owner, so a heart they filled in a session
	    months ago comes up filled rather than inviting a press that would be refused.

	The like half is ONE PROFILE READ FOR THE WHOLE SERVER, not one per plot: what is being asked is
	a question about the reader, and the answer for all six lots is in the same table. ]]
function PlotService._onReady(self, player: Player)
	for _, record in self._plots do
		if record.filter then
			self:_sendName(record, player)
		end
	end

	if not PlotConfig.Likes.Enabled then
		return
	end
	task.spawn(function()
		local given = self:_likesGiven(player)
		if not given or player.Parent ~= Players then
			return
		end
		for _, record in self._plots do
			local owner = record.owner
			if owner and owner ~= player then
				local userId = owner.UserId
				self:getRemoteEvent("DealershipLike"):Fire(player, userId, given[tostring(userId)] == true)
			end
		end
	end)
end

--- Persist what they typed, unfiltered and off the hot path. See PlotConfig.DealershipNameKey for
--- why the SAVE holds the raw string rather than a filtered one.
function PlotService._store(self, player: Player, name: string)
	task.spawn(function()
		local profile = self:_profileOf(player)
		if not profile then
			self.log:warn(string.format("Could not save %s's dealership name: no profile.", player.Name))
			return
		end
		profile:Set(PlotConfig.DealershipNameKey, name)
	end)
end

function PlotService._answer(self, player: Player, ok: boolean, message: string)
	self:getRemoteEvent("DealershipNameResult"):Fire(player, ok, message)
end

--[[ The pencil. Validate, filter, save, broadcast — in that order, and it stops at the first one
	that says no.

	THE AUTHOR'S OWN FILTER IS THE GATE. After the name is filtered, the first thing read out of the
	result is what the PLAYER WHO TYPED IT may see; if their own account cannot be shown it, nothing
	is stored and nothing is broadcast, and they are told the name did not pass. That is a different
	question from the per-viewer one further down — a name can clear the author and still be hashed
	for a nine-year-old on the other side of the plaza, and that reader quietly gets the default. So
	the two together are: a name that is bad by any measure is refused outright and never saved, and
	a name that is merely not-for-everyone is shown to the people it is for.

	The cooldown stamp is spent by an ATTEMPT rather than by a success, because what it is protecting
	is Roblox's per-server filter budget, and a failed call costs that budget exactly what a
	successful one does. ]]
function PlotService._onRename(self, player: Player, text: unknown)
	local rename = PlotConfig.Rename
	if not (PlotConfig.Enabled and rename.Enabled) then
		return
	end
	local messages = rename.Messages

	local assignment = self._assignments[player]
	if not assignment then
		self:_answer(player, false, messages.NotYours)
		return
	end
	local record = assignment.record

	local now = os.clock()
	local last = self._renamedAt[player]
	if last and now - last < rename.CooldownSeconds then
		self:_answer(player, false, messages.TooFast)
		return
	end

	local clean, err = PlotConfig.sanitize(text)
	if not clean then
		self:_answer(player, false, err or messages.BadCharacter)
		return
	end
	self._renamedAt[player] = now

	-- An empty name is a real answer: put the sign back to "<DisplayName>'s Dealership". Nothing to
	-- filter, so it takes none of the machinery below.
	if clean == "" then
		self:_clearName(record)
		self:_store(player, "")
		self:_answer(player, true, messages.Cleared)
		self.log:info(string.format("%s cleared the name on plot %d.", player.Name, record.index))
		self:getSignal("DealershipRenamed"):Fire(player, record.index, nil)
		return
	end

	local ok, result = pcall(function()
		return TextService:FilterStringAsync(clean, player.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok or not result then
		self.log:warn(string.format("FilterStringAsync failed for %s: %s", player.Name, tostring(result)))
		self:_answer(player, false, messages.FilterFailed)
		return
	end

	-- Both calls above yield. A player who left, or a plot that changed hands while Roblox was
	-- thinking, gets nothing written to it.
	if record.owner ~= player or player.Parent ~= Players then
		return
	end

	if not self:_readFor(result, player) then
		self:_answer(player, false, messages.Filtered)
		return
	end
	if record.owner ~= player then
		return -- `_readFor` yields too
	end

	record.name = clean
	record.filter = result
	record.token += 1

	self:_store(player, clean)
	self:_broadcastName(record)
	self:_answer(player, true, messages.Saved)
	self.log:info(string.format("%s named plot %d.", player.Name, record.index))
	self:getSignal("DealershipRenamed"):Fire(player, record.index, clean)
end

--[[ Fetch the owner's saved dealership name, re-filter it, and hand it out.

	Runs off the join path in its own thread because every step of it yields — `GetProfileAsync`
	blocks until the profile loads, and `FilterStringAsync` is a web call. The join path may not
	block: `LoadCharacter` is waiting behind it.

	RE-FILTERED ON EVERY CLAIM rather than trusted from the save, because what is stored is what the
	player typed. That is not belt-and-braces: moderation moves, and a name that was fine in March
	is answered by today's filter this way rather than by the one that ran when it was chosen.

	Anything that comes back a refusal — a name the current rules reject, a filter that hashes it for
	its own author, a call that errors — leaves the sign on the default and the SAVE UNTOUCHED. The
	name is not deleted on the player's behalf over a service blip; it simply does not show, and the
	next session asks again.

	The owner re-check after each yield is not paranoia. Profile loading can take seconds; a player
	who joins and immediately leaves has their plot released and handed to the next player in that
	window, and without the check this thread would wake up and put the departed player's name on
	the new owner's sign. ]]
function PlotService._loadName(self, record: PlotRecord, player: Player)
	if not PlotConfig.Rename.Enabled then
		return
	end
	task.spawn(function()
		local profile = self:_profileOf(player)
		if not profile or record.owner ~= player then
			return
		end

		local clean = PlotConfig.sanitize(profile:Get(PlotConfig.DealershipNameKey))
		if not clean or clean == "" then
			return
		end

		local filtered, result = pcall(function()
			return TextService:FilterStringAsync(clean, player.UserId, Enum.TextFilterContext.PublicChat)
		end)
		if not filtered or not result or record.owner ~= player then
			if not filtered then
				self.log:warn(string.format("FilterStringAsync failed for %s's saved name: %s", player.Name, tostring(result)))
			end
			return
		end

		if not self:_readFor(result, player) or record.owner ~= player then
			return
		end

		record.name = clean
		record.filter = result
		record.token += 1
		self:_broadcastName(record)
	end)
end

-- === Going home =============================================================

--[[ The headshot on the dealership pin was pressed: put this player on their own spawn pad.

	THE ORDER IS THE SEAT RELEASE'S. `Humanoid.Sit = false` takes a few physics frames to let go, and a
	`PivotTo` inside that window is either swallowed (the seat was destroyed first) or flings the rider
	across the map (the seat still holds them). So they are stood up, the seat is waited out on
	Heartbeat, and only then is the car put away and the character moved. `RaceService._returnToSpawn`
	is the reference for the same steps.

	ONLY THEIR OWN LOBBY CAR IS PUT AWAY. A friend's car they were riding in is simply got out of;
	despawning somebody else's car off a button on my screen is not mine to do.

	Refused while racing and on the trip home after a run, and asked again after the stream wait,
	because the Play button is live for the whole of it. ]]
local SEAT_RELEASE_TIMEOUT = 1

function PlotService._onGoHome(self, player: Player)
	local cfg = PlotConfig.Marker.Home
	if not (cfg and cfg.Enabled) then
		return
	end

	local now = os.clock()
	local last = self._homedAt[player]
	if last and now - last < cfg.CooldownSeconds then
		return
	end
	self._homedAt[player] = now

	if self._goingHome[player] then
		return
	end
	local spawn = self:getSpawn(player)
	if not (spawn and spawn:IsDescendantOf(workspace)) then
		return
	end

	local function busy(): boolean
		local Race = Shard.get("RaceService")
		return Race ~= nil and (Race:isRacing(player) or Race:isReturning(player))
	end
	if busy() then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and root and root:IsA("BasePart") and humanoid.Health > 0) then
		return
	end

	self._goingHome[player] = true
	task.spawn(function()
		local ok, err = pcall(self._goHome, self, player, spawn, character, humanoid, root, busy)
		self._goingHome[player] = nil
		if not ok then
			self.log:warn(string.format("%s could not be sent home: %s", player.Name, tostring(err)))
		end
	end)
end

function PlotService._goHome(
	self,
	player: Player,
	spawn: SpawnLocation,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	busy: () -> boolean
)
	local cfg = PlotConfig.Marker.Home

	local seat = humanoid.SeatPart
	local LobbyCar = Shard.get("LobbyCarService")
	local own = LobbyCar and LobbyCar:getLobbyCar(player)
	local inOwnCar = seat ~= nil and own ~= nil and seat:IsDescendantOf(own)

	if seat then
		humanoid.Sit = false
		local deadline = os.clock() + SEAT_RELEASE_TIMEOUT
		while humanoid.SeatPart or humanoid:GetState() == Enum.HumanoidStateType.Seated do
			if os.clock() >= deadline or not humanoid.Parent then
				self.log:warn(string.format("%s never left the seat; not sending them home.", player.Name))
				return
			end
			RunService.Heartbeat:Wait()
		end
	end
	if inOwnCar then
		LobbyCar:setLobbyCar(player, nil)
	end

	--[[ The lot has almost always streamed out on their machine (the pin only shows from 210 studs
		out), and the character is theirs to simulate, so landing before the floor arrives drops them
		through it. Not fatal if it times out; logged so a bad landing has a cause in the output. ]]
	local target = spawn.CFrame + Vector3.new(0, cfg.Lift, 0)
	local streamed, streamErr = pcall(function()
		player:RequestStreamAroundAsync(target.Position, cfg.StreamTimeout)
	end)
	if not streamed then
		self.log:warn(string.format("%s's lot did not stream in before going home (%s).", player.Name, tostring(streamErr)))
	end

	if busy() or player.Character ~= character or not humanoid.Parent or humanoid.Health <= 0 then
		return
	end

	character:PivotTo(target)
	--- Zeroed twice a frame apart: the client owns this character and re-asserts its momentum on the
	--- step after a move, the same reason `RaceService._stillAfterMove` gives.
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	RunService.Heartbeat:Wait()
	if root.Parent then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	self.log:info(string.format("%s went home%s.", player.Name, if inOwnCar then " and put their car away" else ""))
end

-- === Claiming ===============================================================

function PlotService._firstFree(self): PlotRecord?
	for _, record in self._plots do
		if not record.owner then
			return record
		end
	end
	return nil
end

--[[ Claim a plot for a player. Returns the record, or nil if every plot is taken.

	Everything this writes to the world goes in the assignment's trove, so release is one call and
	cannot drift out of sync with claim as more is added here later. ]]
function PlotService._assign(self, player: Player): PlotRecord?
	if self._assignments[player] then
		return self._assignments[player].record
	end

	local record = self:_firstFree()
	if not record then
		return nil
	end

	local trove = Trove.new()
	record.owner = player

	record.model:SetAttribute(PlotConfig.OwnerUserIdAttribute, player.UserId)
	record.model:SetAttribute(PlotConfig.OwnerNameAttribute, player.Name)
	local footprint, footprintSize = record.model:GetBoundingBox()
	player:SetAttribute(PlotConfig.PlayerFootprintAttribute, footprint)
	player:SetAttribute(PlotConfig.PlayerFootprintSizeAttribute, footprintSize)
	player:SetAttribute(PlotConfig.PlayerPlotAttribute, record.index)
	player.RespawnLocation = record.spawn

	--[[ Paint the default immediately, then come back with the custom name for whoever may read it
		once the profile has loaded and the filter has answered. The sign is never blank in between,
		and it is never showing text nobody has checked. ]]
	self:_paintSign(record, player)
	--[[ In the ASSIGNMENT's trove, not the plot's: the valuation and the like count both follow
		whoever holds the lot, so these have to come down the moment they release it.
		`_paintSign(record, nil)` below hides both lines as part of painting the vacant state.

		THE LIKES WATCH GOES IN BEFORE `_onPlayerAdded` CALLS `_loadLikes`, which is the write it is
		waiting for. That write yields on the profile first, so the connection would win the race
		anyway — but an ordering that only holds because the other side is slow is not an ordering. ]]
	trove:Add(self:_watchValue(record, player))
	trove:Add(self:_watchLikes(record, player))

	self:_loadName(record, player)
	--[[ Everyone already standing on the plaza is told where they stand with the new owner. The
		handshake covers the other direction — a client that boots later asks for all six at once. ]]
	self:_broadcastLiked(record)

	trove:Add(function()
		record.owner = nil
		record.model:SetAttribute(PlotConfig.OwnerUserIdAttribute, nil)
		record.model:SetAttribute(PlotConfig.OwnerNameAttribute, nil)
		self:_paintSign(record, nil)
		--[[ AFTER the repaint, and it has to be: the broadcast is what makes every client drop the
			custom name it painted over this sign, and a client that dropped it first would repaint
			the outgoing owner's default for the frames before the vacant text replicated. ]]
		self:_clearName(record)
		-- The player may already be gone; touching a destroyed Player errors, so guard on parent.
		if player.Parent == Players then
			player:SetAttribute(PlotConfig.PlayerPlotAttribute, nil)
			player:SetAttribute(PlotConfig.PlayerFootprintAttribute, nil)
			player:SetAttribute(PlotConfig.PlayerFootprintSizeAttribute, nil)
			if player.RespawnLocation == record.spawn then
				player.RespawnLocation = nil
			end
		end
	end)

	self._assignments[player] = { record = record, trove = trove }
	return record
end

function PlotService._release(self, player: Player)
	local assignment = self._assignments[player]
	if not assignment then
		return
	end
	self._assignments[player] = nil

	local record = assignment.record
	assignment.trove:Destroy()

	self.log:info(string.format("%s released plot %d.", player.Name, record.index))
	self:getSignal("PlotReleased"):Fire(player, record.model, record.index)
end

--[[ Put a character in the world.

	Only ever called from the end of `_onPlayerAdded`, on every path, for the reason in the header.
	The `player.Character` guard is what makes it safe to leave enabled when `TakeOverCharacterLoading`
	is off and Roblox has already auto-loaded one. ]]
function PlotService._loadCharacter(self, player: Player)
	if not PlotConfig.TakeOverCharacterLoading then
		return
	end
	if player.Parent ~= Players or player.Character then
		return
	end
	local spawn = self:getSpawn(player)
	if spawn then
		player.RespawnLocation = spawn
	end
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		self.log:warn(string.format("LoadCharacter failed for %s: %s", player.Name, tostring(err)))
	end
end

--[[ Put a character back after a death — the other half of taking loading over.

	`Players.CharacterAutoLoads = false` does not just skip the first spawn; it means the engine
	never loads a character again. So without this, the FIRST death of a session is permanent: the
	Humanoid enters Dead, the camera goes on pointing at a subject with no root, and the player is
	left staring at a frozen shot with no way back except rejoining. See PlotConfig.RespawnOnDeath
	for the playtest that found it.

	`Died` is the right hook rather than a Health watch, and the difference is load-bearing: a
	character whose parts are destroyed under `FallenPartsDestroyHeight` fires `Died` with its Health
	still sitting at 100, because Died tracks the Dead STATE and not the number. That is exactly the
	case that stranded the player, so a `Health <= 0` test would have missed it.

	Per character, not per player. Each new character brings a new Humanoid, and connecting to the
	player once would leave the connection pointing at the corpse. The trove is the assignment's, so
	the whole chain dies with the claim when they leave.

	`RespawnTime` rather than an immediate load, so the death is legible instead of a teleport — the
	same beat the engine's own respawn uses, read from the same property. ]]
function PlotService._watchDeath(self, player: Player, trove)
	if not (PlotConfig.TakeOverCharacterLoading and PlotConfig.RespawnOnDeath) then
		return
	end

	local function watch(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not (humanoid and humanoid:IsA("Humanoid")) then
			self.log:warn(string.format("%s's character has no Humanoid; they will not respawn.", player.Name))
			return
		end
		trove:Add(humanoid.Died:Connect(function()
			task.delay(Players.RespawnTime, function()
				-- Only if this is still the character that died: a respawn from anywhere else
				-- (or a player who left mid-beat) must not be handed a second body.
				if player.Parent == Players and player.Character == character then
					local spawn = self:getSpawn(player)
					if spawn then
						player.RespawnLocation = spawn
					end
					local ok, err = pcall(function()
						player:LoadCharacter()
					end)
					if not ok then
						self.log:warn(string.format("Respawn failed for %s: %s", player.Name, tostring(err)))
					end
				end
			end)
		end))
	end

	trove:Add(player.CharacterAdded:Connect(watch))
	-- A character already present when the service binds will not fire CharacterAdded again.
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

function PlotService._onPlayerAdded(self, player: Player)
	local record = self:_assign(player)

	--[[ Outside the assignment, on purpose: the like count is a fact about the PLAYER, so a player
		who joined a full server and holds no lot still has one published on them. It also has to be
		after `_assign`, which is what puts the `_watchLikes` connection in place that this write is
		going to wake up. ]]
	self:_loadLikes(player)

	if record then
		self.log:info(string.format("%s claimed plot %d.", player.Name, record.index))
		self:getSignal("PlotAssigned"):Fire(player, record.model, record.index)
	elseif PlotConfig.WhenFull == "kick" then
		self.log:warn(string.format("No free plot for %s — kicking (WhenFull = 'kick').", player.Name))
		player:Kick(PlotConfig.FullMessage)
		return
	else
		self.log:warn(
			string.format(
				"No free plot for %s — joining without one (%d plots, %d players).",
				player.Name,
				#self._plots,
				#Players:GetPlayers()
			)
		)
	end

	--[[ On its OWN trove rather than the assignment's, on purpose: a player who
		joined a full server has no assignment to hang it on and still needs to respawn — the `kick`
		branch above is the only path that legitimately ends without a character. Connected before
		loading so a death during LoadCharacter cannot beat the first Humanoid watch. ]]
	local trove = Trove.new()
	self._lifeTroves[player] = trove
	self:_watchDeath(player, trove)
	self:_loadCharacter(player)
end

-- === Public API =============================================================

-- The plot Model this player holds, or nil.
function PlotService.getPlot(self, player: Player): Model?
	local assignment = self._assignments[player]
	return if assignment then assignment.record.model else nil
end

-- The 1..N index this player holds, or nil. Cheaper than `getPlot` when that is all you need.
function PlotService.getPlotIndex(self, player: Player): number?
	local assignment = self._assignments[player]
	return if assignment then assignment.record.index else nil
end

-- This player's spawn pad, or nil.
function PlotService.getSpawn(self, player: Player): SpawnLocation?
	local assignment = self._assignments[player]
	return if assignment then assignment.record.spawn else nil
end

-- Who owns this plot Model, or nil if it is free.
function PlotService.getOwner(self, plot: Model): Player?
	for _, record in self._plots do
		if record.model == plot then
			return record.owner
		end
	end
	return nil
end

-- Every plot, in index order, as { index, model, spawn, owner }. Read-only by convention.
function PlotService.getPlots(self): { PlotRecord }
	return self._plots
end

function PlotService.getFreeCount(self): number
	local free = 0
	for _, record in self._plots do
		if not record.owner then
			free += 1
		end
	end
	return free
end

-- === Lifecycle ==============================================================

PlotService:withLifecycle({
	init = function(self)
		self._plots = {} :: { PlotRecord }
		self._assignments = {} :: { [Player]: { record: PlotRecord, trove: any } }
		-- [Player] = os.clock() of their last rename ATTEMPT. See `_onRename` on why an attempt and
		-- not a success, and `PlotConfig.Rename.CooldownSeconds` on what it is really protecting.
		self._renamedAt = {} :: { [Player]: number }
		-- [Player] = os.clock() of their last like ATTEMPT. Same rule as `_renamedAt`; see `_onLike`.
		self._likedAt = {} :: { [Player]: number }
		-- [Player] = os.clock() of their last go-home ATTEMPT, and whether one is still in flight.
		-- See `_onGoHome`.
		self._homedAt = {} :: { [Player]: number }
		self._goingHome = {} :: { [Player]: boolean }
		-- [Player] = Trove for things that outlive a plot claim (the respawn watch), since a
		-- player with no plot has no assignment trove but still has a life to look after.
		self._lifeTroves = {} :: { [Player]: any }
		self._trove = Trove.new()

		if not PlotConfig.Enabled then
			self.log:info("Disabled by config — plots are not claimable.")
			return
		end

		self._plots = self:_discoverPlots()
		if #self._plots == 0 then
			self.log:warn("No claimable plots found.")
			return
		end

		--[[ Every sign starts vacant. Not redundant: the signs are authored in the place, so
			whatever text they were last saved with is what ships — including the placeholder owner
			names the BuildDealershipSigns command writes in Preview mode. Starting from a known
			state means a stale save can never show a name nobody in this server owns. ]]
		for _, record in self._plots do
			self:_paintSign(record, nil)
		end

		if PlotConfig.TakeOverCharacterLoading then
			local previous = Players.CharacterAutoLoads
			Players.CharacterAutoLoads = false
			self._trove:Add(function()
				Players.CharacterAutoLoads = previous
			end)
		end

		--[[ Loud on purpose. Six plots against a 60-slot server is not a code bug this service can
			fix — it is `Players.MaxPlayers` disagreeing with the map, and the symptom (most of the
			server has no lot) is far from the cause. ]]
		if Players.MaxPlayers > #self._plots then
			self.log:warn(
				string.format(
					"MaxPlayers is %d but there are only %d plots — %d players could join with no lot. Set MaxPlayers to %d.",
					Players.MaxPlayers,
					#self._plots,
					Players.MaxPlayers - #self._plots,
					#self._plots
				)
			)
		end

		self.log:info(string.format("%d plots ready.", #self._plots))
	end,

	start = function(self)
		if not PlotConfig.Enabled or #self._plots == 0 then
			return
		end
		-- observePlayer covers players who joined before this ran, which matters on a hot reload.
		self._trove:Add(Observers.observePlayer(function(player)
			self:_onPlayerAdded(player)
			return function()
				local trove = self._lifeTroves[player]
				self._lifeTroves[player] = nil
				self._renamedAt[player] = nil
				self._likedAt[player] = nil
				self._homedAt[player] = nil
				self._goingHome[player] = nil
				if trove then
					trove:Destroy()
				end
				self:_release(player)
			end
		end))
	end,
})

PlotService:withCleanup(function()
	if PlotService._trove then
		PlotService._trove:Destroy()
	end
end)

return PlotService
