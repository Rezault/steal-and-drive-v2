--[[
	QuestController  (client)
	-------------------------
	The quest page's wire to the server, and nothing else. Deliberately thin, the same shape
	`WorldController` has with the world-select screen: the server owns what you have done and what
	it pays, the page owns what a row looks like, and this holds the last board either of them saw.

	  • THE BOARD IS ONLY EVER THE SERVER'S. There is no local counter, no optimistic increment and
	    no locally-remembered claim — every number the page draws arrived in a `QuestState`. That is
	    not caution, it is the only shape that can be right: progress moves from six different
	    services (see `QuestService`'s header table), several of which the client cannot observe at
	    all, so a client that tried to keep its own tally would be wrong within one run.

	  • A CLAIM IS A REQUEST, NOT A TRANSACTION. Pressing the pill fires `QuestClaim` and repaints
	    NOTHING. The board that comes back is the answer, and it comes back either way — so a claim
	    the server refuses (already claimed, not finished, a row that is not on today's board) is
	    visibly a claim that did not happen, rather than a row that says CLAIMED over money nobody
	    was paid. Same bargain `WorldController` makes about a teleport.

	  • IT PINGS ON START AND ON EVERY OPEN. The first ping is the handshake `QuestService`'s header
	    note 4 describes — the profile lands long before this controller exists, so the server parks
	    the board and waits to be asked. The later ones are refreshes: the page asks again when it
	    opens, which is what makes a board that changed while the screen was shut correct the moment
	    it comes up, without this file polling anything.

	`QuestConfig.Enabled = false` on the server means no board is ever sent; the page draws its
	empty state and the pill does nothing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dispatcher = require(ReplicatedStorage.Packages.Dispatcher)
local Shard = require(ReplicatedStorage.Packages.Shard)
local QuestConfig = require(ReplicatedStorage.shared.Configs.QuestConfig)

local QuestController = Shard.new("QuestController")

QuestController:withRemoteEvents({
	-- client -> server: send me the board. A handshake on start, a refresh on every page open.
	"QuestReady",
	-- client -> server (id): press the green pill on this quest.
	"QuestClaim",
	{
		-- server -> client (board): the whole board. The only thing that ever changes what is drawn.
		QuestState = function(board)
			QuestController:_onState(board)
		end,
	},
})

-- === What the page draws ====================================================

--[[ The last board the server sent, or nil if it has not sent one yet.

	NIL AND EMPTY ARE DIFFERENT and the page distinguishes them: nil is "we have not heard yet",
	which is the first second of a session and wants no empty-state message; an empty `quests` list
	is the server saying there is nothing today, which does. ]]
function QuestController.board(self)
	return self._board
end

--[[ Ask for the board again. Called by the page as it opens.

	Cheap enough not to need a guard — one empty remote call and three rows back — but it IS guarded
	against the case where nothing has started yet, because a page can be constructed before this
	controller's `start` has run and firing a remote from there would be a call into a nil. ]]
function QuestController.refresh(self)
	if not self._started then
		return
	end
	self:getRemoteEvent("QuestReady"):Fire()
end

--[[ Press the pill on one quest.

	It re-checks locally first, and that check is COURTESY rather than permission — `QuestService`
	re-derives every part of it from state this client never touched. What it buys is that the
	obvious dead press (a claimed row, an unfinished one) never leaves the machine, which is the
	same courtesy `WorldController.canTeleport` does for a locked world. ]]
function QuestController.claim(self, id: string?)
	if not (self._started and id) then
		return
	end
	local quest = self:questOf(id)
	if not quest or quest.Claimed or quest.Progress < quest.Target then
		return
	end
	self:getRemoteEvent("QuestClaim"):Fire(id)
end

--- One row of the current board by id, or nil. The page looks a row up at press time rather than
--- closing over an index, so a board arriving mid-press cannot claim the wrong quest.
function QuestController.questOf(self, id: string?)
	if not (self._board and id) then
		return nil
	end
	for _, quest in self._board.quests do
		if quest.Id == id then
			return quest
		end
	end
	return nil
end

--[[ A board arrived. Store it and tell the page.

	NOT VALIDATED BEYOND ITS SHAPE. This is the server talking, and the fields it sends are the
	fields the page reads; a defensive re-derivation here would be a second opinion about a number
	that has exactly one source. The shape check is for the disabled case and for a hot reload
	mid-flight, where a nil can genuinely arrive. ]]
function QuestController._onState(self, board)
	if type(board) ~= "table" or type(board.quests) ~= "table" then
		return
	end
	self._board = board
	Dispatcher:Publish(QuestConfig.StateEvent)
end

QuestController:withLifecycle({
	init = function(self)
		self._board = nil
		self._started = false
	end,

	start = function(self)
		self._started = true
		--[[ The handshake. Fired unconditionally rather than only when the page first opens, so the
			board is already in hand the first time the player presses QUESTS — a screen that is
			finished when it appears rather than one assembling itself, which is the same reason the
			page builds its rows in `initialize`. ]]
		self:refresh()
	end,
})

return QuestController
