local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)
local Sizing = require(ReplicatedStorage.shared.Modules.MobileMenuSizing)
return function(controller)
 task.spawn(function()
  local gui = UIRoot.wait(controller.PlayerGui, 10)
  local hud = gui and gui:FindFirstChild("HUD")
  local rail = hud and hud:FindFirstChild("Rail")
  if rail and rail:IsA("GuiObject") then Sizing.attach(rail) end
 end)
end
