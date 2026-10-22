--[[
	PlaytimeRewardConfig
	--------------------
	PLAYTIME GIFTS (2026-10-19): free gifts that unlock as a player keeps playing, claimed off a gift
	button on the topbar that counts down to the next one. Added for session length: the median
	session was about ten minutes and the tutorial finishes around minute five or six, so the game
	needed something that says "stay a bit longer" past it. The last gift is a car, at thirty minutes.

	=== THREE THINGS TO KNOW =================================================================

	1. THE CLOCK IS THE DAY'S, NOT THE SESSION'S. Minutes add up across every session in one UTC day
	   (the quest board's day, `QuestConfig.dayIndex`) and the ladder starts again tomorrow. Per
	   session, a rejoin would reset the ladder and the thirty-minute car could be farmed by quitting.
	   Per day, it is a daily habit with a car at the end of it, which is the same bargain the daily
	   calendar makes.

	2. A GIFT IS PRICED BY THE DAILY CALENDAR'S RULES (`DailyRewardService.priceSpec`, the same specs:
	   `Cash` with `Floor` and `Hours`, `Revive`, `Car` with `FromTop`). So a gift is "a quarter hour
	   of your dealership", not a fixed number that is a jackpot on day one and nothing a month in,
	   and both reward systems move together when the economy is retuned. They are smaller than the
	   calendar's on purpose: these come every day, six of them.

	3. GIFTS ARE CLAIMED IN ORDER, ONE PRESS EACH. A gift left unclaimed waits (it is not lost to the
	   next one coming due), and a press always takes the oldest one ready. The press is the moment
	   worth having; paying silently would teach nobody that the button exists.

	`Enabled = false`: no button, no claims, and the saved record left as it was.
]]

local PlaytimeRewardConfig = {}

PlaytimeRewardConfig.Enabled = true

--- Top-level profile key: `{ Day = <UTC day>, Seconds = <played that day>, Claimed = <gifts taken> }`.
PlaytimeRewardConfig.ProfileKey = "PlaytimeGifts"

--[[ The ladder, by minutes played today. Front-loaded: the first gift lands during the tutorial so
	the button is noticed, and the gaps widen as the session goes on, which is the shape that keeps a
	player for "just one more". The car at 30 is `FromTop` rungs under the top car of their highest
	world, one rung lower than the calendar's day 7 (`FromTop = 1`), because this one comes daily. ]]
PlaytimeRewardConfig.Gifts = {
	--- 2026-10-19: a one-minute gift, so the first one is open before the tutorial is, and the panel
	--- the tutorial ends on has a CLAIM on it rather than six clocks.
	{ Minutes = 1, Kind = "Cash", Floor = 1000, Hours = 0.05 }, -- 2026-10-19: Floor WAS 100; a first gift worth opening
	{ Minutes = 3, Kind = "Cash", Floor = 1500, Hours = 0.1 }, -- WAS 250
	{ Minutes = 7, Kind = "Cash", Floor = 2000, Hours = 0.2 }, -- WAS 500
	{ Minutes = 12, Kind = "Revive", Amount = 1 },
	{ Minutes = 20, Kind = "Cash", Floor = 3000, Hours = 0.5 }, -- WAS 1500
	{ Minutes = 30, Kind = "Car", Amount = 1, Body = "Charger", FromTop = 2 },
}

--[[ Seconds between the server writing the day's played time into the profile. It is also written
	on every claim and when the player leaves, so this only bounds what a crashed server can lose:
	at most this many seconds of one player's progress towards a gift. ]]
PlaytimeRewardConfig.SaveInterval = 60

PlaytimeRewardConfig.Remotes = {
	State = "PlaytimeGiftState", -- server -> client: the ladder (see `PlaytimeRewardService._payload`)
	Claim = "PlaytimeGiftClaim", -- client -> server: "claim the oldest gift that is ready", nothing else
}

--[[ THE TUTORIAL ENDS ON THE GIFTS (2026-10-19). When the finish card comes down, the FREE GIFTS
	panel opens (`AfterTutorialEvent`, published by `TutorialController`), so a new player learns the
	button exists with a gift already waiting on it (the one-minute one); and only when they close it
	does Play start calling for the next run, arrow and all (`RaceConfig.PlayBeckon`). False: the
	tutorial's finish beckons Play itself, the moment its card lands, as before. ]]
PlaytimeRewardConfig.ShowAfterTutorial = true
PlaytimeRewardConfig.AfterTutorialEvent = "PlaytimeGiftsAfterTutorial"

--- The topbar button (`TopbarController`): after Daily Reward (4), with the shop's bare gift glyph.
PlaytimeRewardConfig.Topbar = { Order = 5, Caption = "Free Gifts" }

PlaytimeRewardConfig.Text = {
	--- The label while counting down, minutes and seconds to the next gift.
	Countdown = "%d:%02d",
	Ready = "CLAIM!",
	Done = "Come back tomorrow",
	--- The panel (`PlaytimeRewardController`): its title, the line under it, and a tile's words.
	Title = "FREE GIFTS",
	Subtitle = "Keep playing to unwrap them all!",
	Claim = "CLAIM",
	--- A gift that is due but waits for the one before it: they open in order (header note 3).
	Next = "NEXT",
	Cash = "+%s",
	Revive = "+%d REVIVE",
	Car = "FREE %s!",
}

return PlaytimeRewardConfig
