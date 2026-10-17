--[[
	KitGrowth
	---------
	THE NEW UI DRAWS ITS PAGES AND ITS ICON GRID BIGGER THAN THE CARTOONY KIT DID. Dylan, 2026-09-16:
	"increase the size of all of the pages", and the grid's icons "a little bit more", to make the UI
	friendlier on a phone. That answers the Phase 5 device pass's open question (a page was 270x183pt
	on an iPhone 14, with a 16pt close button).

	The build commands call this on the frame they have just made, so a re-run lands on the same size,
	and the Explorer shows the size a player gets. Nothing reads it at runtime.

	=== WHY A FACTOR AND NOT A NEW SIZE ======================================================

	Every kit page is a scale box under a `FitWithinMaxSize` aspect constraint, and on any screen at
	16:9 or wider its HEIGHT is what binds. Setting only `Size.Y` (0.67 on the Cars page, the number
	Dylan tried by hand) grows a page on Studio's wide viewport and changes nothing at 1080p, where the
	kit's `Size.X` is exactly the page's width already. So both halves grow by one factor, and the
	page keeps the box shape the artist gave it.

	=== THE TEXT CAPS GROW WITH THE BOX ======================================================

	A kit label's `UITextSizeConstraint` cap is that label's height in pixels on a 1080-tall screen
	(see `KitPage.scaleTextCaps`). Grow the box and leave the cap, and at 1080p and up the words stop
	growing at the old size inside a bigger box: 0.97 of the box would read as 0.8. So every cap under
	the frame is multiplied too, and `KitPage` keeps scaling the result by screen height as before.
	Skipped, as `KitPage` skips them: a constraint named `Ceiling` or carrying a `Fraction`, which a
	controller sizes itself.

	=== RE-APPLYING IS SAFE ==================================================================

	The factor applied is written on the frame (`KitGrowth`), so a second call with the same factor does
	nothing and a call with a new factor grows by the difference. A build command starts from a fresh
	clone of the kit, which carries no attribute, so it always applies the whole factor. The caps are
	whole pixels, so moving a factor back and forth in place can drift a cap by a pixel; a re-run of the
	page's build command is the exact answer.
]]

local KitGrowth = {}

--[[ The factors. Chosen off side-by-side renders on an iPhone 14, a Galaxy A06, a 4:3 tablet and 1080p
	(`docs/NewUI-Migration-Notes.md`, "Bigger pages and grid"):

	  • `Pages` takes the kit's wide pages from 0.593 of the screen's height to 0.72, and its square
	    ones (Settings, Worlds) from 0.644 to 0.78. Past about 0.78 a page's header crowds the topbar
	    on a phone. At 0.72 a page runs past the top of the Play button, which is why Play slides out
	    of the way while a page is open (`UIController._syncPlayRoom`).
	  • `Rail` is the icon grid: 20.7pt icons on the smallest phone become 26pt. The grid's anchor is
	    its left edge and middle, so it grows right and out from its centre line, and on a 4:3 tablet
	    it still ends left of a page. ]]
KitGrowth.Pages = 0.72 / 0.593
KitGrowth.Rail = 1.25

--- Written on a grown frame: the factor it carries, relative to the kit.
KitGrowth.Attribute = "KitGrowth"

local TEXT_CAP_ENGINE_MAX = 100

--[[ Grow `frame` to `factor` times the kit's size, caps included. Returns the step actually applied
	(1 when the frame was already at that factor). ]]
function KitGrowth.apply(frame: GuiObject, factor: number): number
	local applied = frame:GetAttribute(KitGrowth.Attribute)
	local step = factor / (if type(applied) == "number" and applied > 0 then applied else 1)
	if math.abs(step - 1) < 1e-4 then
		return 1
	end

	local size = frame.Size
	frame.Size = UDim2.new(size.X.Scale * step, size.X.Offset, size.Y.Scale * step, size.Y.Offset)

	for _, descendant in frame:GetDescendants() do
		if
			descendant:IsA("UITextSizeConstraint")
			and descendant.Name ~= "Ceiling"
			and descendant:GetAttribute("Fraction") == nil
		then
			descendant.MaxTextSize = math.clamp(math.round(descendant.MaxTextSize * step), 1, TEXT_CAP_ENGINE_MAX)
		end
	end

	frame:SetAttribute(KitGrowth.Attribute, factor)
	return step
