-- One nearby car readout; collection facts use the same source as the Index.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CarConfig = require(ReplicatedStorage.shared.Configs.CarConfig)
local Config = require(ReplicatedStorage.shared.Configs.CollectionCueConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
local StealConfig = require(ReplicatedStorage.shared.Configs.StealConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local CarCatalogue = require(ReplicatedStorage.shared.Modules.CarCatalogue)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarRarityBadge = require(ReplicatedStorage.shared.Modules.CarRarityBadge)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)
local function oneLine(text)
 return (string.gsub(text," ",utf8.char(0xA0)))
end
local Cue = {}
Cue.__index = Cue

-- Target speed includes body XP, as the steal handoff does; fitted parts are not inherited.
function Cue.describe(rec, found, levels, currentSpeed)
 local speed = CarConfig.maxSpeedOf(rec.body) * RewardConfig.speedScaleFor(RewardConfig.levelOf(levels, rec.body))
 local isNew = found ~= nil and found[rec.body] ~= true
 local faster = currentSpeed > 0 and speed > currentSpeed * Config.SpeedThreshold
 local words = {}
 if isNew then table.insert(words, "NEW") end
 if faster then table.insert(words, "↑ FASTER") end
 return {
  text = table.concat(words, " · "), isNew = isNew, faster = faster,
  value = GarageConfig.valueOf(GarageConfig.TierOfBody[rec.body], rec.mutation),
  name = GarageConfig.displayName(rec.body),
 }
end

function Cue.choose(cars, playerAlong, playerCross, previous)
 local best, bestScore, previousScore
 for _, rec in cars do
  if rec.hit and rec.hit.Parent and not (rec.clipped or rec.physical or rec.frozen) then
   local ahead = rec.along - playerAlong
   local side = math.abs(rec.cross - playerCross)
   if ahead >= -12 and ahead <= Config.FocusDistance and side <= Config.FocusCross then
    local score = math.max(0, ahead) + side * 4
    if not bestScore or score < bestScore then best, bestScore = rec, score end
    if rec == previous then previousScore = score end
   end
  end
 end
 -- Hold a valid nearby car until a meaningfully closer one arrives.
 if previousScore and best ~= previous and bestScore >= previousScore * Config.SwitchRatio then
  return previous
 end
 return best
end

function Cue.shouldRemind(desc, ahead, closing, elapsed, now, nextAt, jumped)
 if not Config.Reminder.Enabled or jumped or not (desc.isNew or desc.faster) then return false end
 local cfg = Config.Reminder
 if elapsed < cfg.StartDelay or now < nextAt or closing <= 0 then return false end
 local arrival = ahead / closing
 return ahead >= cfg.MinAhead and ahead <= cfg.MaxAhead and arrival >= cfg.MinArrival and arrival <= cfg.MaxArrival
end

local function label(parent, name, y, h)
 local text = Instance.new("TextLabel")
 text.Name = name
 text.BackgroundTransparency = 1
 text.Position = UDim2.fromScale(0.04, y)
 text.Size = UDim2.fromScale(0.92, h)
 text.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
 text.TextColor3 = Color3.new(1,1,1)
 text.TextStrokeColor3 = Color3.fromRGB(2,30,56)
 text.TextStrokeTransparency = 0
 text.TextWrapped = false
 text.TextScaled = true
 text.Text = ""
 text.Parent = parent
 return text
end

function Cue.new(playerGui)
 local self = setmetatable({}, Cue)
 local gui = Instance.new("ScreenGui")
 gui.Name = "TrafficCollectionReadout"
 gui.ResetOnSpawn = false
 gui.DisplayOrder = 8
 gui.Enabled = false
 local card = Instance.new("Frame")
 card.Name = "NearbyCar"
 card.AnchorPoint = Vector2.new(0.5,1)
 card.Position = UDim2.fromScale(0.5,0.87)
 card.Size = UDim2.fromScale(0.28,0.125)
 card.BackgroundColor3 = Color3.fromRGB(20,27,45)
 card.BackgroundTransparency = 0.2
 card.BorderSizePixel = 0
 card.Parent = gui
 local corner = Instance.new("UICorner")
 corner.CornerRadius = UDim.new(0.12,0)
 corner.Parent = card
 local stroke = Instance.new("UIStroke")
 stroke.Color = Color3.fromRGB(85,214,122)
 stroke.Thickness = 2
 stroke.Parent = card
 self.name = label(card,"Name",0.04,0.25)
 self.value = label(card,"Value",0.32,0.23)
 self.reason = label(card,"Reason",0.60,0.20)
 local hint = Instance.new("Frame")
 hint.Name = "JumpReminder"
 hint.BackgroundColor3 = Color3.fromRGB(38,105,54)
 hint.BorderSizePixel = 0
 hint.AnchorPoint = Vector2.new(0.5,0)
 hint.Position = UDim2.fromScale(0.5,1.03)
 hint.Size = UDim2.fromScale(1,0.30)
 hint.Visible = false
 hint.Parent = card
 local hintCorner = Instance.new("UICorner")
 hintCorner.CornerRadius = UDim.new(0.2,0)
 hintCorner.Parent = hint
 self.hintText = label(hint,"Text",0.12,0.76)
 self.hintIcon = Instance.new("ImageLabel")
 self.hintIcon.BackgroundTransparency = 1
 self.hintIcon.Position = UDim2.fromScale(0.04,0.10)
 self.hintIcon.Size = UDim2.fromScale(0.13,0.80)
 self.hintIcon.ScaleType = Enum.ScaleType.Fit
 local aspect = Instance.new("UIAspectRatioConstraint")
 aspect.AspectRatio = 1
 aspect.Parent = self.hintIcon
 self.hintIcon.Parent = hint
 self.gui, self.hint, self.stroke = gui, hint, stroke
 self.player = Players.LocalPlayer
 self.started, self.nextAt, self.untilAt, self.nextUpdate = 0,0,0,0
 gui.Parent = playerGui
 return self
end

function Cue.setActive(self, on)
 self.active = on and Config.Enabled
 self.gui.Enabled = false
 self.hint.Visible = false
 self.focus, self.reminderFocus = nil,nil
 self.started, self.nextAt, self.untilAt, self.nextUpdate = os.clock(),0,0,0
 self.jumped = false
end

function Cue.step(self, road, traffic, steal, currentSpeed)
 if not self.active then return false end
 local now = os.clock()
 local camera = workspace.CurrentCamera
 if camera and camera.ViewportSize.X > 0 then
  self.gui.NearbyCar.Size = UDim2.fromScale(math.clamp(0.475 * camera.ViewportSize.Y / camera.ViewportSize.X, 0.22, 0.65), 0.125)
 end
 -- The stop is polled every rendered frame, so a bail dismisses the hint immediately.
 if steal._state ~= "idle" then
  self.jumped = true
  self.untilAt = 0
  self.gui.Enabled = false
  return false
 end
 if now < self.nextUpdate then return self.hint.Visible end
 self.nextUpdate = now + Config.UpdateInterval
 local info, car = road:getRoadInfo(), road:getCar()
 if not (info and car and car.PrimaryPart and traffic) or traffic._wrecked or traffic._suspended or traffic._frozen then
  self.gui.Enabled = false
  self.hint.Visible = false
  return false
 end
 -- Leave the tutorial's own teaching card in charge until it is finished.
 if TutorialConfig.isUnfinished(self.player:GetAttribute(TutorialConfig.StepAttribute)) then
  self.gui.Enabled = false
  return false
 end
 local position = car.PrimaryPart.Position
 local along = road:along(position)
 local cross = position:Dot(info.cross) - info.driveCenter
 local rawFound = self.player:GetAttribute(CarCatalogue.FoundAttribute)
 if rawFound ~= self.rawFound then
  self.rawFound = rawFound
  self.found = if rawFound ~= nil then CarCatalogue.parseFound(rawFound) else nil
 end
 local levels = self.player:GetAttribute(GarageConfig.LevelsAttribute)
 local cars = traffic:getCars()
 self.focus = Cue.choose(cars,along,cross,self.focus)
 local descriptions = {}
 for _,rec in cars do
  local desc = Cue.describe(rec,self.found,levels,currentSpeed)
  descriptions[rec] = desc
  local ahead = rec.along - along
  local text = if ahead >= -12 and ahead <= Config.CueDistance and not (rec.clipped or rec.physical or rec.frozen) then desc.text else ""
  if rec == self.focus then text = "▶ " .. (if text ~= "" then text else "NEARBY") end
  CarRarityBadge.setCue(rec.model,text)
 end
 local rec = self.focus
 if not rec then
  self.gui.Enabled = false
  self.untilAt = 0
  self.hint.Visible = false
  return false
 end
 local desc = descriptions[rec]
 local word,band = CarRarity.of(rec.body)
 local colour = CarRarity.colourOf(band)
 self.name.Text = desc.name
 self.name.TextColor3 = colour
 self.stroke.Color = colour
 self.value.Text = oneLine("CAR VALUE " .. GarageConfig.formatCash(desc.value))
 local mutation = if rec.mutation then WeatherConfig.nameOf(rec.mutation) else ""
 self.reason.Text = if desc.text ~= "" then desc.text .. (if mutation ~= "" then " · " .. string.upper(mutation) else "") else (if mutation ~= "" then string.upper(mutation) else string.upper(word))
 self.reason.Text = oneLine(self.reason.Text)
 self.reason.TextColor3 = Color3.fromRGB(149,244,162)
 if self.reminderFocus ~= rec then self.untilAt = 0 end
 local closing = car.PrimaryPart.AssemblyLinearVelocity:Dot(info.forward) - rec.speed
 if steal:_canBail() and Cue.shouldRemind(desc,rec.along-along,closing,now-self.started,now,self.nextAt,self.jumped) then
  self.reminderFocus = rec
  self.untilAt = now + Config.Reminder.Duration
  self.nextAt = now + Config.Reminder.Cooldown
 end
 self.hint.Visible = now < self.untilAt and steal:_canBail()
 if self.hint.Visible then
  local pad = GamepadInput.isGamepad()
  self.hintIcon.Visible = pad
  if pad then
   local key = GamepadInput.gamepadKeyIn(StealConfig.BailKeys)
   self.hintIcon.Image = if key then GamepadInput.getButtonImage(key) else ""
   self.hintText.Position = UDim2.fromScale(0.18,0.12)
   self.hintText.Size = UDim2.fromScale(0.78,0.76)
   self.hintText.Text = "JUMP OUT TO STEAL"
  else
   self.hintText.Position = UDim2.fromScale(0.04,0.12)
   self.hintText.Size = UDim2.fromScale(0.92,0.76)
   local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
   local key = StealConfig.BailKeys[1]
   self.hintText.Text = if touch then "TAP JUMP TO STEAL" else string.upper(key.Name) .. " · JUMP OUT TO STEAL"
  end
 end
 self.hintText.Text = oneLine(self.hintText.Text)
 self.gui.Enabled = true
 return self.hint.Visible
end
return Cue
