--[[
	CarryService  (server)
	----------------------
	THE CAR IN THE PLAYER'S HANDS. One model, put in a hand that is posed to be holding it, rebuilt
	whenever the answer to "what should this person be holding?" changes.

	It owns the WORLD SIDE of the carry and nothing else. The record (which car, stored where, and
	what happens when it is placed) is `GarageService`'s, because that service owns every read and
	write of the profile's `Garage` table and because a placement is a bay change like any other. So
	this file has no profile access, no remotes, and nothing a client can ask it for: it listens for
	three facts and it draws the consequence.

	    GarageService.CarryChanged   what they are holding is now this, or nothing
	    RaceService.RaceEntered      they are driving: take it off them
	    RaceService.RaceLeft         that run is over: give it back

	=== WHY IT COMES OFF FOR A RACE ============================================================

	A run is the one stretch of the game where the character is not a person walking around: they are
	seated in a car that is being frozen, teleported, hidden and, on a wreck, thrown out of it as a
	rebuilt rig (`StealController`). Every one of those paths knows exactly which parts a character
	has, and two of them write properties across all of them. A car welded to the rider would ride the
	whole of that, be hidden by the same pass that hides the rider, and come back with whatever
	transparency the restore decided to give it.

	It costs nothing to take off, and that is the point: the model is built from a car key, so
	rebuilding it is the same call as building it, and the record it is built from never moved.

	=== WHAT MAKES IT CHEAP ====================================================================

	`_refresh` is the only entry point and it is idempotent: it works out what SHOULD be held, compares
	it to what IS held, and does nothing at all when they agree. Every event above calls it, including
	the ones that usually change nothing (a respawn, a plot claim). That is what makes the set of
	events safe to add to: a new one cannot double-build, and a missing one shows up as a car that
	arrives late rather than as a car that is wrong.

	=== IT IS HELD AS A TOOL ===================================================================

	`_equip` puts the car's hub in a `Tool` as its `Handle` and equips it, which buys the POSE: Roblox's
	own `Animate` script plays its tool animation for as long as anything is equipped, so the arm comes
	up and holds the car out through idle, walking and jumping, on any rig, with nothing of ours to
	load or keep alive. Before this the car was welded beside the shoulder and the character's arms
	hung by their sides, which read as a car floating next to somebody.

	`CarryConfig.Hold.Tool` is the switch and the argument, including what a tool brings with it that
	has to be answered for: the hotbar slot, the unequip keys, the click, and what a death does.

	=== THE MODEL ==============================================================================

	`CarDisplay.build` is the same call the podiums and the plaza stands use, so the thing in your
	hands is the car you are about to park, in its own colour, with its own plate. Three things are
	done to it that a podium does not do, and all three are in `_hold`:

	  • IT IS SCALED BY HAND, part by part, rather than with `Model:ScaleTo`. A display car has no
	    PrimaryPart until this file gives it one, and `ScaleTo` on a model without one scales about a
	    bounding-box pivot that is not the frame the offsets were measured in. Scaling the offsets is
	    exact and needs nothing to be parented first.
	  • IT IS UNANCHORED AND WELDED, in that order, with the parts already standing where they belong.
	    A `WeldConstraint` records the offset it is given, so placing first and welding second is what
	    makes the car arrive in the hands rather than snapping into them. Every panel is welded to the
	    hub and only the hub is welded, or gripped, to the character.
	  • EVERY PART IS `Massless`. They are joined to the character's own assembly, and a player whose
	    jump height depends on which car they banked is a bug nobody would think to look for.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local CarryConfig = require(ReplicatedStorage.shared.Configs.CarryConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local CarDisplay = require(ReplicatedStorage.shared.Modules.CarDisplay)
local CarMutation = require(ReplicatedStorage.shared.Modules.CarMutation)
--- The held car's sign (`GarageConfig.InfoTag`): a pure module.
local CarInfoTag = require(ReplicatedStorage.shared.Modules.CarInfoTag)

--[[ `GarageService` is a real dependency: without it there is no record to draw and nothing to
	listen to. `RaceService` deliberately is not one, and is reached with `Shard.get` at start: a
	server with the race switched off still hands out cars (an admin grant, a plaza stand), and
	declaring it would make this service refuse to start over a feature that is allowed to be off. ]]
local CarryService = Shard.new("CarryService"):withDependencies({ "GarageService" })

--- How long to wait for a freshly spawned character to have the part the car hangs off. Generous,
--- because nothing is blocked on it: it runs in its own thread and the worst case is a car that
--- appears a moment late.
local CHARACTER_WAIT = 10

--[[ What one player is holding right now: the key it was built from, and the thing itself, which is
	the `Tool` on the tool path and the car model on the weld path (`CarryConfig.Hold.Tool`). The key
	is what makes `_refresh` idempotent, since two different cars are two different models and the
	same car twice is no work at all.

	`clickable` IS PART OF THE IDENTITY AND NOT A PROPERTY OF THE MODEL, which is why it is compared
	alongside the key rather than written onto whatever is already held. It says which of the two
	reasons a hand is full (see `_wanted`), and the two want different tools: a lobby toy is dropped
	with a click and a banked car is not. Holding the same car for a different reason is therefore a
	rebuild, which costs one clone and cannot leave a stale verb on a tool. ]]
type Held = { key: string, model: Instance, clickable: boolean }

-- === What should be held ====================================================

--[[ The car key this player OUGHT to be holding and whether it can be clicked, or nil for empty
	hands.

	TWO SOURCES, AND THEY ARE DIFFERENT PROMISES. Both put the same model in the same hand, and that
	is the whole reason this service was worth reusing rather than copying, but what a click means
	is not the same for the two of them:

	    LobbyCarService   a car picked off the Cars Inventory to DRIVE. Clicking drops it in the
	                      street in front of you (`LobbyCarConfig.Toy`). In memory, so a rejoin
	                      empties the hands.
	    GarageService     a car you banked, waiting for a BAY on your own lot. The click does
	                      nothing: it is placed by the podium's own prompt, which is the only thing
	                      that knows which podium you are standing at. In the profile, so a rejoin
	                      still has it.

	THE LOBBY ONE WINS A TIE, and a tie is real: a player who banked a car and then opened the Cars
	Inventory before parking it has asked for two things. The newer press is the one they are
	looking at, and the banked car loses nothing by waiting, because it is already in the collection
	and its bay prompt is unaffected (`CarryConfig` note 1).

	A MISSING SERVICE READS AS "NOT THAT SOURCE" in both cases, and a missing `RaceService` reads as
	"not racing". That is the right way round for all three: this is a cosmetic model, and the
	failure of an optional half should be a car that is visible when it should not be rather than a
	car that is never visible at all. ]]
function CarryService._wanted(self, player: Player): (string?, boolean)
	local Race = Shard.get("RaceService")
	--[[ The trip home counts as racing for this purpose (`CarryConfig.Hold.AfterReturn`): nothing is
		welded onto a character the server is still freezing and teleporting. `ReturnedHome` is the
		refresh that puts the car in their hands once it has let go. ]]
	local racing = Race
		and (Race:isRacing(player) or (CarryConfig.Hold.AfterReturn and Race:isReturning(player)))

	local Lobby = Shard.get("LobbyCarService")
	local toy = if Lobby then Lobby:getToyCar(player) else nil
	if toy then
		return (if racing then nil else toy), true
	end

	local Garage = Shard.get("GarageService")
	local key = if Garage then Garage:getCarriedCar(player) else nil
	if not key or racing then
		return nil, false
	end
	return key, false
end

--[[ Make the world agree with `_wanted`. The only entry point, and safe to call at any time, from
	anything, as often as you like.

	THE `Parent` CHECK IS NOT PARANOIA. A model welded to a character is destroyed with that character,
	so a player who respawned while carrying holds a `Held` record naming a model that no longer
	exists. Comparing keys alone would decide nothing had changed and leave them empty handed for the
	rest of the session. ]]
function CarryService._refresh(self, player: Player)
	local key, clickable = self:_wanted(player)
	local held = self._held[player]

	if held and held.key == key and held.clickable == clickable and held.model.Parent == player.Character then
		return
	end

	self:_drop(player)
	if key then
		self:_hold(player, key, clickable)
	end
end

--- Take whatever is in this player's hands off them. Safe on empty hands, which is what makes every
--- caller able to treat it as "make sure there is nothing there".
function CarryService._drop(self, player: Player)
	local held = self._held[player]
	if not held then
		return
	end
	self._held[player] = nil
	if held.model then
		held.model:Destroy()
	end
end

--[[ Build the car, shrink it, and weld it to the character.

	NOTHING IN HERE YIELDS, and that is load-bearing rather than tidy: the grip frame is computed off
	the anchor part's CURRENT pose, and a yield between that and the weld would be a frame in which
	the player walked away from their own car. A character that is not ready yet is left alone, and
	the watcher in `_watch` calls back when it is. ]]
function CarryService._hold(self, player: Player, key: string, clickable: boolean)
	local hold = CarryConfig.Hold
	local character = player.Character
	local anchor = character and character:FindFirstChild(hold.PartName)
	if not (character and anchor and anchor:IsA("BasePart")) then
		return
	end

	local body, paint, mutation = GarageConfig.parseCarKey(key)
	if not body then
		return
	end

	--- The same options a podium builds with, so a carried car and a parked one are the same clone of
	--- the same dress. The name is this feature's own, because that is what `_drop` finds.
	local display = GarageConfig.Display
	local clone, offsets, extents = CarDisplay.build(body, paint, {
		rosterFolder = display.RosterFolderName,
		bodyFolder = display.BodyFolderName,
		hitBoxName = display.HitBoxName,
		name = hold.ModelName,
		castShadow = hold.CastShadow,
	})
	if not clone then
		self.log:warn(string.format("No %s.%s to carry, so %s is holding nothing.", display.RosterFolderName, body, player.Name))
		return
	end

	--[[ THE SHRINK. A part's `Size` and its offset from the car's own origin both scale, and its
		ROTATION does not: that is what keeps a wheel a wheel rather than shearing it. `CFrame.Rotation`
		is the rotation with the position taken out, so adding the scaled position back is the whole
		transformation.

		A MeshPart renders its mesh into whatever box `Size` gives it, so scaling the box scales the
		car. That is not true of the collision hull, and it does not have to be: every part of a
		display car is already `CanCollide = false` and `CanQuery = false`. ]]
	local scale = hold.Scale
	for part, offset in offsets do
		part.Size *= scale
		offsets[part] = offset.Rotation + offset.Position * scale
	end

	--[[ Where it goes: standing on the plane the frame below names, centred on its own measured BOX
		rather than on its origin.

		The two halves of the last term are the same arithmetic `CarDisplay.standOn` does for a podium
		and for the same reason. A dress fitted around a chassis can sit a stud forward of centre, and
		it is sat ON the plane rather than centred through it so that a tall body rides no higher than
		a low one.

		AS A TOOL THAT FRAME IS A STAGING POSE AND NOTHING MORE. The engine moves the handle into the
		hand the moment the tool is equipped and every panel rides its weld there, so what matters is
		only where the car sits RELATIVE to the hub: wheels on the hub's plane, centred over it, nose
		down its own -Z. Where the car ends up in the hand is `Hold.Tool.Grip`, and a yaw baked in
		here as well would be a second place to turn it from.

		On the weld path the frame IS where the car ends up, which is what `Offset` and `Yaw` are. ]]
	local asTool = hold.Tool.Enabled == true
	local centreX = (extents.minX + extents.maxX) * 0.5 * scale
	local centreZ = (extents.minZ + extents.maxZ) * 0.5 * scale
	local grip = if asTool
		then anchor.CFrame
		else anchor.CFrame * hold.Offset * CFrame.Angles(0, math.rad(hold.Yaw), 0)
	CarDisplay.place(offsets, grip * CFrame.new(-centreX, -extents.minY * scale, -centreZ))

	--[[ The one part this file adds: an invisible hub every panel is welded to, so the car is ONE
		weld away from the character rather than fifty.

		AS A TOOL IT IS THE `Handle`, which is a name the engine reads rather than one we picked: a
		`RequiresHandle` tool is equipped by welding the child called exactly that into the hand. It
		is also why the hub is parented to the TOOL rather than into the model, since the handle has
		to be the tool's own child.

		On the weld path it keeps its old name and is the model's PrimaryPart, which is what lets
		anything downstream pivot the car without having to know which panel to trust. ]]
	local hub = Instance.new("Part")
	hub.Name = if asTool then "Handle" else "Grip"
	hub.Size = Vector3.new(0.2, 0.2, 0.2)
	hub.Transparency = 1
	hub.Anchored = false
	hub.Massless = true
	hub.CanCollide = false
	hub.CanQuery = false
	hub.CanTouch = false
	hub.CFrame = grip
	hub.Parent = clone
	if not asTool then
		clone.PrimaryPart = hub
	end

	--[[ What you are carrying, over it (`GarageConfig.InfoTag`, 2026-10-14): name, rarity, value, so a
		car can be weighed up before it is parked. Off the hub, which rides into the hand with the car.
		Its market value, the number offers and the sell lot use (`Modules/CarInfoTag`). ]]
	local tagCfg = GarageConfig.InfoTag
	local Garage = Shard.get("GarageService")
	if tagCfg and tagCfg.Enabled and Garage then
		--[[ pcall'd: the tag is decoration, and the first cut of it threw here (it read an `extents.maxY`
			that `CarDisplay` does not carry) and took the whole hold down with it — no car in the hands.
			A failure now costs the tag and nothing else. The roof is measured off the scaled panels:
			each panel's top over the car's floor, which `place` put at the hub. ]]
		local ok, err = pcall(function()
			local roof = 0
			for part, offset in offsets do
				roof = math.max(roof, offset.Position.Y - extents.minY * scale + part.Size.Y / 2)
			end
			CarInfoTag.build(hub, body, paint, Garage:marketValueOf(player, key), roof + tagCfg.HeldLift, tagCfg.HeldSize)
		end)
		if not ok then
			self.log:warn(string.format("No info tag over %s's held car (%s); the car is held as normal.", player.Name, tostring(err)))
		end
	end

	--[[ Unanchor and weld, with everything already where it belongs. A `WeldConstraint` keeps the
		offset the two parts have when it is made, so this order is what makes the car appear in the
		hands instead of flying into them from the roster's corner of the map. ]]
	for part in offsets do
		part.Anchored = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hub
		weld.Part1 = part
		weld.Parent = hub
	end

	--[[ ...and on to the character, either in a hand that is posed to be holding it or welded to the
		part named above. `_equip` is the first; the two lines after it are the second, and they are
		what this feature shipped with. ]]
	local carried: Instance = clone
	if asTool then
		carried = self:_equip(player, character, clone, hub, clickable)
	else
		local hand = Instance.new("WeldConstraint")
		hand.Name = "CarryWeld"
		hand.Part0 = anchor
		hand.Part1 = hub
		hand.Parent = hub

		clone.Parent = character
	end

	--[[ The mutation, and only if `CarryConfig.Hold.Mutation` asks for it. Off by default, and that
		config's note has the reason: a mutation is a particle layer authored in studs for a full
		sized car, and the skin cannot be applied without it today. ]]
	if mutation and (hold.Mutation or hold.MutationSkin) then
		CarMutation.apply(clone, mutation, false, not hold.Mutation)
	end

	self._held[player] = { key = key, model = carried, clickable = clickable }
end

--[[ Put the built car in the player's hand, as a `Tool`.

	WHAT THE TOOL IS FOR is the pose, and `CarryConfig.Hold.Tool` has that argument in full: Roblox's
	own `Animate` script plays its tool animation while anything is equipped, so the arm comes up and
	stays up through idle, walking and jumping, on R6 and R15 alike, with no animation of ours to
	load or keep alive.

	IT CANNOT BE PUT DOWN BY ACCIDENT. `CanBeDropped` false means the drop key does nothing, and
	`Unequipped` puts it straight back on.

	WHETHER IT CAN BE CLICKED IS THE CALLER'S ANSWER (`clickable`, from `_wanted`). A lobby toy is
	dropped with a click, so the engine's own activation is what carries that verb across a mouse, a
	tap and a gamepad trigger with nothing of ours to detect; `LobbyCarController` binds it. A banked
	car is not, because the bay it goes on is chosen by the podium's own prompt, so it stays inert:
	something the player is holding, not something they operate.

	BOTH PROPERTIES MOVE TOGETHER and one of them is easy to miss. A tool that is `Enabled` but still
	`ManualActivationOnly` never activates from input at all, because manual-only means
	`Tool:Activate()` is the only way in. Setting one without the other is a click that silently
	does nothing.

	THE MODEL GOES INSIDE THE TOOL, beside the handle rather than around it. A `RequiresHandle` tool
	finds its handle as its OWN child, so the hub has to be there; the panels can be anywhere, since
	what holds them is their weld to the hub.

	Answers whatever `_drop` should destroy, which is the tool when there is one. ]]
function CarryService._equip(self, player: Player, character: Model, clone: Model, hub: BasePart, clickable: boolean): Instance
	local hold = CarryConfig.Hold

	local tool = Instance.new("Tool")
	tool.Name = hold.ModelName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ManualActivationOnly = not clickable
	tool.Enabled = clickable
	tool.ToolTip = ""
	--[[ Set before it is equipped, so the car arrives where it belongs rather than being moved there
		a frame later in front of everybody. That is also why the hand's grip point is read off its
		ATTACHMENT rather than off the `RightGrip` weld: the weld is the engine's and does not exist
		until the tool is on, while the attachment is part of the rig and carries the same CFrame.

		`CarryConfig.toolGrip` turns `Tool.Pose` and `Tool.Yaw` into the grip. Nil here is a rig with
		no such attachment, which answers with the R15 value rather than refusing to hold a car. ]]
	local gripHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local gripPoint = gripHand and gripHand:FindFirstChild("RightGripAttachment")
	tool.Grip = CarryConfig.toolGrip(gripPoint and (gripPoint :: Attachment).CFrame or nil)

	hub.Parent = tool
	clone.Parent = tool

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		--- No humanoid is no pose and no weld, and there is nothing to be gained by pretending: the
		--- tool is parented to the character so the car is at least visible, and the next `_refresh`
		--- gets another go at it.
		tool.Parent = character
		return tool
	end

	tool.Parent = player:FindFirstChildOfClass("Backpack") or character
	humanoid:EquipTool(tool)

	--[[ AND IT STAYS ON. The backpack UI is down (`Hold.Tool.HideBackpack`) so there is no slot to
		press, but the hotbar keys are not the only way here: a seat, a died-and-respawned character
		and a future feature that equips something else all unequip.

		DEFERRED, because this fires DURING the engine's own unequip and equipping inside that is
		asking the engine to undo what it is in the middle of doing. The checks on the other side of
		the hop are what make it safe: the tool has to still be this player's current carry, which is
		false the moment `_drop` ran, and the humanoid has to still be theirs. ]]
	tool.Unequipped:Connect(function()
		task.defer(function()
			local held = self._held[player]
			if not (held and held.model == tool and tool.Parent) then
				return -- dropped, replaced, or on its way out with the character
			end
			local live = player.Character
			local alive = live and live:FindFirstChildOfClass("Humanoid")
			if live == character and alive and alive.Health > 0 then
				alive:EquipTool(tool)
			end
		end)
	end)

	return tool
end

-- === Watching a player ======================================================

--[[ Everything that can change the answer for one player, hung off that player's own trove so a
	leave takes all of it.

	THE CHARACTER IS WAITED FOR IN A SPAWNED THREAD rather than read straight out of `CharacterAdded`.
	The event fires when the model is parented, and the part the car hangs off can arrive a beat
	later; `_hold` refuses a character that is not ready, so without this the first spawn of a
	carrying player would draw nothing until the next event happened to fire. ]]
function CarryService._watch(self, player: Player)
	if self._watching[player] then
		return
	end
	local trove = Trove.new()
	self._watching[player] = trove

	local function onCharacter(character: Model)
		task.spawn(function()
			character:WaitForChild(CarryConfig.Hold.PartName, CHARACTER_WAIT)
			--- They respawned again, or left, while we were waiting. Their own `CharacterAdded` has
			--- already asked this question for the character that replaced this one.
			if player.Character ~= character or player.Parent ~= Players then
				return
			end
			self:_refresh(player)
		end)
	end

	trove:Add(player.CharacterAdded:Connect(onCharacter))
	if player.Character then
		onCharacter(player.Character)
	end
end

function CarryService._forget(self, player: Player)
	self:_drop(player)
	local trove = self._watching[player]
	if trove then
		self._watching[player] = nil
		trove:Destroy()
	end
end

-- === Lifecycle ==============================================================

CarryService:withLifecycle({
	init = function(self)
		self._held = {} :: { [Player]: Held }
		self._watching = {} :: { [Player]: any }
		self._trove = Trove.new()
	end,

	start = function(self)
		if not CarryConfig.Enabled then
			self.log:info("Disabled by config. Cars park themselves, which is what they did before this existed.")
			return
		end

		local Garage = Shard.get("GarageService")
		if not Garage then
			self.log:warn("No GarageService, so there is no record of what anybody is carrying.")
			return
		end

		--- What they are holding changed: a bank put a car in their hands, a podium took it out of
		--- them, or a sale emptied them.
		self._trove:Add(Garage:getSignal("CarryChanged"):Connect(function(player: Player)
			self:_refresh(player)
		end))

		--[[ ...and the profile arriving is the same question asked for a REJOIN. The record is a
			profile key, so a player who logged off holding a car is still holding it, and this is the
			moment that becomes knowable. ]]
		self._trove:Add(Garage:getSignal("ProfileReady"):Connect(function(player: Player)
			self:_watch(player)
			self:_refresh(player)
		end))

		--[[ Both ends of a run. See the header for why a carried car comes off for one: every path
			through a race writes properties across the rider's parts, and two of them rebuild the rig
			outright. `RaceLeft` fires inside the return beat, behind the fade, so the car is back in
			their hands by the time they can see their own character again. ]]
		--[[ ...and the OTHER reason a hand is full: a car picked off the Cars Inventory to drive,
			waiting to be dropped in the street (`LobbyCarConfig.Toy`). Same shape as `CarryChanged`
			above and the same bargain: that service publishes what changed and this one redraws.

			OPTIONAL, like `RaceService` and for the same reason. A server with the lobby car feature
			switched off still hands out banked cars, and declaring it as a dependency would make this
			service refuse to start over a feature that is allowed to be off. ]]
		local Lobby = Shard.get("LobbyCarService")
		if Lobby then
			self._trove:Add(Lobby:getSignal("ToyChanged"):Connect(function(player: Player)
				self:_watch(player)
				self:_refresh(player)
			end))
		else
			self.log:info("No LobbyCarService, so the only car that reaches a hand is a banked one.")
		end

		local Race = Shard.get("RaceService")
		if Race then
			self._trove:Add(Race:getSignal("RaceEntered"):Connect(function(player: Player)
				self:_drop(player)
			end))
			self._trove:Add(Race:getSignal("RaceLeft"):Connect(function(player: Player)
				self:_refresh(player)
			end))
			--- The trip home has let go of them, which is when a banked car reaches their hands now
			--- (`CarryConfig.Hold.AfterReturn`). With that flag off this refresh finds nothing changed.
			self._trove:Add(Race:getSignal("ReturnedHome"):Connect(function(player: Player)
				self:_refresh(player)
			end))
		else
			self.log:warn("No RaceService: a carried car will ride along into a run rather than coming off for it.")
		end

		--[[ Anyone already warm. `ProfileReady` fires off the join path, so on a hot reload, or simply
			if GarageService started first, a player can be past it by the time this connects. The same
			catch-up `TutorialService` and `OfflineService` both make. ]]
		for _, player in Players:GetPlayers() do
			if Garage:isProfileReady(player) then
				self:_watch(player)
				self:_refresh(player)
			end
		end

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self:_forget(player)
		end))
	end,
})

CarryService:withCleanup(function()
	if CarryService._trove then
		CarryService._trove:Destroy()
	end
	for player in CarryService._held or {} do
		CarryService:_forget(player)
	end
end)

return CarryService
