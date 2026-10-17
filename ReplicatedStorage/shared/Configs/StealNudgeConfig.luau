--[[
	StealNudgeConfig
	----------------
	The quiet line that reminds a driver the game is about STEALING cars, for the player who has been
	cruising so long they have forgotten. `StealNudgeController` draws it.

	TWO REASONS IT SPEAKS, AND BOTH ARE RARE ON PURPOSE:

	  • Idle. A run with no steal at all, after `Idle.First` seconds of real driving. It can repeat
	    every `Idle.Every` seconds, but only while the player is still in the car they started in.
	    Once they have taken one car they clearly know the verb, and the idle line never speaks again
	    that run.
	  • Nice car. A car ahead that is a better rarity than the one being driven, and at least
	    `NiceCar.MinBand`. This one can speak after a steal too, because "that one is better than
	    yours" is news whatever you are driving.

	THE CAP IS THE WHOLE POINT. Some players just want to drive far, and that is a fine way to play.
	`MaxPerRun` is shared by both reasons, so a whole run that never steals hears at most that many
	short lines and then nothing. `Cooldown` keeps any two of them apart.

	THE CLOCK IS DRIVING TIME, NOT WALL TIME. It only runs while the car is actually moving under the
	player: not behind the entry fade, not while frozen, not mid-jump, not wrecked, and never during the
	tutorial (which already tells the player to steal, at length).
]]

local StealNudgeConfig = {}

--- Master switch. Off = the controller builds nothing and the race is exactly as before.
StealNudgeConfig.Enabled = true

--- Most nudges in one run, both reasons together. The answer to "they just want to drive".
StealNudgeConfig.MaxPerRun = 3

--- Driving seconds between any two nudges.
StealNudgeConfig.Cooldown = 60

--- Below this speed (studs/s) the clock does not run. Cruise is about 85.
StealNudgeConfig.MinSpeed = 20

-- === Idle: no steal yet this run ============================================

StealNudgeConfig.Idle = {
	Enabled = true,
	--- Driving seconds into a run with no steal before the first line.
	First = 45,
	--- Driving seconds between repeats while there is still no steal.
	Every = 90,
	--- Said in order, one per nudge, wrapping. Sentence case: this is a nudge, not an alarm.
	Lines = {
		"Don't forget to steal a car!",
		"Jump onto a car ahead to steal it.",
		"Better cars are out there. Go steal one!",
	},
}

-- === Nice car: a better ride is right ahead =================================

StealNudgeConfig.NiceCar = {
	Enabled = true,
	--- Lowest rarity band worth calling out (`CarRarity`: 1 Beater .. 5 Supercar). It also has to beat
	--- the band of the car being driven, so a Supercar driver is never told about a Sports car.
	--- Coupe and up: the first stretch of a world only rolls bands 1 and 2, so this is "you have
	--- driven far enough that the good stuff is showing up".
	MinBand = 3,
	--- Driving seconds since the run started or the last steal before this can speak, so it never
	--- talks over the STOLEN! toast or the first beats of a run.
	Quiet = 20,
	--- The window ahead of the driver (studs along the road) a car has to be in. Far enough that
	--- there is time to react, near enough that it is on screen.
	MinAhead = 70,
	MaxAhead = 260,
	--- `%s` is the car's name, drawn in its rarity colour.
	Line = "%s ahead. Steal it!",
}

-- === What it looks like =====================================================

StealNudgeConfig.Ui = {
	--- Screen position (scale) of the line's centre. Under the STOLEN! toast (0.24), over the pickup
	--- toast (0.36), which is never on screen at the same moment as a nudge anyway.
	Position = Vector2.new(0.5, 0.295),
	--- Width and height as a share of the screen. The text scales into it and caps at `MaxTextSize`.
	Size = Vector2.new(0.6, 0.04),
	MaxTextSize = 26,
	TextColor = Color3.fromRGB(255, 255, 255),
	StrokeColor = Color3.fromRGB(10, 10, 18),
	--- The stroke is softer than the toasts' so the line reads as a whisper next to them.
	StrokeTransparency = 0.3,
	--- Pixels the line rises through as it fades in.
	Rise = 10,
	FadeIn = 0.35,
	Hold = 3.5,
	FadeOut = 0.6,
	--- How fast it gets out of the way once the player jumps or steals.
	FadeOutQuick = 0.2,
}

return StealNudgeConfig
