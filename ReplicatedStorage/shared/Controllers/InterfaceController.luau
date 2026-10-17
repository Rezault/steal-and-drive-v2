--[[
	InterfaceController  (client)
	-----------------------------
	PUTTING THE GAME'S UI AWAY AND GETTING IT BACK. Turned on from the second row of the settings
	screen, from the H key, and from the tab it leaves behind. `InterfaceConfig` is the words, the
	answers and the reasoning about why this is not saved; this is the machinery.

	=== IT SWEEPS `PlayerGui` RATHER THAN ASKING ANYBODY ======================================

	There are more than twenty ScreenGuis in this game and every one of them is built and owned by a
	different controller. A "hide yourself" call on each would be twenty edits, twenty chances to
	miss one, and a twenty-first the day somebody adds a screen, which is the version of this feature
	that is quietly broken for a month.

	So this walks `PlayerGui`, switches off every ScreenGui it finds, and remembers what each one WAS
	so that showing again puts back exactly the arrangement it interrupted. A screen that was already
	off stays off. That last part is the whole reason this cannot be a loop that sets everything to
	true on the way out: half the screens in this game are modal panels sitting switched off, and
	restoring them all would open every one of them at once.

	=== TWO THINGS FIGHT THE SWEEP, AND BOTH ARE HANDLED ======================================

	  1. SCREENS THAT DID NOT EXIST YET. Several controllers build their ScreenGui the first time it
	     is needed rather than at boot. One built while the UI is
	     away would arrive switched on, over a screen the player has deliberately cleared. So the
	     sweep leaves a `DescendantAdded` listener up for as long as it is hiding, and newcomers are
	     caught the moment they are parented.

	  2. SCREENS THAT SWITCH THEMSELVES ON. A weather notice, a quest toast and a tip do not wait to
	     be asked, and none of them knows this feature exists. Watching `Enabled` on everything the
	     sweep is holding is what makes the hide actually hold: the write is taken as the screen
	     saying what it WANTS, which is recorded for the restore, and then put straight back to off.

	`_write` is what keeps that from being a loop, and the shape of it is not an accident. Every one
	of this file's own writes to `Enabled` goes through it and RECORDS THE VALUE IT WROTE, so the
	listener can tell "the game asked for this screen" from "this file just switched it off", which
	are otherwise the same event.

	IT USED TO BE A BOOLEAN RAISED ACROSS THE WRITE AND THAT DOES NOT WORK, which is worth spelling
	out because the code looked obviously correct for months. Roblox fires
	`GetPropertyChangedSignal` DEFERRED: the listener runs at the end of the resumption point, long
	after the line that lowered the flag. Measured in a playtest 2026-09-02 - the write returns and
	clears the guard, THEN the handler runs and reads it as false. So every screen the sweep switched
	off was recorded by its own listener as "this screen was already off", and the restore faithfully
	put it back off. Hide the UI, show it again, and the whole HUD was gone for the rest of the
	session with the topbar sitting over an empty screen.

	A recorded VALUE survives the deferred hop because it is compared against the property rather
	than against a moment in time.

	=== THE TOPBAR AND ROBLOX'S OWN UI ========================================================

	`SetCoreGuiEnabled` takes the chat, the player list and the backpack down. It is captured before
	it is written, for the same reason the ScreenGui sweep is: this game already switches parts of
	the core UI off in places (a race is the obvious one), and a restore that turned everything back
	on would be undoing a decision somebody else made.

	THE TOPBAR IS THE ONE THING THIS FILE DOES NOT SWEEP, and that is new. It used to call
	`Icon.setTopbarEnabled(false)` and put a pill of its own in the top right; now the way back IS a
	topbar button, so TopbarPlus's four ScreenGuis are in `InterfaceConfig.Keep` and the strip stays
	up. `_strip` below hands the job to `TopbarController`, which switches every icon except SHOW UI
	off and remembers what each one was. This file does not require TopbarPlus at all any more,
	which is what that controller's header asks of anything wanting a button in the strip.

	The Roblox menu button in the top left cannot be switched off by a game and stays up. That is
	the reason the chip is worth having where it is: that corner is already spoiled in every
	screenshot, so one more button in it costs nothing.

	=== THE WAY BACK =========================================================================

	Three of them, and the reasoning for having three is in `InterfaceConfig`'s header. The chip is
	the one that is always there; H restores on a keyboard; B restores on a controller and is bound
	only while hiding, so it is never competing with a panel for the button.

	NONE OF THE THREE HIDES. The settings row is the only control in the game that does, which is
	`InterfaceConfig`'s "NOTHING BUT THE SETTINGS ROW CAN HIDE" and the reason `toggle` is now
	`restore`. H used to toggle and an accidental press cleared the screen for a player who had
	never opened the setting and had no idea what had happened.

	B IS A SILENT BINDING, with no badge hanging off anything. `GamepadInput` would normally draw
	one under the control it belongs to, and under this one it would be cut off: TopbarPlus's `Left`
	holder clips its descendants, which is what keeps a widget inside the strip. So the glyph goes
	ON the chip instead, as its icon image, which `TopbarController` swaps in whenever a pad is the
	player's device.

	HOUSE RULE: no wiki-style double-bracket links in this comment, the closing pair ends the block
	comment early and the parse error points at the wrong line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local InterfaceConfig = require(ReplicatedStorage.shared.Configs.InterfaceConfig)
local GamepadInput = require(ReplicatedStorage.shared.Modules.GamepadInput)

local InterfaceController = Shard.new("InterfaceController")

--- The gamepad action name, and a priority above every panel's. See the header on why it is bound
--- only while hiding.
local PAD_RESTORE = "InterfaceRestore"
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 900

-- === The sweep ==============================================================

--- Every ScreenGui under `PlayerGui` that this feature is allowed to touch. The tab is skipped by
--- name, which is what keeps the way back on screen.
function InterfaceController._sweepable(self): { ScreenGui }
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return {}
	end
	local out = {}
	for _, inst in playerGui:GetDescendants() do
		if inst:IsA("ScreenGui") and not InterfaceConfig.Keep[inst.Name] then
			table.insert(out, inst)
		end
	end
	return out
end

--[[ Set `Enabled` and leave a note saying we were the ones who did it.

	THE NOTE IS THE VALUE, NOT A FLAG, and the header says why at length: the listener that reads it
	runs deferred, so anything that has to be true only "during" the write is already false by the
	time it is asked. A value written down is still there. ]]
function InterfaceController._write(self, gui: ScreenGui, enabled: boolean)
	if gui.Enabled == enabled then
		return -- no change, no signal, nothing to leave a note about
	end
	self._ours[gui] = enabled
	gui.Enabled = enabled
end

--- Switch one screen off and remember what it was.
function InterfaceController._hold(self, gui: ScreenGui)
	if self._held[gui] ~= nil then
		return
	end
	self._held[gui] = gui.Enabled

	--[[ The screen switching itself on while we are holding it. Taken as a statement of intent
		rather than refused: what it wanted is recorded for the restore, and the screen goes back
		off. A quest toast fired while the UI is away is therefore waiting when it comes back,
		which is the honest outcome.

		A screen switching itself OFF is recorded too, so a panel that finishes closing behind the
		hide is not put back open by the restore. Note the limit: it only lands if the write changes
		the value, and we already forced this screen to false, so a closer that assigns `false` to a
		screen that is already false fires nothing and the hold stays stale. The rule for callers is
		therefore to be genuinely closed BEFORE they ask to hide, not on the way. The settings page
		hides its own frame on the spot for exactly that. ]]
	self._connections[gui] = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		--- Our own write, arriving deferred. Consumed rather than only ignored, so the NEXT change
		--- to this screen is read as somebody else's however long it takes to arrive.
		if self._ours[gui] == gui.Enabled then
			self._ours[gui] = nil
			return
		end
		self._ours[gui] = nil

		if not self._hidden then
			return
		end
		if gui.Enabled then
			self._held[gui] = true
			self:_write(gui, false)
		else
			self._held[gui] = false
		end
	end)

	self:_write(gui, false)
end

--- Put one screen back to whatever it was when the sweep found it, and stop watching it.
function InterfaceController._release(self, gui: ScreenGui)
	local was = self._held[gui]
	self._held[gui] = nil

	local connection = self._connections[gui]
	if connection then
		connection:Disconnect()
		self._connections[gui] = nil
	end

	-- A screen destroyed while hidden (a respawn takes every `ResetOnSpawn` one with it) is simply
	-- dropped: there is nothing to put back and its replacement was never held.
	if was == nil or not gui.Parent then
		self._ours[gui] = nil
		return
	end
	self:_write(gui, was)
	--- The listener is already gone, so nothing will consume the note. Drop it here or it outlives
	--- the hold and swallows the first change of the NEXT one.
	self._ours[gui] = nil
end

--[[ Roblox's own UI, captured before it is written.

	PER TYPE RATHER THAN `All`, because `All` cannot be read back: `GetCoreGuiEnabled` answers for one
	type at a time, so restoring the arrangement this found means recording it one at a time too.
	This game switches parts of the core UI off elsewhere and a blanket re-enable would undo that. ]]
function InterfaceController._coreGui(self, hidden: boolean)
	if hidden then
		self._core = {}
		for _, item in Enum.CoreGuiType:GetEnumItems() do
			if item == Enum.CoreGuiType.All then
				continue
			end
			local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, item)
			if ok then
				self._core[item] = enabled
				pcall(StarterGui.SetCoreGuiEnabled, StarterGui, item, false)
			end
		end
		return
	end

	for item, enabled in self._core do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, item, enabled)
	end
	self._core = {}
