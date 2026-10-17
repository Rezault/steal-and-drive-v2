--[[
	DailyRewardConfig
	-----------------
	THE DAILY REWARD (2026-10-06): a seven-day calendar. Come back on a new day, press CLAIM on that
	day's card, get its reward; come back the next day for the next one. Day 7 is the big one, and the
	week then starts over. `DailyRewardService` owns the record and every payout; `DailyRewardController`
	holds the state and opens the screen; `PagesV2/DailyRewards` draws it on the Quest page's own kit
	art (`BuildDailyRewardsV2`), so it is the same panel, cards, buttons and clock the player already
	knows from the quest board.

	=== FOUR THINGS TO KNOW BEFORE TUNING IT =====================================================

	1. THE DAY IS THE QUEST BOARD'S DAY (`QuestConfig.dayIndex`, UTC midnight), so a returning player's
	   new quests and new reward arrive together, and there is one "tomorrow" in the game, not two.

	2. A MISSED DAY RESETS THE STREAK (`ResetOnMiss`). That is what makes day 7 worth coming back for
	   every day rather than any seven days. `false` makes it a plain calendar that waits for you.

	3. CASH SCALES WITH THE PLAYER (`Cash`: the greater of a floor and `Hours` of what their lot earns
	   offline per hour, `OfflineConfig.Label`). A fixed $2,500 is a jackpot on day one and nothing a
	   month in; "an hour of your dealership" is the same reward at every stage of the game. The floor
	   is the early game's number, where the lot earns little. Rounded to a figure that reads cleanly.

	4. THE SERVER DECIDES EVERYTHING. The client sends a bare "claim" and nothing else; the date, the
	   streak, which day it is and what it pays are all the server's (`DailyRewardService` header).

	=== THE JACKPOT IS THE CAR ON THE CARD — 2026-10-07 ==========================================

	Day 7 used to hand out a random-car pull while its card showed a generic car glyph. It now names
	the Mk5 Supra here, once: the server awards that exact body and the client renders that same body.
	Keeping the identity on the reward spec prevents the attractive card and the payout drifting apart.

	`Enabled = false`: no screen, no topbar button, no claim accepted, and the record left as it was.
]]

local DailyRewardConfig = {}

DailyRewardConfig.Enabled = true

--- The Frame under `MainUIV2.Pages` (`BuildDailyRewardsV2`), and the name `UIController` files it under.
DailyRewardConfig.PageName = "DailyRewards"

--- Top-level profile key: `{ Day = <1..7 last claimed>, LastDay = <the UTC day it was claimed on> }`.
DailyRewardConfig.ProfileKey = "DailyReward"

DailyRewardConfig.ResetOnMiss = true

--[[ The week. `Kind` is "Cash" (scaled — header note 3), "Revive" (stored revive lives,
	`ReviveService.grantLife`) or "Car" (an exact body awarded through `GarageService.awardCar`).
	`Big` marks the card drawn as the jackpot. Cash climbs through the week so every day is a little
	better than the last; day 4 breaks it up with something that is not money, and day 7 is a free
	car, which is the one reward in this game that is always exciting. ]]
DailyRewardConfig.Days = {
	{ Kind = "Cash", Floor = 500, Hours = 0.25 },
	{ Kind = "Cash", Floor = 1000, Hours = 0.5 },
	{ Kind = "Cash", Floor = 1500, Hours = 0.75 },
	{ Kind = "Revive", Amount = 1 },
	{ Kind = "Cash", Floor = 3000, Hours = 1.25 },
	{ Kind = "Cash", Floor = 5000, Hours = 1.75 },
	--[[ THE PLAYER'S OWN WORLD — 2026-10-08. WAS always the MK5 Supra, a world 2 car worth seven of
		world 1's best: a day-7 claim in world 1 tipped the $100k world 2 price in minutes and skipped
		the world Aleafo wants to last 18-30. NOW `FromTop` rungs below the top car of the player's
		highest unlocked world (`DailyRewardService._rewardFor`) — 1 is the second-best car, which in
		world 2 is still the Supra. `Body` is the fallback for a world with too few cars. ]]
	{ Kind = "Car", Amount = 1, Body = "MK5 Supra", FromTop = 1, Big = true },
}

-- === Remotes and events =======================================================

DailyRewardConfig.Remotes = {
	State = "DailyRewardState", -- server -> client: the calendar (see `DailyRewardService._payload`)
	Claim = "DailyRewardClaim", -- client -> server: "claim today's", with nothing else
	Refresh = "DailyRewardRefresh", -- client -> server: "send me the calendar" (at midnight, on open)
}
--- Published on the client whenever a calendar lands, so the page repaints off the controller.
DailyRewardConfig.StateEvent = "DailyRewardState"

-- === Opening it ===============================================================

--[[ The screen opens on its own once a session, when there is something to claim: `Delay` seconds
	after the calendar first lands, and only once no other screen is up (it waits up to `MaxWait` for
	one to close — the Welcome Back screen opens at the same moment). Never in the tutorial or a run:
	a first-timer has enough to read, and a run is not the place. `Enabled = false`: only the topbar
	button opens it. ]]
DailyRewardConfig.AutoOpen = { Enabled = true, Delay = 3, MaxWait = 30 }

--- The topbar button: TopbarPlus order (after Settings 2 and Shop 3) and its caption.
--- `Icon`: the topbar button's glyph; nil is the shop's bare gift (`UIAssets.GiftGlyph`). It was
--- 112124572844666 for a day (2026-10-14, the owner's pick) and is the gift again since 2026-10-15,
--- the owner's call too.
DailyRewardConfig.Topbar = { Enabled = true, Order = 4, Caption = "Daily Reward", Icon = nil :: number? }

-- === Words ====================================================================

DailyRewardConfig.Text = {
	Title = "DAILY REWARDS",
	DayFormat = "DAY %d",
	BigDayFormat = "DAY %d - JACKPOT",
	Revive = "+%d REVIVE",
	Car = "FREE %s",
	Claim = "CLAIM",
	--- The grey kit button's caption on a day already taken, and on a day still to come.
	Claimed = "CLAIMED",
	Locked = "LOCKED",
	NextIn = "Next reward in %s",
}

--- A cash amount rounded to a figure that reads cleanly: to $50 under $1,000, else two significant digits.
function DailyRewardConfig.roundCash(amount: number): number
	if amount < 1000 then
		return math.max(50, math.floor(amount / 50 + 0.5) * 50)
	end
	local magnitude = 10 ^ (math.floor(math.log10(amount)) - 1)
	return math.floor(amount / magnitude + 0.5) * magnitude
end

return DailyRewardConfig
