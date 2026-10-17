-- Visual emphasis only: all controls remain usable. Restore every authored opacity on exit.
local RS=game:GetService("ReplicatedStorage")
local TutorialConfig=require(RS.shared.Configs.TutorialConfig)
local ButtonScale=require(RS.shared.Modules.ControlButtonScale)
local Highlight={}
Highlight.__index=Highlight
local INPUTS={
 boost={Gas=true}, steer={SteerLeft=true,SteerRight=true},
 survive={SteerLeft=true,SteerRight=true},
 bail={Jump=true}, airborne={Jump=true},
 bank={Gas=true,SteerLeft=true,SteerRight=true},
}
function Highlight.buttonsFor(step) return INPUTS[step] end
function Highlight.new(controls)
 local self=setmetatable({entries={}},Highlight)
 for _,button in controls:GetChildren() do
  if button:IsA("GuiButton") then
   local entry={button=button,properties={}}
   local function capture(object)
    if object:IsA("ImageLabel") or object:IsA("ImageButton") then
     table.insert(entry.properties,{object=object,key="ImageTransparency",base=object.ImageTransparency})
    elseif object:IsA("TextLabel") or object:IsA("TextButton") then
     table.insert(entry.properties,{object=object,key="TextTransparency",base=object.TextTransparency})
    end
   end
   capture(button)
   for _,child in button:GetDescendants() do capture(child) end
   local scale=ButtonScale.ensure(button)
   entry.scale=scale
   self.entries[button.Name]=entry
  end
 end
 return self
end
function Highlight.step(self, step, touch, now)
 local wanted=if touch and TutorialConfig.isOn() then INPUTS[step] else nil
 -- `now` is the arrow's bob clock (`TutorialController.bobClock`); same period and phase, so the swell peaks as the arrow dips in (2026-10-16, was its own 1.1s cosine).
 local wave=0.5+0.5*math.sin((now or os.clock())*math.pi*2/TutorialConfig.Arrow.BobPeriod)
 for name,entry in self.entries do
  local focus=wanted and wanted[name]
  -- 0.18, was 0.09 (2026-10-16): a phone playtester never noticed the 9% swell on JUMP.
  ButtonScale.set(entry.button,"Tutorial",if focus then 1+0.18*wave else 1)
  for _,property in entry.properties do
   if property.object.Parent then
    local value=if wanted and not focus then math.max(property.base,0.65) else property.base
    if property.object[property.key]~=value then property.object[property.key]=value end
   end
  end
 end
end
return Highlight
