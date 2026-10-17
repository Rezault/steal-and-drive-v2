--[[
	BasicPage
	---------
	Page-module factory for a screen with no behaviour of its own yet: binds `MainUI.Pages.<name>`
	and wires whatever looks like its close button. `Pages/Foo.luau` can be one line —

		return require(script.Parent.Parent.BasicPage)("Foo")

	— and the screen opens, closes and tweens like every other. Replace it with a real class the
	moment the page grows logic; the contract the controller needs is only `.new(UIController)`,
	`:initialize()` and a `.PageUI`.
]]

local UIControllerTypes = require(script.Parent.UIControllerTypes)

local function findCloseButton(root: Instance): (ImageButton | TextButton)?
	for _, name in { "Close", "CloseButton", "Exit", "X" } do
		local candidate = root:FindFirstChild(name, true)
		if candidate and (candidate:IsA("ImageButton") or candidate:IsA("TextButton")) then
			return candidate
		end
	end
	return nil
end

return function(pageName: string)
	local Page = {}
	Page.__index = Page

	function Page.new(UIController: UIControllerTypes.UIController)
		local self = setmetatable({}, Page)
		self.UIController = UIController

		local mainUI = UIController.PlayerGui:WaitForChild("MainUI")
		self.PageUI = mainUI:WaitForChild("Pages"):WaitForChild(pageName)

		local closeButton = findCloseButton(self.PageUI)
		if closeButton then
			closeButton.MouseButton1Click:Connect(function()
				self.UIController:closePage(pageName)
			end)
		end

		return self
	end

	function Page.initialize(_self) end

	return Page
end
