--[[
	StealTagConfig
	--------------
	THE PRICE TAG OVER A CAR YOU JUST STOLE (`StealTagController`, 2026-10-12). Aleafo asked whether a
	player should see what a stolen car is worth "to make a decision to continue or not"; Dylan's
	answer was a small tag that pops up over the car for a few seconds rather than a screen that asks
	a question.

	JUST THE VALUE (Dylan, same day). The first pass also carried the rarity word, four stat bars and
	a comparison with the last car, and it was too much over the road. Now it is one pill: the price,
	on the kit's gradient for the car's rarity, so the colour still says how rare it is without a word
	to read.

	=== WHY IT IS IN THE WORLD AND SIZED IN STUDS ===============================================

	It is a BillboardGui on the car's HitBox, the same place the HP bar floats, because the car is
	where the player is already looking and the screen edges are taken (the layout table in
	`TutorialController`). Its size is in STUDS, so it is the same share of the screen on a phone as
	on a monitor: the race camera frames the car identically everywhere.

	=== THE VALUE IS THE ONE THE GAME PAYS ======================================================

	`MarketValueConfig.valueOf(tier, mutation)` with no record: the car at full condition, which is
	what it is on the frame of a steal because a steal refills the car. It is what the car sells for
	if you get it home undamaged; crashing on the way still lowers it (`MarketValueConfig.Condition`).

	`Enabled = false`: no tag, nothing else changes.
]]

local StealTagConfig = {}

StealTagConfig.Enabled = true

--- Seconds fully shown after the pop, then `FadeTime` to go.
StealTagConfig.Hold = 3
StealTagConfig.PopTime = 0.3
StealTagConfig.FadeTime = 0.35

--[[ The pill's size in STUDS (a car's HitBox is 8.43 wide, so this is a bit narrower than the car).
	`Aspect` is width over height. ]]
StealTagConfig.Width = 6
StealTagConfig.Aspect = 3

--[[ Studs between the roof and the tag's bottom edge. Just clears the HP bar's slot (`CarHudController`:
	0.7 over the roof, 1.3 tall, so its top is 2.0 up), so a hit while the tag is up shows both
	without overlapping. Any higher and the race camera, which looks down the road, draws it over the
	traffic ahead instead of over your car. ]]
StealTagConfig.Clearance = 2.1
--- Studs the tag rises through as it pops in.
StealTagConfig.Rise = 0.6

--[[ How much bigger the tag is on a small screen, chosen by the viewport's SHORT side in pixels.
	1 at and above `PhoneBelow`; `PhoneScale` under it, because a phone's screen is physically small
	and the number has to stay readable at arm's length. ]]
StealTagConfig.PhoneBelow = 500
StealTagConfig.PhoneScale = 1.3

--- Seconds the value takes to count up to its figure.
StealTagConfig.CountTime = 0.55

return StealTagConfig
