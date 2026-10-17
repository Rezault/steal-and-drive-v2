--[[
	SpeedoConfig
	------------
	THE SPEED READOUT ON THE DRIVING SCREEN: a number and a segmented bar in a rounded panel, in
	place of the half-dial gauge the HUD has worn since the art was first imported.

	IT REPLACES A DIAL BECAUSE THE DIAL WAS NOT EARNING ITS SIZE. `SpeedoBase.png` is a 160-mph
	semicircle centred along the bottom of the screen, and the car lives in a band a third of the
	way across it: cruise is 42-51 mph and a boosted Lambo peaks at 65 (see `DriveConfig.Gearbox`),
	so five sixths of that drawing is empty road the player is never going to reach. The needle it
	was drawn for is already gone, the fuel gauge and the tach either side of it are already gone,
	and what is left is a large piece of furniture in the middle of the screen holding two numbers.

	THE SHAPE AND THE PALETTE BELOW ARE SAMPLED FROM THE REFERENCE Aleafo posted and Dylan signed
	off ("that looks clean", 2026-09-17): a light-blue panel with a heavy navy border, a big white
	number with `MPH` tucked in beside it, and a row of segments under it that lights up from the
	left. Every colour in `Panel`, `Readout` and `Bar` is a pixel read off that image rather than a
	guess, which is why they are not the kit's own `#0066FF` — the reference is a brighter, cyaner
	blue and it is the one that was approved. If it ever has to come back to the kit, `Face.Top` and
	`Face.Bottom` are the two values to move.

	=== THE SEGMENTS ARE A REV BAR, NOT A PROGRESS BAR =========================================

	A progress bar answers "how far along". This one answers "how much is left", which is a
	different question and is why the top of it is painted red whether or not the car has got there
	yet. `Redline` segments are ALWAYS drawn — dim red below the car's speed, hot red once it
	reaches them — so the bar shows the player where the car's ceiling is from the moment the race
	starts, the same way a tach's redline does. A bar whose top band only appeared once you were in
	it would be telling you something you already knew.

	That is also why `ScaleTop` is not the gearbox's `TopMph`. The gearbox's number means "all six
	gears used" and the car reaches it; a bar that pegs on every straight reads as broken. 90 puts
	cruise a little under halfway, boost at about three quarters, and the redline exactly where a
	boosted Lambo tops out (65 mph, measured). A faster car pegs it, which is the honest answer.

	=== NO GEAR, AND THAT IS THE POINT =========================================================

	Aleafo: "we arent gonna have gears". The chassis has none — the gear on the old dial was
	simulated by `AutomaticGearbox` purely so the dial had something to show — so the readout is the
	speed alone. `AutomaticGearbox` stays where it is: the engine note still uses it, and that IS a
	real thing the player hears.

	=== WHERE IT SITS, AND WHAT MOVED OUT OF THE WAY ===========================================

	Bottom right (Dylan). That is the corner the control legend was in, so the legend moved to the
	bottom LEFT in the same change — see `LegendConfig.Panel.Corner`. The right-hand corner is
	spoken for from here on: the nitro readout is coming to sit beside this panel.

	THE INSTANCES ARE AUTHORED IN STUDIO like the rest of this HUD, not built in Luau.
	`BuildSpeedoV2` makes them from the numbers below and `DrivingHudController` only finds and
	fills them, which is the standing contract for `StarterGui.DrivingHud` (see
	`assets/ui/driving/README.md`). Change a number here and RE-RUN THE COMMAND; the controller will
	not redraw a panel that was built from the old ones.
]]

local SpeedoConfig = {}

--[[ WHICH READOUT IS LIVE, and it is an A/B switch rather than a setting.

	`Bar` is this file: the panel `BuildSpeedoV2` builds. `Dial` is the old `Cluster` — the
	half-gauge, the number, the unit, the gear and the AUTO chip — left in the place so the change
	can be looked at both ways in one playtest. `DrivingHudController._attachSpeedo` shows one and
	hides the other's art.

	WHEN ONE OF THESE WINS, DELETE THE LOSER AND THIS SWITCH. Same standing rule as
	`NitroConfig.Hud.Layout`, which is the flag this one is modelled on: a flag that outlives its
	experiment is just a second thing that has to keep working.

	NOTE WHAT `Dial` DOES **NOT** HIDE — the `Cluster` frame itself. It is transparent and empty of
	its own accord, and the vertical nitro bar hangs off it (`NitroConfig.Hud.Bars.Vertical`) because
	the cluster's `UIAspectRatioConstraint` is the only frame on this screen measured against the
	viewport's height. Hiding the frame would take the nitro with it. The bar therefore stands on
	its own until the nitro is moved up beside this panel, which is the next job. ]]
