--[[
	DealershipController  (client)
	------------------------------
	The wire between a podium in the world and the Dealership page, in both directions. It owns no
	UI of its own — the page draws, this decides when the page is up and carries its clicks back.

	Every half exists for the same reason: a page module is not a Shard controller, so it has no
	remotes. Rather than give `Pages/Dealership` a remote handle and a second way to reach the
	server, everything crosses through `Dispatcher`:

	    podium prompt -> OpenDealership (remote) -> here -> DealershipBay + OpenPage -> the page
	    a card click  -> DealershipPick (event)  -> here -> RequestSetBayCar   (remote) -> the server
	    the star chip -> InventoryFlag (event)   -> here -> RequestSetCarFlag  (remote) -> the server
	    a hotbar move -> HotbarAction (event)    -> here -> RequestHotbar      (remote) -> the server

	The last one is the Cars Inventory's, and it comes through here rather than through a service of
	its own because it is the same screen talking to the same service — `GarageService` owns the
	collection, the lot and the flags.

	THERE WAS A THIRD LINE AND IT WAS THE SALE (`InventorySell` -> `RequestSellCars`). It went on
	2026-08-24 with the screen's sell mode: selling is a place you drive to now, `SellService` owns
	it, and the remote it used no longer exists on `GarageService` either. See `SellConfig`.

	WHY THE BAY IS PUBLISHED BEFORE THE PAGE OPENS RATHER THAN PASSED TO IT. `UIController` hands
	`data` to a page's own `Open`, and defining `Open` means taking over the scale tween that makes
	every page in this game feel like the same object. Publishing the bay first and opening second
	keeps the page on the shared tween and costs one event.

	IT IS ALSO WHAT PICKS THE PAGE'S MODE. That page is the Cars Inventory now and opens two ways —
	from a podium (this file) and from the car button on the HUD rail, which goes straight through
	the tag-driven `OpenPage` with no bay attached. `DealershipBay` arriving immediately before an
	open is the ONLY signal that tells the two apart, so this order is load-bearing rather than
	incidental; the page's `StartOpenThread` is the other half and its header note 2 has the rest.

	PRESSING A SECOND PODIUM WHILE THE PAGE IS UP RE-TARGETS IT INSTEAD OF CLOSING IT. `openPage`
	toggles — calling it on a page that is already visible is what makes a rail button close its own
	screen — so walking from bay 1 to bay 2 and pressing would otherwise shut the screen you were
	trying to move. Checked here rather than changed there, because that toggle is right for every
	other caller.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
--- For one flag: the dead-prompt trace (`GarageConfig.Picker.DebugPrompts`).
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
--- Which tutorial beat this player is on, for the beats that quiet the podiums (`QuietBays`).
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)

local PAGE_NAME = "Dealership"

local DealershipController = Shard.new("DealershipController")

function DealershipController._onOpen(self, bay: number)
	if type(bay) ~= "number" then
		return
	end

	-- Tell the page which bay first; it is what the page repaints against when it opens.
	Dispatcher:Publish("DealershipBay", bay)

	local UIController = Shard.get("UIController")
	local page = UIController and UIController.pages and UIController.pages[PAGE_NAME]
	if not page then
		self:_trace(string.format("OpenDealership bay %d: no %s page to open", bay, PAGE_NAME))
		return
	end

	-- Already up (a different podium): the bay above has re-targeted it, so leave it open.
	if page.PageUI and page.PageUI.Visible then
		self:_trace(string.format("OpenDealership bay %d: page already Visible, not reopened", bay))
		return
	end
	self:_trace(string.format("OpenDealership bay %d: opening the page", bay))
	Dispatcher:Publish("OpenPage", PAGE_NAME)
end

--[[ The client's half of `GarageService`'s `assemblyLine`, built the same way so the two lines can be
	read side by side: parts, how many anchored, the assembly's root and the tool held. A difference
	in either count between the two sides is the desync's cause. Pure. ]]
local function assemblyLine(root: BasePart): string
	local parts = root:GetConnectedParts(true)
	local anchored = 0
	for _, p in parts do
		if p.Anchored then
			anchored += 1
		end
	end
	local assemblyRoot = root.AssemblyRootPart
	local tool = root.Parent and root.Parent:FindFirstChildOfClass("Tool")
	return string.format(
		"%d parts (%d anchored), assemblyRoot=%s, tool=%s",
		#parts,
		anchored,
		if assemblyRoot then assemblyRoot:GetFullName() else "nil",
		if tool then tool.Name else "none"
	)
end

--- One of a podium's two prompts: E (the main one) or F (`GarageConfig.Picker.Option`).
local function isPodiumPrompt(prompt: ProximityPrompt): boolean
	return prompt.Name == "ChangeCarPrompt" or prompt.Name == GarageConfig.Picker.Option.Name
end

--- The local character's root, or nil between spawns.
local function localRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

--- One line of the dead-prompt trace (`GarageConfig.Picker.DebugPrompts`).
function DealershipController._trace(self, line: string)
	if GarageConfig.Picker.DebugPrompts then
		print("[PromptTrace] " .. line)
	end
end

--[[ THE CLIENT HALF OF THE DEAD-PROMPT TRACE (`GarageConfig.Picker.DebugPrompts`, 2026-09-28): which
	prompts the engine is drawing, and what happens to each E press. The engine draws ONE prompt per
	key, so a shown/hidden log says which prompt owned E at the moment the bay stopped answering, and
	the press log says whether the key ever reached a prompt at all (`gameProcessed` true with no
	TextBox focused is an input binding eating it). A diagnostic only; off with the flag. ]]
function DealershipController._tracePrompts(self)
	if not GarageConfig.Picker.DebugPrompts then
		return
	end
	local shown: { [ProximityPrompt]: boolean } = {}
	local function describe(prompt: ProximityPrompt): string
		return string.format("%s '%s' (%s)", prompt:GetFullName(), prompt.ActionText, prompt.KeyboardKeyCode.Name)
	end
	ProximityPromptService.PromptShown:Connect(function(prompt)
		shown[prompt] = true
		self:_trace("shown " .. describe(prompt))
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		shown[prompt] = nil
		self:_trace("hidden " .. describe(prompt))
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		self:_trace("TRIGGERED " .. describe(prompt))
		--- A podium's prompt: ask the server what it sees right now (`GarageService._probePrompt`),
		--- with where this client thinks the character is, so the two views land side by side.
		if isPodiumPrompt(prompt) then
			local root = localRoot()
			self:getRemoteEvent("PromptProbe"):Fire(prompt, if root then root.Position else nil, if root then assemblyLine(root) else nil)
		end
	end)
	--[[ The desync watch's heartbeat: where this client has the character, once a second, for
		`GarageService._watchDesync` to hold against its own copy. 1 Hz is plenty — the desync it is
		looking for lasts minutes — and it is one small remote a second, only while the flag is on. ]]
	task.spawn(function()
		while true do
			task.wait(1)
			local root = localRoot()
			if root then
				self:getRemoteEvent("DesyncProbe"):Fire(root.Position, assemblyLine(root))
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if input.KeyCode ~= Enum.KeyCode.E then
			return
		end
		local names = {}
		for prompt in shown do
			table.insert(names, describe(prompt))
		end
		local box = UserInputService:GetFocusedTextBox()
		self:_trace(string.format(
			"E pressed: gameProcessed=%s focusedTextBox=%s promptsEnabled=%s shown=[%s]",
			tostring(gameProcessed),
			if box then box:GetFullName() else "none",
			tostring(ProximityPromptService.Enabled),
			table.concat(names, "; ")
		))
	end)
end

DealershipController:withRemoteEvents({
	{
		OpenDealership = function(bay: number)
			DealershipController:_onOpen(bay)
		end,
		--- EQUIP BEST's answer, handed to the cars screen for its confirmation.
		EquipBestResult = function(changed: unknown, gain: unknown)
			Dispatcher:Publish("DealershipEquipBestResult", {
				changed = tonumber(changed) or 0,
				gain = tonumber(gain) or 0,
			})
		end,
	},
	"RequestSetBayCar",
	"RequestEquipBest", -- the cars screen's EQUIP BEST (`GarageService.equipBest`)
	"RequestSetCarFlag",
	"RequestHotbar",
	"BayPromptPressed", -- every podium press, for the desync heal (`GarageConfig.Picker.HealDesync`)
	"PromptProbe", -- the dead-prompt trace only (`GarageConfig.Picker.DebugPrompts`)
	"DesyncProbe", -- the same trace's once-a-second position check
})

DealershipController:withLifecycle({
	init = function(_self) end,

	start = function(self)
		self:_tracePrompts()

		--[[ OTHER PLAYERS' PODIUM PROMPTS, OFF ON THIS CLIENT (2026-10-08). With the plain prompt
			(`GarageConfig.Picker.Glass = false`) every podium in the server would otherwise offer you
			its E; the server refuses a press on a lot that is not yours anyway, but a prompt that does
			nothing is the worse experience. Local only: `Enabled` written here never replicates, and
			the server never writes it after it makes the prompt. ]]
		local picker = GarageConfig.Picker
		local player = Players.LocalPlayer
		--[[ ...AND THIS PLAYER'S OWN, WHILE A TUTORIAL BEAT SAYS `QuietBays` (2026-10-19). SELL's buyer
			stands beside the parked car, and walking up to them the car's own Pick Up (16 studs) showed
			before their See Offer (12): one E there lifted the car and withdrew the offer. Put back as
			the beat moves on. Same local-only write as above, so the server's copy is untouched. ]]
		local function quiet(): boolean
			local index = TutorialConfig.indexOf(player:GetAttribute(TutorialConfig.StepAttribute))
			local step = index and TutorialConfig.Steps[index]
			return step ~= nil and step.QuietBays == true
		end
		local function claim(prompt: Instance)
			if prompt:IsA("ProximityPrompt") then
				prompt.Enabled = prompt:GetAttribute(picker.OwnerAttribute) == player.UserId and not quiet()
			end
		end
		for _, prompt in CollectionService:GetTagged(picker.PromptTag) do
			claim(prompt)
		end
		CollectionService:GetInstanceAddedSignal(picker.PromptTag):Connect(claim)
		player:GetAttributeChangedSignal(TutorialConfig.StepAttribute):Connect(function()
			for _, prompt in CollectionService:GetTagged(picker.PromptTag) do
				claim(prompt)
			end
		end)

		--[[ EVERY PODIUM PRESS, with where this client has the character (2026-09-30). Not a
			diagnostic: the server needs the client's side of a press its frozen copy never received,
			to heal the desync (`GarageService._onBayPromptPressed`). An ordinary press also arrives
			through the prompt itself and the server ignores this one. ]]
		ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
			if not isPodiumPrompt(prompt) then
				return
			end
			local root = localRoot()
			if root then
				self:getRemoteEvent("BayPromptPressed"):Fire(prompt, root.Position)
			end
		end)

		-- A CAR KEY ("Sedan12:6") or nil for "leave empty" — never a bare body name. A player can own
		-- the same body in several colours, so the server has to be told which one. See
		-- `GarageConfig.carKey` and `GarageService.setBayCar`.
		--- EQUIP BEST off the cars screen; the server decides which cars and which bays.
		Dispatcher:Subscribe("DealershipEquipBest", function()
			self:getRemoteEvent("RequestEquipBest"):Fire()
		end)
		Dispatcher:Subscribe("DealershipPick", function(bay: number, key: string?)
			if type(bay) ~= "number" then
				return
			end
			self:getRemoteEvent("RequestSetBayCar"):Fire(bay, key)
		end)

		--[[ Star or unstar one car. `flag` is one of `InventoryConfig.Keys` and is passed straight
			through — the server checks it against its own table rather than trusting the name, so
			there is nothing for this side to validate that would not be validated again anyway. It is
			worth one name and not two: the lock went on 2026-08-24, and the shape kept for exactly the
			day a second flag came back — which it did on 2026-09-28, as `NotForSale`, with no new wire. ]]
		Dispatcher:Subscribe("InventoryFlag", function(key: string, flag: string, on: boolean)
			if type(key) ~= "string" or type(flag) ~= "string" then
				return
			end
			self:getRemoteEvent("RequestSetCarFlag"):Fire(key, flag, on == true)
		end)

		--[[ One hotbar move (2026-09-30): "toggle" (hold / put back), "toInventory" or "toHotbar", on
			one car ID. From the hotbar (`CarryHotbarController`) and the inventory's TO HOTBAR button.
			The server decides whether the car is where the move needs it (`GarageService.hotbarAction`),
			so this passes it on and stops, like every other wire in this file. ]]
		Dispatcher:Subscribe("HotbarAction", function(action: string, id: string)
			if type(action) ~= "string" or type(id) ~= "string" then
				return
			end
			self:getRemoteEvent("RequestHotbar"):Fire(action, id)
		end)
	end,
})

return DealershipController
