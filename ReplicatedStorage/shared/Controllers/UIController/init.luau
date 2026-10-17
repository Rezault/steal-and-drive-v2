--[[
	UIController  (client)
	----------------------
	Owns which page is on screen. Loads every module under `Pages`, every behaviour module under
	`Components`, and routes open/close — from a `Dispatcher` event, from a tagged button, or from a
	direct call — through one scale tween.

	Ported from NeedohEscape, which is the structure the boss wants us on. Three things carry over
	and are the reason it is worth having at all.

	1. NOTHING WIRES A BUTTON TO A PAGE IN CODE. Tag a GuiButton `UIButton`, give it a `Page`
	   attribute, and it opens that page. Adding a screen means adding a module under `Pages` and
	   typing a page name into an attribute in the Explorer — no controller edit, no require, no
	   registration list to forget. See `Components/Button`.

	2. OPENING A PAGE CLOSES THE OTHERS. That is the default because two of these panels overlap
	   almost exactly, and two visible at once reads as a bug. A page can opt out with `StayOpen`,
	   and a caller can name exceptions via `data.keepPagesOpen`.

	3. THE TWEEN LIVES HERE, NOT IN THE PAGES. Every page scales from 0.9 on a Back ease and
	   collapses on a Quad, so they all feel like the same object. A page that needs something
	   different defines `Open`/`Close` and this steps aside entirely.

	Pages bind in `start`, never `init`: the page modules yield on PlayerGui contents, and a
	yielding `init` dies silently in this project's boot sequence.

	=== THERE ARE TWO SETS OF PAGES NOW =======================================================

	`Pages` is the UI the game ships with. `PagesV2` is the Cartoony Kit one being built behind
	`NewUIConfig.Enabled`, and `Modules/UIRoot` answers which of the two is loaded. Everything above
	is true of both: the same tag opens them, the same tween runs, and the page NAMES are the same in
	either folder, so nothing that names a page by string has to know which UI is up.

	The two are separate modules rather than one set with branches in it. The old pages read a layout
	the kit does not have, and the reason the flag exists at all is to keep the shipping UI out of
	the way of the new one. See `docs/NewUI-Migration-Plan.md`.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)
--- `LockedInTutorial` and the tutorial's step, for the cars screen's gate in `openPage`.
local InventoryConfig = require(ReplicatedStorage.shared.Configs.InventoryConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)

local OPEN_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local START_SCALE = 0.9

--[[ How long the loader waits on one page before it moves on to the next. A page binds in a frame
	when its frame is there; this is only ever reached by one that is waiting on something that is not
	coming. See `_loadPage`. ]]
local PAGE_LOAD_TIMEOUT = 5

--- The name this file asks `RaceEntryController` to move the Play button under. See `_syncPlayRoom`.
local PLAY_ROOM_SOURCE = "Pages"

local UIController = Shard.new(script.Name):withLifecycle({
	init = function(self)
		--- The pages opened and not yet closed, by name. What `_syncPlayRoom` counts.
		self._openPages = {} :: { [string]: boolean }
		self._playRoomAsked = false
	end,
	start = function(self)
		self:_setupDispatchers()
		self:_setupComponentsAndPreload()
	end,
})

function UIController:_setupDispatchers()
	Dispatcher:Subscribe("OpenPage", function(pageName: string, data: any?)
		self:openPage(pageName, data)
	end)
	Dispatcher:Subscribe("ClosePage", function(pageName: string)
		self:closePage(pageName)
	end)
	Dispatcher:Subscribe("CloseAllPages", function()
		self:closeAllPages()
	end)
end

function UIController:openPage(pageName: string, data: any?)
	local page = self.pages[pageName]
	if not page then
		return false
	end
	--- The cars screen stays shut for the tutorial (`InventoryConfig.LockedInTutorial`). Here, at the
	--- one door every page comes through, so no button or prompt can open it around the rule.
	if pageName == InventoryConfig.PageName and InventoryConfig.LockedInTutorial
		and TutorialConfig.isUnfinished(Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute)) then
		return false
	end

	local keepPagesOpen = data and data.keepPagesOpen or {}

	for _, otherPage in self.pages do
		if otherPage ~= page and otherPage.PageUI and otherPage.PageUI.Visible and not otherPage.StayOpen then
			local shouldKeepOpen = false
			for _, keepPageName in keepPagesOpen do
				if otherPage.PageUI.Name == keepPageName then
					shouldKeepOpen = true
					break
				end
			end
			if not shouldKeepOpen then
				--- The quiet close: this page's own open decides where Play goes, once, below.
				self:_closePage(otherPage.PageUI.Name)
			end
		end
	end

	if page.StayOpen and page.PageUI.Visible then
		if type(page.Open) == "function" and data then
			page:Open(data)
		end
		self:_syncPlayRoom()
		return true
	end

	-- Pressing a page's own button again puts it away. The rail buttons are the only way in and
	-- the only way back out for a player who never finds the X.
	if self.currentPage == pageName or page.PageUI.Visible then
		self:_closePage(pageName)
		self:_syncPlayRoom()
		Dispatcher:Publish("PageClosed", pageName)
		return true
	end

	-- `type` and not truthiness: `Open`/`Close` are also the obvious names for a page's own close
	-- BUTTON, and a page that parks the instance there would otherwise call it.
	if type(page.Open) == "function" then
		page:Open(data)
	else
		if page.StartOpenThread then
			page:StartOpenThread()
		end

		local pageUI = page.PageUI

		if page._scaleTween then
			page._scaleTween:Cancel()
		end

		pageUI.Visible = true
		page._pageScale.Scale = START_SCALE
		page._scaleTween = TweenService:Create(page._pageScale, OPEN_TWEEN, { Scale = 1 })
		page._scaleTween:Play()
	end

	self.currentPage = pageName
	self._openPages[pageName] = true
	self:_syncPlayRoom()
	--- For a panel that is not a page but stands where one does (the kit radio closes itself on it).
	--- After the Play request, and only for an open, never for the toggle-close above.
	Dispatcher:Publish("PageOpened", pageName)

	return true
