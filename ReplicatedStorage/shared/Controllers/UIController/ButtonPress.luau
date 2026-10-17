--[[
	ButtonPress  (client)
	---------------------
	What pressing a tagged `UIButton` MEANS, in one place.

	It was inside `Components/Button` until a controller shortcut needed the same thing: a face
	button bound straight to the Play button has to do exactly what pressing Play does, or the two
	drift the first time somebody adds a third attribute and only updates one of them. So the two
	attributes and the click sound live here and both callers go through it.

	The attributes are `Components/Button`'s to document — this only acts on them:

		Page    string   the page it opens (`KeepPagesOpen` = comma-separated list to leave open)
		Action  string   published on `Dispatcher` as `UIAction`, for a button that DOES something

	`Action` is PUBLISHED, not called: whoever owns the verb subscribes to it, and the button rides
	along as the second argument for a listener that wants to grey it out. See `RaceEntryController`
	for the "EnterRace" end of it.

	=== ONE THING MAY REFUSE A PRESS ==========================================================

	The onboarding, while it is holding a player on a beat that names one button (`TutorialConfig`,
	`Gate = "Input"`). Every other tagged button is refused for the length of that beat, and this is
	where the refusal happens — because this is where a press MEANS something, and the two other
	places it could have gone are both worse:

	  • `Active = false` on the button. It stops the button reacting and it does NOT let the click
	    through to anything behind, which was measured rather than assumed: with the rail buttons
	    inactive, a click on one reached nothing at all. So the refusal worked and there was no way
	    left to say anything about it.
	  • A full-screen catcher over the top. It cannot have a hole in it, so the one button that is
	    supposed to work would be covered too.

	Refusing HERE also means the gamepad shortcut is covered by construction — `Components/GamepadNav`
	presses through this same function, so a face button cannot do what a mouse is being refused.

	A BUTTON CARRYING `TutorialExempt` IS NEVER REFUSED (2026-10-15). There is one: the random car
	card's ODDS button. The card is not under the gate (its buy buttons press `RandomCarController`
	directly), and Roblox's paid random items policy wants the odds reachable whenever a pull can be
	bought, so the way to them cannot be the one part of the card the onboarding shuts. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local UIControllerTypes = require(script.Parent.UIControllerTypes)

local SoundController -- resolved lazily; sounds no-op until the controller exists
local TutorialController -- likewise; there is no gate at all until the onboarding exists

local ButtonPress = {}

function ButtonPress.press(UIController: UIControllerTypes.UIController, instance: GuiObject)
	--[[ ASKED BEFORE THE SOUND, so a refused press is silent. A click noise followed by nothing
		happening is the sound of a broken button; silence plus the arrow jumping is a redirection.

		`blocksPress` does the bumping itself — this only has to not act. Looked up lazily and
		tolerated missing, so a place without the onboarding, or one where it is switched off, runs
		this function exactly as it was before the gate existed. ]]
	TutorialController = TutorialController or Shard.get("TutorialController")
	if TutorialController and instance:GetAttribute("TutorialExempt") ~= true and TutorialController:blocksPress(instance) then
		return
	end

	SoundController = SoundController or Shard.get("SoundController")
	if SoundController then
		SoundController:PlayRandom("UIClick")
	end

	local pageToOpen = instance:GetAttribute("Page")
	if pageToOpen then
		local keepPagesOpen = instance:GetAttribute("KeepPagesOpen")
		if keepPagesOpen then
			keepPagesOpen = string.split(keepPagesOpen, ",")
		end
		UIController:openPage(pageToOpen, { keepPagesOpen = keepPagesOpen })
	end

	local action = instance:GetAttribute("Action")
	if action then
		Dispatcher:Publish("UIAction", action, instance)
	end
end

return ButtonPress
