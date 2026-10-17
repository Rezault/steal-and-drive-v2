--[[
	PaintConfig
	-----------
	What colour a car is. One palette for the whole game, an optional per-body pool picking which
	of it that model can turn up in, and one small integer that travels from the car you drove past
	all the way into your save file.

	=== WHY A PALETTE INDEX AND NOT A COLOUR ===================================================

	A `Color3` cannot be stored in a datastore, cannot ride an attribute without being encoded, and
	cannot be validated by the server — a client that sends one can send any of the sixteen million.
	So what moves through the game is the INDEX of an entry in `Palette` below: one integer, storable,
	checkable against a per-body pool, and the same three bytes whether the car is white or magenta.

	THAT MAKES `Palette` AN APPEND-ONLY LIST. Index 7 is written into save files the moment a player
	banks a car, so reordering the table repaints every car every player owns, and deleting an entry
	strands the ones that pointed at it. Add to the bottom; never insert, never reorder, never remove.
	Recolouring an existing entry IS allowed and is the intended way to re-tune — it repaints that
	colour everywhere at once, which is what you want.

	=== HOW A CAR ACTUALLY GETS PAINTED, AND WHY IT IS NOT `part.Color` ========================

	The roster's paint is not a colour, it is a TEXTURE. Every body panel on all 8 world-1 cars is a
	MeshPart with a `TextureID` and a `Color` left at the default 163,162,165 — the blue of the stock
	Charger comes entirely from image 73699211191693. Measured 2026-08-04, and measured the hard way:
	setting `Color` on those panels with the texture still on them changes NOTHING on screen. A
	MeshPart's TextureID wins outright.

	So painting a car means CLEARING THE TEXTURE and then setting the colour, which `Modules/CarPaint`
	does. The textures turn out to be flat colour anyway — the cars come out clean, and the wheels,
	glass, lights and lenses keep theirs because they are on their own textures (see CarPaint for the
	rule that tells those apart). It is also strictly one-way, which is why every caller paints a
	CLONE and never the roster.

	Index 1 is `Stock`: no repaint at all, the livery the artist authored. It is a real palette entry
	rather than a special case so that "this car is the blue one it has always been" is something a
	save file can hold and a pool can weight.

	AND SOME CARS ARE ONLY EVER STOCK. Because the paint IS the texture, a car whose texture carries
	artwork — stripes, sponsor decals, a two-tone split — cannot be recoloured without erasing that
	artwork. Those are listed in `KeepLivery` below and are locked to their own paint. There is no
	code fix for it; recolouring them needs recoloured copies of their livery images.
]]

local PaintConfig = {}

-- Master switch. Off = every car in the game wears its authored livery, exactly as before this
-- file existed, and nothing is stored or read. The one lever to pull if a repaint ever looks wrong
-- on a body that has just been added.
PaintConfig.Enabled = true

--[[ === The palette ==========================================================================

	APPEND ONLY — see the header. The index is save data.

	Chosen to read at chase-camera distance and against this game's road: saturated primaries a
	player can name from thirty studs back, plus enough neutrals (white / black / silver / graphite)
	that a lane of traffic does not look like a bag of sweets. The `Name` is not displayed anywhere
	yet; it is here so that a designer editing this table and a programmer reading a log are talking
	about the same colour.

	`Color = nil` means "do not repaint". Only `Stock` has it, and only `Stock` should. ]]
