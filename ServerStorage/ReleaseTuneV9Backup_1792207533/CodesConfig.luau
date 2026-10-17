--[[
	CodesConfig
	-----------
	Redeemable codes (2026-10-15): typed into the box at the foot of the shop, checked and paid by
	`CodesService`, once per player per code for ever (the profile's `ProfileKey` remembers).

	A CODE PAYS A CASH PACK, NOT A NUMBER, by default. `Pack = "Cash2"` grants what that pack would
	pay THIS player (`CashConfig.cashFor`: the owner's figure for their highest unlocked world),
	so one code posted on the group stays worth having to a new player and a late one alike. `Cash`
	pays a fixed sum instead, for the rare code that should be the same for everyone.

	Codes are matched case blind with spaces trimmed, so "release", " RELEASE " and "Release" are one
	code. `Expires` is a UTC date, "YYYY-MM-DD", after which the code answers "expired"; nil never
	expires. Removing a code makes it answer "doesn't exist", and anyone who already redeemed it keeps
	what they got. `Enabled = false`: the box is not drawn and the server refuses every code.

	TRUST: the client sends a string and nothing else. The server looks it up, checks the profile and
	pays; a made-up code is just an unknown one, and the one-per-player record lives in the profile,
	not on the client. Rate limited per player (`Cooldown`) so the box cannot be used to brute force.
]]

local CodesConfig = {}

CodesConfig.Enabled = true

--- The profile key holding `{ [CODE] = true }` for every code this player has redeemed.
CodesConfig.ProfileKey = "RedeemedCodes"

--- Seconds between two attempts from one player. Long enough to stop guessing, short enough to retype.
CodesConfig.Cooldown = 2
--- Longest string the server will even look at.
CodesConfig.MaxLength = 32

--[[ The codes, by their UPPERCASE text. One of `Pack` (a `CashConfig.Packs` key, scaled to the
	player) or `Cash` (a fixed amount). Examples to start from; edit freely. ]]
CodesConfig.Codes = {
	RELEASE = { Pack = "Cash2" },
	STEALACAR = { Pack = "Cash1" },
}

--- What the box says back. `%s` in `Success` is the amount paid.
CodesConfig.Text = {
	Title = "CODES",
	Placeholder = "Enter a code…",
	Button = "REDEEM",
	Success = "Redeemed! +%s",
	Unknown = "That code doesn't exist.",
	Used = "You've already redeemed that code.",
	Expired = "That code has expired.",
	Slow = "Slow down a moment, then try again.",
	NotReady = "Your data is still loading, try again in a moment.",
	Failed = "Something went wrong. Try again.",
}

--- Remote names, client -> server and back.
CodesConfig.Remotes = { Redeem = "RedeemCode", Result = "CodeResult" }

--- The code as the server and the table key it: trimmed and uppercased. Nil for an unusable input.
function CodesConfig.normalize(text: unknown): string?
	if type(text) ~= "string" then
		return nil
	end
	local code = string.upper((string.gsub(text, "^%s*(.-)%s*$", "%1")))
	if code == "" or #code > CodesConfig.MaxLength then
		return nil
	end
	return code
end

--- Has a code with this `Expires` ("YYYY-MM-DD", UTC) run out at `now` (os.time)? Nil never does.
function CodesConfig.expired(expires: string?, now: number): boolean
	if type(expires) ~= "string" then
		return false
	end
	local y, m, d = string.match(expires, "^(%d+)-(%d+)-(%d+)$")
	if not y then
		return false
	end
	--- The END of that UTC day.
	local last = os.time({ year = tonumber(y) :: number, month = tonumber(m) :: number, day = tonumber(d) :: number, hour = 23, min = 59, sec = 59, isdst = false })
	return now > last
end

return CodesConfig
