--!strict
--[[
	SpeedTrapConfig
	---------------
	A GOAL YOU CAN SEE COMING. Every so often a camera gantry spans the road ahead with a countdown on
	screen. Blow through it as fast as you can: it flashes, rates the pass BRONZE / SILVER / GOLD, and
	remembers your best for the session. A good rating tops the nitro bottle up.

	WHY. Between steals, a run had nothing to aim at in the next ten seconds. A trap turns cruising into
	a plan — save the bottle, clear the lane, time the burn so you cross at full speed — and it lands on
	the moment nitro is most fun to spend.

	RATINGS ARE RELATIVE TO THE CAR YOU ARE IN, so a beater and a supercar are both chasing gold. The
	reference is the car's boosted top speed (`DriveController.getTopSpeed`, converted to studs/s with
	`WindConfig.StudsPerMaxSpeed`): BRONZE is holding boost, SILVER needs something on top (nitro
	building, a fresh kick), GOLD is a burn that has actually reached its speed.

	CLIENT-ONLY. Nothing here pays cash, and that is deliberate for now: the car's speed ceiling is set
	on the client, so the server has nothing fair to price a trap against. The reward is the rating, the
	nitro and the best. If traps ever pay, the server has to measure the car's speed itself at the
	report, the way RewardService already measures distance.

	=== THEY PAY NOW, AND THE SERVER MEASURES — 2026-09-28 ====================================

	Exactly the condition the paragraph above set. The client still builds the gantry, draws the
	countdown and shows the flash; what it sends is only "I crossed one" (`SpeedTrapService`). The
	SERVER then reads the race car's own speed, works out that car's top speed from the same numbers
	the client uses (`CarConfig.maxSpeedOf` x its level scale x the free boost), rates it, and pays
	`Pay` — seconds of the car's tier rate, so a better car earns more from the same rating. The
	rating on screen is replaced by the server's when it answers, so the word and the money agree.

	A BEST IS SAVED, PER WORLD, and beating it pays the trap's cash again on top (`Pay.NewBest`). The
	best is the server's measured speed too, capped (`Pay.MaxFraction`), so a spoofed velocity cannot
	write an unbeatable record.

	WHAT BOUNDS IT, since the gantries are the client's: a trap only pays once the run has driven far
	enough since the last one (`Pay.SpacingSlack` of `SpacingMin`, measured by `RewardService`), so a
	run can collect about one trap per 2,000 studs whatever it claims — the same density honest play
	sees. The speed is the client's physics as replicated, so a cheater can always claim GOLD; that is
	the ceiling, and it is priced as such.

	`Pay.Enabled = false`: traps are decoration again — rating, nitro and a session best, exactly as
	before this block.
]]

local SpeedTrapConfig = {}

SpeedTrapConfig.Enabled = true

-- === Where they appear ======================================================

-- Studs down the road from the start of a run to the first trap, and between traps after that
-- (a random pick inside the range). At ~80 studs/s, 2000-2800 is one every 25-35 seconds.
SpeedTrapConfig.FirstAt = 1400
SpeedTrapConfig.SpacingMin = 2000
SpeedTrapConfig.SpacingMax = 2800

-- The gantry is built when the trap is this far ahead, and the on-screen countdown shows from here.
SpeedTrapConfig.BuildAhead = 900
SpeedTrapConfig.WarnAhead = 700

-- === Ratings ================================================================

--[[ Fractions of the car's boosted top speed. Nitro's dial is 1.7-1.95x the base against boost's
	1.35x, i.e. roughly 1.26-1.44x the boosted top — so GOLD at 1.24 wants a burn that has had time to
	build, and SILVER at 1.08 is a kick or a burn caught early. ]]
