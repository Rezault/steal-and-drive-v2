--[[
	CarDetailConfig
	---------------
	THE CAR DETAIL WINGS: the two panels that stand either side of the card grid on the new UI's car
	screens — the cars inventory (`PagesV2/Dealership`) and the car picker (`PagesV2/StartCar`) —
	and show the car you last pressed. The left one is the car itself, turning; the right one is
	what it is made of.

	Dylan asked for it on 2026-09-17 against a reference screenshot of an anime unit collector:
	"the stats and maybe a rotating viewport on the left ... and on the right the stats". It is also
	the answer to the gap `docs/NewUI-Migration-Notes.md` has been carrying since the V2 inventory
	shipped — the shipping page's hover tooltip did not make the crossing, and the note says why a
	press-to-open panel is the honest version of it rather than a port.

	FIVE THINGS TO KNOW BEFORE TUNING ANY OF IT.

	1. IT CARRIES NO NUMBERS ABOUT A CAR. The four bars are `InventoryConfig.Stats` — the same view
	   of `CarConfig` the shipping tooltip drew — the rarity word is `Modules/CarRarity`, the rate is
	   `GarageConfig.rateOf` and the level is `RewardConfig`. This file is the panel's WORDS and its
	   switches, and a stat table here would be a second opinion about how fast a car is. See
	   `InventoryConfig`'s header notes 1 to 4, which are still the whole story about the bars.

	2. A PRESS OPENS THEM, THE SAME PRESS SHUTS THEM, AND NOTHING ELSE DOES EITHER. Until 2026-09-17
	   a car screen opened with a car already picked and both wings out, which made the panel read as
	   part of the page rather than as an answer to anything; Dylan asked for it to wait for a press
	   on a card, and for a second press on the same card to put it away. So the cards light up and
	   swell under the pointer now (`Components/CarDetailV2.hoverCard`) to say that they can be
	   pressed, and the wings come OUT of the page's own edge when one is. A GAMEPAD MAKES THE SAME
	   GESTURE: the card's picture is in the highlight's walk, so landing on it is the hover and A is
	   the click. It used to be the highlight itself that picked, which a toggle cannot survive.

	3. THE PANEL IS NEVER THE ONLY WAY TO DO ANYTHING. Every card still carries its own verb button,
	   which is the 2026-08-24 rewrite's rule ("a tap is the verb") and the reason the old detail
	   pane was deleted: it made every action two presses. The wing's button is the same press
	   spelled larger, on the car you are already looking at, and a player who never looks at the
	   wings can still do everything from the grid.

	4. THE WINGS NEED THE ROOM THE HUD RAIL IS STANDING IN. A kit page is 0.6 of the screen's width
	   at 1080p and the rail's icon grid ends about 0.15 in, so there is no arrangement where a panel
	   wide enough to read sits left of the grid and clear of the rail — the arithmetic is in
	   `BuildCarDetailV2`'s header. So the rail steps aside while the wings are up, exactly as the
	   Play button already steps aside for any open page (`UIController._syncPlayRoom`), and by the
	   same route: this asks, `RaceEntryController` writes. `HideRail = false` puts the rail back and
	   the wings then draw over it, which is worth seeing once before deciding.

	5. IT IS ONE COMPONENT AND TWO PAGES. `Components/CarDetailV2` owns both wings, the turning car
	   and the stat rows; the page owns which card is selected and what the button says, because
	   PARK HERE and DRIVE are the page's word and not this file's.
]]

local CarDetailConfig = {}

--[[ Master switch. Off = neither car screen builds a detail component, both pages behave exactly as
	they did before this landed, and the rail never moves. The wings themselves stay in the place;
	they are hidden, which is where they start anyway. ]]
CarDetailConfig.Enabled = true

--- Header note 4. Off = the rail stays put and the left wing overlaps it.
CarDetailConfig.HideRail = true

--[[ How fast the car turns, in degrees a second. About fourteen seconds a revolution: slow enough
	that nothing on the car smears, quick enough that a glance catches it moving. `Modules/CarViewport`
	owns everything else about the shot, because the still pictures on the cards are the same shot. ]]
