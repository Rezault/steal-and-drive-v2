-- Visual emphasis only: all controls remain usable. Restore every authored opacity on exit.
local RS=game:GetService("ReplicatedStorage")
local TutorialConfig=require(RS.shared.Configs.TutorialConfig)
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
   local scale=Instance.new("UIScale");scale.Name="TutorialFocus";scale.Parent=button
   entry.scale=scale
   self.entries[button.Name]=entry
  end
 end
 return self
end
function Highlight.step(self, step, touch, now)
 local wanted=if touch and TutorialConfig.isOn() then INPUTS[step] else nil
 local wave=0.5-0.5*math.cos((now or os.clock())*math.pi*2/1.1)
 for name,entry in self.entries do
  local focus=wanted and wanted[name]
  entry.scale.Scale=if focus then 1+0.09*wave else 1
  for _,property in entry.properties do
   if property.object.Parent then
    local value=if wanted and not focus then math.max(property.base,0.65) else property.base
    if property.object[property.key]~=value then property.object[property.key]=value end
   end
  end
 end
end
return Highlight
