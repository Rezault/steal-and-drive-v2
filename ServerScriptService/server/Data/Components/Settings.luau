return {
	DEBUG_MOCK = true,
	-- Main, "Steal and Drive" (universe 10552606589). Live servers here save under PRODUCTION_SUFFIX.
	-- Studio and the TS place (135909936139468, universe 10771147148) take DEVELOPMENT_SUFFIX, as
	-- does any other place.
	PRODUCTION_PLACE_ID = 88780448557155,
	DEVELOPMENT_SUFFIX = "_DEVELOPMENT_04a",
	PRODUCTION_SUFFIX = "_PRODUCTION",
	TEMPLATE = {
		-- Player Data Template:
		--[[ Example:
			```lua
			Cash = 0,
		EconomyVersion = 0,
		StarterInsuranceUsed = 0,
			Stats = {
				Level = 1,
				Experience = 0,
			},
			```
		--]]

		--[[ The player's own name for their dealership, set with the pencil button on the sign.

			This is the WHOLE sign title when set, not a substitute for the player's name in
			"<Player>'s Dealership" — someone who types "Midnight Motors" wants that on the sign,
			not "Midnight Motors's Dealership".

			Empty string means "never set", and the sign falls back to "<DisplayName>'s Dealership",
			so the default is a real, correct-looking sign rather than a blank one. Key name comes
			from PlotConfig.DealershipNameKey; PlotService owns every read and write of it.

			WHAT IS STORED IS WHAT THEY TYPED, UNFILTERED, which is deliberate and is Roblox's own
			guidance for user-authored text: a filter verdict belongs to a VIEWER and a moment, not
			to a save file. So the name is re-filtered on every claim and then once more per player
			who reads it, and nothing in the game ever shows this string as-is. PlotConfig.Rename
			has the whole design. It has still been through `PlotConfig.sanitize` — length and an
			ASCII whitelist — so a save can never hold a control code or a 900-character title. ]]
		DealershipName = "",

		--[[ HOW MANY PLAYERS HAVE LIKED THIS PLAYER'S DEALERSHIP, ever. Key name comes from
			`PlotConfig.Likes.ProfileKey`; PlotService owns every write and it is only ever `+1`.

			IT IS THE RECEIVING HALF OF A PAIR, and `LikesGiven` below is the other one. Everything
			about why the pair is split that way — why the list of WHO liked you is not what is stored
			here, and why the count can only move while both players are in the same server — is in
			`PlotConfig.Likes`.

			MONOTONIC AND WITHOUT AN UNDO, which is the one property to preserve if this is ever
			touched: there is no un-like, so nothing decrements this and no code path should learn how.
			That is what makes it worth putting on a sign.

			NOT IN `Stats`, even though it is a lifetime counter and looks like a fourth one. The three
			in there are a leaderboard's ranking numbers and LeaderboardService owns every write to
			them; this is a plot thing that PlotService owns, and a second service writing into that
			table would make "who owns every write" untrue of both. Mirrored onto the Player as
			`PlotConfig.Likes.Attribute` for the sign to read, the same way `Cash` is.

			Absent is zero, so nothing needs migrating — every profile written before this line already
			answers correctly. ]]
		Likes = 0,

		--[[ WHOSE DEALERSHIPS THIS PLAYER HAS ALREADY LIKED, as a set of user ids with STRING keys:
			`{ ["12345"] = true }`. Key name comes from `PlotConfig.Likes.GivenKey`; PlotService owns
			every write.

			IT IS THE ONLY THING STOPPING A LIKE BEING GIVEN TWICE, which is what makes `Likes` above
			mean anything at all — a count you can press again next session is a count of sessions, not
			of people. Stored on the giver rather than as a list of likers on the receiver so the table
			is bounded by how many dealerships one player has visited instead of by how popular they
			are; `PlotConfig.Likes` has the full reasoning and the 4 MB key it is avoiding.

			STRING KEYS, and that is the datastore rule `Garage.BayLevels` and `Maps` both document
			rather than a stylistic choice: a number-keyed table with gaps in it — which a set of user
			ids is, by definition — comes back from a save as a string-keyed dictionary the code that
			wrote it no longer recognises. So `tostring(userId)` on the way in, every time.

			NOTHING IS EVER REMOVED, for the same reason there is no un-like.

			Absent is "has liked nobody", so nothing needs migrating. ]]
		LikesGiven = {},

		-- Spendable cash. Mirrored onto the Player as an attribute by GarageService so the HUD can
		-- read it without a remote; this is the source of truth, the attribute is the broadcast.
		Cash = 0,

		--[[ Revives bought and not yet spent. Key name comes from `ReviveConfig.ProfileKey`;
			`ReviveService` owns every write and `DevProductsHandler` is the only thing that adds to
			it.

			IT IS STORED RATHER THAN SPENT AT THE TILL, and that is the whole point of it existing.
			A Robux receipt can land at a moment when there is nothing to revive — the offer timed
			out behind the purchase modal, the player left, the server restarted mid-purchase, Roblox
			retried the receipt on their next session. Reviving straight out of the receipt makes
			every one of those a player who paid and got nothing; banking it here makes them a player
			who owns a life, which the next wreck spends for free and without a prompt.

			TOP-LEVEL ON PURPOSE. `PlayerProfile`'s string path is a recursive key search, so a key
			nested inside `Garage` would be reachable only by array path from the two places that
			touch it. Nothing else in this profile has a claim on it either — it is not a garage
			thing and it is not a world thing.

			Absent is zero, so no profile written before this line needs migrating. ]]
		ExtraLives = 0,

		--[[ Offline claim boosts bought and not yet spent. Key name comes from
			`OfflineConfig.Boost.ProfileKey`; `OfflineService` owns every write and
			`DevProductsHandler` is the only thing that adds to it.

			IT IS STORED FOR THE SAME REASON `ExtraLives` ABOVE IS, and that reason is the whole of
			why this key exists rather than the multiplier being applied inside the receipt. A Robux
			receipt can land when there is no WELCOME BACK screen to multiply — the player closed the
			panel behind the purchase modal, they left, the server restarted mid-purchase, Roblox
			retried the receipt two sessions later. Multiplying straight out of the receipt makes
			every one of those a player who paid and got nothing; banking it here makes them a player
			who owns a boost, spent automatically if their screen is still up and waiting on the next
			one if it is not.

			TOP-LEVEL for the same reason `ExtraLives`, `LastSeen`, `World` and `Quests` are:
			`PlayerProfile`'s string path is a recursive key search, so a key nested inside `Garage`
			would be reachable only by array path.

			Absent is zero, so no profile written before this line needs migrating. ]]
		OfflineBoosts = 0,

		--[[ Random car pulls bought and not yet rolled. Key name comes from
			`RandomCarConfig.ProfileKey`; `RandomCarService` owns every write and
			`DevProductsHandler` is the only thing that adds to it.

			IT IS STORED FOR THE REASON `ExtraLives` AND `OfflineBoosts` ABOVE ARE — a Robux receipt
			lands when it lands — AND FOR ONE MORE THAT IS STRONGER HERE. The ROLL is the thing being
			sold. A late revive still revives and a late boost still multiplies the next claim, but a
			car rolled inside a receipt on a server the player is not looking at is a car that turns
			up in their lot with no moment attached to it, and the moment is most of what they paid
			for. Banked, the pull waits for a screen to open in front of, and the next reveal spends
			it.

			TOP-LEVEL for the same reason `ExtraLives`, `LastSeen`, `World` and `Quests` are:
			`PlayerProfile`'s string path is a recursive key search, so a key nested inside `Garage`
			would be reachable only by array path.

			Absent is zero, so no profile written before this line needs migrating. ]]
		RandomCarPulls = 0,

		--[[ Car bodies whose Index reward has been claimed, as a set: `{ Camaro = true }`.
			Discovery remains `Garage.Found`; this second fact is what leaves old discoveries claimable
			and makes a claim idempotent. Absent is an empty set, so existing profiles need no migration. ]]
		IndexClaims = {},

		--[[ THE BEST SPEED-TRAP PASS PER WORLD, as world index (a string) -> mph the SERVER measured:
			`{ ["1"] = 142 }`. Key name is `SpeedTrapConfig.Pay.ProfileKey`; `SpeedTrapService` owns
			every write. Top-level for `RandomCarPulls`' reason, string-keyed for the datastore reason
			every map here is. Absent is "no best yet", so the first rated pass in a world is a best. ]]
		SpeedTrapBest = {},

		--[[ THE MOST VALUABLE CAR THIS PLAYER HAS EVER BEEN GIVEN, as `GarageConfig.valueOf(tier,
			mutation)` whole dollars. Key name is `ShowcaseConfig.ProfileKey`; `ShowcaseService` owns
			every write. A RECORD, NOT A LOOKUP OF THE COLLECTION, so selling your best car does not make
			the next decent one a "new best". Zero means "never measured": the first comparison seeds
			it from whatever the player already owns, so a save written before this line does not greet
			its owner with a cutscene for a car worse than the one on their lot. ]]
		BestCarValue = 0,

		--[[ GAME PASSES THIS PLAYER WAS GIVEN, as a set of pass keys: `{ AutoCollect = true }`. Key
			name comes from `PassConfig.ProfileKey`; `PassService` owns every write and
			`DevProductsHandler` is the only thing that adds to it, through a gift receipt.

			IT IS THE ONE KEY IN HERE THAT CONTRADICTS A RULE THIS FILE STATES ELSEWHERE, and it is
			worth being loud about. `RadioStation` above says ownership of a game pass "lives on
			Roblox and `UserOwnsGamePassAsync` is the only copy that counts", which is true of every
			pass a player BOUGHT and is the reason none of them are stored here.

			A GIFTED PASS HAS NO ROBLOX OWNERSHIP TO READ. Roblox has no API for attaching a pass to
			an account somebody else paid for — `PromptGamePassPurchase` charges the player it
			prompts and grants to that same player — so a gift is a developer product whose receipt
			has to grant the entitlement itself, and the only place an entitlement can live is here.
			`rbxsync.toml`'s GIFTS section has the full argument.

			SO OWNERSHIP IS THE UNION OF TWO SOURCES AND EXACTLY ONE THING READS BOTH.
			`PassService.owns` is that thing. No other file should ever ask this key directly, for
			the same reason nothing but `GarageService` writes `Cash`: two readers of a two-source
			answer is how a player ends up owning a pass on one screen and not on another.

			IT IS NOT A LIST AND NOTHING IS EVER REMOVED. The only question asked of it is "is this
			key in here", and there is no un-gifting — the same call `LikesGiven` makes above.

			Absent is "has been gifted nothing", so no profile written before this line needs
			migrating. ]]
		Passes = {},

		--[[ WHO EACH GIFT THIS PLAYER HAS STARTED BUYING IS FOR, keyed by gift key:
			`{ GiftCash3 = { To = 12345, Name = "Gvistic", At = 1780000000 } }`. Key name comes from
			`GiftConfig.PendingKey`; `GiftService` owns every write and is the only reader.

			IT IS HERE BECAUSE A ROBLOX RECEIPT CANNOT CARRY A RECIPIENT. `receiptInfo` names the
			product and the buyer and nothing else, so the one thing a gift actually needs — who it is
			for — has to be written down before the prompt opens and read back when the receipt lands.
			`GiftService`'s header has the full argument under WHERE THE RECIPIENT IS KEPT.

			ON THE PROFILE RATHER THAN IN MEMORY, and that is the whole reason it is a saved key at
			all. A receipt can arrive on a different server, in a different session, days later, after
			the server that took the money has died. An intent held in a table would be gone by then
			and the gift would pay out to the buyer instead of the person it was bought for.

			KEYED BY GIFT, NOT A SINGLE SLOT. A player can start one purchase, cancel it, start
			another, and then have the first receipt land late. One slot would deliver the first
			purchase to the second purchase's recipient. Bounded by the number of gift products that
			exist, so it cannot grow: twelve entries is the ceiling however many gifts are sent.

			ENTRIES ARE CLEARED WHEN THE RECEIPT LANDS, and stale ones age out at
			`GiftConfig.IntentLifetime` — the guard against an intent left by a purchase that was
			never completed being spent by an unrelated receipt for the same product a month later.

			Absent is "has started buying no gifts", so no profile written before this line needs
			migrating. ]]
		PendingGifts = {},

		--[[ WHETHER THIS PLAYER HAS THE MUSIC TURNED OFF. Key name comes from
			MusicConfig.ProfileKey; MusicService owns every write and is the only reader.

			THE ONLY KEY IN HERE THAT IS NOT ABOUT THE GAME. Everything else in this profile is
			something the player earned, chose or progressed through, and the server is the authority
			on all of it. This is a PREFERENCE: the client applies it the instant the button is
			pressed and tells the server afterwards, because there is no ruling to make about whether
			someone's own speakers make noise. MusicController's "Who owns the mute" has the whole
			argument, including why the attribute this is mirrored onto is read exactly once.

			IT IS STORED FOR ONE REASON: a mute that does not survive a rejoin makes the player hear
			the exact thing they turned off, every session, forever.

			TOP-LEVEL for the same reason ExtraLives, LastSeen, World, Quests and StartCar are:
			PlayerProfile's string path is a recursive key search, so a key nested inside Garage
			would be reachable only by array path.

			Absent is false — unmuted — so every profile written before this line already answers
			correctly and nothing needs migrating. ]]
		MusicMuted = false,

		--[[ WHICH SKY THIS PLAYER'S LOBBY RUNS. Key name comes from `DayNightConfig.ProfileKey`;
			`SettingsService` owns every write and is the only reader.

			ONE OF THREE STRINGS: "" for the day and night cycle, "day" and "night" for a lobby
			pinned to one of them. `DayNightConfig.Preference` is the list and
			`DayNightConfig.resolve` is the only thing that turns a stored value back into one.

			THE SECOND KEY IN HERE THAT IS NOT ABOUT THE GAME, and everything said above `MusicMuted`
			applies word for word: it is a PREFERENCE, the client applies it the instant the pill is
			pressed and tells the server afterwards, and there is no ruling to be made about which
			sky somebody looks at. `Lighting` is per client, so a lie about this reaches nobody.

			TOP-LEVEL for the same reason `MusicMuted` is: `PlayerProfile`'s string path is a
			recursive key search, so a key nested inside a Settings table would be reachable only by
			array path.

			Absent is "", which is the cycle, so every profile written before this line already
			answers correctly and nothing needs migrating. ]]
		SkyPreference = "",

		--[[ HOW LOUD THIS PLAYER KEEPS THE SOUNDTRACK, 0 to 1. Key name comes from
			`AudioConfig.Music.ProfileKey`; `SettingsService` owns every write and is the only reader.

			-1 IS NOT A LEVEL, IT IS "NEVER CHOSEN", and it is the template default rather than 1 for
			the one reason written up at `AudioConfig.Unset`: `MusicMuted` above is the same fact from
			before there was a slider, and a player who muted the game last month has that key and no
			level. Reconcile fills this one in for them, and if it filled it in with a real level
			their mute would be silently discarded. The sentinel is what lets `SettingsService`
			notice that they never answered and inherit the boolean instead. It stops mattering the
			first time they touch the slider.

			A PREFERENCE, not a thing they earned, and everything said above `MusicMuted` applies word
			for word — including why this is top-level rather than nested in a Settings table.

			THE MUTE AND THE LEVEL ARE ONE FACT ON THE CLIENT (`MusicController`): muted IS zero. Both
			keys are still written so that a rolled-back build reads a sensible answer out of the old
			one, and this is the one that wins when they disagree. ]]
		MusicVolume = -1,

		--[[ HOW LOUD THIS PLAYER KEEPS EVERYTHING THAT IS NOT THE SOUNDTRACK, 0 to 1. Key name comes
			from `AudioConfig.Sfx.ProfileKey`; `SettingsService` owns every write and is the only
			reader. `SoundController` is what applies it.

			1 IS FULL AND IS THE MIX AS SHIPPED. A player level multiplies the authored levels rather
			than replacing them, so the default has to be the identity or every build would ship
			quieter than it was tuned. `AudioConfig`'s header has the contract.

			No sentinel here and none needed: nothing has ever stored a sound effects level, so absent
			means "never asked" and "the default" at the same time, and they are the same answer. ]]
		SfxVolume = 1,

		--[[ HOW LOUD THIS PLAYER KEEPS THE CARS (engines, tyres, drifts), 0 to 1. Key name comes from
			`AudioConfig.Car.ProfileKey`; `SettingsService` owns every write, `SoundController` applies
			it. 1 is the mix as shipped, `SfxVolume`'s contract. ]]
		CarVolume = 1,

		--[[ THE DAILY REWARD STREAK. Key name comes from `DailyRewardConfig.ProfileKey`;
			`DailyRewardService` owns every write. `Day` is the last day of the week claimed (1..7, 0 for
			never) and `LastDay` the UTC day number (`QuestConfig.dayIndex`) it was claimed on, -1 for
			never — which reads as "claimable, day 1", so no profile needs migrating. ]]
		DailyReward = { Day = 0, LastDay = -1 },

		--[[ THE PLAYTIME GIFTS (2026-10-19). Key name comes from `PlaytimeRewardConfig.ProfileKey`;
			`PlaytimeRewardService` owns every write. `Day` is the UTC day (`QuestConfig.dayIndex`) the
			other two belong to, `Seconds` how long they have played that day, `Claimed` how many of the
			day's gifts they have taken. A record from another day reads as a fresh one, so -1 needs no
			migrating. ]]
		PlaytimeGifts = { Day = -1, Seconds = 0, Claimed = 0 },

		--[[ EVERY CODE THIS PLAYER HAS REDEEMED, `{ [CODE] = true }`. Key name comes from
			`CodesConfig.ProfileKey`; `CodesService` owns every write. Empty is "none yet". ]]
		RedeemedCodes = {},

		--[[ WHETHER THIS PLAYER HAS EVER BOUGHT FROM A SELLER AT THEIR KERB. Key name comes from
			`SellerConfig.Onboarding.ProfileKey`; `SellerService` owns the one write. False keeps the
			first-time outline and arrow on every seller until they do. ]]
		SellerBought = false,

		--[[ WHETHER THIS PLAYER HAS CLAIMED THE JOIN-THE-GROUP CAR. Key name comes from
			`GroupRewardConfig.ProfileKey`; `GroupRewardService` owns every write. Once true, for ever. ]]
		GroupRewardClaimed = false,

		--[[ THE ONCE-ONLY BUNDLES THIS PLAYER HAS BOUGHT, `{ [Key] = true }` (the Starter Bundle). Key name
			comes from `ShopConfig.BundleStand.BoughtProfileKey`; `BundleService.grantBundle` owns every
			write. Empty is "none yet". ]]
		BundlesBought = {},

		--[[ WHETHER THIS PLAYER WATCHES THEIR STEALS THROUGH THE CINEMATIC CAMERA, "on" or "off". Key
			name comes from `StealJuiceConfig.Setting.ProfileKey`; `SettingsService` owns every write.
			Empty is "never asked", which `StealJuiceConfig.resolveSetting` reads as the default, so a
			profile from before the row existed answers correctly with no migration. ]]
		StealCinematic = "",

		--[[ THE RADIO STATION THIS PLAYER LAST PUT ON. Key name comes from `RadioConfig.ProfileKey`;
			RadioService owns every write and is the only reader.

			A PREFERENCE, NOT AN ENTITLEMENT — which is the whole reason it is here at all and not on
			Roblox with the pass. Ownership of the Car Radio game pass lives on Roblox and
			`UserOwnsGamePassAsync` is the only copy that counts (`RadioService`'s header has the
			division); this is only which of the four stations they had on, so the car they spawn
			tomorrow comes up playing what it was playing today. Nothing is unlocked by it.

			A PLAYER WITHOUT THE PASS CAN HOLD ONE and simply never hears it, which is deliberate:
			the day they buy the pass, the radio is already tuned to the last thing they tried.

			A STATION KEY, NEVER A CUSTOM TRACK ID. `RadioConfig.ProfileKey` has the reasoning —
			re-validating an arbitrary saved id would be a web call on the spawn path, and an id
			moderated since it was saved would come back as a car playing nothing.

			Absent is "" — no station chosen — which `RadioService._stationFor` reads as "give them
			the default", so every profile written before this line already answers correctly and
			nothing needs migrating. ]]
		RadioStation = "",

		--[[ The last `os.time()` we knew this player was in the game — written on join, on a slow
			timer while they play, and on the way out. Key name comes from `OfflineConfig.ProfileKey`;
			`OfflineService` owns every write and is the only reader.

			IT IS NOT PART OF ANY PAYOUT, which is the thing to know before touching it. What a bay
			owes is still derived from that bay's own `Collected` stamp and nothing else (see
			`Garage.Cars` below), so this cannot make the money wrong in either direction. It answers
			one question — "how long were you gone?" — for the WELCOME BACK screen, and decides
			whether that screen is worth putting up at all.

			TOP-LEVEL for the same reason `ExtraLives` is: `PlayerProfile`'s string path is a
			recursive key search, so a key nested inside `Garage` would be reachable only by array
			path. Zero means "we have never seen this player leave", which is a first session and
			every profile written before this line existed; both get no screen rather than a wrong
			one, so nothing needs migrating. ]]
		LastSeen = 0,

		--[[ THE LIFETIME COUNTERS THE LEADERBOARDS RANK. Key name and the three field names come from
			`LeaderboardConfig` (`ProfileKey`, `Stats`); `LeaderboardService` owns every write and is
			the only reader.

			    Stats = { Steals = 12, Distance = 480210, TimePlayed = 9040 }

			`Steals` is cars taken off the road, `Distance` is studs driven summed over every run, and
			`TimePlayed` is seconds in the game summed over every session.

			MONOTONIC, AND NOT THE SAME NUMBERS AS `Quests`. Nothing here is ever decremented and
			nothing resets at midnight — a quest counts what you did today, these count what you have
			ever done, and the two are fed from the same signals precisely so that neither has to
			trust the other's bookkeeping.

			NESTED RATHER THAN THREE TOP-LEVEL KEYS, which is the one place this template's usual
			advice is deliberately declined. That advice — see `ExtraLives` — exists because
			`PlayerProfile`'s string path is a recursive key search, so a nested key is reachable only
			by array path; these are only ever read by array path anyway, from one file. What the
			grouping buys is that `Distance` and `Steals` are exactly the sort of generic name a
			future feature will want somewhere else in here, and a recursive search that silently
			finds the WRONG `Distance` is a bug with no error in it.

			`Distance` IS NOT `Maps`. That one is the furthest point ever reached down each world's
			road and it is a maximum; this is a sum, and driving the same mile twice moves this and
			not that.

			Absent is zero, so nothing needs migrating — a profile written before this feature simply
			starts accruing from its next steal, run and session. ]]
		Stats = {
			Steals = 0,
			Distance = 0,
			TimePlayed = 0,
		},

		--[[ Which world the player last teleported to, as an index into `WorldConfig.Worlds` — the
			road they drive and the ladder of cars that drives past them. Key name and default both
			come from `WorldConfig` (`ProfileKey`, `ActiveIndex`); WorldService owns every write.

			A stale index — a world deleted from the config, or a profile written by a future
			build — is read as the default rather than trusted, so shrinking the world list can
			never strand a save. ]]
		World = 1,

		--[[ WHICH OF THEIR OWN CARS THE PLAYER STARTS A RUN IN, as a CAR KEY ("Camaro:6" — body and
			colour, `GarageConfig.carKey`). Key name and default both come from `StartCarConfig`
			(`ProfileKey`, `DefaultKey`); StartCarService owns every write.

			THE EMPTY STRING IS A REAL VALUE and it is the one every player starts on: it means "this
			world's own starter", resolved per race from `WorldConfig.startBodyFor` rather than stored.
			So retuning `WorldConfig.StartRung` moves every unchosen player onto the new car with
			nothing to migrate, and a profile written before this key existed already answers correctly.

			ONE CAR, NOT ONE PER WORLD — see `StartCarConfig`, which also explains why a saved car from
			another world's ladder is honoured rather than dropped.

			NOT VALIDATED ON LOAD, unlike `World` above, and the difference is what a bad value costs:
			a world you do not own would be a free pass to it, while a car you no longer own simply
			resolves back to the starter on every race (`StartCarService.carFor` re-checks the
			collection each time). So a body renamed out of the roster and back again brings the
			player's choice home instead of having quietly erased it.

			TOP-LEVEL for the same reason `ExtraLives`, `LastSeen`, `World` and `Quests` are:
			`PlayerProfile`'s string path is a recursive key search, so a key nested inside `Garage`
			would be reachable only by array path. ]]
		StartCar = "",

		--[[ THE HIGHEST WORLD THIS PLAYER HAS BOUGHT, so 2 means they own worlds 1 and 2. Key name
			and default both come from `WorldConfig` (`UnlockProfileKey`); WorldService owns every
			write and its `unlockWorld` is the only one.

			ONE NUMBER RATHER THAN A LIST OF WORLDS, because the worlds are a ladder: world 3 asks
			that you have finished world 2, which you cannot have done without owning it, so what a
			player owns is always a prefix of the list. Storing the top of that prefix means the one
			state the shape allows but the game does not — owning world 4 and not world 3 — cannot
			be written down at all. `WorldConfig`'s "Earning a world" block has the rest, including
			what changes if a world ever becomes buyable out of order.

			TOP-LEVEL for the same reason `ExtraLives` and `World` are: `PlayerProfile`'s string
			path is a recursive key search, so a key nested inside `Garage` would be reachable only
			by array path.

			Absent is 1 — world 1 is free — so every profile written before this line already
			answers correctly and nothing needs migrating. ]]
		WorldsUnlocked = 1,

		--[[ TODAY'S QUEST BOARD, or rather the only part of it worth storing. Key name comes from
			`QuestConfig.ProfileKey`; QuestService owns every write.

			WHICH QUESTS YOU HAVE IS NOT IN HERE, and that is the design rather than an omission. The
			four are drawn deterministically from the UTC day number (`QuestConfig.dailySet`), so the
			board is recomputed from the date on both sides of the wire and is the same for every
			player — there is no selection to save, to lose, or to disagree with. What is stored is
			how far along you are:

			    { Day = 20308, Progress = { steal_5 = 3 }, Claimed = { bank_3 = true } }

			`Day` is which day the other two belong to. A `Day` that is not today means the board has
			turned over, and both tables are wiped on the next read rather than by a scheduled sweep —
			so a player who was offline for a week rolls over once, on join, and a server that was
			down at midnight does not owe anybody a rollover it missed. See `QuestService._roll`.

			BOTH INNER TABLES ARE STRING-KEYED MAPS, which is the datastore rule `Garage.BayLevels`
			and `Garage.Levels` both document: a quest ID is a name, so these round-trip through a
			save unchanged. A number-keyed table with a gap in it does not.

			TOP-LEVEL for the same reason `ExtraLives`, `LastSeen` and `World` are: `PlayerProfile`'s
			string path is a recursive key search, so a key nested inside `Garage` would be reachable
			only by array path.

			Absent is a fresh board — `Day = 0` is a day that can never be today — so every profile
			written before this line already answers correctly and nothing needs migrating. ]]
		Quests = {
			Day = 0,
			Progress = {},
			Claimed = {},
		},

		--[[ HOW FAR THROUGH THE ONBOARDING THIS PLAYER IS. Key name comes from
			`TutorialConfig.ProfileKey`; TutorialService owns every write.

			    { Step = "collect", Done = false }

			`Step` IS AN ID, NOT AN INDEX, and that is the one thing to know before touching it. An
			index is a number whose meaning changes the day a beat is inserted into
			`TutorialConfig.Steps`, and every profile mid-tutorial would silently resume onto
			whatever step 3 had become. An id is merely unknown, and there are two answers for one:
			`TutorialConfig.Renamed` translates a beat that was deliberately renamed or retired, and
			anything it does not cover `TutorialService._resume` reads as "start from the top". So
			reordering or retiring a beat costs at most one player one repeated objective, rather
			than pointing them at the wrong one.

			That table earned its keep once already: the five-step list this key was written for was
			replaced by an eight-beat one, and every save mid-tutorial at the time came through it.

			`Done` is the finish AND the skip, deliberately one field: both mean "never show this
			player the tutorial again", and a second key distinguishing them would be a distinction
			nothing reads. What was actually learned is not stored at all — the tutorial teaches by
			making the player do the thing, so their garage, their cash and their map progress are
			the record of it.

			TOP-LEVEL for the same reason `ExtraLives`, `LastSeen`, `World` and `Quests` are:
			`PlayerProfile`'s string path is a recursive key search, so a key nested inside `Garage`
			would be reachable only by array path.

			Absent is a fresh tutorial, so nothing needs migrating — every player who already has a
			profile is offered the onboarding once, which is the right answer for a game that has
			never had one. ]]
		Tutorial = {
			Step = "",
			Done = false,
		},

		--[[ THE FIRST CAR THIS PLAYER EVER HELD, and whether they ever put it down. Key name comes
			from `CarryConfig.Guide.ProfileKey`; `FirstCarService` owns every write.

			    { Carried = true, Placed = false }

			TWO BOOLEANS, AND THE GAP BETWEEN THEM IS THE POINT. `Carried` is "a car has been in
			this player's hands at least once" and `Placed` is "and one of them reached a bay". A
			profile carrying the first without the second is a player the reward flow lost between
			handing them the prize and them keeping it, which is the exact question `CarryConfig`'s
			own header says the carry feature exists to answer and which nothing was measuring.

			THEY ARE A LATCH, NOT A COUNT. Neither is ever cleared and neither counts past one:
			what they gate is a walkthrough that may only ever run once, and a count would invite
			somebody to read them as "cars owned", which `Garage.Owned` already answers properly.

			TOP-LEVEL for the same reason `Tutorial`, `Quests`, `ExtraLives`, `LastSeen` and `World`
			are: `PlayerProfile`'s string path is a recursive key search, so a key nested inside
			`Garage` would be reachable only by array path.

			Absent is a player who has never had a car, so nothing needs migrating. Every profile
			written before this line is offered the walkthrough once, which is the right answer for
			a game whose first car has never been explained. ]]
		FirstCar = {
			Carried = false,
			Placed = false,
		},

		--[[ THE FURTHEST THIS PLAYER HAS EVER GOT DOWN EACH WORLD'S ROAD, in studs, as world index
			-> distance with STRING keys: `{ ["1"] = 48210 }`. Key name comes from
			`WorldConfig.ProgressKey`; WorldService owns every write and RewardService is the only
			thing that asks for one (at the end of a settled run, banked or wrecked — the road was
			driven either way).

			A MAP for the same datastore reason `Garage.BayLevels` is one: worlds 1 and 3 driven with
			2 untouched is a number-keyed table with a gap in it, and that comes back from a save as
			a string-keyed dictionary the writer no longer recognises. Absent is "never driven", and
			it reads as zero everywhere.

			STUDS, NOT A PERCENTAGE, and the reasoning is the same as `Garage.Levels` storing XP and
			not a level: the percentage is this divided by tuning (the road's SegmentLength and the
			ladder's top rung), so storing the raw distance means retuning either one re-derives
			every profile that already exists instead of freezing them on the old scale. What the
			client is sent IS the percentage — see `WorldConfig.ProgressAttribute`. ]]
		Maps = {},

		--[[ The dealership lot. Keys mirror `GarageConfig.Keys` — those two are one contract.

			`Cars` IS A DENSE ARRAY and has to stay one. Bay number is the array index, so a table
			with a gap in it (bays 1, 2 and 5 filled) round-trips through the datastore's JSON as a
			dictionary with string keys and comes back as something the code that wrote it does not
			recognise. The BAY a car sits on is a field on the entry, not the index — see below.

			Each entry is
			`{ Body = "Sedan12", Tier = 1, Paint = 6, Mutation = "Charged", Collected = <os.time()>,
			Bay = 3 }`.
			`Collected` is the ONLY state the income needs: what a bay owes you is the time since
			that stamp times its tier's rate, capped. Nothing accumulates, so nothing has to be
			flushed on a timer and offline income needs no separate path. See GarageConfig's header.

			`Bay` is what lets the lot be SPARSE while the array stays dense — a player who parks a
			car on bay 4 with bays 1-3 empty is now an ordinary case, because the player chooses
			where each car goes. An entry written before `Bay` existed has none, and is read as
			`Bay = <its array index>`, which is exactly what it meant.

			`Paint` is the palette index this copy wears, and it is part of WHICH CAR this is rather
			than decoration — see `Owned` below. An entry written before it existed takes its colour
			from `Paints`, which is what that key is now only kept for.

			`Mutation` is the weather that was on the car when it was stolen (`WeatherConfig`), and is
			ABSENT on an ordinary car — which is nearly all of them, and is also every entry written
			before the weather existed. It needs no migration for exactly that reason: nil and "no
			mutation" are the same value. Like `Paint` it is part of which car this is, and unlike
			`Paint` it changes what the car EARNS — `GarageConfig.rateOf` multiplies the bay's income
			by it, so two entries with the same body, tier and colour can pay different amounts. ]]
		Garage = {
			Cars = {},

			--[[ Per-car state, as car ID -> record: `{ ["Camaro:6#17"] = { Condition = 0.62 } }`.
				Keyed by ID rather than by key because it is about ONE car — two red Camaros can bank in
				different condition. Absent is defaults (full condition, for sale), which is every car
				banked before this existed. `GarageConfig.Keys.CarData` has the rest. ]]
			CarData = {},

			--[[ The serial the next car ID is minted with (`GarageConfig.carId`). Only goes up, so a
				sold car's ID is never handed to a new one. See `GarageConfig.Keys.NextCarSerial`. ]]
			NextCarSerial = 1,

			--[[ Buyers' offers still standing, as car ID -> offer:
				`{ ["Camaro:6#17"] = { Amount = 14200, ExpiresAt = <os.time()>, Name = "Alex" } }`.
				Key name is `BuyerConfig.ProfileKey`; `BuyerService` owns every write. A saved fact rather
				than session state so a buyer who arrived during a run, or before a rejoin, is still there
				(`BuyerConfig` note 1). Expired entries are pruned on the next pass, never trusted. ]]
			Offers = {},

			--[[ The car this player is HOLDING and has not parked yet, as one car key
				(`"Sedan12:6"`), or the empty string for empty hands. Key name comes from
				`CarryConfig.ProfileKey`; GarageService owns every write, and `CarryService` owns the
				model welded to the character.

				IT IS A PENDING PLACEMENT AND NOT A CAR. The car itself is already in `Owned` by the
				time anything is written here, so this key going missing, being emptied by a build
				with the feature switched off, or naming a car that has since been sold costs the
				player nothing: they own the car either way, and the Cars Inventory can park it. That
				is the whole reason it is safe for this to be a single string rather than a record.

				A STRING AND NOT NIL FOR EMPTY, so a client reading the broadcast attribute never has
				to tell "holding nothing" apart from "not published yet". ]]
			Carrying = "",

			--[[ THE HOTBAR (2026-09-30): up to `CarryConfig.Hotbar.Slots` car IDs, slot 1 first. Key
				name is `CarryConfig.Hotbar.ProfileKey`; GarageService owns every write. A car listed
				here is in the hotbar; a car in neither this nor on a bay is in the Cars Inventory. Read
				through `GarageService._hotbarList`, which drops anything sold or parked since, so a
				stale entry costs nothing. Empty for every save written before it, which reads as
				"everything unparked is in the inventory" — see `CarryConfig.Hotbar`. ]]
			Hotbar = {},

			--[[ Every car this player has ever banked, in the order they first banked it, as CAR
				KEYS: `{ "Sedan06:1", "Sedan12:6", "Sedan12:3" }` — body and colour, so the last two
				are the red Sedan12 and the black one. A DENSE ARRAY OF STRINGS, for the same
				datastore reason `Cars` is a dense array.

				COLOUR IS PART OF THE IDENTITY, which is the one thing to understand about this key:
				two Camaros in different colours are two cars to own and both can be parked at once,
				while two in the SAME colour are indistinguishable and the second one sells. The
				reasoning is in `GarageConfig.Banking`; the encoding is `GarageConfig.carKey`.

				SO IS THE MUTATION, and it arrives as a THIRD field only when there is one:
				`"Camaro:6:Charged"` against the plain `"Camaro:6"`. That is what makes it free of
				migration — an ordinary car's key is byte-for-byte what it always was — and it is the
				stronger case of the same argument colour makes, because a mutated car does not merely
				look different, it earns more.

				This is the collection, and it is separate from the lot on purpose: `Cars` is the six
				bays that are earning, `Owned` is everything you have, and the dealership screen is
				how you move one into the other. GarageService mirrors it onto the player as
				`CarsFound`, which four screens and the MOST VALUABLE board read.

				IT SHRINKS NOW, AND IT USED TO SAY IT NEVER WOULD. Selling a car from the Cars
				Inventory takes it out of here — that is what selling is. What must not go backwards
				is the CATALOGUE, and that is why `Found` below exists as a separate list rather than
				this one being asked to be two things at once.

				An entry that is a bare body name with no `:colour` was written before colour was
				part of the identity, and is read as that body in whatever `Paints` recorded for it. ]]
			Owned = {},

			--[[ Every BODY this player has ever banked, in the order they first banked it:
				`{ "Civic", "Camaro" }`. A DENSE ARRAY OF STRINGS, same datastore reason as `Owned`.
				Key name comes from `InventoryConfig.Keys.Found`; GarageService owns every write.

				NOTHING IS EVER REMOVED FROM THIS ONE. That is the whole job: `Owned` answers "what
				do you have" and can shrink when a car is sold, and this answers "what have you ever
				had" and cannot. The Index page ("23/29 Stolen") and the BIGGEST COLLECTION board are
				both catalogues of the roster, and a catalogue that un-ticks because a player cashed
				in a spare Camaro is a catalogue nobody trusts.

				BODIES, NOT CAR KEYS, because that is the question a catalogue asks — four colours of
				one Camaro is one entry in it. Broadcast as `CarsSeen`.

				SEEDED FROM `Owned` ON FIRST READ, so a profile written before this key existed keeps
				every tick it had earned. Absent is therefore not "nothing found", it is "not
				migrated yet"; see `GarageService._foundList`. ]]
			Found = {},

			--[[ CAR KEYS the player has starred: `{ "M5:3" }`. Key name comes from
				`InventoryConfig.Keys.Favorites`.

				A MARKER AND A SPEED BUMP. It sorts a car to the top of the inventory list, and the panel
				at the sell lot marks a starred car with a gold star and an amber line and asks a second
				time before it takes it (`SellPopupController`). It is not a refusal: a favourite is still
				sellable, still parkable, still ordinary.

				Keys rather than bodies, because it is about ONE car: starring your red Camaro must not
				star the black one you were about to cash in. Entries for cars no longer owned are
				harmless and are pruned on the next write.

				THERE WAS A `Locked` LIST BESIDE THIS ONE until 2026-08-24 and it is no longer in this
				template. It was the hard version of the same idea — the server refused to sell anything
				in it — and the favourite's second hold replaced it. NOTHING READS IT ANY MORE, so a
				profile written before this keeps whatever it had under `Locked` and no car is stranded
				by it; it is left rather than migrated away because a migration that deletes a player's
				data to save a few bytes is a migration that can only lose. ]]
			Favorites = {},

			--[[ CAR IDS held back from buyers: `{ "Camaro:6#17" }`. For sale is the default, so this
				is the exception list and an empty one means everything is for sale — which is every
				car banked before this existed. Key name comes from `InventoryConfig.Keys.NotForSale`;
				`GarageService` owns every write through the same flag path as `Favorites`. Versioned
				from "NotForSale" on 2026-10-06 to drop flags written by the DefaultNotForSale bug. ]]
			NotForSale2 = {},

			--[[ What level each bay's upgrade kiosk is on, as bay index -> level with STRING
				keys: `{ ["1"] = 4 }`. Absent is LEVEL 1, not level 0 — every bay starts on a real
				level because the sign says so, which is the one place in this profile where a missing
				number does not mean zero.

				A MAP for the same datastore reason `Levels`, `Paints` and `Upgrades` are: bays 1 and
				5 upgraded is a number-keyed table with a gap in it, which comes back from a save as
				something else entirely.

				The ladder, the price of the next level and what a level is worth all live in
				`UpgradeConfig.Bay` (which also names this key); GarageService stores it and draws the
				sign, UpgradeService is the only thing that decides it may change. ]]
			BayLevels = {},

			--[[ Car XP, as body name -> total XP earned in that car: `{ Sedan12 = 4820 }`.

				A MAP, and deliberately not an array like the two above. The dense-array rule they
				follow exists because a NUMBER-keyed table with a gap comes back from the datastore
				as a string-keyed dictionary; a table that was string-keyed all along has nothing to
				lose. Bodies are named, so this is the shape that survives.

				XP is the only thing stored. Level, the next threshold, and the top-speed bonus a
				level buys are all derived from it by `RewardConfig` — so retuning the ladder
				re-levels every profile that already exists instead of leaving them on the old one.

				Written only by a BANK (RewardService → GarageService.addCarXp): you earn XP in the
				car you got away with, never in one you wrecked. ]]
			Levels = {},

			--[[ What colour each owned car is, as body name -> palette index: `{ Charger = 6 }`.

				A MAP for the same datastore reason `Levels` is one, and an INDEX rather than a colour
				because a `Color3` cannot be stored at all — see `PaintConfig`, which also explains why
				its palette can be appended to but never reordered once this table has entries in it.

				Written once, when a body first joins `Owned` (GarageService.awardCar): the colour of
				the car you got away with is the colour it keeps, on its podium and in the street.
				A body with no entry here is the livery its artist authored, which is what an empty
				table means for a fresh player and what every reader falls back to. ]]
			Paints = {},

			--[[ What the player has bought off the billboard on their forecourt, as upgrade key ->
				level: `{ Income = 3, Floor2 = 1 }`. Key name, ladders and every effect live in
				`UpgradeConfig`; UpgradeService owns every write.

				A MAP, for the third time and the same datastore reason as `Levels` and `Paints`
				above — string keys round-trip, number keys with a gap in them do not.

				THE LEVEL IS ALL THAT IS STORED. What a level is worth is recomputed from
				`UpgradeConfig` on every read, so retuning a curve re-prices every profile that
				already exists rather than leaving old saves on the old numbers. A missing key is
				level 0, which is why an upgrade added after this line was written needs no
				migration: every profile already answers 0 for it.

				`Floor2` is the odd one out and worth knowing about before touching it: its level is
				the only entry here that corresponds to GEOMETRY rather than to a number. Owning it
				means UpgradeService builds a second storey onto whichever plot the player is sitting
				on when they join, and takes it away again when they leave — the plot is a seat for
				the session, so the building has to be too. ]]
			Upgrades = {},
		},
	},
	SESSION_END_MESSAGE = `Profile session ended. Please rejoin the game to continue playing.`,
	LOAD_FAILED_MESSAGE = `You've been kicked from the game. We had an issue loading your data. Please try again.`,
	MESSAGE = `You've been kicked from the game. We had an issue loading your data. Please try again.`,
}