SpeedoConfig.Style = "Bar" :: "Bar" | "Dial"

--- The panel `BuildSpeedoV2` writes, as a direct child of the `DrivingHud` ScreenGui — a SIBLING of
--- `Controls` rather than a child, for the reason the nitro bar is one: `_applyTouchOnly` hides the
--- whole `Controls` frame on a keyboard, and a speedo is a readout every device needs.
SpeedoConfig.FrameName = "SpeedoV2"

--- What the `Bar` style hides inside the old `Cluster`, by name. The frame itself is not on this
--- list and must not be — see `Style`.
SpeedoConfig.DialParts = { "Dial", "Speed", "SpeedUnit", "Gear", "Mode" }

--[[ === THE SCALE ============================================================================

	`ScaleTop` is the mph the bar treats as full, and `Redline` is where the red band starts as a
	fraction of it. Both are DISPLAY constants: nothing on the car is in mph (`DriveConfig`
	§MinSpeedFraction spells out why at length), so these are measured against a playtest rather
	than read off a rig.

	90 and 0.74 put the redline at 66.6 mph, which is a hair over the 65 a boosted Lambo was
	measured at. So the bar fills to about half on cruise, three quarters under boost, and only a
	stolen car from a higher tier gets into the red. ]]
SpeedoConfig.ScaleTop = 90
SpeedoConfig.Redline = 0.74

--[[ How fast the readout chases the car, per second, and how much of a segment the bar has to
	cross before it commits to lighting it.

	The number and the bar share the smoothing so they can never disagree by a segment. The
	old cluster's own 14 is kept: landing instantly reads as a number flickering rather than as an
	instrument, and anything slower lags the throttle.

	`SegmentBias` is where inside a segment the threshold sits, 0 lighting it the instant the car
	touches its bottom edge and 1 only at its top. Half — round to nearest — makes the top-most lit
	segment the one the speed is actually IN, which is what a player reading the bar's tip expects.
	It also halves the dwell either side of a boundary, and the 14-per-second chase is already
	enough damping that the tip does not stutter. ]]
SpeedoConfig.Lerp = 14
SpeedoConfig.SegmentBias = 0.5

--[[ === THE PANEL ============================================================================

	SIZED IN SCALE ON BOTH AXES WITH AN ASPECT CONSTRAINT, which is how `Cluster` is built and for
	the same reason: a readout that changes shape with the viewport reads as a different instrument
	on every device. `AspectRatio` is width over height.

	BOTH SCALE AXES MUST BE NON-ZERO. `FitWithinMaxSize` takes the smaller of the two boxes the
	scales describe, and a zero on either axis collapses the panel to nothing rather than resolving
	it from the aspect — a trap this project has already paid for once (see `LegendConfig.Row.Glyph`).
	At 1920x1080 the pair below resolve to the same 300x128, which is deliberate: they are one box
	written twice, so nudging one axis in Studio without the other is visible immediately.

	`Margin` is the gap from the two screen edges the corner touches, in the screen's own axes. The
	X is the getaway card's and the legend's 0.017 so the right-hand furniture lines up on one
	vertical; the Y is a little more, because the bottom edge of a television is the one most likely
	to be eaten by overscan. ]]
SpeedoConfig.Panel = {
	Size = Vector2.new(0.156, 0.119),
	AspectRatio = 2.34,
	Corner = "BottomRight" :: "BottomRight" | "BottomLeft" | "TopRight" | "TopLeft",
	Margin = Vector2.new(0.017, 0.035),

	--[[ The face, top to bottom. Drawn as a `UIGradient` over a WHITE background rather than as a
		tint over a coloured one, because a `UIGradient` MULTIPLIES: over white the ramp IS the
		colour and both stops can be read straight off this table, where over a coloured fill
		neither of them would be the value on screen. ]]
	Face = {
		Top = Color3.fromRGB(92, 222, 254),
		Bottom = Color3.fromRGB(38, 164, 252),
	},

	--[[ The heavy navy border, which is the whole reason this panel reads as an object over a road
		rather than as a blue smear on it. In PIXELS, because a `UIStroke` is in pixels and ignores
		`UIScale` besides — a hairline is a hairline everywhere, and this is the one number in this
		file that is not a fraction of something.

		`Round` join, not `Miter`: a mitred stroke squares off the outside of a rounded rim (that is
		what miter is FOR, and it belongs on text outlines, where it is used below). ]]
	Border = Color3.fromRGB(2, 17, 74),
	BorderThickness = 4,

	--- A fraction of the panel's own HEIGHT, since `UICorner`'s scale resolves against the shorter
	--- side — so the curve is the same shape whatever the viewport does to the panel's pixels.
	CornerRadius = 0.22,
}

