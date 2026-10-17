-- Mobile-only growth for the side menu: preserve the authored desktop geometry.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Sizing = {}
Sizing.Growth = 1.35
Sizing.MinTouch = 48
Sizing.MaxHeight = 0.72
Sizing.MaxWidth = 0.26

function Sizing.factor(buttonSide: number, railSize: Vector2, viewport: Vector2, mobile: boolean): number
 if not mobile or buttonSide <= 0 or viewport.X <= 0 or viewport.Y <= 0 then return 1 end
 local desired = math.max(Sizing.Growth, Sizing.MinTouch / buttonSide)
 local heightCap = if railSize.Y > 0 then viewport.Y * Sizing.MaxHeight / railSize.Y else desired
 local widthCap = if railSize.X > 0 then viewport.X * Sizing.MaxWidth / railSize.X else desired
 return math.max(1, math.min(desired, heightCap, widthCap))
end

function Sizing.resize(rail: GuiObject, mobile: boolean, viewport: Vector2)
 local scale = rail:FindFirstChild("MobileMenuScale")
 if not scale then
  scale = Instance.new("UIScale")
  scale.Name = "MobileMenuScale"
  scale.Parent = rail
 end
 if not mobile then scale.Scale = 1; return 1 end
 local originalScale = scale.Scale
 local smallest = math.huge
 for _,cell in rail:GetChildren() do
  if cell:IsA("GuiObject") and cell.Visible then
   local button = if cell:IsA("GuiButton") then cell else cell:FindFirstChild("Main")
   if button and button:IsA("GuiButton") and button.Visible then
    local size = button.AbsoluteSize / originalScale
    if math.min(size.X,size.Y) > 0 then smallest = math.min(smallest,size.X,size.Y) end
   end
  end
 end
 if smallest == math.huge then return originalScale end
 local factor = Sizing.factor(smallest, rail.AbsoluteSize / originalScale, viewport, true)
 if math.abs(scale.Scale - factor) > 0.005 then scale.Scale = factor end
 return factor
end

function Sizing.attach(rail: GuiObject)
 local queued = false
 local function queue()
  if queued then return end
  queued = true
  task.spawn(function()
   -- Wait for the layout to reflect a viewport/input change before reading its bounds.
   RunService.RenderStepped:Wait()
   queued = false
   if not rail.Parent then return end
   local parent = rail.Parent
   local camera = workspace.CurrentCamera
   local viewport = if parent:IsA("GuiObject") then parent.AbsoluteSize else (if camera then camera.ViewportSize else Vector2.zero)
   Sizing.resize(rail, UserInputService.PreferredInput == Enum.PreferredInput.Touch, viewport)
  end)
 end
 rail:GetPropertyChangedSignal("AbsoluteSize"):Connect(queue)
 rail.Parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(queue)
 UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(queue)
 for _,cell in rail:GetChildren() do
  if cell:IsA("GuiObject") then cell:GetPropertyChangedSignal("Visible"):Connect(queue) end
 end
 queue()
end

return Sizing
