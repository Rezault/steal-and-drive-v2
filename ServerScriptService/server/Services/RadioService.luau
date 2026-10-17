--[[
	RadioService  (server)
	----------------------
	Decides what a lobby car is allowed to be playing, and writes the answer onto the car. That is
	the entire job, and the list of things it deliberately does NOT do is longer than the list of
	things it does.

	=== IT MAKES NO SOUND ======================================================================

	There is no `Sound` on this side of the wire, no volume, no roll-off and no playlist timer.
	`RadioController` owns every one of those, on every listener's own machine, and this is told
	nothing about what any of them is hearing. `RadioConfig`'s header has the full argument under
	"THE SERVER HAS NO PART IN THE SOUND"; the short version is that a client-built Sound is the
	only kind the music mute can reach, the only kind that respects `StreamingEnabled`, and the only
	kind that needs no timer to stay in sync.

	WHAT CROSSES THE WIRE IS THREE ATTRIBUTES ON THE CAR — station, custom track id, and the server
	clock reading when it was switched on. Everything else is derived by whoever is listening.

	=== IT DOES NOT BANK ANYTHING ==============================================================

	This is the first game pass the project sells and it is nothing like the four products. A
	product's grant is a stored counter on the profile, because a receipt arrives whenever Roblox
	feels like delivering it (`DevProductsHandler`'s header). A pass has no receipt and nothing to
	store: `UserOwnsGamePassAsync` is the only copy of the answer that counts, and everything here
	does with it is CACHE it — because it is a web call and the alternative is one per press.

	The cache is refreshed on exactly two events, and between them it is trusted: the player joining,
	and `PromptGamePassPurchaseFinished` saying they just bought it. A pass cannot be lost mid-
	session in any way this server would want to react to, so nothing polls.

	=== IT DOES NOT DECIDE WHO OWNS A CAR ======================================================

	`_carOf` finds the player's car by the owner stamp `LobbyCarService` puts on it
	(`LobbyCarConfig.OwnerAttribute`), which is that service's documented public contract, rather
	than by reaching into its private table. A player with no car out has nothing to play music on
	and the request is refused with a reason the panel can print.

	=== THE ONE THING IT REALLY DOES DECIDE ====================================================

	Whether a pasted audio id may be played at all. `_checkTrack` is the whole of it, and it exists
	because the failure it prevents is silent: an id belonging to somebody else's private upload
	loads as nothing, raises no error anywhere, and leaves a paying player looking at a car making
	no noise. `GetProductInfo` can tell us it is an Audio asset and whether it is public, so the
	refusal happens in front of the player with a sentence attached instead of as silence.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(script.Parent.Parent.Data)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local RadioConfig = require(ReplicatedStorage.shared.Configs.RadioConfig)

local RadioService = Shard.new("RadioService"):withDependencies({ "LobbyCarService" })

--[[ Audio asset type, as `GetProductInfo` reports it. Written out rather than taken from
	`Enum.AssetType.Audio.Value` because those are two different numberings that happen to agree
	here, and relying on the coincidence is the kind of thing that breaks quietly. ]]
local AUDIO_ASSET_TYPE = 3

RadioService:withRemoteEvents({
	{
		--[[ client -> server: put this on. `station` is a station key, `RadioConfig.CustomStation`,
			or nil for "turn it off"; `trackId` is only read for a custom track. ]]
		[RadioConfig.RemoteName] = function(player: Player, station: unknown, trackId: unknown)
			RadioService:_onRequest(player, station, trackId)
		end,
	},
	RadioConfig.ReplyName,
})

-- === The pass ===============================================================

--[[ Does this player own the radio pass? Cached; nil means "we have not asked yet", which is a
	different answer from false and the panel draws it differently (`RadioConfig.OwnedAttribute`).

	NON-YIELDING, so it is safe on the request path. The web call happens once, off the join path in
	`_refreshOwnership`, and this only ever reads what it left behind. ]]
function RadioService.owns(self, player: Player): boolean?
	return self._owned[player]
end

--[[ Ask Roblox, cache it, and mirror it onto the Player for the panel.

	FAILURE IS NOT "NO". A `UserOwnsGamePassAsync` that throws — Roblox having a bad minute — must
	not be cached as false, because false is the state that offers to sell the pass to somebody who
	already owns it and would take a paying player's radio away for the rest of their session. So a
	throw leaves the cache untouched (unknown on a join, whatever it was before otherwise) and the
	panel says "checking" rather than showing a price. ]]
function RadioService._refreshOwnership(self, player: Player)
	if not RadioConfig.sellable() then
		return
	end

	local ok, owned = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, RadioConfig.PassId)
	end)
	if not ok then
		self.log:warn(string.format("Could not read %s's radio pass ownership: %s", player.Name, tostring(owned)))
		return
	end
	if player.Parent ~= Players then
		return
	end

	self._owned[player] = owned == true
	player:SetAttribute(RadioConfig.OwnedAttribute, owned == true)
end

--[[ Open Roblox's prompt. Money never moves here and nothing is granted on the way back — the pass
	IS the grant, and `PromptGamePassPurchaseFinished` only re-reads ownership from Roblox rather
	than trusting its own `wasPurchased`. That is the same rule the products follow ("a car only ever
	moves on a receipt") applied to the one thing that has no receipt. ]]
function RadioService._prompt(self, player: Player)
	--[[ Report the prompt being SHOWN, which is the half of the conversion Roblox cannot tell you:
		a purchase says somebody bought, and only the pair says how many were asked. Fired before the
		prompt rather than after, so a prompt that throws below is still counted as offered. ]]
	local Analytics = Shard.get("AnalyticsService")
	if Analytics then
		Analytics:PromptShown(player, RadioConfig.PassId)
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, RadioConfig.PassId)
	end)
	if not ok then
		self.log:warn(string.format("Could not prompt %s for the radio pass: %s", player.Name, tostring(err)))
		self:_say(player, false, "The Robux prompt could not open. Try again in a moment.")
	end
end

-- === The car ================================================================

--[[ The lobby car this player has standing in the world, or nil.

	FOUND BY THE OWNER STAMP rather than by asking `LobbyCarService` for its private table — that
	stamp is what `LobbyCarConfig` documents as the public answer to "whose car is this", and going
	through it means this service cannot be broken by that one changing how it bookkeeps.

	`IsDescendantOf(workspace)` for the same reason `LobbyCarService._carOf` re-checks it: a model
	deleted by anything else must read as "no car", not as a dead handle. ]]
function RadioService._carOf(self, player: Player): Model?
	local folder = workspace:FindFirstChild(LobbyCarConfig.FolderName)
	if not folder then
		return nil
	end
	for _, car in folder:GetChildren() do
		if car:IsA("Model") and car:GetAttribute(LobbyCarConfig.OwnerAttribute) == player.UserId then
			return if car:IsDescendantOf(workspace) then car else nil
		end
	end
	return nil
end

--[[ Write the answer onto the car. The only place in the game that sets these three, and therefore
	the only place a listener's radio can be changed from.

	THE STAMP IS TAKEN ONCE AND USED TWICE — it is the origin the schedule is measured from AND the
	seed the shuffle is dealt from (`RadioConfig.StationAttribute` and friends explain why one value
	does both jobs).

	STATION FIRST, STAMP LAST. Attributes replicate individually and a listener reacts to any of
	them changing, so the order decides what a client that reads the set mid-flight sees: with the
	stamp written last, a client can briefly see the NEW station against the OLD stamp — which is a
	song a couple of seconds out of place for one frame — where the other order would have it
	compute the new stamp against the old station, which is the same thing but with the track it was
	already playing restarting first. Both are recoverable; this one is inaudible. ]]
function RadioService._apply(self, car: Model, station: string, trackId: number?)
	car:SetAttribute(RadioConfig.StationAttribute, station)
	car:SetAttribute(RadioConfig.TrackAttribute, trackId or 0)
	car:SetAttribute(RadioConfig.StartedAttribute, workspace:GetServerTimeNow())
end

--- Silence. Safe on a car that was never playing.
function RadioService._clear(self, car: Model)
	car:SetAttribute(RadioConfig.StationAttribute, "")
	car:SetAttribute(RadioConfig.TrackAttribute, 0)
	car:SetAttribute(RadioConfig.StartedAttribute, 0)
end

--[[ The panel's status line, and the ONLY thing this service ever sends a client. `ok` picks the
	colour at the other end; the message is the sentence.

	NOTHING TELLS A CLIENT WHAT ITS OWN RADIO IS ON, which is worth saying out loud because it is
	the obvious second message to add and it would be wrong. The station is already on the car, the
	player's own car is the one car they are guaranteed to have streamed in (it spawns beside them),
	and `RadioController` reads it there — so a "your radio is now X" message would be a second
	source of truth for something the first one cannot be out of date about. Same reasoning as the
	Cars Inventory drawing itself from `LobbyCarConfig.SpawnedAttribute` rather than from a reply. ]]
function RadioService._say(self, player: Player, ok: boolean, message: string)
	if player.Parent ~= Players then
		return
	end
	self:getRemoteEvent(RadioConfig.ReplyName):Fire(player, ok, message)
end

-- === The pasted track =======================================================

--[[ May this audio id be played here? Returns (ok, message) — and the message is the point of the
	whole function, because the failure it is guarding against has no other symptom.

	SINCE ROBLOX'S 2022 AUDIO PRIVACY CHANGE, an upload is private to its creator unless they publish
	it or grant this experience permission. A private id assigned to a `Sound` does not error, does
	not warn and does not fire `Ended` — it plays nothing, forever. So a player pasting the id of a
	song they found on YouTube (or their own upload, or a friend's) gets a car that makes no noise
	and a pass that looks broken.

	`IsPublicDomain` IS THE TEST, plus one exception: audio uploaded by this experience's own creator
	is playable here whether or not it is public, so a group id match passes too. That exception is
	what lets the boss paste an in-house track and have it work.

	CACHED FOREVER-ISH, keyed by id, because `GetProductInfo` is a web call on a player-driven path
	and the answer for a given id essentially never changes. The cache is capped so a server left up
	for a week cannot grow one entry per id anyone ever typed. ]]
function RadioService._checkTrack(self, id: number): (boolean, string)
	local cached = self._tracks[id]
	if cached ~= nil then
		return cached.ok, cached.message
	end

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, Enum.InfoType.Asset)
	end)

	local verdict, message
	if not ok or type(info) ~= "table" then
		--[[ NOT CACHED. A lookup that failed because Roblox was unreachable is not a fact about the
			id, and remembering it as one would make a momentary outage into a track this server
			refuses for the rest of its life. ]]
		return false, "Could not look that track up. Try again in a moment."
	elseif info.AssetTypeId ~= AUDIO_ASSET_TYPE then
		verdict, message = false, "That ID is not an audio track."
	elseif not (info.IsPublicDomain or self:_creatorOwns(info)) then
		verdict, message = false, "That track is private — only its uploader can play it."
	else
		verdict, message = true, type(info.Name) == "string" and info.Name or ""
	end

	self:_remember(id, verdict, message)
	return verdict, message
end

--- Was this asset uploaded by the account or group that owns this experience? See `_checkTrack`.
function RadioService._creatorOwns(self, info): boolean
	local creator = info.Creator
	if type(creator) ~= "table" then
		return false
	end
	local id = tonumber(creator.CreatorTargetId)
	if not id then
		return false
	end
	if creator.CreatorType == "Group" then
		return id == game.CreatorId and game.CreatorType == Enum.CreatorType.Group
	end
	return id == game.CreatorId and game.CreatorType == Enum.CreatorType.User
end

--- Put a verdict in the cache, evicting the oldest if it is full. Insertion-ordered, which for a
--- cache of "ids people typed" is close enough to least-recently-used and is one table.
function RadioService._remember(self, id: number, ok: boolean, message: string)
	if self._tracks[id] == nil then
		table.insert(self._trackOrder, id)
		while #self._trackOrder > 256 do
			local oldest = table.remove(self._trackOrder, 1)
			if oldest then
				self._tracks[oldest] = nil
			end
		end
	end
	self._tracks[id] = { ok = ok, message = message }
end

-- === The request ============================================================

--[[ Public: put `station` on this player's car. `nil` turns it off. Returns (ok, message) so a
	trusted caller — the admin panel, a future tile in the world — gets the same answers the panel
	does.

	TURNING IT OFF IS NOT GATED ON THE PASS, and that is deliberate rather than an oversight. If a
	pass were ever refunded, or `RadioConfig.Enabled` switched off mid-session, an owner whose car
	is playing must still be able to stop it; a silence button that answers "buy the pass" is the
	worst possible sentence to read at that moment. Everything else here is gated. ]]
function RadioService.setStation(self, player: Player, station: string?, trackId: number?): (boolean, string)
	if not RadioConfig.Enabled then
		return false, "disabled"
	end

	local car = self:_carOf(player)
	if not car then
		return false, "Spawn one of your cars first — the radio plays out of it."
	end

	if station == nil then
		self:_clear(car)
		return true, ""
	end

	if self:owns(player) ~= true then
		self:_prompt(player)
		return false, "" -- the prompt IS the message; see `_prompt`
	end

	if station == RadioConfig.CustomStation then
		if not RadioConfig.Custom.Enabled then
			return false, "Custom tracks are switched off right now."
		end
		local id = tonumber(trackId)
		if not id or id <= 0 or id ~= math.floor(id) then
			return false, "That is not an audio ID."
		end

		local allowed, message = self:_checkTrack(id)
		if not allowed then
			return false, message
		end

		self:_apply(car, RadioConfig.CustomStation, id)
		--[[ The track's own name back, so the panel can confirm what went on rather than echoing the
			number the player typed — which is the one thing they already know. ]]
		return true, if message ~= "" then "Now playing: " .. message else ""
	end

	local found = RadioConfig.stationByKey(station)
	if not found then
		return false, "No such station."
	end

	self:_apply(car, found.Key, nil)
	self:_saveStation(player, found.Key)
	return true, "Now playing: " .. found.Name
end

--[[ The remote's end of `setStation` — the rate-limited front door, the same shape as
	`LobbyCarService._onSpawnRequest`, and rate-limited for a reason that file's cooldown does not
	have: a custom id costs a `GetProductInfo`, which is a web call this player chose the timing of.
	Stamped on the ATTEMPT, so a refused request costs a table write. ]]
function RadioService._onRequest(self, player: Player, station: unknown, trackId: unknown)
	local now = os.clock()
	local blockedUntil = self._cooldowns[player]
	if blockedUntil and now < blockedUntil then
		return
	end
	self._cooldowns[player] = now + RadioConfig.RequestCooldown

	if station ~= nil and type(station) ~= "string" then
		return
	end
	if trackId ~= nil and type(trackId) ~= "number" then
		return
	end

	--[[ Spawned, because `setStation` can yield on `GetProductInfo` and a remote handler that yields
		holds the whole event queue behind it. The cooldown above is already stamped, so a second
		press while this one is out on the web is refused before it gets here. ]]
	task.spawn(function()
		local ok, message = self:setStation(player, station :: string?, tonumber(trackId))
		if message ~= "" then
			self:_say(player, ok, message)
		end
	end)
end

-- === Remembering the station ================================================

--- The profile, or nil if it has not loaded yet. Non-yielding, same contract as MusicService's.
function RadioService._profile(self, player: Player)
	local profile = self._profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

--- Keep the station they chose, so tomorrow's car comes up playing it. A preference and nothing
--- more — `RadioConfig.ProfileKey` has the reasoning, including why a custom track is not kept.
function RadioService._saveStation(self, player: Player, key: string)
	local profile = self:_profile(player)
	if profile then
		profile:Set(RadioConfig.ProfileKey, key)
	end
end

--[[ What a car this player spawns should come up playing: the station they last chose, or the
	default, or nothing if they do not own the pass.

	A REMEMBERED KEY THAT NO LONGER EXISTS FALLS BACK TO THE DEFAULT rather than to silence, which is
	the same bargain `MusicConfig` note 2 makes for an unthemed world: dropping a station from the
	list should read as "you are on a different station now", never as "your radio broke". ]]
function RadioService._stationFor(self, player: Player): string?
	if self:owns(player) ~= true then
		return nil
	end
	local profile = self:_profile(player)
	local saved = profile and profile:Get(RadioConfig.ProfileKey)
	if type(saved) == "string" and RadioConfig.stationByKey(saved) then
		return saved
	end
	return if RadioConfig.stationByKey(RadioConfig.DefaultStation) then RadioConfig.DefaultStation else nil
end

-- === Lifecycle ==============================================================

--[[ A car has just been put in the lobby. Two things happen to it here and they are separate.

	IT IS TAGGED WHETHER OR NOT ANYTHING IS PLAYING. `RadioConfig.CarTag` explains why: the tag is
	how a listener finds a car at all, and `CollectionService`'s added signal fires on STREAMING as
	well as on parenting — so a car that streams back into range has to arrive already tagged or its
	radio never comes back.

	AND IT PICKS UP WHERE THE OWNER LEFT OFF. An owner who had Drift FM on last session gets Drift
	FM on the car they spawn today, because a pass that has to be re-switched-on every single time
	is a pass that feels like a consumable.

	SYNCHRONOUS WITH THE SPAWN, on purpose: `LobbyCarService` fires this signal in the same frame it
	parents the car, so the tag and all three attributes are part of the model's initial replication
	rather than a change that arrives after every client has already drawn a silent car. ]]
function RadioService._onCarSpawned(self, player: Player, _body: string, car: Model)
	CollectionService:AddTag(car, RadioConfig.CarTag)

	local station = self:_stationFor(player)
	if station then
		self:_apply(car, station, nil)
	else
		self:_clear(car)
	end
end

--[[ Cache the profile and the pass off the join path.

	It hangs off `GarageService.ProfileReady` rather than `PlayerAdded` for `RandomCarService`'s
	reason: that signal is precisely "the profile has arrived", so `GetProfileAsync` returns
	immediately here. The pass check is the one web call this feature makes per session and it is
	made here, once, well before anybody can press anything. ]]
function RadioService._watch(self, player: Player)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Data:GetProfileAsync(player)
		end)
		if not ok or not profile or player.Parent ~= Players or not profile:IsActive() then
			return
		end
		self._profiles[player] = profile
		self:_refreshOwnership(player)
	end)
