--[[
	UIVisibility
	------------
	WHEN A BUTTON ONTO A FEATURE IS WORTH DRAWING. Four questions, each answered from the feature's own
	config, in one place because two different layers of UI now ask them.

	=== WHY THIS IS NOT JUST A FEW LINES IN THE TOPBAR ========================================

	It was, until the Cartoony Kit migration. `TopbarController` owned all four rules inline, which was
	right while the topbar was the only thing that could draw a door onto the radio or the shop.

	The new HUD splits them across two layers (`docs/NewUI-Migration-Plan.md`, "The new HUD"): the
	topbar keeps what a driver reaches for mid-run, and the kit's side grid carries the rest. Shop is
	the one that crosses over. With the rules written twice, the day the shop's rule changes is the day
	the grid and the topbar disagree about whether there is a shop, and a player sees a button in one
	place and not the other. So the rules moved here and both layers read them.

	=== THE RULE BEHIND ALL FOUR RULES ========================================================

	A button onto something that can only refuse is worse than no button. That is the whole of this
	file, applied four times:

	  • The RADIO is sold from its own panel, so the button is there whether or not the player owns
	    the pass. What is hidden is a radio switched off or never synced, which `sellable()` covers.
	  • SETTINGS needs a screen with something on it. A build with the day and night cycle switched
	    off has an empty settings list, and an empty screen is a refusal with extra steps.
	  • The SHOP needs stock. Anything unsynced or unwired fails `isSellable`, and the cash rungs
	    alone are enough to earn the button, which is why all three tabs count.
	  • The MUSIC mute is only built when the radio panel it normally lives on cannot be reached, and
	    only when there is music to mute at all.

	None of the four is a live answer. Every input is config, decided before a player joins, so both
	the topbar and the HUD ask once at start and nothing subscribes. If any of them ever becomes a
	thing that changes mid-session, it needs a state event and both callers need to hear it, and that
	is the reason to say this out loud rather than leave it implied.

	=== `page` IS THE SAME QUESTION ASKED FROM THE OTHER END ==================================

	`Components/HudRules` walks a HUD rail and knows only that a button carries `Page = "Shop"`. It has
	no business knowing that a shop is a thing with stock, so it asks `page("Shop")` and gets an answer.
	A page with no rule is always shown, which is what makes the table below short: it lists the
	exceptions, not the pages.

	`action` is the same again for a button that carries an `Action` instead of a `Page`. The radio is
	the one that needs it: its panel is not a page, so the grid's Radio cell (2026-09-16) opens it
	with `RadioConfig.PanelAction`, and that cell has to go dark when the topbar chip would.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MusicConfig = require(ReplicatedStorage.shared.Configs.MusicConfig)
local RadioConfig = require(ReplicatedStorage.shared.Configs.RadioConfig)
local SettingsConfig = require(ReplicatedStorage.shared.Configs.SettingsConfig)
local ShopConfig = require(ReplicatedStorage.shared.Configs.ShopConfig)

local UIVisibility = {}

--- Is the radio reachable at all? See the header: the pass is sold on the panel, so owning it is not
--- the question and never has been.
function UIVisibility.radio(): boolean
	return RadioConfig.sellable()
end

--- Is there a settings screen with rows on it?
function UIVisibility.settings(): boolean
	return SettingsConfig.Enabled and SettingsConfig.hasRows()
end

--- Is there anything in the shop? Passes, bundles, or a cash pack with a real product behind it.
function UIVisibility.shop(): boolean
	if #ShopConfig.visiblePasses() > 0 or #ShopConfig.visibleBundles() > 0 then
		return true
	end
	for _, pack in ShopConfig.cashPacks() do
		if pack.ProductId ~= 0 then
			return true
		end
	end
	return false
end

--[[ Does the mute need a home of its own? Only when the radio panel it lives on is unreachable, and
	only when there is a soundtrack to mute: the switch in `MusicConfig` is meant to take the whole
	feature out, and a mute on a game with nothing playing is worse than no mute. ]]
function UIVisibility.music(): boolean
	return MusicConfig.Enabled and not UIVisibility.radio()
end

--[[ The pages that have a rule. Everything not in here is always shown, which is every page in the
	game except this one: Index, Quest, Market, Dealership, Teleport and StartCar are all features the
	player owns from the first second and none of them can be switched off from a config.

	Keyed by the string a HUD button carries in its `Page` attribute, because that is all the caller
	has. `SettingsConfig.PageName` rather than the literal for the same reason `TopbarController` uses
	it: the settings page is the one whose name is configurable. ]]
local PAGE_RULES: { [string]: () -> boolean } = {
	Shop = UIVisibility.shop,
	[SettingsConfig.PageName] = UIVisibility.settings,
}

--- Should a button onto this page be drawn? A page with no rule always answers yes. See the header.
function UIVisibility.page(name: string): boolean
	local rule = PAGE_RULES[name]
	if not rule then
		return true
	end
	return rule()
end

--- The actions that have a rule, keyed by the string a HUD button carries in its `Action` attribute.
--- Everything else (Play's `EnterRace`, a world card's teleport) is always shown.
local ACTION_RULES: { [string]: () -> boolean } = {
	[RadioConfig.PanelAction] = UIVisibility.radio,
}

--- Should a button carrying this action be drawn? An action with no rule always answers yes.
function UIVisibility.action(name: string): boolean
	local rule = ACTION_RULES[name]
	if not rule then
		return true
	end
	return rule()
end

return UIVisibility
