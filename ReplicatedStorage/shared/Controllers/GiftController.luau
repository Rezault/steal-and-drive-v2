--[[
	GiftController  (client)
	------------------------
	The client half of gifting, and it is deliberately almost nothing: it owns the two remotes, asks
	the server to open a prompt, and republishes what comes back. `Pages/Shop` draws all of it and
	`GiftService` decides all of it.

	=== IT HOLDS NO STATE AND MAKES NO RULINGS ==================================================

	Not who can be gifted, not what a gift costs, not whether the recipient is still here. Every one
	of those is re-checked server-side on the request (`GiftService._onRequest`) and the client's
	copy of the answer would only ever be a stale second opinion. What this sends is a gift KEY and a
	USER ID, which is the whole protocol — see `GiftConfig.RequestName` on why that is also the whole
	trust story.

	=== WHY THE SERVER OPENS THE PROMPT AND NOT THIS ============================================

	`Pages/Shop` opens Roblox's window itself for an ordinary purchase, and its header note 1 is
	proud of it: the page sells nothing, there is no remote, and the server learns about a sale from
	a receipt. A GIFT cannot work that way, and the difference is one fact.

	A RECEIPT CANNOT CARRY A RECIPIENT. So somebody has to write down who the gift is for BEFORE the
	prompt opens, that somebody has to be the server, and it has to happen before the player can
	possibly complete the purchase. A client that opened the window itself and then told the server
	would be racing its own receipt. `GiftService`'s header has the long version.

	SO GIFT MODE IS THE ONE PATH ON THAT PAGE THAT GOES THROUGH A REMOTE, and it still sells nothing:
	the remote asks for a window, the window is Roblox's, and the money still only ever moves on a
	receipt.

	=== IT REPUBLISHES RATHER THAN DRAWING ====================================================

	Same bargain `RadioController` makes with its panel: this has no screen, the shop page may not be
	built when a message lands, and a controller holding a reference to a page is a controller that
	breaks when the page is rebuilt. Both messages go out on `Dispatcher` under their config names
	and whatever is listening draws them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local GiftConfig = require(ReplicatedStorage.shared.Configs.GiftConfig)

local GiftController = Shard.new("GiftController")

GiftController:withRemoteEvents({
	{
		--- server -> client: the status line under the gift picker.
		[GiftConfig.ReplyName] = function(ok: any, message: any)
			Dispatcher:Publish(GiftConfig.ReplyName, ok == true, tostring(message or ""))
		end,

		--- server -> client: somebody in this server just gave you something.
		[GiftConfig.ReceivedName] = function(fromName: any, title: any)
			GiftController:_announce(tostring(fromName or "Someone"), tostring(title or ""))
			Dispatcher:Publish(GiftConfig.ReceivedName, tostring(fromName or "Someone"), tostring(title or ""))
		end,
	},
	GiftConfig.RequestName,
})

--[[ Tell the player, in CHAT, that somebody just gave them something.

	CHAT AND NOT A TOAST, which is a smaller decision than it looks. This game has no general toast
	— the near-miss banner, the quest pop and the weather notice are each their own screen with
	their own timing — so a gift toast would be a fourth one built for a message that arrives at most
	a handful of times a session. Chat already exists, already stacks, already scrolls, and is where
	`TipsController` puts the other thing the game says unprompted.

	IT ALSO PERSISTS, which matters more here than for a tip: a gift can land while the player is
	mid-race with the HUD over everything, and a banner they were not looking at is a gift they
	never learn about. A chat line is still there when the run ends.

	SILENT IF CHAT IS NOT UP. Same call `TipsController._onTip` makes — a blank line or a yield on
	the arrival path is worse than no line, and the gift itself has already landed either way. ]]
function GiftController._announce(self, fromName: string, title: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = channels and channels:FindFirstChild("RBXGeneral")
	if not (general and general:IsA("TextChannel")) then
		return
	end
	general:DisplaySystemMessage(string.format(GiftConfig.ReceivedFormat, fromName, title))
end

--[[ PUBLIC (`Pages/Shop`): ask the server to open the Robux prompt for this gift, for this player.

	IT RETURNS NOTHING AND IT IS NOT A PROMISE. The answer arrives on `GiftConfig.ReplyName` if
	there is one, and for the ordinary case — the prompt opens — there is deliberately no reply at
	all: Roblox's own window appearing is the acknowledgement, and a status line saying "opening the
	prompt" under a prompt that is already open is noise. Only refusals and completed sends talk.

	THE LOCAL CHECKS HERE ARE COURTESY, NOT SECURITY. `GiftService` re-checks every one of them and
	its answers are the ones that count; these exist so an obvious mistake costs a frame instead of
	a round trip. ]]
function GiftController.request(self, giftKey: string, recipient: Player)
	if not GiftConfig.Enabled then
		return
	end
	if not (recipient and recipient.Parent == Players) or recipient == Players.LocalPlayer then
		return
	end
	if not GiftConfig.isSellable(GiftConfig.get(giftKey)) then
		return
	end
	self:getRemoteEvent(GiftConfig.RequestName):Fire(giftKey, recipient.UserId)
end

return GiftController
