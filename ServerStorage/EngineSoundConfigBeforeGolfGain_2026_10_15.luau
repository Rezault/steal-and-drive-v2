--[[
	EngineSoundConfig
	-----------------
	Real engine sounds, per car (2026-10-14). Until now every car drove on ONE stand-in clip pitched
	to RPM (`DriveConfig.TestEngine`). A pack here is a real engine recorded in layers, and a car
	listed in `Cars` drives on its pack instead; every other car keeps the stand-in, exactly as before.

	=== WHAT A PACK IS ==========================================================================

	The layout of the Skril Studio packs, which record an engine at three RPM bands, each both under
	load and coasting:
	  `Idle`             standing, or near enough (`DriveConfig.TestEngine.IdleBelowMph`)
	  `Low/Med/High.On`  throttle on, crossfaded by where the RPM is in the gear (`Mix.Bands`)
	  `Low/Med/High.Off` the same bands lifting off: the burble on a lift, a brake, a gear change
	  `MaxRpm`           layered in at the top of each gear, under load, just before the upshift
	  `Startup`          once, when the driver takes the seat; the idle fades in under it
	`Modules/EngineAudio` plays it; the RPM is the simulated six-speed's (`Modules/AutomaticGearbox`),
	the same one the dashboard reads, so the note and the gear readout shift together.

	=== WHICH CARS ==============================================================================

	`GermanI6` (skrilstudio.com, "I6 German free engine sound pack") is a BMW-style straight six.
	Given to the cars whose real engine is one, or close: the MK5 Supra (BMW's B58) and the M4 (S55)
	exactly; the Supra MK4 (2JZ) and the Skyline R34 (RB26), Japanese straight sixes; and as stand-ins
	until better packs exist, the 190E (a six in some trims) and the 350Z (really a V6). Every V8,
	four and supercar is left on the stand-in rather than given a six that is plainly wrong.
	`Rotary` (same day) is the RX-7 and the RX-7 F&F, the roster's only Wankels.

	LOCAL TO THE DRIVER, like the stand-in: other players still hear the car kit's own engine
	(`DriveConfig.TestEngine.MuteKit` mutes that on this client only). `Enabled = false`: every car
	on the stand-in clip, exactly as before this file.
]]

local EngineSoundConfig = {}

EngineSoundConfig.Enabled = true

EngineSoundConfig.Packs = {
	GermanI6 = {
		Startup = 88630197185423,
		Idle = 134182541753024,
		Low = { On = 107652319815907, Off = 120531114280679 },
		Med = { On = 121097707413621, Off = 111145355598619 },
		High = { On = 139793859229431, Off = 118312923915884 },
		MaxRpm = 77012575495536,
		--- The whole pack's level. A taste call, untested; the stand-in sits at 1.5.
		Volume = 1,
	},
	--- A rotary (Wankel), same nine-clip layout. Added the same day for the two RX-7s.
	Rotary = {
		Startup = 79873374512676,
		Idle = 100538780560757,
		Low = { On = 80644581261181, Off = 100408796882401 },
		Med = { On = 117607136725978, Off = 73315061583753 },
		--- `High.Off` is the pack's `Med.Off` raised to `High.On`'s pitch (x1.26, 2026-10-15): the
		--- pack's own high_off (90455385702076) was rejected by moderation and never loads.
		High = { On = 98111067825520, Off = 72354713258874 },
		MaxRpm = 136875231925638,
		Volume = 1,
	},
	--[[ A SIMPLE PACK (same day): only an `Idle` and one `Engine` loop, the best V8 supercar the
		owner found on the toolbox. With no RPM bands to crossfade, `Modules/EngineAudio` pitches the
		one loop up through each gear the way the stand-in does (`Mix.Simple`) and crossfades the idle
		in near a standstill. Replace with a full nine-clip pack when one turns up; nothing else changes. ]]
	SupercarV8 = {
		Idle = 115048434058975,
		Engine = 122719299491983,
		--- Two extras, same day: an Aston Martin V8 ("AM11") start, and a one-shot played on every
		--- downshift (`Modules/EngineAudio`), the blip a dual-clutch makes coming down a gear.
		Startup = 96276731038337,
		Downshift = 92846521526596,
		Volume = 1,
	},
	--- One loop only (same day), so it idles on itself (`Mix.Simple.IdlePitch`). A cross-plane V8.
	MuscleV8 = {
		Engine = 83645151559021,
		Volume = 1,
	},
	--- Idle and one loop (same day), the supercar's layout.
	V6 = {
		Idle = 140163575364310,
		Engine = 106338431486975,
		Volume = 1,
	},
	--- The rest of the roster, same day, all simple packs. One loop each unless an idle is given.
	Turbo4 = { Engine = 103008577790766, Volume = 1 },
	V12 = { Engine = 8144395396, Volume = 1 },
	Flat6 = { Idle = 108494470459885, Engine = 138546026206116, Volume = 1 },
	V10 = { Engine = 109993372870151, Volume = 1 },
	Boxer = { Engine = 749655689, Volume = 1 },
	--[[ The two three-cylinder hybrids (i8, Gemera): no pack of their own exists, so the turbo four
		pitched down a tenth (`Pitch`, a multiplier on the whole loop), which reads as a smaller,
		rougher engine rather than the same car as a Civic. ]]
	ThreeCyl = { Engine = 103008577790766, Pitch = 0.9, Volume = 1 },
	--[[ ELECTRIC, the Rovster 2 (a Roadster): no engine, so no sound. Still a pack rather than left
		on the stand-in, because being listed is what mutes the car kit's own petrol engine; an EV
		that roared would be the bug. `Electric` builds no layers at all (`Modules/EngineAudio`). ]]
	Electric = { Electric = true, Volume = 0 },
}

--- Body name (the roster's, not the display name) -> pack. A body not listed keeps the stand-in.
EngineSoundConfig.Cars = {
	["MK5 Supra"] = "GermanI6",
	["M4"] = "GermanI6",
	["Supra MK4"] = "GermanI6",
	["Skyline R34"] = "GermanI6",
	["190E"] = "GermanI6",
	["350Z"] = "GermanI6",
	--- The roster's only rotaries: the RX-7 (13B) and its Fast & Furious build.
	["RX7"] = "Rotary",
	["RX7 F&F"] = "Rotary",
	--[[ The flat-plane, twin-turbo supercars. `NewSports11` (Ferro Apex) is a guess: if it is the
		V12 LaFerrari rather than a V8 hybrid it wants a V12 pack. ]]
	["M5"] = "SupercarV8",
	["NewSports06"] = "SupercarV8", -- Ferro 48
	["M600"] = "SupercarV8",
	["F40"] = "SupercarV8",
	["NewSports13"] = "SupercarV8", -- Ferro Spider
	["918"] = "SupercarV8",
	["F5"] = "SupercarV8",
	["720S"] = "SupercarV8",
	["Senna"] = "SupercarV8",
	["Jesko Attack"] = "SupercarV8",
	["NewSports11"] = "SupercarV8", -- Ferro Apex
	--- The American and muscle V8s, and the two that share their deep rumble (C63, Pantera).
	["Camaro"] = "MuscleV8",
	["Charger"] = "MuscleV8",
	["Challenger"] = "MuscleV8",
	["Mustang"] = "MuscleV8",
	["C7"] = "MuscleV8",
	["C63 AMG"] = "MuscleV8",
	["NewSports31"] = "MuscleV8", -- Meron GT, grey coupe
	["Pantera GT5"] = "MuscleV8",
	--[[ The V6s: the GNX's turbo six, the Genesis, the GT-R (`NewSports14`, Skylane GT, a twin-turbo
		V6) and the DeLorean. `GT` (Granvel GT) is a V6 if it is the 2017 Ford GT; if it is the 2005
		car it is a V8 and belongs on `SupercarV8`. ]]
	["GNX"] = "V6",
	["Maybach"] = "V6", -- Genes GE7
	["NewSports14"] = "V6", -- Skylane GT
	["DeLorean"] = "V6",
	["GT"] = "V6",
	["Civic"] = "Turbo4",
	["Golf GTI"] = "Turbo4",
	["EVO"] = "Turbo4",
	["EVO 10"] = "Turbo4",
	["F&F EVO"] = "Turbo4",
	["S15"] = "Turbo4",
	["F1 LM"] = "V12",
	["Sian"] = "V12",
	["Huyara BC"] = "V12",
	["NewSports23"] = "Flat6", -- Porten Classic
	["NewSports18"] = "Flat6", -- Porten GT
	["NewSports34"] = "Flat6", -- Porten Sport
	["NewSports02"] = "V10", -- Auren 8
	["NewSports04"] = "V10", -- Huraven
	["Lambo"] = "V12", -- Aventra
	["WRX STI"] = "Boxer",
	["BRZ/FRS/GT86"] = "Boxer",
	["i8"] = "ThreeCyl",
	["Gemera"] = "ThreeCyl",
	["Roadster 2.0"] = "Electric",
}

--[[ === THE MIX ==============================================================================
	`Bands`: where each RPM band is loudest, as a share of the way through the current gear (0 just
	after a shift, 1 at the shift point), and how far either side it fades to nothing. Overlapping,
	so there is never a gap: 0.15, 0.5 and 0.85, each +/- 0.35.
	`PitchSpan`: how far a band's pitch moves from 1 across its own range, so a clip recorded at one
	RPM bends to cover its band instead of jumping to the next. Kept small: past ~0.3 a recorded
	engine starts to sound sped up rather than revved.
	`MaxRpmFrom`: the share of the gear past which `MaxRpm` comes in under load.
	`LoadResponse` / `VolumeResponse`: per-second ease of the on/off blend and of every layer's volume.
	`DecelMph`: mph per second of slowing that counts as "off the throttle"; anything less is on. The
	race's throttle is held on by `DriveConfig.AutoThrottle`, so the seat's own throttle cannot say
	it; slowing down is the one signal that means the same in a race and in the lobby.
	`IdleFadeIn`: seconds the idle takes to come in under the startup clip. ]]
EngineSoundConfig.Mix = {
	Bands = { Low = { 0.15, 0.35 }, Med = { 0.5, 0.35 }, High = { 0.85, 0.35 } },
	PitchSpan = 0.25,
	MaxRpmFrom = 0.85,
	LoadResponse = 6,
	PitchResponse = 14, -- ~0.16 s to settle: retain shifts without snapping pitch each frame
	SpeedResponse = 5, -- filter physics jitter before selecting load/coast
	SwapSeconds = 0.16,
	IdleBlendFromMph = 1,
	IdleBlendToMph = 7,
	VolumeResponse = 10,
	DecelMph = 2,
	IdleFadeIn = 1.2,
	--[[ A simple pack's one loop (`SupercarV8`): pitch `Low` just after a shift to `High` at the shift
		point, `PerGear` higher each gear up, so the note climbs through the run as the stand-in's does.
		Off the throttle it drops to `OffVolume` of its level and `OffPitch` lower, a cheap lift-off. ]]
	--- `IdlePitch` / `IdleVolume`: a simple pack with no `Idle` clip idles on its engine loop, so
	--- low and quiet at a standstill (the muscle V8).
	Simple = { Low = 0.85, High = 1.4, PerGear = 0.03, OffVolume = 0.6, OffPitch = 0.08, IdlePitch = 0.65, IdleVolume = 0.5 },
}

--- The pack for a body, or nil for the stand-in. Nil with the feature off.
function EngineSoundConfig.packFor(body: unknown)
	if not EngineSoundConfig.Enabled or type(body) ~= "string" then
		return nil
	end
	local name = EngineSoundConfig.Cars[body]
	return name and EngineSoundConfig.Packs[name]
end

return EngineSoundConfig
