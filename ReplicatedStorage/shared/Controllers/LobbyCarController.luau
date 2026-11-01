--[[
	LobbyCarController  (client)
	----------------------------
	The wire between the Cars Inventory's SPAWN IN LOBBY button and `LobbyCarService`, and nothing
	else. Structurally the same thing `DealershipController` is for the rest of that page, for the
	same reason: a page module is not a Shard controller, so it has no remotes of its own. Rather
	than hand `Pages/Dealership` a second remote handle, the press crosses through `Dispatcher`:

	    the press -> SpawnCarPick (event) -> here -> RequestSpawnLobbyCar (remote) -> the server

	`SpawnCarPick` IS THE OLD SPAWN CARS PAGE'S EVENT NAME AND IT IS KEPT ON PURPOSE. That page was
	folded into the Cars Inventory (2026-08-16) because the two asked the same question off the same
	attribute with a different verb attached; the verb did not change, so neither did the event, and
	renaming it would have been a rename across three files that taught nobody anything.

	THERE IS NO RETURN TRIP, which is the difference from the dealership wire and worth stating. The
	server does not answer this; it writes `LobbyCarConfig.SpawnedAttribute` on the player, and the
	page redraws off the attribute change. So the "SPAWNED" marker on a card is written by the thing
	that actually knows whether a car is standing in the world, and a refused request simply never
	changes anything — one code path instead of an optimistic repaint that can disagree with the
	lobby.

	The local cooldown is courtesy, exactly as `RaceEntryController`'s is: it stops the obvious mash
	at the source rather than paying a round trip to be told no. `LobbyCarService` re-checks it and
	nothing downstream treats this as a permission check.

	=== AND THE SECOND HALF: THE CAR IS HELD BEFORE IT IS DROPPED =============================

	`LobbyCarConfig.Toy` is the argument in full. In short: the press now puts a small copy of the
	car in the player's HANDS, and the car itself turns up where they are standing when they click.
	The press used to spawn it behind the panel that was still covering the lobby.

	    the press -> SpawnCarPick -> here -> RequestSpawnLobbyCar -> the server puts a toy in the hand
	    the click -> here -> RequestDropLobbyCar -> the server spawns the real car beside them

	THE MODEL IS NOT DRAWN HERE and never touches this file. `CarryService` builds it, from the same
	call the banked car uses, off the attribute the server publishes. What lives here is the two
	things a model cannot do: the sentence saying what to press, and the press itself.

	THE CLICK IS THE TOOL'S OWN ACTIVATION, which is the whole reason this is a few lines rather than
	a device matrix: the engine fires `Tool.Activated` for a left click, a tap and a gamepad trigger
	alike. Only the SENTENCE has to know which device is in the player's hands (`_word`).

	IT IS BOUND ONLY WHILE A TOY IS PENDING. The same tool carries a BANKED car waiting for a bay,
	which is placed by a podium's prompt and must never be dropped in the street by a stray click.
	`_bindTool` re-reads the attribute rather than trusting when it was last looked at, and
	`CarryService` builds the banked one inert, so it takes both of those being wrong to misfire.

	=== AND GETTING OUT: JUMP LEAVES THE CAR ===================================================

	`LobbyCarConfig.JumpExit` has the why. While you sit in the driver's seat of a lobby car, Space
	and ButtonA are bound above the kit's handbrake, and a press calls that car's
	`LocalVehicleSeating.ExitSeat()`: the same call E makes, so nothing here moves the character or
	touches the seat (the server's exit does that). A phone gets out through the kit's own door
	button; its jump button is under the gas pedal (see the config).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
--- For one question, asked once per hint: which of the three things to call the click. See `_word`.
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local CarryConfig = require(ReplicatedStorage.shared.Configs.CarryConfig)
local CollectorConfig = require(ReplicatedStorage.shared.Configs.CollectorConfig)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)

local LobbyCarController = Shard.new("LobbyCarController")

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--- Under the getaway countdown and the results screen, and above nothing that asks a question. The
--- same band `CarryController`'s card reasons about, one step lower because this is a control hint
--- rather than an announcement.
local DISPLAY_ORDER = 875

local FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--- The jump exit's action. ONE ABOVE the kit's `VehicleChassisRawInput`, which is bound at `High`
--- and sinks Space and ButtonA as its handbrake; anything at or below it never sees the key.
local JUMP_EXIT_ACTION = "LobbyCarJumpExit"
local JUMP_EXIT_PRIORITY = Enum.ContextActionPriority.High.Value + 1

LobbyCarController:withRemoteEvents({
	"RequestSpawnLobbyCar", -- client -> server (carKey|nil)
	--[[ client -> server (nothing): drop the car in my hands, here. `LobbyCarConfig.Toy` has why it
		carries no key. ]]
	LobbyCarConfig.Toy.RemoteName,
})

--- Ask for `body`, or for whatever is out to be put away when it is nil.
function LobbyCarController._request(self, body: string?)
	local now = os.clock()
	if now < self._nextRequestAt then
		return
	end
	self._nextRequestAt = now + LobbyCarConfig.RequestCooldown

	self:getRemoteEvent("RequestSpawnLobbyCar"):Fire(body)
end

-- === Dropping it ============================================================

--[[ What to call the click on the device in the player's hands right now.

	THREE WORDS FOR ONE ACTION, because the engine gives us one event for three inputs and a phone
	that is told to "click" has been told nothing. Asked at the moment the hint is raised rather than
	latched at boot: somebody who put a controller down mid-session should get the sentence about
	the thing they are now holding.

	TOUCH IS ASKED FIRST because a tablet with a keyboard attached is still being played with a
	finger, and the gamepad question comes before the mouse for the same reason the other way round:
	a desktop with a pad plugged in is being played with the pad if the pad is what last moved. ]]
function LobbyCarController._word(self): string
	local hint = LobbyCarConfig.Toy.Hint
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return hint.Touch
	end
	if string.match(last.Name, "^Gamepad") then
		return hint.Gamepad
	end
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return hint.Touch
	end
	if UserInputService.GamepadEnabled and not UserInputService.MouseEnabled then
		return hint.Gamepad
	end
	return hint.Mouse
end

--- The hint's label, built once on the first car that needs one. Lazy for `CarryController`'s
--- reason: nothing here is wanted until somebody picks a car, and most sessions never do.
function LobbyCarController._ensureHint(self): TextLabel?
	local hint = LobbyCarConfig.Toy.Hint
	if not hint.Enabled then
		return nil
	end
	if self._hint then
		return self._hint
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "LobbyCarToyHint"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	--- NOT `Active`, and nothing under it is either: it is a line of text lying across the middle of
	--- the screen, and a label that ate a press would cost somebody the click it is telling them to
	--- make.
	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, hint.CentreY)
	label.Size = UDim2.fromScale(0.6, 0.08)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = ""
	label.TextColor3 = hint.Colour
	label.TextSize = hint.TextSize
	--- A fixed size rather than `TextScaled`, and a stroke rather than a panel. There is no box to
	--- fit to: this is one line over the world, and the legacy text stroke is what keeps it legible
	--- against a lobby that is pale in the day and dark at night.
	label.TextStrokeColor3 = hint.StrokeColour
	label.TextStrokeTransparency = 0.2
	label.TextTransparency = 1
	label.Parent = gui

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self._hintGui = gui
	self._hint = label
	return label
end

--[[ Raise the hint for this car, or take it down when the hands are empty.

	THE TOKEN IS WHAT MAKES A SECOND PICK SAFE. Picking another car while the first hint is still
	counting down restarts it rather than stacking two timers, either of which could otherwise take
	down a line the other had just put up. The same shape `CarryController._raise` uses. ]]
function LobbyCarController._showHint(self, on: boolean)
	local label = self:_ensureHint()
	if not label then
		return
	end

	self._hintToken += 1
	local token = self._hintToken

	if not on then
		TweenService:Create(label, FADE, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		return
	end

	label.Text = self:_word()
	TweenService:Create(label, FADE, { TextTransparency = 0, TextStrokeTransparency = 0.2 }):Play()
	task.delay(LobbyCarConfig.Toy.Hint.Seconds, function()
		--- A newer pick owns the line now, or the car has already been dropped and the hands emptied
		--- it on the way out.
		if self._hintToken ~= token then
			return
		end
		TweenService:Create(label, FADE, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

--[[ Keep the click wired to whatever is currently in the player's hands.

	POLLED ON A SLOW TIMER RATHER THAN SUBSCRIBED, and that is the cheap answer to a question with
	four sources: the tool is rebuilt whenever the held car changes, destroyed with the character on
	a death, taken off for a race and put back after one, and re-equipped by `CarryService` whenever
	anything unequips it. Four subscriptions that all have to be unwound correctly, against one
	`FindFirstChild` every half second that cannot leak: if what is in the hand is not what we are
	connected to, drop the connection and take the new one.

	`Tool.Activated` IS THE WHOLE DEVICE STORY. The engine fires it for a left click, a tap and a
	gamepad trigger alike, only while the tool is equipped and only for the player holding it, so
	there is no input mode to detect and nothing to unbind when the car goes away.

	IT IS ONLY EVER BOUND WHILE A TOY IS PENDING. The same tool class carries a BANKED car, which is
	placed by a podium prompt and must not be dropped in the street by a stray click, so the
	attribute is re-read here rather than trusted from when the loop started. `CarryService` also
	builds that one inert, which is the belt to this braces. ]]
function LobbyCarController._bindTool(self)
	local player = Players.LocalPlayer
	local pending = player:GetAttribute(LobbyCarConfig.Toy.Attribute)
	local holding = type(pending) == "string" and pending ~= ""

	local character = player.Character
	local tool = if holding and character then character:FindFirstChild(CarryConfig.Hold.ModelName) else nil
	if tool and not tool:IsA("Tool") then
		tool = nil
	end

	if self._tool == tool then
		return
	end
	if self._toolConn then
		self._toolConn:Disconnect()
		self._toolConn = nil
	end
	self._tool = tool
	if tool then
		self._toolConn = (tool :: Tool).Activated:Connect(function()
			self:_drop()
		end)
	end
end

--[[ The click. It publishes and stops.

	NO OPTIMISM AND NO LOCAL EFFECT: the toy is not taken out of the hand here and no car is drawn.
	Both follow the attributes, which move when the server has really done it, so a drop with nowhere
	to put the car looks like nothing happening rather than like a car appearing and being snatched
	back. The local cooldown is courtesy on top of the server's own, exactly as `_request`'s is. ]]
function LobbyCarController._drop(self)
	local now = os.clock()
	if now < self._nextDropAt then
		return
	end
	self._nextDropAt = now + LobbyCarConfig.Toy.DropCooldown
	self:getRemoteEvent(LobbyCarConfig.Toy.RemoteName):Fire()
end

-- === Getting out ============================================================

--- The lobby car a seat belongs to, or nil for any other seat (a race car, a chair). The same walk
--- `LobbyDriveController` makes, off the same attribute.
local function lobbyCarOf(seat: Instance): Model?
	local node = seat.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute(LobbyCarConfig.OwnerAttribute) ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

--[[ Leave the car through the kit's own door. The car's `LocalVehicleSeating` is required exactly as
	the deployed Driver requires it (same ModuleScript, so the same cached table and the same exit
	hooks), and `ExitSeat` is what the Driver's E binding calls. It checks for itself that we are
	really in a seat of this car, so a press that lands after the server already stood us up does
	nothing. ]]
function LobbyCarController._jumpExit(self)
	local car = self._exitCar
	if not (car and car.Parent) then
		return
	end
	local now = os.clock()
	if now < self._nextExitAt then
		return
	end
	self._nextExitAt = now + LobbyCarConfig.JumpExit.Cooldown

	local scripts = car:FindFirstChild("Scripts")
	local module = scripts and scripts:FindFirstChild("LocalVehicleSeating")
	if not (module and module:IsA("ModuleScript")) then
		return
	end
	local ok, seating = pcall(require, module)
	if ok and type(seating) == "table" and type(seating.ExitSeat) == "function" then
		-- Collector highway: the exit is the race's bail, a glide you steal out of with E.
		local Steal = Shard.get("StealController")
		if not (CollectorConfig.Enabled and Steal and Steal:bailLobby(car, seating.ExitSeat)) then
			seating.ExitSeat()
		end
	end
end

--- Bind the jump exit for `car`, or unbind it when `car` is nil.
function LobbyCarController._armJumpExit(self, car: Model?)
	self._exitCar = car
	if car then
		ContextActionService:BindActionAtPriority(JUMP_EXIT_ACTION, function(_, state)
			if state == Enum.UserInputState.Begin then
				self:_jumpExit()
			end
			--- Every state, so the kit's handbrake never sees half a press.
			return Enum.ContextActionResult.Sink
		end, false, JUMP_EXIT_PRIORITY, table.unpack(LobbyCarConfig.JumpExit.Keys))
	else
		ContextActionService:UnbindAction(JUMP_EXIT_ACTION)
	end
end

--- Follow one character's seat: armed in the DRIVER's seat of a lobby car, disarmed anywhere else.
--- Passenger seats are left to the stock `Passenger` script, which already exits on jump.
function LobbyCarController._watchSeat(self, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	local function sync(seat: Instance?)
		local car = if seat and seat:IsA("VehicleSeat") then lobbyCarOf(seat) else nil
		self:_armJumpExit(car)
	end
	humanoid.Seated:Connect(function(active: boolean, seat: Instance?)
		sync(if active then seat else nil)
	end)
	sync(humanoid.SeatPart)
end

LobbyCarController:withLifecycle({
	init = function(self)
		self._nextRequestAt = 0
		self._nextDropAt = 0
		self._hintToken = 0
		--- The tool the click is wired to, and that connection. See `_bindTool`.
		self._tool = nil
		self._toolConn = nil
		--- The lobby car whose driver's seat we are in, while the jump exit is armed. See `_jumpExit`.
		self._exitCar = nil
		self._nextExitAt = 0
	end,

	start = function(self)
		-- A CAR KEY ("Sedan12:6"), not a body name — the page lists one card per owned car and the
		-- same body can be on several of them in different colours. See `GarageConfig.carKey`.
		Dispatcher:Subscribe("SpawnCarPick", function(key: unknown)
			if key ~= nil and type(key) ~= "string" then
				return
			end
			self:_request(key :: string?)
		end)

		if LobbyCarConfig.JumpExit.Enabled then
			local player = Players.LocalPlayer
			player.CharacterAdded:Connect(function(character)
				self:_armJumpExit(nil)
				self:_watchSeat(character)
			end)
			if player.Character then
				task.spawn(self._watchSeat, self, player.Character)
			end
		end

		if not LobbyCarConfig.Toy.Enabled then
			return -- the press spawns the car outright, and there is nothing to hold or click
		end

		--[[ The car in the hands changed. It is the server's attribute and it is the only input this
			half of the controller has: raised when a card is pressed, cleared when the car is
			dropped, when the pick is cancelled, when a race starts and when the car is sold. ]]
		local player = Players.LocalPlayer
		local function apply()
			local pending = player:GetAttribute(LobbyCarConfig.Toy.Attribute)
			self:_showHint(type(pending) == "string" and pending ~= "")
			self:_bindTool()
		end
		player:GetAttributeChangedSignal(LobbyCarConfig.Toy.Attribute):Connect(apply)

		--[[ ...and the slow poll that keeps the click on whatever tool is currently in the hand. Half
			a second, because the only thing it is racing is `CarryService` building a model, and a
			click that lands in the gap does nothing rather than something wrong. ]]
		task.spawn(function()
			while true do
				task.wait(0.5)
				self:_bindTool()
			end
		end)

		apply()
	end,
})

return LobbyCarController
