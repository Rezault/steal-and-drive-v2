--[[
	StartCarController  (client)
	----------------------------
	The SELECT CAR screen's press, and the two facts its cards are drawn from. The third step of Play:
	Play opens the world screen, a world card opens this one, and a card here starts the run — in that
	world, in that car.

	  • IT HAS NO REMOTE OF ITS OWN. The press goes to `RaceEntryController:play(world, key)`, which
	    owns `RequestEnterRace` and its cooldown, so however a race is asked for there is one place
	    that decides whether to ask. The car rides on that request beside the world for the reason
	    written down there — two remotes are two round trips whose order nothing guarantees.

	  • THE WORLD IS HELD HERE, NOT WRITTEN ANYWHERE. `choose(index)` remembers which card was
	    pressed on the screen before and opens this one; nothing has moved the player, and the server
	    is told both facts at once when a car is pressed. So backing out of this screen leaves you
	    exactly where you were, which is what an X on a page should mean.

	    It survives being wrong: a screen opened without a world (an admin, a rail button somebody
	    authors later) falls back to the world the player is actually in, which is what the lobby pad
	    would have used anyway.

	  • THE SERVER DECIDES. `StartCarService` re-checks ownership against the profile and `RaceService`
	    owns every entry guard; a car this client should not have is answered with the world's own
	    starter rather than a refusal (see that service's header for why those differ). So the list
	    this screen draws is a convenience, not a permission — it is built from the collection
	    attribute, which is a broadcast of the same profile the server checks.

	  • NOTHING CONFIRMS, on purpose, and it is the same bargain the world screen makes: the player
	    attribute IS the answer, it replicates by itself, and a screen that redraws when the value
	    changes cannot get out of step with it the way an optimistic repaint can.

	`RaceStart`/`RaceEnd` are not bound here at all — `RaceEntryController` shuts both entry screens
	on `RaceStart`, because it is the thing that knows a race actually began.

	=== THE SAME SCREEN, FOR THE LOBBY PAD — 2026-10-08 ===
	The car pad (`LobbyCarConfig.Pad`, "YOU PICK THE CAR") opens this screen in SPAWN mode
	(`openForPad`, off the server's `OpenCarPadPicker`): every owned car, whatever world it is from,
	no starter card (a starter is not a car you own, so there is nothing to spawn), and a press asks
	the server to put that car on the pad (`RequestPadSpawn`) instead of starting a run. A world card
	(`choose`) puts it back in race mode, so the two flows can never leak into each other.

	2026-10-12: Sell mode reuses this collection grid and offers every owned car, with no starter or
	stored selection. A SELL opens SellPopupController through SellController.offerSelected; it
	never starts a race or spawns a car. The server's RequestSell validates the chosen key and price.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local StartCarConfig = require(ReplicatedStorage.shared.Configs.StartCarConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local StartCarController = Shard.new("StartCarController")

--- Whether Play is the one screen (`StartCarConfig.OneScreenPlay`); the old UI never is.
function StartCarController.oneScreen(_self): boolean
	return StartCarConfig.OneScreenPlay == true and UIRoot.isNewUI()
end

--[[ Public (`RaceEntryController`, and `preselect` below): put the one Play screen up, on the world
	the player is in. Forgetting the last pick here is the same promise the X makes on the old
	screens: closing without driving leaves nothing behind. ]]
function StartCarController.openPlay(self)
	self._world = nil
	self._mode = "race"
	Dispatcher:Publish("OpenPage", StartCarConfig.PlayPageName)
end

--- The Cars Inventory's "drive this one", taken once by the Play screen as its first selection.
function StartCarController.takePending(self): string?
	local key = self._pendingCar
	self._pendingCar = nil
	return key
end

-- === What the cards are drawn from ==========================================

--[[ Which world this screen is choosing a car FOR. The one handed over by the world screen, or —
	for a screen opened any other way — the world the player is already in, which is the world the
	lobby pad would race. Never nil, so the page never has to decide what to draw for "no world". ]]
function StartCarController.world(self): number
	return WorldConfig.resolve(self._world or Players.LocalPlayer:GetAttribute(WorldConfig.WorldAttribute))
end

--- The car the server says this player starts runs in, as a key — `StartCarConfig.DefaultKey` (the
--- empty string) meaning that world's own starter. Read off the attribute, which is the broadcast.
function StartCarController.selected(self): string
	local key = Players.LocalPlayer:GetAttribute(StartCarConfig.Attribute)
	return if type(key) == "string" then key else StartCarConfig.DefaultKey
end

--[[ Every car this player may drive into `world`, best first, as car keys. The default is NOT in
	here — the page adds that always-available card itself, then sorts it together with the owned
	cars by tier. The starter is not a car out of the collection and is no longer pinned first.

	Sorted by tier and then by key, the same order the dealership and SPAWN CARS screens use and for
	the same reason: the question is "what is my best car", and acquisition order buries the answer
	under whatever you happened to steal last. Several colours of one body land next to each other.

	`WorldLadderOnly` is applied here rather than in the page so that the rule lives with the code
	that also has to explain it to the server — see `StartCarConfig`. ]]
function StartCarController.driveable(self, world: number): { string }
	local keys = {}
	--[[ Split with `GarageConfig.split`, never a whitespace pattern: `Golf GTI` and `Model 3` are
		world 1 cars and a pattern that breaks on spaces turns each of them into two cars nobody
		owns. ]]
	for _, key in GarageConfig.split(Players.LocalPlayer:GetAttribute(GarageConfig.OwnedAttribute)) do
		local body = GarageConfig.parseCarKey(key)
		if not (body and GarageConfig.TierOfBody[body]) then
			continue
		end
		--- The pad spawns into the lobby, which is no world: every owned car is offered (header).
		local anyWorld = self._mode == "pad" or self._mode == "sell"
		if not anyWorld and StartCarConfig.WorldLadderOnly and WorldConfig.WorldOfBody[body] ~= world then
			continue
		end
		table.insert(keys, key)
	end

	table.sort(keys, function(a, b)
		local ta = GarageConfig.TierOfBody[(GarageConfig.parseCarKey(a))] or 0
		local tb = GarageConfig.TierOfBody[(GarageConfig.parseCarKey(b))] or 0
		if ta ~= tb then
			return ta > tb
		end
		return a < b
	end)
	return keys
end

--- "race" (the third step of Play) or "pad" (the lobby pad's SPAWN screen). See the header.
function StartCarController.mode(self): string
	return self._mode
end

--[[ Public (off `OpenCarPadPicker`): the server says a pad was pressed. Put this screen up in SPAWN
	mode; the pad itself is remembered on the server, so nothing about it is held here. ]]
function StartCarController.openForPad(self)
	self._mode = "pad"
	Dispatcher:Publish("OpenPage", StartCarConfig.PageName)
end

-- Sell lots borrow the same collection grid, but a pick opens a confirmation instead of spawning.
function StartCarController.openForSell(self)
	self._mode = "sell"
	Dispatcher:Publish("OpenPage", StartCarConfig.PageName)
end

-- === The presses ============================================================

--[[ Public (`WorldController`): a world card was pressed. Remember it and put this screen up.

	`OpenPage` and not a direct call into the page, so this controller never has to know that the
	page exists — the same wire every other screen in the kit is opened over. ]]
function StartCarController.choose(self, world: number?)
	self._world = world
	self._mode = "race"

	--- On the one screen a world card SELECTS the world; DRIVE is the press that starts the run.
	if self:oneScreen() then
		Dispatcher:Publish(StartCarConfig.WorldChosenEvent, world)
		return
	end

	--[[ A CAR ALREADY CHOSEN FROM THE INVENTORY (`preselect`) skips this screen and drives — the
		world was the only question left. Consumed here whatever happens, so it can only ever apply to
		the world press that followed it. A car that may not be driven in THIS world (`WorldLadderOnly`)
		falls back to the screen, where the player can see why rather than being handed the starter. ]]
	local pending = self._pendingCar
	self._pendingCar = nil
	if pending then
		if table.find(self:driveable(self:world()), pending) then
			self:play(pending)
			return
		end
	end

	Dispatcher:Publish("OpenPage", StartCarConfig.PageName)
end

--[[ Public (via `StartCarConfig.PreselectEvent`): the Cars Inventory double-pressed a car. Remember it
	and open the world screen; `choose` drives it once a world is picked.

	FORGOTTEN IF THE WORLD SCREEN IS SHUT WITHOUT A PICK, so a later ordinary PLAY still shows the
	car screen rather than silently driving a car chosen minutes ago. `choose` runs on the press,
	before the screen closes, so a real pick has always consumed it by the time this fires. ]]
function StartCarController.preselect(self, key: string?)
	if type(key) ~= "string" or key == "" then
		return
	end
	self._pendingCar = key
	if self:oneScreen() then
		--- The car arrives already selected (`takePending`); the world is still the player's to pick.
		self:openPlay()
		return
	end
	Dispatcher:Publish("OpenPage", WorldConfig.PageName)

	if self._watchingWorldPage then
		return
	end
	local UIController = Shard.get("UIController")
	local page = UIController and UIController.pages and UIController.pages[WorldConfig.PageName]
	local ui = page and page.PageUI
	if ui and ui:IsA("GuiObject") then
		self._watchingWorldPage = true
		ui:GetPropertyChangedSignal("Visible"):Connect(function()
			if not ui.Visible then
				task.defer(function()
					self._pendingCar = nil
				end)
			end
		end)
	end
end

--[[ A car card was pressed: race, in the world this screen was opened for, in that car.

	PRESSING A CAR STARTS THE RUN rather than merely selecting it, which is the same call the world
	screen makes about its own cards — this is the last step of Play, so the alternative would be a
	fourth press on a GO button the mock-up does not have. The card the server has stored still reads
	as SELECTED, because that is what the lobby pad and the next Play will use.

	Routed through `RaceEntryController` rather than firing the remote here, so the entry cooldown
	and the "am I already racing" check stay in the one place that owns them however the race was
	asked for. ]]
function StartCarController.play(self, key: string?)
	if self._mode == "sell" then
		local sell = Shard.get("SellController")
		if sell and type(key) == "string" and not StartCarConfig.isDefault(key) then
			sell:offerSelected(key)
		end
		return
	end
	--- SPAWN mode: the press is a car for the pad, never a race (header). The starter is never offered.
	if self._mode == "pad" then
		if type(key) ~= "string" or StartCarConfig.isDefault(key) then
			return
		end
		self:getRemoteEvent("RequestPadSpawn"):Fire(key)
		Dispatcher:Publish("ClosePage", StartCarConfig.PageName)
		return
	end
	local RaceEntryController = Shard.get("RaceEntryController")
	if not RaceEntryController then
		self.log:warn("RaceEntryController is not up; the car screen cannot start a race.")
		return
	end
	RaceEntryController:play(self:world(), key or StartCarConfig.DefaultKey)
end

StartCarController:withRemoteEvents({
	{
		OpenCarPadPicker = function()
			StartCarController:openForPad()
		end,
	},
	--- client -> server (carKey): the pad's pick. `LobbyCarService._onPadPick` checks it.
	"RequestPadSpawn",
})

StartCarController:withLifecycle({
	init = function(self)
		self._world = nil :: number?
		self._mode = "race"
	end,

	start = function(self)
		Dispatcher:Subscribe(StartCarConfig.PickEvent, function(key: string?)
			self:play(key)
		end)
		Dispatcher:Subscribe(StartCarConfig.PreselectEvent, function(key: string?)
			self:preselect(key)
		end)
	end,
})

return StartCarController
