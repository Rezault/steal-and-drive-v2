--[[
	ApplyFeedbackSfx, a Command Runner command (A0 on the Aleafo punch list, 2026-10-12)

	Gives each named feedback cue its own clip. The list is `CLIPS` below and it is the whole command;
	everything else here is checking and reporting.

	=== WHY ===================================================================================

	Aleafo said the game was missing a lot of SFX. An audit of every `Sound = { Group, Name }` in the
	configs, every literal `PlayRandom` / `PlayNamed` call and every `GameplayFeedback` cue found NOTHING
	missing: all 70 clips exist under SoundService and all of them load. What was actually wrong is that
	the Codex batch filled its cues with clips the place already had ("Clips use existing place audio and
	are independently replaceable", `FeedbackAudioConfig`), so twenty different moments shared five
	sounds. `Roblox_UI_Tonal_Stinger` played for eight of them and `reward_screen_reveal` for six. A sound
	you have already heard for something else does not read as feedback, so it reads as missing.

	Two cues were also nearly silent. `Buyer.Sold` and `DailyClaimed` both used `RBLX UI Purchase`, whose
	loudest RMS is 0.054 against the UI click's 0.21, under a 0.5 group: the sell sound was about a fifth
	as loud as clicking the button that triggered it.

	=== HOW THE CLIPS WERE PICKED =============================================================

	Toolbox only, and only from the licence-safe libraries: Roblox's own uploads (the 2024 "Roblox GUI -"
	set, the "Roblox_UI_" and Pinball sets) and verified Pro Sound Effects. Each candidate was measured in
	edit mode through AudioPlayer > Wire > AudioAnalyzer (onset, peak time, loudest RMS, dominant-bin
	contour), since a cue that fires on an event has to sound on that frame.

	`Volume` is set from the measured RMS, aiming at an effective level (Volume x group Volume x RMS)
	next to the UI click's 0.053: about 0.08 for a reward, 0.05 for a notification, 0.03 to 0.045 for
	small confirmations. `StartAt` trims a Pro Sound Effects lead-in, and it only works on the
	`GameplayFeedback` group: `GameplayFeedback.play` honours it, while `SoundController:PlayNamed` goes
	through `PlayLocalSound`, which cannot seek. So every `PlayNamed` row below uses a clip that starts on
	frame one.

	=== WHAT IT TOUCHES =======================================================================

	`SoundId`, `Volume` and the `StartAt` attribute on the Sounds named in `CLIPS`, nothing else. The
	old id and volume are stamped on each Sound as `A0OldSoundId` / `A0OldVolume` the first time it is
	changed, and `Revert` puts them back. IDEMPOTENT: a Sound already on its new id reports `already`.
	`TutorialComplete`, `NewBest` and the crash groups keep their clips on purpose; the reveal stinger
	now belongs only to the two big reveals.
]]

local SoundService = game:GetService("SoundService")

local Types = require(script.Types)

