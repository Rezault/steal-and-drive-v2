--[[
	WorldController  (client)
	-------------------------
	The world-select screen's press, and the two facts its cards are drawn from. Deliberately thin:
	the server owns which world you are in (`WorldService`), the page owns what a card looks like,
	and this is only the wire between them.

	  • A PRESS MEANS ONE OF THREE THINGS, and which one is decided here rather than by the button:
	    play the world, offer to buy it, or confirm the purchase. A world you do not own asks for
	    the price once and takes it on the second press — see `_onTeleportPressed`. That confirm
	    step is not decoration: the top world costs 1.3 billion and the kit has no dialog to put in
	    front of it, so the button IS the dialog.

	  • PRESSING A CARD CHOOSES THAT WORLD AND ASKS WHICH CAR. It used to only move you there, with
	    Play as a separate button afterwards; then the screen became what the HUD's Play button opens
	    and the card became the second click; now it hands off to the SELECT CAR screen, which is the
	    third and the one that actually asks for the race (see `StartCarController`, and
	    `StartCarConfig.Enabled` / `RaceConfig.PlayOpensWorldSelect` for the ways back). The move
	    still happens — the world you picked is the world you are in when the run ends, and it
	    persists — it just arrives as part of entering rather than as its own trip, and it is the CAR
	    screen's press that carries it.

	  • THE CARD IS NOT NAMED HERE. A card's PLAY button carries an `Action` attribute
	    (`WorldConfig.TeleportAction`) and the card above it carries `World`; `Components/Button`
	    publishes the action on Dispatcher and this subscribes to it. Same bargain as the rail's
	    `Page` attribute and the Play button's `EnterRace` — the place file decides which button
	    plays a world, the code decides what that means — so one handler serves three authored
	    cards or thirty cloned ones without knowing how many there are.

	  • THE SERVER DECIDES. The press only fires `RequestEnterRace` (through `RaceEntryController`,
	    which owns that remote and its cooldown); `RaceService` and `WorldService` own every guard
	    between them and either can refuse — a world that does not exist, a run in progress, one day
	    a world you have not earned. So `canTeleport` here is courtesy — it stops the obvious dead
	    press at the source and lets the card say why — and nothing downstream trusts it as
	    permission.

	  • NOTHING CONFIRMS. There is no "you teleported" remote coming back, on purpose: the player
	    attribute IS the answer, it replicates by itself, and a screen that redraws when the value
	    changes cannot get out of step with the value the way an optimistic repaint can. A refused
	    press therefore does nothing visible, which is correct — you did not go anywhere.

	`RaceStart`/`RaceEnd` bracket the run for the same reason `RaceEntryController` uses that pair
	rather than `RaceEntering`/`RaceLive`: it is the pairing that always closes, including on the
	entry paths that fail after the fade has gone up.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local StartCarConfig = require(ReplicatedStorage.shared.Configs.StartCarConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local WorldController = Shard.new("WorldController")

--[[ How long a card stays on CONFIRM? before it goes back to showing the price. Long enough to
	read the number and press again, short enough that a card left confirming while you look at
	something else has forgotten by the time you come back to it. ]]
local CONFIRM_SECONDS = 4

-- === What the cards are drawn from ==========================================

--- Which world we are in. Resolved, so it is a real index from the first frame of the session,
--- before the server has written anything.
function WorldController.worldOf(self): number
	return WorldConfig.resolve(Players.LocalPlayer:GetAttribute(WorldConfig.WorldAttribute))
end

--- Whether a press would do anything right now, and why not if it wouldn't. The reason is a label
--- for the card, not an error — see `WorldService` for the authoritative version of both.
function WorldController.canTeleport(self, index: unknown): (boolean, string?)
	if self._racing then
		return false, "racing"
	end
	if not WorldConfig.isUnlocked(index, Players.LocalPlayer) then
		return false, "locked"
	end
	return true
end

--[[ Everything one card needs, in one call: what the press will do, what the button says, and
	whether it is live. The page draws itself from this and decides nothing.

	`action` is "play" | "buy" | "confirm" | "blocked", and `enabled` is whether the button is live.
	A "buy" is live WHETHER OR NOT YOU CAN AFFORD IT (2026-09-30, Aleafo: "if they don't have enough
	money: click and prompt product"): the button stays green, and `affordable` is what says which
	press it is, a confirm-then-buy or an offer of the cash that closes the gap (`_onTeleportPressed`).

	Cash is read here rather than in `WorldConfig` because the attribute belongs to `GarageConfig`
	and that file has no business knowing this one's names. The server passes the profile's balance
	into the same function; see `WorldService.unlockWorld`. ]]
function WorldController.cardState(self, index: unknown): { [string]: any }
	if self._racing then
		return { action = "blocked", label = "racing", enabled = false }
	end

	local player = Players.LocalPlayer
	local cash = tonumber(player:GetAttribute(GarageConfig.CashAttribute)) or 0
	local state, detail = WorldConfig.unlockStateFor(index, player, cash)

	if state == "open" then
		return { action = "play", label = "play", enabled = true }
	end
	if state == "needs" then
		return {
			action = "blocked",
			label = "needs",
			enabled = false,
			required = detail.required,
			progress = detail.progress,
			previousName = detail.previousName,
			previousShort = detail.previousShort,
		}
	end

	-- "buy". The confirm is local state and deliberately not part of the config's answer: it is a
	-- fact about this screen in this moment, and the server neither knows nor cares about it.
	local confirming = self._confirming == WorldConfig.resolve(index) and os.clock() < self._confirmUntil
	return {
		action = if confirming then "confirm" else "buy",
		label = if confirming then "confirm" else "buy",
		enabled = true,
		cost = detail.cost,
		affordable = detail.affordable,
	}
end

-- Tell the screen something it draws itself from has changed.
function WorldController._publish(self)
	Dispatcher:Publish(WorldConfig.StateEvent)
end

function WorldController._setRacing(self, racing: boolean)
	self._racing = racing
	self:_publish()
end

-- === The press ==============================================================

--[[ Which world a pressed button stands for: the nearest ancestor carrying the attribute.

	Walked rather than assumed to be `button.Parent`, because the card is a piece of authored art
	and the button can gain a wrapper the day someone adds a UIPadding or a shadow frame around it.

	The walk stops at the ScreenGui, and that boundary is load-bearing rather than tidy: keep going
	and it reaches the Player, which carries an attribute of the same name holding the world you are
	ALREADY in — so a button with no card above it would resolve to "here" and the press would be
	swallowed as a no-op instead of warning that the page was never built. ]]
function WorldController._worldOfButton(self, button: Instance?): number?
	local node = button
	while node do
		local value = node:GetAttribute(WorldConfig.WorldAttribute)
		if value ~= nil and value ~= "" then
			return tonumber(value)
		end
		if node:IsA("LayerCollector") then
			break
		end
		node = node.Parent
	end
	return nil
end

--[[ Stop offering to sell whatever was mid-confirm, and repaint. Called when the press lands, when
	the purchase arrives, and on the timer — all three end the same way, so they share the exit. ]]
function WorldController._clearConfirm(self)
	if self._confirming then
		self._confirming = nil
		self._confirmUntil = 0
		self:_publish()
	end
end

--[[ Press a card. Three outcomes, in the order the player meets them:

	  • A WORLD YOU OWN races. The world you are already in is a normal press, not a no-op — it is
	    the world most players will pick most of the time. Routed through `RaceEntryController`
	    rather than firing the remote from here, so the entry cooldown and the "am I already
	    racing" check stay in the one place that owns them however the race was asked for.
	  • A WORLD YOU COULD BUY asks first. The card swaps to CONFIRM? and the NEXT press on the same
	    card buys it. Pressing a different card cancels the first one, which is why the confirm is
	    a single index and not a set.
	  • A WORLD YOU ARE SHORT FOR offers the cash. No confirm, because no money moves: the server
	    refuses the purchase and opens the cheapest cash pack that covers the gap
	    (`WorldService.unlockWorld`, `CashService.offerTopUp`), and Roblox's purchase window is its
	    own confirmation. Sent as offer-only, so a balance that caught up on the server a hop before
	    it did here still cannot buy the world without the confirm.
	  • ANYTHING ELSE does nothing visible, which is correct — you cannot go there yet.

	The server re-checks every one of these (`WorldService.unlockWorld`, `setWorld`), so nothing
	here is permission; it stops the dead press at the source and lets the card say why. ]]
function WorldController._onTeleportPressed(self, button: Instance?)
	local index = self:_worldOfButton(button)
	if not index then
		-- The authored cards ship with `World = ""` — the scaffold's placeholder — so this is what
		-- an un-rebuilt page looks like, not a corrupt one.
		self.log:warn("A TeleportToWorld button has no World attribute above it; nothing to play.")
		return
	end

	local state = self:cardState(index)

	-- A press anywhere else takes the offer off the table before it does its own job.
	if self._confirming and self._confirming ~= index then
		self:_clearConfirm()
	end

	if state.action == "confirm" then
		self._confirming = nil
		self._confirmUntil = 0
		self:getRemoteEvent("RequestUnlockWorld"):Fire(index)
		-- No optimistic repaint: the unlock attribute replicating is the answer, and a card that
		-- painted itself owned before the server agreed could show a world that was refused.
		self:_publish()
		return
	end

	if state.action == "buy" then
		if not state.affordable then
			self:getRemoteEvent("RequestUnlockWorld"):Fire(index, true)
			return
		end
		self._confirming = index
		self._confirmUntil = os.clock() + CONFIRM_SECONDS
		self:_publish()
		-- Put the price back up if it is not taken. Guarded on the index rather than a token: the
		-- only thing that can have changed `_confirming` in the meantime is another press, and
		-- that press already owns the repaint.
		task.delay(CONFIRM_SECONDS, function()
			if self._confirming == index then
				self:_clearConfirm()
			end
		end)
		return
	end

	if state.action ~= "play" then
		return
	end

	--[[ A WORLD YOU OWN OPENS THE CAR SCREEN rather than starting the run, because picking the car is
		the step after picking the world (Trello: PLAY → SELECT WORLD → ALLOW USER TO CHANGE CAR).
		The world is handed over rather than written anywhere: nothing has moved the player yet, and it
		is the card THAT screen presses that carries both to the server as one request.

		`StartCarConfig.Enabled` off, or that controller missing, falls through to what this did
		before — press a world, drive it — so the feature can be switched out without the world screen
		becoming a dead end. ]]
	local StartCarController = Shard.get("StartCarController")
	if StartCarConfig.Enabled and StartCarController then
		StartCarController:choose(index)
		return
	end

	local RaceEntryController = Shard.get("RaceEntryController")
	if not RaceEntryController then
		self.log:warn("RaceEntryController is not up; the world screen cannot start a race.")
		return
	end
	RaceEntryController:play(index)
end

-- No `RequestSetWorld` here any more: a card press is a race request now, and the world moves with
-- it. The remote still exists as `WorldService`'s front door for anything that wants to move a
-- player without starting a run — nothing on this client does.
WorldController:withRemoteEvents({
	{
		RaceStart = function()
			WorldController:_setRacing(true)
		end,
		RaceEnd = function()
			WorldController:_setRacing(false)
		end,
		--[[ A purchase went through (punch list A2). Sound only: the card already redraws off the
			unlock attribute, and that stays the answer. ]]
		WorldBought = function()
			local sounds = Shard.get("SoundController")
			local cue = WorldConfig.UnlockSound
			if sounds and cue then
				sounds:PlayNamed(cue.Group, cue.Name)
			end
		end,
	},
	"RequestUnlockWorld",
})

WorldController:withLifecycle({
	init = function(self)
		self._racing = false
		self._confirming = nil :: number?
		self._confirmUntil = 0
	end,

	start = function(self)
		Dispatcher:Subscribe("UIAction", function(action: string, instance: Instance?)
			if action == WorldConfig.TeleportAction then
				self:_onTeleportPressed(instance)
			end
		end)

		local player = Players.LocalPlayer

		-- The server's answer arriving (on join, and on every accepted teleport).
		player:GetAttributeChangedSignal(WorldConfig.WorldAttribute):Connect(function()
			self:_publish()
		end)

		--[[ The other three things a card is now drawn from, all of them server-owned attributes
			that replicate by themselves:

			  • what you own — a purchase landing, which also takes the confirm down,
			  • how far down each road you have got, so a card flips from "DESERT 100%" to a price
			    the moment the run that finished it settles,
			  • cash, so a press on a price you could not afford becomes a real purchase the moment
			    you can, even while you are standing on the collect mat.

			None of them is polled, and none of them is optimistic: every one is the server having
			already agreed. ]]
		player:GetAttributeChangedSignal(WorldConfig.UnlockAttribute):Connect(function()
			self:_clearConfirm()
			self:_publish()
		end)
		player:GetAttributeChangedSignal(WorldConfig.ProgressAttribute):Connect(function()
			self:_publish()
		end)
		player:GetAttributeChangedSignal(GarageConfig.CashAttribute):Connect(function()
			self:_publish()
		end)
	end,
})

return WorldController
