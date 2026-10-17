--[[
	SellService  (server)
	---------------------
	THE LOT YOU SELL A CAR AT. `SellConfig` has the design and every number, `Modules/SellLot` draws
	the geometry, and this file is the binding, the gate and the till.

	It is the only path that takes a car away from a player that a player can reach. `sellCars` is
	still the one that decides what that means — the ownership check, the cap, the unpark, the bay
	collect, the flag prune and the price all live in `GarageService` and none of it moved here. What
	this file adds is a place, a volume, and the checks that stand in for a player really being at it.

	=== IT BINDS WHAT IS IN THE PLACE. IT DOES NOT BUILD IT ===================================

	The lot is AUTHORED (the owner's call, so it can be restyled by hand) and lives in the saved
	place, tagged `SellLot`. This service finds it, checks it has the one part it owes, takes the old
	button off it and goes to sleep. Move the pad in Studio and the sell area moves with it; replace
	the beams with the modeller's art and nothing here notices.

	THE TAG IS PLURAL. Duplicate the lot in Studio, drag the copy to the far side of the plaza and it
	is a second sell lot: a request is measured against EVERY bound lot and any one of them accepting
	is a sale, so the volume that is checked is whichever one the player is actually standing at.

	THERE IS STILL A FALLBACK, and it is a warning rather than a feature. If no tagged lot is in the
	place — a fresh map, a swap that ate it (`docs/MapLayout.md` §6 has that happening before, to the
	upgrade billboards, silently), somebody deleting it — the service builds one from
	`Modules/SellLot` at the derived pose and says so loudly in the log. The game keeps working and
	the next person to open the place is told to author one with `BuildSellLot`. What it must never
	do is quietly bind nothing, which is exactly how the forecourt signs went missing for a week.

	=== THE BUTTON IS GONE AND A REMOTE TOOK ITS PLACE, 2026-08-31 ============================

	UNTIL THIS PASS THERE WAS NO CLIENT -> SERVER REMOTE IN THIS FEATURE AT ALL, and the file said so
	proudly: a sale arrived as `ProximityPrompt.Triggered`, which the engine only fires for a player
	genuinely standing within `MaxDistance` of the button and which already carried who pressed it.
	That is a real thing to have given up and it is worth being honest about what replaced it.

	The owner asked for the held button to go — it was a third step, and it was the one stock-styled
	surface in a lobby made of the kit (`SellConfig`'s header). A panel with a YES on it has to be
	able to ask, so there is now a `RequestSell` remote. What it costs is one check the engine used
	to make for free, and `_atLot` is that check written out by hand: the sender's own character has
	to be within `SellConfig.Request.Reach` of a bound lot's pad.

	WHAT IT DOES NOT COST is anything else, because the request is EMPTY. It carries no key, no car
	and no price — it means "sell what I have standing on the pad", and every fact the sale is made
	of is looked up here from the sender: their lobby car off the model's own owner attribute, its
	key off the model, its price out of `GarageConfig`. There is no request shape to validate and
	still no way to name somebody else's car.

	=== WHAT IT OWNS AND WHAT IT DELIBERATELY DOES NOT ========================================

	It owns whether a request is allowed. It does NOT own:

	  • THE GEOMETRY. `Modules/SellLot` draws it and the place stores it. One builder, two callers
	    (this and the Command Runner), so an authored lot and a fallback cannot drift apart.
	  • THE SALE. `GarageService.sellCars` is called with a one-car list and every rule it has still
	    applies. If it refuses, the refusal is reported and nothing here second-guesses it.
	  • PUTTING THE CAR AWAY. `LobbyCarService` already despawns a car that was sold while it was
	    standing out — it listens to `CarsSold` and matches on the key. So the model this file
	    measured is gone a frame later without this file touching it, and there is exactly one path
	    that destroys a lobby car.
	  • WHEN THE QUESTION IS ASKED. `SellController` watches for a car of the player's coming to rest
	    on the pad with nobody in it and raises the panel; this file never tells anybody to ask. That
	    is the same split the price sign has always been on — the client owns what differs per player,
	    and when to ask a question is about as personal as it gets.
	  • THE FAVOURITE'S SECOND PRESS. A starred car draws a star and an amber line, and the first
	    SELL IT on the panel turns the title into ARE YOU SURE? rather than sending anything. The
	    server used to own that guard — it armed on the first hold and kept pending state per player
	    — and it owns none of it now (`SellConfig` note 7). That is safe because of what the guard is
	    FOR: it stops a slip of the mouse, not a cheat, and a client that skipped it would sell its
	    own starred car and nobody else's, which it could do anyway by pressing twice.

	=== THE THREE THINGS THAT ARE NOT OBVIOUS ==================================================

	1. THE PAD IS THE VOLUME AND IT IS READ LIVE. Whether a car counts as "in the lot" is a
	   point-in-box test against the pad part's own CFrame and Size at the moment of the request
	   (`SellConfig.isInside`). Nothing is cached and nothing is derived from a bearing, so an artist
	   dragging the pad across the plaza moves the sell area with it and no code has to be told.

	2. THERE IS NO OCCUPANCY STATE AND NOTHING POLLS. A request asks, at that moment, whether the
	   sender's own lobby car is inside one of the boxes. Between requests this service is asleep.
	   That is the whole reason the lot is a volume rather than a set of bays (`SellConfig` note 2) —
	   bays would need a table saying who is on which, and a table like that can disagree with the
	   world.

	3. THE REFUSALS ARE NAMED, AND THAT IS WHAT THEY ARE FOR. `sellCars` re-checks the ownership
	   itself and is welcome to; the checks here exist so the answer can say WHICH one failed, which
	   is the difference between a panel that closes for no reason and one that says the car rolled
	   off the pad.

	=== COLLECTION PICKER, 2026-10-12 ===
	The prompt now opens the shared spawn grid in sell mode. The selected key crosses on
	RequestSell; the car need not be on the pad or spawned. This supersedes the empty-request
	and parked-car rules above. The player must still be alive, in the lobby, near a bound lot,
	and own that exact key. GarageService remains the only writer and the only source of prices.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local SellConfig = require(ReplicatedStorage.shared.Configs.SellConfig)
local SellLot = require(ReplicatedStorage.shared.Modules.SellLot)

local SellService = Shard.new("SellService"):withDependencies({ "GarageService" })

SellService:withSignals({
	--[[ (player, key, price) — a car was sold at the lot. The money is in and the car is out of the
		collection by the time this fires, so a subscriber reading the profile sees the sale done.
		Here for whatever wants to count it: a quest, an analytics funnel, a server feed. ]]
	"CarSold",
})

SellService:withRemoteEvents({
	--[[ server -> client (reason: string, price: number): what your request did. `"sold"` is the one
		success and carries the money; everything else is a refusal, and the panel and the sign each
		draw the ones that can reach them (`SellConfig.Lines`, `SellConfig.PopupLines`).

		FIRED ONLY AT THE SENDER. Nobody else needs to know, and a refusal is a private matter between
		a player and a question they just answered. ]]
	"SellResult",
	"OpenSellPicker",
	{
		-- Only a selected key is accepted; the server rechecks it against the owned collection.
		RequestSell = function(player: Player, key: unknown)
			SellService:_onRequest(player, key)
		end,
	},
})

-- === Selling ================================================================

--[[ The car this player has standing in the lobby, or nil.

	READ OFF THE MODEL'S OWN ATTRIBUTE rather than asked of `LobbyCarService`, which has no public
	getter — and `LobbyCarConfig` documents the flat folder plus `OwnerAttribute` as exactly this
	contract ("the owner is on the model as an attribute"). It also means this service does not
	depend on that one, so a lobby car put out by anything else is still a car this lot can buy.

	The folder may not exist at all: nobody has spawned a car yet on a fresh server. ]]
function SellService._carOf(self, player: Player): Model?
	local folder = workspace:FindFirstChild(LobbyCarConfig.FolderName)
	if not folder then
		return nil
	end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute(LobbyCarConfig.OwnerAttribute) == player.UserId then
			return model
		end
	end
	return nil
end

--[[ Is this player standing at a sell lot, and if so which one's pad?

	THIS IS THE CHECK THE `ProximityPrompt` USED TO MAKE FOR FREE (header). It is the whole of what
	the remote cost, so it is the whole of what has to be paid back: no character, no sale.

	EVERY BOUND LOT IS TRIED and the first one in reach wins, which is what makes two lots on the
	plaza two real places to sell rather than one real one and one decoration. The pad it returns is
	the one the car is then measured against, so a player standing at the north lot cannot sell a car
	parked on the south one.

	MEASURED FROM THE PAD'S CENTRE to the character's root, both in world space, and against
	`Request.Reach` rather than the panel's own — that number is deliberately looser, and the comment
	on it says why. ]]
function SellService._atLot(self, player: Player): BasePart?
	local race = Shard.get("RaceService")
	if race and (race:isRacing(player) or race:isReturning(player)) then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then return nil end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end

	local reach = SellConfig.Request.Reach
	for _, lot in self._lots do
		local pad = self:_padOf(lot)
		if pad and (pad.Position - root.Position).Magnitude <= reach then
			return pad
		end
	end
	return nil
end

--- Is this player sitting in this car? Selling destroys it, and dropping somebody out of a seat
--- mid-physics is the one failure worth a refusal rather than a shrug — `SellConfig` note 5.
function SellService._seatedIn(_self, player: Player, car: Model): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	return seat ~= nil and seat:IsDescendantOf(car)
end

--- Tell the presser, and only the presser, what their press did.
function SellService._reply(self, player: Player, reason: string, price: number?)
	self:getRemoteEvent("SellResult"):Fire(player, reason, price or 0)
end

-- The prompt grants no authority: each sale rechecks proximity and ownership, and never accepts
-- a price from the client. The attempt cooldown applies equally to refusals and successful sales.
function SellService._onRequest(self, player: Player, key: unknown)
	if not (SellConfig.Enabled and GarageConfig.Enabled and InventoryConfig.Enabled and InventoryConfig.Sell.Enabled) then
		return
	end

	--[[ STAMPED ON THE ATTEMPT, so a refusal costs a client as much as a sale does — which is what
		stops the remote being worth hammering. It is also the one path that answers nothing: a request
		inside the window arrived while the answer to the last one was still in flight. ]]
	local now = os.clock()
	local last = self._cooldowns[player]
	if last and now - last < SellConfig.Request.Cooldown then
		return
	end
	self._cooldowns[player] = now

	local GarageService = Shard.get("GarageService")
	if not (GarageService and GarageService:isProfileReady(player)) then
		return
	end

	--[[ THE PROXIMITY CHECK, and the only reason it is written out at all is that the prompt this
		replaced made it for free. A request from somebody who is not at the lot is not a mistake a real
		client can make — the panel closes itself the moment they walk out of `Popup.Reach` — so it is
		answered as a plain refusal and logged like one. ]]
	local pad = self:_atLot(player)
	if not pad then
		self.log:info(string.format("%s asked to sell a car but is not standing at a lot.", player.Name))
		self:_reply(player, "away")
		return
	end

	-- Only the identity crosses: ownership and price always come from the server profile.
	if type(key) ~= "string" or #key == 0 or #key > 256 or not GarageService:owns(player, key) then
		self:_reply(player, "notOwned")
		return
	end
	local car = self:_carOf(player)
	if car and car:GetAttribute(LobbyCarConfig.KeyAttribute) == key and self:_seatedIn(player, car) then
		self:_reply(player, "seated")
		return
	end

	--[[ THE LOT'S PRICE, read off the server's own record of the car. It is passed as the agreed
		price, which is the route a buyer's offer already takes, so `sellCars` still owns every other
		rule. Same helper the labels print through (`SellConfig.lotPriceOf`), so the button and the
		till agree. ]]
	local price = SellConfig.lotPriceOf(key, GarageService:getCarData(player, key))
	local sold, total, reason = GarageService:sellCars(player, { key }, { [key] = price }, "Lot")
	if sold == 0 then
		self.log:info(string.format("%s's sale at the lot was refused (%s).", player.Name, reason))
		self:_reply(player, reason)
		return
	end

	--[[ The car is not put away here. `LobbyCarService` listens to `CarsSold`, matches on this exact
		key and despawns it — so by the time this line runs the model measured above is either gone
		or about to be, and there is one path in the game that destroys a lobby car. ]]
	self.log:info(string.format("%s sold %s at the lot for %d.", player.Name, key, total))
	self:getSignal("CarSold"):Fire(player, key, total)
	self:_reply(player, "sold", total)
end

-- === Binding ================================================================

--- The pad of one bound lot, or nil if that lot has been deleted out from under it. Cheap enough to
--- ask per press (header note 1).
function SellService._padOf(_self, lot: Model): BasePart?
	if not lot.Parent then
		return nil
	end
	local pad = lot:FindFirstChild(SellConfig.Names.Pad, true)
	return if pad and pad:IsA("BasePart") then pad else nil
end

--[[ Take ownership of one lot: check it has what it owes, take off what it should not have, and
	remember it.

	IT REPAIRS TWO THINGS AND REFUSES ON ONE. A missing bubble anchor is re-created (it is derived
	from a config number, so there is nothing to lose) and the board's WORDS are redrawn from
	`SellConfig.Lines` every boot. A missing PAD is fatal for that lot: the pad is the volume, and a
	lot without one is a decoration.

	THE WORDS ARE REDRAWN BECAUSE THEY ARE NOT THE ARTIST'S. Everything else on that board — the pole,
	the panel, the paint, where it stands — is authored and is left alone. The two lines of type are
	config, and an authored board keeps whatever was on it the day somebody last ran `BuildSellLot`:
	the caption said DRIVE IN AND HOLD THE BUTTON for the whole of the pass that deleted the button,
	because nothing on the boot path had any reason to look at it. Same argument the old
	`applyPrompt` made about the hold duration, applied to the one thing left that can go stale.

	IT ALSO STRIPS THE OLD BUTTON, every lot, every boot — `SellLot.strip` and its comment have the
	whole of why. Short version: the button was authored into the saved place, nothing listens to it
	any more, and a live prompt nothing is bound to is worse than no prompt at all.

	THERE IS NOTHING LEFT TO WIRE. Adoption used to end by raising a `ProximityPrompt` and connecting
	its `Triggered`; the press is a remote now and it is bound once in `start`, not per lot. What this
	function produces is an entry in `self._lots`, which is the list `_atLot` measures against. ]]
function SellService._adopt(self, lot: Model, built: boolean): boolean
	local pad = lot:FindFirstChild(SellConfig.Names.Pad, true)
	if not (pad and pad:IsA("BasePart")) then
		self.log:warn(string.format(
			"%s carries the %s tag but has no %s part — it cannot be a sell lot, because the pad IS the volume. Re-run BuildSellLot.",
			lot:GetFullName(),
			SellConfig.Tag,
			SellConfig.Names.Pad
		))
		return false
	end

	SellLot.anchorOn(pad)
	--[[ ATOMIC, SET HERE AND NOT TRUSTED TO THE PLACE (2026-10-15, the two hand-built booths in
		`Workspace.SellLot`). `SellController._bind` needs the pad and its bubble anchor in the same
		arrival, and only a lot `SellLot.build` made was ever set Atomic; an authored one streamed part
		by part could land without them and be skipped with a warning, a booth with no sign over it. ]]
	lot.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	--[[ The board's two lines, from config, over whatever the place has on them. Skipped without a
		word if the lot has no board: a modeller who replaced the sign with their own art has not
		broken anything, and a lot with no sign at all still sells cars. ]]
	local board = lot:FindFirstChild(SellConfig.Names.Sign, true)
	if board and board:IsA("BasePart") then
		SellLot.drawSign(board)
	end

	SellLot.strip(lot)
	local prompt = lot:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SellPickerPrompt"
		prompt.Parent = pad
	end
	prompt.ActionText = "Choose a car"
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.ObjectText = "Sell your cars"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = SellConfig.Popup.Reach
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
	self._trove:Add(prompt.Triggered:Connect(function(player: Player)
		if not self:_atLot(player) then return end
		local now = os.clock()
		if now - (self._openedAt[player] or -math.huge) < SellConfig.Request.Cooldown then return end
		self._openedAt[player] = now
		self:getRemoteEvent("OpenSellPicker"):Fire(player)
	end))

	table.insert(self._lots, lot)

	local position = pad.Position
	if built then
		self.log:warn(string.format(
			"No sell lot was authored in this place, so one was BUILT at (%.0f, %.0f, %.0f) for this server only. It will not be there next time: open the place and run the BuildSellLot command to author one.",
			position.X,
			position.Y,
			position.Z
		))
	else
		self.log:info(string.format("Bound a sell lot at (%.0f, %.0f, %.0f).", position.X, position.Y, position.Z))
	end
	return true
end

--[[ Find the authored lot, or stand one up.

	IT RUNS ONCE AND IT IS NOT RETRIED. A place with no island in it is a much bigger problem than a
	missing lot, and a retry loop against a `FindFirstChild` that will never succeed is a warning
	nobody reads repeated forever.

	EVERY TAGGED LOT IS BOUND, not just the first. Two lots on opposite sides of the plaza are two
	places to sell a car and cost nothing but an extra entry in the list `_atLot` walks, and the old
	behaviour (bind one, log the rest as inert) meant a duplicate made in Studio looked finished and
	was dead. A lot that cannot be adopted, which in practice means it has no pad, is still skipped
	and still warns.

	THE FALLBACK IS ONLY FOR AN EMPTY PLACE. It runs when NO tagged lot could be adopted, so a place
	with one good lot and one broken one gets the warning and the good lot, never a third built on
	top of them. ]]
function SellService._bind(self)
	local authored = SellLot.existing()
	local bound = 0
	for _, lot in authored do
		if self:_adopt(lot, false) then
			bound += 1
		end
	end
	if bound > 0 then
		return
	end

	--- Nothing usable in the place. Build one for this server and say so — see the header.
	local frame, clear, why = SellLot.findPose()
	if not frame then
		self.log:warn(string.format("No sell lot in the place and none could be built: %s", why))
		return
	end
	if not clear then
		self.log:warn(why)
	end

	local folder = Instance.new("Folder")
	folder.Name = SellConfig.FolderName
	folder.Parent = workspace
	self._trove:Add(folder)

	local lot = SellLot.build(frame)
	lot.Parent = folder
	self:_adopt(lot, true)
end

-- === Lifecycle ==============================================================

SellService:withLifecycle({
	init = function(self)
		--- Every lot wearing the tag, in the order they were adopted. A list and not one model,
		--- because the tag never promised there was only one of them, and `_atLot` walks all of them.
		self._lots = {} :: { Model }
		--- Per player, so one person hammering the remote cannot cost anybody else their sale.
		self._cooldowns = {} :: { [Player]: number }
		self._openedAt = {} :: { [Player]: number }
		self._trove = Trove.new()
	end,

	start = function(self)
		if not SellConfig.Enabled then
			self.log:info("Disabled by config — there is no way to sell a car.")
			return
		end

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self._cooldowns[player] = nil
			self._openedAt[player] = nil
		end))

		--- Spawned rather than awaited: the fallback path raycasts and runs overlap queries against a
		--- 43,000-part map, and `Shard.start()` is the server's boot barrier. Nothing waits on the
		--- lot existing.
		task.spawn(function()
			self:_bind()
		end)
	end,
})

--[[ WHAT CLEANUP MAY DESTROY IS ONLY WHAT THIS SERVICE MADE.

	The trove holds the fallback folder, so a built lot goes; an AUTHORED lot is the place's and is
	left exactly where it is. The old version of this file destroyed everything carrying the tag,
	which was right when nothing was authored and would now delete the artist's work on a hot
	reload. ]]
SellService:withCleanup(function()
	if SellService._trove then
		SellService._trove:Destroy()
	end
	SellService._lots = {}
end)

return SellService
