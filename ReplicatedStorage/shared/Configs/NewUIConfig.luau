--[[
	NewUIConfig
	-----------
	THE ONE SWITCH the Cartoony Kit migration hangs off. Off, and the game runs exactly the code it
	ran before any of this existed. On, and the client boots the new ScreenGui and the new page
	modules instead.

	The plan this belongs to is `docs/NewUI-Migration-Plan.md`; the running notes are
	`docs/NewUI-Migration-Notes.md`.

	=== WHAT THE FLAG ACTUALLY CHANGES ========================================================

	Three things, and nothing else:

	  1. WHICH ScreenGui IS THE UI. `MainUI` or `MainUIV2`, resolved once by `Modules/UIRoot`, which
	     every lookup goes through. The unused one is destroyed at boot, so nothing can bind half of
	     one UI and half of the other.
	  2. WHICH PAGE MODULES LOAD. `UIController/Pages` or `UIController/PagesV2`. The page NAMES are
	     the same in both, because `OpenPage` events, `Page` attributes and the tutorial's paths all
	     name pages by string and none of them should have to care.
	  3. WHAT THE TOPBAR BUILDS. With the flag on, Settings, Shop, Radio and Music move into the new
	     HUD's side grid and only the Show UI chip is left in the topbar. That is Phase 2; until it
	     lands the topbar behaves the same either way.

	IT IS READ ONCE, AT CLIENT BOOT. Swapping eight pages mid-session is not worth building, so
	flipping this means changing the value and rejoining. `UIRoot` caches the answer for that reason,
	and because a value that could change between two lookups is a UI that could be half swapped.

	=== THE TESTER OVERRIDE ===================================================================

	`OverrideAttribute` is a Player attribute an admin command can set so one tester sees the new UI
	in a build where everyone else sees the old one. The client reads it at boot alongside this flag,
	so it is a rejoin for that player and nothing else. Set it to `true` or `false` to force either
	UI; leave it unset (the normal case) and `Enabled` decides.

	Nothing sets it yet. The attribute is named here rather than in the admin panel so that the two
	halves cannot drift, exactly as `GamepadConfig.ModalAttribute` is.
]]

local NewUIConfig = {}

--[[ THE FLAG. False is the shipping value for the whole migration: the new UI is built, verified
	and turned on for testers before it is turned on for everyone, and a half-built page behind a
	flag that is off costs a player nothing. ]]
NewUIConfig.Enabled = true

--- The authored ScreenGui each answer points at; neither resets on spawn. Only the new one is in
--- `StarterGui` now: the old one is parked at `ServerStorage.UIImports.MainUI` (2026-10-20) and has
--- to go back to `StarterGui` before `false` here, or the tester override, can show it (`UIRoot`).
NewUIConfig.ScreenGuiName = "MainUIV2"
NewUIConfig.LegacyScreenGuiName = "MainUI"

--- The folder under `UIController` the page modules come from, per answer. The names of the pages
--- inside are deliberately identical between the two.
NewUIConfig.PagesFolderName = "PagesV2"
NewUIConfig.LegacyPagesFolderName = "Pages"

--- Player attribute that overrides `Enabled` for one player. See the header.
NewUIConfig.OverrideAttribute = "NewUI"

--[[ Whether the race results (STOLEN, WRECKED, BUSTED) move onto the kit panel when the new UI is
	on. Off (Dylan, 2026-09-17): the old results, type laid on the black like the loading screen,
	read better as the end of a run, so they stay with either UI. The revive question keeps its kit
	card. `BuildRaceResultsV2` and the panel code are kept, so this is the one line to turn it back. ]]
NewUIConfig.KitRaceResults = false

