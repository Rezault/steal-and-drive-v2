--[[
	CarPaint  (shared)
	------------------
	Which parts of a car are the paintwork, and how to change their colour. One module, because four
	very different callers have to agree on the answer to exactly the same question — a traffic shell
	being tinted on the client, the car you drive away in after a steal, the display car on a garage
	podium, and the one you park in the street — and any two of them disagreeing shows up as a car
	whose colour changes when you look at it from somewhere else.

	=== PAINTING IS CLEARING A TEXTURE, NOT SETTING A COLOUR ===================================

	The roster's paint lives in an IMAGE. Every body panel on the world-1 cars is a MeshPart with a
	`TextureID` and a `Color` sitting at the untouched default 163,162,165; the stock Charger is blue
	because image 73699211191693 is blue. Setting `Color` on a panel that still has its texture does
	nothing whatsoever on screen — measured in the place on 2026-08-04, not inferred.

	So `paint` clears `TextureID` and then writes `Color`. The pack's textures are flat colour, so
	what comes out is the same car in a different paint rather than a car that has lost its detailing.

	IT IS ONE-WAY ON THE PART, which is why every caller in this game paints a CLONE — a traffic shell,
	a grafted dress, a display body, a lobby car — and never `Workspace.CarSystem`. Painting a roster
	car would strip the texture out of the master copy and there is no undo for that. `capture` and
	`restore` exist for the one caller that needs a part to go back (the pooled traffic shells), and
	they are how "this car rolled Stock this time" is honoured without a second copy of the body.

	=== WHICH PARTS ARE THE PAINTWORK ==========================================================

	Neither of the two obvious rules works on its own, and both failures are real cars in this place:

	  • BY NAME (`shell_01_body`, the old `TrafficConfig.BodyMeshMatch`) misses the panels an artist
	    did not name for it. The Charger paints its `trim_01` and both `trim_chrome_*` in body colour,
	    so a name-only repaint leaves three blue flecks on an otherwise red car.
	  • BY TEXTURE (everything sharing the shell's image) is far too greedy, and not on a couple of
	    odd cars — on MOST of them. Re-counted 2026-08-25: 26 of the 29 shipping cars put the whole
	    car on ONE image, body and wheels and lenses and steering wheel together, so texture alone
	    would paint the lot. The veto below is carrying 5 to 17 parts per car, not a handful overall.
	    The Camaro is the worst of it, because the one image its body sits on is the SHARED atlas the
	    rest of the pack trims and grilles with — see `grille` in `HARDWARE`.

	So the rule is both, with a veto:

	  1. a part whose name carries a `body` TOKEN is paintwork, always;
	  2. so is a part carrying the same `TextureID` as those panels —
	  3. UNLESS its name carries a hardware token (`wheel`, `glass`, `lens`, `light`, `grille`, ...),
	     which is what keeps the Camaro's wheels and grille and the M5's steering wheel out of it.

	TOKENS, NOT SUBSTRINGS, and that is not fussiness. `trim` contains `rim`: a naive substring veto
	drops every trim panel in the pack, which is precisely the Charger bug above wearing a different
	hat. Names in this pack are `snake_case` (`trim_chrome_01`, `wheel_FL`, `light_red_01`), so they
	split cleanly on their separators.

	Rule 1 beats rule 3 on purpose. The Lambo redress renamed its `*_wheel_cap_body` and
	`*_door_mirror_base_body` parts INTO the body match precisely because they are body-coloured — an
	explicit `body` in a name is a person saying so, and it outranks the guess.

	THE F40 IS THE OTHER ONE, and it is worth knowing about because the rename is IN THE PLACE and so
	is invisible from this repo. Three of its nose parts were renamed on 2026-08-25 —
	`light_01`/`light_02` -> `light_01_body`/`light_02_body`, and `lens_clear_02` ->
	`lens_clear_02_body`. Despite the names all three are bodywork: two full-width bars and the bezel
	around the pop-up headlights, all body-coloured on the car the artist drew. Vetoed by `light` and
	`lens` they kept the artist's RED, so a black F40 wore two bright red rectangles across its nose —
	reported from a playtest as "red headlights when black car". The `light_white_*` lamps beside them
	are real lamps and are still, correctly, vetoed.

	Do not try to solve that class of thing by loosening `light` or `lens`. Eleven other rigs use a
	bare `light_NN` for a genuine lamp sliver, and all 22 `light_housing_*` parts across the roster
	are real lamp units — checked by painting each and looking. The rename is the narrow fix, and
	rule 1 exists so that a person who has looked at the car can overrule the guess.

	THE M5 HAS THE SAME PAIR, found 2026-09-01 while chasing its door band: `lens_clear_01` and
	`lens_clear_02` are its wing-mirror blades, opaque and drawn in the body colour, not lenses at
	all. Vetoed by `lens` they kept the artist's navy, so a bronze M5 wore a blue stripe across each
	mirror. Renamed `lens_clear_01_body` / `lens_clear_02_body` in the place, which took the M5 from
	5 painted parts to 7.

	THE M5 AND THE SKYLINE R34 ARE THE SAME STORY POINTING THE OTHER WAY, and their renames are in
	the place too. Both carried their whole cabin (seats, bench and centre console, one mesh) as
	`shell_04_body`, so rule 1 painted it and every non-Stock M5 had a body-coloured interior showing
	through its glass. Reported from the dealership as "the interior got tagged as well". Renamed to
	`interior` on 2026-08-26, which `HARDWARE` then vetoes; the M5 went from 6 painted parts to 5.

	THAT ONE WAS FOUND BY MESH IDENTITY, NOT BY EYE AND NOT BY GEOMETRY, and that is the cheap way to
	audit this. Eleven pack A cars name that exact mesh (`112061435627333`) `interior` and only the M5
	named it otherwise; the Skyline's cabin (`106691015307076`) is the Senna's `interior`. So: group
	every body part in the roster by `MeshId`, and any group this module answers differently for is a
	naming mistake on one of its members. Run over all 65 rigs it returned exactly those two, which is
	the whole audit in one query. Geometry does not work here. "Buried inside the hull", "swallows the
	driver seat" and "small relative to the shell" all sweep in bumpers, spoilers and rear body
	sections, and isolating a candidate to photograph it costs one render per part.

	=== WHEN THERE IS NOTHING TO VETO: THE DETAIL MAP ==========================================

	The rule above can only protect a grille that is its OWN mesh. On the ten cars whose parts carry a
	`grille_01` it is, and a repaint leaves a proper dark mouth. On the M5 the entire car — panels,
	kidney grille, lower intakes, headlight bezels, window surround — is one mesh, so rule 1 takes the
	lot and a white M5 came out uniformly white with no front end at all. Reported as "the grille and
	trim got coloured the same, it all blends together", which is exactly what it is.

	A DETAIL MAP fixes it without touching the mesh or renaming anything. It is a copy of that car's
	own texture with the body colour punched out to alpha 0, worn as a `SurfaceAppearance` with
	`AlphaMode = Overlay` — and Overlay means "show the part's `Color` wherever this image is
	transparent". So the paint lands exactly where the body colour was, every other pixel the artist
	drew survives, and ONE image covers all fourteen palette colours.

	IT IS AN INSTANCE IN THE TREE AND NOT AN ASSET ID IN A CONFIG, and that is not a style choice:
	`SurfaceAppearance.ColorMap` is Plugin-capability only, so a game script that builds one throws
	"The current thread cannot write 'ColorMap'" — which is what the first version of this did, from
	the dealership grid, on the client. `Clone()` copies the property without writing it, so the maps
	are authored once in `ReplicatedStorage.shared.PaintDetails` (`src/shared/PaintDetails.rbxmx`),
	one per body, named after the body, and `paint` clones the right one onto each painted MeshPart.
	Nothing here ever assigns a ColorMap.

	IT CANNOT READ ONE EITHER, which is the half that is easy to miss because it does not show up
	until the second paint: `detail.ColorMap ~= template.ColorMap` throws "cannot read 'ColorMap'"
	just as loudly. Every map property is gated the same way, `RoughnessMap` included, so a diagnostic
	that only prints what a clone is wearing will throw as readily as one that assigns. Which map a part is wearing is kept in a `Body` ATTRIBUTE on the clone instead.
	Nothing in this game may touch that property from a game script, in either direction — a plugin
	console will happily do both, so test this path from a real script and not from `execute_luau`.

	THE HOLE IS NOT ONE SWATCH, IT IS EVERY COLOUR ON THE SHEET, and getting that wrong is what the
	M5's "artifact on the side" was. These textures are palette atlases: a flat filler grey over most
	of the sheet, a grid of ~12px colour swatches in one corner, and livery art (sponsor logos,
	racing stripes) the pack shares between cars. Punching only the body's own swatch left two marks,
	and neither is visible on the stock car, which is why both read as paint bugs rather than art
	ones: the door panel UVs onto the STRIPES rather than onto the grid and came out with a hard dark
	band down its leading edge, and the wing-mirror blades sample a DIFFERENT blue swatch from the
	one the body panels use and came out with a blue stripe across each. Navy on navy is navy until
	you paint it bronze. The first mask therefore kept only the NEUTRAL swatches and punched every
	chromatic one, all the livery art and all the filler grey.

	THAT RULE WAS TOO BLUNT AND IT COST THE MIRROR GLASS, corrected 2026-09-02. Neutral covered the
	M5's kidney grilles, surrounds, bezels and intakes, so it shipped looking right, but the pale
	mint the wing-mirror GLASS samples is chromatic and got punched with everything else, so a
	repainted M5 wore a body-coloured mirror. Reported as "white mirror like the other cars".

	THE RULE NOW KEYS ON DISTANCE FROM THE CAR'S OWN BODY COLOUR INSTEAD OF ON HUE. Punch a swatch
	if it is within a cut of the colour the car's painted meshes actually draw, punch the filler,
	and keep everything else whatever colour it is. That still punches both of the things the
	neutral rule was really aiming at, because the livery stripes and the mirror-blade swatch are
	both drawn in the car's own navy and so match by colour wherever they sit on the sheet, and it
	stops throwing away authored detail for the crime of not being grey. Which colour a car's body
	actually is gets MEASURED, by rendering only the parts `parts` returns under flat light and
	histogramming them against the atlas; it is not guessed off the sheet, because on four of the
	six cars with a map the big filler colour is not the body colour at all.

	Safe either way, because the map is only ever cloned onto parts that are being painted anyway.
	`assets/paint/README.md` is the whole procedure, including how to preview a map without
	uploading it.

	AND EVERY MAP CARRIES A FLAT RoughnessMap, which is not decoration. A `SurfaceAppearance` with no
	roughness map renders its part far glossier than the plain material it replaced, and on a car
	that is a dark smear down every crease, worst at the door shut line where it looks exactly like
	one more texture bug. One flat grey image (0.60) is shared by every entry and cancels it; A/B it
	by pulling the detail off one panel and comparing the same crease. `MetalnessMap` stays empty,
	because absent means 0 and that is what paint wants.

	A car with no entry in that folder takes the flat path unchanged, which is almost all of them.
	`assets/paint/README.md` is how the image inside one is made — the packs are not owned by this
	account, so the texture has to be photographed out of the viewport and rebuilt rather than read.

	=== WORKS ON A RIGGED CAR AND ON A FLAT SHELL ==============================================

	A rigged car nests its dress under `Body/`, with the wheel visuals in per-corner models; a traffic
	shell (`TrafficService._buildShell`) is a flat bag of meshes welded to one `Root`. Both are handed
	to this module, so it takes the `Body` folder where there is one and the model itself where there
	is not, and walks descendants either way.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)

local CarPaint = {}

-- The dress container on a rigged car. Absent on a traffic shell, which is the flat case.
local BODY_FOLDER = "Body"

--[[ The name every `SurfaceAppearance` this module hangs on a part is given, so it can be told from
	one an artist put there. `paint` reuses its own by name rather than adding a second, and `restore`
	destroys it — a pooled shell that rolls `Stock` after being painted has to lose the detail map
	along with the colour, or it wears a hole where the paint used to be. ]]
local DETAIL_NAME = "PaintDetail"

-- Where the authored detail maps live, as a child of `shared` (header). Looked up per call rather
-- than latched, for the same reason the traffic templates are: a latched nil would be permanent.
local DETAILS_FOLDER = "PaintDetails"

--[[ Parts that are never paintwork whatever they are called or textured with.

	`HitBox` is the chassis's own invisible hull — it lives under `Body/` but belongs to the rig, owns
	Health, and is the volume the wall sensor rides. `Root` and `Hit` are the shell's own two
	structural parts. All three are invisible anyway, so the transparency filter below would catch
	them; they are named here because "we deliberately do not paint the hull" is worth being able to
	read. ]]
local STRUCTURAL = { HitBox = true, Root = true, Hit = true }

-- The token that says "this is bodywork" outright. Lower case; names are tokenised the same way.
local BODY_TOKEN = "body"

--[[ Tokens that veto a texture match. These are the parts that share a body's texture on the two
	cars whose shell sits on the shared atlas, and none of them should ever take the paint: a repaint
	that turns the headlights or the wheels body-colour is the single most obvious way this can look
	broken. An explicit `body` token overrides every one of them — see the header.

	`grille` IS HERE FOR THE CAMARO ALONE, and on every other car in the game it changes nothing —
	audited 2026-08-25, rig by rig, by painting a clone of all 65 and photographing it. Everywhere
	else a car's `grille_01` sits on the shared trim atlas rather than on that car's own body texture,
	so rule 2 never reached it and the veto costs nothing. The Camaro is the exception because ITS
	BODY TEXTURE *IS* THAT SHARED ATLAS (97212220316378): rule 2 resolved the body texture to the
	image every other car grilles and trims with, and swept the grille in. A painted Camaro had its
	grille and lower bumper intake in body colour, which on a light paint left the front end with no
	definition at all — the car read as a featureless lozenge. It is a world-1 car, so that was one of
	the most-seen cars in the game. With the veto it keeps the authored dark mouth in every colour.

	`trim` IS DELIBERATELY *NOT* HERE, and this is the trap. It looks like the same bug — the Camaro's
	`trim_01`..`trim_05` and the Charger's `trim_01`/`trim_chrome_*` are swept in by rule 2 exactly
	the way `grille_01` was. But those panels really are bodywork on both cars, which is the case the
	header's first bullet describes and the reason rule 2 exists. Vetoing `trim` was tried and
	photographed: it leaves the A-pillar, the window surround and a mirror in the car's ORIGINAL blue
	on an otherwise red car. Adding it would trade one visible defect for a worse one.

	`matte` IS A NAMING CONVENTION RATHER THAN A DESCRIPTION OF SOMETHING THAT WAS ALREADY THERE.
	Added 2026-09-01 with the C7's front splitter, the first of a class the roster audit found on 23
	ownable bodies: a mesh the artist drew ENTIRELY in flat black, a splitter or a valance or a wing
	or a bank of louvres, that happens to carry a `body` token and so gets painted whole. Dropping the
	`body` token is not enough on those cars, because the whole vehicle sits on ONE texture and rule 2
	sweeps the part straight back in; the new name has to carry a veto of its own. `interior` fits a
	cabin (M5, Skyline R34) and `grille` fits a mouth, but an exposed black aero part is neither, and
	borrowing a veto by calling a splitter `grille_02` puts a lie in the Explorer for whoever opens it
	next. So this token says exactly what it means: the artist drew this matte black, never paint it.

	NOTHING IN THE PLACE WAS NAMED `matte` BEFORE THIS LINE, checked across `Workspace.CarSystem` rig
	by rig, so adding it cannot change any car that exists today. It can only ever affect a part
	somebody renames on purpose. The candidate list is `docs/paint-audit-2026-09-01.md` §1a.

	Whatever is added here has to stay a TOKEN match and not a substring, for the reason the header
	gives from the other direction: `trim` contains `rim`, so the two are the same test read
	backwards, and a substring veto for either one silently eats the other. ]]
local HARDWARE = {
	wheel = true,
	rim = true,
	tyre = true,
	tire = true,
	hub = true,
	brake = true,
	glass = true,
	window = true,
	light = true,
	lens = true,
	grille = true,
	matte = true,
	interior = true,
	seat = true,
	dash = true,
	console = true,
	steering = true,
	plate = true,
	exhaust = true,
}

--[[ Split a part name into lower-case word tokens.

	Anything that is not a letter is a separator, so `trim_chrome_01` is {trim, chrome} and `wheel_FL`
	is {wheel, fl}. Digits fall out entirely, which is what makes `shell_01_body` and `shell_1_body`
	the same thing to this rule. ]]
local function tokensOf(name: string): { [string]: boolean }
	local out = {}
	for word in string.gmatch(string.lower(name), "%a+") do
		out[word] = true
	end
	return out
end

-- The dress: `Body/` on a rigged car, the model itself on a flat traffic shell.
local function dressOf(model: Instance): Instance?
	if not model then
		return nil
	end
	return model:FindFirstChild(BODY_FOLDER) or model
end

--[[ The texture the bodywork is painted with, read off the panels that SAY they are bodywork.

	The most common one rather than the first found: a body can carry a stray panel on another image
	(the Charger's `trim_01` sits on the body texture, and the reverse happens too), and the answer
	wanted here is "what is most of this car painted with". nil for a car whose panels carry no
	texture at all, which is both an untextured redress and a body this module has ALREADY painted —
	in that case rule 2 simply contributes nothing and the `body`-named panels still resolve. ]]
local function bodyTextureOf(dress: Instance): string?
	local tally, best, winner = {}, 0, nil
	for _, inst in dress:GetDescendants() do
		if inst:IsA("MeshPart") and inst.TextureID ~= "" and tokensOf(inst.Name)[BODY_TOKEN] then
			local count = (tally[inst.TextureID] or 0) + 1
			tally[inst.TextureID] = count
			if count > best then
				best, winner = count, inst.TextureID
			end
		end
	end
	return winner
end

--[[ The parts of `model` that take a car's paint. See the header for the rule and why it is that
	rule; the whole of it is the three conditions below.

	Returns an empty list rather than nil for a model with no dress, so every caller can count what
	came back instead of branching — "the repaint found nothing to do" is a state worth being able to
	log, and it is how a body rigged wrong reads. ]]
function CarPaint.parts(model: Instance): { BasePart }
	local parts = {}
	local dress = dressOf(model)
	if not dress then
		return parts
	end
	local bodyTexture = bodyTextureOf(dress)

	for _, inst in dress:GetDescendants() do
		if not (inst:IsA("BasePart") and not STRUCTURAL[inst.Name] and inst.Transparency < 1) then
			continue
		end
		local tokens = tokensOf(inst.Name)
		if tokens[BODY_TOKEN] then
			table.insert(parts, inst) -- rule 1: said so in its name, and that beats everything
			continue
		end
		if not (bodyTexture and inst:IsA("MeshPart") and inst.TextureID == bodyTexture) then
			continue
		end
		local hardware = false
		for token in tokens do
			if HARDWARE[token] then
				hardware = true
				break
			end
		end
		if not hardware then
			table.insert(parts, inst) -- rule 2, having survived rule 3
		end
	end
	return parts
end

--[[ Remember what these parts looked like before they were painted, so they can be put back.

	FOR POOLED SHELLS, and really only for them: `TrafficController` builds one record per body and
	hands it out over and over, so a car that rolls `Stock` after a record has already been painted
	red has to get its texture back from somewhere. Everything else in this game paints a fresh clone
	and throws it away.

	A `SurfaceAppearance` is UNPARENTED rather than destroyed, for exactly that reason — see `paint`
	for why it has to move at all. Holding the instance means restoring it is a re-parent, and the
	shell can go back to being genuinely stock rather than approximately stock. ]]
export type Captured = { { part: BasePart, texture: string?, color: Color3, surface: SurfaceAppearance? } }

function CarPaint.capture(parts: { BasePart }): Captured
	local out = {}
	for _, part in parts do
		local authored = nil
		for _, child in part:GetChildren() do
			if child:IsA("SurfaceAppearance") and child.Name ~= DETAIL_NAME then
				authored = child
				break
			end
		end
		table.insert(out, {
			part = part,
			texture = if part:IsA("MeshPart") then part.TextureID else nil,
			color = part.Color,
			surface = authored,
		})
	end
	return out
end

-- Put a captured set back exactly as it was. Skips anything that has since been destroyed, so a
-- teardown racing a restore is a no-op rather than an error.
function CarPaint.restore(captured: Captured?)
	for _, entry in captured or {} do
		local part = entry.part
		if not part.Parent then
			continue
		end
		for _, child in part:GetChildren() do
			if child:IsA("SurfaceAppearance") and child.Name == DETAIL_NAME then
				child:Destroy()
			end
		end
		if entry.texture and part:IsA("MeshPart") then
			part.TextureID = entry.texture
		end
		part.Color = entry.color
		if entry.surface and entry.surface.Parent ~= part then
			entry.surface.Parent = part
		end
	end
end

--[[ Paint a set of parts. Returns how many took the colour.

	Three writes per part, and each one is load-bearing:

	  • `TextureID = ""` — the texture is the paint on this roster, and it beats `Color` outright.
	    Without this line the function is a silent no-op on every car in the game (header).
	  • `Color` — what the panel is now.
	  • an artist's `SurfaceAppearance`, if any, is UNPARENTED. A ColorMap beats `Color` for the same
	    reason a TextureID does, so a panel wearing one would be the only part of the car that did not
	    change and the result reads as a half-finished repaint. No body on the current roster has one —
	    this is here for the packs that do, and it moves rather than dies so `restore` can undo it.

	`template` is the fourth thing, and only some cars have one — `CarPaint.detailFor` is where it comes
	from. Given one, this CLONES it onto every painted MeshPart as `PaintDetail`, so the colour shows
	through the holes in that image and the artist's grille and trim come back. Cloned and never built,
	because `ColorMap` cannot be written by a game script (header); reused by name rather than added
	twice, because the traffic pool paints the same parts over and over. ]]
function CarPaint.paint(parts: { BasePart }, color: Color3, template: SurfaceAppearance?): number
	local painted = 0
	for _, part in parts do
		if part:IsA("MeshPart") and part.TextureID ~= "" then
			part.TextureID = ""
		end
		local detail, authored = nil, nil
		for _, child in part:GetChildren() do
			if child:IsA("SurfaceAppearance") then
				if child.Name == DETAIL_NAME then
					detail = child
				else
					authored = child
				end
			end
		end
		if authored then
			authored.Parent = nil
		end
		if template and part:IsA("MeshPart") then
			--[[ Which map a part is already wearing is remembered in an ATTRIBUTE and not read back off
				the instance, because `ColorMap` cannot be READ from a game script either — the same
				capability that stops this module building one stops it comparing two. The check earns
				its place on the steal: `swapMeshes` carries a `SurfaceAppearance` across, so a part can
				arrive wearing the map of the car it was cut from rather than the one being painted. ]]
			if detail and detail:GetAttribute("Body") ~= template.Name then
				detail:Destroy()
				detail = nil
			end
			if not detail then
				detail = template:Clone()
				detail.Name = DETAIL_NAME
				detail:SetAttribute("Body", template.Name)
				detail.Parent = part
			end
		elseif detail then
			detail:Destroy()
		end
		part.Color = color
		painted += 1
	end
	return painted
end

--[[ The authored detail map for a body, or nil for a car that does not need one — which is almost
	all of them, so this answers nil far more often than not.

	Returns the TEMPLATE, which callers hand to `paint` and `paint` clones. Never parent this one to a
	part: it is the only copy, every car painted after that would find the folder empty, and the fault
	would show up as cars quietly going back to bleached rather than as an error. ]]
function CarPaint.detailFor(body: unknown): SurfaceAppearance?
	if type(body) ~= "string" then
		return nil
	end
	local shared = ReplicatedStorage:FindFirstChild("shared")
	local folder = shared and shared:FindFirstChild(DETAILS_FOLDER)
	local entry = folder and folder:FindFirstChild(body)
	return if entry and entry:IsA("SurfaceAppearance") then entry else nil
end

--[[ The whole job for a caller holding a model and a palette index: resolve the parts, look up the
	colour, paint. Returns how many parts changed.

	A `Stock` index — and an index this build does not have a colour for — paints NOTHING and returns
	0, which is the correct outcome rather than a failure: the car is already wearing the livery its
	artist gave it. Callers that need to tell "no paint wanted" from "no paint possible" should ask
	`PaintConfig.colorOf` first; `GarageService` and `LobbyCarService` deliberately do not, because on
	a fresh clone the two mean the same thing.

	`body` is the roster name of the car — "M5", "Camaro" — and is what looks up its detail map. It is
	passed rather than read off `model` because half these callers hold a rigged car named after its
	player and half hold a clone named after the body, and a fallback that guessed would be wrong
	exactly where it mattered. Omitting it costs the detail map and nothing else, so a caller that
	genuinely does not know one still repaints; `CarPlate.apply` takes the same argument for the same
	reason and reads the same way at every call site. ]]
function CarPaint.apply(model: Instance, index: unknown, body: unknown): number
	local color = PaintConfig.colorOf(index)
	if not color then
		return 0
	end
	return CarPaint.paint(CarPaint.parts(model), color, CarPaint.detailFor(body))
end

return CarPaint
