--[[
	AnalyticsConfig
	---------------
	Switches for where `AnalyticsService` sends what it counts. The taxonomy itself is that service's
	header; this holds only what somebody might want to flip.
]]

local AnalyticsConfig = {}

--[[ THE ROBLOX MIRROR (2026-10-28): a chosen set of Gamebeast markers also goes to Roblox's own
	custom events (`AnalyticsService:LogCustomEvent`), on the Creator Dashboard under Analytics >
	Custom events. Which markers, and in what shape, is `ROBLOX_EVENTS` in `AnalyticsService`.

	WHY: Gamebeast's marker quota ran out at 12:44 UTC on 2026-10-28, and over quota it DROPS custom
	markers until the quota resets or is raised (its own Login, Logout and Purchase carry on). Roblox
	already had the tutorial (the onboarding funnel), the Join, FirstCar and FirstPlacement funnels,
	session length and retention, so the mirror adds what it was missing: races, race loading, join
	timings, the end panel's answer, the market and the shop. GameAnalytics gets every event anyway,
	from the same handlers.

	IN ADDITION TO GAMEBEAST, NOT INSTEAD: every marker still goes to Gamebeast whatever this says, so
	Gamebeast has no gap of its own once the quota is back.

	ROBLOX'S LIMITS shape what is sent: 100 custom event names per experience, three breakdown fields
	per event, and 8,000 distinct field values across the whole experience, past which values read
	"Other". So each event carries one number and at most three LOW-VARIETY fields, never a car body, a
	price or an id. Charts are built once a day, so an event logged today shows tomorrow. Roblox
	ignores custom events from Studio.

	`Enabled` is the default. `Remote` lets the "live" Gamebeast configuration override it without a
	publish: a boolean at `Path` wins (false turns the mirror off on every server, true forces it on),
	and no key, which is how "live" stood on 2026-10-28, leaves `Enabled` in charge. Gamebeast's
	configurations are not markers and keep working over the quota. `Path` starts with the
	configuration's name; renaming it on the dashboard breaks this. ]]
AnalyticsConfig.RobloxMirror = {
	Enabled = true,
	Remote = {
		Enabled = true,
		Path = { "live", "Analytics", "RobloxMirror" },
	},
}

return AnalyticsConfig
