--[[
	GroupRewardConfig
	-----------------
	Join the group, get a free car (2026-10-15). A stand in the lobby (`Tag`) shows the reward car with
	YOUR OWN character dancing beside it; press the prompt, Roblox's own join-group popup opens, and
	once the server sees you in the group the car is yours. Once per player, for ever (`ProfileKey`).

	THE GROUP, NOT A LIKE. "Like the game" is on the sign as an ask with nothing attached. A like
	cannot be checked (Roblox has no API for it), and rewarding likes or favourites is against
	Roblox's rules, as far as this was checked. Group membership CAN be checked, and rewarding it is
	the common, allowed version of the same idea.

	TRUST: the client only asks to claim. The server reads membership off Roblox itself
	(`GroupService:GetGroupsAsync`, which is not cached for the session the way `Player:IsInGroup` is,
	so somebody who joined a moment ago counts), checks the profile flag, MARKS the flag and only then
	awards: `CodesService`'s order, so two presses in one frame cannot pay twice.

	THE CAR GOES IN EVEN IF THEY HAVE ONE. With `GarageConfig.Banking.SellDuplicates` off, an exact
	duplicate is simply another car in the inventory. The one case that would SELL it, a full
	inventory, is refused before anything is marked ("make room first"), so the reward is never spent
	on cash. Leaving the group afterwards keeps the car.

	`Enabled = false`: no car on the stand, no prompt, no sign; the stand parts stay invisible.
]]

local GroupRewardConfig = {}

GroupRewardConfig.Enabled = true

--- roblox.com/communities/262496683
GroupRewardConfig.GroupId = 262496683

--[[ The tag on the stand Model, and the parts inside it, all read the same way as `SellerConfig`'s
	`SellerSpot`: the BOTTOM face is the ground, the FRONT face (LookVector) is the way it faces.
	`Sign` is optional (the board floats over the car without it). Every part is made invisible and
	non-colliding at start-up. More than one tagged stand is fine; each gets its own car and dancer. ]]
GroupRewardConfig.Tag = "GroupReward"
GroupRewardConfig.Parts = { Car = "CarSpot", Avatar = "AvatarSpot", Sign = "Sign" }

--[[ The reward. The Mustang ("Mavero"), world 1's 8th of 10: a big start for the new players who are
	most of the people joining, and a car that stops mattering as they progress, so a reward nearly
	everyone claims cannot unbalance anything. The M5 above it stays world 1's chase. `Paint` nil is
	the stock livery; a palette index here makes it a recognisable "group car". ]]
GroupRewardConfig.Car = {
	Body = "Mustang",
	Paint = nil :: number?,
}

--- The one-time flag in the profile, and the Player attribute that mirrors it for the sign.
GroupRewardConfig.ProfileKey = "GroupRewardClaimed"
GroupRewardConfig.ClaimedAttribute = "GroupRewardClaimed"

GroupRewardConfig.Prompt = {
	ActionText = "Claim Free Car",
	ObjectText = "Join group + like the game",
	MaxDistance = 14,
	--- Seconds between two claims from one player that the server will act on.
	Cooldown = 2,
}

GroupRewardConfig.Sign = {
	--- Studs. Width x height of the board, and how high over the car it floats without a `Sign` part.
	Size = Vector2.new(12, 5),
	Lift = 7,
	MaxDistance = 160,
}

GroupRewardConfig.Text = {
	Title = "FREE CAR!",
	Ask = "Join the group and leave a like",
	Like = "on the game to claim your free car! 👍",
	Claimed = "CLAIMED ✓",
	ClaimedAsk = "Thanks for joining!",
	--- The server's answers.
	Success = "Your free %s is in your inventory!",
	NotMember = "Join the group first, then claim!",
	Already = "You've already claimed this.",
	Full = "Your inventory is full. Make room, then claim!",
	NotReady = "Your data is still loading, try again in a moment.",
	Failed = "Couldn't check the group right now. Try again in a moment.",
}

GroupRewardConfig.Remotes = { Claim = "ClaimGroupReward", Result = "GroupRewardResult" }

return GroupRewardConfig
