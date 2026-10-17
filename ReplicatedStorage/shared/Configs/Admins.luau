--[[
	Admins
	------
	Single source of truth for "who is an admin", shared by client and server. Used by:
	  • AdminPanelController — the F2 Iris panel never boots for non-admins (UI-only gate).
	  • AdminService — the panel's grant remote (cars, pulls, lives, boosts), re-checked per call.
	  • WeatherService — the panel's weather remote, re-checked per call.

	THE TWO SERVER ONES ARE THE CHECKS THAT MATTER. The panel is a client and its gate stops a
	window opening; the remotes it fires are visible to every client in the place, so the list below
	is the whole of what stands between a stranger and a car in their save file.

	The place owner is allowed automatically when the experience is owned by a user. In a
	group / team-create place `game.CreatorId` is the GROUP id, so owner-auto won't match you —
	add your UserId to `List` below in that case.

	The client-side gates are convenience only; never trust them. Anything privileged a panel
	tab triggers must be re-validated server-side.
]]

local List: { [number]: boolean } = {
	-- Same two admins as Meteor.
	[15886356] = true,
	[253611247] = true,
	[55266164] = true,
	-- Studio test players (Start Server + N Players) get negative UserIds.
	[-1] = true,
	[-2] = true,
}

local OWNER_AUTO = true -- also allow the place owner automatically (user-owned places)

--[[ The name of the panel's remote, both directions. It lives here rather than in `AdminService`
	because both ends need it and the client must not require a server module to learn it.

	client -> server (action, target, ...) is the panel asking for something; server -> the one
	client that asked (ok, message) is what happened. `AdminService` has the actions and the reason
	the check on the far end is the one that counts.

	WEATHER HAS ITS OWN DOOR (`WeatherConfig.AdminEvent`) and that is deliberate — see
	`AdminService`'s header for where the line is drawn. Both re-check `isAdmin` below. ]]
local EVENT = "AdminAction"

local Admins = { List = List, Event = EVENT }

function Admins.isAdmin(player: Player?): boolean
	if not player then
		return false
	end
	if List[player.UserId] then
		return true
	end
	if OWNER_AUTO and game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return false
end

return Admins