end

-- === The way back ==========================================================

--[[ Hand the strip to `TopbarController`, which owns every icon in it including SHOW UI.

	ASKED FOR RATHER THAN DONE HERE, and the split is the one this game already makes everywhere
	else: the topbar is a shared strip with its own DPad negotiation, its own build order and its
	own rules about what a caption may say, and a second file reaching into it with TopbarPlus is
	how those rules quietly stop holding. So this says what it wants and that file decides how.

	A build with no topbar at all is a real case rather than a defensive one: `TopbarController`
	is a Shard like any other and nothing guarantees it is up. There is no way back to lose by
	carrying on without it, because the two bindings are bound either way, so this warns and
	continues rather than refusing to hide. ]]
function InterfaceController._strip(self, hidden: boolean)
	local topbar = Shard.get("TopbarController")
	if not topbar then
		self.log:warn("TopbarController is not up; the SHOW UI button cannot be raised.")
		return
	end
	topbar:setRestoreOnly(hidden)
end

-- === Answers ================================================================

--- Public (`UIController/Pages/Settings`): which answer is on.
function InterfaceController.visibility(self): string
	return if self._hidden then InterfaceConfig.Visibility.Hidden else InterfaceConfig.Visibility.Shown
end

--- Public: is the UI away? The same question, for anything that would rather ask than compare keys.
function InterfaceController.isHidden(self): boolean
	return self._hidden
