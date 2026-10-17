--[[
	NoticeLaneConfig
	----------------
	The lobby's one notification lane (Leaf, 2026-10-06: "should be a noti on the left side or
	somewhere else, we have to stop spamming everything on the top"). `Modules/NoticeLane` has the
	mechanics; this has the numbers.

	WHERE IT IS. Down the left, just right of the HUD rail, starting level with the rail's first
	button. That keeps it clear of both left-side neighbours: the tutorial card rests top-left, ABOVE
	the rail (`TutorialConfig.CardSide`), and the rail itself is to the lane's left. The Cash readout
	is bottom-left, far below anything the lane holds.

	WHAT IS IN IT, top to bottom by `Order`: the offline earnings line (out of the lane since
	2026-10-06, `OfflineConfig.Label.InLane`), the carry card (Your New Car, Customize It, Parked), the
	"While You Were Driving" line, and New Car Discovered (in the lane on a phone; top-right on a PC,
	where it still waits its turn). A member that comes up slides in from the left into its slot; one
	going away slides back out and the rest close the gap.

	`Enabled = false` puts every member back where it was before the lane: top-centre.
]]

local NoticeLaneConfig = {}

NoticeLaneConfig.Enabled = true

--- Pixels between the rail's right edge and the lane, and between two stacked notices.
NoticeLaneConfig.Gap = 10
NoticeLaneConfig.Spacing = 6

--[[ Where the lane starts when the rail cannot be measured (not built yet, or hidden for a race), as
	fractions of the viewport. The rail's own spot on a 16:9 screen, roughly. The last measured spot
	is preferred over this whenever there is one. ]]
NoticeLaneConfig.FallbackX = 0.085
NoticeLaneConfig.FallbackY = 0.31

--[[ The width a text member (the offline line) takes: the Your New Car card's own width rule.
	2026-10-13: was 0.27, 280 to 440. Smaller, with `CompactWidth` and `Modules/CarryNoticeLayout`,
	in the pass on the cards that pile up after a run. ]]
NoticeLaneConfig.Width = { Scale = 0.22, Min = 260, Max = 360 }
--- The same on a phone (`NoticeLane.compact`); was 0.42, 240 to 280.
NoticeLaneConfig.CompactWidth = { Scale = 0.36, Min = 220, Max = 250 }

--[[ HOW MANY CARDS ARE UP AT ONCE (2026-10-13, Aleafo on the trip home: "this is excessive af").
	The rest wait their turn, first come first served, and come in as one goes. A phone gets one:
	its screen is a third the size and the cards are not. ]]
NoticeLaneConfig.MaxVisible = 2
NoticeLaneConfig.MaxVisibleCompact = 1

--- Slot order, low on top. The persistent line first, so a card arriving never shoves it about.
NoticeLaneConfig.Order = {
	OfflineLabel = 1,
	CarryHint = 2,
	ShowroomSummary = 3,
	Discovery = 4,
}

NoticeLaneConfig.SlideIn = 0.4
NoticeLaneConfig.SlideOut = 0.3
--- A member moving up or down because one above it came or went.
NoticeLaneConfig.Shift = 0.2

return NoticeLaneConfig
