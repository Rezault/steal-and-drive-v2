--[[
	AdminService  (server — the F2 panel's door, and the only thing that opens it)
	------------------------------------------------------------------------------
	One remote, one admin check, one rate limit, one audit line. Everything the panel can GRANT
	comes through here: a car onto somebody's lot, cash onto their balance, a random-car pull, an
	extra life, an offline boost, a road pickup into a live run, a world unlocked and a player moved
	into it, and (since 2026-09-28) a buyer on a car, a welcome-back screen for an absence that did
	not happen, and a lot's worth of car condition. Nothing here decides
	what any of those things are worth or where they go — every action below is three lines that call
	a function that already existed and shipped.

	=== WHY THIS EXISTS AT ALL ================================================================

	`AdminPanelController` is a client. Its `Admins.isAdmin` gate stops the window opening, which is
	a convenience for the person holding the keyboard and NOT a fact about the network: the remotes
	the panel fires exist in every client's ReplicatedStorage, named, with their arguments visible
	in the traffic. So the check that matters is the one on this side, and it is on this side of
	every action rather than at the panel.

	ONE ACTION HERE GRANTS NOTHING, and it is worth knowing which before reading the paragraph below
	as covering everything: `reference` parks a stock, unpainted copy of a car in front of the admin
	to hold a repaint against, and `clearReference` takes it away. They touch no profile and no
	balance. They live here anyway because the admin check, the rate limit and the audit line are the
	same ones, and a second door with the same lock on it is a second lock to get wrong.

	It is worth being blunt about what is behind the rest. `car` writes a car into a save file, `pull`
	writes a Robux product's payload without a receipt, and `life` and `boost` do the same for
	theirs. `cash` moves a balance, and `cashOffline` moves the balance of somebody who is not even
	here — it is the one action that reaches a save file this server has never opened. `unlock` writes
	which worlds somebody owns, in both directions, which is the only action here that can also TAKE
	something from somebody else. `wipe` takes everything, but only ever from the admin who pressed
	it: it marks their own save to be emptied and sends them back in as a new player. `tutorial`
	grants nothing and takes nothing; it puts somebody back on the first beat of the onboarding.
	This remote is the game's cheat menu; the `Admins` list is the whole of what stands in front of it, and that
	list is the thing to be careful with, not this file.

	=== WHAT IT IS NOT ========================================================================

	It is not where every admin action in the game lives. Weather's panel tab talks to
	`WeatherService` directly and correctly: those actions are surgery on that service's own
	schedule (`_begin`, `_end`, `_pick`) rather than a public grant, and moving them here would
	mean exporting three private functions so a second file could drive them. The rule the split
	follows: IF THE ACTION IS ALREADY A PUBLIC FUNCTION SOMEBODY ELSE CALLS, it belongs here; if it
	is a service's internals, its own service owns the door and re-checks `Admins` itself.

	It is also not a command runner. There is no parser, no argument grammar and no help text — the
	panel is the only caller, it is typed, and a string command language between two files in the
	same repository would be a way of making a function call harder to find.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Admins = require(ReplicatedStorage.shared.Configs.Admins)
local CarDisplay = require(ReplicatedStorage.shared.Modules.CarDisplay)
local CarPlate = require(ReplicatedStorage.shared.Modules.CarPlate)
local Data = require(script.Parent.Parent.Data)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local PassConfig = require(ReplicatedStorage.shared.Configs.PassConfig)
local Shard = require(ReplicatedStorage.Packages.Shard)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local AdminService = Shard.new("AdminService")

--- The least time between one admin's requests, in seconds. Same number and same reason as
--- `WeatherService`'s: it stops a stuck button, not an admin in a hurry.
local COOLDOWN = 0.25

--[[ The most of anything one press can hand out. Pulls, lives and boosts are all "how many", and
	all three end up as a profile `Increment` — so the bound exists to stop a fat finger on the
	panel's slider writing a number nobody meant into a save file that keeps it forever. ]]
local MAX_COUNT = 25

--[[ The most money one press can move, either way. It is deliberately far past anything the game's
	own ladder pays — the point of the number is that a slipped decimal point on the panel's amount
	box cannot write a total that overflows a label or breaks a price comparison, not that it is a
	balance anybody should have. ]]
local MAX_CASH = 1e12

--[[ Where the panel's reference cars stand, and how they are posed. See `Actions.reference`.

	`Ahead` and `Yaw` are the two that matter and they are a pair: far enough back that a whole car
	fits on screen at a walking camera, and turned far enough off head-on that the nose AND one flank
	are both in the same view. Every repaint fault this pack has produced has been a nose part or a
	door band (`CarPaint`'s list of renames), so a broadside pose would hide the half worth looking
	at and a head-on one would hide the other half. ]]
local REFERENCE = {
	--- Studs in front of the admin the row is centred.
	Ahead = 26,
	--- Studs of clear air between two cars of a pair.
	Gap = 3,
	--- Degrees the cars are turned off nose-on to the admin.
	Yaw = 35,
	--- The ground is looked for from this far above the admin's own height, this far down.
	Rise = 10,
	Drop = 80,
	--- The Workspace folder they hang in, one sub-folder per admin so a second press replaces a
	--- first rather than parking a car inside a car.
	Folder = "AdminReferenceCars",
	--- What one built car is called. NOT `DisplayCar` — that name means "the car on this podium" to
	--- `GarageService`, and these stand in the open air with no bay behind them.
	CarName = "ReferenceCar",
	--- Written over the stock car's number plate, so the pair can be told apart from any angle
	--- without counting which side is which. See `Actions.reference`.
	StockPlate = "STOCK",
}

AdminService:withRemoteEvents({
	{
		--[[ client -> server (action, target, ...): the panel asking for something. server -> the
			one client that asked (ok, message): what happened, as a sentence to print.

			`target` is a UserId, or the string "all" for everybody in the server. It is resolved to
			live `Player` objects here and never trusted as a name: a name is not an identity, and
			two players whose names differ by a homoglyph is a real thing that happens. ]]
		[Admins.Event] = function(player: Player, action: unknown, target: unknown, ...: unknown)
			AdminService:_onAction(player, action, target, ...)
		end,
	},
})

-- === The door ===============================================================

--- Say what happened, to the one panel that asked.
function AdminService._reply(self, player: Player, ok: boolean, message: string)
	self:getRemoteEvent(Admins.Event):Fire(player, ok, message)
end

--[[ Who this action lands on. An empty list is a real answer — the target left, or was never here —
	and every action below treats it as a refusal with a sentence rather than a silent no-op. ]]
function AdminService._targets(self, target: unknown): { Player }
	if target == "all" then
		return Players:GetPlayers()
	end
	if type(target) ~= "number" then
		return {}
	end
	local player = Players:GetPlayerByUserId(target)
	return if player then { player } else {}
end

--- A "how many" argument off the wire, bounded. Anything unusable is one, which is the answer that
--- cannot surprise anybody.
local function count(value: unknown): number
	if type(value) ~= "number" or value ~= value then
		return 1
	end
	return math.clamp(math.floor(value), 1, MAX_COUNT)
end

--[[ A money argument off the wire, bounded and whole. Negative is allowed, because taking money away
	is half of what the tab is for.

	IT FALLS BACK TO ZERO AND NOT TO ONE, which is the opposite of `count` above and for the opposite
	reason: a "how many" of zero is a press that did nothing and would read as a bug, while a cash
	amount of zero is refused by name a line later. Nothing here silently grants a dollar. ]]
local function cash(value: unknown): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), -MAX_CASH, MAX_CASH)
end

--[[ Actions that FIND THEIR OWN TARGET, and are therefore dispatched without one.

	`cashOffline` names a player who is not in this server, so there is no `Player` to resolve and an
	empty list is the normal case rather than a refusal — it takes a username or a user id as an
	ordinary argument instead.

	`reference` and `clearReference` are the other kind: they land on THE ADMIN WHO ASKED and can
	land nowhere else. What they park is a thing to look at from where you are standing, so "give it
	to everyone" would be six cars in six lobbies that nobody asked to see.

	`wipe` is that kind too, and for a far harder reason: it deletes a save. There is no version of
	it that should ever be pointed at somebody else, so there is no argument to point it with. ]]
local Untargeted: { [string]: boolean } =
	{ cashOffline = true, reference = true, clearReference = true, wipe = true }

--[[ The panel, asking. Every exit answers, because the panel prints whatever comes back and a
	silence there is indistinguishable from a broken remote — except for the non-admin exit, which
	is silent on purpose and logged instead. Same bargain `WeatherService._onAdmin` makes. ]]
function AdminService._onAction(self, player: Player, action: unknown, target: unknown, ...: unknown)
	if not Admins.isAdmin(player) then
		self.log:warn(string.format(
			"%s (%d) asked for admin '%s' and is not an admin.",
			player.Name,
			player.UserId,
			tostring(action)
		))
		return
	end

	local now = os.clock()
	if now < (self._at[player.UserId] or 0) then
		self:_reply(player, false, "Too fast — try that again.")
		return
	end
	self._at[player.UserId] = now + COOLDOWN

	local handler = self._actions[action]
	if not handler then
		self:_reply(player, false, string.format("Unknown action '%s'.", tostring(action)))
		return
	end

	--[[ The handler is looked up BEFORE the target is resolved, because one action resolves its own
		— see `Untargeted`. Everything else still refuses an empty list here rather than in four
		places, and gets a list it can loop over without checking. ]]
	local targets = {}
	if not Untargeted[action] then
		targets = self:_targets(target)
		if #targets == 0 then
			self:_reply(player, false, "Nobody to give that to — the target has left.")
			return
		end
	end

	local ok, message = handler(self, player, targets, ...)
	self:_reply(player, ok, message)
end

-- === What it can do =========================================================

--[[ Each of these takes the admin who asked and the list it lands on, and answers `(ok, message)`.
	They are a table rather than an if-chain so that adding one is adding an entry — the panel's own
	tabs are built the same way, and for the same reason.

	NONE OF THEM DECIDE ANYTHING. The car goes through `GarageService.awardCar`, which is the same
	call the getaway truck makes; the pull through `RandomCarService.grantPull`, which is the same
	call the Robux receipt makes. That is the whole design: an admin grant that took a shortcut
	would be testing a path no player ever walks. ]]
local Actions = {}

--[[ Put a car on somebody's lot.

	THE TIER IS DERIVED HERE AND NOT SENT. `awardCar` refuses a tier and body that do not agree
	(`_readCar`), and the panel has no business knowing the pairing — deriving it from
	`GarageConfig.TierOfBody` means a body this build does not have is refused with a sentence
	rather than silently mismatched.

	A nil paint is ROLLED rather than defaulted to stock, so "give me a Camaro" ten times gives ten
	different Camaros — which is what a full lot needs to be tested against, since colour is half of
	what makes a car a duplicate (`GarageConfig.Banking`). ]]
function Actions.car(self, admin: Player, targets: { Player }, body: unknown, paint: unknown, mutation: unknown)
	local Garage = Shard.get("GarageService")
	if not Garage then
		return false, "GarageService is not running."
	end
	if type(body) ~= "string" then
		return false, "No car named."
	end

	local tier = GarageConfig.TierOfBody[body]
	if not tier then
		return false, string.format("No car named '%s' on any roster.", body)
	end

	local realMutation = WeatherConfig.sanitize(mutation)
	local lines = {}
	for _, target in targets do
		local colour = if type(paint) == "number"
			then PaintConfig.sanitize(body, paint)
			else PaintConfig.roll(self._random, body)
		local outcome, cash = Garage:awardCar(target, tier, body, colour, realMutation)

		self.log:info(string.format(
			"%s gave %s a %s %s%s — %s.",
			admin.Name,
			target.Name,
			PaintConfig.nameOf(colour),
			body,
			if realMutation then " (" .. realMutation .. ")" else "",
			outcome
		))
		--[[ The colour is named PER LINE rather than once in front of them all, because a nil paint
			rolls a fresh one for every target — so "Red Camaro: two players" would be a sentence
			about a thing that did not happen. ]]
		table.insert(lines, string.format(
			"%s got a %s%s %s — %s%s",
			target.Name,
			if realMutation then WeatherConfig.nameOf(realMutation) .. " " else "",
			PaintConfig.nameOf(colour),
			body,
			outcome,
			if outcome == "sold" then " for " .. GarageConfig.formatCash(cash) else ""
		))
	end

	return true, table.concat(lines, "  ·  ")
end

--[[ Every car on one world's ladder, in one press.

	It exists because the screens that need testing are the ones a full collection fills — the
	garage lot swapping its worst bay, the inventory grid, the collection value — and reaching those
	by pressing `car` eight times is eight round trips through a rate limit built to stop exactly
	that. The ladder is short (eight cars at most today) and comes from `WorldConfig`, so this is
	bounded by the roster rather than by anything off the wire.

	It goes through `Actions.car` rather than calling `awardCar` itself, which is what keeps the
	tier derivation, the paint roll and the mutation sanitising in one place. ]]
function Actions.world(self, admin: Player, targets: { Player }, world: unknown, paint: unknown, mutation: unknown)
	local index = WorldConfig.resolve(world)
	local cars = WorldConfig.carsFor(index)
	if #cars == 0 then
		return false, string.format("%s has no cars on its ladder.", WorldConfig.displayName(index))
	end

	for _, body in cars do
		local ok, message = Actions.car(self, admin, targets, body, paint, mutation)
		if not ok then
			return false, message
		end
	end

	return true, string.format(
		"Gave all %d %s cars to %d player(s).",
		#cars,
		WorldConfig.displayName(index),
		#targets
	)
end

--- Take one admin's reference cars away. False if there were none, which is a normal answer rather
--- than a fault: nothing else in the game parks one, so "none" is the usual state.
local function clearReferences(userId: number): boolean
	local root = workspace:FindFirstChild(REFERENCE.Folder)
	local holder = root and root:FindFirstChild(tostring(userId))
	if not holder then
		return false
	end
	holder:Destroy()
	return true
end

--[[ The folder one admin's reference cars hang in, emptied of whatever was in it.

	ONE SUB-FOLDER PER ADMIN, keyed by user id, so two admins looking at two cars do not clear each
	other's, and so a second press replaces a first rather than parking a car inside a car. ]]
local function referenceHolder(userId: number): Folder
	local root = workspace:FindFirstChild(REFERENCE.Folder)
	if not root then
		local made = Instance.new("Folder")
		made.Name = REFERENCE.Folder
		made.Parent = workspace
		root = made
	end

	clearReferences(userId)

	local holder = Instance.new("Folder")
	holder.Name = tostring(userId)
	holder.Parent = root
	return holder
end

--[[ The ground under a spot, for standing a car on. Falls back to the height handed in, which is the
	admin's own feet, for a spot with nothing under it: a row that runs off the edge of a forecourt
	stays level with the admin rather than dropping one car into the void.

	Nothing already parked here can block the ray, because `CarDisplay.build` leaves every part
	`CanQuery` false. The character is excluded anyway, since an admin standing at the edge of a deck
	can have a limb over the near car's ray. ]]
local function groundUnder(spot: Vector3, fallbackY: number, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(
		spot + Vector3.new(0, REFERENCE.Rise, 0),
		Vector3.new(0, -REFERENCE.Drop, 0),
		params
	)
	return if hit then hit.Position.Y else fallbackY
end

--[[ Stand the car nobody can otherwise see in front of the admin who asked: a STOCK, unpainted copy
	of a body, and, if a colour is named, the painted copy beside it.

	IT IS THE ONLY ACTION ON THIS PANEL THAT GRANTS NOTHING. No profile is written and nothing is
	handed to the solver. What gets parked is a `CarDisplay` clone, the same anchored, collision-free,
	query-blind dress the dealership podiums stand, in the open air with no bay under it.

	WHY THE STOCK CAR IS WORTH A BUTTON. Painting in this game is DESTRUCTIVE on the panel it touches
	(`CarPaint` works by clearing the MeshPart texture the artist's livery actually lives in), so
	every repaint fault is the same question: which of these parts should have kept its texture, and
	which of them lost one it should have kept. That is not a question one car can answer. It needs
	the two side by side, and the stock one is otherwise unreachable in a running game. `CarSystem` is
	not streamed to clients, every car a player ever sees has already been through `CarPaint.apply`,
	and waiting for the palette to roll `Stock` is a one-in-N wait per body.

	THE STOCK CAR IS MARKED ON ITS NUMBER PLATE rather than by position alone, because position is
	only readable from where you were standing when you pressed the button and a car is a thing you
	walk around. See the plate write below for why overwriting a correct plate is the point.

	A PAIR IS BUILT ONLY WHEN THE COLOUR IS NOT STOCK. Asked for stock against stock, which is what a
	`Stock` pick, an unusable index and an unlucky `random` roll all come to, it parks the one car and
	names the colour it landed on, rather than two identical cars a stud apart that read as a
	rendering fault in themselves.

	It goes through `CarDisplay.build` and not through a hand-rolled clone, for the reason that
	module's header gives at length: a dress cloned with its welds left in arrives welded to the
	roster master across the map, and writing a CFrame on it drags the pristine template out of
	`CarSystem` to stand inside the copy. An audit tool that puts a hole in the roster it is auditing
	would be worse than no tool at all. ]]
function Actions.reference(self, admin: Player, _targets: { Player }, body: unknown, paint: unknown)
	if type(body) ~= "string" or not GarageConfig.TierOfBody[body] then
		return false, string.format("No car named '%s' on any roster.", tostring(body))
	end

	local character = admin.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root and root:IsA("BasePart")) then
		return false, "You have no character to stand it in front of."
	end

	--[[ Stock first, always, so the left-hand car in the row is the reference on every press and the
		eye has one fixed thing to come back to. A colour equal to `Stock` gives it nothing to be
		compared against, so it does not earn a second car. ]]
	local wanted = { PaintConfig.StockIndex }
	local colour = if type(paint) == "number"
		then PaintConfig.sanitize(body, paint)
		elseif paint == "random" then PaintConfig.roll(self._random, body)
		else nil
	if colour and colour ~= PaintConfig.StockIndex then
		table.insert(wanted, colour)
	end

	--[[ Built with the SHOWROOM's own options, deliberately: same roster folder, same stripped
		hitbox, same shadows off. A reference car lit differently from the podium car it is being held
		against would answer a question nobody asked. ]]
	local display = GarageConfig.Display
	local built = {}
	for _, index in wanted do
		local clone, offsets, extents = CarDisplay.build(body, index, {
			rosterFolder = display.RosterFolderName,
			bodyFolder = display.BodyFolderName,
			hitBoxName = display.HitBoxName,
			name = REFERENCE.CarName,
			castShadow = display.CastShadow,
		})
		if not clone then
			--- Nothing is parented until the placing loop below, so an exit here leaves no half-built
			--- row on screen and no orphan in Workspace.
			for _, entry in built do
				entry.clone:Destroy()
			end
			return false, string.format("%s.%s is not in this place.", display.RosterFolderName, body)
		end
		--[[ THE STOCK CAR SAYS SO ON ITS PLATE, over the one `CarDisplay.build` just wrote.

			That plate is not wrong — `CarPlate.apply` hashes body-and-colour, so it is the plate a
			player's own Stock Camaro really would wear — and being right is the problem: two cars of
			the same body wearing two ordinary plates are two ordinary cars, and which of them is the
			reference is a thing you then have to remember rather than read. This is the one mark on
			the car that no real one carries. The painted car keeps its real plate, so the pair still
			shows what a genuine plate looks like beside it. ]]
		if index == PaintConfig.StockIndex then
			CarPlate.write(clone, REFERENCE.StockPlate)
		end

		table.insert(built, { clone = clone, offsets = offsets, extents = extents, paint = index })
	end

	--- The admin's own frame, flattened. A seated admin's root carries the car's orientation, which is
	--- still the direction they are looking and so is still the right answer.
	local origin = root.Position
	local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local look = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local right = look:Cross(Vector3.yAxis)
	local centre = origin + look * REFERENCE.Ahead

	--- Their feet, as the fallback floor. The character box is measured in the pivot frame, and for an
	--- upright character that frame is upright, so Y is its height.
	local boxCF, boxSize = character:GetBoundingBox()
	local feetY = boxCF.Position.Y - boxSize.Y / 2

	--[[ How wide one car reads ACROSS the admin's view once it is turned, which is what decides the
		spacing: a car at 35 degrees needs most of its own length of room, not its width. It is the
		rotated box, width and length each projected onto the view's right axis. ]]
	local radians = math.rad(REFERENCE.Yaw)
	local acrossCos, acrossSin = math.abs(math.cos(radians)), math.abs(math.sin(radians))
	local widths, total = {}, REFERENCE.Gap * (#built - 1)
	for index, entry in built do
		local across = (entry.extents.maxX - entry.extents.minX) * acrossCos
			+ (entry.extents.maxZ - entry.extents.minZ) * acrossSin
		widths[index] = across
		total += across
	end

	local holder = referenceHolder(admin.UserId)
	local ignore = { character, holder.Parent :: Instance }

	--- Left to right across the view, from the far edge of the row inward.
	local cursor = -total / 2
	local names = {}
	for index, entry in built do
		local spot = centre + right * (cursor + widths[index] / 2)
		cursor += widths[index] + REFERENCE.Gap

		local groundY = groundUnder(spot, feetY, ignore)
		local facing = CFrame.lookAt(
			Vector3.new(spot.X, groundY, spot.Z),
			Vector3.new(origin.X, groundY, origin.Z)
		) * CFrame.Angles(0, radians, 0)

		-- Placed while still unparented, so no car is ever on screen at the roster's own position.
		CarDisplay.place(entry.offsets, CarDisplay.standOn(entry.extents, spot, groundY, facing, display.Lift))
		entry.clone.Parent = holder
		table.insert(names, PaintConfig.nameOf(entry.paint))
	end

	self.log:info(string.format(
		"%s parked a reference %s (%s) in front of themselves.",
		admin.Name,
		body,
		table.concat(names, ", ")
	))

	--- Two cars are worth saying which way round they stand; one is not, and "Stock, left to right"
	--- reads as a sentence with something missing from it.
	if #built == 1 then
		return true, string.format("%s ahead of you in %s. Nothing was granted; Clear takes it away.", body, names[1])
	end
	return true, string.format(
		"%s ahead of you: %s on the left, %s on the right. Nothing was granted; Clear takes them away.",
		body,
		names[1],
		names[2]
	)
end

--- Take the reference cars away again. Nothing else clears them, so a press that finds none says so
--- rather than reporting a success that removed nothing.
function Actions.clearReference(self, admin: Player, _targets: { Player })
	if not clearReferences(admin.UserId) then
		return false, "Nothing of yours is parked out here."
	end
	self.log:info(string.format("%s cleared their reference cars.", admin.Name))
	return true, "Cleared."
end

--[[ Money, onto (or off) a balance in this server.

	IT GOES THROUGH `GarageService.addCash`, which is the one thing in the game that writes `Cash`.
	That matters more here than for the grants above, because cash is the number three different
	screens are reading: the HUD, the forecourt billboard and the upgrade kiosks all repaint off that
	one call. A shortcut straight into the profile would move the save file and leave every one of
	them showing the old number until something else happened to move it.

	`set` is written as the DIFFERENCE rather than as a write, for exactly that reason — the one
	writer stays the one writer, and "set them to $500 so I can watch a $600 kiosk stay dark" is a
	thing the tab can do without a second code path.

	NO ANALYTICS EVENT. `AnalyticsService.Resource` is how the dashboard balances the economy's
	sources against its sinks, and an admin inventing money is neither — logging it would put a spike
	in the source column that no player behaviour explains. The audit line below is the record. ]]
function Actions.cash(self, admin: Player, targets: { Player }, amount: unknown, mode: unknown)
	local Garage = Shard.get("GarageService")
	if not Garage then
		return false, "GarageService is not running."
	end

	local money = cash(amount)
	local setTo = mode == "set"
	if money == 0 and not setTo then
		return false, "That is nothing — pick an amount."
	end

	local lines = {}
	for _, target in targets do
		local before = Garage:getCash(target)
		local delta = if setTo then math.max(money, 0) - before else money
		local balance = Garage:addCash(target, delta)

		self.log:info(string.format(
			"%s %s %s %s — %s is now %s.",
			admin.Name,
			if setTo then "set" else (if delta >= 0 then "gave" else "took from"),
			target.Name,
			GarageConfig.formatCash(math.abs(if setTo then balance else delta)),
			target.Name,
			GarageConfig.formatCash(balance)
		))
		--[[ The MOVE is named as well as the balance, because `formatCash` abbreviates above $100K —
			so a $5,000 grant onto a $1.04M balance reads as "$1.0M -> $1.0M" and looks like a button
			that did nothing. The delta is exact at the amounts where the balance is not. ]]
		table.insert(lines, string.format(
			"%s: %s%s -> %s",
			target.Name,
			if balance >= before then "+" else "-",
			GarageConfig.formatCash(math.abs(balance - before)),
			GarageConfig.formatCash(balance)
		))
	end

	return true, table.concat(lines, "  ·  ")
end

--[[ Money for somebody who is not in this server.

	THE PANEL CANNOT NAME THEM AS A `Player`, so this is the one action that takes a username or a
	user id as an argument and resolves it itself (see `Untargeted`). A name is turned into an id
	immediately and never used again: `GetUserIdFromNameAsync` is the only thing that knows which
	account a string of characters belongs to, and the id is what a save file is keyed by.

	IT DOES NOT WRITE THE DATASTORE. Their save file may be open on another server right now, and a
	raw write into a key under a live session lock is a write that server's next autosave silently
	overwrites. What it posts instead is a PROFILESTORE MESSAGE — a queue that lives alongside the
	data and is drained by whichever session opens next, so the grant lands exactly once whether they
	are offline, joining, or already playing somewhere else. `GarageService`'s "Cash by post" block is
	the far end.

	Somebody already in THIS server is handed the money directly rather than posted it, because the
	direct path shows up on their HUD in the same frame and this one would not.

	IN STUDIO IT POSTS TO THE MOCK STORE. `Settings.DEBUG_MOCK` swaps the whole store, and the mock
	is wiped between playtests — so a post from a Studio playtest to a player who is not in it is a
	message nothing will ever read. The panel says so; this is where the reason lives. ]]
function Actions.cashOffline(self, admin: Player, _targets: { Player }, who: unknown, amount: unknown)
	if type(who) ~= "string" then
		return false, "Type a username or a user id first."
	end
	local name = string.match(who, "^%s*(.-)%s*$")
	if name == "" then
		return false, "Type a username or a user id first."
	end

	local money = cash(amount)
	if money == 0 then
		return false, "That is nothing — pick an amount."
	end

	local userId = tonumber(name)
	if userId then
		userId = math.floor(userId)
		if userId <= 0 then
			return false, string.format("'%s' is not a user id.", name)
		end
	else
		local ok, resolved = pcall(function()
			return Players:GetUserIdFromNameAsync(name)
		end)
		if not ok or type(resolved) ~= "number" then
			return false, string.format("No Roblox account named '%s'.", name)
		end
		userId = resolved
	end

	local here = Players:GetPlayerByUserId(userId)
	if here then
		local ok, message = Actions.cash(self, admin, { here }, money, "add")
		return ok, string.format("%s is in this server — gave it to them directly.  %s", here.Name, tostring(message))
	end

	local store = Data:GetProfileStore()
	local key = Data:GetKeyFromUserId(userId)
	if not (store and key) then
		return false, "The profile store is not up yet."
	end

	local posted = store:MessageAsync(key, { "Cash", money, admin.Name })
	if not posted then
		return false, string.format("Could not post to %d — the datastore refused it. Try again.", userId)
	end

	self.log:info(string.format(
		"%s posted %s to user %d (key %s).",
		admin.Name,
		GarageConfig.formatCash(math.abs(money)),
		userId,
		key
	))
	return true, string.format(
		"Posted %s to user %d. It lands the moment they next join, or within a minute if they are playing elsewhere.",
		GarageConfig.formatCash(math.abs(money)),
		userId
	)
end

--[[ Give somebody a game pass, exactly as a GIFT receipt grants one.

	IT IS THE ONLY WAY TO TEST A PASS BEFORE IT IS SYNCED, and that is most of why it exists. A pass
	seam cannot be exercised by buying the pass in Studio — `PromptGamePassPurchase` does not draw in
	a playtest at all (a known Studio gap this project has hit before) and a pass whose id is still 0
	cannot be bought anywhere. This writes the same profile entry `GiftService` writes, so
	`PassService.owns` answers true through the same union every seam already reads, and Auto Collect
	starts sweeping and 2x Car HP starts doubling with nothing else changed.

	IT GRANTS THE GIFT HALF, NOT THE ROBLOX HALF, and the difference is worth knowing before reading
	a result off it: this cannot make `UserOwnsGamePassAsync` say true, so it is testing the seam and
	the union rather than Roblox's own answer. That is the right half to be able to fake — the other
	half is Roblox's and is not ours to be wrong about.

	IT IS NOT REVOCABLE, for the same reason a gift is not: `PassConfig.ProfileKey` has no removal
	and there is no un-gifting. Granting one to a real account in production is permanent, which is
	the one thing to be careful with on this panel — the same warning `car` carries.

	A PASS WHOSE SEAM IS NOT WRITTEN (`Live = false`) IS REFUSED rather than granted, because the
	entitlement would do nothing and the tester would be reading a result off a seam that does not
	exist. Flip `Live` in `PassConfig` first; that is the switch this is checking. ]]
function Actions.pass(self, admin: Player, targets: { Player }, key: unknown)
	local Passes = Shard.get("PassService")
	if not Passes then
		return false, "PassService is not running."
	end

	local pass = PassConfig.get(key)
	if not pass then
		local names = {}
		for _, entry in PassConfig.Passes do
			table.insert(names, entry.Key)
		end
		return false, string.format("'%s' is not a pass. Try one of: %s.", tostring(key), table.concat(names, ", "))
	end
	if not pass.Live then
		return false, string.format("%s has no seam written yet, so owning it would do nothing.", pass.Key)
	end

	local given = 0
	for _, target in targets do
		if Passes:grant(target, pass.Key) then
			given += 1
			self.log:info(string.format("%s gave %s the %s pass.", admin.Name, target.Name, pass.Key))
		end
	end
	if given == 0 then
		return false, "Nobody's profile was ready — try again in a moment."
	end
	return true, string.format("Gave %s to %d player(s). It does not wear off.", pass.Title, given)
end

--- Bank a random-car pull, exactly as the receipt does. The card repaints to OPEN and the next
--- press rolls it in front of them, which is the half of the product that is worth testing.
function Actions.pull(self, admin: Player, targets: { Player }, amount: unknown)
	local RandomCar = Shard.get("RandomCarService")
	if not RandomCar then
		return false, "RandomCarService is not running."
	end
	local many = count(amount)
	for _, target in targets do
		RandomCar:grantPull(target, many)
		self.log:info(string.format("%s gave %s %d random car pull(s).", admin.Name, target.Name, many))
	end
	return true, string.format("Gave %d pull(s) to %d player(s).", many, #targets)
end

--- Extra lives, the same way the revive product's receipt grants them.
function Actions.life(self, admin: Player, targets: { Player }, amount: unknown)
	local Revive = Shard.get("ReviveService")
	if not Revive then
		return false, "ReviveService is not running."
	end
	local many = count(amount)
	for _, target in targets do
		Revive:grantLife(target, many)
		self.log:info(string.format("%s gave %s %d extra life/lives.", admin.Name, target.Name, many))
	end
	return true, string.format("Gave %d life/lives to %d player(s).", many, #targets)
end

--- Offline-income boosts, the same way that product's receipt grants them.
function Actions.boost(self, admin: Player, targets: { Player }, amount: unknown)
	local Offline = Shard.get("OfflineService")
	if not Offline then
		return false, "OfflineService is not running."
	end
	local many = count(amount)
	for _, target in targets do
		Offline:grantBoost(target, many)
		self.log:info(string.format("%s gave %s %d offline boost(s).", admin.Name, target.Name, many))
	end
	return true, string.format("Gave %d boost(s) to %d player(s).", many, #targets)
end

--[[ A pack in somebody's slot, exactly as driving over one puts it there.

	IT IS THE ONLY GRANT ON THIS PANEL THAT DOES NOT OUTLIVE THE PRESS. A car, a pull and a life are
	written into a save file; a pack lives in `ObstacleService`'s race state and dies with the run —
	so the refusals are different in kind from every other action here. "They are not in a race" is
	the normal answer, not an error, and the panel says so rather than reporting a silent success.

	`spendNow` chooses which end of the slot is under test: off, the pack banks — and the owner's rule
	still applies to it, because this goes through the same `_onPickup` the road does, so a health
	pack under `PickupConfig.Packs.Health.AutoUseBelow` spends itself on contact and a nitro pack
	handed to a depleted bottle is sent straight back out by the target's own client; on, the payout
	lands immediately, which is the only way to watch a pack pay out on somebody whose keyboard the
	admin does not have. ]]
function Actions.pickup(self, admin: Player, targets: { Player }, name: unknown, spendNow: unknown)
	local Obstacles = Shard.get("ObstacleService")
	if not Obstacles then
		return false, "ObstacleService is not running."
	end

	local immediately = spendNow == true
	local lines = {}
	local allWell = true
	for _, target in targets do
		local ok, what = Obstacles:grantPickup(target, name, immediately)
		allWell = allWell and ok
		if ok then
			self.log:info(string.format(
				"%s gave %s a %s pack%s.",
				admin.Name,
				target.Name,
				tostring(name),
				if immediately then " and spent it for them" else ""
			))
		end
		table.insert(lines, string.format("%s %s", target.Name, what))
	end

	return allWell, table.concat(lines, "  ·  ")
end

--[[ Move the HP bar, so the pack above has something to heal.

	IT IS PART OF THE PICKUP TAB RATHER THAN A TAB OF ITS OWN, because that is the only thing it is
	for: a health pack collected at full health pays nothing, and the rule that makes the pack
	interesting only fires under half a tank. Both are unreachable without this.

	`ObstacleService.setRaceHealth` does the arithmetic and owns the refusals — including the honest
	one, that an invulnerable or freshly-spawned run will not take the damage and the bar stays where
	it is. Its reply carries the HP before and after so a press that moved nothing reads as numbers
	rather than as a lie. ]]
function Actions.health(self, admin: Player, targets: { Player }, fraction: unknown)
	local Obstacles = Shard.get("ObstacleService")
	if not Obstacles then
		return false, "ObstacleService is not running."
	end

	local lines = {}
	local allWell = true
	for _, target in targets do
		local ok, what = Obstacles:setRaceHealth(target, fraction)
		allWell = allWell and ok
		if ok then
			self.log:info(string.format("%s set %s's car health: %s", admin.Name, target.Name, what))
		end
		table.insert(lines, string.format("%s %s", target.Name, what))
	end

	return allWell, table.concat(lines, "  ·  ")
end

--[[ Worlds unlocked, without a till — and lockable again.

	IT EXISTS FOR THE OBSTACLES. A world's obstacle set is keyed by its MAP
	(`ObstacleConfig.TiersByMap`), and the only way onto a map is to own the world it is under and be
	standing in it. Reaching world 4 the way a player does means a price and 100% of world 3's road,
	which is a job of work before a single course has been looked at.

	IT IS THE ONE ADMIN ACTION THAT CAN TAKE SOMETHING AWAY, and that is the point rather than a side
	effect: a gate is only testable if it can be put back. `1` locks everything but the free world.

	`WorldService.setUnlocked` is where every guard is — a real index, a loaded profile, and a refusal
	to move somebody who is mid-race. Nothing about the purchase it is not (the cost, the previous
	road, the refund) is skipped here, because none of it is reached. ]]
function Actions.unlock(self, admin: Player, targets: { Player }, world: unknown)
	local World = Shard.get("WorldService")
	if not World then
		return false, "WorldService is not running."
	end

	local lines = {}
	local allWell = true
	for _, target in targets do
		local ok, why = World:setUnlocked(target, world)
		allWell = allWell and ok
		if ok then
			local index = WorldConfig.resolve(world)
			self.log:info(string.format(
				"%s set %s's unlocked worlds to 1-%d (%s).",
				admin.Name, target.Name, index, WorldConfig.displayName(index)))
			table.insert(lines, string.format(
				"%s owns worlds 1-%d, up to %s.", target.Name, index, WorldConfig.displayName(index)))
		else
			table.insert(lines, string.format("%s: %s.", target.Name, tostring(why)))
		end
	end

	return allWell, table.concat(lines, "  ·  ")
end

--[[ Move somebody to a world, which is the other half of testing a map: owning one changes what the
	teleport screen offers, being IN one changes the road the next run builds.

	`WorldService.setWorld` is the public function the teleport screen's own request goes through, so
	this refuses exactly what that refuses — a world they do not own ("locked") and a player who is
	already driving ("mid-race"). Unlock first; the two presses are deliberately not one, because
	"give them the world" and "put them in it" are different things to want. ]]
function Actions.visit(self, admin: Player, targets: { Player }, world: unknown)
	local World = Shard.get("WorldService")
	if not World then
		return false, "WorldService is not running."
	end

	local lines = {}
	local allWell = true
	for _, target in targets do
		local ok, why = World:setWorld(target, world)
		allWell = allWell and ok
		local index = WorldConfig.resolve(world)
		if ok then
			self.log:info(string.format(
				"%s moved %s to world %d (%s).", admin.Name, target.Name, index, WorldConfig.displayName(index)))
			table.insert(lines, string.format("%s is in %s.", target.Name, WorldConfig.displayName(index)))
		else
			table.insert(lines, string.format("%s: %s.", target.Name, tostring(why)))
		end
	end

	return allWell, table.concat(lines, "  ·  ")
end

--[[ The "and drive it" half of `Actions.bench` below: end whatever run they are on, own the world,
	stand in it, enter a race.

	A RUN ALREADY UNDER WAY IS ENDED FIRST, and that is this function's second job. Hazards are
	looked at one at a time — drive into the boom gate, decide it reads too late, pick the next thing
	and press again — and a button that answered "you are already driving, this lands on your next
	run" made the tester wreck on purpose between every pair of tests. `RaceService.abandonRun` is
	the ordinary ending with nothing banked, and it is the yielding call in this function: it does
	not come back until the player is home, because seating them in a new car while the return beat
	is still teleporting them would land that teleport in the middle of the new run.

	The bench itself is untouched by any of that. `ObstacleService` arms it against the PLAYER rather
	than the run, so the spec `Actions.bench` stored a moment ago survives the teardown and is what
	`beginRace` reads on the way back in.

	THE WORLD IS THE HALF THAT IS EASY TO FORGET. A map's obstacle set is keyed by its map name
	(`ObstacleConfig.TiersByMap`) and so is its prop ART, so a desert hazard benched on the city road
	has no model to build from and drops out of the layout entirely. The panel picks the world that
	owns the hazard and sends it; anything that is not a world index leaves them where they are,
	which is what the road packs want, since a pack is drawn identically in every world.

	UNLOCK ONLY IF THEY DO NOT ALREADY OWN IT, because unlocking is a write to their save file and
	the number is a prefix: re-granting world 2 to somebody who owns world 5 would take three worlds
	off them. `WorldService.setUnlocked` is the same call the Maps tab makes.

	Both refusals below are `WorldService`'s own, in its words, so this cannot disagree with the
	teleport screen about what is locked. ]]
local function driveBench(target: Player, world: unknown): (boolean, string?)
	local Race = Shard.get("RaceService")
	if not Race then
		return false, "RaceService is not running"
	end

	--[[ The run they are on, ended, before anything below moves them. `abandonRun` yields until they
		are home, and that wait is the reason the whole call chain from the button down is allowed to
		yield — see its own note for what happens to a player seated in a new car while the old run's
		teleport is still in flight.

		Asked again afterwards because anything can have happened across that wait: they can have
		left, respawned, or been put into a run by a second admin. A run still standing here is a
		teardown that lost a race with something else, and `enterRace` refuses one of those silently
		— so it is said out loud instead. ]]
	if Race:isRacing(target) then
		Race:abandonRun(target)
		if Race:isRacing(target) then
			return false, "their run would not end, so this lands on their next one"
		end
	end

	if type(world) == "number" and WorldConfig.Worlds[world] then
		local World = Shard.get("WorldService")
		if not World then
			return false, "WorldService is not running"
		end
		if World:highestUnlocked(target) < world then
			local ok, why = World:setUnlocked(target, world)
			if not ok then
				return false,
					string.format("%s could not be unlocked (%s)", WorldConfig.displayName(world), tostring(why))
			end
		end
		local ok, why = World:setWorld(target, world)
		if not ok then
			return false,
				string.format("they could not be moved to %s (%s)", WorldConfig.displayName(world), tostring(why))
		end
	end

	--[[ The same call the entry pad makes, so everything a real entry does happens here too: the
		transition screen, the car their SELECT CAR choice named, the storey, the freeze until the
		client's road is built. A bench that started a run some shorter way would be a hazard tested
		in a race nobody else is driving. ]]
	Race:enterRace(target)
	--[[ ...and say so if it did not take. `enterRace` refuses silently for a player with no
		character to seat and for a missing RoadService, and both are ordinary in a Studio session
		that has just started. `isRacing` counts the pending window, so it is already true by the
		time that call returns: what this catches is an entry that never committed at all, which
		would otherwise be reported as a bench somebody is driving. ]]
	if not Race:isRacing(target) then
		return false, "the entry did not take, so they are still in the lobby"
	end
	return true
end

--[[ Put somebody on the obstacle bench: one hazard, laid at a fixed distance and repeated, instead
	of the seeded ramp. `ObstacleConfig.Bench` has the design; the short version is that the shipping
	ramp is a random draw over a pool, so meeting a particular kind means driving until it turns up,
	and meeting it twice means driving a lot further than that.

	IT IS TWO PRESSES FOR THE REASON THE MAPS TAB'S ARE. "Arm" writes what their NEXT run will be
	built from and nothing else; "Drive" arms it and then puts them in a run on the map that owns
	that hazard, which means unlocking a world, standing in it and entering a race. Arming alone is
	what you want when the run is going to be started some other way: off the pad, by the tutorial,
	by the player themselves.

	NOTHING HERE DECIDES WHAT A BENCH MEANS. The spec goes through `ObstacleService.setBench`, which
	runs it past `ObstacleLayout.sanitizeBench` and answers with what it actually stored, so a kind
	this build does not have is refused by name rather than silently building an empty road.

	A RUN ALREADY UNDER WAY IS NEVER *EDITED*, and the distinction is the whole reason "Drive" ends
	the run rather than swapping the road under it. The client built its road from what it was handed
	at `RaceStart` and the server prices hits against the same thing, so changing either half mid-run
	is how a hit stops matching an obstacle. So "Drive" ends the run they are on, sends them home and
	starts a fresh one on the new bench — which is a whole new `RaceStart` and therefore a road both
	sides agree about. "Arm" still leaves a live run completely alone. ]]
function Actions.bench(self, admin: Player, targets: { Player }, spec: unknown, world: unknown, drive: unknown)
	local Obstacles = Shard.get("ObstacleService")
	if not Obstacles then
		return false, "ObstacleService is not running."
	end
	--- Only ever asked "are they racing", for the wording below. `driveBench` reaches for it again
	--- itself and answers for its own absence, so a missing service is not a refusal here.
	local Race = Shard.get("RaceService")

	local lines = {}
	local allWell = true
	for _, target in targets do
		local bench = Obstacles:setBench(target, spec)
		if not bench then
			--- Every unusable spec lands here, the panel's own "Off" button included, which sends a
			--- string on purpose. There is one outcome for "not a bench" and this is it.
			self.log:info(string.format("%s took %s off the obstacle bench.", admin.Name, target.Name))
			table.insert(lines, string.format("%s is back on the real ramp.", target.Name))
			continue
		end

		local what = bench.course or bench.kind or "?"
		if drive ~= true then
			table.insert(lines, string.format("%s: %s armed for their next run.", target.Name, what))
			continue
		end

		--- Asked BEFORE the drive, because the drive is what ends it. Only the wording changes on
		--- the answer: a press that quietly cut a run short and then said nothing about it is a
		--- press the tester has to remember the meaning of.
		local wasRacing = Race ~= nil and Race:isRacing(target)
		local ok, why = driveBench(target, world)
		allWell = allWell and ok
		if ok then
			self.log:info(string.format("%s put %s on the %s bench.", admin.Name, target.Name, what))
			table.insert(lines, string.format(
				if wasRacing then "%s's run was ended; they are driving the %s bench now."
				else "%s is driving the %s bench.",
				target.Name, what))
		else
			table.insert(lines, string.format("%s: %s armed, but %s.", target.Name, what, tostring(why)))
		end
	end

	return allWell, table.concat(lines, "  ·  ")
end

--[[ Replay the onboarding from beat one, on the save they already have.

	`TutorialService.restart` does the work and owns the refusals, including the Studio case where
	the place's bypass tick means no tutorial is running yet (it lifts the tick for the session).

	A RUN IN PROGRESS IS ENDED FIRST, the way the Obstacles tab's Drive ends one: beat one is a lobby
	beat (press DRIVE), and a card asking for it over a road that is already being driven is a card
	nobody can obey until the run happens to end. `abandonRun` yields until they are home. ]]
function Actions.tutorial(self, admin: Player, targets: { Player })
	local Tutorial = Shard.get("TutorialService")
	if not Tutorial then
		return false, "TutorialService is not running."
	end
	local Race = Shard.get("RaceService")

	local lines = {}
	local allWell = true
	for _, target in targets do
		local ended = false
		if Race and Race:isRacing(target) then
			Race:abandonRun(target)
			if Race:isRacing(target) then
				allWell = false
				table.insert(lines, string.format("%s: their run would not end, so the tutorial was left alone.", target.Name))
				continue
			end
			ended = true
		end

		local ok, what = Tutorial:restart(target)
		allWell = allWell and ok
		if not ok then
			table.insert(lines, string.format("%s: %s.", target.Name, what))
			continue
		end
		self.log:info(string.format("%s restarted %s's tutorial.", admin.Name, target.Name))
		table.insert(lines, string.format(
			if ended then "%s's run was ended; they are %s." else "%s is %s.",
			target.Name,
			what
		))
	end

	return allWell, table.concat(lines, "  ·  ")
end

--- Seconds between the press and the rejoin, so the panel has the reply on screen before the
--- teleport takes the screen away.
local REJOIN_DELAY = 2
--- Seconds a started teleport gets to actually take them before they are kicked instead. Covers a
--- teleport that fails after it was accepted, which `TeleportAsync` does not report to its caller.
local REJOIN_TIMEOUT = 20
local WIPED_KICK = "Your save was wiped. Rejoin to start again as a new player."

--[[ Send somebody back into this game as a new session: a teleport to this place, and a kick saying
	to rejoin if the teleport cannot happen (always, in Studio) or has not happened in time.

	A TELEPORT RATHER THAN A KICK because a wipe is only done when the save has been reloaded, and a
	teleport does that without asking the player to find the game again. It can land them on this
	same server; that is fine, because `Data` already waits for the old session to end before it
	opens the new one. ]]
local function rejoin(player: Player)
	if player.Parent ~= Players then
		return
	end
	local ok = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player })
	end)
	if not ok then
		if player.Parent == Players then
			player:Kick(WIPED_KICK)
		end
		return
	end
	task.delay(REJOIN_TIMEOUT, function()
		if player.Parent == Players then
			player:Kick(WIPED_KICK)
		end
	end)
end

--[[ Wipe the pressing admin's own save and send them back in as a brand-new player.

	IT CANNOT BE AIMED AT ANYBODY ELSE (see `Untargeted`), and it cannot be undone. Everything in the
	profile goes: cars, cash, worlds, likes, banked lives and pulls, gifted passes, the tutorial
	record. Game passes BOUGHT on Roblox are not in the save and survive, as does anything outside
	the profile such as leaderboard rows.

	IT MARKS RATHER THAN WIPES (`Data.MarkForWipe` says why), then rejoins them after a beat. The
	save is emptied when the next session opens it, so the rejoin is not optional: until it happens
	the old save is still the live one.

	REFUSED ON STUDIO'S MOCK STORE, where it would do nothing but kick the only player out of the
	playtest: the mock starts empty on every playtest, so a new playtest already IS a wiped save.
	Replay is the button for testing the tutorial in Studio. ]]
function Actions.wipe(self, admin: Player, _targets: { Player })
	if Data:IsMock() then
		return false,
			"Studio is on the mock profile store, which starts empty every playtest, so a fresh playtest already is a wiped save. Use Replay tutorial to rerun it in this one."
	end
	if not Data:MarkForWipe(admin) then
		return false, "Your profile is not loaded, so there is nothing to wipe yet."
	end

	self.log:warn(string.format(
		"%s (%d) wiped their own save. It empties to the template when their next session opens.",
		admin.Name,
		admin.UserId
	))
	task.delay(REJOIN_DELAY, rejoin, admin)
	return true, "Save marked for wiping. Sending you back in as a new player..."
end

-- === The showroom ===========================================================
--[[ THE SHOWROOM TAB (2026-09-28): buyers, the welcome-back screen and car condition, which are the
	three parts of the dealership rework that cannot otherwise be looked at without waiting. A buyer is
	a seventy-five second wait and a Great one a one-in-ten roll; the welcome-back screen needs five
	real minutes logged out; condition only moves when a run banks a damaged car.

	Every one of these is a call to a public function of the service that owns the thing, per this
	file's rule, and those functions answer `(ok, sentence)` themselves. What this section adds is
	only the per-target loop and the audit line. ]]

--- Run one `(ok, sentence)` call per target and join the answers, the shape every tab's reply takes.
local function each(self, admin: Player, targets: { Player }, verb: string, call: (Player) -> (boolean, string))
	local lines = {}
	local allWell = true
	for _, target in targets do
		local ok, what = call(target)
		allWell = allWell and ok
		if ok then
			self.log:info(string.format("%s %s for %s: %s.", admin.Name, verb, target.Name, what))
		end
		table.insert(lines, string.format("%s: %s.", target.Name, what))
	end
	return allWell, table.concat(lines, "  ·  ")
end

--[[ A buyer on one of their for-sale cars, now, walking in. `band` is a `BuyerConfig.Bands` key
	("Great") or anything else for a normal roll. `BuyerService.forceOffer` has what it skips (the
	arrival cap) and what it does not (one buyer per car). ]]
function Actions.buyer(self, admin: Player, targets: { Player }, band: unknown)
	local Buyers = Shard.get("BuyerService")
	if not Buyers then
		return false, "BuyerService is not running."
	end
	return each(self, admin, targets, "sent a buyer", function(target)
		return Buyers:forceOffer(target, band)
	end)
end

--[[ A seller at their kerb now (2026-10-15), replacing any already there. `band` is a
	`SellerConfig.Bands` key ("Steal") or anything else for a normal roll. A REAL seller: buying it
	costs the target real cash, the same as one that came on the clock. ]]
function Actions.seller(self, admin: Player, targets: { Player }, band: unknown)
	local Sellers = Shard.get("SellerService")
	if not Sellers then
		return false, "SellerService is not running."
	end
	return each(self, admin, targets, "sent a seller", function(target)
		return Sellers:forceVisit(target, band)
	end)
end

--- The waiting seller drives off unsold.
function Actions.clearSeller(self, admin: Player, targets: { Player })
	local Sellers = Shard.get("SellerService")
	if not Sellers then
		return false, "SellerService is not running."
	end
	return each(self, admin, targets, "sent the seller away", function(target)
		return Sellers:clearVisit(target)
	end)
end

--- Every standing offer set to run out in `seconds`, to watch a buyer give up without the full wait.
function Actions.hurryBuyers(self, admin: Player, targets: { Player }, seconds: unknown)
	local Buyers = Shard.get("BuyerService")
	if not Buyers then
		return false, "BuyerService is not running."
	end
	local wait = if type(seconds) == "number" and seconds == seconds then math.clamp(seconds, 1, 600) else 10
	return each(self, admin, targets, "hurried the buyers", function(target)
		return Buyers:hurryOffers(target, wait)
	end)
end

--- Every buyer sent away with nothing sold.
function Actions.clearBuyers(self, admin: Player, targets: { Player })
	local Buyers = Shard.get("BuyerService")
	if not Buyers then
		return false, "BuyerService is not running."
	end
	return each(self, admin, targets, "cleared the buyers", function(target)
		return Buyers:clearOffers(target)
	end)
end

--[[ The welcome-back screen, as if they had been gone `minutes`. `OfflineService.pretendAway` runs
	the join path's own check, so the tips it banks are real — a grant, like the rest of this file.
	Bounded at a day: past the two-hour cap (`CustomerConfig.Offline.CapSeconds`) and the five-minute
	buyer lifetime nothing changes, so a larger number is only a slip of the slider. ]]
function Actions.away(self, admin: Player, targets: { Player }, minutes: unknown)
	local Offline = Shard.get("OfflineService")
	if not Offline then
		return false, "OfflineService is not running."
	end
	local span = if type(minutes) == "number" and minutes == minutes then math.clamp(minutes, 1, 24 * 60) else 60
	return each(self, admin, targets, "faked an absence", function(target)
		return Offline:pretendAway(target, span * 60)
	end)
end

--[[ Condition (0..1) onto every car standing on their bays, the one field a run writes when it banks
	(`GetawayService`). Bays only, because the lot is where condition shows — in the tips, the buyers'
	offers and the WORTH line — and it is written through `GarageService.setCarData`, the same call
	the bank makes, so the value and the broadcast repaint as they would after a run. ]]
function Actions.condition(self, admin: Player, targets: { Player }, fraction: unknown)
	local Garage = Shard.get("GarageService")
	if not Garage then
		return false, "GarageService is not running."
	end
	local condition = if type(fraction) == "number" and fraction == fraction then math.clamp(fraction, 0, 1) else 1
	return each(self, admin, targets, "set car condition", function(target)
		local count = 0
		for _, bay in Garage:getBays(target) do
			local _car, id = Garage:getBayTip(target, bay.index)
			if id and Garage:setCarData(target, id, { Condition = condition }) then
				count += 1
			end
		end
		--- `getBayTip` answers empty for the workshop, so its car is added by name — a damaged car in
		--- the workshop is the one thing the REPAIR button needs to be tested at all.
		local workshop = Garage:workshopCar(target)
		if workshop and Garage:setCarData(target, workshop, { Condition = condition }) then
			count += 1
		end
		if count == 0 then
			return false, "no cars on their bays"
		end
		return true, string.format("%d car(s) on the lot now at %d%% condition", count, math.round(condition * 100))
	end)
end

--[[ The NEW BEST cutscene (`ShowcaseConfig`), on demand: `play` shows it now for the most valuable
	car they own and leaves their record alone; `forget` wipes the record so their next car of any worth
	earns it for real, which is the only way to test the save-and-compare half. `preview` shows any car
	named (`body`, `paint`, `mutation`, as the Cars tab sends them), owned or not, and writes nothing. ]]
function Actions.showcase(self, admin: Player, targets: { Player }, mode: unknown, body: unknown, paint: unknown, mutation: unknown)
	local Showcase = Shard.get("ShowcaseService")
	if not Showcase then
		return false, "ShowcaseService is not running."
	end
	if mode == "preview" then
		return each(self, admin, targets, "previewed the new-best cutscene", function(target)
			return Showcase:playCar(target, body, paint, mutation)
		end)
	end
	if mode == "forget" then
		return each(self, admin, targets, "wiped the best-car record", function(target)
			return Showcase:forgetBest(target)
		end)
	end
	return each(self, admin, targets, "played the new-best cutscene", function(target)
		return Showcase:playBest(target)
	end)
end

-- === Lifecycle ==============================================================

AdminService:withLifecycle({
	init = function(self)
		--- `UserId` -> the `os.clock()` before which that admin's next press is ignored. Keyed by id
		--- rather than by the Player so a rejoin does not strand the instance here.
		self._at = {} :: { [number]: number }
		self._actions = Actions
		--- Its own generator, for the paint roll. Nothing else in the game should be able to have
		--- its sequence moved by an admin pressing a button.
		self._random = Random.new()
	end,

	start = function(_self)
		--[[ Reference cars are the one thing this service leaves standing in the world, so they are
			the one thing it has to tidy up. An admin who parks a pair and leaves would otherwise
			leave two cars in a lobby that nobody in the server can clear, since the Clear button only
			ever reaches the presser's own folder. ]]
		Players.PlayerRemoving:Connect(function(player: Player)
			clearReferences(player.UserId)
		end)
	end,
})

return AdminService
