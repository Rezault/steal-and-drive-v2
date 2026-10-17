--[[
	VehiclePromptGui  (client)
	--------------------------
	The pill that floats over a lobby car and says "press E to get in". It is the CarBones kit's own
	`LocalVehiclePromptGui`, lifted out of the place into git the same way `Vehicle` was, plus the
	one thing the kit cannot know: WHICH SEAT the press is actually going to put you in.

	=== WHAT IT IS ============================================================================

	`Style = Custom` on a `ProximityPrompt` means Roblox draws nothing at all, so something has to.
	This is that something. It listens to `ProximityPromptService.PromptShown`, and for any prompt
	named `EndorsedVehicleProximityPromptV1` it clones `ButtonGuiPrototype` (a `BillboardGui`,
	`AlwaysOnTop`), adorns it to the prompt's own attachment, dresses it for the device the player
	is holding, and takes it down again on `PromptHidden`.

	ONE COPY PER PLAYER, NOT PER CAR, and it is worth knowing which. `Vehicle.setup`'s `playerAdded`
	only deploys this script if the player has no `VehiclePromptScreenGui` yet, so the FIRST car to
	see a player wins and every other car's copy is never deployed. That is fine because the
	`PromptShown` connection is global: the one live copy draws for every car on the map. It also
	means the `CarValue` this script carries names an arbitrary car which may not be streamed in.
	Since 2026-10-12 the kit's identical `Keymap` and `InputImageLibrary` are loaded from the shared
	copy `Vehicle` publishes in ReplicatedStorage before deploying the GUI. No car reference is
	needed to start listening for prompts.

	=== THE SEAT THE PRESS IS FOR =============================================================

	The stock rule is `seat.Name == "VehicleSeat"`: parent the prompt to the wheel and it draws a
	steering wheel, parent it to a passenger seat and it draws a passenger. That works when a car
	carries four prompts, one per door, and it is wrong here, because this game's lobby cars carry
	exactly ONE prompt and it speaks for all four seats. `LobbyCarService._wireEntry` has the
	measurement that forced that (four prompts all share E, the engine draws one of them and does
	not pick the nearest, and the driver's seat is the one that loses), so the prompt lives on the
	wheel and the wheel is what the kit drew, even on the press that seats you in the back.

	So the car tells us. `_wireEntry` writes `EntrySeat` on the prompt as the wheel fills and
	empties: "Driver" if the press is going to put you behind the wheel, "Passenger" if the wheel is
	taken and the press will find you a seat. That is everything only the server knows.

	THE REST IS WORKED OUT HERE, PER PLAYER, because the rest depends on where you are standing.
	"Passenger" means the free seat NEAREST THE PRESSER, so the server cannot name it for a prompt
	that half a dozen people can see at once. `seatOnOffer` runs the server's own rule against the
	replicated `Occupant`s and the local character, and the pill then does two things with the one
	answer: it hangs itself on THAT SEAT'S door, and it draws that seat's icon. A pill that says
	"passenger" while floating at the driver's window is describing a seat on the other side of the
	car, which is the report this was written for.

	BOTH ARE RE-ASKED WHILE THE PILL IS UP, five times a second and on the attribute. Walk from the
	front door to the back one and the pill walks with you; somebody takes the wheel of the car you
	are standing at and it moves to a passenger door under you rather than lying until you leave.

	NO ATTRIBUTE MEANS THE STOCK RULE, deliberately, and it means the pill never moves. Anything
	else in the place that raises one of these prompts, now or later, keeps the behaviour the kit
	shipped with and does not have to know this file exists.

	=== EDITING IT ============================================================================

	Every car's `Scripts.LocalVehiclePromptGui` is a stub that requires this module, written by the
	`StubVehiclePromptGui` Command Runner command. Edit the module, not the place. If a car ever
	turns up with the old inline copy (a fresh CarBones import, say), re-run that command.

	See `Vehicle` for the server half and for the extraction pattern, and `LobbyCarService` for the
	entry beat this prompt fires.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local VehiclePromptGui = {}

--- The name the whole kit agrees on. `PromptShown` matches on it here, `VehicleSeating.AddSeat`
--- looks for it when it wires a seat, and `LocalVehicleSeating.ExitSeat` refuses to let a rider out
--- of a seat whose `PromptLocation` does not hold a prompt called exactly this.
VehiclePromptGui.PromptName = "EndorsedVehicleProximityPromptV1"

--- The attribute a car writes on its prompt to say what the next press is worth. Named here rather
--- than spelled out at both ends so the server and this file cannot drift apart.
VehiclePromptGui.SeatAttribute = "EntrySeat"
VehiclePromptGui.Driver = "Driver"
VehiclePromptGui.Passenger = "Passenger"

--- Stock, in degrees off vertical. A seat past this is on its roof and the pill offers a flip
--- instead of a way in.
local MIN_FLIP_ANGLE = 70

--[[ How often the pill re-asks which door it belongs at, and how much closer a rival door has to be
	before it will move.

	NOT EVERY FRAME, because the answer only changes when the player walks a stud or somebody takes a
	seat, and there is at most one of these on screen at a time. Five times a second is under a
	stud's worth of walking at lobby speed.

	THE STUD OF HYSTERESIS IS THE POINT OF THE SECOND NUMBER. Standing halfway between two doors, the
	nearest of them flips back and forth on millimetres, and a pill that strobes between two windows
	is worse than one at the wrong window. A rival has to actually be nearer by a stud to take it. ]]
local RETARGET_INTERVAL = 0.2
local RETARGET_MARGIN = 1

--[[ The kit's own art, unchanged, gathered into one table because it is now picked twice: once when
	the pill goes up and again whenever the car changes its mind about which seat is on offer.

	Keyboard and gamepad have no pressed state of their own in the stock script (both ids are the
	same image), and that is copied rather than tidied so the two devices keep behaving exactly as
	they did. Only touch has a real pressed frame. ]]
local ART = {
	[Enum.ProximityPromptInputType.Keyboard] = {
		Driver = { Image = "rbxassetid://2848250902", Pressed = "rbxassetid://2848250902" },
		Passenger = { Image = "rbxassetid://2848251564", Pressed = "rbxassetid://2848251564" },
	},
	[Enum.ProximityPromptInputType.Gamepad] = {
		Driver = { Image = "rbxassetid://2848635029", Pressed = "rbxassetid://2848635029" },
		Passenger = { Image = "rbxassetid://2848636545", Pressed = "rbxassetid://2848636545" },
	},
	[Enum.ProximityPromptInputType.Touch] = {
		Driver = { Image = "rbxassetid://2847898200", Pressed = "rbxassetid://2847898354" },
		Passenger = { Image = "rbxassetid://2848217831", Pressed = "rbxassetid://2848218107" },
	},
}

--- Stock `isFlipped`. Asked of the SEAT, whose up vector is the only thing in a car that reliably
--- says which way up the body is.
local function isFlipped(seat: BasePart): boolean
	local angle = math.deg(math.acos(math.clamp(seat.CFrame.UpVector:Dot(Vector3.yAxis), -1, 1)))
	return angle >= MIN_FLIP_ANGLE
end

--- Is this press going to put them behind the wheel? The car's answer if it gave one, otherwise the
--- stock question, which is the right fallback for any prompt that is not one of ours.
local function offersTheWheel(prompt: ProximityPrompt, seat: Instance): boolean
	local offer = prompt:GetAttribute(VehiclePromptGui.SeatAttribute)
	if offer == VehiclePromptGui.Driver then
		return true
	elseif offer == VehiclePromptGui.Passenger then
		return false
	end
	return seat.Name == "VehicleSeat"
end

--[[ Is this seat open? `LobbyCarService._wireEntry`'s `seatIsFree`, minus the half that only a
	server can do.

	The server's version takes the `SeatWeld` down when it finds a seat held by a humanoid that has
	died or left the world, because destroying the weld is what makes the engine agree the seat is
	empty. We only have to READ the same situation the same way. It corrects itself either way: the
	server re-asks on the same signals and clears the weld, and `Occupant` comes back to us as nil a
	moment later. ]]
local function seatIsFree(part: BasePart): boolean
	local occupant = (part :: Seat).Occupant
	if not occupant then
		return true
	end
	return occupant.Parent == nil or occupant.Health <= 0
end

--- Where the player is standing, or nil if they have no character to stand with.
local function standingAt(): Vector3?
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))
	return if root and root:IsA("BasePart") then root.Position else nil
end

--[[ WHICH SEAT THIS PRESS IS FOR, ANSWERED THE WAY THE SERVER ANSWERS IT.

	`LobbyCarService._wireEntry`'s `seatFor` is the real decision and it reads: the wheel if the wheel
	is free, otherwise the free seat nearest to where the presser is standing. This is that function
	again, run on the client against the same replicated `Occupant`s and the local character's own
	position, so the pill can be drawn at the door it is going to open.

	IT IS A PREDICTION AND IT CAN BE WRONG, in exactly one way: somebody else takes the seat between
	the pill being drawn and the key going down, and the server seats you in a different one. That is
	the same race any two players pressing E on the same car have always had, and the server's answer
	is the one that counts.

	A PROMPT THAT NEVER PUBLISHED AN OFFER GETS ITS OWN SEAT AND NOTHING ELSE. That is the stock
	behaviour, and it keeps every other prompt in the place, now or later, out of this. ]]
local function seatOnOffer(prompt: ProximityPrompt, seat: BasePart): BasePart
	if prompt:GetAttribute(VehiclePromptGui.SeatAttribute) ~= VehiclePromptGui.Passenger then
		return seat
	end

	local chassis = seat.Parent
	local from = standingAt()
	if not (chassis and from) then
		return seat
	end

	local best, bestDistance = nil, math.huge
	for _, part in chassis:GetChildren() do
		if part:IsA("Seat") and part ~= seat and seatIsFree(part) then
			local distance = (from - part.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = part, distance
			end
		end
	end

	--- A full car keeps the pill on the wheel. The prompt is dark in that case anyway, so this is
	--- only ever the frame between the last seat filling and the light going out.
	return best or seat
end

--[[ The attachment to hang the pill on for a given seat, and why it is always an attachment.

	Every seat on a lobby car carries a `PromptLocation` (`Vehicle.raisePassengerPrompt` gives the
	three passenger seats theirs), all four positioned from the same offset with its X mirrored for
	the seats across the car, so each one floats at ITS OWN door. `_wireEntry` moves the driver's
	before the car is parented, which is before `raisePassengerPrompt` copies it, so all four agree
	without anything having to keep them in step.

	Adorning to the attachment rather than to the seat with a `StudsOffsetWorldSpace` is what makes
	the offset ride the car: a world-space offset is a fixed direction and would swing to the wrong
	side of a car that turns. ]]
local function adorneeFor(seat: BasePart, fallback: Instance): Instance
	local location = seat:FindFirstChild("PromptLocation")
	return if location and location:IsA("Attachment") then location else fallback
end

function VehiclePromptGui.setup(promptScript: LocalScript)
	local screenGui = promptScript.Parent
	local assets = script.Parent:WaitForChild("VehiclePromptAssets")
	local Keymap = require(assets:WaitForChild("Keymap"))
	local InputImageLibrary = require(assets:WaitForChild("InputImageLibrary"))

	--[[ Dress one pill for one prompt. Returns the BillboardGui and the connection that keeps its
		icon honest, which the caller takes down with the pill. ]]
	local function createPrompt(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
		local seat = prompt.Parent.Parent
		local buttonGui = promptScript:WaitForChild("ButtonGuiPrototype")
		local promptUI = buttonGui:Clone()
		promptUI.Name = "ButtonGui"
		promptUI.Enabled = true
		promptUI.Adornee = prompt.Parent

		local EnterImageButton = promptUI:WaitForChild("ButtonImage")
		local FlipImageButton = promptUI:WaitForChild("FlipImage")
		local BackgroundDesktop = promptUI:WaitForChild("BackgroundDesktop")
		local BackgroundConsole = promptUI:WaitForChild("BackgroundConsole")
		local ButtonPrompt = promptUI:WaitForChild("ButtonPrompt")

		-- Switch button type
		if inputType == Enum.ProximityPromptInputType.Keyboard then
			EnterImageButton.Size = UDim2.new(0, 36, 0, 36)
			FlipImageButton.Image = "rbxassetid://2848307983"
			FlipImageButton:WaitForChild("Pressed").Image = "rbxassetid://2848307983"
			FlipImageButton.Size = UDim2.new(0, 44, 0, 44)

			BackgroundConsole.Visible = false
			BackgroundDesktop.Visible = true
			BackgroundDesktop.Size = UDim2.new(0, 97, 0, 46)
			BackgroundDesktop.Position = UDim2.new(0.5, 28, 0.5, 0)

			ButtonPrompt.Visible = true
			ButtonPrompt.Image = "rbxassetid://2935912536"
			ButtonPrompt.Size = UDim2.new(0, 36, 0, 36)
			ButtonPrompt.Position = UDim2.new(0.5, -46, 0.5, 0)
			ButtonPrompt.TextLabel.Visible = true

			-- Display the correct key
			ButtonPrompt.TextLabel.Text = Keymap.EnterVehicleKeyboard.Name
		elseif inputType == Enum.ProximityPromptInputType.Gamepad then
			EnterImageButton.Size = UDim2.new(0, 60, 0, 60)
			FlipImageButton.Image = "rbxassetid://2848307983"
			FlipImageButton:WaitForChild("Pressed").Image = "rbxassetid://2848307983"
			FlipImageButton.Size = UDim2.new(0, 44, 0, 44)

			BackgroundDesktop.Visible = false
			BackgroundConsole.Visible = true
			BackgroundConsole.Size = UDim2.new(0, 136, 0, 66)
			BackgroundConsole.Position = UDim2.new(0.5, 40, 0.5, 0)

			ButtonPrompt.Visible = true
			ButtonPrompt.Size = UDim2.new(0, 46, 0, 46)
			ButtonPrompt.Position = UDim2.new(0.5, -63, 0.5, 0)
			ButtonPrompt.ImageRectSize = Vector2.new(71, 71)
			ButtonPrompt.ImageRectOffset = Vector2.new(512, 600)
			ButtonPrompt.TextLabel.Visible = false

			-- Set the correct image for the gamepad button prompt
			local template = InputImageLibrary:GetImageLabel(Keymap.EnterVehicleGamepad, "Light")
			ButtonPrompt.Image = template.Image
			ButtonPrompt.ImageRectOffset = template.ImageRectOffset
			ButtonPrompt.ImageRectSize = template.ImageRectSize
		elseif inputType == Enum.ProximityPromptInputType.Touch then
			BackgroundDesktop.Visible = false
			BackgroundConsole.Visible = false
			ButtonPrompt.Visible = false

			EnterImageButton.Size = UDim2.new(0, 44, 0, 44)
			FlipImageButton.Image = "rbxassetid://2848187559"
			FlipImageButton:WaitForChild("Pressed").Image = "rbxassetid://2848187982"
			FlipImageButton.Size = UDim2.new(0, 44, 0, 44)

			EnterImageButton.InputBegan:Connect(function()
				prompt:InputHoldBegin()
			end)
			EnterImageButton.InputEnded:Connect(function()
				prompt:InputHoldEnd()
			end)
			FlipImageButton.InputBegan:Connect(function()
				prompt:InputHoldBegin()
			end)
			FlipImageButton.InputEnded:Connect(function()
				prompt:InputHoldEnd()
			end)

			promptUI.Active = true
		end

		if isFlipped(seat) then
			FlipImageButton.Visible = true
			EnterImageButton.Visible = false
		else
			FlipImageButton.Visible = false
			EnterImageButton.Visible = true
		end

		--[[ THE DOOR AND THE ICON, WHICH ARE ONE ANSWER AND NOT TWO. Everything below this line is
			the part that is not the kit's.

			The kit hangs the pill on the prompt's own attachment and draws the art of the seat that
			attachment belongs to, which on a lobby car is the wheel and only the wheel, because one
			prompt speaks for all four seats. So it drew a steering wheel over the driver's door on
			the press that was going to put you in the passenger seat: two statements, both wrong,
			about a seat on the other side of the car.

			`seatOnOffer` answers it once and both follow. Nothing here decides anything separately,
			which is what stops the icon and the position ever disagreeing. ]]
		local art = ART[inputType]
		local target: BasePart? = nil

		local function dressFor(which: BasePart)
			promptUI.Adornee = adorneeFor(which, prompt.Parent)
			if not art then
				return
			end
			--- `offersTheWheel` rather than `which == seat`, because the prompt may have published
			--- nothing at all, and then the stock rule is the honest answer.
			local isDriver = which == seat and offersTheWheel(prompt, seat)
			local face = if isDriver then art.Driver else art.Passenger
			EnterImageButton.Image = face.Image
			EnterImageButton.Pressed.Image = face.Pressed
		end

		--[[ Re-asked rather than set once, because both halves of the answer move while the pill is
			up: somebody takes the wheel of the car you are standing at, or you walk from the front
			door to the back one.

			THE MARGIN IS ONLY APPLIED BETWEEN PASSENGER DOORS. A change of seat CLASS, the wheel
			filling or emptying, is not a near miss between two candidates and is taken at once. ]]
		local function retarget()
			local wanted = seatOnOffer(prompt, seat)
			if wanted == target then
				return
			end
			if target and wanted ~= seat and target ~= seat then
				local from = standingAt()
				if from and (from - wanted.Position).Magnitude > (from - target.Position).Magnitude - RETARGET_MARGIN then
					return
				end
			end
			target = wanted
			dressFor(wanted)
		end
		retarget()

		local connections = {
			prompt:GetAttributeChangedSignal(VehiclePromptGui.SeatAttribute):Connect(retarget),
		}

		--- Only while the pill is up, and only five times a second. There is at most one of these on
		--- screen at a time, because every vehicle prompt in the place shares E and its exclusivity.
		local since = 0
		table.insert(
			connections,
			RunService.Heartbeat:Connect(function(delta)
				since += delta
				if since >= RETARGET_INTERVAL then
					since = 0
					retarget()
				end
			end)
		)

		return promptUI, connections
	end

	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Name == VehiclePromptGui.PromptName then
			local promptUI, connections = createPrompt(prompt, inputType)
			promptUI.Parent = screenGui
			prompt.PromptHidden:Wait()
			for _, connection in connections do
				connection:Disconnect()
			end
			promptUI:Destroy()
		end
	end)
end

return VehiclePromptGui
