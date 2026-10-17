--[[
	Dealership page, V2 - THE CARS INVENTORY  (client)
	--------------------------------------------------
	"Everything I own, and one press that does something with it." The Cartoony Kit's inventory: a
	four-column grid of cards, each a real picture of the car in the colour you own it in, with a
	rarity over it, its name under it and a button that puts it in the street or parks it on a bay.

	It is the HUD's `Cars` cell, the one button in the new grid wearing our own art (`BuildHudV2`).

	`BuildDealershipV2` (Command Runner) cloned the kit's `InventoryUI` into
	`MainUIV2.Pages.Dealership`, dropped the two top-bar actions nothing is behind, and added the
	favourite star and the active rim. Its header carries every decision about the SHAPE of this
	screen; this file is the behaviour.

	=== THE FOUR RULES THE SHIPPING PAGE HAS, UNCHANGED =======================================

	1. IT HAS TWO MODES AND THE WAY IT WAS OPENED PICKS ONE.

	       podium prompt -> DealershipBay(n) -> OpenPage   = BAY MODE, "which car stands here"
	       the HUD's Cars ->                    OpenPage   = INVENTORY MODE, "my cars"

	   `setBay` ARMS the bay and the open consumes it, so the page never has to ask which bay you
	   meant and can never be wrong about it. An open that was NOT preceded by a bay is a HUD open,
	   and the armed flag is the only thing that can tell them apart.

	2. NOTHING HERE DECIDES ANYTHING. Every press publishes an event and stops. The server owns
	   whether you own that car, whether that is a real bay and whether a flag may be flipped. This
	   page does not optimistically repaint either: the attribute write comes back a frame later and
	   repaints it for real, which is one code path instead of two and cannot disagree with the
	   podium behind the panel.

	   THE ONE THING A PRESS DOES ON ITS OWN is close this screen when it spawned a car, because the
	   car arrives in the street BEHIND it (Dylan, 2026-09-19). That is a statement about the PANEL
	   and not about the car: nothing here is assuming the spawn worked, and a request the server
	   refuses closes the page just the same, leaving the street exactly as it was.

	3. FIVE PLAYER ATTRIBUTES FEED IT AND NOT ONE REMOTE DOES. Owned, Lot, Levels, Favorites and the
	   lobby car. Two of them change the CARDS and rebuild; three change what a card SAYS and only
	   repaint. See `_watchState`.

	   EVERY ENTRY IN THE FIRST FOUR IS A CAR KEY, body AND colour ("Sedan12:6"). A player can own
	   the same body in several colours and they are different cars, so one card is one KEY and
	   nothing here may key off the body alone. The one exception is LEVEL, which is per BODY
	   because XP is.

	4. THE CARS ON THE CARDS ARE A VIRTUALISED LIST and `Modules/CarViewportGrid` is the whole of it.
	   Each is a real 25-mesh model, so a collection of forty drawn at once is a thousand meshes
	   behind a panel showing ten. This page's half is two calls: the geometry, which `KitPage` works
	   out, and the cards that are showing, in the order the grid lays them out.

	=== WHAT THE KIT TOOK OVER ===============================================================

	Most of the shipping page's length, which was layout and an entrance:

	  • THE GRID. `KitPage` reads the kit's `UIGridLayout`, counts the columns off the authored
	    fractions and owns the canvas, so `_buildGrid`, `_applyLayout` and `CARD_ASPECT` are gone.
	    The cells are pinned to the window's pixels (`KitPage.pinGridToWindow`): a cell's HEIGHT in
	    scale resolves against the canvas, so past two rows of cars every card drew taller than the
	    window and the cars landed in the wrong cards. It does not run away the way the old list did,
	    because the canvas is computed from the window; it just sits wrong.
	  • THE COLUMN AND THE `Done` BUTTON. The shipping page is a full-height column down the right of
	    the screen with a `Done` pill at the bottom centre, standing exactly where `Play` stands, and
	    an entrance sequence spread across two files to hand one over to the other. This is a centred
	    kit panel with the kit's own X in its header, so `_slideColumn`, `_slideDone`,
	    `SuppressPlayButton` and the paired timings all go, and the page opens on the same tween
	    every other V2 page opens on.
	  • THE CARD'S FURNITURE. The old card is a blank slab that had a level chip, a status line, a
	    star, a flash and two flag marks built onto it in code. The kit draws a rarity, a name, a
	    picture and a two-state button.

	=== THE NUMBERS ARE A PANEL NOW, NOT A TOOLTIP ===========================================

	The shipping page follows the pointer with the car's tier, level, rate and four stat bars, and
	this page shipped without it: the kit draws no tooltip, a hover cannot be simulated in a
	playtest, and a card here is a fifth of a panel that is half the screen. The note left in
	`docs/NewUI-Migration-Notes.md` said the honest home for those numbers was a press-to-open panel
	rather than a hover, and on 2026-09-17 Dylan asked for exactly that, off a reference shot of an
	anime unit collector: the grid in the middle, the car you picked turning on one side of it and
	its numbers on the other.

	So the page has a SELECTED CAR now, which it did not before. Four rules keep that from undoing the
	2026-08-24 rewrite this file is otherwise built on:

	  • A TAP IS STILL THE VERB. The button on a card spawns, parks or puts away on one press, as it
	    always has. What picks a car is a press on its PICTURE (`PickBtn`), which had no press on it
	    before, so nothing that worked before now takes two.
	  • THE WINGS ARE NEVER THE ONLY WAY. Their button is the selected card's button drawn larger and
	    says the same word, read off the card rather than worked out again (`_mirrorVerb`).
	  • NOTHING HERE DEPENDS ON THEM EXISTING. `Components/CarDetailV2` answers nil when the feature
	    is off or the place has not had `BuildCarDetailV2` run over it, and every call is guarded, so
	    that page is the one that shipped.
	  • AND A PRESS IS THE ONLY THING THAT OPENS THEM (Dylan, 2026-09-17). The first pass had
	    `_reselect` pick a car whenever none was picked, so the page opened with both wings out and
	    the panel read as part of the screen rather than as an answer to anything. Now `_reselect`
	    only keeps up with a car that is already on the panel, `_forget` empties it on every open, and
	    the cards light their rim and swell under the pointer so that the grid says a picture can be
	    pressed at all (`Components/CarDetailV2.hoverCard`).

	On a pad the CARD'S PICTURE is in the walk, so a console makes the same gesture: the highlight
	landing on it is the hover and A is the press. And the HUD's icon grid steps aside while the wings
	are up, because there is no width at which a readable panel fits between a centred kit page and
	that grid — `BuildCarDetailV2` has the arithmetic and `CarDetailConfig.HideRail` is the switch.

	=== ON A GAMEPAD ==========================================================================

	THE ENGINE WILL NOT STEP INTO A SCROLLING GRID FROM OUTSIDE IT, which the collection index
	measured first (`PagesV2/Index`), so the doors are wired by hand here too. Inside the grid its
	own neighbour search walks card to card and scrolls the list to follow. The doors are the search
	box's and the X's DOWN (the card level with each, on the top row the window is showing) and a
	first-row card's UP (whichever of the two is nearer across). The list itself is not selectable:
	with the doors wired it is only ever a decoy the highlight parks on.

	A CARD IS THREE STOPS since the wings landed: the verb, the star, and the PICTURE above them both,
	which is what a press opens the wings with. The picture covers the star, so the ladder between
	them is wired by hand in `_wireCard` rather than left to a directional search between two
	overlapping selectables, and the door out of the grid moved up with it: it is the picture's now.

	THEY ARE WORKED OUT AGAIN WHEN THE SEARCH CHANGES, not only when a control gains the highlight.
	A search moves every card behind it into new slots, and a door still naming a card the search
	just hid puts the highlight on nothing. See `_refreshDoors`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
--- The EQUIP BEST button's face (`_buildEquipBest`), the kit's green.
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
--- EQUIP BEST's confirmation (`_equipBestDone`): its tweens and its sound.
local TweenService = game:GetService("TweenService")
local GameplayFeedback = require(ReplicatedStorage.shared.Modules.GameplayFeedback)
--- For one event name: the double-click that asks to drive a car (`StartCarConfig.PreselectEvent`).
local StartCarConfig = require(ReplicatedStorage.shared.Configs.StartCarConfig)
local CarDetailConfig = require(ReplicatedStorage.shared.Configs.CarDetailConfig)
-- What is in the player's hands, and whether a car may be picked up out of this screen at all.
local CarryConfig = require(ReplicatedStorage.shared.Configs.CarryConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local LobbyCarConfig = require(ReplicatedStorage.shared.Configs.LobbyCarConfig)
local RewardConfig = require(ReplicatedStorage.shared.Configs.RewardConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local CarCardDress = require(ReplicatedStorage.shared.Modules.CarCardDress)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local CarViewport = require(ReplicatedStorage.shared.Modules.CarViewport)
local CarViewportGrid = require(ReplicatedStorage.shared.Modules.CarViewportGrid)
local CarDetail = require(script.Parent.Parent.Components.CarDetailV2)
local KitPage = require(script.Parent.Parent.KitPage)

local PAGE_NAME = "Dealership"
--- Seconds within which a second press on a car's picture is a double-click, which drives it. The
--- SELECT CAR screen's number (`PagesV2/StartCar`), so the gesture feels the same on both.
local DOUBLE_PRESS = 0.4
local TEXT = InventoryConfig.Text

local Page = KitPage.extend(PAGE_NAME)

--- The kit's card, as `BuildDealershipV2` left it.
local CARD_NAME = "CarCard"
local FACE_NAME = "Face"
local EMPTY_CARD = "LeaveEmpty"

--- Which car a card is showing, read back off it at press time. See `_wireCard`.
local KEY_ATTRIBUTE = "CarKey"

--- The portrait the viewport grid fills, in the box the kit drew for its own icon.
local CAR_VIEW = "Car"

--- What `BuildCarDetailV2` added to a card: the halo that says the wings are describing it, and the
--- invisible press over its picture that picks it.
local DETAIL = CarDetailConfig.Parts

--[[ How much a card is dimmed when its car is parked on a bay OTHER than the one being edited.

	IT ONLY MEANS ANYTHING IN BAY MODE, and forgetting that dimmed six cards out of ten on the first
	playtest of the shipping inventory. "Spoken for" is a statement about the bay you are editing;
	open the same list from the HUD and there is no bay, so every parked car read as unavailable when
	in fact the whole lot is available. ]]
local ELSEWHERE_FADE = 0.55

--- How lit the star is, starred and not. The picture is the same either way, which is what makes an
--- unstarred card read as "you could" rather than as a second kind of car.
local STAR_ON = 0
local STAR_OFF = 0.65

--[[ How much white goes into the top of a rarity's ramp. The kit writes the rarity in a two-stop
	gradient, light at the top and saturated at the bottom, and our bands are one flat colour each
	(`CarRarity.Colours`), so the colour is the bottom stop and this is the lift on the top one.
	Same number and same reason as the market's listing row. ]]
local RARITY_LIFT = 0.35

local NBSP = "\u{00A0}"

--[[ Fill a template out of `InventoryConfig.Text` and make it safe for a TextScaled label.

	EVERY SPACE COMES OUT NON-BREAKING, which is the whole reason this exists rather than a bare
	`gsub`: TextScaled would rather wrap to a second line than shrink, so "PARK HERE" on a button a
	fifth of a card high becomes two stacked words at a readable size instead of one line at a
	smaller one. ]]
local function fill(template: string, fields: { [string]: string | number }?): string
	local text = template
	if fields then
		text = (string.gsub(text, "{(%w+)}", function(name)
			local value = fields[name]
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end))
	end
	return (string.gsub(text, " ", NBSP))
end

--- Search keys and typed queries are compared with everything but letters and digits thrown away, so
--- "golf gti", "GolfGTI" and "golf-gti" are one query.
local function normalize(text: string?): string
	return (string.gsub(string.lower(text or ""), "%W", ""))
end

--[[ "1:Sedan12:6,4:Sports16:1" -> { [carKey] = bay }. Anything unparseable is skipped, not fatal.

	The bay is the leading digits and EVERYTHING AFTER THE FIRST COLON IS THE KEY, which is why the
	pattern is `(%d+):(.+)` and not a split: a key has a colon of its own in it, and body names have
	spaces in them ("Golf GTI"), so neither can be treated as a field break. ]]
local function parseLot(raw: any): { [string]: number }
	local out = {}
	for _, entry in GarageConfig.split(raw) do
		local bay, key = string.match(entry, "^(%d+):(.+)$")
		if bay and key then
			out[key] = tonumber(bay)
		end
	end
	return out
end

--- A comma-separated attribute as a set of car keys.
local function parseSet(raw: any): { [string]: boolean }
	local out = {}
	for _, key in GarageConfig.split(raw) do
		out[key] = true
	end
	return out
end

--- A rarity's colour as the ramp the kit drew: lifted towards white at the top, the colour itself at
--- the bottom. Two stops, which is what the artist's own gradient has.
local function rarityRamp(colour: Color3): ColorSequence
	return ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), RARITY_LIFT), colour)
end

-- === Building ===============================================================

function Page.initialize(self)
	--- The kit's text caps are pixels for a 1080-tall screen; this keeps them in proportion above it.
	KitPage.scaleTextCaps(self.PageUI)

	self.Player = (self.UIController and self.UIController.Player) or Players.LocalPlayer

	--[[ One record per card, in the order the grid lays them out. NOT `self._rows`, which is
		`KitPage`'s own list of the cells it has stamped: a page extending it owns the names it
		invents and nothing else.

		AN ENTRY IS ALSO A `CarViewportGrid.Cell`. It carries `viewport`, `body`, `paint` and `fade`,
		which is the whole of what that module reads, so the list handed to `setCells` is this list
		rather than a second one built to mirror it. ]]
	self._entries = {} :: { any }
	self._query = ""

	--[[ BAY MODE UNTIL AN OPEN SAYS OTHERWISE. `_bay` is only meaningful in bay mode and `_bayArmed`
		is the one-shot that carries a podium press through to the open. Header note 1. ]]
	self._mode = "inventory"
	self._bay = 1
	self._bayArmed = false

	--- The spam floor. Courtesy on top of the server's own checks, never a permission.
	self._nextPressAt = 0

	self.TopBar = self.PageUI:FindFirstChild("TopBar")
	self.Note = self.Main and self.Main:FindFirstChild("Note")
	self.Storage = self.TopBar and self.TopBar:FindFirstChild("Storage")
	self.Caption = self.Storage and self.Storage:FindFirstChild("Title")

	--[[ THE CELLS IN THE WINDOW'S PIXELS, before a single card exists. Left in the artist's scale, a
		cell's HEIGHT resolves against the canvas: StartCar measured it on this same kit frame, twenty
		cards drawn 306px tall in a 266px window while the canvas and the viewport grid both counted
		139, so past about ten cars the cars went into the wrong cards. See `KitPage`'s header. ]]
	self:pinGridToWindow()

	--[[ Built before anything is filled, because `_applyFilter` hands it the cards on the first
		pass. It watches the scroll and the page for itself, so nothing below has to remember to
		tell it about either. ]]
	self._views = CarViewportGrid.new(self.List :: ScrollingFrame, self.PageUI)

	--[[ THE DETAIL WINGS. Nil when the feature is switched off or when this place has not had
		`BuildCarDetailV2` run over it, and every call below is guarded, so a page without them is
		exactly the page that shipped before they existed.

		The press is handed straight to `_press`, which is the card's own verb: the wing's button and
		the button on the selected card are two draws of one action. ]]
	self._detail = CarDetail.new(self.PageUI, {
		source = PAGE_NAME,
		showRate = true,
		onPress = function(key: string)
			self:_press(key)
		end,
		onSecondary = function(key: string)
			self:_pressSecondary(key)
		end,
	})
	--- The card the wings are describing, and its key kept beside it so a rebuild can find the same
	--- car again in cards that did not exist when it was picked.
	self._selected = nil :: any
	self._selectedKey = nil :: string?

	self:_buildSearch()
	self:_wireGamepad()

	--[[ The list is re-laid-out on every viewport change, and the geometry the viewport grid tests
		against has to move with it or the cars stop agreeing with the cards.

		RE-PINNED HERE FIRST rather than trusting `KitPage`'s own handler to have run already: the
		engine does not promise an order between two connections to one signal, and the geometry
		handed on has to be the new cells' numbers. `pinGridToWindow` is safe to call again. ]]
	if self.List then
		self.List:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:pinGridToWindow()
			self:_applyGeometry()
		end)
	end

	--- The bay arrives just before the page opens. Header note 1.
	Dispatcher:Subscribe("DealershipBay", function(bay: number)
		self:setBay(bay)
	end)

	--- Smaller on a monitor than on a phone (`InventoryConfig.PageScale`).
	self._authoredSize = self.PageUI.Size
	self:_applyPageScale()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		self:_applyPageScale()
	end)

	self:_watchState()
end

--[[ The frame's Size, not a `UIScale`: the page's one `UIScale` is `UIController`'s open tween, and the
	grid is pinned in pixels read off `AbsoluteSize`, which a resting scale would apply twice. The text
	is `TextScaled` under caps that are only ceilings, so it follows the smaller box by itself. ]]
function Page:_applyPageScale()
	local share = InventoryConfig.PageScale[UserInputService.PreferredInput.Name] or 1
	local size = self._authoredSize
	self.PageUI.Size = UDim2.new(size.X.Scale * share, size.X.Offset, size.Y.Scale * share, size.Y.Offset)
end

--[[ Header note 1: the bay, armed. Applied here as well as on open, so a bay changed while the page
	is already up (pressing a second podium without closing the first) redraws rather than waiting
	for a reopen. ]]
function Page:setBay(bay: number)
	self._bay = bay
	self._bayArmed = true
	if self._mode == "bay" then
		self:_applyMode()
		self:_rebuild()
	end
end

--- Title and caption: the whole of what the mode changes, now that the LEAVE EMPTY card is decided
--- in `_rebuild` and the verb on each button is decided in `_refresh`.
function Page:_applyMode()
	self:setTitle(fill(if self._mode == "bay" then TEXT.TitleBay else TEXT.TitleInventory))
	self:_refreshCaption()
end

--[[ The kit's `50/50` storage readout, which is the one free label above the list and carries
	whichever of the two things this screen most needs to say: which bay you are editing, or how many
	backpack cars you have against InventoryConfig.MaxCars, excluding the hotbar and bays. ]]
function Page:_refreshCaption()
	local caption = self.Caption
	if not (caption and caption:IsA("TextLabel")) then
		return
	end

	if self._mode == "bay" then
		caption.Text = fill(TEXT.CaptionBay, { bay = self._bay })
		return
	end
	-- Cars, not cards: the LEAVE EMPTY card is not one and never appears in inventory mode anyway.
	local count = 0
	for _, entry in self._entries do
		if entry.key then
			count += 1
		end
	end
	caption.Text = fill(TEXT.CaptionInventory, { count = count, limit = InventoryConfig.MaxCars })
end

-- === The search =============================================================

--[[ The kit ships the box with `Search...` TYPED IN IT rather than as placeholder text, which
	`BuildDealershipV2` moves; this is the half that has to agree with it. A box whose text is a
	prompt filters the list by the word "search" and shows nothing. ]]
function Page:_buildSearch()
	local bar = self.TopBar and self.TopBar:FindFirstChild("SearchBar")
	local box = bar and bar:FindFirstChildWhichIsA("TextBox")
	if not box then
		return
	end
	self.SearchBox = box
	box:GetPropertyChangedSignal("Text"):Connect(function()
		self:_setQuery(box.Text)
	end)
	self:_buildEquipBest(bar)
	local icon = bar:FindFirstChild("Icon")
	if icon and icon:IsA("GuiObject") then
		-- Equip Best narrows the bar; give the magnifier extra width and keep the text clear.
		local extraScale = icon.Size.X.Scale * 0.4
		local extraOffset = icon.Size.X.Offset * 0.4
		icon.Size += UDim2.new(extraScale, extraOffset, 0, 0)
		icon.Position += UDim2.new(extraScale * icon.AnchorPoint.X, extraOffset * icon.AnchorPoint.X, 0, 0)
		box.Size -= UDim2.new(extraScale, extraOffset, 0, 0)
		box.Position += UDim2.new(extraScale * (1 - box.AnchorPoint.X), extraOffset * (1 - box.AnchorPoint.X), 0, 0)
	end
end

--[[ EQUIP BEST (2026-10-15, the owner): a green button between the search box and the car count,
	which puts the most valuable cars the player owns on their bays (`GarageService.equipBest` has
	which and how). The search box gives up the room; the top bar's own list layout places all three.
	It sends nothing but the press, through `DealershipController`, and the lot redrawing is the
	answer. Built once, with the page. ]]
function Page:_buildEquipBest(search: Instance)
	local top = self.TopBar
	if not (top and search and search:IsA("GuiObject")) or top:FindFirstChild("EquipBest") then
		return
	end
	search.Size = UDim2.new(0.56, 0, search.Size.Y.Scale, search.Size.Y.Offset)
	local button, caption = ArcadeKit.button(top, "Claim", 0, 0, 0.215, search.Size.Y.Scale)
	button.Name = "EquipBest"
	caption.Text = "EQUIP BEST"
	--- Between the two, whatever the layout sorts by: by order (1, 2, 3) or by name ("EquipBest"
	--- would come first, so the orders are what put it in the middle).
	local layout = top:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.SortOrder = Enum.SortOrder.LayoutOrder
	end
	search.LayoutOrder = 1
	button.LayoutOrder = 2
	local storage = top:FindFirstChild("Storage")
	if storage and storage:IsA("GuiObject") then
		storage.LayoutOrder = 3
	end
	if button:IsA("GuiButton") then
		self:tagButton(button)
		button.Activated:Connect(function()
			Dispatcher:Publish("DealershipEquipBest")
		end)
	end
	self._equipButton, self._equipCaption = button, caption
	Dispatcher:Subscribe("DealershipEquipBestResult", function(result)
		self:_equipBestDone(result)
	end)
end

--[[ EQUIP BEST WORKED, AND SAYS SO (2026-10-15, the owner: "some sort of cool confirmation"). Played
	on the cars screen itself, since the lot is behind it and the notice lane is under it:
	  * the button pops and reads EQUIPPED! in gold for a moment, then goes back;
	  * a burst of gold sparks flies out of it;
	  * a banner slides in under the top bar with what happened: how many cars moved and how much
	    the parked cars are worth now on top of before (the server's own figures, `equipBest`);
	  * the parking sound.
	With nothing to change, the banner says the best cars are already out and there is no burst:
	a celebration for nothing would read as the button lying. ]]
function Page:_equipBestDone(result)
	local button, caption = self._equipButton, self._equipCaption
	if not (button and button.Parent and type(result) == "table") then
		return
	end
	local changed = result.changed or 0
	local token = (self._equipToken or 0) + 1
	self._equipToken = token

	--- The pop and the caption.
	local scale = button:FindFirstChild("EquipPop") or Instance.new("UIScale")
	scale.Name = "EquipPop"
	scale.Parent = button
	scale.Scale = 1.18
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	caption.Text = if changed > 0 then "EQUIPPED!" else "ALL SET!"
	caption.TextColor3 = Color3.fromRGB(255, 215, 70)
	task.delay(2.2, function()
		if self._equipToken == token and caption.Parent then
			caption.Text = "EQUIP BEST"
			caption.TextColor3 = Color3.new(1, 1, 1)
		end
	end)

	--- The banner, under the top bar.
	local page = self.PageUI
	local banner = Instance.new("TextLabel")
	banner.Name = "EquipBestBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.fromScale(0.5, 0.25)
	banner.Size = UDim2.fromScale(0.62, 0.065)
	banner.BackgroundColor3 = Color3.fromRGB(2, 30, 56)
	banner.BackgroundTransparency = 1
	banner.Font = Enum.Font.FredokaOne
	banner.TextScaled = true
	banner.TextTransparency = 1
	banner.TextColor3 = Color3.fromRGB(255, 215, 70)
	banner.ZIndex = 60
	banner.Text = if changed > 0
		then string.format(
			"Best cars equipped!  %d moved  ·  lot +%s",
			changed,
			GarageConfig.formatCash(result.gain or 0)
		)
		else "Your best cars are already on the lot!"
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = banner
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = banner
	banner.Parent = page
	local slide = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	banner.Position = UDim2.fromScale(0.5, 0.22)
	TweenService:Create(banner, slide, { Position = UDim2.fromScale(0.5, 0.25), BackgroundTransparency = 0.1, TextTransparency = 0 }):Play()
	task.delay(2.4, function()
		if banner.Parent then
			local out = TweenService:Create(banner, TweenInfo.new(0.35), { BackgroundTransparency = 1, TextTransparency = 1 })
			out.Completed:Once(function()
				banner:Destroy()
			end)
			out:Play()
		end
	end)

	if changed <= 0 then
		return
	end
	GameplayFeedback.play("Parked")

	--- The burst: a dozen gold sparks out of the button's centre, flying and fading.
	local centre = button.AbsolutePosition + button.AbsoluteSize / 2 - page.AbsolutePosition
	local uiScale = page:FindFirstChildOfClass("UIScale")
	local k = if uiScale and uiScale.Scale > 0 then uiScale.Scale else 1
	centre /= k
	for i = 1, 12 do
		local spark = Instance.new("Frame")
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Size = UDim2.fromOffset(9, 9)
		spark.Position = UDim2.fromOffset(centre.X, centre.Y)
		spark.BackgroundColor3 = if i % 3 == 0 then Color3.new(1, 1, 1) else Color3.fromRGB(255, 205, 50)
		spark.Rotation = math.random(0, 90)
		spark.ZIndex = 61
		spark.Parent = page
		local angle = (i / 12) * math.pi * 2 + math.random() * 0.4
		local reach = 60 + math.random() * 50
		local to = UDim2.fromOffset(centre.X + math.cos(angle) * reach, centre.Y + math.sin(angle) * reach)
		local fly = TweenService:Create(spark, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = to,
			BackgroundTransparency = 1,
			Rotation = spark.Rotation + 180,
			Size = UDim2.fromOffset(4, 4),
		})
		fly.Completed:Once(function()
			spark:Destroy()
		end)
		fly:Play()
	end
end

function Page:_setQuery(text: string)
	local query = normalize(text)
	if query == self._query then
		return -- punctuation-only edits do not change the result set
	end
	self._query = query
	self:_applyFilter()
end

--[[ Which cards are showing, and the list the viewport grid draws cars into.

	IT IS NOT THE SAME LIST AS `_entries`: a `UIGridLayout` lays out VISIBLE children only, so a
	search moves every card behind the query up into the rows the window is over. `_entries` is built
	in layout order, so collecting it in order collects the grid. ]]
function Page:_applyFilter()
	local cells = {}
	local visible = 0
	for _, entry in self._entries do
		--- The LEAVE EMPTY card is not a car and is never filtered out: clearing a bay has to stay
		--- reachable whatever is typed in the box.
		local matches = entry.key == nil or self._query == "" or string.find(entry.search, self._query, 1, true) ~= nil
		entry.card.Visible = matches
		--- Where the card lands in the grid as it is now laid out. The gamepad doors read it.
		entry.slot = nil
		if matches then
			visible += 1
			table.insert(cells, entry)
			entry.slot = visible
		end
	end

	--- `KitPage` sizes the canvas off the VISIBLE cells, so a search shortens the list as well as
	--- shortening what is in it.
	self:_updateCanvas()
	self:_updateEmptyState()

	if self.List then
		self.List.CanvasPosition = Vector2.zero
	end
	--- After the canvas, so the grid tests the new list against the new geometry rather than the old.
	self:_applyGeometry()
	self._views:setCells(cells)

	--- The doors into the grid named cards by slot, and the slots just changed.
	self:_refreshDoors()
	--- And the wings may be describing a car the query has just hidden.
	self:_reselect()
end

--- The cell geometry, straight from `KitPage`, which is working it out for the canvas anyway.
function Page:_applyGeometry()
	if not self.List then
		return
	end
	self._views:setLayout(self:cellGeometry())
end

--[[ A panel with nothing in it should say which kind of nothing. The count excludes the LEAVE EMPTY
	card, which is not a car and is not always there (see `_rebuild`). ]]
function Page:_updateEmptyState()
	local note = self.Note
	if not (note and note:IsA("TextLabel")) then
		return
	end

	local cars, shownCars = 0, 0
	for _, entry in self._entries do
		if entry.key then
			cars += 1
			if entry.card.Visible then
				shownCars += 1
			end
		end
	end

	note.Visible = shownCars <= 0
	--- With cars owned but none stored, the inventory says how to store one rather than "steal one".
	local ownsAny = #GarageConfig.split(self.Player:GetAttribute(GarageConfig.OwnedAttribute)) > 0
	--- A controller cannot click a tile; its way to store a car is the held car and Y (`CarryHotbarController`).
	local stored = if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then TEXT.NoStoredPad else TEXT.NoStored
	local empty = if self._mode ~= "bay" and ownsAny then stored else TEXT.NoCars
	note.Text = fill(if cars <= 0 then empty else TEXT.NoMatch)
end

-- === The cards ==============================================================

--[[ One card, for one owned car. `key = nil` builds the LEAVE EMPTY card at the head of the list.

	The clone carries its tags with it, so the kit's button is already a `UIButton` with hover, sound
	and a gamepad highlight, and nothing here wires any of that. The star is the one control this
	page adds, so it is the one this page has to tag. ]]
function Page:_makeCard(key: string?, order: number)
	local card = self:newRow(CARD_NAME)
	if not card then
		return nil
	end
	card.Name = key or EMPTY_CARD
	card.LayoutOrder = order

	local body, paint, mutation = nil, nil, nil
	if key then
		body, paint, mutation = GarageConfig.parseCarKey(key)
	end

	local face = card:FindFirstChild(FACE_NAME)
	local icon = face and face:FindFirstChild("Icon")
	local btns = card:FindFirstChild("Btns")

	local entry = {
		key = key,
		card = card,
		face = face,
		--- `CarViewportGrid.Cell`'s fields, which is why this record is handed to it directly.
		body = body,
		paint = paint,
		mutation = mutation,
		fade = 0,
		viewport = nil :: ViewportFrame?,

		title = face and face:FindFirstChild("Title"),
		rarity = face and face:FindFirstChild("Rarity"),
		icon = icon,
		star = face and face:FindFirstChild("Star"),
		level = face and face:FindFirstChild("Level"),
		rim = face and face:FindFirstChild("Rim"),
		--- The detail wings' three additions. All nil on a place built before they landed.
		halo = face and face:FindFirstChild(DETAIL.Halo),
		hover = face and face:FindFirstChild(DETAIL.Hover),
		pick = face and face:FindFirstChild(DETAIL.Select),
		action = btns and btns:FindFirstChild("EquipBtn"),
		state = btns and btns:FindFirstChild("EquippedBtn"),
		--- Normalised once here rather than per keystroke: the query is normalised instead.
		--- The mutation's name leads the key (2026-10-14), so "molten" finds every molten car.
		search = if body
			then normalize((if mutation then WeatherConfig.nameOf(mutation) .. " " else "") .. GarageConfig.carName(body, paint))
			else "",
		favorited = false,
	}

	if key then
		card:SetAttribute(KEY_ATTRIBUTE, key)
	end

	--[[ The portrait, over the box the kit drew for its own picture. `CarViewport` builds the frame,
		so there is no second copy of its camera or its lighting here.

		THE KIT'S PICTURE GOES WITH IT, and it used to be the fallback for a body with no published
		shell. It is a pink rabbit, and the cars on this page arrive a couple a frame
		(`CarViewportGrid`), so every card on an opening screen drew the rabbit for the frames before
		its car landed: what the page did on open was flash rabbits. `BuildIndexV2` took the same
		decision on the collection page and for the same reason, "a rabbit captioned CIVIC is worse
		than an empty card". THE BOX STAYS. It is what the viewport is measured off, and it is still
		the LEAVE EMPTY card's own sign (`_paintIdentity`), which is why only a card with a body is
		cleared here. ]]
	if icon and icon:IsA("GuiObject") and body then
		if icon:IsA("ImageLabel") then
			icon.Image = ""
		end
		local view = CarViewport.new(face :: GuiObject, CAR_VIEW)
		view.AnchorPoint = icon.AnchorPoint
		view.Position = icon.Position
		view.Size = icon.Size
		view.ZIndex = icon.ZIndex
		entry.viewport = view
	end

	self:_paintIdentity(entry)
	self:_wireCard(entry)
	return entry
end

--- What a card says about WHICH car it is. Fixed for the life of the card, so it is painted once.
function Page:_paintIdentity(entry)
	local title = entry.title
	if title and title:IsA("TextLabel") then
		title.Text = if entry.key then GarageConfig.carName(entry.body, entry.paint) else fill(TEXT.ClearBay)
	end

	--- The LEAVE EMPTY card wears a "no car" sign rather than the kit's picture. It is the one card
	--- whose picture box keeps an image at all, because a car card's is cleared in `_makeCard`.
	local icon = entry.icon
	if not entry.key and icon and icon:IsA("ImageLabel") then
		icon.Image = "rbxassetid://" .. UIAssets.Inventory.ClearBay
	end

	local rarity = entry.rarity
	if rarity and rarity:IsA("TextLabel") then
		if not entry.key then
			--- The LEAVE EMPTY card is not a car and has no rarity to print.
			rarity.Text = ""
		else
			--[[ `CarRarity` rather than a word off the roster: same word off the same ladder, and
				that module is the only thing in the game that also has the COLOUR. One lookup keeps
				the two from ever disagreeing. ]]
			local word, colour = CarRarity.labelOf(entry.body)
			--- The mutation is its glyph on the card now, not a word here (`Modules/CarCardDress`).
			rarity.Text = fill(string.upper(word))
			local tint = rarity:FindFirstChild("Tint")
			if tint and tint:IsA("UIGradient") then
				tint.Color = rarityRamp(colour)
			end
		end
	end

	--- Aleafo's card: rarity face, name on top, mutation glyph (`Modules/CarCardDress`).
	CarCardDress.apply(entry.face, entry.title, entry.rarity, entry.body, entry.mutation)

	local star = entry.star
	if star and star:IsA("GuiObject") then
		--- No star on the LEAVE EMPTY card: there is nothing to favourite.
		star.Visible = entry.key ~= nil and InventoryConfig.Enabled
	end
end

--[[ The two presses a card has. Both read the car off the CARD at press time rather than closing
	over it, so a rebuild that moves a card cannot leave a button acting on the car that used to be
	in that slot.

	`Activated` and not `MouseButton1Click`: it is the one event a mouse, a touch and a gamepad's A
	press all raise, and on a real button it already means press and release on the same control,
	which is the whole of what the shipping page's hold guards were for. ]]
function Page:_wireCard(entry)
	local action = entry.action
	if action and action:IsA("GuiButton") then
		action.Activated:Connect(function()
			self:_press(entry.card:GetAttribute(KEY_ATTRIBUTE))
		end)
	end

	local star = entry.star
	if star and star:IsA("GuiButton") then
		self:tagButton(star)
		star.Activated:Connect(function()
			self:_toggleFavorite(entry.card:GetAttribute(KEY_ATTRIBUTE))
		end)
	end

	--[[ A press on the PICTURE opens the wings on that car, and the same press again puts them away.
		It is deliberately not the verb — the verb is the button under it and still fires on one press
		(2026-08-24, "a tap is the verb") — so a player who never touches a picture has the screen
		that shipped, and one who does gets the numbers without having spawned anything.

		THE SAME PRESS ON A PAD. The picture is in the gamepad's walk, the highlight landing on it is
		the hover and A is the click, so a console makes the pointer's gesture rather than a second
		one of its own (header, "On a gamepad"). NOT ON THE LEAVE EMPTY CARD, which is not a car: a
		selectable that answers nothing is a dead stop in the middle of the grid. ]]
	local pick = entry.pick
	if pick and pick:IsA("GuiButton") then
		if entry.key then
			--[[ A DOUBLE PRESS DRIVES IT (2026-09-28): the second press inside `DOUBLE_PRESS` asks to
				race in this car — the world screen opens, and the world picked there starts the run
				in it (`StartCarController.preselect`). It does not toggle the wings shut; the first
				press opened them, and a panel that flashed open and closed before the page changed
				would read as a glitch. ]]
			local lastPress = 0
			pick.Activated:Connect(function()
				local now = os.clock()
				if now - lastPress <= DOUBLE_PRESS then
					lastPress = 0
					Dispatcher:Publish(StartCarConfig.PreselectEvent, entry.key)
					return
				end
				lastPress = now
				self:_toggleSelect(entry)
			end)

			--- The card says so while a pointer is on it or the highlight is: the rim lights and the
			--- card swells. Since the wings stopped opening by themselves this is the only thing on
			--- the grid that says a picture can be pressed at all. `Components/CarDetailV2` owns the
			--- reaction; both car screens wear it.
			CarDetail.hoverCard(entry.card, pick, entry.hover)

			pick.SelectionGained:Connect(function()
				--- Down is the card's own furniture; up is the top bar from the first row, and the
				--- card above everywhere else, which the engine finds for itself.
				pick.NextSelectionDown = self:_topControl(entry)
				local firstRow = entry.slot ~= nil and entry.slot <= math.max(1, self._columns)
				pick.NextSelectionUp = if firstRow then self:_topBarNearest(pick) else nil
			end)
		else
			pick.Selectable = false
		end
	end

	--[[ The ladder UP a card, decided on arrival for the same reason the doors in are: the slot moves
		with the search. The card's topmost control hands up to the PICTURE, which is the new top of
		the card and carries the door out of the grid; everywhere else the engine's own answer (the
		star above the button, the card above the card) is the right one and is left alone. ]]
	for _, control in { action, star } do
		if control and control:IsA("GuiObject") then
			control.SelectionGained:Connect(function()
				control.NextSelectionUp = if control == self:_topControl(entry) and pick and pick.Selectable
					then pick
					else nil
			end)
		end
	end
end

--[[ WHICH CARS THIS SCREEN LISTS (2026-09-30, `CarryConfig.Hotbar`). Every car is in one place —
	a bay, the hotbar or the inventory — and this screen shows:

	    inventory mode   the INVENTORY only: owned, not in the hotbar, not on any bay
	    bay mode         everything that could go on this bay — the hotbar and the inventory — plus
	                     the car already standing HERE, so ON THIS BAY and the sale toggle still show

	Cars on OTHER bays are in neither (the owner's call): a car on a podium lives on the podium. ]]
function Page:_listed(): { string }
	local owned = GarageConfig.split(self.Player:GetAttribute(GarageConfig.OwnedAttribute))
	local lot = parseLot(self.Player:GetAttribute(GarageConfig.LotAttribute))
	local bar = parseSet(self.Player:GetAttribute(CarryConfig.Hotbar.Attribute))
	local out = {}
	for _, key in owned do
		local bay = lot[key]
		local keep = if self._mode == "bay"
			then bay == nil or bay == self._bay
			else bay == nil and not bar[key]
		if keep then
			table.insert(out, key)
		end
	end
	return out
end

--[[ Rebuild the cards. The collection only changes when a car is banked, sold or starred, so this is
	the expensive one and it is not on the hot path; `_refresh` is.

	SORTED STARRED FIRST, then by tier, then by name. Starring a car moves it to the top, which is
	why a favourite change rebuilds rather than repaints. ]]
function Page:_rebuild()
	--- Emptied BEFORE the cards go, so the grid lets go of viewports that still exist rather than of
	--- ones it has to reason about the destruction of.
	self._views:clear()
	self:clearRows()
	table.clear(self._entries)

	local favorites = parseSet(self.Player:GetAttribute(InventoryConfig.FavoritesAttribute))
	local owned = self:_listed()
	table.sort(owned, function(a, b)
		local fa, fb = favorites[a] == true, favorites[b] == true
		if fa ~= fb then
			return fa
		end
		local ta = GarageConfig.TierOfBody[(GarageConfig.parseCarKey(a))] or 0
		local tb = GarageConfig.TierOfBody[(GarageConfig.parseCarKey(b))] or 0
		if ta ~= tb then
			return ta > tb
		end
		return a < b
	end)

	--[[ THE LEAVE EMPTY CARD EXISTS IN BAY MODE ONLY. In inventory mode there is no bay to clear,
		and putting a car away is what pressing the card that is already out does, so a card whose
		whole job is "none of these" would be a card with nothing to do.

		AND ONLY ONCE A CAR IS OWNED. With none, the bay cannot hold anything, so the card is a
		choice with no alternative sitting under STEAL A CAR FIRST; the note alone says it (Dylan,
		2026-09-17). Owning a car rebuilds, so the card arrives with the first one. ]]
	if self._mode == "bay" and #owned > 0 then
		local empty = self:_makeCard(nil, 0)
		if empty then
			table.insert(self._entries, empty)
		end
	end
	for index, key in owned do
		local entry = self:_makeCard(key, index)
		if entry then
			table.insert(self._entries, entry)
		end
	end

	self:_applyFilter()
	self:_refreshCaption()
	self:_refresh()
end

--[[ Repaint every card's state without rebuilding: which bay each car is on, what is in the street,
	the levels, the star and the green rim. Runs on three attribute changes and on every open, so it
	is the one that has to be cheap. ]]
function Page:_refresh()
	local lot = parseLot(self.Player:GetAttribute(GarageConfig.LotAttribute))
	local favorites = parseSet(self.Player:GetAttribute(InventoryConfig.FavoritesAttribute))
	local levels = RewardConfig.decodeLevels(self.Player:GetAttribute(GarageConfig.LevelsAttribute))
	local inLobby = self.Player:GetAttribute(LobbyCarConfig.SpawnedAttribute)
	local barFull = #GarageConfig.split(self.Player:GetAttribute(CarryConfig.Hotbar.Attribute)) >= CarryConfig.Hotbar.Slots

	local occupied = false
	for _, bay in lot do
		if bay == self._bay then
			occupied = true
			break
		end
	end

	for _, entry in self._entries do
		if not entry.key then
			--[[ The LEAVE EMPTY card is the CURRENT state when nothing is parked here, and it says
				so in the same words a car does. Without this an empty bay is the one case the screen
				shows no marker at all, which reads as the page having failed to load rather than as
				the bay being empty on purpose.

				SO IT IS PRESSABLE EXACTLY WHEN THERE IS SOMETHING TO CLEAR, which is the opposite
				way round from every other card on the screen: a bay that is already empty is a card
				that is already what you are asking for. ]]
			self:_paintButton(entry, occupied, fill(TEXT.ActionClear), fill(TEXT.ParkedHere))
			self:_setRim(entry, not occupied)
			continue
		end

		--- Looked up by the whole KEY. By body it would mark every colour of a body as parked the
		--- moment one of them was, which is the exact confusion owning two Camaros exists to avoid.
		local bay = lot[entry.key]
		local here = bay == self._bay and self._mode == "bay"
		local out = entry.key == inLobby

		--[[ Opacity is the kit's own state language, so "parked on some other bay" is a fade rather
			than a badge. The card stays pressable: pressing it moves the car here. ]]
		local fade = if bay and not here and self._mode == "bay" then ELSEWHERE_FADE else 0
		self:_setFade(entry, fade)

		--[[ LEVEL IS PER BODY, not per key: XP is earned in a body and both your Camaros carry it.

			BLANK AT LEVEL 1, which is every car nobody has driven far in: the chip is there to say
			"this one is worth more than it looks", and printing it on all forty cards says nothing
			at all. It is a chip rather than a line because `TextScaled` sizes a label to its own
			string, and a level appended to the rarity made two cards' captions half the size of
			their neighbours'. ]]
		local level = levels[entry.body] or 1
		local chip = entry.level
		if chip and chip:IsA("TextLabel") then
			chip.Text = if level > 1 then fill(TEXT.LevelShort, { level = level }) else ""
		end

		entry.favorited = favorites[entry.key] == true
		self:_paintStar(entry)

		--[[ WHAT THE BUTTON SAYS IS WHAT A PRESS DOES, and the grey face is the card that is already
			what you are asking for. Bay mode has one of those (the car parked here); inventory mode
			never does, because a car in the street can always be put away again. ]]
		if self._mode == "bay" then
			self:_paintButton(entry, not here, fill(TEXT.ActionPark), fill(TEXT.ParkedHere))
		else
			--- TO HOTBAR, or the grey HOTBAR FULL (2026-09-30). The street's SPAWN moved to the wings.
			self:_paintButton(entry, not barFull, fill(TEXT.ActionToHotbar), fill(TEXT.HotbarFull))
		end

		--- The rim follows the mode: the car on THIS bay, or the car in the street.
		self:_setRim(entry, if self._mode == "bay" then here else out)
	end

	--- Which of a card's two buttons is showing just changed, and a door has to land on one that is.
	self:_refreshDoors()
	--- The wings pick a car up again after a rebuild, and let one go when it is sold.
	self:_reselect()
end

--- Which of the artist's two button faces is showing, and what each says. The wings' button is the
--- same statement about the same car, so a repaint of the selected card repaints that too.
function Page:_paintButton(entry, pressable: boolean, action: string, state: string)
	local button = entry.action
	if button and button:IsA("GuiObject") then
		button.Visible = pressable
		local label = button:FindFirstChild("Title")
		if label and label:IsA("TextLabel") then
			label.Text = action
		end
	end

	local grey = entry.state
	if grey and grey:IsA("GuiObject") then
		grey.Visible = not pressable
		local label = grey:FindFirstChild("Title")
		if label and label:IsA("TextLabel") then
			label.Text = state
		end
	end

	if entry == self._selected then
		self:_mirrorVerb(entry)
	end
end

--- The green rim on the card this screen is about.
function Page:_setRim(entry, on: boolean)
	local rim = entry.rim
	if rim and rim:IsA("UIStroke") then
		rim.Enabled = on
	end
end

--- The star, lit or unlit. Same picture either way: an unstarred card should read as "you could"
--- rather than as a second kind of car.
function Page:_paintStar(entry)
	local star = entry.star
	if star and star:IsA("ImageButton") then
		star.ImageTransparency = if entry.favorited then STAR_ON else STAR_OFF
	end
end

--[[ Dim a whole card, car included.

	`ImageTransparency` on a ViewportFrame is the RENDERED SCENE's transparency, so one write dims
	the model rather than twenty-five parts. LATCHED as well as applied, because a car built later
	has to arrive already dimmed rather than flash to full and be corrected. ]]
function Page:_setFade(entry, fade: number)
	entry.fade = fade
	for _, part in { entry.title, entry.rarity, entry.level } do
		if part and part:IsA("TextLabel") then
			part.TextTransparency = fade
		end
	end
	if entry.face and entry.face:IsA("GuiObject") then
		entry.face.BackgroundTransparency = fade
	end
	if entry.icon and entry.icon:IsA("ImageLabel") then
		entry.icon.ImageTransparency = fade
	end
	if entry.viewport then
		entry.viewport.ImageTransparency = fade
	end
end

-- === The detail wings =======================================================

--[[ Pick a car: the wings describe it and its card wears the halo.

	EVERY CALL IS SAFE WITHOUT THE WINGS. `_detail` is nil when the feature is off or the place has
	not been rebuilt, and `halo` is nil on a card built before it existed, so a page without either
	runs every line below and changes nothing. ]]
function Page:_select(entry)
	--- No wings, no selection: with the feature off this is the page that shipped, rather than the
	--- page that shipped plus a halo lighting up cards for a panel nobody has.
	if not (self._detail and entry and entry.key) then
		return
	end
	if self._selected == entry and self._detail and self._detail:isShowing() then
		return -- already the car on the panel; a pad walking back over a card must not rebuild it
	end

	self._selected = entry
	self._selectedKey = entry.key
	for _, other in self._entries do
		if other.halo and other.halo:IsA("UIStroke") then
			other.halo.Enabled = other == entry
		end
	end

	if self._detail then
		self._detail:show(entry)
		self:_mirrorVerb(entry)
	end
end

--[[ The press on a card's picture: describe this car, or put the panel away when it is already the
	one being described. Dylan, 2026-09-17: "if you click the card again, the stats go away."

	SEPARATE FROM `_select` BECAUSE ONLY A PRESS MAY TOGGLE. `_reselect` re-points the panel at the
	rebuilt card for the car it is already showing, and a toggle there would read that as a second
	press and put the wings away on any repaint. It is the same reason the pad's highlight no longer
	picks: a panel that shut because the DPad passed back over its card is one nobody could keep
	open. ]]
function Page:_toggleSelect(entry)
	if not (self._detail and entry and entry.key) then
		return
	end
	if self._selected == entry and self._detail:isShowing() then
		self:_forget()
		return
	end
	self:_select(entry)
end

--[[ The wings' button says exactly what the selected card's button says.

	READ OFF THE CARD rather than worked out again. Which verb a card carries depends on the mode,
	the bay, the lot and what is in the street, and `_refresh` has already done all of that; a second
	copy of that reasoning here would be the one thing on this screen that could tell the player a
	press does something it does not. ]]
function Page:_mirrorVerb(entry)
	local detail = self._detail
	if not (detail and entry) then
		return
	end
	local function titleOf(button): string
		local label = button and button:FindFirstChild("Title")
		return if label and label:IsA("TextLabel") then label.Text else ""
	end
	local pressable = entry.action ~= nil and entry.action.Visible
	detail:setAction(titleOf(entry.action), pressable, titleOf(entry.state))

	local verb = self:_secondaryFor(entry.key)
	detail:setSecondary(if verb then fill(verb.label) else nil)
end

--[[ The wings' SECOND verb for one car, or nil when it has none (2026-09-28; the carry pair became
	the street on 2026-09-30, when the hotbar took over getting a car into your hands):

	    on a bay          FOR SALE: ON / OFF   a toggle, reading the state (`NotForSale` flag)
	    anywhere else     SPAWN / PUT AWAY     the car in the street (`LobbyCarService`)

	Read off the same three attributes `_refresh` repaints from, so the verb and the card beneath it
	cannot disagree about where a car is. Pure — it decides a word and writes nothing, so `_mirrorVerb`
	and `_pressSecondary` both run it and a press always does what the button said. ]]
function Page:_secondaryFor(key: string?): { kind: string, label: string, on: boolean? }?
	if not key then
		return nil
	end

	local lot = parseLot(self.Player:GetAttribute(GarageConfig.LotAttribute))
	if lot[key] then
		local held = parseSet(self.Player:GetAttribute(InventoryConfig.NotForSaleAttribute))[key] == true
		return { kind = "sale", label = if held then TEXT.ForSaleOff else TEXT.ForSaleOn, on = not held }
	end

	--- A car in the inventory: the street (2026-09-30). The hotbar is the card's own button now.
	local out = self.Player:GetAttribute(LobbyCarConfig.SpawnedAttribute) == key
	return { kind = "street", label = if out then TEXT.ActionPutAway else TEXT.ActionSpawn }
end

--[[ A press on the second verb. Publishes and stops, header note 2: the flag and the carry both come
	back as attribute writes, which repaint the button for real.

	A CARRY CLOSES THE SCREEN, for the reason a spawn does (Dylan, 2026-09-19): the car arrives in the
	player's hands behind this panel, and the next thing they do is walk it to a podium. Neither of
	the other two closes it — a sale toggle and a put-down are things you do while still looking at
	the list. ]]
function Page:_pressSecondary(key: string)
	local now = os.clock()
	if now < self._nextPressAt then
		return
	end
	local verb = self:_secondaryFor(key)
	if not verb then
		return
	end
	self._nextPressAt = now + CarryConfig.Prompt.Cooldown

	if verb.kind == "sale" then
		--- `on` is "is it for sale NOW", and the flag is the exception list, so taking a car off sale
		--- is SETTING the flag. The server re-checks ownership; this only names the car.
		Dispatcher:Publish("InventoryFlag", key, InventoryConfig.Keys.NotForSale, verb.on == true)
	else
		--- `_spawn` keeps its own cooldown and closes the screen on a spawn; clear ours so it runs.
		self._nextPressAt = 0
		self:_spawn(key)
	end
end

--[[ Keep the panel pointed at the car it is already describing, and let that car go when it leaves
	the screen. Runs after every rebuild, every filter and every repaint, and does nothing at all in
	the usual case.

	IT NEVER PICKS A CAR, and it used to. A page with nothing selected chose the car on the bay being
	edited, or the one in the street, or the first card — so every open of this screen came up with
	both wings already out. Dylan asked for that to stop on 2026-09-17: the wings are the answer to a
	press now, the cards say so under the pointer (`Components/CarDetailV2.hoverCard`), and a screen
	that opens with them folded away is a screen whose grid has the room to itself again.

	What is left is bookkeeping. A rebuild makes new cards for the same cars, so the entry the panel
	was pointed at is a dead frame and the same car has to be found again by key; a search can hide
	the car being described, and selling it takes it away for good. ]]
function Page:_reselect()
	local detail = self._detail
	if not (detail and self._selectedKey and detail:isShowing()) then
		return
	end

	local current = self._selected
	if current and current.key == self._selectedKey and current.card.Parent ~= nil and current.card.Visible then
		return
	end

	local keep = nil
	for _, entry in self._entries do
		if entry.key == self._selectedKey and entry.card.Visible then
			keep = entry
			break
		end
	end

	if keep then
		--- Cleared first, so `_select` cannot mistake the destroyed card it is replacing for the one
		--- it has just been asked for.
		self._selected = nil
		self:_select(keep)
	else
		--- Sold, or hidden by a query. There is no longer a car to describe.
		self:_forget()
	end
end

--[[ Nothing is picked any more: the halos go out and the wings go away.

	ALSO WHAT AN OPEN STARTS FROM. A screen is reopened with its grid to itself, which is the other
	half of "a press opens them" — a page that remembered the last car picked would come back up with
	the panel already out, which is the thing that was asked to stop. ]]
function Page:_forget()
	self._selected = nil
	self._selectedKey = nil
	for _, entry in self._entries do
		if entry.halo and entry.halo:IsA("UIStroke") then
			entry.halo.Enabled = false
		end
	end
	if self._detail then
		self._detail:clear()
	end
end

-- === Doing things ===========================================================

--[[ A press. Header note 2: it publishes and stops — and on a spawn it takes the screen with it.

	The cooldown is courtesy on top of the server's own checks, not a permission: both services
	re-check their own, and the numbers are theirs (`GarageConfig.Picker.Cooldown` is a lot rebuild,
	`LobbyCarConfig.RequestCooldown` is a 310-instance rig clone). ]]
function Page:_press(key: string?)
	local now = os.clock()
	if now < self._nextPressAt then
		return
	end

	if self._mode == "bay" then
		self._nextPressAt = now + GarageConfig.Picker.Cooldown
		Dispatcher:Publish("DealershipPick", self._bay, key)
		return
	end

	if not key then
		--- The LEAVE EMPTY card only exists in bay mode, but a stale one is not a spawn.
		return
	end
	--[[ OUT OF THE INVENTORY, INTO THE HOTBAR (2026-09-30, `CarryConfig.Hotbar`) — the card's one
		press, and the other half of a hotbar click with this screen open. The card leaves the grid when
		the hotbar attribute comes back; nothing is removed here, header note 2. The screen stays up:
		moving cars back and forth is something done several at a time. ]]
	self._nextPressAt = now + CarryConfig.Prompt.Cooldown
	Dispatcher:Publish("HotbarAction", "toHotbar", key)
end

--[[ The street, which used to be the card's press and is the wings' second button since 2026-09-30.
	Everything below is the old press unchanged: the spawn closes the screen, a put-away does not. ]]
function Page:_spawn(key: string)
	local now = os.clock()
	if now < self._nextPressAt then
		return
	end
	self._nextPressAt = now + LobbyCarConfig.RequestCooldown
	Dispatcher:Publish("SpawnCarPick", key)

	--[[ AND THE SCREEN GETS OUT OF THE WAY (Dylan, 2026-09-19). The car lands in the street behind
		this panel, so a page that stays up is one the player has to close by hand before they can
		see the thing they just pressed for.

		ONLY ON A SPAWN, NEVER ON A PUT-AWAY. The same press is a toggle — pressing the car that is
		already out puts it back — and there is nothing to go and look at then; closing on that
		would take the list away from someone who is clearing the street in order to pick something
		else out of it. Read off the attribute `_refresh` paints the verb from, so the page cannot
		close on a press whose button said PUT AWAY.

		BAY MODE RETURNED ABOVE and never reaches this: a lot is a list you work down, and closing
		the page after each car would make parking six of them six openings. ]]
	if key ~= self.Player:GetAttribute(LobbyCarConfig.SpawnedAttribute) then
		self.UIController:closePage(PAGE_NAME)
	end
end

--- Ask the server to star or unstar this car. Publishes and stops, like everything else here.
function Page:_toggleFavorite(key: string?)
	if not (key and InventoryConfig.Enabled) then
		return
	end
	local on = parseSet(self.Player:GetAttribute(InventoryConfig.FavoritesAttribute))[key] ~= true
	Dispatcher:Publish("InventoryFlag", key, InventoryConfig.Keys.Favorites, on)
end

-- === The five attributes ====================================================

--[[ Header note 3. A rebuild for the two lists that change the CARDS, a repaint for the three that
	change what a card SAYS. Favourites are in the first group because they are a sort key: starring
	a car moves it to the top, which is a new order and therefore new cards. ]]
function Page:_watchState()
	self:_rebuild()

	--- The lot and the hotbar decide WHICH cards exist since 2026-09-30 (`_listed`), so they rebuild.
	for _, attribute in {
		GarageConfig.OwnedAttribute,
		InventoryConfig.FavoritesAttribute,
		GarageConfig.LotAttribute,
		CarryConfig.Hotbar.Attribute,
	} do
		self.Player:GetAttributeChangedSignal(attribute):Connect(function()
			self:_requestRebuild()
		end)
	end
	for _, attribute in {
		GarageConfig.LevelsAttribute,
		LobbyCarConfig.SpawnedAttribute,
		--- The two the wings' second verb reads (2026-09-28). They change what a button SAYS, never
		--- which cards exist, so they repaint rather than rebuild.
		CarryConfig.Attribute,
		InventoryConfig.NotForSaleAttribute,
	} do
		self.Player:GetAttributeChangedSignal(attribute):Connect(function()
			self:_refresh()
		end)
	end
end

--[[ A rebuild asked for by a state change, COALESCED AND DEFERRED (2026-10-05, "there's lag when
	banking a car"; RE-APPLIED 2026-10-07 — a later commit carried an older copy of this file and
	dropped it, and the hitch came straight back).

	MEASURED, NOT GUESSED (`Modules/HitchProbe`, 2026-10-07): the first bank of a session froze the
	client for 947ms one second after the bank, and the only work of ours in that frame was this
	page's `_rebuild` — run on a CLOSED page, because the bank moves the collection and the hotbar
	attributes. Every card in the collection was torn down and stamped again behind a page nobody had
	open, and the engine paid for the new cards' first layout and art on that frame. The second bank
	of a session, with all of that already loaded, showed nothing over 103ms.

	NOW: closed, the page only remembers it is stale and rebuilds on its next open
	(`StartOpenThread`). Open, the requests in one frame collapse into a single rebuild at the end of
	it (`task.defer`), so a bank costs one rebuild, and only if somebody is looking. ]]
function Page:_requestRebuild()
	if not (self.PageUI and self.PageUI.Visible) then
		self._stale = true
		return
	end
	if self._rebuildQueued then
		return
	end
	self._rebuildQueued = true
	task.defer(function()
		self._rebuildQueued = false
		self._stale = false
		self:_rebuild()
	end)
end

-- === On a gamepad ===========================================================

local function centreX(gui: GuiObject): number
	return gui.AbsolutePosition.X + gui.AbsoluteSize.X / 2
end

--[[ The doors between the grid and the top bar. Header, "On a gamepad".

	The list's own `Selectable` goes off here: a ScrollingFrame is selectable by default, and the
	index measured the highlight parking on the well and staying there. ]]
function Page:_wireGamepad()
	if self.List then
		self.List.Selectable = false
	end
	for _, control in { self.SearchBox, self.CloseBtn } do
		if control then
			control.SelectionGained:Connect(function()
				self:_refreshDoors()
			end)
		end
	end

	--[[ The door back out of the right wing. Its button is a tagged kit button, so the highlight can
		reach it from the grid; what it cannot do on its own is find its way back in, which is the
		same engine limit the doors above exist for. ]]
	local wing = self._detail and self._detail.Action
	if wing and wing:IsA("GuiObject") then
		wing.SelectionGained:Connect(function()
			wing.NextSelectionLeft = self:_cardNearest(wing)
		end)
	end
end

--- The doors INTO the grid: the search box's down and the X's down. Cheap enough to redo whole.
function Page:_refreshDoors()
	for _, control in { self.SearchBox, self.CloseBtn } do
		if control then
			control.NextSelectionDown = self:_cardNearest(control)
		end
	end
end

--[[ The control a door into a card lands on: the card's verb, or its star when the verb is the grey
	face. Nil for a card with nothing to press, the LEAVE EMPTY card on a bay that is already empty. ]]
function Page:_doorControl(entry): GuiObject?
	for _, control in { entry.action, entry.star } do
		if control and control:IsA("GuiObject") and control.Visible then
			return control
		end
	end
	return nil
end

--- The highest pressable thing on a card: the star sits on the face, over the button.
function Page:_topControl(entry): GuiObject?
	for _, control in { entry.star, entry.action } do
		if control and control:IsA("GuiObject") and control.Visible then
			return control
		end
	end
	return nil
end

--[[ The card under `from` on the top row the window is showing, as its door control.

	A CARD'S PLACE ON SCREEN IS COMPUTED FROM ITS SLOT, NOT READ, the index's reason: `_applyFilter`
	asks this in the same frame it hides half the grid, before the layout has moved anything, so
	`AbsolutePosition` would still be describing the last search. The slot and `cellGeometry` are
	already the new layout. The grid is laid out from the top left (`BuildDealershipV2` leaves the
	kit's alignment), which is what the column arithmetic assumes. ]]
function Page:_cardNearest(from: GuiObject): GuiObject?
	local list = self.List
	local grid = self.Grid
	if not (list and grid) then
		return nil
	end
	local top = list.AbsolutePosition.Y
	local bottom = top + list.AbsoluteSize.Y
	local columns, pitch, cellHeight, padTop = self:cellGeometry()
	columns = math.max(1, columns)
	local padLeft = 0
	if self.Padding then
		local pad = self.Padding.PaddingLeft
		padLeft = pad.Scale * list.AbsoluteSize.X + pad.Offset
	end
	local originX = list.AbsolutePosition.X + padLeft + self._cellWidth / 2
	local strideX = self._cellWidth + grid.CellPadding.X.Offset
	local originY = top - list.CanvasPosition.Y + padTop + cellHeight / 2
	local target = centreX(from)

	local best, bestRow, bestDistance, bestOnScreen = nil, math.huge, math.huge, false
	for _, entry in self._entries do
		local control = entry.slot and self:_doorControl(entry)
		if not control then
			continue
		end
		local row = (entry.slot - 1) // columns
		local column = (entry.slot - 1) % columns
		local y = originY + row * pitch
		local onScreen = y >= top and y <= bottom
		local distance = math.abs(originX + column * strideX - target)
		local better = if onScreen ~= bestOnScreen
			then onScreen
			elseif row ~= bestRow then row < bestRow
			else distance < bestDistance
		if better then
			best, bestRow, bestDistance, bestOnScreen = control, row, distance, onScreen
		end
	end
	return best
end

--- The door OUT of the grid: whichever of the search box and the X is nearer across.
function Page:_topBarNearest(control: GuiObject): GuiObject?
	local target = centreX(control)
	local best, bestDistance = nil, math.huge
	for _, candidate in { self.SearchBox, self.CloseBtn } do
		if candidate and candidate.Visible then
			local distance = math.abs(centreX(candidate) - target)
			if distance < bestDistance then
				best, bestDistance = candidate, distance
			end
		end
	end
	return best
end

-- === Open and close =========================================================

--[[ Header note 1, the mode arbitration, and the only place either mode is entered. An open that a
	`DealershipBay` did not precede is a HUD open. ]]
function Page:StartOpenThread()
	local mode = if self._bayArmed then "bay" else "inventory"
	self._bayArmed = false

	--- Every open starts with nothing picked. See `_forget`.
	self:_forget()

	local changed = mode ~= self._mode
	self._mode = mode
	self:_applyMode()

	--[[ Rebuilt on a mode change because the LEAVE EMPTY card comes and goes with it; repainted
		otherwise, since the collection is watched and is already right. Either way the search is
		cleared: a query typed last time is a list that opens with most of the collection missing
		and no visible reason.

		`_query` IS CLEARED BY HAND as well as the box, StartCar's fix for StartCar's bug. The box's
		`Text` signal is deferred, so it lands after this open has already drawn the list by the old
		query: a reopen after a search opened on the cards that search left, or on none, until the
		signal caught up. And since the hand-cleared query makes that late signal a no-op, the
		repaint branch has to re-filter for itself when there was a query to undo. ]]
	local hadQuery = self._query ~= ""
	self._query = ""
	if self.SearchBox and self.SearchBox.Text ~= "" then
		self.SearchBox.Text = ""
	end
	--- `_stale`: the collection moved while the page was shut (`_requestRebuild`).
	if changed or self._stale then
		self._stale = false
		self:_rebuild()
	else
		if hadQuery then
			self:_applyFilter()
		end
		self:_refresh()
	end

	if self.List then
		self.List.CanvasPosition = Vector2.zero
	end
end

--[[ The viewport grid watches the page's own `Visible` and empties itself, so the cards need
	nothing here. The WINGS do: the rail is standing aside for them and should come back as the panel
	leaves rather than after it, and a car turning behind a closing page is work nobody can see.
	`suspend` is both, and the wings themselves go out on the page's own tween. ]]
function Page:StartCloseThread()
	if self._detail then
		self._detail:suspend()
	end
end

return Page
