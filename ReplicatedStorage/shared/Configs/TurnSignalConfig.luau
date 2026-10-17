--[[
	TurnSignalConfig
	----------------
	The player's own indicators: a key for left, a key for right, and the car's lamps on that side
	flash amber until the turn is made. Traffic has had them since 2026-09-17
	(`TrafficConfig.Blinkers`, which is also the LOOK these use: the same amber twin of the same
	lamps, so the car you stole indicates exactly the way it did in front of you). What is decided
	here is only how the player asks for one and when it goes out again.

	=== THE KEYS ARE Z AND C, NOT Q AND E, AND HERE IS WHY ======================================

	Q and E were the first choice and both are spoken for during a race: Q spends the pickup slot
	(`PickupConfig.Keys`) and E is the steal out of the air (`StealConfig.Prompt.Keys`) as well as
	the stock chassis's exit key (`DriveConfig.ExitKeys`). Binding an indicator over either would
	sink the other verb on every press. Z and C flank X under the driving cluster, are reached
	without leaving WASD, and nothing else in the game binds them. Should the pickup ever move off
	Q, swapping these two lists is the whole change: the binding, the legend row and the touch
	buttons all read from here.

	The D-pad halves are free during a race (the rail's focus keys stand down for its length,
	`GamepadConfig.FocusKeys`), and the pad legend draws them off the same lists.

	=== A STALK, NOT A HOLD ====================================================================

	One press turns the signal on, the same press turns it off, the other side's press swaps it.
	It then CANCELS ITSELF the way a real stalk does, off the steering: once the player has steered
	the signalled way past `SteerThreshold` and let the input fall back under `ReleaseThreshold`,
	the lane change is done and the lamp goes out. `MaxSeconds` catches the signal nobody acted on.
	A bail, a wreck and a tutorial freeze all cancel it too, because there is no driver.

	=== TOUCH ==================================================================================

	Two `ContextActionService` buttons, which is the minimal on-screen control Roblox offers: no
	authored art, gone with the binding at the end of the race, and only ever created on a touch
	device. They are parked just above the steering arrows on their own side of the screen, sized
	off those arrows, so the thumb that steers left finds the left indicator above it. The rest of
	the driving HUD (`DrivingHudController`) is untouched.
]]

local TurnSignalConfig = {}

TurnSignalConfig.Enabled = true

TurnSignalConfig.Keys = {
	Left = { Enum.KeyCode.Z, Enum.KeyCode.DPadLeft },
	Right = { Enum.KeyCode.C, Enum.KeyCode.DPadRight },
}

--- Bound above the stock `Driver` and sunk, on the same argument `NitroConfig.BindPriority`
--- makes: its Keymap does not name these keys today, and this keeps that true tomorrow.
TurnSignalConfig.BindPriority = Enum.ContextActionPriority.High.Value + 500

TurnSignalConfig.AutoCancel = {
	Enabled = true,
	MaxSeconds = 8,
	SteerThreshold = 0.5,
	ReleaseThreshold = 0.1,
}

TurnSignalConfig.Touch = {
	--- OFF since 2026-10-06 (Leaf, on a phone: "why is there 2 arrows on the left", "we do not need
	--- the blinkers"). Two more arrows above the steering arrows read as a second pair of steering
	--- buttons. Z and C still signal, and traffic keeps its own blinkers.
	Enabled = false,
	Titles = { Left = "←", Right = "→" },
	--- Where the buttons sit, measured off the driving HUD's own steering arrows: this many arrow
	--- heights above them, and this fraction of an arrow's height across.
	Above = 1.2,
	Size = 0.72,
	--- Where they sit when there are no steering arrows to measure off, as fractions of the
	--- viewport (centre) and of its height (size).
	Fallback = {
		Left = Vector2.new(0.0975, 0.74),
		Right = Vector2.new(0.2031, 0.74),
		Size = 0.09,
	},
}

return TurnSignalConfig
