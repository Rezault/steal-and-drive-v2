local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local Config = require(ReplicatedStorage.shared.Configs.FeedbackAudioConfig)
local Feedback = {}
local lastAt, active = {}, 0
function Feedback.play(key)
 local spec = Config.Cues[key]
 if not (Config.Enabled and spec) or active >= Config.MaximumActive then return false end
 local now = os.clock()
 if now - (lastAt[key] or -math.huge) < spec.Cooldown then return false end
 local group = SoundService:FindFirstChild("GameplayFeedback")
 local source = group and group:FindFirstChild(spec.Name)
 if not (source and source:IsA("Sound") and source.SoundId ~= "") then return false end
 lastAt[key] = now
 local sound = source:Clone()
 sound.Name = spec.Name .. "Playback"
 sound.SoundGroup = source.SoundGroup or (if group:IsA("SoundGroup") then group else nil)
 sound.Looped = false
 sound.Parent = SoundService
 active += 1
 local released = false
 local function release()
  if released then return end
  released = true
  active = math.max(0,active-1)
  sound:Destroy()
 end
 sound.Ended:Once(release)
 sound:Play()
 local startAt = source:GetAttribute("StartAt")
 if type(startAt)=="number" then sound.TimePosition=startAt end
 task.delay(spec.Duration, release)
 Debris:AddItem(sound, 6)
 return true
end
function Feedback.preload()
 local group=SoundService:FindFirstChild("GameplayFeedback")
 if not group then return end
 task.spawn(function() pcall(function() ContentProvider:PreloadAsync(group:GetChildren()) end) end)
end
return Feedback
