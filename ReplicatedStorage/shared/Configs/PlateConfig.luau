--[[
	PlateConfig
	-----------
	What a car's number plate reads. One pool for the whole game, drawn from so that every plate in
	it looks like something a real DVLA/DMV would have issued and NONE of it can ever be read as a
	word somebody complains about.

	=== WHY A CURATED POOL AND NOT A RANDOM STRING =============================================

	`string.char(rng:NextInteger(65, 90))` three times is four lines and produces `FAG`, `ASS`,
	`SEX` and worse on a long enough road — and it produces them at a rate a 60-car race notices.
	A game with user-visible generated text has to be able to say what the whole output set is, so
	this file IS the whole output set: a plate is one entry from `Groups` and one entry from
	`Numbers`, and there is no third source of characters.

	=== THE THREE THINGS THAT KEEP IT CLEAN ====================================================

	  1. `Groups` IS HAND-VETTED. Every trio in it was read before it went in. It is the only place
	     letters come from, so a plate can only ever be as bad as the worst line in that table.

	  2. NO VOWELS, EVER — and that is the load-bearing one, because it is structural rather than
	     a matter of somebody having been careful. `A E I O U Y` do not appear in `Groups` at all,
	     and virtually every English word worth objecting to needs one. A maintainer adding twenty
	     more trios in a hurry cannot introduce `GAY` or `TIT` without first breaking a rule this
	     header states in capitals. The handful of vowel-free strings that still read as something
	     (`FCK`, `SHT`, `CNT`, `KKK`, `WTF`, ...) are simply not in the table, and the pattern of
	     the ones that are — `BKR`, `TRL`, `MSK` — is exactly what a real plate looks like anyway.

	  3. `BannedNumbers` COVERS THE DIGITS. Digits cannot spell anything, but a few numbers carry
	     meaning on their own; those are struck out of the numeric half rather than filtered at the
	     point a plate is built.

	So the pool is 160 x 992 = 158,720 plates, all of them pre-approved, from ~30 lines of data.
	That is the trade this file makes: a pre-defined pool, as asked for, but defined as its two
	halves so the table stays short enough that a human can actually re-read it.

	=== WHICH CAR GETS WHICH PLATE =============================================================

	Two different questions, and this module answers both:

	  • A CAR YOU OWN keeps its plate, forever, on every screen — `forKey`. The plate is hashed out
	    of the car's identity (`GarageConfig.carKey`, "Camaro:6"), so the car on your podium, the one
	    parked in the street, the card on the dealership page and the one you take into a race all
	    read the same number without a single byte being stored, replicated or migrated. Identity
	    here is BODY AND PAINT because that is what a car is in this game — repainting a Camaro
	    makes it a different car in the collection, and it gets a different plate to match.

	  • A CAR ON THE ROAD is a stranger — `roll`. Traffic rolls a plate per spawn out of the
	    controller's own rng, the same way it rolls its colour, so two identical Chargers passing
	    each other are still two cars.

	    A STOLEN CAR THEREFORE KEEPS THE VICTIM'S PLATE for the rest of the run: the plate's text
	    rides on the shell's `SurfaceGui` and `CarBody.swapMeshes` clones it across with the rest of
	    the dress. That is deliberate and it is free. Bank the car and it turns up on your podium
	    wearing your plate, because a banked car is an owned car and owned cars are plated by
	    identity — the in-fiction reading is that you re-plated it, which is what you would do.

	REORDERING `Groups` RE-PLATES EVERY CAR IN THE GAME. Nothing is stored, so nothing breaks and
	no save needs migrating — but a player's car quietly gets a new number, so append rather than
	insert if you can be bothered.
]]

local PlateConfig = {}

--[[ Master switch. Off = every car wears whatever text its master rig was authored with (today the
	placeholder `STEAL`, from `CommandRunnerScripts/FitLicensePlates`), and nothing here is read.
	The one lever to pull if generated plates ever have to go away in a hurry. ]]
PlateConfig.Enabled = true

