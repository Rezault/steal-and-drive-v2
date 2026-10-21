local M={}
function M.stage(importRoot)
assert(not game:GetService("RunService"):IsRunning(),"Use Edit mode")
assert(importRoot and importRoot:IsA("Model"),"Pass the imported VegetationTemplates model")
local work=script.Parent
local uploaded={}
for _,p in ipairs(importRoot:GetDescendants())do
if p:IsA("MeshPart")then
local current=p local name
while current and current~=importRoot.Parent do name=string.match(current.Name,"Template_%d%d")if name then break end current=current.Parent end
if name then assert(p.MeshId~="" and string.find(p.MeshId,"%d"),"Mesh asset not uploaded: "..name)uploaded[name]=p end
end end
local cache={}
for _,c in ipairs(work.SignatureMap:GetChildren())do
assert(uploaded[c.Name],"Missing imported mesh: "..c.Name)
cache[c:GetAttribute("GeometryKey")]=uploaded[c.Name]
end
local folder=work:FindFirstChild("Candidates")
if folder then folder:Destroy()end
folder=Instance.new("Folder")folder.Name="Candidates"folder.Parent=work
local B=require(work.Builder)local count=0
for i,e in ipairs(game.ServerStorage.VegetationBackup_20261020.Entries:GetChildren())do
local old=e.Original.Value
assert(old:IsDescendantOf(workspace.Map),"Original is not active: "..e.Name)
local new=Instance.new("Model")new.Name=old.Name new.WorldPivot=old:GetPivot()
new:SetAttribute("VegetationSharedMesh",true)
for k,v in pairs(old:GetAttributes())do new:SetAttribute(k,v)end
for _,t in ipairs(old:GetTags())do new:AddTag(t)end
for _,g in ipairs(B.groups(old))do
local src=g.parts[1]local p=cache[g.key]:Clone()
for _,child in ipairs(p:GetChildren())do child:Destroy()end
for _,tag in ipairs(p:GetTags())do p:RemoveTag(tag)end
p.Name=src.Name p.TextureID=""p.Material=Enum.Material.Plastic p.MaterialVariant="Studs"
p.Size=g.size
local offset=p.CFrame:ToObjectSpace(p.ExtentsCFrame)
p.CFrame=g.pivot*CFrame.new(g.center)*offset:Inverse()
p.Anchored=true p.CanTouch=false p.CanCollide=src.CanCollide p.CanQuery=src.CanQuery
p.CastShadow=src.CastShadow p.CollisionGroup=src.CollisionGroup p.Color=src.Color
p.Transparency=src.Transparency p.Reflectance=src.Reflectance
p.CollisionFidelity=Enum.CollisionFidelity.Default p.RenderFidelity=Enum.RenderFidelity.Automatic
p.CustomPhysicalProperties=src.CustomPhysicalProperties
for k,v in pairs(src:GetAttributes())do p:SetAttribute(k,v)end
for _,t in ipairs(src:GetTags())do p:AddTag(t)end
p.Parent=new count+=1
end
local oc,os=old:GetBoundingBox()local nc,ns=new:GetBoundingBox()
assert((oc.Position-nc.Position).Magnitude<.05 and (os-ns).Magnitude<.05,"Candidate bounds differ: "..e.Name)
new.Parent=folder
local ref=e:FindFirstChild("MeshCandidate")or Instance.new("ObjectValue")
ref.Name="MeshCandidate"ref.Value=new ref.Parent=e
if i%30==0 then task.wait()end
end
importRoot.Parent=work
return "Staged "..count.." uploaded mesh parts. Originals remain active; benchmark before applying."
end
return M