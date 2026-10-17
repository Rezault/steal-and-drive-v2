--[[
	CashBurstController  (client)
	-----------------------------
	Money coming out of a collect mat and into you. One remote in (`CashBurst`, fired by
	`GarageService._collect` after the cash is already banked), a fan of banknote billboards out.

	Every knob is in `CollectEffectConfig`, including the account of what the four beats are and why
	the SIZE of a payout is carried by the note COUNT and by nothing else. This file is the mechanism.

	=== IT IS DOWNSTREAM OF THE MONEY, NEVER ON ITS PATH =======================================

	The payout is written to the profile, mirrored onto the Player attribute and signalled to
	`QuestService` before the remote that gets here is even fired. So there is nothing this file can
	do to a player's cash: a burst that is culled by distance, trimmed by the live cap, or dropped
	because the character is not spawned yet costs nobody a dollar, and none of those cases needs an
	apology in the log. The HUD counter is watching the attribute and rolls either way.

	=== WHY ONE LOOP AND NOT A TWEEN PER NOTE ==================================================

	A `TweenService` tween cannot chase a moving target, and the whole point of the second half of
	the flight is that it is re-aimed at the player EVERY FRAME — walk away mid-collection and the
	money follows you rather than landing where you were standing. So the notes are stepped by hand
	on one `RenderStepped`, which also means one connection for a whole `collectAll` sweep instead of
	eighty-four tweens, and which is what makes the ballistic arc in the first half possible at all.

	The loop only exists while notes do. `_start` connects on the first note of a quiet moment and
	`_stop` disconnects on the last one, so a player who never collects pays nothing per frame.

	=== TWO INSTANCE-LEVEL TRAPS THIS FILE IS SHAPED AROUND ====================================

	  1. A `Trail` DRAWS THE TELEPORT. Parent a part with a live trail into Workspace and it streaks
	     from wherever the part was last (the origin, for a fresh part) to where you put it. So a
	     note is positioned BEFORE it is parented and its trail is left disabled until the frame the
	     note actually starts moving.

	  2. DESTROYING THE PART TAKES THE RIBBON WITH IT. On arrival the icon is hidden and the part is
	     left standing where it landed for exactly the trail's lifetime, so the tail finishes into
	     the player instead of being cut off. `_retire` is that, and it is why a note stops being
	     stepped a fraction of a second before it stops existing.

	Everything the notes are made of is `CanQuery`/`CanTouch`/`CanCollide` false and `Anchored`, so
	none of it can be hit by a raycast, retrigger the mat's own `Touched`, or be pushed by a car.

	HOUSE RULE: no wiki-style double-bracket links in these comments — the closing pair ends the
	block comment early and the parse error points at the wrong line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local CollectEffectConfig = require(ReplicatedStorage.shared.Configs.CollectEffectConfig)
local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)

local CashBurstController = Shard.new("CashBurstController")

-- One live banknote. `from` is filled in at the top of the arc rather than up front: the flight
-- starts from wherever the ballistic half actually left the note, which is not a point either half
-- knows in advance.
type Note = {
	part: BasePart,
	image: ImageLabel,
	scale: UIScale,
	trail: Trail?,
	delay: number, -- seconds after the burst that this note leaves
	t: number, -- seconds since the burst
	live: boolean, -- has it been revealed and its trail switched on
	origin: Vector3,
	velocity: Vector3,
	popTime: number,
	flyTime: number,
	from: Vector3?,
	rotation: number,
	spin: number,
}

-- A value somewhere in the range, and a jittered copy of a base value. Both take `math.random`
-- rather than a seeded stream on purpose: nothing here is replicated or replayed, so two clients
-- watching the same collection are allowed to see two different sprays.
local function pick(range: NumberRange): number
	return range.Min + math.random() * (range.Max - range.Min)
end

local function jitter(base: number, amount: number): number
	return base * (1 + (math.random() - 0.5) * 2 * amount)
end

-- === Building ================================================================

--[[ The note every burst clones. Built once at start and never parented — a clone source, so the
	per-note cost of a collection is a `Clone` rather than eleven `Instance.new`s inside one frame,
	which for a six-bay sweep is the difference between a hitch and nothing.

	The banknote is a BillboardGui sized in SCALE, which on a billboard is studs — so its size is a
	world size and does not change with the viewport. Its height is derived from the artwork's own
	aspect rather than written down, so a re-upload at a different resolution cannot squash it. ]]
function CashBurstController._buildTemplate(self): BasePart
	local icon = CollectEffectConfig.Icon
	local art = UIAssets.Size.CashIcon

	local part = Instance.new("Part")
	part.Name = "CashNote"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1 -- the part is a carrier; the banknote is the billboard on it
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true

	local gui = Instance.new("BillboardGui")
	gui.Name = "Note"
	gui.Size = UDim2.fromScale(icon.Width, icon.Width * art.Y / art.X)
	gui.AlwaysOnTop = icon.AlwaysOnTop
	gui.LightInfluence = 0
	gui.MaxDistance = icon.FadeDistance
	gui.Parent = part

	--[[ Anchored at its own centre so the arrival shrink pulls the note into a point rather than
		into its top-left corner. Same convention the rest of this kit's UI is built on. ]]
	local image = Instance.new("ImageLabel")
	image.Name = "Icon"
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.Image = UIAssets.url(icon.Image)
	image.ImageTransparency = 1 -- revealed on the frame the note leaves; see `_advance`
	image.Parent = gui

	-- The shrink on arrival. A UIScale rather than the label's Size for the reason every other
	-- punch in this project uses one: it scales the rendered result and re-flows nothing.
	local scale = Instance.new("UIScale")
	scale.Parent = image

	if CollectEffectConfig.Trail.Enabled then
		self:_buildTrail(part)
	end

	return part
end

--[[ The streak. Two attachments a ribbon-width apart and a `Trail` between them.

	`FaceCamera` is the load-bearing property. The attachments are separated along the part's local
	Y and the part is never rotated, so a note flying straight up would otherwise present its ribbon
	edge-on and draw nothing at all — which is exactly the half of the arc that most wants a streak.
	With it on, the ribbon is billboarded and the separation is only its width. ]]
function CashBurstController._buildTrail(_self, part: BasePart)
	local cfg = CollectEffectConfig.Trail

	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, cfg.Width / 2, 0)
	top.Parent = part

	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, -cfg.Width / 2, 0)
	bottom.Parent = part

	local trail = Instance.new("Trail")
	trail.Name = "Streak"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.FaceCamera = true
	trail.Lifetime = cfg.Lifetime
	trail.MinLength = 0
	trail.Texture = cfg.Texture
	trail.LightEmission = cfg.LightEmission
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(cfg.Color, cfg.TailColor)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, cfg.Transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- Tapers to a point, so the streak is a wake rather than a rectangle following the note.
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	-- OFF until the note moves — see trap 1 in the header.
	trail.Enabled = false
	trail.Parent = part
end

--[[ The clone source, built on demand.

	`start` builds it eagerly so the first collection of a session is not the frame that pays for it,
	and this exists so `Enabled` can be flipped ON mid-playtest and work — every other taste value in
	this project's effects is read live for the same reason, and a master switch that only takes
	effect on a rejoin is the one knob nobody can dial. ]]
function CashBurstController._templateOf(self): BasePart
	if not self._template then
		self._template = self:_buildTemplate()
	end
	return self._template
end

-- The Workspace folder the notes live in, re-created if something clears Workspace under us (the
-- race teardown does exactly that to other folders). Same shape as every other client-built effect.
function CashBurstController._folderOf(self): Folder
	local folder = self._folder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = CollectEffectConfig.FolderName
	folder.Parent = workspace
	self._folder = folder
	return folder
end

-- === Aiming ==================================================================

--[[ Where the money is going: the centre of the player.

	The HumanoidRootPart IS the middle of the character, so this is the torso plus a small lift to
	the chest. nil means there is nothing to fly into — no character yet on join, or one that died
	mid-flight — and every caller treats that as "do not draw", never as an error. ]]
function CashBurstController._target(_self): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	return root.Position + Vector3.new(0, CollectEffectConfig.Flight.TargetHeight, 0)
end

-- === One collection ==========================================================

--[[ PUBLIC. Throw a payout's worth of notes out of `origin` and into the player.

	`origin` is the top face of the mat that paid, as `GarageService` measured it, and nil is a real
	answer: a podium can be authored without a `CashButton` at all (`_discoverBays` tolerates it), and
	the money still has to be seen. In that case the notes are thrown from just above the player, which
	reads as "it arrived" rather than as "it came from over there".

	Written to take the wire's `unknown`s and validate them here rather than at the remote, because
	the other caller is any future collection that wants the same beat — a quest claim, a race payout
	— and it should not have to know what the remote's shape is. ]]
function CashBurstController.burst(self, amount: unknown, origin: unknown)
	if not CollectEffectConfig.Enabled then
		return
	end

	local cash = tonumber(amount) or 0
	if cash <= 0 then
		return
	end

	local target = self:_target()
	if not target then
		return -- no character to fly into; the counter still rolls
	end

	local pop = CollectEffectConfig.Pop
	local from: Vector3
	if typeof(origin) == "Vector3" then
		from = origin + Vector3.new(0, pop.StartHeight, 0)
		--[[ Off-screen collections are not drawn. The two sweeps that reach this line from across
			the map — the AUTO COLLECT timer during a race, and the welcome-back screen's six bays —
			are the whole reason the cull exists; see `CollectEffectConfig.MaxDistance`. ]]
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - from).Magnitude > CollectEffectConfig.MaxDistance then
			return
		end
	else
		from = target + Vector3.new(0, pop.StartHeight, 0)
	end

	--[[ Trim rather than drop. `collectAll` fires six of these inside one frame and the cap is
		shared across all of them, so the sixth bay throws whatever room the first five left it. ]]
	local room = CollectEffectConfig.Notes.MaxLive - #self._notes
	if room <= 0 then
		return
	end
	local count = math.min(CollectEffectConfig.noteCount(cash), room)

	--[[ The fan is EVEN with a wobble, and it is rotated by a random amount per burst. Even so two
		notes never leave on the same heading; wobbled so it is not a machine; turned so collecting
		two mats in a row does not throw the identical shape twice. ]]
	local turn = math.random() * math.pi * 2
	for i = 1, count do
		local angle = turn + (i - 1) / count * math.pi * 2 + (math.random() - 0.5) * pop.AngleJitter
		self:_spawn(from, angle, (i - 1) * pop.Stagger)
	end

	self:_start()

	if CollectEffectConfig.Sound ~= "" and self._sounds then
		self._sounds:PlayRandom(CollectEffectConfig.Sound)
	end
end

-- One note, parked at the origin and invisible until its turn comes round. Positioned BEFORE it is
-- parented — see trap 1 in the header.
function CashBurstController._spawn(self, origin: Vector3, angle: number, delay: number)
	local pop = CollectEffectConfig.Pop
	local flight = CollectEffectConfig.Flight
	local icon = CollectEffectConfig.Icon

	local part = self:_templateOf():Clone()
	part.CFrame = CFrame.new(origin)

	local gui = part:FindFirstChild("Note") :: BillboardGui
	local image = gui:FindFirstChild("Icon") :: ImageLabel
	local scale = image:FindFirstChildOfClass("UIScale") :: UIScale
	local rotation = pick(icon.StartRotation)
	image.Rotation = rotation

	part.Parent = self:_folderOf()

	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle)) * pick(pop.Spread)
	table.insert(self._notes, {
		part = part,
		image = image,
		scale = scale,
		trail = part:FindFirstChildOfClass("Trail"),
		delay = delay,
		t = 0,
		live = false,
		origin = origin,
		velocity = outward + Vector3.new(0, pick(pop.Rise), 0),
		popTime = jitter(pop.Time, pop.TimeJitter),
		flyTime = jitter(flight.Time, flight.TimeJitter),
		from = nil,
		rotation = rotation,
		--[[ Signed either way so a fan tumbles both directions. The sign is taken off the launch
			heading rather than rolled separately, so the two notes on opposite sides of the fan spin
			opposite ways and the spray reads as one throw. ]]
		spin = pick(icon.Spin) * (if math.cos(angle) < 0 then -1 else 1),
	} :: Note)
