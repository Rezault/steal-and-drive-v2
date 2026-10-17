--[[
	CarryNoticeLayout (shared presentation)
	--------------------------------------
	The carry notice is a short toast, not the full PromptUI it was cloned from (2026-10-04).
	Apply the same compact geometry to existing runtime templates and newly authored ones so
	players do not need a Command Runner rebuild to lose the empty space. The art stays the kit's.
]]

local CarryNoticeLayout = {}

function CarryNoticeLayout.apply(card: GuiObject)
	local header = card:FindFirstChild("Header")
	local main = card:FindFirstChild("Main")
	if not (header and header:IsA("GuiObject") and main and main:IsA("GuiObject")) then
		return
	end
	-- Desktop keeps its 3.5 shape; the notice lane fits phones to 220-250px wide (2026-10-12).
	-- 2026-10-13: smaller with the rest of the lane (was 0.27 wide, 240 x 68 to 440 x 126).
	card.Size = UDim2.fromScale(0.22, 0.2)
	local aspect = card:FindFirstChildOfClass("UIAspectRatioConstraint") or Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 3.5
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = card
	local bounds = card:FindFirstChildOfClass("UISizeConstraint") or Instance.new("UISizeConstraint")
	bounds.MinSize = Vector2.new(220, 63)
	bounds.MaxSize = Vector2.new(360, 103)
	bounds.Parent = card
	header.AnchorPoint = Vector2.zero
	header.Position = UDim2.fromScale(0.035, 0.04)
	header.Size = UDim2.fromScale(0.93, 0.24)
	local title = header:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.AnchorPoint = Vector2.zero
		title.Position = UDim2.fromScale(0, 0)
		title.Size = UDim2.fromScale(1, 1)
	end
	main.AnchorPoint = Vector2.zero
	main.Position = UDim2.fromScale(0.025, 0.325)
	main.Size = UDim2.fromScale(0.95, 0.625)
	local well = main:FindFirstChild("Well")
	if well and well:IsA("GuiObject") then
		well.AnchorPoint = Vector2.new(0.5, 0.5)
		well.Position = UDim2.fromScale(0.095, 0.5)
		-- width/card width = height/body aspect; preserves the bare icon's square at every size.
		well.Size = UDim2.fromScale(0.76 * 0.625 / (3.5 * 0.95), 0.76)
	end
	for _, spec in {
		{ "Car", 0.29, 0.39, 0.19 },
		{ "Line", 0.73, 0.3, 0.18 },
	} do
		local label = main:FindFirstChild(spec[1])
		if label and label:IsA("TextLabel") then
			label.AnchorPoint = Vector2.new(0, 0.5)
			label.Position = UDim2.fromScale(0.19, spec[2])
			label.Size = UDim2.fromScale(0.78, spec[3])
			local ceiling = label:FindFirstChild("Ceiling")
			if ceiling and ceiling:IsA("UITextSizeConstraint") then
				ceiling:SetAttribute("Fraction", spec[4])
				ceiling.MaxTextSize = math.round(120 * spec[4])
			end
		end
	end
end

return CarryNoticeLayout
