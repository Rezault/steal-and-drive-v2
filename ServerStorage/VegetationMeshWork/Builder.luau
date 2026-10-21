local M={}
function M.groups(model)
local pivot=model:GetPivot()local _,size=model:GetBoundingBox()
local groups={}
for _,p in ipairs(model:GetDescendants())do if p:IsA("Part")then
local tags=p:GetTags()table.sort(tags)
local key=tostring(p.Color).."|"..tostring(p.CanCollide).."|"..tostring(p.CanQuery).."|"..table.concat(tags,",")
groups[key]=groups[key]or{}table.insert(groups[key],p)
end end
local out={}
for _,parts in pairs(groups)do
local records={}local lo=Vector3.new(math.huge,math.huge,math.huge)local hi=-lo
for _,p in ipairs(parts)do
local rel=pivot:ToObjectSpace(p.CFrame)
local vals={p.Size.X/size.X,p.Size.Y/size.Y,p.Size.Z/size.Z,rel.X/size.X,rel.Y/size.Y,rel.Z/size.Z}
local _,_,_,a,b,c,d,e,f,g,h,i=rel:GetComponents()
for _,v in ipairs({a,b,c,d,e,f,g,h,i})do table.insert(vals,v)end
local str=""for _,v in ipairs(vals)do str..=string.format("%.2f,",math.abs(v)<.005 and 0 or v)end table.insert(records,str)
for x=-1,1,2 do for y=-1,1,2 do for z=-1,1,2 do local v=pivot:PointToObjectSpace(p.CFrame:PointToWorldSpace(p.Size*Vector3.new(x,y,z)/2))
lo=lo:Min(v)hi=hi:Max(v)
end end end
end
table.sort(records)
table.insert(out,{key=table.concat(records,";"),parts=parts,center=(lo+hi)/2,size=hi-lo,pivot=pivot})
end
return out
end
function M.build(g)
local mesh=game:GetService("AssetService"):CreateEditableMesh()
assert(mesh,"EditableMesh creation failed")
local faces={
{Vector3.new(1,0,0),{Vector3.new(1,-1,-1),Vector3.new(1,1,-1),Vector3.new(1,1,1),Vector3.new(1,-1,1)}},
{Vector3.new(-1,0,0),{Vector3.new(-1,-1,1),Vector3.new(-1,1,1),Vector3.new(-1,1,-1),Vector3.new(-1,-1,-1)}},
{Vector3.new(0,1,0),{Vector3.new(-1,1,-1),Vector3.new(-1,1,1),Vector3.new(1,1,1),Vector3.new(1,1,-1)}},
{Vector3.new(0,-1,0),{Vector3.new(-1,-1,1),Vector3.new(-1,-1,-1),Vector3.new(1,-1,-1),Vector3.new(1,-1,1)}},
{Vector3.new(0,0,1),{Vector3.new(1,-1,1),Vector3.new(1,1,1),Vector3.new(-1,1,1),Vector3.new(-1,-1,1)}},
{Vector3.new(0,0,-1),{Vector3.new(-1,-1,-1),Vector3.new(-1,1,-1),Vector3.new(1,1,-1),Vector3.new(1,-1,-1)}}}
local removed=0
for _,p in ipairs(g.parts)do
for _,face in ipairs(faces)do
local normal=p.CFrame:VectorToWorldSpace(face[1])local corners={}
for _,v in ipairs(face[2])do table.insert(corners,p.CFrame:PointToWorldSpace(p.Size*v/2))end
local hidden=false
for _,other in ipairs(g.parts)do if other~=p then
local inside=true
for _,v in ipairs(corners)do local q=other.CFrame:PointToObjectSpace(v+normal*.002)local h=other.Size/2
if math.abs(q.X)>h.X+.00001 or math.abs(q.Y)>h.Y+.00001 or math.abs(q.Z)>h.Z+.00001 then inside=false break end end
if inside then hidden=true break end end end
if hidden then removed+=1 else
local ids={}for _,v in ipairs(corners)do local localV=g.pivot:PointToObjectSpace(v)-g.center
table.insert(ids,mesh:AddVertex(localV/g.size))end
local n=mesh:AddNormal(g.pivot:VectorToObjectSpace(normal))
local w=(corners[2]-corners[1]).Magnitude/2 local h=(corners[4]-corners[1]).Magnitude/2
local uv={mesh:AddUV(Vector2.new(0,0)),mesh:AddUV(Vector2.new(w,0)),mesh:AddUV(Vector2.new(w,h)),mesh:AddUV(Vector2.new(0,h))}
for _,t in ipairs({{1,2,3},{1,3,4}})do local f=mesh:AddTriangle(ids[t[1]],ids[t[2]],ids[t[3]])mesh:SetFaceNormals(f,{n,n,n})mesh:SetFaceUVs(f,{uv[t[1]],uv[t[2]],uv[t[3]]})end
end end end
return mesh,removed
end
return M