end

-- === The loop ================================================================

function CashBurstController._start(self)
	if self._connection then
		return
	end
	self._connection = RunService.RenderStepped:Connect(function(dt: number)
		self:_step(dt)
	end)
end

function CashBurstController._stop(self)
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

--[[ One frame of every live note.

	The target is resolved ONCE per frame rather than per note: it is the same answer for all of
	them, and it is a `FindFirstChild` on the character. Iterated backwards so a note retiring
	mid-loop can be removed without shuffling the ones not yet stepped. ]]
function CashBurstController._step(self, dt: number)
	local target = self:_target()
	local notes = self._notes
	for i = #notes, 1, -1 do
		if not self:_advance(notes[i], dt, target) then
			table.remove(notes, i)
		end
	end
	if #notes == 0 then
		self:_stop()
	end
end

--[[ Advance one note. Returns whether it is still being stepped.

	The two halves are told apart by nothing more than the clock: before `popTime` the note is on a
	thrown arc that owes nothing to where the player is, and after it the note is being pulled in.
	`from` is stamped on the crossing frame, which is what makes the join seamless — the pull starts
	from exactly where the throw ended, at exactly the standstill the ease begins at. ]]
function CashBurstController._advance(self, note: Note, dt: number, target: Vector3?): boolean
	note.t += dt

	local u = note.t - note.delay
	if u < 0 then
		return true -- still queued; it is sitting at the origin with its icon hidden
	end

	if not note.live then
		note.live = true
		note.image.ImageTransparency = 0
		if note.trail then
			note.trail.Enabled = true
		end
	end

	note.image.Rotation = note.rotation + note.spin * u

	local pop = CollectEffectConfig.Pop
	if u < note.popTime then
		-- Thrown, not simulated: `p = origin + v*t - ½gt²`, with the arc's own gravity rather than
		-- the world's. See `CollectEffectConfig.Pop.Gravity`.
		local drop = 0.5 * pop.Gravity * u * u
		note.part.CFrame = CFrame.new(note.origin + note.velocity * u - Vector3.new(0, drop, 0))
		return true
	end

	if not note.from then
		note.from = note.part.Position
	end
	if not target then
		return self:_retire(note) -- the character went away mid-flight
	end

	local flight = CollectEffectConfig.Flight
	local v = (u - note.popTime) / note.flyTime
	if v >= 1 then
		return self:_retire(note)
	end

	note.part.CFrame = CFrame.new((note.from :: Vector3):Lerp(target, v ^ flight.Power))

	-- The arrival: shrink and fade together over the tail of the flight, so the note goes INTO the
	-- player. Untouched before that, which is why this is a branch rather than a curve from zero.
	if v > 1 - flight.Shrink then
		local k = (v - (1 - flight.Shrink)) / flight.Shrink
		note.scale.Scale = 1 + (flight.EndScale - 1) * k
		note.image.ImageTransparency = k
	end
	return true