end

function UIController:closePage(pageName: string)
	local closed = self:_closePage(pageName)
	self:_syncPlayRoom()
	--- `PageOpened`'s other half, for the car hotbar, which steps aside while a menu is up. Not sent
	--- for the quiet closes inside `openPage`: the `PageOpened` that follows them says it all.
	if closed then
		Dispatcher:Publish("PageClosed", pageName)
	end
	return closed
end

--- Is this page open? The open set again, so a page mid-close tween (still `Visible`) answers no.
function UIController:isPageOpen(pageName: string): boolean
	return self._openPages[pageName] == true
end

--- Is any page open, other than those named in `except`? Read off the open set rather than
--- `PageUI.Visible`, which stays true for the length of a close tween.
function UIController:anyPageOpen(except: { [string]: boolean }?): boolean
	for pageName in self._openPages do
		if not (except and except[pageName]) then
			return true
		end
	end
	return false
end

--[[ `closePage` without telling the Play button. `openPage` closes the other pages on its way to
	opening one, and a close that spoke up there would send Play back up and straight down again in
	the same frame. ]]
function UIController:_closePage(pageName: string)
	local page = self.pages[pageName]
	if not page then
		return false
	end
	self._openPages[pageName] = nil

	if type(page.Close) == "function" then
		page:Close()
	else
		if page.StartCloseThread then
			page:StartCloseThread()
		end

		local pageUI = page.PageUI

		if page._scaleTween then
			page._scaleTween:Cancel()
		end

		page._scaleTween = TweenService:Create(page._pageScale, CLOSE_TWEEN, { Scale = START_SCALE })
		page._scaleTween:Play()
		page._scaleTween.Completed:Once(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed and pageUI then
				pageUI.Visible = false
			end
		end)
	end

	if self.currentPage == pageName then
		self.currentPage = nil
	end

	return true
end

--[[ PLAY STEPS ASIDE WHILE A PAGE IS OPEN, on the new UI (Dylan, 2026-09-16).

	The kit's pages were made bigger for phones (`Modules/KitGrowth`), and at their new size a page
	runs past the top of the Play button. So while any page is open, Play slides off the bottom of the
	screen, and it slides back up once the last one closes. Switching straight from one page to another
	leaves it where it is.

	THE SLIDE IS NOT DRAWN HERE. `RaceEntryController` is the one writer of Play's `Visible`, and it
	already slides Play out of the way for a race and for the old Cars page; this only asks, under its
	own source name, so a race and a page can never disagree about the button.

	Published only on a change, and LAST in `openPage` and `closePage`, because `Publish` runs its
	listeners inline. The old UI keeps its own arrangement (its Cars page asks for itself). ]]
function UIController:_syncPlayRoom()
	if not UIRoot.isNewUI() then
		return
	end
	local anyOpen = next(self._openPages) ~= nil
	if anyOpen == self._playRoomAsked then
		return
	end
	self._playRoomAsked = anyOpen
	Dispatcher:Publish("SuppressPlayButton", anyOpen, PLAY_ROOM_SOURCE)
end

