--[[
	CollectEffectConfig
	-------------------
	The banknotes that fly out of a collect mat and into you. Everything `CashBurstController` reads,
	and nothing else — no economy, no payout, no decision about WHETHER money changed hands.

	WHY IT EXISTS. `GarageConfig`'s header is blunt about the fact that pending cash is derived rather
	than accumulated, and `OfflineConfig`'s is blunt about what that cost: the money has been correct
	since the day the formula was written, and nobody ever saw it happen. Standing on a mat rolled a
	counter in the corner of the screen. This is the other half — the payout given a place in the
	world it came out of and a path to the player it went to, which is the beat every simulator on the
	front page spends its animation budget on.

	IT IS PURELY COSMETIC AND IT IS ALLOWED TO BE WRONG. Not one number here is on the payout path.
	The cash is already in the profile and already mirrored onto the Player attribute by the time a
	single note is drawn — `GarageService._collect` pays first and fires the burst last — so a note
	that never spawns, gets culled by distance, or is dropped by the live cap costs the player
	nothing. Switch `Enabled` off and the economy is untouched.

	=== THE SHAPE OF ONE COLLECTION ============================================================

	    pop        each note is thrown on a real ballistic arc — outward on an even fan, up, and
	               already falling by the time the arc ends. Notes leave staggered, so a payout
	               sprays rather than blooming as one blob.
	    hang       falls out of the maths rather than being a phase: the flight eases IN from a
	               standstill, so a note stalls at the top of its arc for a beat before it moves.
	    flight     accelerating into the player's centre, re-aimed every frame at wherever they
	               actually are, so walking away does not leave the money behind.
	    arrival    shrinks and fades over the last fifth rather than popping out of existence, and
	               the part outlives its own icon by the trail's lifetime so the ribbon finishes
	               into the player instead of being cut off mid-air.

	=== WHAT CARRIES THE SIZE OF THE PAYOUT ====================================================

	THE COUNT, AND ONLY THE COUNT. A $20 mat throws `Notes.Min` notes and a $900 one throws
	`Notes.Max`; every note is the same size, the same speed and the same arc either way. That is
	this project's standing preference about effects — small reactions that VARY by severity beat
	big uniform ones — and the variable that varies here is how much money is in the air, which is
	the thing the player is being told. Scaling the notes as well would say it twice and make a big
	collection read as a screen wipe.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[ For the note's artwork and its aspect. THE SAME BANKNOTE THE HUD COUNTER AND THE QUEST REWARD
	CHIP WEAR (`UIAssets.Page.CashIcon`, the Gvesster note) — deliberately, and it is the whole
	reason this needed no new art. A currency the player learns to read in one place has to be the
	same shape everywhere it appears, and the alternative is a second cash icon that eventually
	disagrees with the first. `UIAssets` requires nothing, so this cannot cycle. ]]
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local CollectEffectConfig = {}

-- Master switch. Off = `GarageService` still fires the burst (one remote per collection, unwatched)
-- and the controller drops it on the floor. Money, labels and the HUD counter are unaffected.
CollectEffectConfig.Enabled = true

-- The Workspace folder the live notes are parented to, the same shape every other client-built
-- effect in this project uses (`TrafficConfig.FolderName`, `ObstacleConfig.DebrisFolderName`).
-- CLIENT-SIDE ONLY: nothing here is ever replicated, and nothing on the server looks for it.
CollectEffectConfig.FolderName = "CashBurst"

--[[ Past this many studs from the CAMERA, a collection is not drawn at all.

	It is not a performance guard — a dozen billboards is nothing. It is there because two of the
	three things that call `_collect` can fire while the player is nowhere near the mat: the AUTO
	COLLECT upgrade is a timer that keeps sweeping the lot MID-RACE, and the welcome-back screen's
	COLLECT button sweeps six bays from wherever the player happens to have spawned. Money erupting
	out of a plot on the far side of the island — or worse, arriving at a car doing 85 down the
	motorway — is noise, and the HUD counter already tells that story properly.

	Measured to the camera rather than to the character on purpose: what matters is whether it would
	be ON SCREEN, and during a race the camera and the character are not in the same place. ]]
CollectEffectConfig.MaxDistance = 180

--[[ A SoundGroup under SoundService, played once per collection, not once per note, which would be
	a machine gun. The group is authored in the place rather than in source (see `SoundController`'s
	header), and the race results screen plays the same clip for its payout, so money sounds like
	money everywhere. Blank means silence. ]]
CollectEffectConfig.Sound = "CashCollect"

-- === How many notes ==========================================================

CollectEffectConfig.Notes = {
	--[[ The floor and the ceiling of the fan. `Min` is what a $1 collection throws — three notes,
		because one is an accident and two is a pair, and three is the fewest that reads as a spray.

		`Max` is the point past which more notes stop meaning "more money" and start meaning "the
		screen is full". Fourteen is roughly what fits in the air at these speeds without any two
		overlapping for the whole flight. ]]
	Min = 3,
	Max = 14,

	--[[ One extra note per this many dollars. Set against the mid game rather than the early one:
		$40 is a few seconds of a well-upgraded bay, so an idle-collect walk down the row throws
		five or six notes a mat and a bay left overnight throws the full fourteen. Lower it and
		every collection maxes out, which throws the size language away. ]]
	CashPerNote = 40,

	--[[ Hard ceiling on notes in the air across ALL collections at once, and the reason it is not
		simply `Max`: `collectAll` pays six bays inside one frame, so the welcome-back screen and
		every AUTO COLLECT tick fire six bursts simultaneously. Six times fourteen is eighty-four
		billboards, which is not a disaster but is well past the point of reading as anything.

		A burst that does not fit is TRIMMED, not dropped — it throws whatever room is left, down to
		nothing. A collection that pays and shows less is honest; one that pays and shows nothing
		looks broken. ]]
	MaxLive = 42,
}

--- How many notes one payout is worth. Whole number, clamped to the range above.
function CollectEffectConfig.noteCount(amount: number): number
	local notes = CollectEffectConfig.Notes
	return math.clamp(notes.Min + math.floor(amount / notes.CashPerNote), notes.Min, notes.Max)
end

-- === The note itself =========================================================

CollectEffectConfig.Icon = {
	-- The Gvesster banknote. See the require at the top for why it is this one and not a new one.
	Image = UIAssets.Page.CashIcon,

	--[[ How wide one note is IN STUDS — a BillboardGui sized in scale is sized in studs, so this is
		world size and does not change with the viewport. Height comes off the artwork's own aspect
		(`UIAssets.Size.CashIcon`, 1.673) rather than being written down again here, which is the
		same rule the Quest reward chip follows.

		1.9 studs against a car that is 19.9 long: a note is about a tenth of a car, which is roughly
		a real banknote against a real car and is the scale this project's prop yardstick asks for. ]]
	Width = 1.9,

	--[[ FALSE, and worth stating because every simulator on the front page has this on. A note that
		draws through the podium it came out of is a sticker on the lens; one that is briefly hidden
		behind the deck as it arcs over it is an object in the world, which is the reading this
		project's effect taste asks for. Flip it if the notes read as lost against a busy forecourt. ]]
	AlwaysOnTop = false,

	-- BillboardGui's own fade-out distance. Well past `MaxDistance` above, so it never actually
	-- bites — it is only here so a note in flight when the camera cuts away does not hang in the
	-- distance at full size.
	FadeDistance = 220,

	--[[ Degrees per second of flutter, picked per note and signed either way, plus the spread of
		starting angles. A banknote that stays perfectly upright the whole way in is a sprite; one
		that turns a few degrees as it flies is paper. Kept small — this is a tumble, not a spin. ]]
	Spin = NumberRange.new(30, 110),
	StartRotation = NumberRange.new(-25, 25),
}

-- === The pop =================================================================

CollectEffectConfig.Pop = {
	--[[ Seconds between one note leaving and the next, and the jitter on each note's own arc time.
		The stagger is what makes a payout a SPRAY rather than a bloom: at 14 notes it spreads the
		launch over half a second, so the first notes are already turning for home while the last
		are still on the way up. ]]
	Stagger = 0.035,
	Time = 0.34,
	TimeJitter = 0.18, -- +/- this fraction, per note

	--[[ Launch speed, studs per second, split into the two components of the throw: outward along
		an even fan around the mat, and straight up.

		`Gravity` is the arc's own, NOT `workspace.Gravity` — nothing here is simulated and borrowing
		the world's number would tie the look of a payout to a physics value tuned for cars. At 42
		with a rise of 11-15, a note tops out about two studs over the mat and is coming back down by
		the time the flight takes it, which is the beat that makes the hang read. ]]
	Spread = NumberRange.new(4.5, 9),
	Rise = NumberRange.new(11, 15.5),
	Gravity = 42,

	--[[ How far off the even fan each note's angle may wander, in radians. An EVEN fan with a small
		wobble, rather than a random direction each: pure random clumps visibly at these counts, and
		a perfect fan reads as a machine. ]]
	AngleJitter = 0.45,

	-- Studs above the mat's top face that the notes are born at, so the first frame of the arc is
	-- not drawn half inside the plate.
	StartHeight = 0.7,
}

-- === The flight ==============================================================

CollectEffectConfig.Flight = {
	-- Seconds from the top of the arc to the player, and the per-note jitter on it. Jittered for the
	-- same reason the arc is: notes that all land on the same frame land as one event.
	Time = 0.42,
	TimeJitter = 0.2,

	--[[ The ease. Position is `from:Lerp(target, v ^ Power)`, so a power above 1 starts at a
		standstill and accelerates all the way in — which is what buys the hang at the top of the arc
		without a hang PHASE, and what makes the arrival feel like being pulled rather than like a
		tween finishing. 2.4 is a hard suck; drop toward 1.6 for a lazier drift. ]]
	Power = 2.4,

	--[[ Studs above the character's HumanoidRootPart the notes aim at. Zero is already the middle of
		the torso — the root part IS the centre of the player — and a small lift puts it at the chest,
		which reads better than the belt when the camera is above and behind. ]]
	TargetHeight = 0.3,

	--[[ The arrival, as a fraction of the flight: over the last fifth the note shrinks toward
		`EndScale` and fades out together, so it goes INTO the player rather than blinking off at
		their feet. The trail is still drawing while this happens, which is what carries the last
		few studs. ]]
	Shrink = 0.2,
	EndScale = 0.35,
}

-- === The trail ===============================================================

--[[ Untextured on purpose. A `Trail` with a blank `Texture` renders as a solid ribbon, which is
	exactly the streak wanted here, and it costs no upload and no draw of a repeating strip. The key
	is here rather than hard-coded so a proper streak PNG can be dropped in later without touching
	the controller. ]]
CollectEffectConfig.Trail = {
	Enabled = true,
	Texture = "",

	--[[ Seconds of ribbon behind each note. It is also HOW LONG THE NOTE'S PART OUTLIVES ITS OWN
		ICON: the controller hides the banknote on arrival and destroys the part this much later, so
		the tail finishes into the player instead of vanishing with it. Longer than about 0.3 and the
		ribbon is still hanging in the air after the money has landed. ]]
	Lifetime = 0.22,

	-- Studs between the two attachments, i.e. the ribbon's width at the note. Tapers to nothing at
	-- the tail via the width curve the controller builds.
	Width = 0.55,

	--[[ Head and tail colour. Green because green is what this kit pays money out in — the same
		reason `UIAssets` gives for the welcome-back panel wearing the green title cap — and the head
		is nearly white so it reads as speed rather than as a green stripe. ]]
	Color = Color3.fromRGB(214, 255, 214),
	TailColor = Color3.fromRGB(96, 214, 118),

	-- Transparency at the head; the tail is always fully transparent, so this is really "how solid
	-- the streak is where it leaves the note".
	Transparency = 0.35,

	-- A little glow, so the streak holds up against a bright forecourt without being neon.
	LightEmission = 0.45,
}

return CollectEffectConfig
