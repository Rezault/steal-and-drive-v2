--[[
	CodesService  (server)
	----------------------
	Checks and pays redeemable codes (`CodesConfig` has what a code is and the trust note). One remote
	in, one answer out: the client sends the text it typed, this answers `(ok, message)`.

	THE ORDER IS THE SAFETY, and it is the bank's: the code is MARKED redeemed in the profile BEFORE it
	is paid, so a second attempt racing the first (two presses in one frame) finds it used. A pay that
	then fails is the rare case and costs the player that code; paying first and marking second would
	let a double press pay twice, which is the one outcome that cannot be taken back.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CodesConfig = require(ReplicatedStorage.shared.Configs.CodesConfig)
--- A code's `Pack` pays that pack's scaled amount: a CONFIG, for `cashFor`, not the service.
local CashConfig = require(ReplicatedStorage.shared.Configs.CashConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local Data = require(script.Parent.Parent.Data)

local CodesService = Shard.new("CodesService"):withDependencies({ "GarageService" })

--- (player: Player, code: string, amount: number) : a code was redeemed and paid. For
--- `AnalyticsService` (2026-10-15): which codes are actually used, as a cash source.
CodesService:withSignals({ "Redeemed" })

CodesService:withRemoteEvents({
	CodesConfig.Remotes.Result,
	{
		[CodesConfig.Remotes.Redeem] = function(player: Player, text: unknown)
			CodesService:_redeem(player, text)
		end,
	},
})

function CodesService._reply(self, player: Player, ok: boolean, message: string)
	self:getRemoteEvent(CodesConfig.Remotes.Result):Fire(player, ok, message)
end

--- What a code pays this player, or nil for a code whose reward is malformed.
local function amountFor(entry, player: Player): number?
	if type(entry.Pack) == "string" then
		for _, pack in CashConfig.Packs do
			if pack.Key == entry.Pack then
				return CashConfig.cashFor(pack, player)
			end
		end
		return nil
	end
	return if type(entry.Cash) == "number" and entry.Cash > 0 then entry.Cash else nil
end

function CodesService._redeem(self, player: Player, text: unknown)
	local words = CodesConfig.Text
	if not CodesConfig.Enabled then
		return
	end
	local now = os.clock()
	if (self._last[player] or -math.huge) + CodesConfig.Cooldown > now then
		self:_reply(player, false, words.Slow)
		return
	end
	self._last[player] = now

	local code = CodesConfig.normalize(text)
	local entry = code and CodesConfig.Codes[code]
	if not (code and entry) then
		self:_reply(player, false, words.Unknown)
		return
	end
	if CodesConfig.expired(entry.Expires, os.time()) then
		self:_reply(player, false, words.Expired)
		return
	end
	local profile = self._profiles[player]
	local Garage = Shard.get("GarageService")
	if not (profile and profile:IsActive() and Garage and Garage:isProfileReady(player)) then
		self:_reply(player, false, words.NotReady)
		return
	end
	local redeemed = profile:Get(CodesConfig.ProfileKey)
	redeemed = if type(redeemed) == "table" then table.clone(redeemed) else {}
	if redeemed[code] then
		self:_reply(player, false, words.Used)
		return
	end
	local amount = amountFor(entry, player)
	if not amount then
		self.log:warn(string.format("Code %s has no usable reward (Pack or Cash); refusing it.", code))
		self:_reply(player, false, words.Failed)
		return
	end

	--- Marked first, paid second (header).
	redeemed[code] = true
	profile:Set(CodesConfig.ProfileKey, redeemed)
	local ok = pcall(function()
		Garage:addCash(player, amount)
	end)
	if not ok then
		self.log:warn(string.format("%s redeemed %s but the payment failed; the code is spent.", player.Name, code))
		self:_reply(player, false, words.Failed)
		return
	end
	self.log:info(string.format("%s redeemed %s for %s.", player.Name, code, GarageConfig.formatCash(amount)))
	self:getSignal("Redeemed"):Fire(player, code, amount)
	self:_reply(player, true, string.format(words.Success, GarageConfig.formatCash(amount)))
end

CodesService:withLifecycle({
	init = function(self)
		self._profiles = {} :: { [Player]: any }
		self._last = {} :: { [Player]: number }
	end,

	start = function(self)
		if not CodesConfig.Enabled then
			return
		end
		--- The profile handle off `ProfileReady`, `DailyRewardService`'s pattern.
		Shard.get("GarageService"):getSignal("ProfileReady"):Connect(function(player: Player)
			task.spawn(function()
				local ok, profile = pcall(function()
					return Data:GetProfileAsync(player)
				end)
				if ok and profile and player.Parent == Players then
					self._profiles[player] = profile
				end
			end)
		end)
		Players.PlayerRemoving:Connect(function(player)
			self._profiles[player] = nil
			self._last[player] = nil
		end)
	end,
})

return CodesService
