--[[
	UIGeom  (client)
	----------------
	Edge arithmetic for authored GUI rects, so nothing downstream has to assume an AnchorPoint.

	WHY THIS EXISTS. Every page on this UI measures the artist's mock-up instead of repeating its
	numbers: the Index grid is derived from `Slot1`, the Dealership's list from `Card1`, the Quest
	well from `QuestRow`, the Market scrollbar's track from `Shelf`. All of that was written as
	`thing.Position.X.Scale` — which is the rect's LEFT EDGE only while the thing is anchored at
	0,0. Re-anchor a sample to 0.5,0.5 (the house preference for buttons and text) and `Position`
	becomes its CENTRE instead, every derived layout slides half an element, and it does not show
	in the Explorer because the samples are destroyed and rebuilt at runtime.

	So the edge is COMPUTED, never read: `topLeft` subtracts the anchor back out and `place` puts
	it back in. Both are pure functions of the instance, so a page written against them is right at
	any anchor and stays right when somebody changes one in the Explorer — which is the property
	the measuring was for in the first place.

	SCALE, DELIBERATELY. Every rect in this UI is authored in pure scale; the pages convert to
	offset themselves against a live AbsoluteSize, for the reasons written up on each of them.
	These helpers report the SCALE component of an edge and ignore the offset half rather than
	mixing the two into a number that is neither. `place` is exact regardless: it rewrites only the
	scale component and leaves `Position`'s offset alone, and since the anchor is unchanged across
	the call the offset half of the edge is unchanged with it.

	HOUSE RULE: no wiki-style double-bracket links in this comment — the closing pair ends the
	block comment early and the parse error points at the wrong line.
]]

local UIGeom = {}

--- The scale-space top-left corner of `gui`'s rect, whatever it is anchored at.
function UIGeom.topLeft(gui: GuiObject): (number, number)
	local anchor, position, size = gui.AnchorPoint, gui.Position, gui.Size
	return position.X.Scale - anchor.X * size.X.Scale, position.Y.Scale - anchor.Y * size.Y.Scale
end

--- The scale-space centre of `gui`'s rect.
function UIGeom.centre(gui: GuiObject): (number, number)
	local left, top = UIGeom.topLeft(gui)
	return left + gui.Size.X.Scale * 0.5, top + gui.Size.Y.Scale * 0.5
end

function UIGeom.left(gui: GuiObject): number
	local left = UIGeom.topLeft(gui)
	return left
end

function UIGeom.top(gui: GuiObject): number
	local _, top = UIGeom.topLeft(gui)
	return top
end

function UIGeom.right(gui: GuiObject): number
	return UIGeom.left(gui) + gui.Size.X.Scale
end

function UIGeom.bottom(gui: GuiObject): number
	return UIGeom.top(gui) + gui.Size.Y.Scale
end

--[[ Move `gui` so its top-left corner lands at (`left`, `top`) in scale, honouring whatever anchor
	it carries. SIZE FIRST: the compensation is measured off `gui.Size`, so a call that resizes and
	repositions in one go has to set the size before this runs or it corrects by the old width. ]]
function UIGeom.place(gui: GuiObject, left: number, top: number)
	local anchor, size = gui.AnchorPoint, gui.Size
	local position = gui.Position
	gui.Position = UDim2.new(
		left + anchor.X * size.X.Scale,
		position.X.Offset,
		top + anchor.Y * size.Y.Scale,
		position.Y.Offset
	)
end

--[[ Give `gui` a new anchor without moving it on screen. Both halves of the UDim2 are corrected,
	so this is exact for a rect with offsets as well as one in pure scale.

	This is the same transform the authored UI was converted with; it lives here so a page that
	builds a widget at runtime can adopt the house anchor without re-deriving the arithmetic. ]]
function UIGeom.reanchor(gui: GuiObject, anchor: Vector2)
	local delta = anchor - gui.AnchorPoint
	if delta.X == 0 and delta.Y == 0 then
		gui.AnchorPoint = anchor
		return
	end

	local position, size = gui.Position, gui.Size
	gui.AnchorPoint = anchor
	gui.Position = UDim2.new(
		position.X.Scale + delta.X * size.X.Scale,
		position.X.Offset + delta.X * size.X.Offset,
		position.Y.Scale + delta.Y * size.Y.Scale,
		position.Y.Offset + delta.Y * size.Y.Offset
	)
end

return UIGeom