PaintConfig.Palette = {
	{ Name = "Stock", Color = nil }, -- 1 — the artist's own livery, untouched
	{ Name = "White", Color = Color3.fromRGB(238, 238, 238) }, -- 2
	{ Name = "Black", Color = Color3.fromRGB(28, 28, 31) }, -- 3
	--[[ 4 — Silver. DARKENED HARD 2026-08-25, from 172,177,183, because at that value it was not a
		second colour: `Lighting.Ambient` is 218,202,232 with `Brightness` at 2, which lifts a light
		mid-tone until it clips, and Silver and White (2) came out of the same render as the same
		white car. Two of fourteen slots were one slot. Re-checked with the ambient halved and they
		still collapsed, so this is the palette's problem and not the lighting's.

		THE VALUE HERE WAS PICKED OFF A RENDER, NOT REASONED. That matters, because reasoning gets it
		wrong: the first attempt at 140,146,154 is a third of the way to black on paper and still came
		out of the engine looking white. A ladder of 140 / 122 / 106 / 92 photographed on a Camaro put
		the first honest silver at 106 — clearly not White above it, clearly not Graphite (5) below.
		Anything lighter than about 120 in this place is another white car. Re-shoot the ladder rather
		than nudging the number if the lighting is ever re-tuned.

		Recolouring an entry is the sanctioned edit — the header explains why, and why reordering one
		is not. ]]
	{ Name = "Silver", Color = Color3.fromRGB(106, 113, 123) },
	{ Name = "Graphite", Color = Color3.fromRGB(68, 72, 79) }, -- 5
	{ Name = "Red", Color = Color3.fromRGB(198, 32, 38) }, -- 6
	{ Name = "Blue", Color = Color3.fromRGB(26, 72, 190) }, -- 7
	{ Name = "Cyan", Color = Color3.fromRGB(44, 178, 214) }, -- 8
	{ Name = "Lime", Color = Color3.fromRGB(124, 198, 52) }, -- 9
	{ Name = "Yellow", Color = Color3.fromRGB(246, 200, 42) }, -- 10
	{ Name = "Orange", Color = Color3.fromRGB(238, 128, 30) }, -- 11
	{ Name = "Purple", Color = Color3.fromRGB(122, 58, 188) }, -- 12
	{ Name = "Pink", Color = Color3.fromRGB(238, 112, 178) }, -- 13
	{ Name = "Racing Green", Color = Color3.fromRGB(24, 108, 70) }, -- 14
	{ Name = "Bronze", Color = Color3.fromRGB(164, 110, 56) }, -- 15
}

--[[ === Which colours a given car can be ======================================================

	A pool is a list of PALETTE INDICES, and a body with no entry here can be any of them. Empty on
	purpose: the whole point of the feature is a road that is not one colour, and hand-restricting 43
	cars before anyone has looked at them is work that would mostly be undone.

	REPEATING AN INDEX IS THE WEIGHTING KNOB, and it is the only one — `roll` picks uniformly from the
	list, so a pool that names `Stock` three times makes that car wear its own livery three times as
	often. That is deliberately cruder than a weight table: a weight table is a second thing to keep
	in step with the palette, and this is a list of numbers a designer can read.

	Reach for this when a specific model looks wrong in a specific colour. Examples:

		["Model 3"] = { 1, 2, 3, 4, 5, 6 },   -- the Tesla stays in showroom colours
		["Civic"] = { 1, 1, 1 },              -- always stock, three ways of saying so

	For a car that must never be repainted at all, use `KeepLivery` below rather than writing `{ 1 }`
	here — it says WHY. ]]
PaintConfig.Pools = {}

--[[ === Cars that must never be repainted ====================================================

	A LIVERY AND A PAINT ARE THE SAME IMAGE ON THIS ROSTER, so there is no way to recolour one of
	these cars and keep its artwork. There is not a single `Decal` or `Texture` instance on any of the
	49 bodies — checked, not assumed — which means every stripe, sponsor decal and two-tone split is
	painted into the body panels' `TextureID`. `CarPaint` works by clearing that texture, so a repaint
	does not sit on top of the art, it replaces it: the orange F&F Supra comes out a flat orange car
	with its decals gone.

	Recolouring these properly is an ART job, not a code one — it needs a recoloured variant of each
	livery uploaded as its own image. Until that exists, these keep what their artist drew.

	IDENTIFIED BY EYE, 2026-08-04, by photographing the whole roster. None of world 1's eight cars is
	liveried, so nothing currently on the road is affected — this list is here so worlds 2-4 do not
	ship with their signature cars stripped.

	HOW TO CHECK A NEW ONE: paint it and look at it. There is no property that distinguishes a flat
	texture from a decorated one, and the texture images cannot be read back (the packs are not owned
	by this account, so `AssetService:CreateEditableImageAsync` refuses them) — a screenshot is the
	only test. If in doubt, add it here: a car that keeps its livery is a small loss, a car that loses
	one is a broken-looking car. ]]
