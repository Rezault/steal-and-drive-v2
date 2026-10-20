--[[
	UpgradeService  (server)
	------------------------
	The billboard on every dealership forecourt, and the four things it sells.

	It is deliberately NOT where an upgrade level is stored. `GarageService` owns the profile's
	`Garage` table and is the only thing that writes cash, so the levels live there (`getUpgrades` /
	`setUpgradeLevel`) and this service decides WHEN they change and what changes with them — the
	same split `RewardService` has with car XP. What is left here is the three things nothing else
	can do:

	=== 1. THE BOARD =========================================================================

	Authored by the `BuildPlotUpgradeSigns` command, filled in here. The sign is a billboard lifted
	out of `Workspace.Worlds.FuturisticCity` and stood on the forecourt of all six plots; its four
	corner tiles are the four entries in `UpgradeConfig.Order`. This service only ever writes TEXT,
	a bar width and a colour into instances that already exist — the same split the dealership sign,
	the collect mats and the race pads all make, and for the same reason.

	It is PUBLIC. A SurfaceGui in Workspace replicates to everyone, so a visitor standing on your lot
	reads your levels off it, exactly as they read your name off the sign over the door. That is the
	point of a billboard. The BUTTONS are owner-only and that is checked on the server, in
	`_onRequest`, never by hiding them — a button a client can see is a button a client can fire.

	=== 2. WHAT A LEVEL DOES TO THE WORLD ====================================================

	Three of the four upgrades are numbers that something else reads straight out of `UpgradeConfig`
	with no help from this file: `Customers` sizes the crowd (`CustomerConfig.countFor`), `Luck`
	re-weights the traffic roll on the client that owns it (`TrafficController._pickTier`), and `Jump`
	scales the bail arc on that same client (`StealController._advance` / `_stepLaunch`). All three
	are read off the replicated `UpgradeConfig.Attribute` and all three are pure functions of a table
	their reader already has. Nothing to do here.

	The same is true of the four ladders that came OFF this board in the 2026-08-09 and 2026-08-14
	swaps — `Income`, `Storage` and `AutoCollect` are still read by `GarageService`, `OfflineService`
	and `_restartAutoCollect` respectively, and `MythicalLuck` is still summed into `luckFactor`, for
	anybody holding a level. See note 6 in `UpgradeConfig`; the only thing that changed is that
	`_onRequest` will not sell them.

	`Floor2` is not a number. It is 53 parts of building, six podiums, a roof that has to go back up
	and a cap panel that has to become invisible again — geometry that is not in Workspace until it
	is bought. `_setFloor` is the whole of that, and it runs in BOTH directions, which is the part
	worth reading before touching it:

	    A PLOT IS A SEAT FOR A SESSION, NOT A SAVE. `PlotConfig` says so and the whole plot system is
	    built on it — you get whichever lot is free and it goes back in the pool when you leave. So a
	    second storey is a property of the PLAYER that has to be STAMPED ONTO whichever plot they
	    happen to be sitting on, and taken off again on release. Leave it standing and the next
	    player to claim that lot inherits a building they never paid for, plus six bays
	    `GarageService` will happily park their cars on.

	`AutoCollect` is a timer, and it is a timer per lot rather than a global sweep because the only
	thing it can do is call `GarageService:collectAll`, which needs a claimed lot to have anything to
	collect from.

	=== 3. TAKING THE MONEY ==================================================================

	`_onRequest` and `_onBayRequest` are the only two paths that spend cash here, and both do it
	through `GarageService:addCash` with a negative amount rather than writing the profile themselves
	— one writer per number, and the HUD's roll-up comes free. Both re-read the level and the balance
	AFTER every check rather than trusting what the client sent, because the client sends one thing:
	which button it pressed.

	=== 4. AND THE SECOND BOARD ==============================================================

	`_onBayRequest` sells one level on ONE BAY's upgrade kiosk — the tilted sign standing on
	each podium's collect mat. This service decides the purchase, exactly as it does for the
	billboard; it does NOT draw that board or store its level. Both of those belong to `GarageService`,
	which already owns the bay records, the profile's `Garage` table and the income formula the kiosk
	is a readout of. Splitting it the other way would mean this file discovering podiums and reading
	what is parked on them, which is that service's whole job.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
--- The board's discovery and drawing, shared with the client's Upgrades page (`PagesV2/Upgrades`).
local UpgradeBoardFace = require(ReplicatedStorage.shared.Modules.UpgradeBoardFace)

type Face = UpgradeBoardFace.Face

type Board = {
	plot: Model,
	faces: { Face },
}

local UpgradeService = Shard.new("UpgradeService"):withDependencies({ "PlotService", "GarageService" })

UpgradeService:withSignals({
	"UpgradeBought", -- (player: Player, key: string, level: number, cost: number)
	"BayUpgradeBought", -- (player: Player, bay: number, level: number, cost: number)
})

UpgradeService:withRemoteEvents({
	{
		-- client -> server (key): the player pressed a tile on the board they are standing at
		RequestUpgrade = function(player: Player, key: unknown)
			UpgradeService:_onRequest(player, key)
		end,

		--[[ client -> server (slot): the player pressed a podium's upgrade kiosk.

			IT SENDS THE SLOT MODEL, NOT A BAY NUMBER, and that is worth a line. Every kiosk on the
			server is bound by every client (see `UpgradeController` note 1), so a bay number alone
			would let a press on somebody else's bay 3 upgrade your own bay 3 — a button that does
			something other than what it is standing in front of. An Instance can be checked against
			the plot this player actually holds, so a press on a lot that is not yours is refused
			outright rather than redirected. ]]
		RequestBayUpgrade = function(player: Player, slot: unknown)
			UpgradeService:_onBayRequest(player, slot)
		end,
	},
})

-- === The plot upgrade templates =============================================
--[[ Where the second storey lives while nobody has bought it: `ServerStorage.PlotUpgrades`, holding
	ONE `Floor2` folder and ONE `Floor2Contents` folder for all six plots.

	One and not six, because the six plots were measured to be geometrically identical to 0.0003
	studs in plot-local space — they are the same lot in different rotations. Both folders were
	captured in plot 1's frame and carry `SourceOriginCFrame` (the `Floor2` one does; the contents
	are in the same frame, verified against their own `PlotLocalCFrame` stamps), so putting either
	on plot N is one delta applied to every part. ]]
local UPGRADES_FOLDER = "PlotUpgrades"
local FLOOR2_TEMPLATE = "Floor2"
local FLOOR2_CONTENTS = "Floor2Contents"
local SOURCE_ORIGIN_ATTRIBUTE = "SourceOriginCFrame"

--[[ Which plot the folders were cut out of, stamped beside the frame. It is the recovery route in
	`_sourceOrigin` and the reason a re-capture that loses the frame is survivable rather than fatal:
	the plot is still standing in Workspace and its `Origin` is where those numbers came from. ]]
local SOURCE_PLOT_ATTRIBUTE = "SourcePlotIndex"

-- Names inside a plot's `Building`. The roof carries its own drop, stamped by whatever locked it.
local BUILDING_NAME = "Building"
local FLOOR1_NAME = "Floor1"
local FLOOR2_NAME = "Floor2"
local ROOF_NAME = "Roof"
local ROOF_DROPPED_ATTRIBUTE = "RoofDropped"
local ROOF_OFFSET_ATTRIBUTE = "RoofDropOffset"

--[[ The cap over the ramp tower, and the one step of a lock that looks like a no-op.

	It is already `Transparency = 0` in the file, so "make it visible" changes nothing you can see —
	it only starts SHOWING when Floor 2 leaves, because its coplanar twin lives up there. Which means
	the direction that matters is the other one: on UNLOCK it has to go transparent, or the two
	surfaces z-fight.

	AND IT HAS TO STOP COLLIDING, WHICH IS NOT THE SAME STEP. For a long time this went transparent
	and stayed solid, so a lot that had just bought a second storey grew an invisible ceiling across
	the whole ramp tower at y+0.74 above the deck: a 21 x 30 slab with no opening in it, sitting in
	exactly the plane the ladder arrives at. The ladder looked right, climbed right, and stopped
	dead one rung from the top with nothing on screen to explain it. Transparency is what you see;
	`CanCollide` is what you hit, and this part is a floor, so it needs both. ]]
local FLOOR1_ROOF_NAME = "Floor1Roof"

--[[ The stairwell in the upstairs deck, cut by hand because the mesh will not hold one.

	`Cube.008` is the deck slab, the coplanar twin the note above describes: same 21.143 x 0.740 x
	30.403 as `Floor1Roof`, same place, and unlike the cap it has a rectangular opening modelled
	into it for the ladder. The opening is real in the ART and does not survive the trip to physics.
	A `MeshPart` on the default collision fidelity is approximated by a handful of convex hulls, and
	convex pieces cannot meet at the inside corner of a hole, so the cook bridges two opposite
	corners with diagonals. Measured on the standing reference lot, the collision opening pinches
	from the modelled 5.3 x 11.2 down to nothing at the ladder end: a body-width box centred on the
	rungs overlaps the slab for the last two studs of the climb. That is the second half of the same
	bug, and it is the half that survives fixing the cap.

	`PreciseConvexDecomposition` is the obvious answer and it is worse: asked for it, the cook fills
	the opening in completely (checked). So the deck slab stops colliding and four boxes take over,
	laid out as a picture frame around the hole. Four parts per lot, six lots, and the opening is
	then exactly the rectangle below rather than whatever the cook felt like.

	THE NUMBERS ARE IN THE SLAB'S OWN FRAME, not the world's, because that is the only frame they
	are true in: the six lots stand at six rotations around the plaza. Probed off the reference lot
	at 0.02 studs and then pulled in a hair, so the collision opening sits just inside the modelled
	one and no visible floor is left unsupported. The ladder centre lands at x = -0.036, z = 3.794
	in this frame on all six lots and on the reference, which leaves about 1.5 studs of clearance on
	either shoulder. ]]
local DECK_SLAB_HOLE = {
	minX = -2.526,
	maxX = 2.624,
	minZ = -7.047,
	maxZ = 3.803,
}

-- What the four boxes are called. They hang off the slab itself, so they arrive and leave with it.
local DECK_COLLISION_NAME = "DeckCollision"

--[[ The glass balustrade around the deck, which is the same lie told in a different shape.

	The deck's open edge is a run of 36 stone posts with tinted glass between them, and the glass is
	one `MeshPart` called `Plane`: 70% transparent, 85.9 x 1.6 x 38.9 of bounding box for what is
	really a thin L of panels lying along two edges. Its collision hull is the convex fill of that L,
	which is a solid TRIANGLE 1.6 studs thick covering about an eighth of the deck. You do not walk
	into it, you walk on top of it, and you float a stud and a half over your own forecourt with
	nothing under your feet. That is what this looked like from the player's side.

	Neither collision fidelity helps. Default fills 18.1% of the bounding box; asking for
	`PreciseConvexDecomposition` fills 16.9% (both measured on the standing reference lot), because
	the problem is not precision, it is that a right-angled run of panels has no thin convex cover.
	So the glass stops colliding and the barrier is rebuilt from the posts instead.

	THE POSTS ARE THE RAIL, and they are honest geometry: 36 separate thin parts that already collide
	correctly, spaced 2.62 to 4.14 studs apart along one unbroken chain. Linking every pair closer
	than `BALUSTRADE_LINK_STUDS` reproduces that chain exactly, because the nearest real neighbour is
	never more than 4.14 away and the nearest SKIP is never less than 6.7, so the threshold sits in
	open water rather than on a knife edge. Measured on the live lot it yields 36 links over 36 posts
	with two chain ends and no orphans: one continuous run with one extra chord across the chamfered
	corner, which is glass anyway.

	The glass is found by being transparent rather than by being called `Plane`. It is the only part
	of Floor 2 with any transparency at all, in the template and in the clone alike (checked), and
	that is a fact about what it IS rather than about what the exporter named it. ]]
local BALUSTRADE_COLLISION_NAME = "BalustradeCollision"
local BALUSTRADE_LINK_STUDS = 5
local BALUSTRADE_THICKNESS = 0.3

--[[ The ladder up the ramp tower. Two models per plot, 28 parts of rail and rung, named `Stair` by
	whoever modelled it — matched by NAME anywhere under the plot rather than by path or by a rename,
	so a re-import of the builder's map keeps working (see the map-swap contract). ]]
local LADDER_NAME = "Stair"


-- === Discovery ==============================================================

--[[ One of a plate's two SurfaceGuis, as a face (`Modules/UpgradeBoardFace.discover`, which the
	Upgrades page shares). A face with no grid is one startup warning naming the plot. ]]
function UpgradeService._discoverFace(self, plot: Model, gui: SurfaceGui): Face?
	return UpgradeBoardFace.discover(gui, nil, function(message: string)
		self.log:warn(string.format("%s: %s", plot.Name, message))
	end)
end

--[[ Resolve one plot's billboard: every face its plate carries. A board built before the kit face
	existed has only `UpgradeGui`, and draws exactly as it did. ]]
function UpgradeService._discoverBoard(self, plot: Model): Board?
	local names = UpgradeConfig.Board

	local sign = plot:FindFirstChild(names.ModelName)
	local screen = sign and sign:FindFirstChild(names.ScreenName, true)
	if not screen then
		return nil
	end

	local faces: { Face } = {}
	for _, name in { names.GuiName, names.KitGuiName } do
		local gui = screen:FindFirstChild(name)
		if gui and gui:IsA("SurfaceGui") then
			local face = self:_discoverFace(plot, gui)
			if face then
				table.insert(faces, face)
			end
		end
	end
	if #faces == 0 then
		return nil
	end

	return {
		plot = plot,
		faces = faces,
	}
end

-- === Drawing the board ======================================================

--[[ Write one player's levels onto one board.

	Everything here is derived from the stored LEVEL, so there is no board state to keep in step with
	anything. Redrawn on a purchase, on a claim, and still on a cash change: nothing on the board has
	followed the balance since the button stopped doing it, but the redraw is a few string writes and
	it is the path a board that drifted heals on. ]]
function UpgradeService._draw(self, board: Board, player: Player?)
	local GarageService = Shard.get("GarageService")

	local upgrades = if player and GarageService then GarageService:getUpgrades(player) else {}

	--[[ NOTHING BELOW GOES THROUGH `oneLine` ANY MORE — 2026-08-23, and this is a localization fix
		rather than a cosmetic one.

		Every string written here used to have its spaces swapped for U+00A0 so that `TextScaled`
		could not wrap "6 BAYS" onto two lines. `AutoLocalize` is true on this SurfaceGui, so what
		Roblox captured as each label's SOURCE string was the non-breaking version — a key no
		translation of the real sentence will ever match, and mangled copy in front of any human
		translator. All twelve labels on the board were affected.

		The rebuild removed the reason for it: every label now carries a `UITextSizeConstraint`
		ceiling shared across the whole board, so there is one type scale rather than one per box and
		nothing to defend against. `UpgradeConfig.oneLine` is still live and still correct for the
		per-bay kiosk, which is drawn by `GarageService` and still sizes each line independently. ]]
	for _, face in board.faces do
		self:_drawFace(face, player, upgrades)
	end
end

-- One face of a billboard. Called for both on every draw; see `Face`. The drawing itself is shared
-- with the Upgrades page (`Modules/UpgradeBoardFace.draw`), so the two cannot disagree on a rule.
function UpgradeService._drawFace(self, face: Face, player: Player?, upgrades: any)
	UpgradeBoardFace.draw(face, player, upgrades)
end

--[[ Put the Upgrades prompt on one plot's cabinet (`UpgradeConfig.Machine`). Once per plot at boot,
	and never touched again: who it is FOR is decided on each client. Hung on an Attachment at the
	cabinet's centre rather than on whichever part happens to be first, so the prompt floats over the
	machine and not over one of its buttons. A plot with no cabinet simply has no prompt. ]]
function UpgradeService._wireMachine(self, plot: Model)
	local cfg = UpgradeConfig.Machine
	local machine = plot:FindFirstChild(cfg.ModelName)
	local part = machine and (if machine:IsA("BasePart") then machine else machine:FindFirstChildWhichIsA("BasePart", true))
	if not part or part:FindFirstChildWhichIsA("ProximityPrompt", true) then
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.Name = "UpgradesPromptAnchor"
	anchor.Parent = part
	if machine:IsA("Model") then
		--- `PromptHeight` of the way up the cabinet's box rather than its middle (2026-10-20: "move the
		--- upgrades prompt further lower down, it feels pretty high"). 0.5 is the old centre.
		local frame, size = machine:GetBoundingBox()
		local share = cfg.PromptHeight or 0.5
		anchor.WorldPosition = frame.Position - frame.UpVector * (size.Y * (0.5 - share))
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UpgradesPrompt"
	prompt.ActionText = cfg.ActionText
	prompt.ObjectText = cfg.ObjectText
	prompt.HoldDuration = cfg.HoldDuration
	prompt.MaxActivationDistance = cfg.MaxDistance
	prompt.RequiresLineOfSight = false
	--[[ ALWAYS SHOWN (2026-10-14, "the upgrades prompt stopped showing at one point"). The engine
		draws ONE prompt per key by default (`OnePerButton`) and does not pick the nearest, so the
		plot's lobby-car pad and the bays, all on E, could take the key and hide this one. ]]
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt:AddTag(cfg.PromptTag)
	prompt.Parent = anchor
end

-- Redraw the board on the plot this player holds, if they hold one.
function UpgradeService._redraw(self, player: Player)
	local plot = self._plotOf[player]
	local board = plot and self._boards[plot]
	if board then
		self:_draw(board, player)
	end
end

-- === The second storey ======================================================

--[[ Show or hide the ladder to deck 2.

	It climbs the ramp tower from the forecourt to exactly where the upstairs deck lands, so on a
	one-deck lot it is a ladder to a capped tower with nothing on top of it — which is what three
	playtesters reported as "the ladder is pointless". It belongs to the storey it serves, so it
	arrives and leaves with it.

	IT RUNS AHEAD OF `_setFloor`'S SHORT-CIRCUIT, and that is the whole reason it is its own
	function. `init` stamps every plot with the floor it can SEE and then asks for floor 1, so on a
	place saved at floor 1 the short-circuit fires and the three lock steps never run at all; a
	ladder hidden only in there would stay standing for the entire session. What makes running it
	every call safe is that both writes are ABSOLUTE, unlike the roof's relative drop — nothing here
	compounds, so the world is simply told what it should look like each time.

	COLLISION GOES WITH THE LOOK, or the fix trades a pointless ladder for a worse bug: an invisible
	one you can still stand on leaves the player floating halfway up an empty tower. `CanQuery` too,
	so nothing aims a raycast or a click at a ladder that is not there.

	Restoring to `Transparency = 0` rather than to a remembered value because that is what all 28
	parts are authored at on all six plots (checked) — a ladder is not something the map fades. ]]
function UpgradeService._setLadder(self, plot: Model, shown: boolean)
	for _, model in plot:GetDescendants() do
		if model.Name ~= LADDER_NAME then
			continue
		end
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency = if shown then 0 else 1
				part.CanCollide = shown
				part.CanQuery = shown
			end
		end
	end
end

--[[ Cut the ladder's stairwell into a deck that has just been built.

	`DECK_SLAB_HOLE` carries the measurements and the reason the mesh cannot be left to hold its own
	opening. This is the other half of it: the deck slab stops colliding and four anchored boxes take
	over, laid out as a picture frame with the stairwell in the middle. The boxes are exactly as
	thick as the slab and sit in its plane, so the deck a player stands on is where it always was.

	THE SLAB IS FOUND BY ITS TWIN RATHER THAN BY NAME. `Cube.008` is what the exporter happened to
	call it, and a re-import of the builder's map is free to call it anything, but the relationship
	underneath cannot drift: the deck slab is the one part of Floor 2 that lands at the same size and
	in the same place as `Floor1Roof`, because the two are one floor drawn twice, once with the hole
	and once without. Measured across all six lots that is an exact size match and at most 0.0003
	studs of position, while no other part in the template comes within 0.05 of the size or 0.5 of
	the place. So the cap is the search key, and a lot that has lost its cap keeps the stock mesh
	collision and says so.

	IT RUNS ON THE CLONE, AFTER THE PIVOT. Every CFrame here is read off the slab as it now stands,
	so the boxes inherit whichever of the six rotations this lot has for free, and the numbers in
	`DECK_SLAB_HOLE` never have to leave the slab's own frame.

	Anything already named `DECK_COLLISION_NAME` in the clone is destroyed first. That costs nothing
	today, because the template has none. It matters on the day somebody re-captures the template off
	a lot that was standing at floor 2, which is how this folder grew an awning and gained six parts
	the last time. ]]
function UpgradeService._cutStairwell(self, built: Instance, cap: BasePart?)
	if not cap then
		self.log:warn(string.format(
			"%s has no %s, so its deck keeps the mesh's own collision and the ladder may not top out.",
			built:GetFullName(),
			FLOOR1_ROOF_NAME
		))
		return
	end

	local slab: BasePart? = nil
	for _, part in built:GetDescendants() do
		if part.Name == DECK_COLLISION_NAME then
			part:Destroy()
		elseif
			part:IsA("BasePart")
			and (part.Size - cap.Size).Magnitude < 0.05
			and (part.Position - cap.Position).Magnitude < 0.5
		then
			slab = part
		end
	end

	if not slab then
		self.log:warn(string.format(
			"%s has no deck slab matching %s (%s at %s), so the stairwell was not cut.",
			built:GetFullName(),
			FLOOR1_ROOF_NAME,
			tostring(cap.Size),
			tostring(cap.Position)
		))
		return
	end

	--[[ The mesh stops being a floor in both senses at once. Collision moves to the boxes, and so do
		queries: they are coplanar, so every ray that used to land on the slab lands on a box at the
		same point, and the only rays whose answer changes are the ones down the stairwell, which
		should have been passing through all along. `CanTouch` is left alone because nothing here is
		about touching, and turning it off would quietly change what the deck reports to anything
		listening. ]]
	slab.CanCollide = false
	slab.CanQuery = false

	local half = slab.Size / 2
	local frame = {
		{ -half.X, DECK_SLAB_HOLE.minX, -half.Z, half.Z },
		{ DECK_SLAB_HOLE.maxX, half.X, -half.Z, half.Z },
		{ DECK_SLAB_HOLE.minX, DECK_SLAB_HOLE.maxX, -half.Z, DECK_SLAB_HOLE.minZ },
		{ DECK_SLAB_HOLE.minX, DECK_SLAB_HOLE.maxX, DECK_SLAB_HOLE.maxZ, half.Z },
	}

	for _, rect in frame do
		local x0, x1, z0, z1 = rect[1], rect[2], rect[3], rect[4]
		--[[ A hole wider than the slab it is cut into would turn one of these inside out and land a
			box across the stairwell, which is the bug this whole function exists to remove. ]]
		if x1 - x0 <= 0 or z1 - z0 <= 0 then
			continue
		end

		local box = Instance.new("Part")
		box.Name = DECK_COLLISION_NAME
		box.Size = Vector3.new(x1 - x0, slab.Size.Y, z1 - z0)
		box.Anchored = true
		box.CanCollide = true
		box.CanQuery = true
		box.CanTouch = false
		box.CastShadow = false
		box.Transparency = 1
		--[[ Invisible, but the material is still doing a job: `Humanoid.FloorMaterial` is read off
			whatever the character is standing on, and that is what picks the footstep sound. Take the
			slab's so the deck sounds like the deck rather than like plastic. ]]
		box.Material = slab.Material
		box.CollisionGroup = slab.CollisionGroup
		box.CFrame = slab.CFrame * CFrame.new((x0 + x1) / 2, 0, (z0 + z1) / 2)
		box.Parent = slab
	end
end

--[[ Rebuild the deck balustrade's collision from its posts, and let the glass off duty.

	See `BALUSTRADE_COLLISION_NAME` for the shape of the problem. In short: the glass panel's hull is
	a solid triangle lying across the deck, so this drops its `CanCollide` and stretches a thin box
	between each neighbouring pair of posts to put the barrier back where the glass actually is.

	ONLY `CanCollide` MOVES. The glass keeps `CanQuery`, because it is a thing you can see and a ray
	that stops on it is answering correctly; the boxes take `CanQuery = false` for the mirror reason,
	since an invisible wall standing in the same plane would only double every hit. Between them the
	deck answers exactly the queries it answered before this existed, and collides differently, which
	is the whole of the intended change.

	A LOT WITH NO GLASS IS NOT AN ERROR, it is a lot whose balustrade was never the problem, so this
	returns quietly. A lot with glass and no posts IS worth a warning: it means the run this measures
	from has been renamed or resized out of recognition, and the deck is about to lose an edge it is
	supposed to have.

	THE RAIL IS DELIBERATELY NOT A BARRIER, and it is worth knowing that before "fixing" it. It is as
	tall as the posts and no taller, which puts its top 1.74 studs above the deck against a humanoid
	`HipHeight` of 2.00, so a player walks over it. Measured: charging the rail head on goes over a
	post exactly as readily as over a pane. That is how the deck behaved before any of this existed
	and Dylan asked to keep it, because hopping the rail down to the forecourt is a shortcut worth
	having. Raising these boxes past hip height is a one-line change if that call is ever reversed,
	but it would put an invisible wall above waist-high glass, so it is a decision rather than a fix.

	The boxes hang off the glass, so they leave with the storey exactly as the stairwell frame does. ]]
function UpgradeService._fitBalustrade(self, built: Instance)
	local glass: BasePart? = nil
	local posts: { BasePart } = {}

	for _, part in built:GetDescendants() do
		if part.Name == BALUSTRADE_COLLISION_NAME then
			part:Destroy()
		elseif part:IsA("BasePart") then
			if part.Transparency >= 0.3 and part.Transparency < 1 then
				glass = part
			elseif
				part.Size.Y > 1.5
				and part.Size.Y < 2.5
				and part.Size.X < 0.5
				and part.Size.Z < 0.5
			then
				table.insert(posts, part)
			end
		end
	end

	if not glass then
		return
	end

	glass.CanCollide = false

	if #posts < 2 then
		self.log:warn(string.format(
			"%s has glass but only %d balustrade post(s), so the deck edge is open. Nothing to measure a rail from.",
			built:GetFullName(),
			#posts
		))
		return
	end

	--[[ Every pair inside the threshold, which on this geometry is every neighbour and nothing else.
		Written as the full pass rather than as a walk along a sorted chain because the run turns two
		corners and chamfers one of them, so there is no axis to sort on that stays true the whole way
		round. ]]
	for i = 1, #posts do
		for j = i + 1, #posts do
			local a, b = posts[i], posts[j]
			local span = (b.Position - a.Position).Magnitude
			if span > BALUSTRADE_LINK_STUDS or span < 0.05 then
				continue
			end

			local pane = Instance.new("Part")
			pane.Name = BALUSTRADE_COLLISION_NAME
			-- As tall as the posts and no taller, so the rail tops out level with the glass.
			pane.Size = Vector3.new(BALUSTRADE_THICKNESS, a.Size.Y, span)
			pane.Anchored = true
			pane.CanCollide = true
			pane.CanQuery = false
			pane.CanTouch = false
			pane.CastShadow = false
			pane.Transparency = 1
			pane.Material = glass.Material
			pane.CollisionGroup = glass.CollisionGroup
			pane.CFrame = CFrame.lookAt(a.Position:Lerp(b.Position, 0.5), b.Position)
			pane.Parent = glass
		end
	end
end

--[[ `tostring(CFrame)` run backwards: "x, y, z, r00 .. r22" -> the CFrame that printed it.

	`CFrame.new` takes those twelve numbers in exactly that order, so this is a true inverse of the
	engine's own formatting rather than a guess at a layout. Anything that is not twelve numbers is
	nil, never a partial CFrame built out of whatever parsed. ]]
local function parseCFrame(text: string): CFrame?
	local numbers = {}
	for piece in string.gmatch(text, "[^,%s]+") do
		local number = tonumber(piece)
		if not number then
			return nil
		end
		table.insert(numbers, number)
	end
	if #numbers ~= 12 then
		return nil
	end
	return CFrame.new(table.unpack(numbers))
end

--[[ The frame both stored folders were captured in, however it happens to have been written down.

	IT IS SUPPOSED TO BE A `CFrame` ATTRIBUTE ON THE `Floor2` FOLDER, and for a long time it was one.
	It stopped being one when that folder was re-captured by hand after the map art sync — the current
	template is 59 parts and carries an awning where the original was 53 — and whatever re-stamped it
	wrote `tostring(origin.CFrame)`. The twelve numbers were exactly right; the TYPE was a string. So
	`typeof(stored) == "CFrame"` was false on every plot on the island, and EXPAND BASE took 250,000,
	stored the level, warned that a template sitting right there was missing, and built nothing.

	A purchase whose payload is a BUILDING has to survive its own template being re-captured, so the
	frame is now read three ways in order:

	  1. the attribute, when it really is a `CFrame`;
	  2. the attribute PARSED, when it is the text `tostring(CFrame)` produces — the exact inverse of
	     the mistake above, so a re-capture written the wrong way still lands;
	  3. `SourcePlotIndex` -> that plot's live `Origin`, which is where the numbers came from in the
	     first place and is the only one of the three that cannot go stale if the map ever moves.

	Route 2 stamps the parsed frame back as a real `CFrame`, so a broken template announces itself
	once per server rather than once per purchase, and re-saving the place makes route 1 true again. ]]
function UpgradeService._sourceOrigin(self, template: Instance): CFrame?
	local stored = template:GetAttribute(SOURCE_ORIGIN_ATTRIBUTE)
	if typeof(stored) == "CFrame" then
		return stored
	end

	if type(stored) == "string" then
		local parsed = parseCFrame(stored)
		if parsed then
			template:SetAttribute(SOURCE_ORIGIN_ATTRIBUTE, parsed)
			self.log:warn(string.format(
				"%s.%s was stored as text rather than a CFrame — parsed and re-stamped it. Re-save the place to keep the fix.",
				template.Name,
				SOURCE_ORIGIN_ATTRIBUTE
			))
			return parsed
		end
	end

	local index = tonumber(template:GetAttribute(SOURCE_PLOT_ATTRIBUTE))
	local PlotService = Shard.get("PlotService")
	local plots = index and PlotService and PlotService:getPlots()
	for _, record in plots or {} do
		if record.index == index then
			local origin = record.model:FindFirstChild("Origin")
			if origin and origin:IsA("BasePart") then
				self.log:warn(string.format(
					"%s has no usable %s — falling back to %s's live Origin. Re-stamp the template.",
					template.Name,
					SOURCE_ORIGIN_ATTRIBUTE,
					record.model.Name
				))
				return origin.CFrame
			end
		end
	end

	return nil
end

--[[ Build or remove a plot's Floor 2, and stamp what it now has.

	IDEMPOTENT IN BOTH DIRECTIONS — asked for the floor a plot already has, it does nothing at all.
	That matters more than it sounds: this is called on claim (which may be a rejoin onto a lot that
	is already at floor 1), on purchase, and on release, and the roof drop is a RELATIVE move. Apply
	it twice and the roof is 19 studs into the ground with no record that it happened.

	The three steps are the recipe the plots were locked with, run backwards:

	  1. `Building.Floor2` in or out of Workspace
	  2. `Building.Roof` up or down by its own `RoofDropStuds`, stamped as `RoofDropped`
	  3. `Floor1Roof` invisible or visible — the step that looks like a no-op and is not

	Step 3 is the one to check if this ever half-works. `Floor1Roof` caps the ramp tower that the
	dropped roof does not span, and it is only VISIBLE while Floor 2 is away, because its coplanar
	twin (`Cube.008`) lives inside Floor 2. Skip it on unlock and you get two opaque surfaces in the
	same plane fighting over every pixel. It is also the part the deck's collision is measured
	against, which is why it is now read once at the top rather than at the point of use.

	The ladder is a fourth step and deliberately sits OUTSIDE the short-circuit below — `_setLadder`
	says why.

	A fifth and a sixth run only on the way up, and only on the clone. `_cutStairwell` puts a real
	hole in the new deck where the ladder arrives; `_fitBalustrade` puts a real rail along the deck's
	open edge. Steps 3 and 5 are two halves of one bug and were fixed together, so if the ladder ever
	stops topping out again, suspect them as a pair rather than separately. Step 6 is a separate bug
	of the same species: a mesh whose collision hull is nothing like the mesh. See `DECK_SLAB_HOLE`
	and `BALUSTRADE_COLLISION_NAME`.

	Returns whether anything moved, so the caller knows whether the bays need re-discovering. ]]
function UpgradeService._setFloor(self, plot: Model, top: number): boolean
	self:_setLadder(plot, top >= 2)

	local current = tonumber(plot:GetAttribute(UpgradeConfig.PlotFloorsAttribute)) or GarageConfig.BaseFloor
	if current == top then
		return false
	end

	local building = plot:FindFirstChild(BUILDING_NAME)
	local roof = building and building:FindFirstChild(ROOF_NAME)
	local floor1 = building and building:FindFirstChild(FLOOR1_NAME)
	if not (building and roof and floor1) then
		self.log:warn(string.format("%s has no %s/%s — cannot change its floor count.", plot.Name, BUILDING_NAME, ROOF_NAME))
		return false
	end

	local slots = plot:FindFirstChild(GarageConfig.SlotsFolderName)

	--[[ Read once, used twice and for two different things: it is the panel the lock switches off
		down at the bottom of this function, and it is the search key `_cutStairwell` measures the
		new deck against. Both want the same part and neither wants it more than the other, so it is
		resolved here rather than in either. ]]
	local cap = floor1:FindFirstChild(FLOOR1_ROOF_NAME)
	cap = if cap and cap:IsA("BasePart") then cap else nil

	if top >= 2 then
		--[[ THE TEMPLATE IS ONLY NEEDED IN THIS DIRECTION, which is why it is resolved here rather
			than above the branch. Taking a storey AWAY is a `Destroy`, a roof and a cap panel, and it
			needs nothing out of ServerStorage at all — but while this block sat outside the branch, a
			template the service could not read also blocked the TEARDOWN. That is the worse half of
			the same bug: a place saved with a storey standing on it would keep it for the whole
			session, and hand it free to whoever claimed that lot. ]]
		local origin = plot:FindFirstChild("Origin")
		local store = ServerStorage:FindFirstChild(UPGRADES_FOLDER)
		local template = store and store:FindFirstChild(FLOOR2_TEMPLATE)
		local contents = store and store:FindFirstChild(FLOOR2_CONTENTS)
		if not (origin and origin:IsA("BasePart") and template and contents) then
			--[[ Names the half that actually failed. The old line blamed the template for every one of
				these, including the run that found the template exactly where it should be and could
				not read one attribute off it. ]]
			self.log:warn(string.format(
				"%s stays on one deck: ServerStorage.%s needs %s and %s, and the plot needs an Origin part (template=%s, contents=%s, origin=%s).",
				plot.Name,
				UPGRADES_FOLDER,
				FLOOR2_TEMPLATE,
				FLOOR2_CONTENTS,
				tostring(template ~= nil),
				tostring(contents ~= nil),
				tostring(origin ~= nil and origin:IsA("BasePart"))
			))
			return false
		end

		local sourceOrigin = self:_sourceOrigin(template)
		if not sourceOrigin then
			self.log:warn(string.format(
				"%s stays on one deck: %s carries no readable %s and no %s to recover it from.",
				plot.Name,
				FLOOR2_TEMPLATE,
				SOURCE_ORIGIN_ATTRIBUTE,
				SOURCE_PLOT_ATTRIBUTE
			))
			return false
		end

		--[[ The source plot's frame -> this plot's. Every part in both folders is anchored with no
			joint of any kind (checked: 0 constraints across both), so writing CFrames moves exactly
			what is written and cannot drag an assembly — the trap the memory on welded clones
			describes. ]]
		local delta = origin.CFrame * sourceOrigin:Inverse()

		local built = template:Clone()
		built.Name = FLOOR2_NAME
		for _, part in built:GetDescendants() do
			if part:IsA("BasePart") then
				part.CFrame = delta * part.CFrame
			end
		end
		built.Parent = building
		self:_cutStairwell(built, cap)
		self:_fitBalustrade(built)

		if slots then
			--[[ BAY NUMBERS ARE PER LOT, NOT PER DECK, AND THE TEMPLATE DOES NOT KNOW THAT.

				The six stored deck-2 podiums carry `SlotIndex` 1..6, exactly like the six downstairs,
				because they were captured off a plot that only ever had one deck's worth of them at a
				time. Cloned in as they are, a twelve-bay lot has two bay 1s — and every part of the
				garage keys off that number. `_carAtBay` finds whichever it meets first, `_rebuildLot`
				stands the same car on both podiums, and `_freeBay` reports a free bay that is already
				full. It is not a display bug; it is the profile pointing at two places at once.

				So the upstairs bays are renumbered ON THE WAY IN, continuing from the highest number
				already standing on this plot: six downstairs means seven to twelve upstairs. Derived
				from the deck below rather than from a constant, because `GarageConfig` promises a plot
				may have any number of bays and a seventh podium downstairs must push the upstairs ones
				along rather than collide with them.

				RANK, NOT OFFSET. The rank of a template within its own sorted order is what gets added
				to the base, so re-capturing the templates one day with 7..12 already stamped on them
				produces the same 7..12 rather than 13..18. ]]
			local base = 0
			for _, slot in slots:GetChildren() do
				local index = tonumber(slot:GetAttribute(GarageConfig.SlotIndexAttribute))
				if index and index > base then
					base = index
				end
			end

			local ordered = contents:GetChildren()
			table.sort(ordered, function(a, b)
				local ai = tonumber(a:GetAttribute(GarageConfig.SlotIndexAttribute)) or math.huge
				local bi = tonumber(b:GetAttribute(GarageConfig.SlotIndexAttribute)) or math.huge
				if ai == bi then
					return a.Name < b.Name
				end
				return ai < bi
			end)

			for rank, slot in ordered do
				local clone = slot:Clone()
				clone:SetAttribute(GarageConfig.SlotIndexAttribute, base + rank)
				clone:PivotTo(delta * slot:GetPivot())
				clone.Parent = slots
			end
		end
	else
		local existing = building:FindFirstChild(FLOOR2_NAME)
		if existing then
			existing:Destroy()
		end
		if slots then
			for _, slot in slots:GetChildren() do
				if slot:GetAttribute(GarageConfig.SlotFloorAttribute) == 2 then
					slot:Destroy()
				end
			end
		end
	end

	--[[ The roof. `RoofDropOffset` is the exact vector it was moved by, kept rather than recomputed
		from `RoofDropStuds` and an up vector: it is what actually happened to this roof, and a
		re-derivation is one sign error away from burying it. ]]
	local dropped = roof:GetAttribute(ROOF_DROPPED_ATTRIBUTE) == true
	local offset = roof:GetAttribute(ROOF_OFFSET_ATTRIBUTE)
	local wantDropped = top < 2
	if typeof(offset) == "Vector3" and dropped ~= wantDropped then
		local move = if wantDropped then offset else -offset
		for _, part in roof:GetDescendants() do
			if part:IsA("BasePart") then
				part.CFrame = part.CFrame + move
			end
		end
		roof:SetAttribute(ROOF_DROPPED_ATTRIBUTE, wantDropped)
	end

	--[[ The cap. Every one of these four writes is the same statement said to a different system:
		this part is the roof of floor 1 while there is no floor 2, and it is nothing at all once
		there is. `CanCollide` is the one that was missing and the one the ladder needed. The other
		two go with it so that nothing is left half-true, because a part that cannot be seen or stood
		on but still answers a raycast is the kind of thing that reads as a different bug later. ]]
	if cap then
		local capped = top < 2
		cap.Transparency = if capped then 0 else 1
		cap.CanCollide = capped
		cap.CanQuery = capped
		cap.CanTouch = capped
	end

	plot:SetAttribute(UpgradeConfig.PlotFloorsAttribute, top)
	return true
end

--[[ Put the plot on the storey count this player has paid for, and tell the garage if it changed.

	The `refreshBays` call is not optional and is not tidiness: `GarageService` discovers bays once,
	so six podiums that appeared a moment ago are six podiums nothing is bound to — no collect mat,
	no picker prompt, and no car, even for a player whose profile says one is parked up there.

	RETURNS WHETHER THE PLOT NOW STANDS AT THE FLOOR THIS PLAYER PAID FOR, which is a different
	question from `_setFloor`'s "did anything move" and is the one a purchase has to ask. The two
	answers differ in both directions: nothing moves when the plot is already correct (fine), and
	nothing moves when the build failed (not fine, and indistinguishable from the first). So this
	reads the ATTRIBUTE back — `_setFloor` stamps it only on the path where the storey really
	changed, so it is a statement about the world rather than about the call. ]]
function UpgradeService._applyFloor(self, player: Player, plot: Model): boolean
	local GarageService = Shard.get("GarageService")
	local want = UpgradeConfig.topFloor(GarageService and GarageService:getUpgrades(player))
	if self:_setFloor(plot, want) and GarageService then
		GarageService:refreshBays(plot)
	end
	return (tonumber(plot:GetAttribute(UpgradeConfig.PlotFloorsAttribute)) or GarageConfig.BaseFloor) == want
end

-- === Auto collect ===========================================================

--[[ Sweep this player's lot on the interval their upgrade bought, and restart the clock whenever
	that interval changes.

	ONE THREAD PER OWNED LOT, not a global pass, because the interval is per player — five levels
	means five different periods running at once on a full server, and a shared tick would have to
	track a phase per player anyway. The thread dies with the assignment's trove.

	It deliberately does NOT care where the player is. Income in this game is a function of a
	timestamp, so it accrues during a race and while the player is offline; a sweep that only ran
	while you stood on your own forecourt would be a different, worse feature wearing the same
	name. ]]
function UpgradeService._restartAutoCollect(self, player: Player)
	local lot = self._lots[player]
	if not lot then
		return
	end

	--[[ `Remove` cleans the sub-trove AND drops it out of its parent, which is the whole reason this
		is an `Extend` rather than a second Trove held by hand: a plain `Destroy` would leave the
		release path holding a reference to a trove it destroys a second time. ]]
	if lot.autoTrove then
		lot.trove:Remove(lot.autoTrove)
		lot.autoTrove = nil
	end

	local GarageService = Shard.get("GarageService")
	local interval = UpgradeConfig.autoCollectInterval(GarageService and GarageService:getUpgrades(player))
	if not (interval and GarageService) then
		return
	end

	local trove = lot.trove:Extend()
	lot.autoTrove = trove

	--[[ Heartbeat with an accumulator rather than `task.delay`, so the sweep cannot outlive the
		release that cancelled it — the same shape and the same reason as `GarageService._labelLoop`. ]]
	local accumulator = 0
	trove:Add(RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < interval then
			return
		end
		accumulator = 0
		if GarageService:collectAll(player) > 0 then
			self:_redraw(player)
		end
	end))
end

-- === Buying =================================================================

--[[ The one path that spends cash, and the only thing a client can reach.

	WHAT THE CLIENT SENDS IS A KEY AND NOTHING ELSE. Not a level, not a price, not a plot — every one
	of those is looked up here from state the client never touched. So the whole attack surface is
	"which of four buttons did you press", and the worst a forged call can do is buy something you
	could have bought by walking to the board.

	The owner check is the load-bearing one. A SurfaceGui in Workspace is visible to everyone on the
	server, so every player can see — and fire — every other player's board. `_plotOf` is written
	only by `PlotService`'s own assignment signal, so it is the server's answer to "whose lot is
	this", not the client's. ]]
function UpgradeService._onRequest(self, player: Player, key: unknown)
	-- `isOnBoard` rather than `isKey` — see its own note. A key this file still knows about but no
	-- longer sells is refused here, not merely absent from the UI.
	if not (UpgradeConfig.Enabled and UpgradeConfig.isOnBoard(key)) then
		return
	end

	local now = os.clock()
	if now - (self._cooldowns[player] or 0) < UpgradeConfig.PurchaseCooldown then
		return
	end
	self._cooldowns[player] = now

	local plot = self._plotOf[player]
	if not plot then
		return -- no lot, nothing to upgrade
	end

	local GarageService = Shard.get("GarageService")
	if not (GarageService and GarageService:isProfileReady(player)) then
		return
	end

	local level = UpgradeConfig.levelOf(GarageService:getUpgrades(player), key :: string)
	if WorldConfig.highestUnlocked(player) < UpgradeConfig.requiredWorldOf(key :: string, level) then
  self:_redraw(player)
  return
 end
 local cost = UpgradeConfig.costOf(key :: string, level)
	if not cost then
		return -- already at the top of this ladder
	end
	local cash = GarageService:getCash(player)
	if cash < cost then
		--[[ Redrawn rather than ignored: pressing a button you cannot afford should repaint the price
			you are short of, which is also how the board recovers if its cash colour is stale. ]]
		self:_redraw(player)
		--[[ And offered a way to close the gap. `CashService` picks the cheapest pack that covers
			what is MISSING rather than what is priced, opens Roblox's window, and changes nothing
			here: the press is still refused and a player who buys presses the tile again. See
			`CashConfig`. ]]
		local CashService = Shard.get("CashService")
		if CashService then
			CashService:offerTopUp(player, cost - cash, string.format("the %s upgrade", tostring(key)))
		end
		return
	end

	GarageService:addCash(player, -cost)
	if not GarageService:setUpgradeLevel(player, key :: string, level + 1) then
		-- The profile went away between the balance check and the write. Give the money back rather
		-- than charging for a level that was never stored.
		GarageService:addCash(player, cost)
		return
	end

	-- Only Floor2 changes the world; the other three are numbers the garage already reads for itself.
	if key == "Floor2" then
		--[[ AND IT IS THE ONLY ONE THAT CAN FAIL AFTER THE MONEY HAS ALREADY MOVED.

			The other three ARE the level — store it and the effect exists, because every reader is a
			pure function of the number. `Floor2` is 59 parts of building that have to be found, read
			and cloned, and any of that can be missing from a place that was edited: for a while it
			was, and the result was the worst shape a purchase can have. It took 250,000, stored the
			level, drew the tile as OWNED and left the lot on one deck, with nothing but a server
			warning to say so. Nobody watching the game can tell that from a UI bug.

			So the cash and the level are rolled back together and the board is repainted on the
			state the player is actually in. Restoring `level` rather than subtracting one because
			that is the number this handler read before it touched anything — a decrement would
			re-derive a value it already has and would be wrong if the profile moved underneath. ]]
		if not self:_applyFloor(player, plot) then
			GarageService:setUpgradeLevel(player, key :: string, level)
			GarageService:addCash(player, cost)
			self:_redraw(player)
			self.log:warn(string.format(
				"%s's %s purchase was refunded: %s could not be built (see the warning above).",
				player.Name,
				tostring(key),
				plot.Name
			))
			return
		end
	elseif key == "AutoCollect" then
		self:_restartAutoCollect(player)
	end

	self:_redraw(player)
	--- Over the buyer, who is standing at the board (`UpgradeConfig.Celebrate`).
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		self:_celebrate(root.Position - Vector3.new(0, 3, 0), level + 1, player)
	end
	self:getSignal("UpgradeBought"):Fire(player, key, level + 1, cost)
	self.log:info(string.format("%s bought %s level %d for %d.", player.Name, tostring(key), level + 1, cost))
end

--[[ The other purchase: one level on one bay's upgrade kiosk.

	SAME SHAPE AS `_onRequest` ABOVE AND DELIBERATELY NOT SHARED WITH IT. The two look alike — check,
	price, take, store, redraw — but they differ at every one of those steps (a different ladder, a
	different profile key, a different board, and an ownership test the other one does not need), and
	a merged handler would be five branches on which kind it is. They share the COOLDOWN, which is the
	one thing that genuinely is per player rather than per board.

	WHAT THE CLIENT SENDS IS A SLOT AND NOTHING ELSE. Not a level, not a price, not a bay number —
	the level comes off the profile, the price off `UpgradeConfig`, and the bay number off the map's
	own `SlotIndex` attribute. So the whole attack surface is "which podium did you press", and a
	forged call can only buy something you could have bought by walking to it. ]]
function UpgradeService._onBayRequest(self, player: Player, slot: unknown)
	--- The ladder's own switches are checked further down, after the workshop has had its turn: the
	--- workshop's board is not an upgrade and works with the ladder off (`UpgradeConfig.Bay.Enabled`).
	if typeof(slot) ~= "Instance" or not slot:IsA("Model") then
		return
	end

	local now = os.clock()
	if now - (self._cooldowns[player] or 0) < UpgradeConfig.PurchaseCooldown then
		return
	end
	self._cooldowns[player] = now

	--[[ THE OWNERSHIP CHECK IS THE LOAD-BEARING ONE, and it is a containment test rather than a
		comparison of bay numbers: the kiosk pressed has to be standing on the plot this player holds.
		`_plotOf` is written only by `PlotService`'s assignment signal, so it is the server's answer to
		"whose lot is this" and not the client's. ]]
	local plot = self._plotOf[player]
	if not (plot and slot:IsDescendantOf(plot)) then
		return
	end

	local index = tonumber(slot:GetAttribute(GarageConfig.SlotIndexAttribute))
	if not index or index ~= index or index % 1 ~= 0 then
		return
	end

	local GarageService = Shard.get("GarageService")
	if not (GarageService and GarageService:isProfileReady(player)) then
		return
	end

	--[[ THE WORKSHOP'S KIOSK SELLS NOTHING (2026-09-28, `CustomizeConfig.Kiosk`): it is the workshop's
		sign, and a press on it is a press on the workshop — the screen with a car there, the picker
		without one. Checked after the ownership test above, so a visitor pressing it still does
		nothing at all. ]]
	if GarageService:isWorkshopBay(index) then
		if not GarageService:pressWorkshop(player) then
			GarageService:openPicker(player, index)
		end
		return
	end
	if not (UpgradeConfig.Enabled and UpgradeConfig.Bay.Enabled) then
		return
	end

	local level = GarageService:getBayLevel(player, index)
	local cost = UpgradeConfig.bayCostOf(level)
	if not cost then
		return -- already at the top of this bay's ladder
	end
	local cash = GarageService:getCash(player)
	if cash < cost then
		-- Redrawn rather than ignored, the same as the billboard: pressing a button you cannot afford
		-- should repaint the price you are short of.
		GarageService:refreshKiosks(player)
		-- ...and offered the gap, the same as the billboard. See the block on the tile handler above.
		local CashService = Shard.get("CashService")
		if CashService then
			CashService:offerTopUp(player, cost - cash, string.format("bay %d's upgrade", index))
		end
		return
	end

	GarageService:addCash(player, -cost)
	if not GarageService:setBayLevel(player, index, level + 1) then
		-- The profile went away between the balance check and the write. Give the money back rather
		-- than charging for a level that was never stored.
		GarageService:addCash(player, cost)
		return
	end

	--- Over the bay that changed (`UpgradeConfig.Celebrate`).
	for _, bay in GarageService:getBays(player) do
		if bay.index == index then
			self:_celebrate(bay.deck.Position + Vector3.new(0, bay.deck.Size.Y / 2, 0), level + 1, player)
			break
		end
	end
	self:getSignal("BayUpgradeBought"):Fire(player, index, level + 1, cost)
	self.log:info(string.format("%s upgraded bay %d to level %d for %d.", player.Name, index, level + 1, cost))
end

--[[ The purchase moment (`UpgradeConfig.Celebrate`).

	=== A MARKER, AND EVERY CLIENT DRAWS THE SHOW — 2026-10-07 ================================
	WAS: the billboard and sparkles built here and tweened here, which the owner called "very bland"
	— and server tweens replicate every step, so anything richer would have been choppy for everybody
	and a stream of property writes on the wire. NOW the server only drops an invisible, anchored marker
	at the spot, tagged and carrying the level, the floor height and the buyer; `UpgradeCelebration
	Controller` on every client sees it arrive and draws the whole thing locally (shockwaves, light,
	fountains, the banner). One replicated part per purchase, gone after `Seconds`.

	`at` is the spot on the floor: the bay's deck for a kiosk, the buyer's feet for the board. ]]
function UpgradeService._celebrate(self, at: Vector3, level: number, buyer: Player?)
	local cfg = UpgradeConfig.Celebrate
	if not cfg.Enabled then
		return
	end
	local marker = Instance.new("Part")
	marker.Name = "UpgradeCelebration"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1
	marker.Size = Vector3.one * 0.2
	marker.CFrame = CFrame.new(at)
	marker:SetAttribute("Level", level)
	marker:SetAttribute("Buyer", if buyer then buyer.UserId else 0)
	CollectionService:AddTag(marker, cfg.Tag)
	marker.Parent = workspace
	Debris:AddItem(marker, cfg.Seconds + 1)
end

-- === Lots ===================================================================

--[[ Bind a plot's billboard to its owner.

	Everything stamped onto the world goes in the assignment's trove, the same shape `PlotService`
	and `GarageService` both use and for the same reason: the release path is one `Destroy` rather
	than a hand-written list of undo statements that a later feature forgets to extend.

	The floor and the auto-collect timer are NOT applied here. Both depend on what the player has
	bought and the profile has not arrived yet at assignment time — `_onProfile` is the other half,
	and it is why this service listens to `ProfileReady` as well as to `PlotAssigned`. ]]
function UpgradeService._claim(self, player: Player, plot: Model)
	if self._lots[player] then
		return
	end

	local board = self._boards[plot]
	self._plotOf[player] = plot

	local trove = Trove.new()
	self._lots[player] = { plot = plot, trove = trove, autoTrove = nil }

	--[[ The board redraws when the owner's balance moves. It no longer has to: nothing drawn here
		reads the balance since the button stopped changing colour with it (2026-08-26). It is kept
		as the self-heal, because it is the one signal that fires often enough to correct a board
		that missed a purchase, and a redraw is a dozen string writes. `GarageConfig.CashAttribute`
		is the broadcast `GarageService` already publishes, so this costs no second remote. ]]
	trove:Add(player:GetAttributeChangedSignal(WorldConfig.UnlockAttribute):Connect(function() self:_redraw(player) end))
	trove:Add(player:GetAttributeChangedSignal(GarageConfig.CashAttribute):Connect(function()
		self:_redraw(player)
	end))

	trove:Add(function()
		self._plotOf[player] = nil
		--[[ Back to one deck, THEN blank the sign. In that order: taking the storey away destroys
			six podiums, and `refreshBays` on a released lot is what stops the next owner's cars being
			parked on them. ]]
		if self:_setFloor(plot, GarageConfig.BaseFloor) then
			local GarageService = Shard.get("GarageService")
			if GarageService then
				GarageService:refreshBays(plot)
			end
		end
		if self._boards[plot] then
			self:_draw(self._boards[plot], nil)
		end
	end)

	if board then
		self:_draw(board, player)
	end
end

function UpgradeService._release(self, player: Player)
	local lot = self._lots[player]
	if not lot then
		return
	end
	self._lots[player] = nil
	lot.trove:Destroy()
end

--[[ The profile has arrived for a player who already holds a lot: make the world match it.

	Both halves are here rather than in `_claim` because both need levels, and levels are the one
	thing that is not known at assignment. Running them twice is harmless — `_setFloor` is idempotent
	and `_restartAutoCollect` replaces its own trove — which is what lets `start` catch up on players
	who were already ready before this service connected. ]]
function UpgradeService._onProfile(self, player: Player)
	local lot = self._lots[player]
	if not lot then
		return
	end
	self:_applyFloor(player, lot.plot)
	self:_restartAutoCollect(player)
	self:_redraw(player)
end

-- === Lifecycle ==============================================================

UpgradeService:withLifecycle({
	init = function(self)
		self._boards = {} :: { [Model]: Board }
		self._lots = {} :: { [Player]: { plot: Model, trove: any, autoTrove: any } }
		self._plotOf = {} :: { [Player]: Model }
		self._cooldowns = {} :: { [Player]: number }
		self._trove = Trove.new()

		if not (UpgradeConfig.Enabled and PlotConfig.Enabled) then
			self.log:info("Disabled by config — no upgrade boards are bound.")
			return
		end

		--[[ `withDependencies` orders init, so PlotService has already discovered its plots. The
			empty-table fallback is for the case it has not: a disabled or failed PlotService should
			cost the game its upgrade boards, not take this service down with it. ]]
		local PlotService = Shard.get("PlotService")
		local plots = PlotService and PlotService:getPlots()
		if not plots then
			self.log:warn("No plots from PlotService — upgrade boards cannot be bound to owners.")
			return
		end

		local missing = {}
		for _, record in plots do
			--[[ Every plot starts the session on one deck whatever the place file says, so a place
				saved mid-test with a storey standing on it does not hand the first player who claims
				it a free upgrade.

				THE ATTRIBUTE IS SET FROM THE GEOMETRY FIRST, not assumed. `_setFloor` short-circuits
				when the plot already says it is on the floor being asked for, so stamping 1 onto a
				plot that has a Floor2 standing in it would make the teardown a no-op and leave the
				storey there for the rest of the session — the one case this whole block exists to
				catch. Look at the building, tell the attribute what is really there, then lock it. ]]
			local building = record.model:FindFirstChild(BUILDING_NAME)
			local standing = building and building:FindFirstChild(FLOOR2_NAME)
			record.model:SetAttribute(UpgradeConfig.PlotFloorsAttribute, if standing then 2 else GarageConfig.BaseFloor)
			self:_setFloor(record.model, GarageConfig.BaseFloor)

			--[[ THE MACHINE REPLACES THE BOARD (2026-10-14, the owner: "I don't want it in a SurfaceGui
				any more, I want a proximity prompt and JUST the ScreenGui"). Every board face on the plot
				is switched off and none is bound or drawn, so the screen in the cabinet is just its art.
				`UpgradeController` skips binding them for the same flag. Off: the billboard, as before. ]]
			if UpgradeConfig.Machine.Enabled then
				self:_wireMachine(record.model)
				for _, gui in record.model:GetDescendants() do
					if gui:IsA("SurfaceGui") and (gui.Name == UpgradeConfig.Board.GuiName or gui.Name == UpgradeConfig.Board.KitGuiName) then
						gui.Enabled = false
					end
				end
				continue
			end

			local board = self:_discoverBoard(record.model)
			if board then
				self._boards[record.model] = board
				self:_draw(board, nil)
			else
				table.insert(missing, record.model.Name)
			end
		end

		if #missing > 0 and not UpgradeConfig.Machine.Enabled then
			self.log:warn(string.format("No upgrade board on: %s — run BuildPlotUpgradeSigns.", table.concat(missing, ", ")))
		end
		self.log:info(string.format("%d upgrade board(s) bound.", #plots - #missing))
	end,

	start = function(self)
		if not (UpgradeConfig.Enabled and PlotConfig.Enabled) then
			return
		end

		local PlotService = Shard.get("PlotService")
		local GarageService = Shard.get("GarageService")
		local plots = PlotService and PlotService:getPlots()
		if not (plots and GarageService) then
			return
		end

		self._trove:Add(PlotService:getSignal("PlotAssigned"):Connect(function(player: Player, plot: Model)
			self:_claim(player, plot)
		end))
		self._trove:Add(PlotService:getSignal("PlotReleased"):Connect(function(player: Player)
			self:_release(player)
		end))
		self._trove:Add(GarageService:getSignal("ProfileReady"):Connect(function(player: Player)
			self:_onProfile(player)
		end))

		--[[ Catch up on lots already claimed, and on profiles that already arrived. `PlotService`
			assigns inside its own `start`, so on a hot reload a player can be standing on a working
			lot with a loaded profile before any of the three connections above exist — without this
			they would have a blank board and no second storey until they rejoined. ]]
		for _, record in plots do
			if record.owner then
				self:_claim(record.owner, record.model)
				if GarageService:isProfileReady(record.owner) then
					self:_onProfile(record.owner)
				end
			end
		end

		self._trove:Add(Players.PlayerRemoving:Connect(function(player: Player)
			self:_release(player)
			self._cooldowns[player] = nil
		end))
	end,
})

UpgradeService:withCleanup(function()
	if UpgradeService._trove then
		UpgradeService._trove:Destroy()
	end
end)

return UpgradeService