--[[ `Seconds` is the cash (2026-09-28, `Pay`): that many seconds of the car's tier rate
	(`GarageConfig.rateOf`, the ladder the value scale is built on). 30 / 15 / 6 puts a GOLD in a Tier 1
	beater at about $60 and in a Tier 8 at about $2,300 — a trap every 25-35 seconds adds a real but
	secondary slice on top of the run's distance cash. A TASTE CALL; the three numbers to move together. ]]
SpeedTrapConfig.Ratings = {
	--- `Seconds` cut 2026-10-13 (punch list E1, was 30 / 15 / 6): traps pay by the car you drive, so they
	--- were the lever that ran away in a top car (a World 1 GOLD in the top car: $3,125 -> $1,250).
	{ Name = "GOLD", Fraction = 1.24, Color = Color3.fromRGB(255, 205, 60), Nitro = 0.35, Seconds = 12 },
	{ Name = "SILVER", Fraction = 1.08, Color = Color3.fromRGB(215, 225, 240), Nitro = 0.15, Seconds = 6 },
	{ Name = "BRONZE", Fraction = 0.92, Color = Color3.fromRGB(215, 140, 80), Nitro = 0, Seconds = 3 },
}

-- === Pay ====================================================================

SpeedTrapConfig.Pay = {
	Enabled = true,

	--[[ A new best pays the trap's cash again ON TOP, times this: 1 doubles it. A best is rare by
		construction — you have to beat yourself — so the bonus can be generous without adding up. ]]
	--- 0.5 since 2026-10-13 (punch list E1, was 1): half again on a best, with the trap pay itself cut.
	NewBest = 0.5,

	--[[ How much of the spacing the run must have covered since the last paid trap (and of `FirstAt`
		for the first one). Below 1 because the server's distance and the client's gantry position
		are measured a frame and a round trip apart; 0.75 absorbs that and still holds a run to one
		trap per ~1,500 studs at the very least. ]]
	SpacingSlack = 0.75,

	--[[ The measured speed is capped at this fraction of the car's top before it is rated or saved as
		a best. GOLD needs 1.24; nitro honestly reaches ~1.44 (the rating note above), so 1.6 never
		touches an honest pass and stops a spoofed velocity writing a record nobody can beat. ]]
	MaxFraction = 1.6,

	--- The profile key: world index (as a string) -> best mph, `{ ["1"] = 142 }`.
	ProfileKey = "SpeedTrapBest",
	--- The broadcast of it on the Player, "1=142,2=160", for the result toast to compare against.
	Attribute = "SpeedTrapBest",
}
SpeedTrapConfig.MissColor = Color3.fromRGB(150, 160, 175)
SpeedTrapConfig.MissLabel = "TOO SLOW"

-- Studs/s -> mph, the stock CarBones speedo's own conversion (DrivingHudController.MPH_PER_STUD).
SpeedTrapConfig.MphPerStud = 0.6263

-- === The gantry =============================================================

SpeedTrapConfig.Gantry = {
	-- Studs either side of the drive centre the posts stand at when the road declares no width.
	HalfSpan = 42,
	Height = 30,
	PostSize = Vector3.new(2.2, 30, 2.2),
	BeamThickness = 2.6,
	PostColor = Color3.fromRGB(40, 44, 52),
	SignColor = Color3.fromRGB(20, 22, 28),
	LightColor = Color3.fromRGB(255, 60, 60),
	FlashColor = Color3.fromRGB(255, 255, 255),
	SignText = "SPEED TRAP",
}

-- === Screen =================================================================

SpeedTrapConfig.Ui = {
	Enabled = true,
	--- 2026-10-20 ("move the speed trap text over to the right side ... smaller, it's not that important"):
	--- WAS centred at 0.155 and 0.26 x 0.03; now on the right over its own result (`ResultPosition`), smaller.
	WarnPosition = Vector2.new(0.76, 0.16),
	WarnSize = Vector2.new(0.18, 0.022),
	--- On TOUCH (2026-10-13, punch list M4): clear of Roblox's top bar (to y ~0.15 on a phone), between
	--- the streak meter (`NearMissConfig.Flow.TouchPosition`, 0.2) and the steal nudge (0.295), and big
	--- enough to read (0.03 of a 390px screen was 12px).
	--- 2026-10-20: WAS 0.255; swapped with the police chase bar on a phone (`PoliceConfig.Hud.Bar.TouchCentreY`),
	--- which took this spot so it sits higher, under the FLOW meter.
	WarnTouchPosition = Vector2.new(0.74, 0.24), -- ...and on a phone, right side too, left of the camera button
	WarnTouchSize = Vector2.new(0.22, 0.032),
	WarnColor = Color3.fromRGB(255, 90, 90),
	-- Mirrored against the near-miss toast, leaving the centre of the road unobstructed.
	ResultPosition = Vector2.new(0.76, 0.22),
	ResultSize = Vector2.new(0.22, 0.065),
	TextColor = Color3.fromRGB(245, 249, 255),
	BestColor = Color3.fromRGB(120, 230, 140),
	FlashTransparency = 0.72,
	FlashTime = 0.18,
	PopFrom = 0.82,
	PopTime = 0.16,
	GoldScale = 1.04,
	Hold = 0.85,
	FadeTime = 0.25,
	-- The outlines are gone by this fraction of `FadeTime`, ahead of the letters. Same value and
	-- reason as the near-miss toast's (NearMissConfig.Ui.StrokeFade).
	StrokeFade = 0.5,
	StudsPerMeter = 4.4, -- RewardConfig.Distance.StudsPerMeter
	-- SoundService groups (blank ids are silent; see SoundController's header).
	ShutterSound = "SpeedTrap",
	GoldSound = "SpeedTrapGold",
}

-- === Derived ================================================================

--[[ The rating for crossing at `speed` studs/s in a car whose boosted top is `top` studs/s: the entry
	from `Ratings`, or nil for too slow. Nonsense in either argument is too slow. ]]
function SpeedTrapConfig.ratingFor(speed: number, top: number)
	if type(speed) ~= "number" or type(top) ~= "number" or speed ~= speed or top ~= top or top <= 0 then
		return nil
	end
	local fraction = speed / top
	for _, rating in SpeedTrapConfig.Ratings do
		if fraction >= rating.Fraction then
			return rating
		end
	end
	return nil
end

-- Where the next trap goes after one at `along`, given a 0..1 roll.
function SpeedTrapConfig.nextAlong(along: number, roll: number): number
	local t = math.clamp(if roll == roll then roll else 0.5, 0, 1)
	return along + SpeedTrapConfig.SpacingMin + (SpeedTrapConfig.SpacingMax - SpeedTrapConfig.SpacingMin) * t
end

function SpeedTrapConfig.mph(studsPerSecond: number): number
	return math.floor(math.max(0, studsPerSecond) * SpeedTrapConfig.MphPerStud + 0.5)
end

--- A rating by its name, or nil (the server answers with the name).
function SpeedTrapConfig.ratingNamed(name: unknown)
	for _, rating in SpeedTrapConfig.Ratings do
		if rating.Name == name then
			return rating
		end
	end
	return nil
end

return SpeedTrapConfig