PaintConfig.KeepLivery = {
	"350Z", -- green over black, Tokyo-Drift style graphics
	"SUPRA MK4", -- the orange F&F car, decals down both flanks
	"M3 GTR", -- blue/silver Most-Wanted livery
	"F&F EVO", -- red with white graphics and sponsor decals
	"RX7 F&F", -- orange over black, two-tone split baked into the texture
	"Skyline R34", -- blue/silver with stripes
	"i8", -- black body with white accent panels
	--- 2026-10-09: ONE texture atlas for the whole car, and its door/windscreen meshes carry their
	--- glass IN that texture (the export names them `windows`). A repaint would paint the windows
	--- over. Not a livery, but the same reason: the art cannot be recoloured without losing detail.
	"Maybach",
}

--[[ === Cars whose DETAIL is in the texture too ==============================================

	A repaint clears the body panel's texture and writes a flat colour, which is right for a car whose
	grille and trim are their own meshes and wrong for one where they are the same mesh as the wings —
	the M5 came out of a repaint with its kidney grille, its intakes and its window surround all the
	same white as its bodywork. There is no entry for that here and there deliberately isn't one: the
	fix is a DETAIL MAP, and it has to be an instance rather than an asset id in this table, because
	`SurfaceAppearance.ColorMap` cannot be written by a game script at all.

	So the registry is `ReplicatedStorage.shared.PaintDetails` — one `SurfaceAppearance` per body,
	named after the body, which `CarPaint` clones onto the painted parts. `src/shared/PaintDetails.rbxmx`
	is the file, `CarPaint`'s header is why it works, and `assets/paint/README.md` is how the image
	inside one is made. Nothing about the palette, the pools or `KeepLivery` changes for a car that
	has one: it is repainted normally and simply keeps its detail while it happens. ]]

-- Index 1, spelled out, because three files need to say "the authored livery" and a bare `1` in
-- any of them is a number nobody can look up.
PaintConfig.StockIndex = 1

--[[ === How often a car keeps its own paint ==================================================

	HOW MANY OF `DefaultPool`'s SLOTS BELONG TO `Stock`. Three of fourteen colours plus three is
	about one car in six wearing the livery its artist drew, and the rest of the road repainted.

	IT USED TO BE ONE IN FIFTEEN, and by accident rather than by decision: `Stock` was a single
	entry in a uniform pool, so its share was "one over however long the palette happens to be", and
	every colour appended to `Palette` quietly made the authored look rarer. That is the wrong thing
	for a number to be a function of. This makes it a decision.

	WHY IT SHOULD NOT BE ZERO, and why it should not be large either. The stock livery is the only
	look on a car that somebody chose — the grille picked out, the two-tone split, the trim that
	`PaintDetails` exists to protect through a repaint — so a road that never shows one is a road
	that throws all of that away. But it is also ONE look, repeated: fourteen painted cars are
	fourteen different cars at a glance and fourteen stock ones are not, which is the same
	repetition every other change in this pass is fighting. A sixth is the balance point.

	IT IS A WEIGHT, NOT A SWITCH. Every ordinary car can still turn up either way — stock or in any
	of the fourteen — which is the whole point: two Chargers on one stretch of road can be a red one
	and the blue one the artist drew. The cars this does NOT reach are `KeepLivery` above, which are
	locked to `Stock` by a fact about their texture rather than by a share.

	0 takes the authored livery off the road entirely (a stored one still reads back fine — see
	`sanitize`); a number at or above the palette length makes it the majority. ]]
PaintConfig.StockWeight = 3

-- === Reading it =============================================================

--[[ Every index, built once — the pool a body with no `Pools` entry gets.

	`Stock` appears `StockWeight` times and every colour once, which is exactly the weighting the
	`Pools` note above describes: repeating an index is the knob, and this is the one place the
	default pool uses it. `roll` picks uniformly, so a repeated slot is a heavier chance; `sanitize`
	only asks whether an index is in the list at all, so repeats cost it nothing.

	Colours first and the `Stock` slots last so the list still reads as the palette in order. ]]
