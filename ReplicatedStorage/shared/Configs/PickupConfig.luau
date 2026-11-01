--[[
	PickupConfig
	------------
	The two things on the road you are meant to aim AT: a health pack and a nitro pack. They float
	over a lane, spin, wear a billboard icon, and go into a SLOT you spend when you choose.

	=== WHY THEY RIDE THE OBSTACLE LAYOUT AND ARE NOT THEIR OWN SYSTEM =========================

	A pickup is an obstacle in every structural sense: it has a seeded position, a lane, a hit
	volume, an id, and it may only ever be collected once. `ObstacleLayout` already solves all five
	and both sides already agree on its answers, so a pack is authored as an `ObstacleConfig.Kinds`
	entry carrying `Pickup = "<name from Packs below>"` and everything else here is what that name
	buys.

	What that gets for free, none of which had to be written:
	  • the layout is derived from the race seed on both sides, so a pack never replicates,
	  • the client's hit poll (one GetPartsInPart against the car's HitBox) already sees it,
	  • `ObstacleService._onObstacleHit` already validates the id against the seed, refuses a
	    second claim on the same id, checks the lane is plausible and rate-limits the lot,
	  • a recycled or rebased road tile carries its packs with it.

	So the ONLY thing this feature had to add on the trust boundary is which way the number moves.
	The client still reports one id and no amount, and the server still reads the payout out of
	config. See `ObstacleService._onPickup`.

	=== BANKED, EXCEPT WHEN YOU NEEDED IT ======================================================

	A pack does not fire on contact. It fills a one-item SLOT, and you spend it on a key — which is
	the whole reason to put one on the road rather than a boost pad: a pad is a line you take, a
	pack is a decision you make later.

	The exception is the owner's rule, and BOTH packs carry it: BANKED UNLESS YOU NEEDED IT. Driving
	over a repair while you are on your last legs, or over a nitro pack with a bottle too empty to
	light, and having either sit in a slot is the feature arguing with the player. So each pack names
	an `AutoUseBelow` and at or under that much of ITS OWN resource it spends itself on contact and
	never reaches the slot. Above that, it banks like anything else.

	Each threshold is a FRACTION of the resource rather than a flat amount, and neither resource is a
	fixed size. MaxHealth is per car (`CarConfig`'s stat curve, restamped on every steal), so a flat
	40 HP would be "nearly dead" on a beater and a scratch on a supercar; the tank is only ever
	spoken about in fractions anyway (`NitroConfig`).

	WHICH SIDE ENFORCES IT FOLLOWS WHICH SIDE OWNS THE RESOURCE, which is the split the section after
	next describes. The server applies the health rule in `ObstacleService._onPickup`, on the frame it
	validates the pickup, because it is the only thing that can read HP. It cannot read the tank at
	all, so it banks the nitro pack and `PickupController` sends it straight back out when the slot
	attribute arrives -- through `UsePickup`, the same remote the key fires, carrying nothing. That
	costs one round trip of latency and buys no new trust: the worst a compromised client can do with
	it is spend a pack it was holding, which is the button it already had.

	=== ONE SLOT, AND THE NEW ONE WINS ========================================================

	One slot rather than an inventory, because everything else on this screen during a race is a
	glance (`DrivingHudController`) and a second slot is the first thing a player has to look away
	from the road to read. A pack collected onto a full slot REPLACES what was in it: the
	alternative is a pickup that does nothing, which is indistinguishable from a bug at 85 studs/s,
	and the player has already had the chance to spend the old one.

	=== WHAT THE SERVER OWNS AND WHAT IT DOESN'T ==============================================

	The slot lives on the SERVER (`ObstacleService`'s race state) and is mirrored to the client as a
	player attribute for the HUD to read. That split is not symmetry for its own sake — it is
	exactly the split that already exists between the two payouts:

	  HEALTH is server-authoritative because HP is. `ObstacleService` is the only writer of Health
	  in the game and this feature does not become the second one: the heal lands in `_applyHeal`,
	  the mirror image of `_applyDamage`, and a client cannot ask for it — it can only say "use my
	  slot", which the server checks against its own record of what is in that slot.

	  NITRO is client-owned because the tank already is. `NitroController._tank` is a local number
	  the client spends against its own speed dial (see `NitroConfig`), so the server clearing the
	  slot and firing `PickupUsed` back is the honest amount of ceremony: an exploiting client could
	  already set its own tank to 1 every frame and this changes nothing about that. Driving is
	  solo, so the only person cheated is the cheater — the same trade `ObstacleService`'s header
	  makes about the road being client-built.

	=== THE ART IS DRAWN IN CODE, DELIBERATELY ================================================

	Every other obstacle from world 2 on is a delivered model (`ObstacleConfig`'s Art block). A pack
	is not, and should not become one: it is a UI object that happens to be in the world — a glyph
	on a plate, in the same family as the weather badges on the world cards — so it is built from
	primitives plus a `BillboardGui`, and it is IDENTICAL IN EVERY MAP. A player must be able to
	read "that is health" in the desert with the same glance they learned in the city, and a themed
	pack per world is how that gets unlearned.

	Both icons are Gvesster pack files, letterboxed by `assets/ui/pickups/build_pickups.py` the way
	the weather badges are: `Main/Heart` and `Nature/Bolt` (blue, which is the colour `NitroConfig`
	burns and fills its bar in). Ids live in `UIAssets.Pickups`, because that file is the registry.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NitroConfig = require(ReplicatedStorage.shared.Configs.NitroConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local PickupConfig = {}

--[[ Master switch. Off = no pack is ever placed in the layout, so the slot is never filled, the HUD
	never appears and the key is never bound. The road is exactly the road it was before this
	feature existed — `ObstacleLayout` skips the whole second pass.

	IT IS SUBORDINATE TO `ObstacleConfig.Enabled`, and that is worth knowing before using the other
	switch to bench something. Packs ride the obstacle layout, so turning the obstacle course off
	takes the pickups with it: `ObstacleLayout.forTile` returns an empty list before either pass
	runs, and `ObstacleService._onObstacleHit` refuses every report. That is the right coupling —
	a pack with no course around it is a reward for nothing — but it means "no obstacles, still
	pickups" is not a state this supports, and the switch to reach for when measuring driving is
	still `ObstacleConfig.Invulnerable`, which leaves both layers on the road.

	=== NOT SUBORDINATE ANY MORE — 2026-09-28 ================================================

	WHAT IT WAS. The paragraph above: the course switched off took the packs with it. The course HAS
	been off (`ObstacleConfig.Enabled = false`), so every run since shipped with no packs at all, and
	that was reported as the packs having gone missing.

	WHAT IT IS. "No obstacles, still pickups" is now a supported state, on the owner's call: the
	packs are the road's reward for steering, and the road still has traffic to steer round without a
	course. `ObstacleLayout.forTile` runs the pickup pass over an empty road, `ObstacleController`
	builds for either layer, and `ObstacleService._onObstacleHit` accepts a report for either. This
	switch alone now decides whether packs are on the road. ]]
PickupConfig.Enabled = true

--[[ Apply every validated pickup on contact instead of placing it in the one-item slot.

	This is enforced by `ObstacleService`, after the existing seeded-id, lane, duplicate and rate
	checks have accepted the collision. The client therefore cannot manufacture a heal by firing the
	old slot remote. Keeping the switch here preserves the proven slot implementation as a fallback,
	but while true the HUD never binds Q/R1 and every collection toast says APPLIED. ]]
PickupConfig.InstantUse = true

-- === Names =================================================================

--[[ The player attribute the server mirrors the slot onto: the pack's name, or nil for empty. An
	attribute rather than a remote for the STATE (there is a remote too, for the events) because the
	HUD wants a value it can read at any moment — on a respawn, on a rejoin, at the frame the GUI is
	built — and a signal only tells you about changes you were listening for.

	It replicates to every client rather than just its owner, which is what a Player attribute does
	and is harmless here: what another player is holding is not secret, and there is nothing on the
	other end that reads it. ]]
PickupConfig.SlotAttribute = "PickupSlot"

-- === The packs =============================================================

--[[ What each pack is worth, and what it looks like. The KEY is what an `ObstacleConfig.Kinds`
	entry names in its `Pickup` field, and it is the string that travels: it goes into the slot, onto
	the player attribute, through `PickupUsed`, and into the HUD's icon lookup. Adding a third pack
	is an entry here, a kind in `ObstacleConfig`, and nothing else.

	`Weight` is its share of the draw when the layout decides a tile gets a pack. Health is the
	commoner of the two on purpose: nitro already refills on a clock and on every near miss
	(`NitroConfig.Gain`), so a nitro pack is a bonus on a resource you were getting anyway, while
	health has exactly two other sources in a run and both of them cost you something — a steal
	(you had to take a car) and a revive (you had to wreck first). ]]
PickupConfig.Packs = {
	Health = {
		Weight = 0.6,

		--[[ HP restored, as a FRACTION of the car's own MaxHealth rather than a flat number, for the
			reason `AutoUseBelow` gives: the ceiling moves with the car. 0.35 is a little over a
			barricade and a half on world 1's numbers, which is the size that makes the slot worth
			carrying without making the obstacle course optional. ]]
		Heal = 0.35,

		--[[ THE OWNER'S RULE, in one number: banked unless you need the health. At or under this
			fraction of MaxHealth the pack spends itself on contact and never reaches the slot.

			0.5 rather than something desperate like 0.2 because the point is to not make the player
			fight the UI, and by the time you are at a fifth you are usually mid-crash with no hand
			free for a second button. Half health is also the moment a player starts driving
			differently, which is exactly when an instant repair reads as a rescue rather than as
			the game deciding for you.

			Set to 0 to switch the exception off for this pack and have it always bank. ]]
		AutoUseBelow = 0.5,

		--- The pack's own colour: the plate behind the glyph, the light it casts, and the toast.
		--- The kit's green, which is what every "you gained" reading in this game already is.
		Color = Color3.fromRGB(64, 214, 106),
		Icon = UIAssets.Pickups.Health,
		--- What the toast says. Two words, because it is read at speed and out of the corner of an
		--- eye. See `Toast` below.
		Label = "REPAIR",
		--- The pack's own pickup sound, in place of `Collect.Sound`: a ratchet wrench, which players
		--- asked for by name. A SoundGroup under SoundService like every other; nil falls back.
		Sound = "PickupRepair" :: string?,
	},

	Nitro = {
		Weight = 0.4,

		--[[ Fraction of a FULL tank, in `NitroController.reward`'s currency — the same currency a
			near miss (0.1) and the futuristic boost pad (0.35) already pay in.

			0.5 is deliberately the biggest single payout in that currency: a pad is street furniture
			you drive over on the racing line, and a pack is a slot you gave up to carry it. Paying
			the same as the pad would make the slot the worse deal. ]]
		Tank = 0.5,

		--[[ THE OWNER'S RULE AGAIN, against the tank instead of the bar: a pack collected with the
			bottle at or under this fraction pours itself in on contact and never reaches the slot.

			`MinToFire` rather than a number of our own, and read off `NitroConfig` rather than
			copied, because that constant IS the definition of depleted -- it is the floor under
			which a press does nothing at all. Banking a pack in that state is the slot holding the
			one thing that would give the player their button back, and a player whose nitro is dead
			is not weighing a decision, they are waiting. Above it the bottle still works, so the
			pack goes in the slot where it belongs.

			It is deliberately NOT "auto-use whenever the tank is not full". A pack is a decision,
			and spending it to top up a bottle that is three-quarters there throws most of the
			payout away, which is the same waste `Heal`'s clamp exists to keep a player out of.

			The CLIENT enforces this one, because the tank is a client-owned number; see the header
			and `PickupController._autoUse`. Set to 0 to switch it off. ]]
		AutoUseBelow = NitroConfig.Tank.MinToFire,

		--- `NitroConfig`'s own `ReadyColor`, so the pack, the bar it fills and the flame it buys are
		--- one colour. Nitrous burns blue and this kit's brand colour is blue; see NitroConfig.Flame.
		Color = Color3.fromRGB(0, 148, 255),
		Icon = UIAssets.Pickups.Nitro,
		Label = "NITRO",
		--- A turbo blow-off hiss, which players asked for. Same rules as `Health.Sound`.
		Sound = "PickupTurbo" :: string?,
	},

	--[[ THE STAR (2026-10-13, punch list N2, a player's "works just like Mario Kart"). A few seconds
		where nothing can hurt you, the car runs faster, and traffic you hit is batted out of the way
		instead of slowing you down.

		It is always spent on contact, slot or no slot: a star is a moment, not a resource, and
		banking one would turn "I just got lucky" into a menu decision. `AutoUseBelow = 0` keeps
		`PickupController._wouldAutoUse` out of it, and `ObstacleService._onPickup` spends a `Star`
		pack before the slot is considered.

		WHO DOES WHAT follows the same split as the other two packs. The SERVER owns the immunity,
		because it owns HP: `ObstacleService._spend` arms `starUntil` and `_applyDamage` refuses every
		hit until it passes, which covers obstacles, walls and traffic from one line. The CLIENT owns
		the rest (`StarController`): the speed dial, the shimmer on the car, and the plough through
		traffic (`TrafficController._onClip`) and obstacles (`ObstacleController.applyImpact`). ]]
	Star = {
		--- Rarer than either of the others by a long way. At one pack per ~25 seconds this is a star
		--- every few minutes of driving, which is what keeps it an event.
		Weight = 0.08,
		AutoUseBelow = 0,

		Star = {
			--- Seconds it lasts, on the client's clock from the moment `PickupUsed` lands.
			Duration = 12,
			--[[ Extra seconds the SERVER keeps the immunity past `Duration`. Its clock starts a
				one-way trip earlier than the client's, so without this the last hits the client
				believes it shrugged off arrive after the server's window has shut and cost HP. ]]
			ServerGrace = 0.6,
			--[[ Multiplier over the car's base MaxSpeed, through `DriveController.setStar`, which
				resolves against boost and nitro by the highest. Level with the top of nitro's range
				(`NitroConfig.Power`), so a star feels like a free bottle that never runs dry rather
				than a new top speed the road was never laid out for. ]]
			SpeedScale = 1.8,
			--- Studs/s of forward shove on the frame it lights, the same idea as `NitroConfig.Power.Kick`.
			Kick = 18,
			--- The last stretch of the run, where the shimmer speeds up to warn that it is ending.
			WarnTime = 1.5,
		},

		--- Gold. `Body.BurnPeak` keeps it from blooming to white on the road cube.
		Color = Color3.fromRGB(255, 196, 0),
		Icon = UIAssets.Pickups.Star,
		Label = "STAR",
		--- The toast's second line for this pack, in place of `Toast.UsedText`.
		UsedText = "INVINCIBLE",
		--- No dedicated clip yet: nil falls back to `Collect.Sound`. Name a SoundGroup here to give
		--- the star its own sting.
		Sound = nil :: string?,
	},
}

-- === Where they appear =====================================================

--[[ Packs are placed by a SECOND, INDEPENDENT PASS over each road tile, after the obstacle courses
	are laid (`ObstacleLayout.forTile`). Not by adding a "healthPack" course to the tier pools, and
	the difference matters in three ways:

	  IT REACHES EVERY MAP FOR FREE. A tier pool is per map (`ObstacleConfig.TiersByMap`), so a
	  course-based pack would have to be threaded into world 1's ramp, the desert's, the arctic's,
	  and every ramp added after — and a map whose author forgot would silently have no packs.

	  DENSITY IS ITS OWN DIAL. In a pool, a pack REPLACES an obstacle course, so making packs
	  commoner makes the road easier twice over. Here the two layers are independent: the course
	  ramp decides how hard the tile is and this decides how much help is on it.

	  IT CANNOT DESTABILISE THE COURSES. The pass draws from its own `Random`, salted off the tile
	  seed, so retuning pack density does not reshuffle a single obstacle. That also means an
	  existing seed keeps its obstacle course exactly as it was when this feature landed.

	DETERMINISM. Everything below is read on both sides through `ObstacleLayout`, so the same rules
	apply as to the rest of that file: the pass draws from the passed-in `Random` in a fixed order
	and touches nothing else. ]]
PickupConfig.Spawn = {
	--[[ Chance that a tile carries a pack at all. Roughly one every other tile — a tile is about
		1,000 studs and cruise is about 85 studs/s, so this is a pack about every 25 seconds, which
		is a little under two full nitro refill cycles (`NitroConfig.Tank.RefillSeconds`). Rare
		enough that seeing one is an event and you will change your line for it; common enough that
		a run always has one coming. ]]
	ChancePerTile = 0.55,

	--[[ ...and the chance of a SECOND one on a tile that already has one. Deliberately small: two
		packs on one tile is the good run, not the normal one. The pass never places more than
		`MaxPerTile`, whatever these are set to. ]]
	ChanceOfSecond = 0.18,
	MaxPerTile = 2,

	--[[ Studs from the tile's lead-in and tail-out that a pack may not be placed in. Wider than the
		obstacle course's own `LeadIn`/`TailOut` on both ends, because a pack you have to spot,
		decide about and steer to needs more warning than a cone you only have to miss — and one
		sitting on a tile seam is one you meet with no notice at all. ]]
	LeadIn = 180,
	TailOut = 260,

	--[[ How far a pack must sit from the nearest obstacle, so it is never buried inside a barricade
		or hidden behind a boulder — which turns a reward into a trap, and a trap the player cannot
		see is the one thing this file must not produce.

		Measured as a box, not a radius, because the road is not isotropic: `Along` is generous
		because everything closes at 85 studs/s down that axis, and `Cross` only has to clear the
		widest hit volume in the game plus a car. A candidate that fails is redrawn up to
		`Attempts` times and then abandoned, which is the right failure — a tile packed wall to wall
		with obstacles is a tile with no honest room for a reward on it. ]]
	ClearAlong = 70,
	ClearCross = 22,
	Attempts = 8,

	--[[ Which lanes a pack may sit in, as indices into `ObstacleConfig.Lanes`. All five: a pack in
		the outside lane is a real decision (the guardrail scrape is out there) and a pack that only
		ever appears in the middle three is one you take without steering. ]]
	Lanes = { 1, 2, 3, 4, 5 },
}

-- === What one looks like on the road ========================================

--[[ The floating, spinning body: a HOLOGRAPHIC ITEM BOX. A transparent cube with glowing edges and
	the pack's glyph suspended in the middle of it, always facing you.

	WHY A BOX WITH THE GLYPH INSIDE IT. The first version was a small solid core with the glyph
	floating on a billboard ABOVE it, and the two never became one object -- at speed it read as a
	glowing lozenge with an unrelated decal hovering over it, and there was no silhouette to the
	thing you were steering at. Putting the glyph INSIDE a cage makes the box the object and the
	glyph its contents, which is the Mario Kart item box read and the reason that shape is worth
	copying: the cube gives it a position, a size and a distance, and the glyph gives it a meaning.

	THE FACES AND THE EDGES DO DIFFERENT JOBS, and it needs both. The edges are what survives
	distance -- twelve thin neon bars still resolve as a cube when the faces have washed out to
	nothing -- and the faces are what make it a solid you can see through rather than a wireframe
	drawing. Drop either and the object stops reading: faces alone are a coloured blob, edges alone
	are a diagram.

	The whole cage is re-posed every frame off the TILE's pivot rather than the world's, the same
	way the desert's tumbleweed is (`ObstacleController._updateRollers`): a road tile is recycled to
	the front and the world is rebased under the car as you drive, and an absolute frame captured at
	build time would leave the pack bobbing around a stretch of road that has moved on. ]]
PickupConfig.Body = {
	--[[ The cube, in studs. Six, which is most of the way across a lane and a little under three
		quarters of the car's own width -- big enough to be a target you steer AT rather than a
		detail you notice, and it is what buys the room for the glyph to live inside it.

		IT MUST STAY INSIDE THE HIT VOLUME, which is 13 x 14 x 8 on the kind (see `ObstacleConfig`).
		At `Height` 6 the cube spans 3..9 of that 14, and 6 of its 8 studs of depth. That ordering
		is the honest one and the reason it is written down here: the volume is deliberately
		generous so you are never denied a reward you steered for, and art that grew past it would
		invert that into a pack you can see and drive straight through. ]]
	CoreSize = Vector3.new(6, 6, 6),
	--- Tilted off-axis so the spin shows a changing silhouette rather than four identical faces. A
	--- cube on its corner also reads as an "item" rather than as a crate someone left on the road.
	CoreTilt = Vector3.new(18, 0, 32),
	--[[ Degrees per second about the world's up axis. Slower than the 90 the small core spun at,
		because the cube is now two thirds wider and angular speed is not what the eye reads -- the
		edge of a 6-stud box at 80 deg/s travels further per frame than the edge of a 3.6-stud one
		did at 90, so holding the number would have been a speed-up. ]]
	SpinSpeed = 80,

	--[[ THE FACES, and the material is the whole reason the glyph is visible at all.

		`ForceField` is the only transparent material in the engine that a BillboardGui renders
		THROUGH. Glass does not -- a glass shell at any transparency swallows the glyph completely,
		which is not a subtle failure to catch later: it is a pack with no icon on it, and it is how
		the first two attempts at this looked. `SmoothPlastic` at a high transparency does let the
		glyph through but is nearly invisible against a bright sky, so it costs the "solid you can
		see through" read and buys nothing back.

		HOW FAR UP IT GOES IS SET BY THE GLYPH, not by how the cube looks on its own. The faces sit
		between the camera and the icon and ForceField TINTS what it does not hide, so every point
		of face is a point of green or blue laid over a glyph whose whole job is to be recognised in
		one look. 0.15 was picked for the cube and it cost the icon too much; 0.35 is the most face
		the glyph can carry and still read as its own colour. Past about 0.5 the faces stop
		contributing and the object falls back to being the wireframe on its own. ]]
	CoreMaterial = Enum.Material.ForceField,
	CoreTransparency = 0.35,

	--[[ Thickness of the twelve edge bars, in studs. They are Neon and fully opaque: they are the
		part of the object that has to survive being 400 studs away and half behind a barricade.

		Set to 0 to drop the frame entirely and leave the bare tinted cube. It is a real switch
		rather than a courtesy -- twelve parts per pack, up to two packs a tile and nine tiles live
		(`RaceConfig.DesiredSegmentCount`) is the one place this feature touches a budget, so the
		way to measure what the frame costs is to turn it off rather than to guess.

		Thin, for the same reason the faces are faint: a bar is fully opaque, so any of it that
		crosses the glyph is a slice of the icon simply gone. `IconFloat` is what stops that
		happening at all, and this only has to keep the frame from being heavy while it does. ]]
	EdgeThickness = 0.26,

	--[[ NEON BURNS TOWARD WHITE, so a pack's own colour is not the colour to paint it.

		Both packs' colours have a channel at or near full (`Packs.Nitro` is 0,148,255) and Neon
		blooms whatever the brightest channel is, so painting the raw colour on gave a white-cyan
		cube for the blue pack and a white-cyan cube for the green one -- THE TWO PACKS CAME OUT THE
		SAME COLOUR, which is the one thing this art must never do. Which pack it is, is the thing a
		player is meant to read at a glance and from furthest away.

		The fix is to hold the brightest channel at this ceiling and scale the other two with it,
		which preserves the hue exactly and lets the bloom carry the brightness back up. 0.55 is
		measured rather than guessed: at 0.75 the blue still came out cyan, and at 0.4 it went navy
		and stopped glowing. A ceiling rather than a multiplier, so a third pack in any colour gets
		the same treatment without a second number to tune. ]]
	BurnPeak = 0.55,

	--- Studs of light the pack casts on the deck. Small -- it is a marker, not a streetlight, and a
	--- big one on a night road washes out the obstacle it is sitting next to. Lit with the pack's
	--- TRUE colour rather than the burnt one: a light does not bloom, so it wants no correction.
	LightBrightness = 2,
	LightRange = 16,

	--- Height of the cube's centre above the deck, and the bob about it.
	Height = 6,
	BobHeight = 0.9,
	--- Seconds for one full bob. Slower than the spin on purpose: two motions on the same clock
	--- read as one motion, and the point of having both is that the object looks unstable.
	BobPeriod = 2.4,

	--[[ The glyph's billboard, as a FRACTION OF THE CUBE rather than a size in studs, because it
		lives inside the cube and its job is to fill that opening without crowding the bars. A
		number in studs would have to be re-derived by hand every time the cube resized, and getting
		it wrong reads as a glyph clipping through the frame. ]]
	IconScale = 0.72,

	--[[ Studs the glyph floats TOWARD THE CAMERA from the cube's centre, and it is the number that
		makes the icon legible rather than the two transparencies above.

		The glyph started dead centre, which is the honest place for the contents of a box and is
		also directly behind half the frame. A cube seen from a general angle puts one or two of its
		twelve edges across its own middle, and an edge is opaque Neon -- so at most spin angles a
		bar cut straight through the icon, and no amount of clearing the FACES fixed that, because
		the faces were never what was covering it. Thinning the bars only makes the cut narrower.

		Pushing the billboard toward the camera moves the glyph in FRONT of the near face and the
		near bars, at every angle, for free: the offset is applied in the billboard's own
		screen-facing frame, so it tracks the camera and no spin angle can put geometry back over
		it. 2.2 is measured against the cube's own half-width of 3: enough to clear the near
		geometry through a full turn, and short of the 3.4 that starts to read as a sticker sitting
		proud of the box rather than as something inside it. At 4.6 it is a detached decal floating
		in front of a cage, which is the exact failure the cube was built to fix.

		It does NOT change what the pack is occluded BY. The billboard is still `AlwaysOnTop = false`
		and still depth-tested, so a barricade in front of a pack still hides its glyph -- the offset
		is small next to the 13 x 14 x 8 hit volume the pack already occupies, so nothing becomes
		collectable-looking that was not already. ]]
	IconFloat = 2.2,
	--[[ How far away the billboard stops drawing. Well past the distance the road fades in at, so a
		pack is readable as soon as its tile is, which is the whole reason it is a billboard: you
		need to decide on it while it is still far enough away to change lanes for. ]]
	MaxDistance = 900,

	--[[ AlwaysOnTop is OFF, and that is a decision rather than a default. On, the glyph draws
		through the traffic and the barricades between you and it, which makes a pack look
		collectable when it is behind a wall -- and this game's road is full of things it would draw
		through. Off, it is occluded like a real object, so what you see is what you can reach.

		It also keeps the pack VISIBLE IN A PLAYTEST CAPTURE: a billboard with AlwaysOnTop set is
		missing from every screenshot the tooling can take, which would make this the one part of
		the feature that could never be checked by eye. ]]
	AlwaysOnTop = false,
}

--- The colour to paint a GLOWING part with so it blooms to the pack's hue instead of to white; see
--- `Body.BurnPeak` for why that is not the same as the pack's colour. Everything that ends up on
--- Neon or ForceField goes through this. A light or a piece of UI takes `pack.Color` raw, because
--- neither of those blooms.
function PickupConfig.burn(color: Color3): Color3
	local peak = math.max(color.R, color.G, color.B)
	if peak <= 0 then
		return color
	end
	local f = PickupConfig.Body.BurnPeak / peak
	return Color3.new(color.R * f, color.G * f, color.B * f)
end

--[[ THE HIT VOLUME IS NOT IN THIS FILE, and that is the one piece of a pack that lives elsewhere on
	purpose. It is authored on the kind, in `ObstacleConfig.Kinds.HealthPack` / `.NitroPack`,
	alongside every other `HitSize` in the game — because it is read by the client's hit poll and the
	server's plausibility check, both of which reach it through the KIND, and a second copy here
	would be the one number two files could disagree about.

	The reasoning for why it is deliberately bigger than the art is written up there with it. ]]

-- === Collecting one ========================================================

--[[ The beat on contact. Nothing here touches the car: a pack must never shove, slow, yaw, shake or
	report a police strike, which is what `Pass = true` on the kind buys (see `ObstacleConfig`'s
	Kinds legend). Being rewarded should not feel like being hit. ]]
PickupConfig.Collect = {
	--[[ The box coming apart as it goes, over `PopTime` and fading the whole way. Short, because it
		happens behind you and nobody watches it -- it exists so the pack LEAVES rather than
		vanishing between two frames.

		Two motions, because the box is two things (see `Body`): the tinted core swells to
		`PopScale` of its size, and the twelve edge bars fly straight out from the centre to
		`PopBurst` of their radius. The core alone was the old single-part pop and on a caged cube
		it reads wrong -- the frame just sits there, at its own size, fading, while something grows
		out through it. Sending the frame outward with it is what makes the whole object burst
		instead of one part of it dissolving inside the rest.

		`PopBurst` is the smaller number of the two on purpose. The bars start on the outside, so
		the same multiplier would throw them much further in studs than the core's faces travel, and
		the box would come apart into a spray rather than opening up. ]]
	PopScale = 2.2,
	PopBurst = 1.5,
	PopTime = 0.22,

	--[[ Seconds the pack's own glyph flies up the screen toward the slot. Purely decorative and the
		one piece of this that exists only to answer "where did it go" — a slot that fills with no
		travel between the road and the HUD is a slot that fills for no visible reason. ]]
	FlyTime = 0.45,

	--- A SoundGroup name in SoundService, played through `SoundController:PlayRandom`. The group is
	--- authored in the place (`SoundController`'s header); nil takes the sound out. A pack with a
	--- `Sound` of its own (`Packs`) plays that INSTEAD, so a pickup is one cue rather than two
	--- stacked; this is the fallback for a pack without one.
	Sound = "PickupCollect" :: string?,
}

--[[ The toast: the same two-line card `NearMissController` puts up, in the pack's own colour, so a
	pickup and a near miss read as one language of "that went well". Built in code rather than
	authored, for that controller's reason — it is one card and the layout is three numbers. ]]
PickupConfig.Toast = {
	Enabled = true,
	--- Fraction of the viewport, centre-relative. Left of the near-miss toast so a pack collected
	--- during a chain of near misses does not land on top of one.
	Position = Vector2.new(0.5, 0.36),
	Size = Vector2.new(0.3, 0.1),
	HoldTime = 0.55,
	FadeTime = 0.3,
	--- What the second line says when the pack banked, and when it spent itself. Either pack can say
	--- the second (see `AutoUseBelow`), and it has to say something different or the rule looks like
	--- the slot failing to fill.
	BankedText = "STORED",
	UsedText = "APPLIED",
}

-- === The slot on screen ====================================================

--[[ Drawn in code into its own ScreenGui rather than authored into `StarterGui.DrivingHud`.

	That is a departure from the driving HUD's rule (the layout lives in Studio so it can be nudged
	in the Explorer) and it is deliberate for one release only: the slot is new, nobody has decided
	where it wants to be, and a feature that cannot ship without a Studio edit is a feature that
	cannot be reviewed from the repository. Everything below is the layout, so moving it is a number
	here.

	WHEN THE STUDIO VERSION LANDS, this block becomes `_findSlot`'s fallback and the numbers stay as
	the defaults — the same shape `NitroConfig.Hud.Bars` already has for the nitro bar. ]]
PickupConfig.Hud = {
	--[[ Fraction of the viewport, and it is the MIRROR OF THE NITRO BAR across the gauge cluster.

		That is the whole placement argument: the bar and the slot are the two resources you spend,
		so they flank the dials rather than queueing on one side. Measured live at 1228x620 —

		    Cluster        x 0.351 .. 0.650
		    NitroVertical  x 0.659 .. 0.682   (just right of it)
		    this slot      x 0.260 .. 0.330   (just left of it)

		— which clears the cluster by 0.021 and, on touch, the right steering arrow (ends 0.236) by
		0.024. Both gaps GROW on a wider screen rather than shrink: the slot is sized off the
		viewport's HEIGHT (`Size` below) and the cluster is aspect-constrained, so both narrow in
		x-scale as the window widens.

		0.86 was the first guess and it was wrong — dead centre, which put the slot UNDERNEATH the
		speedometer where it rendered every frame and could not be seen. If this moves again, check
		it against those three rects rather than by eye. ]]
	Position = Vector2.new(0.295, 0.765),
	--- Fraction of the viewport's HEIGHT, kept square by an aspect constraint — so the slot is the
	--- same physical size on a phone and an ultrawide, which a width-relative size is not.
	Size = 0.14,

	--[[ THERE IS NO EMPTY SLOT. The plate is on screen only while it is holding a pack, and it goes
		away the moment it is spent.

		That is the owner's call and it replaces the opposite one, which shipped first: a dim resting
		plate, always there, on the argument that it is what teaches a player the slot exists. It
		does not. What it teaches is that the square is furniture, which is how a HUD element stops
		being read at all, and it puts a keycap on screen under an empty box, which is a button
		advertised for a press that does nothing. Both are worse than the alternative, because the
		first pack a player drives through teaches the whole thing at the one moment the lesson is
		worth having: the plate arrives, wearing the glyph of the thing they just took, with Q
		written under it.

		It also buys back the only piece of permanent furniture this feature was adding to a screen
		the player spends the whole race looking THROUGH.

		Seconds the plate takes to fade as it empties. Short, because it is the tail of something the
		player just did and wants to read as the pack leaving rather than as a panel closing. A slot
		emptied by anything that is not a spend (a race starting, a wreck, a rebuilt GUI) is hidden
		outright: a fade there would announce something that did not just happen. ]]
	EmptyFade = 0.14,

	--- The plate's border, and the outline on the toast's two lines.
	StrokeColor = Color3.fromRGB(15, 17, 51),
	StrokeThickness = 0.035, -- fraction of the slot's own height, so it scales with it
	CornerRadius = 0.16, -- ditto

	--- How long the slot takes to swell and settle when a pack lands in it, and how far it swells.
	--- The one animation the slot has, and it is what makes a pickup land ON the HUD rather than
	--- just appearing there.
	FillTime = 0.18,
	FillScale = 1.35,

	--- The pulse while the slot is full and usable: how far the plate's glow travels, and how fast.
	--- A breath, matching the nitro bar's own `BurnPulse` language.
	Pulse = 0.18,
	PulseHz = 1.6,

	--- The keycap under the slot, on desktop. Nil on touch (the slot IS the button) and replaced by
	--- the pad glyph on a console, which `Modules/ControlLegend` draws instead.
	CapHeight = 0.26, -- fraction of the slot
	CapText = "Q",
}

-- === Input =================================================================

--[[ HOLD nothing — this is a TAP. A pack is spent in one instant and there is no version of it that
	is held, so a hold would only add a way to fail to use it.

	Q AND THE RIGHT BUMPER, and both were free. `NitroConfig`'s note has the full audit of what this
	race already claims: W/Up/R2 throttle, S/Down/L2 brake, Space/ButtonA handbrake and bail,
	A/D/arrows steering, E/ButtonY enter, E/ButtonX the steal prompt, LeftShift/L1 the nitro. R1 is
	the obvious pad button precisely because L1 is the nitro — the two resources a player spends sit
	under the two bumpers — and Q is the one key a driving game's left hand can reach without
	leaving the steering keys.

	ON TOUCH there is no key at all: the slot itself is the button. That is why there is no entry
	here for it and why `PickupConfig.Hud` has no separate button — a phone screen during a race is
	already carrying six controls (`DrivingHudController`) and a seventh would be the one that
	finally crowds the steering. ]]
PickupConfig.Keys = { Enum.KeyCode.Q, Enum.KeyCode.ButtonR1 }

--- Bound above the stock `Driver`, for the reason `NitroConfig.BindPriority` gives at length: that
--- script binds at `ContextActionPriority.High` and sinks every key it recognises. Neither of ours
--- is one today, so this costs nothing — it is here so a rig whose Keymap grows a Q tomorrow loses
--- the argument rather than winning it silently.
PickupConfig.BindPriority = Enum.ContextActionPriority.High.Value + 500

-- === Asking about a pack ===================================================

--- The pack a name refers to, or nil. Every consumer goes through this rather than indexing
--- `Packs` directly, so a name arriving from a remote, an attribute or a config typo is one
--- rejected lookup instead of an error inside a HUD.
function PickupConfig.pack(name: unknown)
	if type(name) ~= "string" then
		return nil
	end
	return PickupConfig.Packs[name]
end

--[[ Draw a pack name from the weights, using the caller's `Random` so it stays inside
	`ObstacleLayout`'s determinism contract. Iterates `Names` rather than `Packs` because pairs()
	over a hash table has no defined order, and an order that differs between two machines is
	exactly the desync that file's header warns about. ]]
PickupConfig.Names = { "Health", "Nitro", "Star" }

-- === The Star's look and the plough =========================================

--[[ What the car looks like while a star is lit, and what it does to the things it hits. Read by
	`StarController` (the look) and by `TrafficController._onClip` (the plough). `Packs.Star.Star`
	holds the timing and the speed; this holds everything you see.

	PITCHED AT THE RESTRAINED END, on the house rule for effects: a star is a rare, earned moment so
	it may be louder than a hit reaction, but it is a shimmer over the car's own paint, not a repaint.
	The paint is still the car you stole. ]]
PickupConfig.StarFx = {
	--[[ The shimmer: a Highlight on the player's car whose colour walks round the hue wheel. ONE
		Highlight, on the car you are driving, for a few seconds; the ~31 budget is spent mostly on
		mutated traffic and this does not threaten it. ]]
	Shimmer = {
		--- Full trips round the hue wheel per second, and the faster rate during `WarnTime`.
		HueSpeed = 0.9,
		WarnHueSpeed = 2.6,
		Saturation = 0.75,
		Value = 1,
		FillTransparency = 0.55,
		OutlineTransparency = 0.1,
		--- During `WarnTime` the fill blinks between its own transparency and this, at `WarnBlinkHz`.
		WarnFillTransparency = 0.9,
		WarnBlinkHz = 6,
		--- Seconds to fade the shimmer in, and out once it ends.
		FadeIn = 0.15,
		FadeOut = 0.35,
	},

	--- Glints trailing off the car: the engine's own four-point flare, so nothing to upload.
	Sparkles = {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = 26,
		Lifetime = { 0.35, 0.7 },
		Size = { 1.1, 1.8, 0 },
		Speed = { 2, 6 },
		LightEmission = 1,
	},

	--- A warm light under the car so the road shows the star too.
	Light = { Brightness = 2.5, Range = 18 },

	--[[ Traffic you hit with a star lit. No speed lost, no shove, no HP, no police strike: the car
		you hit goes physical and is batted aside with this velocity (studs/s) instead of the
		severity-priced knock. `Carry` is the share of YOUR forward speed it is given, so it is
		thrown along with you rather than left as a wall you pass through; `Side` throws it away
		from the side you hit; `Up` lifts it off the deck so it tumbles; `Spin` is radians/s of
		random yaw and roll. Louder than `TrafficConfig.Knock.Push` on purpose, which is the
		"save the big reaction for rare, earned moments" half of the effects rule. ]]
	Plow = {
		Carry = 0.85,
		Side = 34,
		Up = 26,
		Spin = 4,
		--- The camera shake a plough still plays, as a fraction of the normal clip's.
		ShakeScale = 0.5,
	},
}

function PickupConfig.draw(rng: Random): string
	local total = 0
	for _, name in PickupConfig.Names do
		total += PickupConfig.Packs[name].Weight
	end
	local roll = rng:NextNumber(0, total)
	for _, name in PickupConfig.Names do
		roll -= PickupConfig.Packs[name].Weight
		if roll <= 0 then
			return name
		end
	end
	return PickupConfig.Names[#PickupConfig.Names]
end

-- Music owned by StarController's active deadline; pickup collection remains a separate one-shot.
PickupConfig.StarMusic = {
 Group = "StarMusic",
 Name = "PowerLaunch",
 Volume = 1, -- Twice the previous level; still follows the Music slider/mute.
 FadeIn = 0.08,
 FadeOut = 0.2,
}

--[[ === THE STAR'S TIMER — 2026-10-16 ===
	WHAT IT WAS: nothing. A star ended when the shimmer on the car stopped, so a player learned it was
	over by being hit (the owner: "theres no indicator to say when its going to end").
	WHAT IT IS (Gvistic: "clone the nitro timer, and use a diff icon, then once it's done it fades
	away"): `DrivingHudController._buildStarBadge` clones `DrivingHud.NitroBadge` into a second badge
	beside it wearing the star, its ring draining `StarController:remaining() / Packs.Star.Star.Duration`
	in the star's gold, faded in on the light and out when it ends. A CLONE and not new art, so a
	re-run of `BuildNitroBadge` restyles both. Only with `NitroConfig.Hud.Layout = "Badge"`, the
	one shape there is to clone. `Enabled = false`: no timer, the old behaviour exactly. ]]
PickupConfig.StarTimer = {
	Enabled = true,
	--[[ Where the star badge's top-left corner sits, in nitro-badge sizes from the nitro badge's own:
		(0, -1.12) is straight above it with an eighth of a badge between. Above rather than beside,
		because beside it on a phone is the brake pedal (`NitroConfig.Hud.Badge` stands over the
		pedals' corner) and above is open road. ]]
	Offset = Vector2.new(0, -1.12),
	--- Seconds to fade in when a star lights and out when it ends. The track under the ring is the
	--- gold dimmed by `NitroConfig.Hud.Badge.RingDim`, so the two badges dim by one rule.
	Fade = 0.3,
}

--[[ === A ROW OVER THE SPEEDO, NITRO FIRST — 2026-10-16 ===
	`StarTimer.Offset` stood the star over the nitro badge. The owner marked the strip along the
	speedo's top for phones, and Aleafo then asked for the same on PC with nitro in it for good
	("add boost as the powerup there too and it takes up a permanent slot"), on every device.

	So `DrivingHud.PowerupTimers` is a compact grid on keyboard, pad and touch alike: its left edge on
	the speedo's and its bottom `Gap` px over the speedo's top. The NITRO BADGE is slot 1 and never
	leaves; timed indicators fill the first `Columns` slots, then wrap underneath. A hidden indicator
	takes no room, so future indicators only need to be parented in by `DrivingHudController._layoutTimers`.

	WHAT MOVED TO MAKE ROOM: on desktop the nitro badge stood centred over the speedo
	(`NitroConfig.Hud.Badge.Margin`), on a phone beside it (`DrivingHudController._layoutReadouts`).
	Both now give way to the row. `Enabled = false`: both come back exactly, and the star rides over
	nitro at `StarTimer.Offset`. ]]
PickupConfig.TimerRow = {
	Enabled = true,
	--[[ Every badge's size as a share of `NitroConfig.Hud.Badge.Height` (0.135 of the screen).
		0.7 = ~0.095 of the screen (2026-10-23, the owner: "make them a tiny bit
		smaller"); the full badge over a speedo read as two stacked panels of equal weight. 1 = the
		nitro badge's own authored size. ]]
	Scale = 0.7,
	Gap = 6,
	Spacing = 8,
	Columns = 3,
}

return PickupConfig
