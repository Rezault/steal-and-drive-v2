--[[
	CarDealController  (client)
	---------------------------
	WHAT A CAR DEAL LOOKS LIKE. `CarDealService` puts three cars on three plinths in the plaza and
	prices them; everything a player actually sees standing next to one is built here.

	    [ friend's avatar ] ---- bubble over their head ----> "GVISTIC IS SELLING / CAMARO / $37,000"
	           |                                             ...and, in range, the BUY CAR pill
	           |                                             ...and, once you are near enough to
	           |                                                 read it, "NEW CAR IN 4:32" under it

	=== THE SELLER IS YOURS AND NOBODY ELSE'S =================================================

	The person beside the car is one of YOUR friends, built on this client from your own friends
	list. The car, the price and the clock are the server's and identical for everybody in the
	server; the face is not, and two players standing at the same stand are being sold the same car
	by two different people.

	That split is the opposite of `CustomerService`'s, which builds its showroom crowd on the SERVER,
	and the reason is worth being clear about because the two look like the same feature: a customer
	HANDS OVER CASH and stands in a lot other players walk through, so it has to exist for everyone
	and be written by the only thing allowed to write money. A seller does neither. The money moves
	on a prompt the server owns and re-checks from scratch; the person is chrome, and chrome that is
	personal costs one client its own three web calls instead of costing the server thirty.

	=== FIVE THINGS THAT ARE NOT OBVIOUS ======================================================

	1. THE BUBBLE IS PINNED TO THE PLINTH, NOT TO THE SELLER'S HEAD. Building a friend's avatar is
	   three web calls deep and any of them can fail; a sign hanging off a head that never arrives is
	   a market with no prices in it. Adorned to the stand's `BubbleAnchor` attachment, the seller is
	   free to turn up late, not turn up at all, or be a different person next rotation, and the
	   price never moves.

	2. THE STANDS ARE FOUND BY TAG, NOT BY WALKING A FOLDER. StreamingEnabled is on: a stand appears
	   and disappears from this client as the player crosses the island, and `Workspace.CarDeals` may
	   not exist here at all. `GetInstanceAddedSignal` covers all of that with one subscription. The
	   stands are `ModelStreamingMode.Atomic`, which is what makes it safe to walk a stand's children
	   on the frame its tag fires — see the memory note on tags firing before descendants replicate.

	3. THE BUY BUTTON IS A `ProximityPrompt` WEARING OUR CLOTHES. `Style = Custom` means Roblox draws
	   nothing and we draw the pill, but the INPUT is still entirely the engine's: the key, the
	   gamepad button, the hold timer, the range check and the `Triggered` that reaches the server all
	   belong to the prompt. The one thing Custom takes away is the touch tap target, so `_bindPill`
	   puts a transparent button over the pill and drives `InputHoldBegin`/`InputHoldEnd` from it —
	   which is exactly what Roblox's own reference implementation of a custom prompt does.

	4. EVERYTHING THE BUBBLE SAYS IS READ, NEVER TOLD. The offer is four attributes on the stand, the
	   collection is `GarageConfig.OwnedAttribute` and the balance is `CashAttribute` — all replicated,
	   all written by the server, none of them asked for. So a bubble is redrawn by the same code path
	   whether the offer rotated, the player bought the car, or their cash changed somewhere else
	   entirely, and the three can never disagree.

	5. NOTHING HERE IS AUTHORITATIVE. The pill greys out when you cannot afford a car and the sign
	   says ALREADY YOURS when you own one, and both are courtesies: the server re-checks every one
	   of them on the press. A client that lied about any of it would get a refusal and no car.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local CarDealConfig = require(ReplicatedStorage.shared.Configs.CarDealConfig)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
-- Dealer visuals use lightweight server-published display templates.
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local RigAnimator = require(ReplicatedStorage.shared.Modules.RigAnimator)
local NpcFriends = require(ReplicatedStorage.shared.Modules.NpcFriends)
--- The buyer offer's billboard, reused as this sign (`Bubble.KitStyle`).
local BuyerOfferSign = require(ReplicatedStorage.shared.Modules.BuyerOfferSign)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local CarDealController = Shard.new("CarDealController")

--[[ Hard stop on how many pages of the friends list `_friendList` will walk, whatever
	`Dealer.Friends.Scan` asks for — the same bound, for the same reason, as
	`StealController.MAX_FRIEND_PAGES` and `CustomerService`'s: this is a loop whose exit condition
	belongs to a web service, and a service that answers "not finished, nothing here" forever must
	not take a session with it. A page is 50. ]]
local MAX_FRIEND_PAGES = 4

--- Where every locally-built seller lives. Client-side only, so it replicates nowhere and is
--- invisible to every server-side query in the game.
local SELLER_FOLDER = "CarDealSellers"

local FONT = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold)

--- One face, built once and cloned per stand. `name` is nil for the fallback dealers, which get no
--- name on the bubble at all (`CarDealConfig.Dealer.Fallback`).
type Face = { model: Model, name: string? }

type Pill = {
	holder: Frame,
	box: Frame,
	fill: ImageLabel,
	clip: Frame,
	label: TextLabel,
	key: Frame,
	keyLabel: TextLabel,
	keyImage: ImageLabel,
	button: TextButton,
	--- Widths as fractions of the PANEL, worked out once from the bubble's own aspect. See
	--- `_buildPill` for why an aspect constraint is the wrong tool here.
	pillWidth: number,
	keyWidth: number,
	gap: number,
	rowY: number,
	rowHeight: number,
}

--- The strip under the sign, and the two pieces of state one frame of it needs to know.
type Clock = {
	strip: Frame,
	text: TextLabel,
	scale: UIScale,
	shown: boolean,
	--- The whole second the line was last written at, so it is rebuilt once a second rather than on
	--- each of the sixty frames that second contains.
	lastWhole: number?,
}

type Deal = {
	index: number,
	model: Model,
	--- What the bubble is adorned to, kept because the clock measures its distance to the SIGN.
	anchor: Attachment,
	--- The bay's floor, which is what both attachments hang off. Kept because a rotation MOVES the
	--- whole bay now, and this is the part whose CFrame changing is how a client hears about it.
	base: BasePart?,
	prompt: ProximityPrompt?,
	gui: BillboardGui,
	panel: GuiObject,
	--- The buyer sign's money ramp on the price, set only on the kit sign (`Bubble.KitStyle`). It
	--- MULTIPLIES the text colour, so a red or grey price has to switch it off to read as red or grey.
	priceTint: UIGradient?,
	--- The kit caption's own ink, put back after the OWNED state recolours it.
	captionInk: Color3?,
	seller: TextLabel,
	body: TextLabel,
	priceCaption: TextLabel,
	price: TextLabel,
	pill: Pill,
	clock: Clock?,
	rig: Model?,
	anim: any?,
	--- The template this stand's seller was cloned from, so no two stands wear the same face and a
	--- re-dress with the same face is a no-op rather than a rebuild.
	faceTemplate: Model?,
	sellerName: string?,
	--- Whether the car on this stand is already in the collection, cached from the last redraw so
	--- the pill does not have to work it out again when the prompt appears.
	owned: boolean,
	holdTween: Tween?,
	holdValue: NumberValue?,
	holdConnection: RBXScriptConnection?,
	trove: any,
}

-- === Small helpers ==========================================================

--- One row of the bubble. Every one of them is `TextScaled` into a band of the panel's own height,
--- which is what keeps the five rows in proportion at any distance and on any screen.
local function label(parent: Instance, name: string, row, colour: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.fromScale(0.5, row.Y)
	text.Size = UDim2.fromScale(0.92, row.Height)
	text.BackgroundTransparency = 1
	text.FontFace = FONT
	text.TextColor3 = colour
	text.TextScaled = true
	text.Text = ""
	text.Parent = parent
	return text
end

-- === The faces ==============================================================

--[[ Everything a fresh rig needs before it can stand next to a car.

	A PUPPET, NOT A CHARACTER, in the same shape and for the same reasons as
	`StealController.prepareDriverRig`: the Humanoid is kept (strip it and the rig loses its clothes)
	but switched off, the root is anchored, and every part is uncollidable, massless and query-blind.

	THAT IS WHY THERE IS NO COLLISION GROUP HERE, unlike `CustomerService`'s walking crowd. A
	customer has to WALK, so it needs a live Humanoid, which means it needs to collide with the floor,
	which is why collidability had to become a property of a pair of groups. A seller stands still.
	An anchored assembly with `CanCollide` off is not solid to anybody and cannot fall through
	anything, and it costs nothing to say so.

	Returns nil for a rig with no root, which is the one failure nothing here can work around. ]]
local function prepareSellerRig(model: Model, displayName: string?): Model?
	for _, inst in model:GetDescendants() do
		if inst:IsA("BaseScript") then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
			inst.Anchored = false
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.Massless = true
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
		humanoid.EvaluateStateMachine = false
		humanoid.PlatformStand = true
		--[[ Stamped so the rig is identifiable in the explorer during a playtest, and never DRAWN —
			the name belongs on the bubble, where it is part of the sentence, and a tag over the head
			would sit in exactly the space the bubble occupies. ]]
		if displayName and displayName ~= "" then
			humanoid.DisplayName = displayName
		end
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
	end

	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not (root and root:IsA("BasePart")) then
		model:Destroy()
		return nil
	end
	root.Anchored = true
	model.PrimaryPart = root
	model.Name = "Seller"
	model.Archivable = true
	return model
end

--[[ The nameless dealers, built once for the session and shared by every stand.

	`CreateHumanoidModelFromDescription` IS A WEB CALL AND IT YIELDS, which is why every rig in this
	file is a template built off the critical path and cloned later.

	R15 EXPLICITLY, and not "whatever the player wears": the idle clip in `Dealer.Animations` is the
	stock R15 one, and an R6 rig would load a track driving joints it does not have and stand there
	in an A-pose. This is not the player.

	A HAND-COLOURED description rather than an empty one — an empty `HumanoidDescription` builds a
	BLACK avatar, which reads as a bug rather than as a person. See `CarDealConfig.Dealer.Fallback`. ]]
function CarDealController._buildFallbackFaces(self)
	task.spawn(function()
		for _, palette in CarDealConfig.Dealer.Fallback.Palettes do
			local ok, model = pcall(function()
				local desc = Instance.new("HumanoidDescription")
				desc.HeadColor = palette.Head
				desc.TorsoColor = palette.Body
				desc.LeftArmColor, desc.RightArmColor = palette.Limbs, palette.Limbs
				desc.LeftLegColor, desc.RightLegColor = palette.Limbs, palette.Limbs
				return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
			end)
			if ok and model then
				local rig = prepareSellerRig(model, nil)
				if rig then
					table.insert(self._fallback, { model = rig, name = nil } :: Face)
				end
			end
		end

		if #self._fallback == 0 then
			self.log:warn("No fallback seller rigs could be built — the stands will have prices and nobody standing at them.")
		end
		self:_dressAll()
	end)
end

--[[ Read the local player's friends list, as far as `Friends.Scan` and no further.

	EVERY LAYER IS pcall'd BECAUSE EVERY LAYER IS A WEB CALL. `GetFriendsAsync` throws on a throttle
	and on a user id the backend will not answer for, which includes a Studio session with nobody
	logged in. Whatever we have when it breaks is what we use; an empty list is a valid answer and
	means "nameless dealer", not "error".

	`IsFinished` is checked AFTER reading a page rather than before, because the first page is already
	loaded when the object arrives — advancing first would skip it. ]]
function CarDealController._friendList(self, userId: number, limit: number): { { id: number, name: string? } }
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(userId)
	end)
	if not (ok and pages) then
		return {}
	end

	local friends = {}
	for _ = 1, MAX_FRIEND_PAGES do
		local read = pcall(function()
			for _, item in pages:GetCurrentPage() do
				local id = tonumber(item.Id)
				if NpcFriends.isUsable(item) then
					local name = item.DisplayName
					if not name or name == "" then
						name = item.Username
					end
					table.insert(friends, { id = id, name = name })
				end
			end
		end)
		if not read or #friends >= limit or pages.IsFinished then
			break
		end
		if not pcall(function()
			pages:AdvanceToNextPageAsync()
		end) then
			break
		end
	end
	return friends
end

--[[ Put your friends behind the counter: up to `Friends.Count` real avatars, built once at start-up
	and cloned per stand for the rest of the session.

	SHUFFLED THEN TAKEN, not taken then shuffled, so the pick is over everyone read rather than over
	the first three — otherwise a player with 200 friends is sold to by the same three people for the
	life of the game.

	FAILING ONE FRIEND IS NOT FAILING. A private account, a deleted user, a description the backend
	will not serve: each drops that id and moves to the next, and a pool that comes back short or
	empty simply means `_pickFace` reaches for the nameless dealers.

	Deliberately NOT retried and deliberately NOT re-run per rotation: this runs once, and whatever
	it produces is the session's cast. A player who joins with the friends endpoint down gets
	strangers for that session, which is a fine outcome for a cosmetic and a much better one than a
	retry loop against a rate limit. ]]
function CarDealController._buildFriendFaces(self)
	local cfg = CarDealConfig.Dealer.Friends
	if not cfg.Enabled or self._friendsPending then
		return
	end
	local player = Players.LocalPlayer
	if not player then
		return
	end
	self._friendsPending = true

	task.spawn(function()
		local want = math.max(cfg.Count, 0)
		local friends = self:_friendList(player.UserId, math.max(cfg.Scan, want))
		for i = #friends, 2, -1 do
			local j = self._rng:NextInteger(1, i)
			friends[i], friends[j] = friends[j], friends[i]
		end

		for _, friend in friends do
			if #self._faces >= want then
				break
			end
			local gotDesc, desc = pcall(function()
				return Players:GetHumanoidDescriptionFromUserId(friend.id)
			end)
			if gotDesc and desc then
				local gotRig, model = pcall(function()
					return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
				end)
				if gotRig and model then
					local rig = prepareSellerRig(model, friend.name)
					if rig then
						table.insert(self._faces, { model = rig, name = friend.name } :: Face)
					end
				end
			end
		end

		self._friendsPending = false
		if #self._faces == 0 then
			self.log:info("No friend avatars for the car deal sellers; using the nameless dealers.")
		else
			self.log:info(string.format("%d friend face(s) built for the market.", #self._faces))
		end
		--- Stands that streamed in while those web calls were out are wearing whatever was available
		--- then. This is what upgrades them.
		self:_dressAll()
	end)
end

--[[ Which face stand `index` wears.

	NOT THE SAME FACE TWICE ON THE RING, while still being random: faces already worn by a live stand
	are taken out of the pool and the pick is over what is left. With three faces and three stands
	that means the player never sees the same friend at two plinths, which is the one thing that
	would give away that these are clones. ]]
function CarDealController._pickFace(self, exclude: { [Model]: boolean }): Face?
	local pool = if #self._faces > 0 then self._faces else self._fallback
	if #pool == 0 then
		return nil
	end

	local free = {}
	for _, face in pool do
		if not exclude[face.model] then
			table.insert(free, face)
		end
	end

	local choices = if #free > 0 then free else pool
	return choices[self._rng:NextInteger(1, #choices)]
end

-- === Standing a seller at a stand ===========================================

--[[ Stand this stand's seller on its mark.

	CALLED AGAIN WHENEVER THE BAY MOVES, which since the market stopped living on a fixed ring is
	every rotation. The rig is NOT a child of the stand: it is built here, out of the local player's
	own friends list, and parented to this controller's own folder, so a Model the server pivots to
	the other side of the island takes its paint, its prompt and its sign with it and leaves the
	person standing in an empty road. `_bind` watches the bay's floor for exactly that.

	PLACED BY THE ROOT, not by the model's bounding box: `prepareSellerRig` sets `PrimaryPart` to the
	HumanoidRootPart for this, because a rig pivoted by its box sinks into the road by half a torso.

	AND THE HEIGHT IS THE RIG'S OWN, not a constant. `HipHeight + root height / 2` is where a
	standing R15 puts its root above its feet, and it is not the same number twice: measured on three
	live friend rigs it ran 2.6 to 3.4 studs depending on avatar scale. A fixed offset floats the
	short ones and buries the tall ones, which beside a car for sale is the difference between a
	person and a decal. `Dealer.RootHeight` is only the answer for a rig with no Humanoid to ask.

	IDEMPOTENT AND CHEAP TO CALL SPECULATIVELY. A rig already standing where it belongs is left
	alone, which is what lets the two callers below both fire on a rotation without one of them
	rebuilding the other's work: the property signal and the attribute burst arrive in whichever
	order replication feels like, and only the first of them does anything. ]]
function CarDealController._seatRig(self, deal: Deal)
	local rig = deal.rig
	if not rig then
		return
	end

	local mark = deal.model:FindFirstChild(CarDealConfig.Names.DealerStand, true)
	if not (mark and mark:IsA("Attachment")) then
		return
	end

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local root = rig.PrimaryPart
	local lift = if humanoid and root
		then humanoid.HipHeight + root.Size.Y / 2
		else CarDealConfig.Dealer.RootHeight

	local target = (mark :: Attachment).WorldCFrame * CFrame.new(0, lift, 0)
	if (rig:GetPivot().Position - target.Position).Magnitude < 0.05 then
		return
	end
	rig:PivotTo(target)
end

--[[ Clone a face, stand it on the seller's mark and start it breathing.

	IT IS RE-RUN, NOT BUILT ONCE. The friend rigs arrive several web calls after the first stand
	streams in, so a stand dressed early is wearing a stranger; `_dressAll` calls back through here
	when a better pool lands, and the seller quietly becomes somebody the player knows.

	A ROTATION DOES NOT RE-DRESS. The same person sells whatever is in their bay and walks it to the
	next one, which is what makes them read as a dealer with a pitch rather than as part of the
	offer. What a rotation does do is MOVE them, and that is `_seatRig`. ]]
function CarDealController._dress(self, deal: Deal)
	local dealer = CarDealConfig.Dealer
	if not dealer.Enabled then
		return
	end

	local stand = deal.model:FindFirstChild(CarDealConfig.Names.DealerStand, true)
	if not (stand and stand:IsA("Attachment")) then
		return
	end

	--- Faces standing at another plinth right now. Recorded per stand rather than read back off the
	--- clones, so "who is already out there" is a fact this file owns rather than one it infers.
	local worn: { [Model]: boolean } = {}
	for _, other in self._deals do
		if other ~= deal and other.faceTemplate then
			worn[other.faceTemplate] = true
		end
	end

	local face = self:_pickFace(worn)
	if not face then
		return
	end
	--- Already wearing this one. Re-dressing would rebuild a rig to look identical.
	if deal.faceTemplate == face.model then
		return
	end

	--- The clip is stopped BEFORE the rig goes, not after: `stop` walks tracks that belong to an
	--- Animator inside it, and stopping a track on a destroyed rig is a call into nothing.
	self:_undress(deal)

	local rig = face.model:Clone()

	--- Stood on the mark before it is parented, so it never appears at the roster template's own
	--- pose for a frame. `_seatRig` is where the placement itself is written down.
	deal.rig = rig
	self:_seatRig(deal)
	rig.Parent = self._sellers

	deal.faceTemplate = face.model
	deal.sellerName = face.name

	if dealer.Animations.Enabled then
		local anim = RigAnimator.new(rig, dealer.Animations.Clips)
		if anim then
			anim:play("Idle", 0)
			deal.anim = anim
		end
	end

	--- The bubble does not move (it is adorned to the stand, not to the head), but the sentence on it
	--- names the seller, so it is redrawn the moment one arrives.
	self:_redraw(deal)
end

--- Take the seller away: the clip first, then the rig. Called by a re-dress and by a teardown, so
--- the ordering above lives in one place rather than at both call sites.
function CarDealController._undress(self, deal: Deal)
	if deal.anim then
		deal.anim:stop(0)
		deal.anim = nil
	end
	if deal.rig then
		deal.rig:Destroy()
		deal.rig = nil
	end
	deal.faceTemplate = nil
	deal.sellerName = nil
end

--- Re-dress every live stand. Called when a better pool of faces lands.
function CarDealController._dressAll(self)
	for _, deal in self._deals do
		self:_dress(deal)
	end
end

-- === The bubble =============================================================

--[[ Build the sign: five stacked rows on a kit panel, adorned to the stand's own attachment.

	`AlwaysOnTop` is OFF, deliberately. The car is the thing being sold and the bubble hangs beside
	it; drawn through the car it would be a price tag floating inside a bonnet. Everything it needs
	to be readable from is open plaza. ]]
function CarDealController._buildBubble(self, deal: Deal, anchor: Attachment)
	local cfg = CarDealConfig.Bubble
	local rows = cfg.Rows
	local clock = cfg.Clock

	--[[ The billboard is the panel PLUS the clock strip hanging under it, and the panel is then
		given back exactly `Size.Y` studs of that. Doing it in this order is what keeps `Rows` and
		`_buildPill` — which are both fractions of the panel — untouched by the strip existing. ]]
	local total = cfg.Size.Y + (if clock.Enabled then clock.Gap + clock.Height else 0)

	local gui = Instance.new("BillboardGui")
	gui.Name = string.format("CarDeal%d", deal.index)
	gui.Adornee = anchor
	gui.Size = UDim2.fromScale(cfg.Size.X, total)
	--- Half the bubble's own height plus the gap, so `HeadOffset` is the clearance between the top of
	--- the seller and the bottom of the sign rather than a number measured to its centre.
	gui.StudsOffset = Vector3.new(0, total / 2 + cfg.HeadOffset, 0)
	gui.MaxDistance = cfg.MaxDistance
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Active = true
	deal.gui = gui

	--- The buyer's sign when this place has it (`Bubble.KitStyle`); nil falls through to the panel.
	local kit = if cfg.KitStyle and UIRoot.isNewUI() then BuyerOfferSign.buildKit(gui, cfg.Size.Y / total, 0) else nil
	local kitPanel = kit and kit.who:FindFirstAncestor("Panel")
	local kitMain = kit and kit.body.Parent
	if kit and kitPanel and kitMain and kitMain:IsA("GuiObject") then
		deal.panel = kitPanel
		deal.seller, deal.body, deal.priceCaption, deal.price = kit.who, kit.body, kit.caption, kit.price
		deal.priceTint = kit.price:FindFirstChildOfClass("UIGradient")
		deal.captionInk = kit.caption.TextColor3
		kit.value.Visible, kit.rating.Visible = false, false
		--[[ The pill takes the band from the top of Comparison to the bottom of Rating, worked out in
			PANEL fractions, because `_buildPill`'s width maths assumes the panel's aspect.
			Every box in the template is centre-anchored (`BuildBuyerOfferV2`'s `setBox`), so
			edge = centre -/+ size / 2, nested through Main's own box. ]]
		local function panelY(label: GuiObject, edge: number): number
			local inMain = label.Position.Y.Scale + edge * label.Size.Y.Scale / 2
			return kitMain.Position.Y.Scale + (inMain - 0.5) * kitMain.Size.Y.Scale
		end
		local top, bottom = panelY(kit.value, -1), panelY(kit.rating, 1)
		deal.pill = self:_buildPill(kitPanel, { Y = top, Height = bottom - top })
		--- Over the white body, which is the pill's sibling here (the template is built for Sibling order).
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		deal.pill.holder.ZIndex = kitMain.ZIndex + 1
		if clock.Enabled then
			deal.clock = self:_buildClock(gui, total)
		end
		gui.Parent = self._gui
		deal.trove:Add(gui)
		return
	end

	--[[ THE KIT'S PAGE PANEL, one texture — 2026-08-26. It was a `#364157` Frame with a `UICorner`
		and a `#0066FF` `UIStroke`, which is the rounded-rect-and-neon-outline the plot signage, the
		customer bubbles and the sell lot were all rebuilt to get away from.

		ONLY THE BACKGROUND AND THE CORNER MOVED. The five rows are where they were, and the pill below
		them is untouched — it was already the kit's own art and already right. What this buys is the
		things a `UICorner` cannot draw: the 5px `#151D2D` border, the 5px `#384769` inner rim, the
		checkerboard weave, and corners that belong to the drawing instead of being clipped out of a
		rectangle.

		`Stretch`, never `Slice`: `Bubble.Size` is set from this texture's own 1023x644, so the stretch
		is the identity and there is no `SliceCenter` to be measured against a texture Roblox silently
		downscaled. `UIAssets.Slice` has the argument. ]]
	local panel = Instance.new("ImageLabel")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, cfg.Size.Y / total)
	panel.Image = UIAssets.url(UIAssets.Page.Panel)
	panel.ScaleType = Enum.ScaleType.Stretch
	panel.BackgroundColor3 = cfg.Colors.Face
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Parent = gui

	deal.gui = gui
	deal.panel = panel
	deal.seller = label(panel, "Seller", rows.Seller, cfg.Colors.Caption)
	deal.body = label(panel, "Body", rows.Body, Color3.new(1, 1, 1))
	deal.priceCaption = label(panel, "PriceCaption", rows.PriceCaption, cfg.Colors.Caption)
	deal.price = label(panel, "Price", rows.Price, cfg.Colors.Price)
	deal.pill = self:_buildPill(panel, rows.Pill)
	if clock.Enabled then
		deal.clock = self:_buildClock(gui, total)
	end

	gui.Parent = self._gui
	deal.trove:Add(gui)
end

--[[ The clock strip: a capsule hanging under the sign with one rich-text line in it.

	A SEPARATE FRAME UNDER THE PANEL AND NOT A SIXTH ROW OF IT, which is the whole reason it can come
	and go. A row inside the panel would leave a hole in the sign every time the player walked away
	from it; a tag hanging off the bottom is simply not there, and the sign above it never changes
	shape. It is also why it is narrower — see `Clock.Width`.

	BUILT ONCE PER STAND EVEN THOUGH ALL THREE COUNT DOWN TOGETHER. They fade independently (a player
	can be near one sign and not the others) and they are children of a billboard that is already
	streaming in and out with its stand, so there is nothing shared for a single instance to hang
	off. `_stepClocks` does the work once and only the drawing three times. ]]
function CarDealController._buildClock(self, gui: BillboardGui, total: number): Clock
	local cfg = CarDealConfig.Bubble.Clock

	local strip = Instance.new("Frame")
	strip.Name = "Clock"
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.fromScale(0.5, 1)
	strip.Size = UDim2.fromScale(cfg.Width, cfg.Height / total)
	strip.BackgroundColor3 = cfg.PanelColor
	--- Invisible in both senses to start with: transparent so the first fade has somewhere to come
	--- from, and `Visible` off so a strip nobody has walked near is not drawn at all.
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Visible = false
	strip.Parent = gui

	local corner = Instance.new("UICorner")
	--- Half of the shorter side, which on a strip this shape is a capsule at any screen size.
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = strip

	--- The pulse over the last few seconds lives here rather than on the strip's `Size`, so it
	--- scales about the strip's own centre and cannot fight the fade for a property.
	local scale = Instance.new("UIScale")
	scale.Parent = strip

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.fromScale(0.86, 0.66)
	text.BackgroundTransparency = 1
	text.FontFace = FONT
	--- `CarDealConfig.clockLine` colours the number with a `<font>` tag; this is the caption's colour
	--- and the tag's fallback.
	text.RichText = true
	text.TextColor3 = cfg.CaptionColor
	text.TextTransparency = 1
	text.TextScaled = true
	text.Text = ""
	text.Parent = strip

	return { strip = strip, text = text, scale = scale, shown = false, lastWhole = nil } :: Clock
end

--[[ The BUY CAR pill and the key beside it.

	THE ART IS THE KIT'S OWN GREEN PILL, straight out of `UIAssets.Pill.Green`, on `ScaleType.Stretch`
	— never 9-sliced. `UIAssets`' own note says why at length: every pill in this game is aspect-locked
	and only ever shrinks uniformly, and a slice holds the corner radius at 1:1 texture pixels, so a
	shrunk pill comes out a lozenge.

	=== AND THE ASPECT IS ARITHMETIC, NOT A CONSTRAINT ========================================

	A `UIAspectRatioConstraint` is the obvious tool and it is the wrong one here, for the reason
	`GetawayHudController` records: `FitWithinMaxSize` resolves a zero-width box to NOTHING rather
	than deriving the width from the aspect, and inside a list layout there is no width to give it
	that is not already the answer. But a billboard has something a screen does not — a FIXED,
	KNOWN aspect of its own, `Bubble.Size`. So the pill's width in panel-scale is just

	    rowHeight * pillAspect / bubbleAspect

	which is exact, needs no constraint, and cannot collapse. Everything on this row is placed from
	that number.

	THE HOLD FILLS THE PILL LEFT TO RIGHT using the artist's OWN two faces: the idle green underneath,
	the hover green above it inside a frame that grows from nothing. Same bar language as the nitro
	and HP gauges, painted in art that is already in the kit. ]]
function CarDealController._buildPill(self, panel: GuiObject, row): Pill
	local cfg = CarDealConfig.Bubble
	local bubbleAspect = cfg.Size.X / cfg.Size.Y
	local pillAspect = UIAssets.Size.Pill.X / UIAssets.Size.Pill.Y

	local pillWidth = row.Height * pillAspect / bubbleAspect
	--- The key box is square and a little shorter than the pill, so it reads as sitting beside the
	--- button rather than as part of it.
	local keyHeight = row.Height * 0.82
	local keyWidth = keyHeight / bubbleAspect
	local gap = 0.018

	--[[ The left margin the row starts at, and it exists because the panel HAS A BORDER NOW.

		This row used to start at x = 0 and that was fine against a flat frame with a `UICorner` on it:
		there was nothing at the edge for the pill to collide with. `UIAssets.Page.Panel` draws a 5px
		`#151D2D` border and a 5px `#384769` inner rim into the texture, and flush left the pill's
		rounded cap sat straight on top of both — the button read as hanging off the side of the sign
		rather than as sitting on it.

		0.04 is not a new number: every text row on this sign is `UDim2.fromScale(0.92, ...)` centred,
		which is the same 4% margin on each side. The pill lines up with the type above it now, where
		before it started a little to the left of all of it. ]]
	local inset = 0.04

	local holder = Instance.new("Frame")
	holder.Name = "Buy"
	holder.Position = UDim2.fromScale(0, row.Y)
	holder.Size = UDim2.fromScale(1, row.Height)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = panel

	local pillBox = Instance.new("Frame")
	pillBox.Name = "Pill"
	pillBox.AnchorPoint = Vector2.new(0, 0.5)
	pillBox.Position = UDim2.fromScale(inset, 0.5)
	pillBox.Size = UDim2.fromScale(pillWidth, 1)
	pillBox.BackgroundTransparency = 1
	pillBox.Parent = holder

	local idle = Instance.new("ImageLabel")
	idle.Name = "Idle"
	idle.Size = UDim2.fromScale(1, 1)
	idle.BackgroundTransparency = 1
	idle.Image = "rbxassetid://" .. tostring(UIAssets.Pill.Green.Idle)
	idle.ScaleType = Enum.ScaleType.Stretch
	idle.Parent = pillBox

	local clip = Instance.new("Frame")
	clip.Name = "HoldClip"
	clip.Size = UDim2.fromScale(0, 1)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Visible = false
	clip.Parent = pillBox

	local fill = Instance.new("ImageLabel")
	fill.Name = "Hold"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundTransparency = 1
	fill.Image = "rbxassetid://" .. tostring(UIAssets.Pill.Green.Hover)
	fill.ScaleType = Enum.ScaleType.Stretch
	fill.Parent = clip

	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	--- Off centre by a hair: the artist's pill is drawn with its face sitting slightly high in the
	--- art's own box, and centring the caption on the BOX leaves it visibly low on the FACE.
	text.Position = UDim2.fromScale(0.5, 0.46)
	text.Size = UDim2.fromScale(0.74, 0.44)
	text.BackgroundTransparency = 1
	text.FontFace = FONT
	text.TextColor3 = cfg.Colors.PillText
	text.TextScaled = true
	text.Text = CarDealConfig.oneLine(CarDealConfig.Lines.Buy)
	text.ZIndex = 3
	text.Parent = pillBox

	--[[ THE TAP TARGET `Style = Custom` TOOK AWAY (header note 3). Over the pill only, so the rest of
		the sign stays inert — a bubble that ate presses would be a bubble a player could not look
		past. `Selectable = false` keeps it out of the gamepad rail's selection: the pad already has
		this button as `GamepadKeyCode`, and a selectable world button would eat ButtonA from the menu
		navigation `GamepadConfig` owns. ]]
	local button = Instance.new("TextButton")
	button.Name = "Tap"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Selectable = false
	button.ZIndex = 4
	button.Parent = pillBox

	local key = Instance.new("Frame")
	key.Name = "Key"
	key.AnchorPoint = Vector2.new(0, 0.5)
	key.Position = UDim2.fromScale(inset + pillWidth + gap, 0.5)
	key.Size = UDim2.fromScale(keyWidth, 0.82)
	key.BackgroundColor3 = Color3.fromRGB(20, 27, 45)
	key.BackgroundTransparency = 0.12
	key.BorderSizePixel = 0
	key.Visible = false
	key.Parent = holder

	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(0.22, 0)
	keyCorner.Parent = key

	local keyStroke = Instance.new("UIStroke")
	keyStroke.Color = Color3.fromRGB(206, 214, 232)
	keyStroke.Thickness = 1.5
	keyStroke.Transparency = 0.35
	keyStroke.Parent = key

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "Glyph"
	keyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	keyLabel.Position = UDim2.fromScale(0.5, 0.5)
	keyLabel.Size = UDim2.fromScale(0.74, 0.62)
	keyLabel.BackgroundTransparency = 1
	keyLabel.FontFace = FONT
	keyLabel.TextColor3 = Color3.new(1, 1, 1)
	keyLabel.TextScaled = true
	keyLabel.Text = ""
	keyLabel.Parent = key

	local keyImage = Instance.new("ImageLabel")
	keyImage.Name = "Button"
	keyImage.AnchorPoint = Vector2.new(0.5, 0.5)
	keyImage.Position = UDim2.fromScale(0.5, 0.5)
	keyImage.Size = UDim2.fromScale(0.84, 0.84)
	keyImage.BackgroundTransparency = 1
	keyImage.Visible = false
	keyImage.Parent = key

	return {
		holder = holder,
		box = pillBox,
		fill = fill,
		clip = clip,
		label = text,
		key = key,
		keyLabel = keyLabel,
		keyImage = keyImage,
		button = button,
		pillWidth = pillWidth,
		keyWidth = keyWidth,
		gap = gap,
		rowY = row.Y,
		rowHeight = row.Height,
	} :: Pill
end

--[[ Centre the row on whatever is actually in it.

	The key box is not there on a touchscreen (the pill IS the button), and a pill left where a
	pill-plus-key was centred sits visibly off to the left. Two lines of arithmetic rather than a
	list layout, for `_buildPill`'s reason: a billboard's aspect is known, so the widths are known. ]]
local function layoutPill(pill: Pill, withKey: boolean)
	local total = pill.pillWidth + (if withKey then pill.gap + pill.keyWidth else 0)
	local left = (1 - total) / 2
	pill.box.Position = UDim2.fromScale(left, 0.5)
	pill.key.Position = UDim2.fromScale(left + pill.pillWidth + pill.gap, 0.5)
	pill.key.Visible = withKey
end

--[[ How far through the hold the pill is drawn, 0 to 1.

	The clip grows and the image inside it is widened by the reciprocal, so the art's rendered width
	is constant and what travels is the edge rather than the drawing. Guarded off below a pixel's
	worth of progress, where the reciprocal would be enormous and the wipe invisible anyway. ]]
local function setHold(pill: Pill, progress: number)
	local p = math.clamp(progress, 0, 1)
	if p <= 0.004 then
		pill.clip.Visible = false
		return
	end
	pill.clip.Visible = true
	pill.clip.Size = UDim2.fromScale(p, 1)
	pill.fill.Size = UDim2.fromScale(1 / p, 1)
end

-- === What the sign says =====================================================

--[[ Redraw one bubble from what is currently true.

	READ, NEVER TOLD (header note 4). Four attributes on the stand, one on the player for the
	collection and one for the balance; nothing here is passed in, so this is the single path every
	change in any of those goes down and the sign cannot disagree with any of them.

	The one thing it writes back is `deal.owned`, which is not a cache of anything a caller supplied
	— it is this function's own conclusion, kept so that the pill (which appears on an engine event
	rather than on a redraw) does not have to reach the same one a second way. ]]
function CarDealController._redraw(self, deal: Deal)
	self:_presentStock(deal)
	local attrs = CarDealConfig.Attributes
	local lines = CarDealConfig.Lines
	local colours = CarDealConfig.Bubble.Colors

	local body = deal.model:GetAttribute(CarDealConfig.stockAttribute(attrs.Body, WorldConfig.highestUnlocked(Players.LocalPlayer)))
	local price = deal.model:GetAttribute(CarDealConfig.stockAttribute(attrs.Price, WorldConfig.highestUnlocked(Players.LocalPlayer)))
	local paint = deal.model:GetAttribute(CarDealConfig.stockAttribute(attrs.Paint, WorldConfig.highestUnlocked(Players.LocalPlayer)))
	if type(body) ~= "string" or type(price) ~= "number" then
		deal.panel.Visible = false
		return
	end
	deal.panel.Visible = true

	deal.seller.Text = if deal.sellerName and deal.sellerName ~= ""
		then CarDealConfig.oneLine(string.format(lines.SellerNamed, deal.sellerName))
		else CarDealConfig.oneLine(lines.SellerAnonymous)

	--- The car's name in its RARITY colour, which is the same language the Index and the Cars
	--- Inventory print a rarity in. One less row than spelling the word out, and the colour is the
	--- part a player reads at a glance anyway — the word itself is on both of those screens already.
	local _, colour = CarRarity.labelOf(body)
	deal.body.Text = CarDealConfig.oneLine(GarageConfig.displayName(body))
	deal.body.TextColor3 = colour

	local key = GarageConfig.carKey(body, if type(paint) == "number" then paint else nil)
	deal.owned = CarDealConfig.Offer.RefuseOwned and self._owned[key] == true
	local affordable = self._cash >= price
	if deal.owned then
		--- Owned: the price is not the useful thing to say any more, so it is replaced rather than
		--- struck through. `Owned` on top, the explanation under it.
		deal.priceCaption.Text = CarDealConfig.oneLine(lines.OwnedCaption)
		deal.priceCaption.TextColor3 = colours.Owned
		deal.price.Text = CarDealConfig.oneLine(lines.Owned)
		deal.price.TextColor3 = colours.Owned
	else
		deal.priceCaption.Text = CarDealConfig.oneLine(lines.PriceCaption)
		deal.priceCaption.TextColor3 = deal.captionInk or colours.Caption
		deal.price.Text = GarageConfig.formatCash(price)
		--- On the kit sign the money ramp IS the affordable green, so the text under it stays white.
		deal.price.TextColor3 = if not affordable then colours.PriceShort
			elseif deal.priceTint then Color3.new(1, 1, 1)
			else colours.Price
	end
	if deal.priceTint then
		deal.priceTint.Enabled = affordable and not deal.owned
	end

	--- The pill may be up right now on a stand that has just rotated into a car the player owns.
	if deal.owned and deal.pill.holder.Visible then
		deal.pill.holder.Visible = false
	end
end

--- Redraw every live bubble. The two player attributes this reads change for reasons that have
--- nothing to do with any one stand, so they redraw all of them.
function CarDealController._redrawAll(self)
	for _, deal in self._deals do
		self:_redraw(deal)
	end
end

-- === The prompt =============================================================

--[[ Show the pill for one stand, and paint the glyph for whatever the player is actually holding.

	`inputType` COMES FROM THE ENGINE, not from `UserInputService.TouchEnabled` — which is the whole
	point of taking it off `PromptShown`. A device with both a touchscreen and a keyboard answers TRUE
	to both of those, and the prompt already knows which one was last used. It is also why the key box
	is simply absent on touch: the pill itself is the button there, and a key glyph beside it would be
	telling a phone about a keyboard.

	A CAR THE PLAYER ALREADY OWNS GETS NO PILL. The server refuses that purchase
	(`Offer.RefuseOwned`), and offering a button that cannot work is worse than offering none — the
	bubble is already saying ALREADY YOURS in the space the pill would be under. ]]
function CarDealController._showPill(self, deal: Deal, inputType: Enum.ProximityPromptInputType)
	local pill = deal.pill
	setHold(pill, 0)

	if deal.owned or not deal.panel.Visible then
		pill.holder.Visible = false
		return
	end

	local prompt = deal.prompt
	if inputType == Enum.ProximityPromptInputType.Touch then
		layoutPill(pill, false)
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		local image = prompt and UserInputService:GetImageForKeyCode(prompt.GamepadKeyCode)
		pill.keyLabel.Visible = false
		pill.keyImage.Visible = image ~= nil
		if image then
			pill.keyImage.Image = image
		end
		layoutPill(pill, image ~= nil)
	else
		local text = prompt and UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
		pill.keyImage.Visible = false
		pill.keyLabel.Visible = true
		--- `GetStringForKeyCode` answers for the player's own layout, so an AZERTY keyboard is drawn
		--- the letter it will actually press. The fall-back is only for a KeyCode it has no name for.
		pill.keyLabel.Text = if text and text ~= "" then text else "E"
		layoutPill(pill, true)
	end

	pill.holder.Visible = true
end

function CarDealController._hidePill(self, deal: Deal)
	self:_endHold(deal)
	deal.pill.holder.Visible = false
end

--- Tear down a hold in progress. One place, because a hold ends three ways — released, triggered,
--- and the prompt going away underneath it — and a half-cleaned one leaks a connection per press.
function CarDealController._endHold(self, deal: Deal)
	if deal.holdTween then
		deal.holdTween:Cancel()
		deal.holdTween = nil
	end
	if deal.holdConnection then
		deal.holdConnection:Disconnect()
		deal.holdConnection = nil
	end
	if deal.holdValue then
		deal.holdValue:Destroy()
		deal.holdValue = nil
	end
	setHold(deal.pill, 0)
end

--[[ The touch tap target, and the fill that runs while the button is held.

	`InputHoldBegin` / `InputHoldEnd` are what a custom prompt has instead of a tap: the engine runs
	the hold timer and fires `Triggered` at the end of it exactly as it would for a key, so touch and
	keyboard reach the server down the identical path and there is no second purchase route to
	secure. Straight out of Roblox's own reference implementation of a custom prompt.

	THE FILL IS A TWEEN ON A `NumberValue`, not a per-frame step, so it runs on the engine's own clock
	and cannot drift from the hold the prompt is timing. It is not a tween on the clip's `Size`
	because `setHold` writes the reciprocal onto the image inside that clip on the same frame, and two
	writers of one property is a fight nobody wins. ]]
function CarDealController._bindPill(self, deal: Deal, prompt: ProximityPrompt)
	local pill = deal.pill
	local down = false

	deal.trove:Add(pill.button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputState == Enum.UserInputState.Change then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			down = true
			prompt:InputHoldBegin()
		end
	end))

	deal.trove:Add(pill.button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if down then
				down = false
				prompt:InputHoldEnd()
			end
		end
	end))

	deal.trove:Add(prompt.PromptButtonHoldBegan:Connect(function()
		self:_endHold(deal)

		local progress = Instance.new("NumberValue")
		progress.Value = 0
		deal.holdValue = progress
		deal.holdConnection = progress.Changed:Connect(function(value: number)
			setHold(deal.pill, value)
		end)
		deal.holdTween = TweenService:Create(
			progress,
			TweenInfo.new(math.max(prompt.HoldDuration, 0.01), Enum.EasingStyle.Linear),
			{ Value = 1 }
		)
		deal.holdTween:Play()
	end))

	deal.trove:Add(prompt.PromptButtonHoldEnded:Connect(function()
		self:_endHold(deal)
	end))

	--- The purchase itself is the server's; all this does locally is stop the fill so a pill that has
	--- just been spent is not left sitting at full while the sign turns over.
	deal.trove:Add(prompt.Triggered:Connect(function()
		down = false
	end))

	deal.trove:Add(function()
		self:_endHold(deal)
	end)
end

-- === A stand arriving and leaving ===========================================

function CarDealController._bind(self, model: Model)
	if self._deals[model] or not model:IsA("Model") then
		return
	end

	local index = model:GetAttribute(CarDealConfig.Attributes.Index)
	local anchor = model:FindFirstChild(CarDealConfig.Names.BubbleAnchor, true)
	if not (type(index) == "number" and anchor and anchor:IsA("Attachment")) then
		--[[ A stand whose subtree has not arrived. It should not be reachable — every stand is
			`ModelStreamingMode.Atomic` (header note 2) — and it is checked because the failure it
			guards against is silent: a bubble bound to nothing, on a plinth that looks finished. ]]
		self.log:warn(string.format("Car deal stand %s arrived without its anchor — not dressed.", model.Name))
		return
	end

	local deal: Deal = {
		index = index,
		model = model,
		anchor = anchor,
		base = if anchor.Parent and anchor.Parent:IsA("BasePart") then anchor.Parent else nil,
		prompt = nil,
		gui = nil :: any,
		panel = nil :: any,
		seller = nil :: any,
		body = nil :: any,
		priceCaption = nil :: any,
		price = nil :: any,
		pill = nil :: any,
		clock = nil,
		rig = nil,
		anim = nil,
		faceTemplate = nil,
		sellerName = nil,
		owned = false,
		holdTween = nil,
		holdValue = nil,
		holdConnection = nil,
		trove = Trove.new(),
	} :: any

	self._deals[model] = deal
	self:_buildBubble(deal, anchor)

	local prompt = model:FindFirstChild(CarDealConfig.Names.Prompt, true)
	if prompt and prompt:IsA("ProximityPrompt") then
		deal.prompt = prompt
		self._byPrompt[prompt] = deal
		self:_bindPill(deal, prompt)
		deal.trove:Add(function()
			self._byPrompt[prompt] = nil
		end)
	end

	--[[ One handler for all four offer attributes rather than four signals. They are written in a
		burst when an offer rotates, so a per-attribute subscription would redraw the same sign four
		times for one change; `_redraw` is idempotent and reads all of them, so the last write wins
		either way and this costs three redraws less.

		IT RE-SEATS THE SELLER TOO, because the two things a rotation does are move the bay and swap
		the car in it, and this is the half of that a client hears about reliably. The property watch
		below is the other half; both are idempotent and either may arrive first. ]]
	deal.trove:Add(model.AttributeChanged:Connect(function()
		self:_redraw(deal)
		self:_seatRig(deal)
	end))

	--[[ THE BAY MOVED. Every rotation pivots the whole stand to a new spot on the island, and the
		one thing that does not travel with it is the seller, who belongs to this client and lives in
		this controller's own folder (`_seatRig`).

		WATCHED ON THE FLOOR PART AND NOT POLLED, because the alternative is three rigs re-pivoted or
		three distances measured on every frame of the session to catch a move that happens once
		every five minutes. `Base` is anchored and moved by the server, so its `CFrame` replicates as
		a property change and the signal fires with it. ]]
	if deal.base then
		deal.trove:Add(deal.base:GetPropertyChangedSignal("CFrame"):Connect(function()
			self:_seatRig(deal)
			self:_presentStock(deal)
		end))
	end

	--- Dressed first, so the very first draw of the sign already carries a seller's name if one is
	--- available. `_dress` redraws on its own too, which is what covers the friend rigs landing later.
	self:_dress(deal)
	self:_redraw(deal)
end

function CarDealController._unbind(self, model: Instance)
	local deal = self._deals[model]
	if not deal then
		return
	end
	self._deals[model] = nil
	self:_undress(deal)
	if deal.stockCar then deal.stockCar:Destroy(); deal.stockCar = nil end
	deal.trove:Destroy()
end

-- === The countdown ==========================================================

--[[ One frame of every clock in the plaza.

	THE DEADLINE IS READ EVERY FRAME rather than cached and subtracted from, so a rotation landing, a
	server restarting the clock and a player joining halfway through a cycle all arrive at the right
	number with no handler anywhere. `GetServerTimeNow` is the same clock the server set that deadline
	on, which is the only thing that makes the subtraction mean anything.

	ONE ATTRIBUTE READ AND ONE PLAYER POSITION for all three stands, because both are the same
	question however many signs are standing in the plaza. ]]
function CarDealController._stepClocks(self)
	local deadline = workspace:GetAttribute(CarDealConfig.NextRotationAttribute)
	--- Held at zero rather than hidden for the half second between the deadline passing and the new
	--- offers landing: a clock that vanished there would read as the market closing.
	local remaining = if type(deadline) == "number"
		then math.max(0, deadline - workspace:GetServerTimeNow())
		else nil

	--[[ THE CHARACTER'S POSITION, NOT THE CAMERA'S, so "near enough for a deadline" is the same kind
		of measurement as the prompt's "near enough to buy". A player who swings the camera across the
		plaza from their own plot has not walked anywhere, and three clocks should not light up for
		it. Nil until the character spawns, which simply means no strip is drawn yet. ]]
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local origin = if root and root:IsA("BasePart") then root.Position else nil

	for _, deal in self._deals do
		self:_stepClock(deal, remaining, origin)
	end
end

--- One strip: whether it should be up at all, and what it says if it is.
function CarDealController._stepClock(self, deal: Deal, remaining: number?, origin: Vector3?)
	local clock = deal.clock
	if not clock then
		return
	end
	local cfg = CarDealConfig.Bubble.Clock

	--- Three things have to be true to draw one: the server has posted a deadline, this plinth has an
	--- offer standing on it, and the player is close enough to read the number.
	local visible = remaining ~= nil and origin ~= nil and deal.panel.Visible
	if visible then
		--- The range is wider once the strip is up, so a player idling exactly on the line does not
		--- get a clock that flickers in time with their breathing.
		local range = cfg.NearDistance + (if clock.shown then cfg.Hysteresis else 0)
		visible = (deal.anchor.WorldPosition - (origin :: Vector3)).Magnitude <= range
	end

	if visible ~= clock.shown then
		clock.shown = visible
		self:_fadeClock(clock, visible)
	end
	if not (visible and remaining) then
		return
	end

	--- Rewritten on the second and not on the frame: the line is a string build and a rich-text
	--- parse, and fifty-nine of every sixty would produce the text that is already there.
	local whole = math.ceil(remaining)
	if whole == clock.lastWhole then
		return
	end
	clock.lastWhole = whole
	clock.text.Text = CarDealConfig.clockLine(remaining)

	--- One beat per second over the last few: 8% and back, on the tick, which is the restrained
	--- version of a countdown going loud. Nothing is at stake here — it is a shop clock.
	if remaining > 0 and remaining <= cfg.UrgentSeconds then
		clock.scale.Scale = cfg.PulseScale
		TweenService:Create(
			clock.scale,
			TweenInfo.new(cfg.PulseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end
end

--- Fade one strip in or out. `Visible` goes on before the fade in and off after the fade out, so a
--- sign nobody is standing near costs nothing to draw rather than being drawn at full transparency.
function CarDealController._fadeClock(self, clock: Clock, visible: boolean)
	local cfg = CarDealConfig.Bubble.Clock
	local info = TweenInfo.new(cfg.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	if visible then
		clock.strip.Visible = true
	end
	TweenService:Create(clock.strip, info, {
		BackgroundTransparency = if visible then cfg.PanelTransparency else 1,
	}):Play()
	local textTween = TweenService:Create(clock.text, info, { TextTransparency = if visible then 0 else 1 })
	textTween:Play()

	if not visible then
		textTween.Completed:Once(function()
			--- ...unless the player walked back inside the quarter second the fade takes.
			if not clock.shown then
				clock.strip.Visible = false
			end
		end)
	end
end

-- === Lifecycle ==============================================================

CarDealController:withRemoteEvents({
	{
		--[[ The purchase landed. The bubble redraws itself off the collection attribute a moment
			later anyway (header note 4), so all this adds is the beat that says WHICH stand it was —
			the pill flashes to its pressed face and the sign turns over to ALREADY YOURS. ]]
		DealBought = function(standIndex: number)
			CarDealController:_onBought(standIndex)
		end,
	},
})

--- The one beat a purchase gets out in the world: the pill it was pressed on flashes and drops away.
function CarDealController._onBought(self, standIndex: unknown)
	for _, deal in self._deals do
		if deal.index == standIndex then
			setHold(deal.pill, 1)
			task.delay(CarDealConfig.Bubble.SwapSeconds, function()
				if self._deals[deal.model] == deal then
					setHold(deal.pill, 0)
					self:_redraw(deal)
				end
			end)
			return
		end
	end
end

CarDealController:withLifecycle({
	init = function(self)
		self._deals = {} :: { [Instance]: Deal }
		self._byPrompt = {} :: { [ProximityPrompt]: Deal }
		self._faces = {} :: { Face }
		self._fallback = {} :: { Face }
		self._friendsPending = false
		--- Every car key the local player owns, off `GarageConfig.OwnedAttribute`. A set rather than
		--- the list, because the only question asked of it is "is this one in it?" once per redraw.
		self._owned = {} :: { [string]: boolean }
		self._cash = 0
		self._sellers = nil :: Folder?
		self._gui = nil :: Instance?
		self._rng = Random.new()
		self._trove = Trove.new()
	end,

	start = function(self)
		if not CarDealConfig.Enabled then
			return
		end

		task.spawn(function()
			local player = Players.LocalPlayer
			local playerGui = player:WaitForChild("PlayerGui")
			self._gui = playerGui
   task.spawn(function()
    local templates = ReplicatedStorage:WaitForChild("CarDealDisplayTemplates", 30)
    if templates then self._trove:Add(templates.ChildAdded:Connect(function() self:_redrawAll() end)); self:_redrawAll() end
   end)

			--- Client-side only, so it replicates nowhere and no server query can see a seller.
			local sellers = Instance.new("Folder")
			sellers.Name = SELLER_FOLDER
			sellers.Parent = workspace
			self._sellers = sellers
			self._trove:Add(sellers)

			--[[ Seeded from the current values before subscribing, and not rolled to them: both
				attributes are written the moment the profile loads, which is usually before this
				controller finishes waiting on PlayerGui, so without the seed the first bubble a
				player sees would price against a balance of zero. ]]
			local function readOwned()
				local set = {}
				-- A set of MODELS, not IDs: the bubble asks "do you already have a red Camaro", the same
				-- question `GarageService.ownsModel` answers when the press arrives. See
				-- `GarageConfig.modelKeyOf` for why an owned ID alone would not match the stand's key.
				for _, id in GarageConfig.split(player:GetAttribute(GarageConfig.OwnedAttribute)) do
					local model = GarageConfig.modelKeyOf(id)
					if model then
						set[model] = true
					end
				end
				self._owned = set
				self:_redrawAll()
			end
			local function readCash()
				local cash = player:GetAttribute(GarageConfig.CashAttribute)
				self._cash = if type(cash) == "number" then cash else 0
				self:_redrawAll()
			end
			readOwned()
			readCash()
			self._trove:Add(player:GetAttributeChangedSignal(GarageConfig.OwnedAttribute):Connect(readOwned))
			self._trove:Add(player:GetAttributeChangedSignal(GarageConfig.CashAttribute):Connect(readCash))
			self._trove:Add(player:GetAttributeChangedSignal(WorldConfig.UnlockAttribute):Connect(function() self:_redrawAll() end))

			--- Both pools are web calls and both yield. The fallbacks are quick and cover the stands
			--- that stream in first; the friends arrive later and `_dressAll` swaps them in.
			self:_buildFallbackFaces()
			self:_buildFriendFaces()
			RigAnimator.preload(CarDealConfig.Dealer.Animations.Clips)

			for _, model in CollectionService:GetTagged(CarDealConfig.Tag) do
				self:_bind(model :: Model)
			end
			self._trove:Add(CollectionService:GetInstanceAddedSignal(CarDealConfig.Tag):Connect(function(model)
				self:_bind(model :: Model)
			end))
			self._trove:Add(CollectionService:GetInstanceRemovedSignal(CarDealConfig.Tag):Connect(function(model)
				self:_unbind(model)
			end))

			--[[ The pill is shown and hidden by the ENGINE's own range test rather than by a distance
				check of ours, which is the other half of what `Style = Custom` buys: one definition of
				"close enough", shared by the button that is drawn and the press that is accepted. ]]
			self._trove:Add(ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
				local deal = self._byPrompt[prompt]
				if deal then
					self:_showPill(deal, inputType)
				end
			end))
			self._trove:Add(ProximityPromptService.PromptHidden:Connect(function(prompt)
				local deal = self._byPrompt[prompt]
				if deal then
					self:_hidePill(deal)
				end
			end))

			--[[ ONE CONNECTION FOR EVERY STRIP. The countdown is one number and the player is in one
				place, so a per-stand binding would ask the same two questions three times a frame.
				`RenderStepped` and not `Heartbeat` because what it drives is drawn — a clock stepped
				after the frame it belongs to is a clock a sixtieth of a second stale in every shot. ]]
			if CarDealConfig.Bubble.Clock.Enabled then
				self._trove:Add(RunService.RenderStepped:Connect(function()
					self:_stepClocks()
				end))
			end
		end)
	end,
})

CarDealController:withCleanup(function()
	for model in CarDealController._deals or {} do
		CarDealController:_unbind(model)
	end
	if CarDealController._trove then
		CarDealController._trove:Destroy()
	end
end)

-- Unlocked-world dealer stock, 2026-10-04.
function CarDealController._presentStock(self, deal: Deal)
 local attrs = CarDealConfig.Attributes
 local highest = WorldConfig.highestUnlocked(Players.LocalPlayer)
 local body = deal.model:GetAttribute(CarDealConfig.stockAttribute(attrs.Body, highest))
 local paint = deal.model:GetAttribute(CarDealConfig.stockAttribute(attrs.Paint, highest))
 local base = deal.base
 if not base then return end
 local key = tostring(body) .. ":" .. tostring(paint) .. ":" .. tostring(base.CFrame)
 if deal.stockKey == key then return end
 if type(body) ~= "string" or type(paint) ~= "number" then
  if deal.stockCar then deal.stockCar:Destroy(); deal.stockCar = nil end
  deal.stockKey = key
  return
 end
 local templates = ReplicatedStorage:FindFirstChild("CarDealDisplayTemplates")
 local template = templates and templates:FindFirstChild(tostring(deal.index) .. "_" .. tostring(highest))
 if not (template and template:IsA("Model") and template:GetAttribute("StockBody") == body and template:GetAttribute("StockPaint") == paint) then return end
 if deal.stockCar then deal.stockCar:Destroy() end
 local clone = template:Clone()
 clone.Name = "PersonalDealCar"
 local originalFrame = template:GetAttribute("StandFrame")
 local frame = base.CFrame * CFrame.new(0, -CarDealConfig.Bay.Slab / 2, 0)
 clone:PivotTo(frame * originalFrame:ToObjectSpace(clone:GetPivot()))
 clone.Parent = deal.model
 deal.stockCar, deal.stockKey = clone, key
end

return CarDealController