--[[ Put every page away.

	`openPage` already closes the others as a side effect of opening one, which covers every case
	where the player is going SOMEWHERE. This is the case where they are going nowhere and the screen
	has to be clear anyway: a race starts and none of the lobby's panels are part of it — see
	`RaceEntryController`, which is the only caller today.

	`StayOpen` is deliberately not honoured here. It means "do not close me just because something
	else opened", which is a statement about page-to-page traffic; it is not a claim to survive a
	run, and a page that stayed up over the road would be exactly the thing this is called to fix.

	Routed through `closePage` per page rather than hiding `Pages` wholesale so each one still gets
	its close tween and its own `Close`/`StartCloseThread` teardown — a page hidden behind its parent
	would come back mid-collapse the next time the lobby's HUD returned. ]]
function UIController:closeAllPages()
	for pageName, page in self.pages do
		if page.PageUI and page.PageUI.Visible then
			self:closePage(pageName)
		end
	end
end

function UIController:_setupComponentsAndPreload()
	self.Player = Players.LocalPlayer
	self.PlayerGui = self.Player:WaitForChild("PlayerGui")

	local Components = script:FindFirstChild("Components")
	if Components then
		for _, component in Components:GetChildren() do
			local componentModule = require(component)
			if componentModule and type(componentModule) == "function" then
				componentModule(self)
			end
		end
	end

	--[[ The UI is claimed here, before a page or a component looks anything up: `UIRoot.wait` enables
		the ScreenGui in use and destroys the other one, and doing it first means no observer, tag or
		lookup below can ever land in the UI that is not in play. See `Modules/UIRoot`. ]]
	UIRoot.wait(self.PlayerGui)

	self.pages = {}
	local pagesFolderName = UIRoot.pagesFolderName()
	local Pages = script:FindFirstChild(pagesFolderName)
	if not Pages then
		--- Ordinary while the new UI is being built: the flag can be on before `PagesV2` has a single
		--- page in it. A HUD with no pages behind it is a legible half-built state, not an error.
		warn(string.format("[UIController] No `%s` folder; no pages will be loaded.", pagesFolderName))
	end
	if Pages then
		for _, page in Pages:GetChildren() do
			self:_loadPage(page)
		end
	end

	-- The panel art is ~30 images the player has never seen before the first time they open a
	-- screen; without this the first open is a page assembling itself piece by piece.
	task.spawn(function()
		local assetsToPreload = {}

		for _, page in self.pages do
			if page.PageUI then
				for _, descendant in page.PageUI:GetDescendants() do
					if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
						table.insert(assetsToPreload, descendant)
					end
				end
			end
		end

		if #assetsToPreload > 0 then
			ContentProvider:PreloadAsync(assetsToPreload)
		end
	end)
end

--[[ Load one page module: require it, make it, initialize it, and give it the scale the tween drives.

	ONE PAGE MAY NOT STOP THE PAGES AFTER IT. They load one after another, and a page's `new` waits on
	its frame with no timeout of its own. A page module synced into the place before its frame was
	built waited forever, and every page after it in the folder never loaded at all; on 2026-09-16
	that hung three sessions' playtests at once. So each page runs in a thread of its own, the loop
	waits on it for `PAGE_LOAD_TIMEOUT` and then moves on with a warning naming it, and a page that
	THROWS is a warning too rather than the end of the loop.

	WHEN NOTHING GOES WRONG THIS IS THE OLD LOOP. `task.spawn` runs the thread straight away, so a page
	that never yields is loaded before this returns, in the same order as before.

	A SLOW PAGE STILL ARRIVES. Its thread is not cancelled, so a frame that turns up late binds late,
	through the same lines, and opens from then on; what it misses is the art preload, which has
	already gathered its list. A page that threw is taken back out of `pages`, so opening it is a
	`false` from `openPage` rather than a half-built page. ]]
function UIController:_loadPage(module: Instance)
	local name = module.Name
	local started = os.clock()
	local finished = false
	local late = false

	task.spawn(function()
		local ok, err = xpcall(function()
			self.pages[name] = require(module).new(self)

			local page = self.pages[name]
			if page then
				page:initialize()
				local pageUI = page.PageUI
				if pageUI then
					page._pageScale = pageUI:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", pageUI)
					page._pageScale.Scale = START_SCALE
				end
			end
		end, debug.traceback)

		finished = true
		if not ok then
			self.pages[name] = nil
			warn(string.format("[UIController] Page `%s` failed to load and was skipped: %s", name, tostring(err)))
		elseif late then
			warn(string.format("[UIController] Page `%s` loaded late, after %.1fs.", name, os.clock() - started))
		end
	end)

	while not finished and os.clock() - started < PAGE_LOAD_TIMEOUT do
		task.wait()
	end
	if not finished then
		late = true
		warn(
			string.format(
				"[UIController] Page `%s` is still loading after %ds (is its frame in the place?). Loading the pages after it without it.",
				name,
				PAGE_LOAD_TIMEOUT
			)
		)
	end
end

return UIController