--[[ === The letters ==========================================================================

	HAND-VETTED, AND NO VOWELS — see the header, both halves of which are why this table can be
	extended safely by somebody who has not read the rest of the file.

	Composed to look like issued plates rather than like a random generator: consonant clusters that
	fall naturally out of English spelling (`BKR`, `CRT`, `MLD`, `TRK`), no repeated letter pairs,
	and no trio that abbreviates something — no `FBI`, no `KGB`, no `THC`. `Q` is left out entirely
	because a Q with no U after it reads as a typo. ]]
PlateConfig.Groups = {
	"BKR", "BLT", "BNS", "BRC", "BTL", "BXR", "BSK", "BTZ", "BRV", "BZK",
	"CBL", "CDR", "CHR", "CLM", "CLT", "CMB", "CMP", "CND", "CPR", "CRT",
	"DBL", "DFT", "DGL", "DLM", "DMR", "DNS", "DPT", "DRB", "DSK", "DVR",
	"FBR", "FDL", "FLM", "FLT", "FLX", "FRB", "FRM", "FSH", "FTN", "FVR",
	"GBL", "GDR", "GFT", "GLD", "GLM", "GND", "GRB", "GRD", "GRT", "GTR",
	"HBR", "HDL", "HLM", "HLT", "HMR", "HND", "HRB", "HRT", "HST", "HWK",
	"JBL", "JDL", "JLT", "JMB", "JPR", "JRD", "JST", "JVL",
	"KBL", "KLM", "KMB", "KND", "KPR", "KRB", "KRT", "KST", "KTL", "KVR",
	"LBR", "LDR", "LFT", "LGN", "LKR", "LMB", "LND", "LRD", "LTR", "LZR",
	"MBL", "MGL", "MKR", "MLD", "MLT", "MND", "MPL", "MRK", "MSK", "MTR",
	"NBL", "NDL", "NKL", "NMB", "NRT", "NTL", "NVR", "NWL",
	"PDL", "PLM", "PLT", "PNT", "PRT", "PTL", "PVT", "PWR",
	"RBL", "RDL", "RFT", "RGL", "RKT", "RLM", "RMB", "RND", "RSL", "RVN",
	"SBL", "SFT", "SGL", "SKL", "SLR", "SND", "SPR", "SRT", "STL", "SVN",
	"TBL", "TGL", "TMB", "TND", "TPL", "TRB", "TRC", "TRK", "TRL", "TWL",
	"VDR", "VLT", "VNL", "VRT", "VSL",
	"WGN", "WLD", "WND", "WRD", "WSP", "WTR",
	"XLR", "XTR",
	"ZBR", "ZND", "ZPR",
}

--[[ Numbers a plate is never issued with.

	Digits cannot spell anything, so this is a short list of the few that carry meaning on their own
	rather than an attempt at a filter: two hate numbers, two drug/party numbers, an emergency
	number, a police code, and `000` because it reads as a placeholder rather than as a plate.

	Keyed by the INTEGER, not the padded string, so `69` here strikes out `069`. ]]
PlateConfig.BannedNumbers = {
	[0] = true,
	[13] = true,
	[69] = true,
	[88] = true,
	[187] = true,
	[420] = true,
	[666] = true,
	[911] = true,
}

--[[ The separator between the two halves. A plain space: the plate face is 2.2 studs wide and the
	label is `TextScaled`, so every character costs legibility at chase-camera distance and a dash
	buys nothing a space does not. ]]
PlateConfig.Separator = " "

-- What `forKey` returns when it is handed nothing usable. A real plate rather than a marker,
-- because a car wearing `?????` on a podium is worse than a car wearing a plate nobody chose.
PlateConfig.Fallback = "STL 001"

--[[ === The numeric half =====================================================================

	Built once at require time rather than filtered per draw, so that "how many plates are there"
	is a number this module knows and `plateAt` can index straight into. Three digits, zero-padded
	— `007` is what a plate looks like; `7` is what a debug print looks like. ]]
