--[[
	TipsController  (client)
	------------------------
	Writes the tip the server just chose into this player's chat window.

	=== WHY THIS FILE EXISTS AT ALL ============================================================

	It is a two-line job and it needs a whole controller because `TextChannel:DisplaySystemMessage`
	IS A CLIENT CALL. There is no server-side way to put a system line in everybody's chat — see
	`TipsConfig`'s header for what `SendAsync` does instead and why it is not this. So the server
	broadcasts an index and this is the half that turns it into something a player can read.

	=== THE LEGACY-CHAT GUARD ==================================================================

	`TextChatService.ChatVersion` can be `LegacyChatService`, and under it there is no `TextChannels`
	folder at all — the walk below would park on a `WaitForChild` forever and the failure would look
	exactly like a server that had stopped sending. It is checked once, warned about once, and the
	controller stands down. Nothing else in the game changes: a place on legacy chat simply has no
	tips, which is the correct outcome rather than a broken one.

	The check is worth keeping even though this place is on `TextChatService` today, because the
	property is a place setting rather than a code one — nothing in this repo would show up in a
	diff if somebody flipped it in Studio.

	=== THE CHANNEL IS RESOLVED ONCE, LAZILY ===================================================

	`RBXGeneral` is created by Roblox during chat's own startup, which is not ordered against Shard's
	`start`. So the channel is fetched on the FIRST TIP rather than at boot: by then chat has long
	since built itself, and the alternative is a `WaitForChild` in `start` that holds up every
	controller behind this one for a feature that does not matter for another ninety seconds.

	It is then cached, and re-resolved if it ever comes back nil — a channel can legitimately go away
	and return if chat is reset.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local TipsConfig = require(ReplicatedStorage.shared.Configs.TipsConfig)

--- Seconds to wait for chat's own instances on the first tip. Generous: this runs off a timer that
--- is already minutes old, so nothing is being held up by it, and a short timeout on a slow client
--- would silently drop that player's first tip only.
local CHANNEL_WAIT = 10

local TipsController = Shard.new("TipsController")

-- === The channel ============================================================

--- The general channel, cached. Nil while chat is still building itself, or on legacy chat.
function TipsController._channel(self): TextChannel?
	if self._general and self._general.Parent then
		return self._general
	end

	local channels = TextChatService:WaitForChild("TextChannels", CHANNEL_WAIT)
	local general = channels and channels:WaitForChild("RBXGeneral", CHANNEL_WAIT)
	if general and general:IsA("TextChannel") then
		self._general = general
		return general
	end
	return nil
end

-- === Printing ===============================================================

--[[ One tip has arrived. Look it up, and print it if this build has it.

	AN UNKNOWN INDEX PRINTS NOTHING — `TipsConfig.line` returns nil for one, and the reasoning is in
	that file's header: during a soft deploy a server can outrun a client's config by one entry, and
	a blank chat line is a worse answer than no line. ]]
function TipsController._onTip(self, index: unknown)
	local line = TipsConfig.line(index)
	if not line or not self._live then
		return
	end

	local channel = self:_channel()
	if not channel then
		return
	end

	channel:DisplaySystemMessage(line)
end

TipsController:withRemoteEvents({
	{
		ChatTip = function(index: unknown)
			TipsController:_onTip(index)
		end,
	},
})

TipsController:withLifecycle({
	init = function(self)
		self._general = nil :: TextChannel?
		--[[ Set in `start` rather than assumed, so a tip that lands between the remote binding and
			the version check below is dropped instead of walking into the `WaitForChild` the guard
			exists to prevent. ]]
		self._live = false
	end,

	start = function(self)
		if not TipsConfig.Enabled then
			return
		end

		if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
			self.log:warn("This place is on LegacyChatService, which has no TextChannels — chat tips are off.")
			return
		end

		self._live = true
	end,
})

return TipsController