end

RadioService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		--- [Player] = true/false/nil. nil is "not asked yet" and is NOT false — see `owns`.
		self._owned = {} :: { [Player]: boolean? }
		--- [Player] = os.clock() before which a request is ignored.
		self._cooldowns = {} :: { [Player]: number }
		--- [assetId] = { ok, message } — see `_checkTrack`, and `_trackOrder` for the eviction.
		self._tracks = {} :: { [number]: { ok: boolean, message: string } }
		self._trackOrder = {} :: { number }
	end,

	start = function(self)
		if not RadioConfig.Enabled then
			return
		end
		self._trove = Trove.new()

		local Garage = Shard.get("GarageService")
		if Garage then
			self._trove:Add(Garage:getSignal("ProfileReady"):Connect(function(player: Player)
				self:_watch(player)
			end))
			--[[ Catch up on anyone already ready — `GarageService` fires that off the join path, so
				a player can be warm before this connects. `RandomCarService` has the same block. ]]
			for _, player in Players:GetPlayers() do
				if Garage:isProfileReady(player) then
					self:_watch(player)
				end
			end
		else
			self.log:warn("No GarageService — the radio pass cannot be checked and nothing will play.")
		end

		local LobbyCars = Shard.get("LobbyCarService")
		if LobbyCars then
			self._trove:Add(LobbyCars:getSignal("CarSpawned"):Connect(function(player, body, car)
				self:_onCarSpawned(player, body, car)
			end))
		else
			self.log:warn("No LobbyCarService — there is nothing for a radio to play out of.")
		end

		--[[ A pass prompt that closed. RE-READ FROM ROBLOX rather than trusting `wasPurchased`,
			which is the same rule the products follow for receipts and matters more here: this
			callback fires on a cancel too, and a `false` taken at face value would be indistinguish-
			able from "they already owned it and dismissed the prompt".

			The re-read is also what switches the radio on for somebody who just bought it while
			standing next to their car — they should not have to press anything a second time. ]]
		if RadioConfig.sellable() then
			self._trove:Add(MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
				if passId ~= RadioConfig.PassId or not wasPurchased then
					return
				end
				task.spawn(function()
					self:_refreshOwnership(player)
					if self:owns(player) ~= true then
						return
					end
					local car = self:_carOf(player)
					local station = self:_stationFor(player)
					if car and station then
						self:_apply(car, station, nil)
					end
				end)
			end))
		end

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self._profiles[player] = nil
			self._owned[player] = nil
			self._cooldowns[player] = nil
		end))
	end,
})

RadioService:withCleanup(function()
	if RadioService._trove then
		RadioService._trove:Destroy()
	end
end)

return RadioService