PaintConfig.DefaultPool = {}
do
	for index = 1, #PaintConfig.Palette do
		if index ~= PaintConfig.StockIndex then
			table.insert(PaintConfig.DefaultPool, index)
		end
	end
	for _ = 1, math.max(0, math.floor(PaintConfig.StockWeight)) do
		table.insert(PaintConfig.DefaultPool, PaintConfig.StockIndex)
	end
	--- `StockWeight = 0` with a one-entry palette would leave nothing to roll. Never happens with
	--- the table above; guarded because an empty pool is an error every caller would report as a
	--- different bug.
	if #PaintConfig.DefaultPool == 0 then
		table.insert(PaintConfig.DefaultPool, PaintConfig.StockIndex)
	end
end

-- `KeepLivery` as a set, so the lookup below is one hash rather than a scan of the list.
PaintConfig.LiveriedBodies = {}
do
	for _, body in PaintConfig.KeepLivery do
		PaintConfig.LiveriedBodies[body] = true
	end
end

-- The one pool a liveried car gets: its own artwork, and nothing else.
local STOCK_ONLY = { PaintConfig.StockIndex }

--[[ The colours this body can turn up in, as palette indices. Never nil, never empty.

	`KeepLivery` is checked FIRST and cannot be overridden by a `Pools` entry, which is deliberate:
	the reason a liveried car may not be repainted is a fact about its texture, not a taste call, so
	it should not be possible to undo it by accident from the table above. ]]
function PaintConfig.poolFor(body: unknown): { number }
	if type(body) == "string" and PaintConfig.LiveriedBodies[body] then
		return STOCK_ONLY
	end
	local pool = type(body) == "string" and PaintConfig.Pools[body]
	if type(pool) == "table" and #pool > 0 then
		return pool
	end
	return PaintConfig.DefaultPool
end

--[[ The colour a palette index means, or nil for "leave the authored livery alone".

	nil is also the answer for an index that is out of range, which is the safe direction: a save
	written against a longer palette than this build has repaints nothing rather than repainting
	something arbitrary. ]]
function PaintConfig.colorOf(index: unknown): Color3?
	if not PaintConfig.Enabled or type(index) ~= "number" then
		return nil
	end
	local entry = PaintConfig.Palette[index]
	return if entry then entry.Color else nil
end

-- What to call this index in a log. Never fails; an unknown index reports itself by number.
function PaintConfig.nameOf(index: unknown): string
	local entry = type(index) == "number" and PaintConfig.Palette[index]
	return if entry then entry.Name else string.format("paint %s", tostring(index))
end

--[[ Roll a colour for one car. `rng` is the caller's own generator, so a race that seeds its
	Random gets a repeatable road out of this for free and nothing here has to own a seed.

	Falls back to `Stock` with the feature off, which is what makes `Enabled = false` a complete
	switch rather than something every call site has to check. ]]
function PaintConfig.roll(rng: Random, body: unknown): number
	if not PaintConfig.Enabled then
		return PaintConfig.StockIndex
	end
	local pool = PaintConfig.poolFor(body)
	return pool[rng:NextInteger(1, #pool)]
end

--[[ Read a paint index off the wire, or out of a save file, and answer with one this build can use.

	THE SERVER'S ONLY CHECK ON A COLOUR, and it is a real one — unlike the tier and the body name it
	rides beside (see GarageService's header on what traffic being client-sided costs), a paint is
	cosmetic, so the worst a lie can buy is a colour the pool would have given out anyway. What this
	stops is the cheap breakage: a fractional index, a NaN, a number pointing past the palette, or a
	colour that body's pool does not allow.

	Anything it cannot use comes back as `Stock`, which is always legal and always looks right. ]]
function PaintConfig.sanitize(body: unknown, index: unknown): number
	if not PaintConfig.Enabled or type(index) ~= "number" or index ~= index or index % 1 ~= 0 then
		return PaintConfig.StockIndex
	end
	if not PaintConfig.Palette[index] then
		return PaintConfig.StockIndex
	end
	for _, allowed in PaintConfig.poolFor(body) do
		if allowed == index then
			return index
		end
	end
	return PaintConfig.StockIndex
end

return PaintConfig