CarDetailConfig.SpinDegreesPerSecond = 26

--[[ THE NAMES THE BUILDER WRITES AND THE COMPONENT READS. One table rather than two lists of
	strings in two files that have to agree: `BuildCarDetailV2` makes exactly these and
	`Components/CarDetailV2` looks up exactly these. ]]
CarDetailConfig.Parts = {
	--- The two wings, children of the page frame itself.
	Left = "DetailLeft",
	Right = "DetailRight",

	--- On the left: the car's name, its rarity band, the box the turning car goes in, the money line
	--- and the level bar under it.
	Name = "CarName",
	Rarity = "Rarity",
	--- The gradient inside `Rarity`, tinted per band. Named by `BuildDealershipV2` on the card too.
	Tint = "Tint",
	Portrait = "Portrait",
	Rate = "Rate",
	Level = "Level",

	--- On the right: the stat rows, and the same two button faces a card wears.
	Stats = "Stats",
	StatRow = "StatRow",
	Bar = "ProgressBar",
	Fill = "Progress",
	Rating = "Rating",
	Title = "Title",
	Buttons = "Btns",
	Action = "EquipBtn",
	State = "EquippedBtn",

	--- The cyan halo on the card the wings are describing. A card can wear this AND the green rim
	--- (`BuildDealershipV2`'s `Rim`) at once: they answer different questions, and the halo is the
	--- thicker of the two so the pair reads as a ring inside a glow rather than as one muddy edge.
	Halo = "Pick",

	--[[ The card's own rim again, drawn thicker and held at transparency 1 until a pointer arrives.
		THE SATURATED END of the page's ramp, where the halo above is the light end of it: one says
		"you can press this" and the other says "this is the car you are looking at". It was white
		until 2026-09-17 and white is the one colour it cannot be, because the grid these cards sit on
		is opaque white — `BuildCarDetailV2`'s `HOVER_THICKNESS` has the measurements. The hover ring
		is built UNDER the halo, so a card wearing both reads as picked.
		`Components/CarDetailV2.hoverCard` fades it in and out; that file says why the cards react. ]]
	Hover = "Hover",

	--[[ The invisible press over a card's picture: what PICKS the car the wings describe.

		IT IS NOT THE CARD'S VERB and must never become it. The verb is the button under the picture
		and a press on it still spawns, parks or drives outright — the 2026-08-24 rule that a tap is
		the verb. This is the picture itself, which had no press at all before the wings existed, so
		a screen where nobody touches a picture behaves exactly as it always did.

		SELECTABLE, AND STILL UNTAGGED. It is a gamepad stop as of 2026-09-17 ("fix it so that a
		console can select that card") because the wings open on a press and shut on the same press
		again, and a pad that picked by HIGHLIGHTING would open and shut the panel as the DPad crossed
		the grid. So a console makes the pointer's gesture: the highlight landing on the picture is
		the hover, A is the click. The `UIButton` TAG stays off — it would add a second hover swell
		and a press sound on top of the whole-card reaction `Components/CarDetailV2.hoverCard`
		already gives, and it owns `Selectable` the moment it lands. ]]
	Select = "PickBtn",
}

--[[ Every string the wings print. Non-breaking spaces are added by the component where a
	`TextScaled` label would rather wrap than shrink, so these stay greppable. ]]
CarDetailConfig.Text = {
	--- The green line: what this car earns a second standing in your dealership. Hidden on the car
	--- picker, where the question is which car you are driving and not what it is worth.
	Rate = "{rate}/s",
	--[[ ...and what that line says without passive income (2026-09-28), when a parked car earns
		nothing a second: what THIS car is worth, condition included (`MarketValueConfig`) — the number
		its tips, the sell lot and a buyer's offer are all measured against. ]]
	Value = "WORTH {value}",
	--- The level bar's caption. Out of `RewardConfig.Xp.MaxLevel`, because a level with no ceiling
	--- on it is a number nobody can place — and the bar under it is filled by the same fraction.
	Level = "LEVEL {level} / {max}",
	--- The caption over the four bars.
	Stats = "STATS",
}

return CarDetailConfig
