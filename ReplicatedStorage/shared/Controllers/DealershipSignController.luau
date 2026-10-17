--[[
	DealershipSignController  (client)
	----------------------------------
	The player's end of the dealership sign: the pencil that opens the rename box, the heart that
	likes somebody else's lot, and the two parts of the sign the server is not allowed to write —
	the owner's custom name, and which heart THIS player is looking at.

	=== WHY THE CLIENT PAINTS THE TITLE AT ALL =================================================

	The name a player types is filtered PER VIEWER (`PlotConfig.Rename` has the reasoning), and a
	SurfaceGui in Workspace shows everybody the same string — there is no per-viewer value of a
	replicated property. So the split is:

	  * the SERVER writes the safe default, "<DisplayName>'s Dealership", which is a name Roblox has
	    already moderated and is therefore fine to show every player at once;
	  * THIS FILE writes the custom name over the top, locally, using the copy the server filtered
	    for this client specifically. A client that was sent nothing simply leaves the default
	    standing, which is exactly what a viewer whose filter hashed the name should be looking at.

	A local write to a replicated instance is client-side only and is never sent back up, so six
	players standing at the same sign can legitimately be reading six different titles.

	=== THE TRAP THAT SHAPES THE REST OF IT ====================================================

	A PROPERTY THE SERVER RE-WRITES TO THE VALUE IT ALREADY HAD DOES NOT REPLICATE. That is the whole
	reason this file has a `_repaint` that composes the default itself rather than "letting the server
	fix it": if the client has locally painted "Midnight Motors" over a sign whose server-side text is
	"Bob's Dealership", and Bob then clears his name, the server sets that title to "Bob's Dealership"
	— which it already was. Nothing changes, nothing replicates, and the sign keeps reading a name
	that no longer exists for the rest of the session.

	So once a title has been overwritten here, this file owns putting it back. `PlotConfig.oneLine`
	and `PlotConfig.defaultTitle` are shared with `PlotService` precisely so the two sides cannot
	disagree about what the default is.

	=== THE HEART IS THE SAME SPLIT, ONE LAYER DOWN ============================================

	The likes pill is one widget every viewer sees, and it is doing two jobs at once: it shows how
	many people have liked this dealership, and it is the button a visitor presses to add one. The
	NUMBER is public and the server writes it onto the replicated sign; the HEART is per-viewer — a
	filled one means "you have already liked this" — so it is written here, locally, off what the
	server sent this client over `DealershipLike`.

	Which is exactly the title's split again, and it is why the pill has two labels inside it rather
	than one string reading "🤍 12": with one, whichever side wrote last would erase the other's half.

	KEYED BY THE OWNER'S USER ID, NOT BY PLOT INDEX, unlike `_names`. A like belongs to a player, so
	"have I liked 12345" survives that player releasing a lot and claiming another one, and no cached
	answer here is ever invalidated by a plot changing hands.

	THE OWNER'S OWN PILL IS A READOUT. Their heart is drawn filled and their press does nothing —
	which is the honest picture, since the count is people liking THEM. It is not access control, and
	`PlotService._onLike` refuses a press on your own lot regardless.

	=== THREE SMALLER THINGS ===================================================================

	1. IT BINDS EVERY SIGN IN THE MAP, BY TAG, exactly like `UpgradeController` binds every upgrade
	   board: `StreamingEnabled` is on, so a plot across the island has no sign in this client's
	   DataModel at boot and gains one when the player walks over. And a Model arrives BEFORE its
	   descendants do, so every hop down to the widgets is a `WaitForChild` — the same bug that once
	   left all 48 upgrade kiosks unbound.

	2. THE PENCIL IS HIDDEN ON LOTS THAT ARE NOT YOURS, locally, because a pencil on somebody else's
	   sign is a lie. It is NOT access control — a hidden button never is — and `PlotService`
	   refuses a rename from anyone who does not hold the plot.

	3. A SURFACEGUI ONLY TAKES INPUT WHILE IT IS `Active`. The `BuildDealershipSigns` command sets
	   it, and this sets it again on bind: a place whose signs were authored before that line existed
	   would otherwise have a pencil that cannot be clicked, and the symptom is indistinguishable
	   from an unbound controller.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Observers = require(ReplicatedStorage.Packages.Observers)
local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local PlotConfig = require(ReplicatedStorage.shared.Configs.PlotConfig)

--- Seconds to wait for each hop of the walk down to the sign's widgets. See note 1.
local SIGN_WAIT = 20

--[[ The heart's press feedback. GEOMETRIC AND NOT A COLOUR CHANGE, the same call `UpgradeController`
	makes about its kiosk buttons: colour on this pill already means something — the stroke is what
	says "you can still like this one" — and a press that recoloured it would be overwriting the one
	piece of state the widget is trying to tell you.

	Kept small and short per the house note on effect intensity. The payoff is the heart filling in
	and the number moving; this is only the acknowledgement that the tap registered. ]]
local PRESS_SCALE = 0.94
local PRESS_TIME = 0.07

--[[ How long a press waits for the server's answer before letting itself be pressed again.

	`PlotService._onLike` answers EVERY request, refusals included, precisely so this never has to
	fire. It is here for the case that guarantee does not cover — a reply lost on the way down —
	because the two failures are not equally bad: a second press costs one refused remote, while a
	heart that stayed disabled would be dead for the rest of the session with nothing to show why. ]]
local REPLY_TIMEOUT = 5

type Bound = {
	index: number,
	plot: Model,
	--- The sign's plate, which the pad's rename prompt hangs on (`PlotConfig.Rename.PadPrompt`).
	part: BasePart,
	title: TextLabel,
	edit: GuiButton,
	--[[ The likes pill and its two dressings, all optional together: a place whose
		`BuildDealershipSigns` has not been re-run has signs without one, which is a working sign
		minus a feature rather than a failed bind. `likeSize` is the pill's authored size, kept so a
		press that lands mid-tween still has something to spring back to. ]]
	like: GuiButton?,
	likeIcon: TextLabel?,
	likeStroke: UIStroke?,
	likeSize: UDim2?,
}

local DealershipSignController = Shard.new("DealershipSignController"):withDependencies({ "RenameController" })

-- === Binding ================================================================

--[[ Walk one plot down to its sign widgets, waiting at every hop.

	Returns nil for a plot that has no sign — which is a legitimate state, not an error: the sign is
	authored by a Command Runner command and a plot that has never had it run on it is still a
	perfectly playable lot. The warning belongs to the server, which says it once at startup. ]]
function DealershipSignController._resolve(self, plot: Model): Bound?
	--[[ Each hop re-checks that the plot is still in the DataModel. Without it, a lot that streams
		out while this is waiting keeps the thread parked for the full timeout on every hop left. ]]
	local function step(parent: Instance?, name: string): Instance?
		if not (parent and plot:IsDescendantOf(game)) then
			return nil
		end
		return parent:WaitForChild(name, SIGN_WAIT)
	end

	--[[ The plate is a DESCENDANT rather than a child — it is built beside the entrance beam, wherever
		in the plot that beam lives — and `WaitForChild` has no recursive form. So this one hop is a
		poll rather than a wait.

		Polled and not hung off `DescendantAdded`, because that signal only fires if something arrives:
		a plot that genuinely has no sign would park the thread on it forever rather than for the
		timeout, and a plot with no sign is a legitimate state (see the note above `_resolve`). ]]
	local part = plot:FindFirstChild(PlotConfig.SignName, true)
	local deadline = os.clock() + SIGN_WAIT
	while not part and os.clock() < deadline and plot:IsDescendantOf(game) do
		task.wait(0.25)
		part = plot:FindFirstChild(PlotConfig.SignName, true)
	end
	if not part then
		return nil
	end

	local gui = step(part, PlotConfig.SignGuiName)
	if not (gui and gui:IsA("SurfaceGui")) then
		return nil
	end
	local panel = gui:FindFirstChildWhichIsA("GuiObject")
	local title = panel and panel:FindFirstChild(PlotConfig.SignTitleName, true)
	local edit = panel and panel:FindFirstChild(PlotConfig.SignEditButtonName, true)
	if not (title and title:IsA("TextLabel") and edit and edit:IsA("GuiButton")) then
		return nil
	end

	-- See note 3: without this the pencil is decoration. A local write, so it costs the server
	-- nothing and heals a sign built before the command set it.
	gui.Active = true

	local index = plot:GetAttribute(PlotConfig.IndexAttribute)
	if type(index) ~= "number" then
		return nil
	end

	--[[ The likes pill, optional on exactly the terms `PlotService._resolveSign` uses — and resolved
		as a group, because a button with no heart in it is not half a feature, it is a sign somebody
		hand-edited. The stroke is found by CLASS rather than by name: it is the only one inside this
		button, so there is no third string for the config and the build command to disagree about. ]]
	local like = panel:FindFirstChild(PlotConfig.SignLikeButtonName, true)
	local likeIcon = like and like:FindFirstChild(PlotConfig.SignLikeIconName, true)
	if not (like and like:IsA("GuiButton") and likeIcon and likeIcon:IsA("TextLabel")) then
		like, likeIcon = nil, nil
	end

	return {
		index = index,
		plot = plot,
		part = part :: BasePart,
		title = title,
		edit = edit,
		like = like,
		likeIcon = likeIcon,
		likeStroke = like and like:FindFirstChildWhichIsA("UIStroke"),
		likeSize = like and like.Size,
	}
end

--[[ One tagged plot has arrived. Bind its sign and hand back the undo.

	The pencil's own press is bound here rather than by tagging it `UIButton`, and that is not an
	oversight. The reason USED to be the offset trap — the hover tween scaled a button by its Size's
	SCALE components only, and every widget on this sign is sized in OFFSET pixels, so a tagged pencil
	tweened to 0x0 the first time a cursor touched it. That was fixed on 2026-08-19 and is no longer
	why. What is: this is a SurfaceGui in Workspace, and the tag forces `Selectable` on so a gamepad
	can reach what it marks — which would put a sign on a building into the engine's selection graph
	alongside the screen UI. Tagging these is a real option the day somebody wants the sounds on them,
	but it is a console-navigation decision and not a free one. Same for `UpgradeController`'s boards
	and `LeaderboardController`'s tabs. A controller reaches the pencil through a prompt instead
	(`_padPencil`), which is how the workshop sign is reached too. ]]
function DealershipSignController._bind(self, plot: Model): (() -> ())?
	--[[ PATH-SCOPED, NOT TAG-ONLY, for the reason `PlotConfig` note 1 gives the server: map work
		leaves tagged COPIES of plots lying around Workspace — `workspace.Plot7` is a full copy of
		Plot1, tagged and claiming `PlotIndex` 1. Binding one would shadow the real plot 1 in
		`_signs`, and every name meant for it would be painted onto a building nobody can see. ]]
	local folder = plot.Parent
	local map = folder and folder.Parent
	if not (folder and folder.Name == PlotConfig.PlotsFolderName and map and map.Name == PlotConfig.MapName) then
		return nil
	end

	local bound = self:_resolve(plot)
	if not bound then
		return nil
	end

	self._signs[bound.index] = bound
	local trove = Trove.new()

	trove:Add(bound.edit.Activated:Connect(function()
		self:_pressPencil(bound)
	end))
	self:_padPencil(bound, trove)

	if bound.like then
		trove:Add(bound.like.Activated:Connect(function()
			self:_pressLike(bound)
		end))
	end

	--[[ Ownership decides two things and they are both re-evaluated on every change: whether this
		client sees a pencil, and — because the default title is composed from the owner — what the
		sign says when there is no custom name to show. ]]
	trove:Add(plot:GetAttributeChangedSignal(PlotConfig.OwnerUserIdAttribute):Connect(function()
		self:_refresh(bound)
	end))
	self:_refresh(bound)

	trove:Add(function()
		if self._signs[bound.index] == bound then
			self._signs[bound.index] = nil
		end
	end)

	return function()
		trove:Destroy()
	end
end

--[[ The pencil's prompt for a CONTROLLER (`PlotConfig.Rename.PadPrompt`): Roblox's own, made on this
	client, on only at this player's own sign while a pad is the device in use. A press is a press of the
	pencil, so `_pressPencil`'s owner check and the rename box's own pad bindings take it from there. ]]
function DealershipSignController._padPencil(self, bound: Bound, trove)
	if not PlotConfig.Rename.Enabled then
		return
	end
	local pad = PlotConfig.Rename.PadPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RenamePadPrompt"
	prompt.ActionText = pad.ActionText
	prompt.ObjectText = pad.ObjectText
	prompt.GamepadKeyCode = pad.Key
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = pad.MaxDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = bound.part
	trove:Add(prompt)

	local function refresh()
		prompt.Enabled = self:_owner(bound.plot) == Players.LocalPlayer.UserId
			and UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
	end
	trove:Add(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refresh))
	trove:Add(bound.plot:GetAttributeChangedSignal(PlotConfig.OwnerUserIdAttribute):Connect(refresh))
	trove:Add(prompt.Triggered:Connect(function()
		self:_pressPencil(bound)
	end))
	refresh()
end

-- === Painting ===============================================================

--- Who owns this lot, from the attributes the server stamps on it. Nil for a free lot.
function DealershipSignController._owner(self, plot: Model): (number?, string?)
	local userId = plot:GetAttribute(PlotConfig.OwnerUserIdAttribute)
	if type(userId) ~= "number" then
		return nil, nil
	end
	local name = plot:GetAttribute(PlotConfig.OwnerNameAttribute)
	return userId, if type(name) == "string" then name else nil
end

--[[ Write the title this client should be reading, and show or hide the pencil.

	THE VACANT LOT IS LEFT ALONE, deliberately. `PlotService` writes "Available Lot" on release and
	that is a real change to the server's own value, so it replicates on its own; composing it here
	as well would mean two writers for a string only one of them has any information about. What
	this file owns is the OWNED states, which are the ones a local write can have overwritten. ]]
function DealershipSignController._refresh(self, bound: Bound)
	local userId, userName = self:_owner(bound.plot)

	bound.edit.Visible = userId ~= nil and userId == Players.LocalPlayer.UserId
	self:_refreshLike(bound, userId)

	if not userId then
		return
	end

	local custom = self._names[bound.index]
	if custom then
		bound.title.Text = PlotConfig.oneLine(custom)
		return
	end

	--[[ The display name off the live Player, falling back to the `OwnerName` attribute. The owner
		is by definition in this server, so the lookup all but always succeeds; the attribute is the
		account name, which is right enough for the frames around a join. ]]
	local owner = Players:GetPlayerByUserId(userId)
	local displayName = if owner then owner.DisplayName else nil
	bound.title.Text = PlotConfig.oneLine(PlotConfig.defaultTitle(displayName, userName))
end

--[[ The server has told this client what it may read as plot `index`'s name. `name` nil means "no
	custom name for you" — either the lot has none, or the filter hashed it for this reader, and the
	client is never told which. Either way the answer is the default title.

	Cached by index rather than applied straight to the widget, because the sign may not be bound
	yet: a name broadcast while that plot is streamed out has to survive until the player walks over
	and `_bind` paints it. ]]
function DealershipSignController._onName(self, index: unknown, name: unknown)
	if type(index) ~= "number" then
		return
	end
	self._names[index] = if type(name) == "string" and name ~= "" then name else nil

	local bound = self._signs[index]
	if bound then
		self:_refresh(bound)
	end
end

-- === The heart ==============================================================

--[[ Draw the heart THIS client should be looking at on one sign.

	WHETHER THE PILL IS SHOWN AT ALL IS NOT DECIDED HERE, and that is the difference between it and
	the pencil. The pill is a readout as much as a button — the count belongs on every claimed sign,
	including the owner's own — so `PlotService._paintLikes` has already made that call for everybody
	and this file has no business second-guessing it. What is local is which of the two hearts is in
	it, and whether it looks pressable.

	YOUR OWN LOT DRAWS AS ALREADY-LIKED. There is nothing for you to press there and the number is
	other people liking you, so a hollow heart inviting a press would be an invitation to a refusal. ]]
function DealershipSignController._refreshLike(self, bound: Bound, userId: number?)
	local button, icon = bound.like, bound.likeIcon
	if not (button and icon) then
		return
	end

	local mine = userId ~= nil and userId == Players.LocalPlayer.UserId
	local liked = mine or (userId ~= nil and self._liked[userId] == true)

	icon.Text = if liked then PlotConfig.Likes.LikedIcon else PlotConfig.Likes.Icon
	button.AutoButtonColor = not liked
	if bound.likeStroke then
		-- The stroke is the whole affordance: a pill you can still act on is outlined, a spent one
		-- is a flat chip. See the colour note in `BuildDealershipSigns`.
		bound.likeStroke.Transparency = if liked then 1 else 0
	end
end

--[[ Acknowledge the tap. Geometric, small and short — see `PRESS_SCALE`.

	Springs back to the pill's AUTHORED size rather than to whatever it measured on the way in: a
	second press landing mid-tween would otherwise read the shrunk size as "full" and walk the widget
	down towards nothing, one press at a time. ]]
function DealershipSignController._pop(self, bound: Bound)
	local button, full = bound.like, bound.likeSize
	if not (button and full) then
		return
	end

	local down = UDim2.new(
		full.X.Scale * PRESS_SCALE,
		full.X.Offset * PRESS_SCALE,
		full.Y.Scale * PRESS_SCALE,
		full.Y.Offset * PRESS_SCALE
	)
	local info = TweenInfo.new(PRESS_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(button, info, { Size = down }):Play()
	task.delay(PRESS_TIME, function()
		if button.Parent then
			TweenService:Create(button, info, { Size = full }):Play()
		end
	end)
end

--[[ Somebody else's lot, so send the like.

	THE OWNERSHIP TEST IS REPEATED HERE rather than trusted from what the pill is drawing, for the
	same reason `_pressPencil` repeats it: a press can outrun a repaint, and a lot that changed hands
	in that window would send a like aimed at a sign showing something the player never read. The
	server refuses a press on your own lot regardless — this is about what the screen promised.

	The already-liked and in-flight tests are LOCAL COURTESY, not a rule. `PlotService._onLike` is the
	only thing that decides whether a like counts; these keep a player from spending presses on an
	answer that is already known. ]]
function DealershipSignController._pressLike(self, bound: Bound)
	if not PlotConfig.Likes.Enabled then
		return
	end

	local userId = self:_owner(bound.plot)
	if not userId or userId == Players.LocalPlayer.UserId then
		return
	end
	if self._liked[userId] or self._pending[userId] then
		return
	end

	self._pending[userId] = true
	task.delay(REPLY_TIMEOUT, function()
		if self._pending[userId] then
			self._pending[userId] = nil
		end
	end)

	self:_pop(bound)
	self:getRemoteEvent("RequestDealershipLike"):Fire(bound.index)
end

--[[ The server has told this client where it stands with one player. `liked` is the answer to every
	request, refusals included, so this is also what re-enables a heart after a press.

	CACHED BY USER ID AND NOT BY PLOT, which is what makes the cache outlive a claim: the answer is
	about a person, so it stays true when they release one lot and take another, and it is worth
	holding for a player who is not currently behind any sign at all — they may walk up to one.

	Every bound sign is repainted rather than a single one looked up, because the message does not
	name a plot and there are six. ]]
function DealershipSignController._onLiked(self, userId: unknown, liked: unknown)
	if type(userId) ~= "number" then
		return
	end
	self._liked[userId] = liked == true
	self._pending[userId] = nil

	for _, bound in self._signs do
		self:_refreshLike(bound, (self:_owner(bound.plot)))
	end
end

-- === The pencil =============================================================

--[[ Their own sign, so open the box with whatever it currently says in it.

	The ownership test is repeated here rather than trusted from `edit.Visible`, because visibility
	is a local write and a press can outrun it — a player standing at a lot at the moment it changes
	hands could otherwise open a box for a dealership that is no longer theirs. The server would
	refuse the save, but the screen would have lied on the way there. ]]
function DealershipSignController._pressPencil(self, bound: Bound)
	local userId = self:_owner(bound.plot)
	if userId ~= Players.LocalPlayer.UserId then
		return
	end

	local rename = self._rename or Shard.get("RenameController")
	self._rename = rename
	if rename and not rename:isOpen() then
		rename:open(self._names[bound.index])
	end
end

DealershipSignController:withRemoteEvents({
	--[[ client -> server: this controller is bound, so send me everything on these signs that is
		mine alone to know — the names I am allowed to read, and whose dealerships I have already
		liked. One ping for both, because it reports one fact. ]]
	"DealershipSignReady",
	-- client -> server (index: number): the heart on plot `index`.
	"RequestDealershipLike",
	{
		DealershipName = function(index: unknown, name: unknown)
			DealershipSignController:_onName(index, name)
		end,

		DealershipLike = function(userId: unknown, liked: unknown)
			DealershipSignController:_onLiked(userId, liked)
		end,
	},
})

DealershipSignController:withLifecycle({
	init = function(self)
		self._trove = Trove.new()
		-- [plot index] = the name this client may read for it. Survives the sign streaming out.
		self._names = {} :: { [number]: string }
		self._signs = {} :: { [number]: Bound }
		--[[ [owner user id] = this client has already liked that player's dealership. By USER ID and
			not by plot, so nothing in here is invalidated when a lot changes hands. ]]
		self._liked = {} :: { [number]: boolean }
		-- [owner user id] = a press is waiting for its answer. Cleared by the reply or by REPLY_TIMEOUT.
		self._pending = {} :: { [number]: boolean }
	end,

	--[[ Bound in `start` and not `init`, the rule every module in this project follows: `init` may
		not yield and this reaches into Workspace. `observeTag` then makes the timing a non-question —
		it fires for the plots that are already here and for every one that streams in later.

		THE PING GOES LAST, after the observer is live. It is a promise that a name sent now will be
		heard, and the handler that hears it needs somewhere to put it. ]]
	start = function(self)
		if not PlotConfig.Enabled then
			return
		end

		self._trove:Add(Observers.observeTag(PlotConfig.PlotTag, function(plot: Instance)
			if not plot:IsA("Model") then
				return nil
			end
			return self:_bind(plot)
		end, { workspace }))

		-- Either feature having something per-viewer to send is reason enough to ping; the server
		-- answers with whichever halves are switched on.
		if PlotConfig.Rename.Enabled or PlotConfig.Likes.Enabled then
			self:getRemoteEvent("DealershipSignReady"):Fire()
		end
	end,
})

DealershipSignController:withCleanup(function()
	if DealershipSignController._trove then
		DealershipSignController._trove:Destroy()
	end
end)

return DealershipSignController