end

--[[ Public (the settings page, the chip, both bindings): pick an answer.

	APPLIED HERE AND REPAINTED THROUGH THE STATE EVENT, never the other way round. That is the same
	one-way the sky setting makes and it is what stops the settings screen ever showing an answer the
	screen is not actually in. ]]
function InterfaceController.setVisibility(self, visibility: unknown)
	if not InterfaceConfig.Enabled then
		return
	end

	local key = InterfaceConfig.resolve(visibility)
	local hidden = key == InterfaceConfig.Visibility.Hidden
	if hidden == self._hidden then
		return
	end

	self._hidden = hidden

	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		playerGui:SetAttribute(InterfaceConfig.Attribute, hidden or nil)
	end

	if hidden then
		for _, gui in self:_sweepable() do
			self:_hold(gui)
		end

		--[[ Screens built after the sweep. `DescendantAdded` rather than `ChildAdded` because a
			ScreenGui is not obliged to be a direct child, and the filter costs nothing. ]]
		if playerGui then
			self._watch = playerGui.DescendantAdded:Connect(function(inst)
				if self._hidden and inst:IsA("ScreenGui") and not InterfaceConfig.Keep[inst.Name] then
					self:_hold(inst)
				end
			end)
		end

		self:_coreGui(true)
		self:_strip(true)
		self:_bindPad(true)
	else
		if self._watch then
			self._watch:Disconnect()
			self._watch = nil
		end
		--[[ Collected first and released after, because `_release` writes the table it would
			otherwise be iterating. ]]
		local held = {}
		for gui in self._held do
			table.insert(held, gui)
		end
		for _, gui in held do
			self:_release(gui)
		end

		self:_coreGui(false)
		self:_strip(false)
		self:_bindPad(false)
	end

	Dispatcher:Publish(InterfaceConfig.StateEvent, key)
