-- One UIScale per driving button. Compose device size and feedback instead of competing scales.
local ButtonScale = {}
local states = setmetatable({}, { __mode = "k" })
local legacy = { TutorialFocus = true, MobileSteeringScale = true, Pulse = true }

function ButtonScale.ensure(button: GuiButton): UIScale
 local state = states[button]
 if state and state.scale.Parent == button then return state.scale end
 local scale = button:FindFirstChild("ControlScale")
 local base = if scale and scale:IsA("UIScale") then scale:GetAttribute("AuthoredScale") or 1 else nil
 if not (scale and scale:IsA("UIScale")) then
  scale = nil
  for _,child in button:GetChildren() do
   if child:IsA("UIScale") and not legacy[child.Name] then scale = child; base = child.Scale; break end
  end
  if not scale then scale = Instance.new("UIScale"); base = 1; scale.Parent = button end
  scale.Name = "ControlScale"
 end
 for _,child in button:GetChildren() do
  if child:IsA("UIScale") and child ~= scale then child:Destroy() end
 end
 scale:SetAttribute("AuthoredScale", base)
 states[button] = { scale = scale, base = base, factors = {} }
 scale.Scale = base
 return scale
end

function ButtonScale.set(button: GuiButton, channel: string, factor: number)
 local scale = ButtonScale.ensure(button)
 local state = states[button]
 if factor ~= factor or factor <= 0 or factor == math.huge then factor = 1 end
 state.factors[channel] = factor
 local combined = state.base
 for _,value in state.factors do combined *= value end
 if math.abs(scale.Scale - combined) > 0.0001 then scale.Scale = combined end
end

return ButtonScale