end

--[[ The car card grids draw FOUR across, not the kit's five (Dylan, 2026-09-16: "make the cards a
	little bit bigger so that we have a better view of the cars"). A page is already as big as a page
	gets, so the cards grow by losing a column, the smallest step that still fills the row. Used by
	`BuildDealershipV2` and `BuildStartCarV2`, which are the same kit grid. ]]
KitGrowth.CarColumns = 4

--[[ How many of its own heights wide `frame` is, off the scale sizes up to the first ancestor with an
	aspect constraint. Nil when there is none, because then the shape depends on the screen. ]]
local function widthInHeights(frame: Instance?): number?
	local ratio = 1
	local node = frame
	while node and node:IsA("GuiObject") do
		local aspect = node:FindFirstChildOfClass("UIAspectRatioConstraint")
		if aspect then
			return ratio * aspect.AspectRatio
		end
		if node.Size.Y.Scale == 0 then
			return nil
		end
		ratio *= node.Size.X.Scale / node.Size.Y.Scale
		node = node.Parent
	end
	return nil
end

--[[ Redraw a kit card grid `columns` across, with `cell` (its card template) grown to match.

	The artist's gap, padding and leftover slack (0.2% on `InventoryUI`, which `KitPage` floors its
	pixels against) are kept, and the new cells share the width the old ones did. The height grows by
	the same factor as the width, so a card keeps its shape, and so do the card's text caps, through
	`apply`. `FillDirectionMaxCells` says the count out loud, which is what `KitPage` counts from.

	THE TOP AND BOTTOM GET THE ROOM THE LEFT HAS. The kit's top padding is 0.015 of the list's height,
	4px in Studio's viewport, and a card's outline is drawn OUTSIDE its box, so the grown card's
	outline sat on the scroll frame's top edge (Dylan, 2026-09-16). The left padding is 0.018 of a
	width twice the height, 11px, which is what reads right, so the top is given that many pixels, and
	the bottom too, so the last row does not end on the edge when scrolled down. `KitPage` converts
	both to pixels against the height and counts them into the canvas.

	Call it on a fresh clone of the kit, BEFORE the page-wide `apply`: that one then grows these caps
	again along with the rest of the page. Returns the factor the card grew by. ]]
function KitGrowth.columns(grid: UIGridLayout, cell: GuiObject, columns: number): number
	local list = grid.Parent
	local padding = list and list:FindFirstChildOfClass("UIPadding")
	local shape = widthInHeights(list)
	if padding and shape then
		local inset = UDim.new(padding.PaddingLeft.Scale * shape, 0)
		padding.PaddingTop = inset
		padding.PaddingBottom = inset
	end
	local room = 1 - (if padding then padding.PaddingLeft.Scale + padding.PaddingRight.Scale else 0)
	local kitCell, gap = grid.CellSize, grid.CellPadding.X.Scale
	local kitColumns = if grid.FillDirectionMaxCells > 0
		then grid.FillDirectionMaxCells
		else math.floor((room + gap) / (kitCell.X.Scale + gap) + 1e-6)
	local slack = room - kitColumns * kitCell.X.Scale - (kitColumns - 1) * gap
	local width = (room - slack - (columns - 1) * gap) / columns
	local growth = width / kitCell.X.Scale

	grid.CellSize = UDim2.new(width, kitCell.X.Offset, kitCell.Y.Scale * growth, kitCell.Y.Offset)
	grid.FillDirectionMaxCells = columns
	KitGrowth.apply(cell, growth)
	return growth
end

return KitGrowth