--[[ === THE NUMBER ===========================================================================

	`42` big, `MPH` small and tucked in at its baseline, which is the reference's arrangement and is
	the one that survives the number changing width: the pair are NOT centred as a group, because a
	group that re-centres itself every time the speed crosses 100 is a readout that jitters. The
	number is right-aligned into a fixed box and the unit is left-aligned beside it, so the only
	thing that moves when 99 becomes 100 is the left edge of the digits.

	Every rect below is a fraction of the PANEL. Ubuntu Bold is the kit's type, everywhere, no
	exceptions (see the theme note in `UIAssets`), and it ships with Roblox so nothing is uploaded.

	THE OUTLINE IS MITRED, and that is the one place miter is right: a mitred `UIStroke` on text
	keeps the sharp interior corners of the glyphs, where `Round` sands them off and the digits go
	soft at HUD size. ]]
SpeedoConfig.Readout = {
	Color = Color3.fromRGB(255, 255, 255),
	Outline = Color3.fromRGB(2, 17, 74),

	--- Both in pixels, for the reason `Panel.BorderThickness` is.
	OutlineThickness = 3,
	UnitOutlineThickness = 2,

	--- The digits: anchored at their RIGHT edge so they grow leftwards into the panel's air rather
	--- than pushing the unit around.
	Number = {
		Anchor = Vector2.new(1, 0.5),
		Position = Vector2.new(0.605, 0.31),
		Size = Vector2.new(0.52, 0.46),
	},

	--- `MPH`, anchored at its BOTTOM LEFT and sat on the digits' baseline.
	Unit = {
		Anchor = Vector2.new(0, 1),
		Position = Vector2.new(0.625, 0.50),
		Size = Vector2.new(0.30, 0.19),
	},
	UnitText = "MPH",

	--- What the panel reads in the Explorer, so a freshly built one looks like the finished thing
	--- rather than like a bug. The reference's own number.
	Placeholder = "42",
}

--[[ === THE BAR ==============================================================================

	A dark well with N segments in it. The well's rect is a fraction of the panel; everything inside
	the well is a fraction of the well.

	`Count` 20 with `Redline` 0.74 puts five segments in the red band, which is what the reference
	draws. It is also about the most a 258px bar can hold and still read as separate marks at a
	glance — past that the gaps close up and it becomes a plain fill with a texture on it.

	`Gap` is a fraction of one segment's PITCH rather than a width of its own, so changing `Count`
	does not also change how the bar is spaced. ]]
SpeedoConfig.Bar = {
	Position = Vector2.new(0.5, 0.745),
	Anchor = Vector2.new(0.5, 0.5),
	Size = Vector2.new(0.86, 0.30),

	--- The well behind the segments, and the inset that keeps them off its border.
	Well = Color3.fromRGB(20, 54, 117),
	WellBorder = Color3.fromRGB(2, 17, 74),
	WellBorderThickness = 3,
	--- Fractions of the well's own height and width. A curve under the segments' own, so the well
	--- reads as a slot they sit in rather than as a pill they are floating on.
	WellCornerRadius = 0.18,
	Inset = Vector2.new(0.014, 0.11),

	Count = 20,
	Gap = 0.28,
	--- Fraction of a segment's SHORTER side, i.e. its width — so the marks keep the same corner at
	--- any panel size.
	SegmentCornerRadius = 0.28,

	--[[ FOUR COLOURS FOR TWO BANDS x TWO STATES, and the asymmetry between the two bands IS the
		design rather than an oversight.

		The blue band is an ordinary readout and its unlit state recedes: `Lit` is a pale cyan and
		`Unlit` is a dark muted blue that sits back into the well. THE RED BAND'S UNLIT STATE DOES
		NOT RECEDE — `RedlineUnlit` is a full-strength red, the reference's own, because those marks
		are a warning about where the car's ceiling is and a warning that only appears once you have
		arrived is not one (see the header).

		So "lit" is not a brightness on this bar, it is a BLEACH: both lit states are the band's
		colour washed towards white, which is the one move that reads as "the needle has passed
		this" on a pale cyan and on a saturated red alike. Going the other way — brightening — has
		nowhere to go from a red that is already at full strength. ]]
	Lit = Color3.fromRGB(175, 240, 253),
	Unlit = Color3.fromRGB(74, 122, 178),
	RedlineLit = Color3.fromRGB(255, 138, 152),
	RedlineUnlit = Color3.fromRGB(222, 40, 76),

	--- How many segments are lit when the panel is sat in the Explorer with nothing driving it.
	--- The reference's own 42 of 90, rounded — so a freshly built panel matches the picture.
	PreviewLit = 9,
}

return SpeedoConfig