end

--[[ H, and it goes ONE WAY. See `InterfaceConfig.RestoreKey`, and the section above it for the
	argument: this used to toggle, and a key that hides the whole game by accident costs more than
	the shortcut it was worth to the few people who meant to press it.

	The guard is what makes it one way rather than `setVisibility`'s own early return doing it.
	Same answer, and this one says so out loud on the line that reads it. ]]
function InterfaceController.restore(self)
	if not self._hidden then
		return
	end
	self:setVisibility(InterfaceConfig.Visibility.Shown)
end

--[[ B, bound only while the UI is away.

	SILENT: no parent, so `GamepadInput` binds the button and draws nothing. Everywhere else in this
	game the badge hangs off the control it presses, and here the control is a topbar widget inside
	a holder that clips its descendants, so a badge under it would simply be cut in half. The glyph
	rides on the chip itself instead, which `TopbarController` puts there for a pad player.

	Nothing else can be reached with the UI hidden, so this is never competing for the button. ]]
function InterfaceController._bindPad(self, on: boolean)
	if not on then
		GamepadInput.unbind(PAD_RESTORE)
		return
	end
	GamepadInput.bind({
		actionName = PAD_RESTORE,
		keyCode = InterfaceConfig.RestorePad,
		callback = function()
			self:setVisibility(InterfaceConfig.Visibility.Shown)
		end,
		priority = PAD_PRIORITY,
	})
end

--[[ A RUN TAKES THE UI BACK.

	Same argument as the one that closes the settings panel on `RaceStart`, and the same handler
	shape. Driving with no speedometer, no health bar and, on a phone, no steering is not a
	photograph. Photo mode is a lobby thing, and a race is the game moving the player somewhere this
	setting was never about. ]]
InterfaceController:withRemoteEvents({
	{
		RaceStart = function()
			InterfaceController:setVisibility(InterfaceConfig.Visibility.Shown)
		end,
	},
})

InterfaceController:withLifecycle({
	init = function(self)
		self._hidden = false
		--- What each held screen was when the sweep found it, and what the restore puts back.
		self._held = {} :: { [ScreenGui]: boolean }
		--- One `Enabled` listener per held screen. See `_hold`.
		self._connections = {} :: { [ScreenGui]: RBXScriptConnection }
		--- The value THIS file last wrote to each screen's `Enabled` and has not seen come back
		--- round yet. See `_write`, and the header for why it is a value and not a flag.
		self._ours = {} :: { [ScreenGui]: boolean }
		self._core = {} :: { [Enum.CoreGuiType]: boolean }
		self._watch = nil :: RBXScriptConnection?
	end,

	start = function(self)
		if not InterfaceConfig.Enabled then
			return
		end

		--[[ `gameProcessedEvent` is kept even though H can no longer hide anything. It costs a
			comparison and it is the difference between a key that does nothing while a player types
			their car's new name and one that fires under the rename box: Roblox raises the flag for
			any input a focused TextBox has already taken, and the day this key gains a second job is
			the day its absence would be a bug nobody looked for. ]]
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			if input.KeyCode == InterfaceConfig.RestoreKey then
				self:restore()
			end
		end)
	end,
})

return InterfaceController
