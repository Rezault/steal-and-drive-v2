local M={}
function M.restore()
assert(not game:GetService("RunService"):IsRunning(),"Restore in Edit mode")
local n=0
for i,e in ipairs(script.Parent.Entries:GetChildren())do
if e:GetAttribute("Status")=="Done"then
local old=e.Original.Value local parent=e.OriginalParent.Value local replacement=e.Optimized.Value
assert(old and parent,"Missing backup or original parent: "..e.Name)
old.Parent=parent
if replacement then replacement:Destroy()end
e:SetAttribute("Status","Restored")n+=1
end
if i%30==0 then task.wait()end
end
script.Parent:SetAttribute("Restored",true)
return "Restored "..n.." original vegetation models"
end
return M