local NUMBERS: { string } = {}
do
	for n = 0, 999 do
		if not PlateConfig.BannedNumbers[n] then
			table.insert(NUMBERS, string.format("%03d", n))
		end
	end
end
PlateConfig.Numbers = NUMBERS

--[[ How many distinct plates exist. `#Groups * #Numbers`, and the only reason it is a function is
	so a caller reading it cannot accidentally cache a stale one after a live edit in Studio. ]]
function PlateConfig.count(): number
	return #PlateConfig.Groups * #NUMBERS
end

--[[ Every integer maps to a real plate and no caller has to bounds-check a hash. Odd, large, and
	coprime with `count()` — which is 2^10 x 5 x 31, so any odd number that is not a multiple of 5
	or 31 will do — this is what stands between two neighbouring numbers and two neighbouring
	plates.

	IT HAS TO SCRAMBLE, and the case that says so is real: the two cars a player is most likely to
	see side by side are the same body in two colours, whose keys ("Camaro:6", "Camaro:7") differ by
	one character and therefore hash one apart. Split straight down the middle, one apart means the
	same three digits with the letters nudged — `SFT 886` parked next to `SGL 886` — which reads as
	a generator rather than as two cars. Multiplied through first, one apart is 47,683 apart and
	both halves move.

	MULTIPLYING IS SAFE AND STAYS A BIJECTION. The index is reduced modulo `count()` before the
	multiply, so the product tops out at 1.6e11 — nowhere near the 2^53 where a double starts
	rounding — and being coprime with the modulus means it permutes the pool rather than folding it,
	so `roll` stays exactly as uniform as the rng it was handed. ]]
local SCRAMBLE = 1000003

--[[ The nth plate, 1-based and wrapped.

	The group moves on every step of the scrambled index and the number every 160th, which together
	with `SCRAMBLE` above is what makes two cars that hashed close together read as two plates. ]]
function PlateConfig.plateAt(index: unknown): string
	local n = tonumber(index)
	local groups = PlateConfig.Groups
	if not n or n ~= n or #groups == 0 or #NUMBERS == 0 then
		return PlateConfig.Fallback
	end
	local total = #groups * #NUMBERS
	n = ((math.floor(n) % total) * SCRAMBLE) % total
	local group = groups[(n % #groups) + 1]
	local number = NUMBERS[(n // #groups) % #NUMBERS + 1]
	return group .. PlateConfig.Separator .. number
end

--[[ A stable 31-bit hash of a string. djb2, with the modulo taken every step.

	THE MODULO IS NOT DECORATION. Luau numbers are doubles: 33 * 2^31 is 7.1e10 and exact, while the
	same loop left to grow unbounded passes 2^53 in twelve characters and starts rounding — at which
	point two different keys silently hash the same and two different cars wear the same plate. ]]
local function hash(key: string): number
	local h = 5381
	for i = 1, #key do
		h = (h * 33 + string.byte(key, i)) % 2147483647
	end
	return h
end

--[[ The plate belonging to an identity — a `GarageConfig.carKey` ("Camaro:6"), or any other stable
	string a caller can produce the same way twice.

	DETERMINISTIC IS THE WHOLE POINT: this is what lets four different systems on two different
	machines put the same number on the same car with nothing passed between them. Change the hash
	or the pool and they all change together, which is fine; make one of them ask a random number
	generator instead and the car's plate starts changing when you walk away from it. ]]
function PlateConfig.forKey(key: unknown): string
	if not PlateConfig.Enabled or type(key) ~= "string" or key == "" then
		return PlateConfig.Fallback
	end
	return PlateConfig.plateAt(hash(key))
end

--[[ A plate for a car nobody owns — traffic. Rolled off the caller's own rng so that seeding the
	road seeds its plates too, exactly as `PaintConfig.roll` does for its colours. ]]
function PlateConfig.roll(rng: Random): string
	if not PlateConfig.Enabled then
		return PlateConfig.Fallback
	end
	return PlateConfig.plateAt(rng:NextInteger(1, PlateConfig.count()))
end

return PlateConfig