-- stylua: ignore
local CLIPS = {
	-- PlayNamed groups: the clip must start on frame one.
	{ group = "Buyer", name = "GreatOffer", id = 17208361335, volume = 0.48, clip = "Roblox GUI - Notification High" },
	{ group = "Buyer", name = "Sold", id = 99366249808641, volume = 0.54, clip = "TutorialPurchase_01 (Roblox)" },
	{ group = "UI", name = "Denied", id = 17208353912, volume = 0.6, clip = "Roblox GUI - Negative" },
	{ group = "Upgrade", name = "Upgraded", id = 16480578169, volume = 0.8, clip = "Roblox_Pinball_8Bit_Riser_01" },
	{ group = "Collection", name = "Discovered", id = 9116394876, volume = 2.5, clip = "Magic Glows Soft Clusters Of Chiming Hits 2 (SFX)" },
	{ group = "Steal", name = "RareSpotted", id = 15675085146, volume = 0.7, clip = "Roblox_UI_Indicator" },
	-- A5 (2026-10-13): player requests, played by `PickupConfig.Packs.<name>.Sound` in place of the
	-- shared stinger. Both groups (Volume 0.5) and Sounds were created in the place by hand; these rows
	-- keep the clips on record. The ratchet sounds at 0.07 s and is gone by 0.24 s, RMS 0.30. The air
	-- brake is a single burst peaking at 0.13 s, RMS 0.05, so it carries a big Volume, and it is set to
	-- PlaybackSpeed 1.2 by hand (this command does not write speed) so it reads as a car's blow-off
	-- valve rather than a bus.
	{ group = "PickupRepair", name = "PickupRepair1", id = 9118043651, volume = 0.53, clip = "Ratchet Sharp Turn 1 (SFX)" },
	{ group = "PickupTurbo", name = "PickupTurbo1", id = 9113052763, volume = 3.1, clip = "Air Brakes Bus Truck Several Bursts 2 (SFX)" },

	-- GameplayFeedback: `StartAt` is honoured here.
	{ group = "GameplayFeedback", name = "TutorialStep", id = 17208204604, volume = 0.7, clip = "Roblox GUI - Bubble" },
	{ group = "GameplayFeedback", name = "Parked", id = 9114307927, volume = 1.1, startAt = 0.18, clip = "Emergency Brake 1 (SFX)" },
	{ group = "GameplayFeedback", name = "OfferArrived", id = 17208372272, volume = 0.33, clip = "Roblox GUI - Notification Low" },
	{ group = "GameplayFeedback", name = "StealReady", id = 17208323435, volume = 0.5, clip = "Roblox GUI - Equip" },
	{ group = "GameplayFeedback", name = "NitroReady", id = 9125648149, volume = 0.55, clip = "Magic Zoom Up Sharp Tubular Whoosh Fast Hiss (SFX)" },
	{ group = "GameplayFeedback", name = "RampCaptured", id = 9125585029, volume = 0.25, clip = "Go Cart Drop Hitting Ground Big Metal Clunki (SFX)" },
	{ group = "GameplayFeedback", name = "Docked", id = 9125626478, volume = 2, clip = "Lever Mechanism Crank Clicks Big Metal Clunk (SFX)" },
	{ group = "GameplayFeedback", name = "ComboLost", id = 15675062723, volume = 0.35, clip = "Roblox_UI_Whistle_Low" },
	{ group = "GameplayFeedback", name = "LuckRaised", id = 9119833603, volume = 0.9, startAt = 0.22, clip = "Synth Sparkle Tone High Pitch Tone Burst 2 (SFX)" },
	{ group = "GameplayFeedback", name = "EventStarted", id = 9114302200, volume = 0.9, startAt = 0.12, clip = "Elevator Bell Synth Chimes 4 (SFX)" },
	{ group = "GameplayFeedback", name = "Revived", id = 17208327798, volume = 0.72, clip = "Roblox GUI - Aura" },
	{ group = "GameplayFeedback", name = "RandomResolved", id = 9125485591, volume = 0.8, startAt = 0.18, clip = "Desk Bell Counter Service Single Ringing Ding (SFX)" },
	{ group = "GameplayFeedback", name = "DailyClaimed", id = 127645268874265, volume = 1, clip = "CoinTransfer_01 (Roblox)" },
}

return {
	Description = "Gives each feedback cue its own measured toolbox clip (punch list A0).",
	Tags = { "audio", "sfx" },
	AutoRecordChanges = true,

	Arguments = {
		DryRun = {
			Type = "boolean",
			Default = false,
			Description = "Report what would change without touching anything.",
			LayoutOrder = 1,
		},
		Revert = {
			Type = "boolean",
			Default = false,
			Description = "Put back the clip and volume each Sound had before this command first ran.",
			LayoutOrder = 2,
		},
	} :: Types.ArgumentType,

	Run = function(props: Types.Props, arguments: Types.ArgumentResult)
		local out = props:Output()
		out:clear()
		local dry = arguments.DryRun == true
		local revert = arguments.Revert == true
		local counts = {}

		for _, row in CLIPS do
			local group = SoundService:FindFirstChild(row.group)
			local sound = group and group:FindFirstChild(row.name)
			local state
			if not (sound and sound:IsA("Sound")) then
				state = "missing"
			elseif revert then
				local oldId = sound:GetAttribute("A0OldSoundId")
				if type(oldId) ~= "string" then
					state = "never applied"
				else
					state = "reverted"
					if not dry then
						sound.SoundId = oldId
						sound.Volume = sound:GetAttribute("A0OldVolume") or sound.Volume
						sound:SetAttribute("StartAt", sound:GetAttribute("A0OldStartAt"))
						sound:SetAttribute("A0OldSoundId", nil)
						sound:SetAttribute("A0OldVolume", nil)
						sound:SetAttribute("A0OldStartAt", nil)
					end
				end
			else
				local newId = "rbxassetid://" .. row.id
				if sound.SoundId == newId and sound.Volume == row.volume and sound:GetAttribute("StartAt") == row.startAt then
					state = "already"
				else
					state = "applied"
					if not dry then
						if sound:GetAttribute("A0OldSoundId") == nil then
							sound:SetAttribute("A0OldSoundId", sound.SoundId)
							sound:SetAttribute("A0OldVolume", sound.Volume)
							sound:SetAttribute("A0OldStartAt", sound:GetAttribute("StartAt"))
						end
						sound.SoundId = newId
						sound.Volume = row.volume
						sound:SetAttribute("StartAt", row.startAt)
					end
				end
			end
			counts[state] = (counts[state] or 0) + 1
			out:print(string.format("%-8s %s.%s  %s", state, row.group, row.name, if revert then "" else row.clip))
		end

		local summary = {}
		for state, n in counts do
			table.insert(summary, string.format("%d %s", n, state))
		end
		table.sort(summary)
		out:print(string.format("%s %s.", if dry then "Would do:" else "Done:", table.concat(summary, ", ")))
	end,
} :: Types.ScriptModule
