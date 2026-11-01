--[[
	StartCarConfig
	--------------
	WHICH CAR THE RUN STARTS IN, when the player has an opinion about it. The third step of Play:
	press Play, pick a world, pick the car you drive into it (Trello: "PLAY → SELECT WORLD → ALLOW
	USER TO CHANGE CAR").

	  • WHY IT EXISTS. The loop is "steal a car, keep it, drive it next time", and until now only the
	    first two halves were real: every run started in `WorldConfig.startBodyFor(world)` whatever
	    was in the collection, so a garage full of stolen supercars changed nothing about driving.
	    This is the third half.

	  • THE DEFAULT IS UNCHANGED AND IS ALWAYS OFFERED. An empty selection (`DefaultKey`) means "that
	    world's own starter", which is exactly what every run did before this file existed — so a
	    fresh player, a player who never opens the screen, and the lobby pad all get the car they
	    always got. Nothing here can leave a player with no car to press.

	  • IT DOES NOT MAKE THE START CAR BANKABLE. A car is banked off the `Tier`/`Body`/`Paint`
	    attributes that `StealController._applyTier` stamps and nothing else does (GetawayService's
	    header), and the start car is spawned carrying none of them however it was chosen. So driving
	    your own Lambo off the line still cannot be turned in at the truck for a second Lambo — you
	    have to steal something to have something to bank, which is the whole game.

	  • IT IS ONE CAR, NOT ONE PER WORLD. The choice is remembered globally and offered afresh on
	    every world screen, because the question the player is answering is "what do I want to drive",
	    not "what do I drive HERE". A selection whose body is not on the world you picked is still
	    honoured (see `WorldLadderOnly`), so there is nothing per-world for the store to keep.

	THE ATTRIBUTE IS THE BROADCAST, THE PROFILE IS THE TRUTH — the same split as cash, ownership, the
	lot and the world index. `StartCarService` is the only writer of either.
]]

local StartCarConfig = {}

--[[ Off = Play goes straight from the world card into the race, in that world's own starter, which
	is exactly what the flow did before this feature. The switch back, and the same bargain
	`RaceConfig.PlayOpensWorldSelect` makes one step earlier in the same flow. ]]
StartCarConfig.Enabled = true

--[[ The screen: the module under `UIController/Pages` and the Frame under `MainUI.Pages`, which have
	to agree. Named here rather than only in the place file because the WORLD screen opens it — the
	two are one flow — and neither of those files should be hard-coding the other's name. ]]
StartCarConfig.PageName = "StartCar"

--[[ PLAY ON ONE SCREEN (2026-10-25): Play opens `PlayMenu`, where the world and the car are picked
	side by side and DRIVE starts the run, instead of Play -> Worlds -> Select Car. New UI only; the
	old UI keeps its two screens. Off = the two-screen flow everywhere, unchanged. The Select Car
	page stays either way: the lobby car pad and Sell borrow it. ]]
StartCarConfig.OneScreenPlay = true
StartCarConfig.PlayPageName = "PlayMenu"
--- Published by `StartCarController.choose` on the one screen, carrying the world index picked.
StartCarConfig.WorldChosenEvent = "PlayMenuWorldChosen"

--[[ What the page publishes on Dispatcher when a card is pressed, carrying the car key. Same shape
	as the SPAWN CARS screen's `SpawnCarPick`: the page decides nothing, it says which card was
	pressed and `StartCarController` decides what that means. ]]
StartCarConfig.PickEvent = "StartCarPick"

--[[ What the Cars Inventory publishes when a car's picture is DOUBLE-pressed (2026-09-28), carrying
	the car ID: "drive this one". `StartCarController.preselect` remembers it and opens the world
	screen, and the world picked there starts the run in that car without the SELECT CAR step. ]]
StartCarConfig.PreselectEvent = "StartCarPreselect"

--[[ The chosen car, as a CAR KEY ("Camaro:6" — body and colour, `GarageConfig.carKey`), mirrored
	onto the Player so the page can draw itself and so anything else that wants to know can read it
	without a remote. `DefaultKey` (the empty string) is a real value and the one every player starts
	on: it means "whatever this world's starter is", resolved per race rather than stored, so the day
	a world's `StartRung` changes every player who never chose still gets the new car. ]]
StartCarConfig.Attribute = "StartCar"
StartCarConfig.ProfileKey = "StartCar"
StartCarConfig.DefaultKey = ""

--[[ NO COOLDOWN OF ITS OWN, deliberately, unlike every other request front door in this codebase.
	The selection has no remote: it rides along with `RequestEnterRace`, which is already rate
	limited by `RaceConfig.EnterRequestCooldown` on both sides. A second limiter here would only be
	a second number to keep in step with that one. Give this feature its own remote one day and it
	needs its own cooldown the same day. ]]

--[[ FALSE = you may drive any car you own on any road. TRUE = the list is filtered to bodies that
	belong to the world you picked (`WorldConfig.WorldOfBody`).

	False is the call, and it is a smaller call than it looks. The ladders RESTART per world —
	world 2's beater is as slow as world 1's (`WorldConfig` note 4, `StealConfig.TierStats`) — so
	bringing a world-4 car onto world 1's road is not bringing a faster car, it is bringing a
	different-looking one at roughly the top of the local range. What it buys is the thing the
	feature is for: the car you stole is a car you can go and drive, wherever you feel like driving
	it. Stealing still works unchanged on any road, because a steal redresses you into whatever the
	local traffic is.

	Turn it on if a world should ever read as a self-contained set. Nothing else has to change: the
	page filters, and `StartCarService.carFor` falls back to the world's starter for a selection the
	filter would have hidden, so a saved choice cannot smuggle a car past a rule switched on later. ]]
StartCarConfig.WorldLadderOnly = false

--- Is this the "use the world's own starter" selection? Written down once because three files ask.
function StartCarConfig.isDefault(key: unknown): boolean
	return key == nil or key == StartCarConfig.DefaultKey
end

return StartCarConfig
