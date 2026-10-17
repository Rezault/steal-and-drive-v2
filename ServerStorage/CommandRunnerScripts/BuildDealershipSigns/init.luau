--[[
	BuildDealershipSigns — Command Runner command

	Authors the owner sign on every dealership plot: an invisible plate parented next to the header
	beam over the showroom entrance, carrying a SurfaceGui that reads

		(avatar)  <Name>'s Dealership          (pencil)
		          WORTH $2,880     (🤍 12)

	`PlotService` never builds this — it only writes the text and the headshot into it when a player
	claims the lot. The names it looks for live in `PlotConfig` (SignName, SignGuiName, SignTitleName,
	SignHeadshotName, SignEditButtonName, SignValueName, SignLikeButtonName, SignLikeIconName,
	SignLikeCountName); this command and that config are the two halves of one contract, so renaming a
	part here means renaming it there.

	RE-RUN THIS AFTER PULLING THE VALUATION OR THE LIKES CHANGE. The `Value` label and the `LikeButton`
	pill were both added after these signs were first authored, so a place built before them has signs
	with no such children. Nothing breaks in the meantime — `PlotService` treats both as optional
	precisely so an un-rebuilt sign keeps working — but no lot shows what it is worth, and nobody can
	like anybody, until this has been run once.

	WHY A SEPARATE PLATE INSTEAD OF A SURFACEGUI ON THE BEAM. The beam is a Blender MeshPart whose
	BOUNDING BOX is far bigger than its mesh — measured on Plot4, a 28.47 x 6.32 x 1.48 box around a
	plate that is really about 23.1 x 6.31 x 0.79. A SurfaceGui parented to it renders on the box
	face, which puts the canvas 0.35 studs in front of the mesh and hangs 2.7 studs of it off each end
	in mid-air. Worse, the front face is a TRAPEZOID: full width at the bottom, narrowing to roughly
	half by the top edge. So the sign gets its own thin invisible plate, sized to sit inside the real
	silhouette with margin, and placed just proud of the mesh surface so it cannot z-fight.

	HOW WIDE THE BEAM ACTUALLY IS, BY HEIGHT. Raycasts are no use here: this mesh is on
	`CollisionFidelity.Default`, whose hull covers the whole box, and the account cannot open the
	mesh either (`CreateEditableMeshAsync` — no permission). So the profile below was read off the
	render instead, by sinking a neon sheet 0.025 studs BEHIND the front face and photographing what
	still showed: whatever is visible is where the flat face has run out.

		y = -3.1 .. +0.2   half-width >= 12.2    <- the full-width body
		y = +1.25          half-width  >11
		y = +1.45          half-width   ~9.3
		y = +1.8           half-width   ~8.8     <- the sloped shoulders

	Note how fast it closes above y = +1.2. The shoulders come in at roughly 2 studs of half-width
	per stud of height, so the TOP CORNERS are the only part of this sign that has ever been tight
	and every stud of height costs four studs of usable width.

	WHY THE PLATE IS 16.4 WIDE AND NOT 18. An 18-wide plate topped out at y = +1.45 with about 0.3
	studs of clearance either side — inside the mesh, and measurably so, which is why this looked
	fine on paper for months. It does not look fine: 0.3 studs is a couple of pixels from the plaza,
	and the shoulder runs diagonally past the corner at 27°, so the true perpendicular gap was under
	0.15 studs. The corner read as sliced by the shoulder, and rounding it only sharpened the sliver
	of grey left in the gap.

	At `PIXELS_PER_STUD` 66 the plate is 16.36 x 4.0, its top edge drops to y = +1.25, and the
	corners clear by about 1.6 studs — roughly 0.7 perpendicular. It is a 9% smaller sign, which is
	the trade: this beam has no room at the top and the plate is already 0.4 studs off the bottom,
	so there is nowhere to move it to. Shrinking is the only lever.

	SCOPE: the six live plots under `workspace.Map.Plots`, and
	`ServerStorage.PlotUpgrades.PlotMaster`, the template new plots are cut from — miss that one and
	the next plot cut from it arrives wearing the previous shape of this sign. Dated snapshots
	(`PlotSync_Backup_*`, `Map_OLD_BACKUP`) are left alone on purpose.

	IDEMPOTENT. Run it as many times as you like — an existing sign is repositioned and its GUI
	rebuilt in place rather than duplicated. That matters because the plots get re-imported and
	copied around during map work, and a half-updated sign is worse than no sign.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Types = require(script.Types)

--[[ `UIAssets`, resolved at Run time. This command used to require nothing and spell every colour
	out as a local, which was right while the banner was flat fills; it now wears the kit's panel
	texture like the rest of the plot signage, so it needs the registry. Set by `Run`. ]]
local ASSETS: any = nil

-- === The map contract =======================================================

local PLOTS_PATH = { "Map", "Plots" }
local DEFAULT_HOST_NAME = "Cube.080" -- the header beam over the showroom entrance

-- Names PlotService looks for. Keep in sync with PlotConfig.Sign* .
local SIGN_NAME = "DealershipSign"
local GUI_NAME = "Sign"
local TITLE_NAME = "Title"
local HEADSHOT_NAME = "Headshot"
local EDIT_BUTTON_NAME = "EditButton"
local VALUE_NAME = "Value"
local LIKE_BUTTON_NAME = "LikeButton"
local LIKE_ICON_NAME = "Icon"
local LIKE_COUNT_NAME = "Count"

-- === Geometry ===============================================================

--[[ THE CANVAS IS THE FIXED THING, AND THE PLATE IS DERIVED FROM IT.

	Every offset in the layout below is an absolute pixel on a 1080 x 264 canvas, and the banner
	texture is drawn at exactly that size, so the canvas may not change — but the plate's PHYSICAL
	size is free, and changing it is how the sign is made to fit the beam. Raising `PIXELS_PER_STUD`
	shrinks the sign in the world and leaves the canvas, the layout and the art untouched.

	They used to be two independent constants that happened to agree (an 18 x 4.4 plate at 60 px per
	stud). Written this way the agreement cannot lapse.

	60 px per stud matched the ComingSoonSign, so text on the two signs was the same physical size.
	That is no longer true and the beam is the reason — see the header. ]]
local CANVAS = Vector2.new(1080, 264)
local PIXELS_PER_STUD = 66

-- Studs. Z is the plate's thickness; it only has to be non-zero.
local PLATE_SIZE = Vector3.new(CANVAS.X / PIXELS_PER_STUD, CANVAS.Y / PIXELS_PER_STUD, 0.05)

--[[ Where the plate sits in the BEAM'S OWN object space.

	The beam's Front face (its LookVector) points out over the forecourt, so the plate goes at
	NEGATIVE Z. The mesh surface is at z = -0.395; -0.43 puts the plate's mid-plane 0.035 proud of it
	and its front skin about 0.06 proud, which is clear of z-fighting without visibly floating.

	Y IS THE ONE NUMBER HERE WITH A REAL TRADE IN IT, and it is not "centre the sign on the beam".
	The beam's face closes at about 2 studs of half-width per stud of height (see the header), so
	every stud UP costs four studs of usable width at the top corners, while the bottom edge is
	straight and costs nothing. That is why this sat at -0.75 for so long: pushed down, away from
	the corners entirely.

	Pushed down too far, as it turned out. At -0.75 the banner had 1.35 studs of beam above it and
	0.54 below, and a lip that thin over the plaza opening reads as the sign running off the bottom
	rather than as a margin. -0.40 splits it about evenly — roughly 1.0 above, 0.9 below — and
	still leaves the top corners about 0.9 studs clear of the shoulders.

	Anything above about -0.2 starts eating that corner clearance faster than it improves the
	balance, and it is the corners that look broken first. ]]
local PLATE_OFFSET = CFrame.new(0, -0.40, -0.43)

-- === Look ===================================================================
--[[ The `car ui.psd` kit. This block used to say it was "lifted from the ComingSoonSign, which is
	itself the car ui.psd kit" — true when both signs were flat fills, and wrong since 2026-08-23,
	when the banner body became the kit's actual PANEL TEXTURE. The colours below are now only the
	things that sit ON that texture; the panel itself is `UIAssets.Upgrades.BannerPanel`.

	`COLOR_PANEL` (#364157) and `COLOR_PANEL_STROKE` were deleted with the flat fill they described.
	Nothing else referenced them — the border and rim they were imitating are drawn into the art. ]]

--[[ The kit's real face colour, sampled off the artist's own panel: every solid shape in that stack
	is this, and the depth comes from layer styles rather than from three different navies. Painted
	behind the banner texture so the 80% art has something to sit on other than the beam. ]]
local COLOR_PANEL_FACE = Color3.fromRGB(40, 51, 75) -- #28334B

--[[ The banner's corner radius, in CANVAS pixels — so it rides `CANVAS`, not the plate, and the
	sign shrinking in the world shrinks the radius with it and keeps the art in register. It is
	drawn into `UIAssets.Upgrades.BannerPanel` and repeated here as a `UICorner` on the panel's
	opaque background; the two must agree or the corners disagree by a pixel. Changing it means
	regenerating the texture with `assets/ui/upgrades/make_rounded_banner.py`, not just editing this
	number. ]]
local PANEL_RADIUS = 26
local COLOR_ACCENT = Color3.fromRGB(0, 102, 255) -- #0066FF
local COLOR_TEXT_STROKE = Color3.fromRGB(10, 20, 32)
local COLOR_TEXT = Color3.new(1, 1, 1)
-- #0DB415, the kit's money green (`UpgradeConfig.Colors.Done`). The valuation is the only thing on
-- this sign that is a cash figure, and money is green everywhere else in this game.
local COLOR_MONEY = Color3.fromRGB(13, 180, 21)

--[[ The likes pill. A chip a shade DARKER than the panel rather than a lighter one, so it reads as a
	recess in the banner instead of as a second button competing with the pencil — there is already
	one accent-blue rectangle on this sign and the eye should go to it first.

	The stroke is the only warm colour anywhere on the plot furniture, and it is doing the work the
	chip's fill deliberately is not: it is what makes a pill nobody has pressed look pressable from
	across the plaza. It is left off the filled state (see `PlotService`), so "already liked" is a
	flat chip with a red heart in it. ]]
--[[ DROPPED TO THE KIT'S OUTLINE NAVY ON 2026-08-23, because the panel moved under it. It was
	`#283142`, a shade darker than the old flat `#364157` body — but the kit's real face is `#28334B`,
	which is the same VALUE as that chip (luma 50 against 48), so the recess flattened into the panel
	and the likes count read as a smudge. `#151D2D` is the border colour already drawn into the panel
	texture, so the chip now reads as a hole punched in the banner rather than as a second surface. ]]
local COLOR_CHIP = Color3.fromRGB(21, 29, 45)
local COLOR_LIKE = Color3.fromRGB(255, 86, 120)

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

-- Preview only. Long-lived Roblox accounts, so the thumbnails are guaranteed to resolve.
local PREVIEW_HEADSHOT = "rbxthumb://type=AvatarHeadShot&id=%d&w=420&h=420"
local PREVIEW_USER_IDS = { 1, 156, 261, 2032622, 1516946 }
-- Preview only. Written as `GarageConfig.formatCash` would render them — the point of the widest
-- one is to prove the line does not collide with the pencil.
local PREVIEW_VALUES = { "$1,440", "$28,760", "$412,900", "$6.1M", "$2.7B" }
--[[ Preview only. Written as `PlotConfig.formatLikes` would render them. The point of the spread is
	the same as the valuations': the narrow end proves the pill does not look empty around a single
	digit, and the wide end proves a four-figure count still centres inside it. ]]
local PREVIEW_LIKES = { "3", "47", "612", "1,284", "8,905" }

--[[ U+00A0. Every space on the sign is one of these, and that is the ONLY thing keeping long names
	on a single line. PlotService does the same substitution when it writes an owner in — see the
	note on PlotConfig.SignNonBreakingSpace.

	TextScaled maximises size subject to the laid-out text fitting, and it will happily WRAP to get
	there: "SuperCoolGamer1234x's Dealership" came out as two lines at 37 px in preference to one
	line at 37 px. Roblox only breaks lines at spaces, so removing the break opportunities leaves
	shrinking as its only move.

	Two more obvious fixes were tried and measured, and neither works:
	  * TextWrapped = false silently clears TextScaled, dropping the label to the default TextSize
	    of 8 — it renders as unreadably tiny text, not as an unwrapped line.
	  * A UITextSizeConstraint MinTextSize above the two-line threshold does not help either;
	    TextScaled wraps first and the constraint is applied to the result. ]]
local NB_SPACE = utf8.char(0x00A0)

local function oneLine(text: string): string
	return (string.gsub(text, " ", NB_SPACE))
end

-- === Building ===============================================================

local function clearChildren(instance: Instance)
	for _, child in ipairs(instance:GetChildren()) do
		child:Destroy()
	end
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

--[[ Fill an (existing or fresh) SurfaceGui with the sign layout.

	Laid out left to right across the 1080 px canvas:

		 24 ..  224   circular headshot, 200 px
		240 ..  916   title over valuation, as a stacked pair
		706 ..  916   likes pill, 210 px — on the valuation's row, at the right end of it
		932 .. 1052   pencil button, 120 px

	Left-aligned rather than centred so the title does not slide sideways when the headshot appears
	on claim — the vacant sign and the owned sign put their first letter in exactly the same place.

	=== THE PILL SHARES THE VALUATION'S ROW, AND THAT IS A MEASURED FIT ========================

	The two boxes overlap on paper — the valuation label is 676 px wide because it inherited the
	title's column, and the pill starts 466 px into it — but the TEXT cannot reach. That label is
	left-aligned and NOT `TextScaled`, so what matters is how wide the string actually draws, and
	`GarageConfig.formatCash` puts a hard ceiling on it: past 100,000 it switches to a suffix, so
	there are only a handful of longest cases. Measured off the real label:

		"WORTH $99,999"   388 px, ends at x = 628
		"WORTH $999.9K"   394 px, ends at x = 634
		"WORTH $999.9M"   405 px, ends at x = 645   <- the widest string formatCash can produce

	So the tightest this ever gets is 61 px of clear air before the pill.

	Which is the thing to re-measure if anyone widens that band: raising `formatCash`'s suffix
	threshold, or making the valuation `TextScaled`, is what would let the two collide. Shrinking the
	label's box does not help and is not the fix — a TextLabel without `TextScaled` overflows its
	frame rather than clipping to it.

	The pill's own contents are checked the same way and have more room: the widest a like count can
	get is "999,999" at 179 px of the 210 px pill, because `PlotConfig.formatLikes` takes a suffix
	from a million upwards and "1.0M" is narrower than the number it replaced.

	The pill was put here rather than in the right-hand column beside the pencil for a reason that is
	not about space: see `PlotConfig.SignLikeButtonName`. It is one widget that every viewer sees, so
	it can never end up stacked on top of a pencil while a client decides which of the two to hide.

	=== THE MIDDLE COLUMN IS A STACK, AND THE STACK IS CENTRED AS A PAIR =======================

	Vertically, on the 264 px canvas:

		 54 .. 142    title, 88 px  (unchanged type size — see the size cap below)
		154 .. 210    valuation, 56 px

	The pair is centred together rather than each half being centred in its own band, so a VACANT
	lot — which shows the title and hides the valuation — has its one line sitting high rather than
	in the middle. That is deliberate and it is the one thing to look at if this ever gets re-tuned:
	the alternative is moving the title on claim, which makes the sign visibly jump the instant
	somebody walks up to it.

	IT IS NOT A UIListLayout. A layout would re-centre the title when the valuation is hidden, which
	is exactly the jump above, and the two labels are also different type sizes with a deliberate gap
	rather than a uniform run. Two fixed offsets are less machinery and cannot surprise anyone. ]]
local function buildGui(part: BasePart): SurfaceGui
	local gui = part:FindFirstChild(GUI_NAME)
	if not (gui and gui:IsA("SurfaceGui")) then
		if gui then
			gui:Destroy()
		end
		gui = Instance.new("SurfaceGui")
		gui.Name = GUI_NAME
	end
	clearChildren(gui)

	gui.Face = Enum.NormalId.Front
	--[[ Written rather than left alone because a rebuild REUSES an existing SurfaceGui, and a
		`false` left on it by anyone — a debug session, a builder hiding it to work behind it —
		survives every re-run and reads as "the command silently did nothing". ]]
	gui.Enabled = true
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0 -- read the same at night as at noon
	gui.Brightness = 1
	gui.AlwaysOnTop = false
	gui.ZOffset = 0.05
	gui.MaxDistance = 0 -- never fade out; it is the lot's nameplate
	gui.ClipsDescendants = false
	--[[ THE ONE PROPERTY THAT DECIDES WHETHER THE PENCIL WORKS. A SurfaceGui in Workspace takes no
		input at all unless it is `Active`, and a dead button on a live sign looks exactly like an
		unbound controller — the upgrade boards carry the same line and `UpgradeController` note 3
		says the same thing. Off would make the edit button decoration. ]]
	gui.Active = true
	gui.Parent = part

	--[[ THE BANNER BODY IS THE KIT'S PANEL TEXTURE — 2026-08-23, and it is the only thing about this
		sign that changed. Everything laid out below it is untouched.

		It was a flat `#364157` fill with a `UICorner` and a light `UIStroke`, which is what this whole
		kit's panels LOOK like from a distance but is not what they are: the real thing carries a 5px
		`#151D2D` border, a 5px `#384769` inner rim and a faint woven overlay, none of which two
		properties can approximate. It was the last flat-fill surface on a plot.

		IT KEEPS ITS ROUNDED CORNERS, and this is the one sign in the game where that is right. The
		beam it is bolted to is CHAMFERED — its ends slope away — and a square corner runs straight
		into that slope. It wore a 26px `UICorner` for that reason long before it had real art. The
		upgrade billboard sits in a square neon aperture and the garage-door sign sits on a flat door,
		so both of those are square; here the roundness answers the mesh rather than the mockup.

		THE RADIUS IS IN THE TEXTURE, NOT IN A `UICorner`. A `UICorner` clips the element, so it would
		slice through the 5px border drawn into the art and leave four bare corners of face colour.
		The border and the inner rim each follow the curve instead — see `UIAssets.Upgrades` and
		`assets/ui/upgrades/make_rounded_banner.py`.

		THE BACKGROUND IS OPAQUE BEHIND IT, for the reason the coming-soon sign documents at length:
		every navy surface in this kit is drawn at 80% so gameplay shows faintly through a page you
		opened, and on a world sign that just lets the beam behind it wash the navy out. ]]
	local panel = Instance.new("ImageLabel")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.Image = ASSETS.url(ASSETS.Upgrades.BannerPanel)
	-- The canvas is 1080x264 and the texture is drawn at exactly that, so the stretch is identity.
	panel.ScaleType = Enum.ScaleType.Stretch
	panel.BackgroundColor3 = COLOR_PANEL_FACE
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Parent = gui

	--[[ AND THIS ROUNDS THE OPAQUE BACKGROUND, WHICH IS THE ONLY THING IT IS FOR. The art's own alpha
		is already rounded; the `BackgroundColor3` above is not, so without this the sign draws four
		square navy corners poking out from behind a rounded texture. Same radius as the art
		(`PANEL_RADIUS`) so the two silhouettes coincide exactly — change one and change the other, or
		the corners disagree by a pixel and it reads as a bad crop. ]]
	corner(panel, UDim.new(0, PANEL_RADIUS))

	local headshot = Instance.new("ImageLabel")
	headshot.Name = HEADSHOT_NAME
	headshot.AnchorPoint = Vector2.new(0, 0.5)
	headshot.Position = UDim2.new(0, 24, 0.5, 0)
	headshot.Size = UDim2.fromOffset(200, 200)
	headshot.BackgroundColor3 = COLOR_ACCENT
	headshot.BackgroundTransparency = 0
	headshot.BorderSizePixel = 0
	headshot.Image = "" -- PlotService fills this from the owner's UserId
	headshot.ScaleType = Enum.ScaleType.Fit
	headshot.Visible = false -- vacant until claimed
	headshot.Parent = panel
	corner(headshot, UDim.new(1, 0)) -- circle
	stroke(headshot, COLOR_ACCENT, 5, 0)

	local title = Instance.new("TextLabel")
	title.Name = TITLE_NAME
	title.AnchorPoint = Vector2.new(0, 0.5)
	-- -34 lifts the title to make room for the valuation under it; see the stack note above.
	title.Position = UDim2.new(0, 240, 0.5, -34)
	--[[ The height doubles as the maximum text size — one line of ~88 px is what fills this banner.
		Keeping the name ON one line is a separate problem, solved by the non-breaking spaces in
		NB_SPACE below; see that note for why the obvious fixes do not work. ]]
	title.Size = UDim2.fromOffset(676, 88)
	title.BackgroundTransparency = 1
	title.BorderSizePixel = 0
	title.Text = oneLine("Available Lot") -- matches PlotConfig.SignVacantText
	title.TextColor3 = COLOR_TEXT
	title.FontFace = FONT
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = panel
	stroke(title, COLOR_TEXT_STROKE, 2, 0.55)

	--[[ Cap the size so short and long names look like one set of signs rather than six unrelated
		ones — uncapped, "Al's Dealership" would tower over "Bartholomew's Dealership". ]]
	local sizeCap = Instance.new("UITextSizeConstraint")
	sizeCap.MaxTextSize = 88
	sizeCap.MinTextSize = 24
	sizeCap.Parent = title

	--[[ The valuation, under the title — what everything in this dealership would sell for.

		HIDDEN UNTIL CLAIMED, like the headshot and the pencil: an empty lot is worth nothing and
		"WORTH $0" on five vacant signs reads as a broken feature rather than an honest zero.

		`PlotService` writes the text, from `PlotConfig.SignValueFormat` — the word is there and not
		here so that changing it does not need this command re-run. What this builds is the widget.

		NOT `TextScaled`. The title is scaled because a display name can be any length; a cash figure
		is at most about nine characters through `formatCash` ("$999,999" then "$1.2M"), so a fixed
		56 px keeps every sign's second line the same physical size — which is what makes six lots
		comparable at a glance from across the plaza. It is the one number a player is meant to be
		able to compare between signs. ]]
	local value = Instance.new("TextLabel")
	value.Name = VALUE_NAME
	value.AnchorPoint = Vector2.new(0, 0.5)
	value.Position = UDim2.new(0, 240, 0.5, 50)
	value.Size = UDim2.fromOffset(676, 56)
	value.BackgroundTransparency = 1
	value.BorderSizePixel = 0
	value.Text = ""
	value.TextColor3 = COLOR_MONEY
	value.FontFace = FONT
	value.TextSize = 56
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextYAlignment = Enum.TextYAlignment.Center
	value.Visible = false -- vacant until claimed
	value.Parent = panel
	stroke(value, COLOR_TEXT_STROKE, 2, 0.55)

	--[[ The pencil. It is written VISIBLE TO EVERYONE on a claimed lot by `PlotService`, and hidden
		again on lots you do not own by `DealershipSignController` — a local write, because whose lot
		it is differs per client. That is cosmetic and nothing more: a hidden button is not access
		control, and `PlotService._onRename` refuses a rename from anyone not holding the plot.

		The click needs `gui.Active` above, which is easy to lose in a re-author and impossible to
		see in the Explorer. ]]
	--[[ The likes pill: a heart and a number, and pressing it is how you like somebody's dealership.

		A BUTTON EVEN THOUGH THE OWNER CANNOT PRESS THEIR OWN. `PlotConfig.Likes` has the design; what
		it means for this file is that the pill is built once and shown to everybody, and only its
		HEART changes per viewer. There is no owner-only variant of this widget to author and no
		second copy of it to keep in step.

		HIDDEN UNTIL CLAIMED, like the headshot, the valuation and the pencil — a vacant lot belongs to
		nobody, so there is nobody to like.

		THE TWO LABELS ARE SEPARATE INSTANCES rather than one string like "🤍 12", and that is the
		whole reason the split works: the SERVER writes the count onto this replicated GUI for
		everyone, and each CLIENT writes the heart locally for itself. One label holding both would
		mean whichever side wrote last erased the other's half.

		Centred by a UIListLayout, which is the one place on this sign a layout is the right tool. The
		note on the title/valuation stack explains why it is the wrong one there — a layout re-centres
		when a sibling is hidden, and that band hides its second line on a vacant lot. Nothing inside
		this pill is ever hidden; what changes is the WIDTH of the count as it goes from "9" to
		"1,284", and re-centring for that is exactly what you want. ]]
	local like = Instance.new("TextButton")
	like.Name = LIKE_BUTTON_NAME
	--[[ Right edge flush with the title column's (916), on the valuation's row. See the layout note
		above. Centre-anchored, so the press in `DealershipSignController._pop` shrinks it into its own
		middle rather than towards that edge; 811 is 916 less half the width. ]]
	like.AnchorPoint = Vector2.new(0.5, 0.5)
	like.Position = UDim2.new(0, 916 - 210 / 2, 0.5, 50)
	like.Size = UDim2.fromOffset(210, 64)
	like.BackgroundColor3 = COLOR_CHIP
	like.BorderSizePixel = 0
	like.AutoButtonColor = true
	like.Text = "" -- the two labels below carry it; this is the hit area and the chip
	like.Visible = false -- vacant until claimed
	like.Parent = panel
	corner(like, UDim.new(1, 0))
	--[[ The pressable affordance, and `DealershipSignController` fades it out once this viewer has
		already liked this dealership. Found there by CLASS and not by name — it is the only UIStroke
		inside this button, so there is no third string for the two files to disagree about. ]]
	stroke(like, COLOR_LIKE, 3, 0)

	local likeLayout = Instance.new("UIListLayout")
	likeLayout.FillDirection = Enum.FillDirection.Horizontal
	likeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	likeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	likeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	likeLayout.Padding = UDim.new(0, 10)
	likeLayout.Parent = like

	--[[ The heart. Written by the CLIENT and by nothing else once a player is looking at it — what is
		built here is the un-liked state, which is also the correct thing for a viewer whose controller
		has not bound yet to be looking at.

		A TextLabel does not sink input, so this sitting on top of the button costs the button nothing.
		Sized in offset like everything else on this sign; nothing here may be scale-sized. ]]
	local likeIcon = Instance.new("TextLabel")
	likeIcon.Name = LIKE_ICON_NAME
	likeIcon.LayoutOrder = 1
	likeIcon.Size = UDim2.fromOffset(44, 44)
	likeIcon.BackgroundTransparency = 1
	likeIcon.BorderSizePixel = 0
	likeIcon.Text = "🤍" -- matches PlotConfig.Likes.Icon
	likeIcon.TextColor3 = COLOR_TEXT
	likeIcon.FontFace = FONT
	likeIcon.TextSize = 40
	likeIcon.Parent = like

	--[[ The count, written by `PlotService` from `PlotConfig.formatLikes`. `AutomaticSize` on X so the
		layout can keep the pair centred as the number grows — a fixed box would leave "9" hanging off
		one side of a pill built for "1,284". ]]
	local likeCount = Instance.new("TextLabel")
	likeCount.Name = LIKE_COUNT_NAME
	likeCount.LayoutOrder = 2
	likeCount.Size = UDim2.fromOffset(0, 48)
	likeCount.AutomaticSize = Enum.AutomaticSize.X
	likeCount.BackgroundTransparency = 1
	likeCount.BorderSizePixel = 0
	likeCount.Text = "0"
	likeCount.TextColor3 = COLOR_TEXT
	likeCount.FontFace = FONT
	likeCount.TextSize = 44
	likeCount.Parent = like

	local edit = Instance.new("TextButton")
	edit.Name = EDIT_BUTTON_NAME
	--- Right edge 28 in from the panel's, centre-anchored like every button (house rule).
	edit.AnchorPoint = Vector2.new(0.5, 0.5)
	edit.Position = UDim2.new(1, -28 - 120 / 2, 0.5, 0)
	edit.Size = UDim2.fromOffset(120, 120)
	edit.BackgroundColor3 = COLOR_ACCENT
	edit.BorderSizePixel = 0
	edit.AutoButtonColor = true
	edit.Text = "✏️"
	edit.TextColor3 = COLOR_TEXT
	edit.FontFace = FONT
	edit.TextSize = 72
	edit.Visible = false -- vacant until claimed
	edit.Parent = panel
	corner(edit, UDim.new(0, 26))

	return gui
end

--[[ Put the plate in the world next to `host`, reusing one that is already there.

	Reuse rather than replace so a sign that has been nudged in Studio is snapped back to spec
	instead of being deleted and re-created — re-creating would break any reference to it and would
	churn the undo history for what is usually a no-op re-run. ]]
local function buildPlate(host: BasePart): BasePart
	local parent = host.Parent
	local existing = parent and parent:FindFirstChild(SIGN_NAME)

	local part: BasePart
	if existing and existing:IsA("BasePart") then
		part = existing
	else
		if existing then
			existing:Destroy()
		end
		part = Instance.new("Part")
		part.Name = SIGN_NAME
	end

	part.Size = PLATE_SIZE
	part.Anchored = true
	part.CanCollide = false
	--[[ QUERYABLE, AND IT HAS TO BE — this line used to read `false`, with "never block a raycast"
		next to it, and that made the pencil undressable: A SURFACEGUI'S BUTTONS ARE REACHED BY THE
		MOUSE'S OWN RAY, so a plate the mouse cannot hit renders a sign that cannot be pressed. It is
		the identical failure `BuildPlotUpgradeSigns` documents on its own screen plate, and it looks
		exactly like an unbound controller from the outside.

		The cost is a thin invisible pane in front of the entrance beam that raycasts can now hit. The
		only probe in this project that casts anywhere near it is `PlotService._resolveSpawn`, which
		fires straight down at the FORECOURT (plot-local z = -30, well out in front of the building)
		and only on a plot with no authored `PlotSpawn` — so nothing today is looking through this. ]]
	part.CanQuery = true
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Transparency = 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	--[[ Safe to write CFrame directly: this part is freshly made or was made by a previous run, and
		nothing is ever welded to it. On an already-welded part this line would drag the whole
		assembly instead of moving the part. ]]
	part.CFrame = host.CFrame * PLATE_OFFSET
	part.Parent = parent

	buildGui(part)
	return part
end

-- === Command ================================================================

return {
	AutoRecordChanges = true,
	Description = "Author the owner sign (avatar + '<Name>'s Dealership' + valuation + likes pill + pencil) on the entrance beam of every plot in Map.Plots. Idempotent — re-run after any map re-import, and once after pulling the likes change.",
	Tags = { "Plots", "UI" },
	Arguments = {
		HostName = {
			Type = "string",
			Default = DEFAULT_HOST_NAME,
			LayoutOrder = 1,
			ClearTextOnFocus = false,
			Description = "Name of the beam MeshPart inside each plot to hang the sign on. The plate is placed in this part's own object space, so all six plots line up regardless of how each one is rotated.",
		},
		Preview = {
			Type = "boolean",
			Default = false,
			LayoutOrder = 2,
			Description = "Fill every sign with placeholder owner text so the built sign can be judged in Studio without joining a game. Off = leave them reading 'Available Lot', which is what an unclaimed lot shows at runtime.",
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()

		--[[ Checked down to the one entry this file needs, rather than left to fail as a nil index in
			the middle of the draw. Edit mode caches a required module, so a `UIAssets` from before
			`Upgrades.BannerPanel` existed means the Command Runner wants reconnecting — which is a
			one-line fix that looks like a mystery if the error comes from somewhere else. ]]
		local shared = ReplicatedStorage:FindFirstChild("shared")
		local configs = shared and shared:FindFirstChild("Configs")
		local module = configs and configs:FindFirstChild("UIAssets")
		local assetsOk, assets = pcall(require, module)
		if not (assetsOk and type(assets) == "table" and assets.Upgrades and assets.Upgrades.BannerPanel) then
			out:error(
				"Could not require ReplicatedStorage.shared.Configs.UIAssets, or it predates UIAssets.Upgrades.BannerPanel — is Rojo syncing, and has the Command Runner been reconnected?"
			)
			return
		end
		ASSETS = assets

		local folder: Instance = workspace
		for _, name in ipairs(PLOTS_PATH) do
			local nextFolder = folder:FindFirstChild(name)
			if not nextFolder then
				out:error(string.format("No workspace.%s — nothing to build on.", table.concat(PLOTS_PATH, ".")))
				return
			end
			folder = nextFolder
		end

		local hostName = arguments.HostName
		if type(hostName) ~= "string" or hostName == "" then
			hostName = DEFAULT_HOST_NAME
		end

		local built, missing = {}, {}
		for _, plot in ipairs(folder:GetChildren()) do
			if not plot:IsA("Model") then
				continue
			end
			local host = plot:FindFirstChild(hostName, true)
			if not (host and host:IsA("BasePart")) then
				table.insert(missing, plot.Name)
				continue
			end
			table.insert(built, buildPlate(host))
		end

		--[[ The template new plots are cut from. It is not under `workspace.Map.Plots` and so was
			outside every previous run of this command, which did not matter while the sign's shape
			never changed and mattered the moment it did: a plot re-cut from a stale master arrives
			carrying the OLD sign, and looks like this command failing on one lot for no reason.

			`BuildComingSoonSigns` has covered it from the start; this is the same scope. Dated
			snapshots (`PlotSync_Backup_*`, `Map_OLD_BACKUP`) are deliberately NOT touched — a
			snapshot that quietly changes underneath you is not a snapshot. ]]
		local store = ServerStorage:FindFirstChild("PlotUpgrades")
		local master = store and store:FindFirstChild("PlotMaster")
		local masterHost = master and master:FindFirstChild(hostName, true)
		local builtMaster = false
		if masterHost and masterHost:IsA("BasePart") then
			buildPlate(masterHost) -- no preview text: the template ships in the vacant state
			builtMaster = true
		elseif master then
			out:warn(string.format("PlotMaster has no BasePart named '%s' — its sign is now stale.", hostName))
		end

		if #built == 0 then
			out:error(string.format("Found no plot containing a BasePart named '%s'.", hostName))
			return
		end

		--[[ Placeholder text is applied AFTER the build rather than baked into `buildGui`, so the
			built-and-never-previewed state is exactly the vacant state a player sees. ]]
		if arguments.Preview then
			for index, part in ipairs(built) do
				local panel = part:FindFirstChild(GUI_NAME) and part[GUI_NAME]:FindFirstChild("Panel")
				if panel then
					panel[TITLE_NAME].Text = oneLine(string.format("Player%d's Dealership", index))
					-- A real thumbnail, not a coloured circle: the headshot is the one element whose
					-- framing and crop can only be judged against an actual avatar.
					panel[HEADSHOT_NAME].Image = string.format(PREVIEW_HEADSHOT, PREVIEW_USER_IDS[(index - 1) % #PREVIEW_USER_IDS + 1])
					panel[HEADSHOT_NAME].Visible = true
					panel[EDIT_BUTTON_NAME].Visible = true
					--[[ Deliberately spans the widths a real valuation reaches — a starting lot, a
						mid-game one, and one deep enough to have crossed into `formatCash`'s suffix
						band. The narrow and wide ends are the only two worth eyeballing, and a
						preview that showed six identical figures would prove nothing about either. ]]
					panel[VALUE_NAME].Text = string.format(
						"WORTH %s",
						PREVIEW_VALUES[(index - 1) % #PREVIEW_VALUES + 1]
					)
					panel[VALUE_NAME].Visible = true

					--[[ The un-liked state, which is what the server paints and what every viewer sees
						until their own client tells them otherwise. The filled heart is per-viewer and
						therefore not something a Studio preview can honestly show. ]]
					local like = panel[LIKE_BUTTON_NAME]
					like[LIKE_COUNT_NAME].Text = PREVIEW_LIKES[(index - 1) % #PREVIEW_LIKES + 1]
					like.Visible = true
				end
			end
		end

		pcall(function()
			props:SetSelection(built)
			props:FocusView(built)
		end)

		if #missing > 0 then
			out:warn(string.format("No '%s' in: %s — those plots have no sign.", hostName, table.concat(missing, ", ")))
		end
		out:print(string.format(
			"Built %d dealership sign(s) on '%s'%s%s. PlotService fills them in on claim.",
			#built,
			hostName,
			builtMaster and " (plus PlotMaster)" or "",
			arguments.Preview and " with preview text" or ""
		))
	end,
} :: Types.ScriptModule
