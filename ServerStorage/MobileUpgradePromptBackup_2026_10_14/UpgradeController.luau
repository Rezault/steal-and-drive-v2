--[[
	UpgradeController  (client)
	---------------------------
	Every UPGRADE button a player can press: the four on the billboard standing on your forecourt,
	and the one on each podium's CASH PER SECOND kiosk. It owns no layout and writes no text — the
	server draws both boards for everybody (`UpgradeService` the billboard, `GarageService` the
	kiosks) — this only turns a click into a remote and gives the button something to feel like on
	the way.

	THE TWO BOARDS ARE BOUND THE SAME WAY AND SEND DIFFERENT THINGS. A billboard tile sends its
	UPGRADE KEY, because which of the four it is, is all the server needs. A kiosk sends its SLOT
	MODEL, because a bay number would be ambiguous across six lots — see the remote's own note in
	`UpgradeService`. Everything else below is shared.

	THREE THINGS WORTH KNOWING.

	1. IT BINDS EVERY BOARD IN THE MAP, NOT JUST YOURS, AND IT BINDS THEM BY TAG. There are six plots,
	   the boards are ordinary Workspace SurfaceGuis, and which one is yours changes when a plot is
	   assigned — so binding all six and letting the server refuse the five that are not yours is far
	   less machinery than watching an attribute to re-bind, and it is the same answer either way: the
	   button fires the remote, the server checks who owns the lot. A hidden button is not access
	   control, and neither is an unbound one.

	   THE TAG IS NOT A STYLE CHOICE. `StreamingEnabled` is on, so a plot across the island has no
	   board in this client's DataModel at boot and gains one when the player walks over. The first
	   version of this file walked `Map.Plots` once in `start`, found nothing, and warned that the
	   build command had never been run — on a map where all six boards existed. `observeTag` binds
	   each one as it arrives and drops it again when it streams out.

	2. THE PRESS IS PURELY LOCAL AND DELIBERATELY DOES NOT PREDICT. Nothing here repaints a price, a
	   level or a bar. The board redraws when the server has actually taken the money, so a press
	   that fails (not your lot, already maxed) changes nothing rather than flashing a level you did
	   not buy. Same rule the teleport screen follows: nothing repaints optimistically.

	   AND IT DOES NOT CHECK THE PRICE EITHER, which is what makes the cash pack offer possible. A
	   press the player cannot afford is a real press: the remote fires, and `UpgradeService` answers
	   it by opening Roblox's window on the cheapest pack that closes the gap (`CashConfig`). A
	   client that refused locally would be a client deciding a thing the server has to decide again
	   anyway, and it would silently delete that offer.

	3. A SURFACEGUI ONLY TAKES INPUT WHILE IT IS `Active`. That is set by the command that authors
	   the board, not here, and it is the single property that decides whether any of this runs. If
	   the buttons are dead in a playtest, check that first — the symptom is identical to an unbound
	   controller.

	=== AND THE UPGRADES MACHINE — 2026-10-14 ===
	The board's kit face moved into a ScreenGui page (`PagesV2/Upgrades`), opened from a prompt on
	each plot's `Upgrades` cabinet. `_bindMachine` turns that prompt on for the owner only
	(`UpgradeConfig.Machine` has why that is presentation and not security), and `requestUpgrade`
	is the page's way onto the same remote a billboard tile fires.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Players = game:GetService("Players")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Observers = require(ReplicatedStorage.Packages.Observers)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
-- For the `CarSlot` tag alone: the kiosks are children of the podiums, so the map's existing tag is
-- how they are found and they need none of their own. See `UpgradeConfig.Bay`.
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
--- Which podium's board is the workshop's sign, the one bound with the per-bay ladder off.
local CustomizeConfig = require(ReplicatedStorage.shared.Configs.CustomizeConfig)
local NewUIConfig = require(ReplicatedStorage.shared.Configs.NewUIConfig)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
--- The plot owner attribute, which is what says whose cabinet a prompt is on (`_bindMachine`).
local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)
--- The tutorial's step, which keeps the Upgrades prompt off until it is over (`_bindMachine`).
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

--[[ The press, and the whole of the local feedback: the button shrinks and comes back.

	GEOMETRIC, NOT A COLOUR CHANGE, because colour on this button already MEANS something. The server
	paints it orange while there is a level to buy and green when the ladder is finished, and a press
	that recoloured it would be overwriting the one piece of state the board is trying to tell you.
	The kit's own pill does exactly this: `UIAssets.Pill` notes that its pressed state is purely
	geometric for the same reason.

	Kept small and short per the house note on effect intensity — this is a button, not a payoff. ]]
local PRESS_SCALE = 0.94
local PRESS_TIME = 0.07

--[[ The hover: the billboard's UPGRADE buttons swell a little under the cursor, the way every tagged
	screen button does. The same numbers and the same channel as `Components/Button` (1.05, 0.2s Back
	out, a `UIScale` named `HoverScale`), so a world button and a screen button feel alike.

	NOT THE `UIButton` TAG ITSELF. That component opens pages, plays the UI sounds and forces
	`Selectable`, all of which is screen UI; the build command strips the tag off the kit's button for
	that reason. Only the nudge is borrowed.

	A `UIScale` RATHER THAN `Size`, and that is what lets it stack with the press above. The press
	tweens `Size` down and back to the size recorded at bind; a hover written to `Size` as well would
	be undone by every press that finished under the cursor. A `UIScale` multiplies whatever `Size`
	says, so the two never touch the same number. ]]
local HOVER_SCALE = 1.05
local HOVER_SCALE_NAME = "HoverScale"
local HOVER_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--[[ How long any hop down to a button is prepared to wait for the instance under it.

	ONE NUMBER FOR BOTH BOARDS, because they are waiting on the same thing — replication — and a
	billboard is not more or less patient than a kiosk. Generous, because the cost of being wrong in
	each direction is not symmetric: waiting too long costs a parked thread that the plate leaving
	the DataModel ends anyway, while not waiting at all is a dead button for the rest of the session.
	It exists at all only to stop a board authored without its screen parking a thread forever. ]]
local WAIT = 20

local UpgradeController = Shard.new("UpgradeController")

UpgradeController:withRemoteEvents({ "RequestUpgrade", "RequestBayUpgrade" })

function UpgradeController._press(self, button: GuiButton)
	local full = self._sizes[button]
	if not full then
		return
	end

	local down = UDim2.new(
		full.X.Scale * PRESS_SCALE,
		full.X.Offset * PRESS_SCALE,
		full.Y.Scale * PRESS_SCALE,
		full.Y.Offset * PRESS_SCALE
	)
	local info = TweenInfo.new(PRESS_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(button, info, { Size = down }):Play()
	task.delay(PRESS_TIME, function()
		if button.Parent then
			TweenService:Create(button, info, { Size = full }):Play()
		end
	end)
end

--[[ Give one board button the hover nudge. Returns its connections; the caller disconnects them and
	calls `_settle` when the board is unbound.

	`SelectionGained` / `SelectionLost` ride along with the mouse pair for the reason
	`Components/Button` gives: a highlight that lands on a button and a cursor that lands on it are
	the same news. ]]
function UpgradeController._hoverable(self, button: GuiButton): { RBXScriptConnection }
	local scale = button:FindFirstChild(HOVER_SCALE_NAME)
	if not (scale and scale:IsA("UIScale")) then
		--[[ Only one `UIScale` on an instance takes effect, so a button already carrying one under
			another name belongs to whoever put it there. Nothing on either face does today; stand
			down rather than fight it. ]]
		if button:FindFirstChildOfClass("UIScale") then
			return {}
		end
		scale = Instance.new("UIScale")
		scale.Name = HOVER_SCALE_NAME
		scale.Parent = button
	end

	local function nudge(factor: number)
		TweenService:Create(scale, HOVER_TWEEN, { Scale = factor }):Play()
	end

	return {
		button.MouseEnter:Connect(function()
			nudge(HOVER_SCALE)
		end),
		button.MouseLeave:Connect(function()
			nudge(1)
		end),
		button.SelectionGained:Connect(function()
			nudge(HOVER_SCALE)
		end),
		button.SelectionLost:Connect(function()
			nudge(1)
		end),
	}
end

--- Put a button's hover back to rest, for a board that is unbound while the cursor is still on it.
function UpgradeController._settle(self, button: GuiButton)
	local scale = button:FindFirstChild(HOVER_SCALE_NAME)
	if scale and scale:IsA("UIScale") then
		scale.Scale = 1
	end
end

--[[ Wire one tile's button. Returns its connections and the button, so the board can be unbound
	when it streams out.

	The tile carries WHICH upgrade it is as an attribute (`UpgradeConfig.Board.KeyAttribute`), which
	is what lets one handler serve all four and lets the artist reorder the grid in the Explorer
	without a code change — the same inversion the tag-driven `UIController` makes for pages.

	THE KEY IS READ FIRST AND THE BUTTON IS WAITED FOR SECOND, and that order is the whole point.
	The attribute arrives WITH the tile, so it can be trusted immediately and is what tells us this
	is a tile worth waiting on at all; the button is a child, so over the wire it can be a moment
	behind. Testing the key first is what stops a stray non-tile child parking a thread for the full
	timeout. See `_bindBoard` for what this is protecting against. ]]
function UpgradeController._bindTile(self, tile: Instance): ({ RBXScriptConnection }?, GuiButton?)
	local names = UpgradeConfig.Board
	local key = tile:GetAttribute(names.KeyAttribute)
	-- `isOnBoard` rather than `isKey`, so a tile left over from the old four-up board is not wired to
	-- a press the server will refuse anyway. See `UpgradeConfig.isOnBoard`.
	if not UpgradeConfig.isOnBoard(key) then
		return nil, nil
	end
	local button = tile:WaitForChild(names.ButtonName, WAIT)
	if not (button and button:IsA("GuiButton")) then
		return nil, nil
	end

	--[[ The authored size is recorded ONCE, at bind, and never re-read. Reading it at press time
		would capture whatever the last tween left behind if two presses overlap, and the button
		would walk itself smaller with every click. ]]
	self._sizes[button] = button.Size

	local connections = self:_hoverable(button)
	table.insert(
		connections,
		button.Activated:Connect(function()
			self:_press(button)
			self:getRemoteEvent("RequestUpgrade"):Fire(key)
		end)
	)
	return connections, button
end

--[[ One tagged screen plate has arrived. Bind its four buttons and hand back the undo.

	=== IT WAITS, AND IT DID NOT USE TO — THIS IS THE "CAN'T BUY AN UPGRADE AFTER A ROUND" BUG =====

	The old version walked `screen → UpgradeGui → Panel → Grid` with `FindFirstChild` on the
	reasoning that "a plate is tagged by the build command only AFTER its screen is drawn, so
	anything this observer sees is already complete." That is true in the PLACE FILE and false over
	the wire, which is the only place it matters: `StreamingEnabled` is on, the tag arrives with the
	plate, and A PLATE ARRIVES BEFORE ITS DESCENDANTS DO — the same fact `_bindKiosk` below has a
	whole essay about. So the walk found nothing, warned about a build command that had been run
	perfectly well, and — the part that made it a player-facing bug — NEVER RETRIED. The grid landing
	a moment later fired nothing, and the board stayed dead for the rest of the session.

	Which made it a bug you could only hit AFTER A RACE. At boot the lobby is already streamed in, so
	the first bind is against a complete subtree and every button works. Then a race puts the player
	a lane-storey and a world away, their lot streams out, `observeTag` correctly unbinds it, and the
	journey home streams it back in cold — this time with the plate ahead of its screen. Reproduced
	deterministically by untagging a board, hiding its `Grid`, and re-tagging: bound tiles went
	72 → 68 → 68, and stayed at 68 a full second after the grid came back. The kiosk path, which
	already waited, ran the identical test at 68 → 67 → 68 and recovered.

	=== AND THE TILES ARE WATCHED, NOT SNAPSHOTTED ================================================

	Waiting for the grid is not enough on its own. The grid is one instance and the four tiles are
	four more, so a grid that has arrived can still be empty or half full. `ChildAdded` covers the
	rest of the replication for as long as the board is bound, which also means no assumption is made
	about how many tiles there are or what they are called — a fifth upgrade authored into the grid
	binds itself. ]]
function UpgradeController._bindBoard(self, screen: Instance): (() -> ())?
	local names = UpgradeConfig.Board

	-- Each hop re-checks the plate is still in the DataModel, so a board that streams out mid-wait
	-- does not keep a thread alive for the full timeout on every hop it has left. Same shape and
	-- same reason as `_bindKiosk`'s.
	local function step(parent: Instance?, name: string): Instance?
		if not (parent and screen:IsDescendantOf(game)) then
			return nil
		end
		return parent:WaitForChild(name, WAIT)
	end

	local connections = {}
	local buttons: { GuiButton } = {}

	--[[ WHICH FACE THIS PLAYER SEES (2026-09-17). The plate carries two SurfaceGuis on one face, the
		classic board and the kit one, and the server keeps both drawn. Showing one is a local
		`Enabled` write, so it never replicates and each player gets the face that matches their own
		UI. The classic face is authored enabled and the kit face disabled, so a board this never
		reaches still shows something.

		The kit face goes up only once it has actually arrived. Hiding the classic one on the strength
		of a kit face that is still on the wire, or that a board built before it existed will never
		have, would blank the sign. Watched on `ChildAdded` rather than checked once for the reason
		the header of this function gives: the plate lands before its descendants. ]]
	local wantKit = UIRoot.isNewUI() and NewUIConfig.KitUpgradeBoards == true
	local function showFace()
		local kitGui = screen:FindFirstChild(names.KitGuiName)
		local classicGui = screen:FindFirstChild(names.GuiName)
		local showKit = wantKit and kitGui ~= nil and kitGui:IsA("SurfaceGui")
		if kitGui and kitGui:IsA("SurfaceGui") then
			kitGui.Enabled = showKit
		end
		if classicGui and classicGui:IsA("SurfaceGui") then
			classicGui.Enabled = not showKit
		end
	end
	showFace()
	table.insert(connections, screen.ChildAdded:Connect(showFace))

	-- Only the face on show is bound: a disabled SurfaceGui takes no input, so wiring the other is
	-- four connections that can never fire. A kit face that never turns up falls back to the classic.
	local gui = if wantKit then step(screen, names.KitGuiName) else nil
	if not gui then
		gui = step(screen, names.GuiName)
	end
	local panel = step(gui, names.PanelName)
	local grid = step(panel, names.GridName)
	if not grid then
		for _, connection in connections do
			connection:Disconnect()
		end
		warn(string.format("[UpgradeController] %s has no upgrade grid — re-run BuildPlotUpgradeSigns.", screen:GetFullName()))
		return nil
	end

	--[[ `done` is what makes waiting safe to combine with an undo, and it is not belt-and-braces.
		Each tile waits in its own thread, so the board can stream out — and be cleaned up — while
		one of them is still waiting. That tile then arrives to a binding nobody is holding the
		undo for: a live connection that never gets disconnected, and a second one on top of it the
		next time the board streams in, i.e. one press firing the remote twice. So a late arrival
		checks whether the undo has already run, and unbinds itself if it has. ]]
	local done = false

	local function bind(tile: Instance)
		local tileConnections, button = self:_bindTile(tile)
		if not (tileConnections and button) then
			return
		end
		if done then
			for _, connection in tileConnections do
				connection:Disconnect()
			end
			self._sizes[button] = nil
			return
		end
		for _, connection in tileConnections do
			table.insert(connections, connection)
		end
		table.insert(buttons, button)
	end

	for _, tile in grid:GetChildren() do
		task.spawn(bind, tile) -- `_bindTile` waits, and four tiles must not wait in series
	end
	table.insert(connections, grid.ChildAdded:Connect(bind))

	return function()
		done = true
		for _, connection in connections do
			connection:Disconnect()
		end
		--[[ Drop the recorded sizes with the buttons, so a board that streams in and out repeatedly
			does not grow this table for the length of the session. Tracked as the buttons we
			actually bound rather than re-walked from the grid at cleanup time: a tile removed in
			between would otherwise leave its entry behind forever, and by cleanup the grid may be
			half-way out of the DataModel anyway. ]]
		for _, button in buttons do
			self._sizes[button] = nil
			-- A board rebound onto the other face would otherwise leave this one swollen.
			self:_settle(button)
		end
	end
end

--[[ One podium has arrived. Bind its CASH PER SECOND kiosk and hand back the undo.

	REACHED THROUGH THE `CarSlot` TAG THE MAP ALREADY CARRIES, rather than a tag of its own. The kiosk
	is a child of the podium, so it cannot go missing separately from the podium it stands on, and it
	is one fewer thing for a build command to remember to tag.

	=== IT WAITS, AND THE FIRST VERSION OF THIS DID NOT ==========================================

	`StreamingEnabled` is on, and A MODEL ARRIVES BEFORE ITS DESCENDANTS DO. The tag fires the instant
	the `CarSlot` Model is added, and at that instant the five-deep path down to the button — Upgrade,
	UpgradeBoard, UpgradeGui, Panel, UpgradeButton — is very often not there yet. The first version
	walked it with `FindFirstChild`, got nil on every one of the 48 podiums, and bound nothing at all;
	the symptom was a kiosk whose button did nothing, in a session where re-running the identical code
	by hand a minute later bound all 48. It is the same class of bug as the race car's HitBox arriving
	late, and it is invisible in edit mode, where everything is always already there.

	So every hop is a `WaitForChild` with a timeout rather than a lookup. Yielding here is safe:
	`observeTag` runs this callback in its own deferred thread and copes with the instance going away
	mid-callback — it calls the cleanup we return the moment it gets it. The timeout is what stops a
	podium authored without a kiosk from parking a thread forever.

	Every slot on the island is bound, not only the six on your own lot, for the reason note 1 gives
	for the billboards: which lot is yours changes, a hidden button is not access control, and the
	server refuses a press on a plot you do not hold. ]]
function UpgradeController._bindKiosk(self, slot: Instance): (() -> ())?
	local names = UpgradeConfig.Bay

	--[[ With the ladder off, only the workshop's board still stands (`GarageService._kioskFor`
		destroys the rest), so only it is waited for — otherwise every other podium on the island would
		park a thread for the full `WAIT` looking for a board that is never coming. ]]
	if not names.Enabled and slot:GetAttribute(GarageConfig.SlotIndexAttribute) ~= CustomizeConfig.Bay.SlotIndex then
		return nil
	end

	--[[ Each hop re-checks that the slot is still in the DataModel. Without it, a podium that streams
		out while this is waiting keeps the thread alive for the full timeout on every hop left. ]]
	local function step(parent: Instance?, name: string): Instance?
		if not (parent and slot:IsDescendantOf(game)) then
			return nil
		end
		return parent:WaitForChild(name, WAIT)
	end

	local model = step(slot, names.ModelName)
	local board = step(model, names.BoardName)
	if not board then
		return nil
	end

	local connections = {}

	--[[ THE WORKSHOP SIGN HAS TWO FACES (2026-09-30), the classic plaque and the kit one
		(`BuildWorkshopSign`), front and back each, and which pair shows is a local `Enabled` write,
		exactly as `_bindBoard` does the billboard: it never replicates, and a kit face that has not
		arrived (or a board built before it) leaves the plaque up rather than a blank. Unlike the
		billboard, the KIT face is the authored one here (`BuildWorkshopSign`), so this is what turns
		the plaque back on for the old UI. ]]
	local sign = CustomizeConfig.Kiosk
	local isWorkshop = slot:GetAttribute(GarageConfig.SlotIndexAttribute) == CustomizeConfig.Bay.SlotIndex
	local wantKit = isWorkshop and UIRoot.isNewUI() and NewUIConfig.KitWorkshopSign == true
	if isWorkshop then
		local function showFace()
			for _, pair in { { names.GuiName, sign.KitGuiName }, { "BackPlate", sign.KitBackName } } do
				local classicGui = board:FindFirstChild(pair[1])
				local kitGui = board:FindFirstChild(pair[2])
				local showKit = wantKit and kitGui ~= nil and kitGui:IsA("SurfaceGui")
				if kitGui and kitGui:IsA("SurfaceGui") then
					kitGui.Enabled = showKit
				end
				if classicGui and classicGui:IsA("SurfaceGui") then
					classicGui.Enabled = not showKit
				end
			end
		end
		showFace()
		table.insert(connections, board.ChildAdded:Connect(showFace))
	end

	local function unbind()
		for _, connection in connections do
			connection:Disconnect()
		end
	end

	-- Only the face on show is bound; a kit face that never turns up falls back to the plaque.
	local gui = if wantKit then step(board, sign.KitGuiName) else nil
	if not gui then
		gui = step(board, names.GuiName)
	end
	local panel = step(gui, names.PanelName)
	local button = step(panel, names.ButtonName)
	if not (button and button:IsA("GuiButton")) then
		unbind()
		return nil
	end

	-- Recorded once at bind and never re-read, the same rule and the same reason as `_bindTile`.
	self._sizes[button] = button.Size

	table.insert(
		connections,
		button.Activated:Connect(function()
			self:_press(button)
			self:getRemoteEvent("RequestBayUpgrade"):Fire(slot)
		end)
	)

	--[[ On the kit face the hover lifts the green button, not the face: the face fills the board, and
		grown by the billboard's 1.05 its rim would run off the canvas and be cut. The face is still
		what takes the press, so the nudge is driven by its events. ]]
	local lift: UIScale? = nil
	local go = if gui.Name == sign.KitGuiName then button:FindFirstChild(sign.KitButtonName, true) else nil
	if go and go:IsA("GuiObject") then
		local scale = go:FindFirstChild(HOVER_SCALE_NAME)
		if not (scale and scale:IsA("UIScale")) then
			scale = Instance.new("UIScale")
			scale.Name = HOVER_SCALE_NAME
			scale.Parent = go
		end
		lift = scale
		local function nudge(factor: number)
			TweenService:Create(scale, HOVER_TWEEN, { Scale = factor }):Play()
		end
		for _, pair in { { button.MouseEnter, HOVER_SCALE }, { button.MouseLeave, 1 }, { button.SelectionGained, HOVER_SCALE }, { button.SelectionLost, 1 } } do
			local signal: RBXScriptSignal, factor: number = pair[1], pair[2]
			table.insert(connections, signal:Connect(function()
				nudge(factor)
			end))
		end
	end

	return function()
		unbind()
		self._sizes[button] = nil
		-- A sign unbound with the cursor on it would otherwise come back with its button swollen.
		if lift then
			lift.Scale = 1
		end
	end
end

--[[ PUBLIC (`PagesV2/Upgrades`): a tile on the Upgrades page was pressed. The same remote and the
	same "do not predict" rule as a billboard tile (header note 2); the page redraws off the
	replicated levels once the server has actually taken the money. ]]
function UpgradeController.requestUpgrade(self, key: string)
	self:getRemoteEvent("RequestUpgrade"):Fire(key)
end

--[[ One Upgrades prompt has streamed in (`UpgradeConfig.Machine`). On only on a plot this player
	owns, re-checked whenever that plot's owner changes; pressed, it opens the page. The plot is the
	nearest ancestor carrying the owner attribute, which `PlotService` stamps on the model it hands
	out. A prompt with no such ancestor stays off. ]]
function UpgradeController._bindMachine(self, prompt: Instance): (() -> ())?
	if not prompt:IsA("ProximityPrompt") then
		return nil
	end
	local plot = prompt.Parent
	while plot and plot:GetAttribute(PlotConfig.OwnerUserIdAttribute) == nil and plot ~= workspace do
		plot = plot.Parent
	end
	local player = Players.LocalPlayer
	--[[ Off for the whole tutorial too (2026-10-14, the owner): the onboarding walks a first-timer
		through stealing and banking, and an upgrade screen opened mid-lesson is a detour it never
		mentions. Re-checked as the tutorial's step moves, so it lights up the moment it ends. ]]
	local function inTutorial(): boolean
		return TutorialConfig.isUnfinished(player:GetAttribute(TutorialConfig.StepAttribute))
	end
	--- And not under the NEW BEST cutscene (2026-10-14: it showed through it, over the stage).
	local showcasing = false
	local function refresh()
		prompt.Enabled = plot ~= nil
			and plot:GetAttribute(PlotConfig.OwnerUserIdAttribute) == player.UserId
			and not inTutorial()
			and not showcasing
	end
	refresh()
	local connections = {
		prompt.Triggered:Connect(function()
			if not inTutorial() then
				Dispatcher:Publish("OpenPage", UpgradeConfig.Machine.PageName)
			end
		end),
		player:GetAttributeChangedSignal(TutorialConfig.StepAttribute):Connect(refresh),
	}
	local started = Dispatcher:Subscribe("ShowcaseStarted", function()
		showcasing = true
		refresh()
	end)
	local ended = Dispatcher:Subscribe("ShowcaseEnded", function()
		showcasing = false
		refresh()
	end)
	if plot and plot ~= workspace then
		table.insert(connections, plot:GetAttributeChangedSignal(PlotConfig.OwnerUserIdAttribute):Connect(refresh))
	end
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		started() -- `Dispatcher:Subscribe` hands back its own unsubscribe
		ended()
	end
end

UpgradeController:withLifecycle({
	init = function(self)
		self._trove = Trove.new()
		self._sizes = {} :: { [GuiButton]: UDim2 }
	end,

	--[[ Bound in `start` and not `init` for the reason every module in this project is: `init` may
		not yield and this reaches into Workspace. `observeTag` then makes the timing a non-question —
		it fires for boards that are already there and for every one that arrives later. ]]
	start = function(self)
		if not UpgradeConfig.Enabled then
			return
		end
		--- With the machine on, the billboard faces stay off (`UpgradeService` switches them off, and
		--- `_bindBoard` would switch one back on locally), so they are not bound at all.
		if not UpgradeConfig.Machine.Enabled then
			self._trove:Add(Observers.observeTag(UpgradeConfig.Board.Tag, function(screen: Instance)
				return self:_bindBoard(screen)
			end, { workspace }))
		end
		if UpgradeConfig.Machine.Enabled then
			self._trove:Add(Observers.observeTag(UpgradeConfig.Machine.PromptTag, function(prompt: Instance)
				return self:_bindMachine(prompt)
			end, { workspace }))
		end

		--- The workshop's board is bound even with the ladder off, because it is the workshop's sign
		--- and not an upgrade (`CustomizeConfig.Kiosk`); `_bindKiosk` skips every other board then.
		if UpgradeConfig.Bay.Enabled or CustomizeConfig.Enabled then
			self._trove:Add(Observers.observeTag(GarageConfig.SlotTag, function(slot: Instance)
				return self:_bindKiosk(slot)
			end, { workspace }))
		end
	end,
})

UpgradeController:withCleanup(function()
	if UpgradeController._trove then
		UpgradeController._trove:Destroy()
	end
end)

return UpgradeController