end

--[[ This note is done. Hide the banknote, stop the trail emitting, and leave the part standing for
	the ribbon's own lifetime before destroying it — see trap 2 in the header. Always returns false,
	so callers can `return self:_retire(note)`. ]]
function CashBurstController._retire(_self, note: Note): boolean
	note.image.ImageTransparency = 1
	local part = note.part
	local trail = note.trail
	if trail then
		trail.Enabled = false
		task.delay(trail.Lifetime, function()
			part:Destroy()
		end)
	else
		part:Destroy()
	end
	return false
end

--[[ Everything down, now, with no arrival.

	Called on the beats where a note in flight would be following the player into something else:
	the start of a race (a mat collected a frame before the teleport would otherwise chase the car
	onto the motorway) and the end of one. Instant rather than faded — both of those beats already
	have something loud happening, which is the same argument the near-miss toast makes for the same
	treatment. ]]
function CashBurstController._clear(self)
	for _, note in self._notes do
		note.part:Destroy()
	end
	table.clear(self._notes)
	self:_stop()
end

CashBurstController:withRemoteEvents({
	{
		--[[ server -> client (amount, origin), from `GarageService._collect` — one per BAY, so a
			`collectAll` sweep arrives as six of these inside a frame. `origin` is the top face of the
			mat that paid, or nil for a podium with no mat part. The money is already banked by the
			time this lands; nothing here is allowed to matter. ]]
		CashBurst = function(amount: unknown, origin: unknown)
			CashBurstController:burst(amount, origin)
		end,

		RaceStart = function()
			CashBurstController:_clear()
		end,
		RaceEnd = function()
			CashBurstController:_clear()
		end,
	},
})

CashBurstController:withLifecycle({
	init = function(self)
		self._notes = {} :: { Note }
		self._connection = nil
		self._folder = nil
		self._template = nil
	end,

	start = function(self)
		if not CollectEffectConfig.Enabled then
			return
		end
		self:_templateOf()
		self._sounds = Shard.get("SoundController")
		if CollectEffectConfig.Sound ~= "" and self._sounds then
			self._sounds:Preload(CollectEffectConfig.Sound)
		end
	end,
})

return CashBurstController
