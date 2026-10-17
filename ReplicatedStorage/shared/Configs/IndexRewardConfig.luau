--[[
	IndexRewardConfig
	-----------------
	The permanent luck earned by claiming cars on the Index page.

	DISCOVERY AND CLAIM ARE TWO DIFFERENT FACTS. `InventoryConfig.Keys.Found` remains the catalogue of
	every body ever banked; `ProfileKey` is the subset whose reward was pressed. Keeping the second
	set is what gives a newly filled card a verb without making old discoveries lose their reward.

	THE CLIENT NAMES A BODY, OR ASKS FOR ALL WITHOUT A LIST. `IndexRewardService` checks against the real
	roster, then checks the server-owned Found list before writing one idempotent claim. The client
	never sends luck, a count or a profile path.
]]

local IndexRewardConfig = {}

IndexRewardConfig.Enabled = true

--- Top-level set of body names: `{ Camaro = true }`. A map survives roster reorderings unchanged.
IndexRewardConfig.ProfileKey = "IndexClaims"

--- The claimed bodies for the two Index pages, encoded as the roster-ordered comma list.
IndexRewardConfig.ClaimedAttribute = "IndexClaimedCars"
--- The server-counted number of valid claims. Luck consumers read this, never the client-built set.
IndexRewardConfig.CountAttribute = "IndexLuckClaims"

--[[ Added to the top-rung weight factor per claimed body. One percent makes each press legible,
	while a completed current catalogue stays below Lucky Roads' +2.5 and far below the retired plus
	affordable upgrade ladders together. New cars extend the ceiling naturally. ]]
IndexRewardConfig.Step = 0.01

IndexRewardConfig.Remotes = {
	Claim = "IndexRewardClaim",
	ClaimAll = "IndexRewardClaimAll",
	Claimed = "IndexRewardClaimed",
}

IndexRewardConfig.ClaimText = "CLAIM +1% LUCK"

--- Server-side spam guard. A normal player cannot press two different cards this quickly.
IndexRewardConfig.ClaimCooldown = 0.15

function IndexRewardConfig.bonusFor(claims: unknown): number
	local count = tonumber(claims)
	if not count or count ~= count then
		return 0
	end
	return math.max(0, math.floor(count)) * IndexRewardConfig.Step
end

function IndexRewardConfig.percentFor(claims: unknown): number
	return math.round(IndexRewardConfig.bonusFor(claims) * 100)
end

function IndexRewardConfig.parseClaimed(raw: unknown): { [string]: boolean }
	local claimed = {}
	if type(raw) ~= "string" then
		return claimed
	end
	for body in string.gmatch(raw, "[^,]+") do
		claimed[body] = true
	end
	return claimed
end

return IndexRewardConfig