--[[ The wreck as ONE screen (Aleafo's reference, 2026-09-30). True: the revive question also
	reports the run (the crashed car in the corner, WRECKED, the ladder bar, what it paid and kept)
	and counts down under the panel to racing again on its own. END RUN goes home with no results
	screen after it, REVIVE is unchanged, and letting the count run out races again in the same world
	and car. False: the kit revive question and the old results screen after it, as before.
	`BuildReviveV2` builds both templates (`Revive`, `WreckRevive`), so this is the one line to go back.
	New UI only; the old UI keeps its own revive screen whatever this says. ]]
NewUIConfig.WreckPanel = true

--[[ ...and EVERY OTHER ENDING on the same panel (Dylan, 2026-10-01). True: a getaway (STOLEN!, the
	car turning on a sunburst), a bad landing (WIPED OUT, your ragdoll in the corner), a fall, and a
	wreck or bust with no revive left all show the `WreckRevive` panel over the scene, with HOME and
	RACE AGAIN for buttons and the same countdown to racing again. The server holds the return until
	it is answered (`RaceConfig.EndPanel`). False: those endings keep the old results screen on black.
	Needs `WreckPanel` (it is that panel), and new UI only. ]]
NewUIConfig.EndPanel = true

--[[ Which face the dealership upgrade billboards wear when the new UI is on (Dylan, 2026-09-17).

	Every billboard carries BOTH faces on its screen plate, drawn by `BuildPlotUpgradeSigns`: the
	classic one in the `car ui.psd` kit (`UpgradeGui`) and a Cartoony Kit one (`UpgradeGuiKit`). The
	server fills in both, and `UpgradeController` shows one per client, so this is a rejoin for the
	player and not a rebuild of the map.

	True puts the kit face up for anyone on the new UI (the flag above, or the tester override). A
	player on the old UI always sees the classic face, whatever this says. False keeps the classic
	face for everybody. ]]
NewUIConfig.KitUpgradeBoards = true

--[[ Which layout the workshop (the customization bay's screen) wears when the new UI is on
	(2026-09-30). True is the CARD layout off Aleafo's reference: a navy card per option with a
	coloured icon tile, level dots, and PAINT picked on the swatches and bought on its own button
	(`BuildWorkshopCards`). False is the one before it, the kit's coloured upgrade rows on a white body
	(`BuildWorkshopV2`). Both templates stay built on the shelf, so this is the one line to go back.
	A missing cards template falls back to the rows with a warning. ]]
NewUIConfig.WorkshopCards = true

--[[ Which face the workshop podium's CUSTOMIZE sign wears for a player on the new UI (2026-09-30).
	The board carries two pairs of SurfaceGuis, the classic purple plaque and a kit face built to
	match the card-layout workshop screen it opens (`BuildWorkshopSign`), and `UpgradeController`
	flips them locally, the same way `KitUpgradeBoards` does the forecourt billboard. A player on the
	old UI always sees the classic plaque. False keeps the plaque for everybody. ]]
NewUIConfig.KitWorkshopSign = true

--[[ Where Radio and Settings live on the new UI (Leaf, 2026-10-06: "Settings can be topbar"). True:
	they are topbar chips all the time, lobby and race alike, and the side rail holds only Shop, Index
	and Quest. False: the 2026-09-16 layout, chips in a race only, because the rail had a cell for
	each in the lobby. The rail is a place edit (`MainUIV2.HUD.Rail`), so going back to false means
	putting the Radio and Settings cells back there too, or the lobby has no way into either. ]]
NewUIConfig.TopbarRadioSettings = true

--[[ Where the kit itself is parked: `ServerStorage.UIImports.NewUITemplate`, a Folder holding the
	pack's own ScreenGui and its `Container` of 24 frames. Named here so a command that clones a
	frame out of it and a human reading this file are looking at the same path.

	IT IS IN ServerStorage ON PURPOSE. In `StarterGui` all 7,616 instances were copied into every
	player's PlayerGui on every respawn, disabled ScreenGui or not. Nothing needs the kit at runtime:
	each V2 page carries its own row templates, the way today's pages do. ]]
NewUIConfig.TemplatePath = "ServerStorage.UIImports.NewUITemplate"

return NewUIConfig
