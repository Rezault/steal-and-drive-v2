--[[
	GuideTrailController  (client)
	------------------------------
	THE LINE FROM A PLAYER HOLDING A CAR TO THE BAY IT GOES ON. `GuideTrailConfig` has the why (the
	first-car funnel) and the two looks; this file decides WHETHER to draw and AT WHICH BAY, and hands
	the drawing to whichever look is chosen (`Modules/GuideTrailClassic`, `Modules/GuideTrailModern`).

	=== IT IS DRAWN WHILE THE HANDS ARE FULL ===================================================

	`CarryConfig.Attribute` on the Player is the trigger, the same attribute the glow and the hint read,
	so every way a car reaches the hands (a bank, a hotbar slot, a lift off a bay, a seller) draws it
	and every way out (a bay, the hotbar, the inventory) takes it down, with nothing here having to
	know about any of them. A run suspends it: `RaceStart` to `RaceEnd`, the bracket the glow uses.

	=== THE BAY IS `CarryController`'S ANSWER ==================================================

	Which decks a carried car may go on (whose floor, which storey is bought, which are empty, whether
	the customize pointer is up) is settled there every quarter second for the glow, and asked of it
	here (`getGuideDecks`) rather than walked again. Of those, the line goes to:

	  1. the bay the tutorial's chip is over, when there is one, so the arrow and the chip agree;
	  2. otherwise the nearest, keeping the current one unless another is `SwitchMargin` nearer.

	=== ONE LOOP, ALIVE ONLY WHILE THERE IS A LINE ==============================================

	A Heartbeat connection while the line is wanted or still fading out, and none at all otherwise.
	The bay is re-picked on `Interval`; the drawing follows the player every frame, because a line that
	trails a quarter second behind its owner's feet reads as broken.

	=== THE LOOK IS GAMEBEAST'S, PER PLAYER ====================================================

	Modern against Classic is an A/B (`GuideTrailConfig.Remote` has the setup). `_observeRemote`
	watches this player's value and swaps the look under them if it changes, which it can once, a
	few seconds into a session, when their experiment group lands after their configs did. That is
	long before anybody is holding a car.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local CarryConfig = require(ReplicatedStorage.shared.Configs.CarryConfig)
local GuideTrailConfig = require(ReplicatedStorage.shared.Configs.GuideTrailConfig)
local RaceConfig = require(ReplicatedStorage.shared.Configs.RaceConfig)
local GuideTrailClassic = require(ReplicatedStorage.shared.Modules.GuideTrailClassic)
local GuideTrailModern = require(ReplicatedStorage.shared.Modules.GuideTrailModern)

local GuideTrailController = Shard.new("GuideTrailController")

--- The looks by name, and the order the admin panel lists them in. "Off" is a look that draws nothing.
local LOOKS = {
	Modern = GuideTrailModern,
	Classic = GuideTrailClassic,
}
GuideTrailController.Styles = { "Modern", "Classic", "Off" }

--- Is `point` within `margin` studs of the deck's footprint? Height is ignored: a player stood on the
--- step in front of a bay is at the bay.
local function nearDeck(deck: BasePart, point: Vector3, margin: number): boolean
	local localPoint = deck.CFrame:PointToObjectSpace(point)
	return math.abs(localPoint.X) <= deck.Size.X / 2 + margin and math.abs(localPoint.Z) <= deck.Size.Z / 2 + margin
end

-- === Whether ================================================================

--- Is there a car in the hands (or an admin preview), with nothing standing the line down?
function GuideTrailController._wanted(self): boolean
	if not GuideTrailConfig.Enabled or self._style == "Off" or self._suspended then
		return false
	end
	if self._preview then
		return true
	end
	local player = Players.LocalPlayer
	local key = player:GetAttribute(CarryConfig.Attribute)
	if not (type(key) == "string" and key ~= "") then
		return false
	end
	if GuideTrailConfig.UntilFirstPark and player:GetAttribute(CarryConfig.Guide.ParkedBeforeAttribute) == true then
		return false
	end
	return true
end

-- === Which bay ==============================================================

function GuideTrailController._pickDeck(self, here: Vector3): BasePart?
	local carry = Shard.get("CarryController")
	if not carry then
		return nil
	end
	local decks = carry:getGuideDecks()
	if #decks == 0 then
		return nil
	end

	--- The tutorial's chip names a bay during the PLACE beat. If it is one of these, it is the answer.
	local tutorial = Shard.get("TutorialController")
	local chipped = tutorial and tutorial:getChipTarget()
	if chipped and table.find(decks, chipped) then
		return chipped
	end

	local best, bestAway = nil, math.huge
	local held: number? = nil
	for _, deck in decks do
		local away = (deck.Position - here).Magnitude
		if deck == self._deck then
			held = away
		end
		if away < bestAway then
			best, bestAway = deck, away
		end
	end
	if bestAway > GuideTrailConfig.MaxStuds then
		return nil
	end
	if held and bestAway > held - GuideTrailConfig.SwitchMargin then
		return self._deck
	end
	return best
end

-- === Drawing ================================================================

--- The look in use, built on first need. Nil while the style is "Off".
function GuideTrailController._look(self)
	if self._renderer and self._rendererStyle == self._style then
		return self._renderer
	end
	if self._renderer then
		self._renderer:destroy()
		self._renderer = nil
	end
	local look = LOOKS[self._style]
	if look then
		self._renderer = look.new()
		self._rendererStyle = self._style
	end
	return self._renderer
end

function GuideTrailController._step(self, dt: number)
	self._sinceCheck += dt
	if self._sinceCheck >= GuideTrailConfig.Interval or (self._deck and not self._deck.Parent) then
		self._sinceCheck = 0
		self._want = self:_wanted()
	end

	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local deck: BasePart? = nil
	local feet: Vector3? = nil

	if self._want and root then
		feet = root.Position - Vector3.yAxis * ((if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2)
		if self._sinceCheck == 0 or not (self._deck and self._deck.Parent) then
			self._deck = self:_pickDeck(root.Position)
		end
		deck = self._deck
		if deck and nearDeck(deck, feet :: Vector3, GuideTrailConfig.ArriveStuds) then
			--- Arrived: the prompt is up and the deck is glowing. The bay is kept, so stepping back
			--- off it brings the same line straight back.
			deck = nil
		end
	end

	local target = if deck then 1 else 0
	local rate = if target > self._alpha then 1 / GuideTrailConfig.FadeIn else 1 / GuideTrailConfig.FadeOut
	self._alpha = if target > self._alpha
		then math.min(target, self._alpha + rate * dt)
		else math.max(target, self._alpha - rate * dt)

	local look = self:_look()
	local drawAt = deck or self._lastDeck
	if look and self._alpha > 0 and root and drawAt and drawAt.Parent and feet then
		self._lastDeck = drawAt
		look:draw(root.Position, feet, drawAt, self._alpha, dt)
	elseif look then
		look:hide()
		self._lastDeck = nil
	end

	if not self._want and self._alpha <= 0 then
		self:_stop()
	end
end

function GuideTrailController._start(self)
	if self._loop then
		return
	end
	self._sinceCheck = math.huge
	self._loop = RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end)
end

function GuideTrailController._stop(self)
	if self._loop then
		self._loop:Disconnect()
		self._loop = nil
	end
	if self._renderer then
		self._renderer:hide()
	end
	self._alpha = 0
	self._lastDeck = nil
end

--- Something that decides whether there is a line changed. The loop works out the rest.
function GuideTrailController._apply(self)
	self._want = self:_wanted()
	if self._want then
		self:_start()
	end
end

-- === The A/B ================================================================

--- A look name the drawing knows, or nil. "Off" is one.
local function lookName(value: unknown): string?
	if value == "Off" or (type(value) == "string" and LOOKS[value] ~= nil) then
		return value :: string
	end
	return nil
end

--[[ Follow this player's look in Gamebeast's remote config. `Observe` calls back once when the configs
	have loaded and again on every change, including the player's experiment group arriving. Anything
	missing or unknown is the build's `Style`, so a failure here costs the experiment and nothing else. ]]
function GuideTrailController._observeRemote(self)
	local remote = GuideTrailConfig.Remote
	if not remote.Enabled then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			local Gamebeast = require(ReplicatedStorage:WaitForChild("Gamebeast"))
			Gamebeast:GetService("Configs"):Observe(remote.Path, function(value)
				self:_onRemoteStyle(value)
			end)
		end)
		if not ok then
			self.log:warn("Gamebeast config unavailable, drawing the build's look: " .. tostring(err))
		end
	end)
end

function GuideTrailController._onRemoteStyle(self, value: unknown)
	self._remoteStyle = lookName(value)
	local style = self._remoteStyle or GuideTrailConfig.Style
	-- The admin panel's pick stands for the rest of the session: a tester comparing looks is not
	-- to be switched back by the next config poll.
	if self._styleForced or style == self._style then
		return
	end
	self._style = style
	self:_apply()
end

-- === Public (the admin panel's Showroom tab) =================================

function GuideTrailController.getStyle(self): string
	return self._style
end

--- What Gamebeast assigned this player, or nil before it has answered. For the admin panel.
function GuideTrailController.getRemoteStyle(self): string?
	return self._remoteStyle
end

--- One client only, for comparing the looks. "Off" draws nothing. Overrides the A/B's pick.
function GuideTrailController.setStyle(self, style: string)
	if not lookName(style) then
		return
	end
	self._styleForced = true
	self._style = style
	self:_apply()
end

function GuideTrailController.getPreview(self): boolean
	return self._preview
end

--- Draw the line with empty hands, so a look can be judged without banking a car first.
function GuideTrailController.setPreview(self, on: boolean)
	self._preview = on == true
	self:_apply()
end

GuideTrailController:withRemoteEvents({
	{
		--- The race bracket, the same one the glow and the dealership pin use.
		RaceStart = function()
			GuideTrailController._suspended = true
			GuideTrailController:_apply()
		end,
		RaceEnd = function()
			GuideTrailController._suspended = false
			GuideTrailController:_apply()
		end,
	},
})

GuideTrailController:withLifecycle({
	init = function(self)
		self._style = GuideTrailConfig.Style
		self._remoteStyle = nil :: string? -- Gamebeast's answer for this player, once it has given one
		self._styleForced = false -- the admin panel picked a look; Gamebeast no longer moves it
		self._preview = false
		self._suspended = false
		self._want = false
		self._alpha = 0
		self._sinceCheck = 0
		self._deck = nil :: BasePart?
		self._lastDeck = nil :: BasePart?
	end,

	start = function(self)
		if not GuideTrailConfig.Enabled then
			return
		end
		local player = Players.LocalPlayer
		player:GetAttributeChangedSignal(CarryConfig.Attribute):Connect(function()
			self:_apply()
		end)
		player:GetAttributeChangedSignal(CarryConfig.Guide.ParkedBeforeAttribute):Connect(function()
			self:_apply()
		end)
		player.CharacterAdded:Connect(function()
			self:_apply()
		end)
		--- Home from a run with no `RaceEnd` (it is not ordered against this): put the line back.
		Dispatcher:Subscribe(RaceConfig.ReturnedEvent, function()
			self._suspended = false
			self:_apply()
		end)
		self:_observeRemote()
		self:_apply()
	end,
})

return GuideTrailController
