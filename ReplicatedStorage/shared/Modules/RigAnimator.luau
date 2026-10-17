--[[
	RigAnimator  (shared, client-side in practice)
	---------------------------------------------
	Play a named set of clips on a rig. One instance per rig, built when the rig is, thrown away
	with it.

	WHY A MODULE AND NOT SIX LINES IN THE CALLER. Two rigs need this and they are nothing like each
	other — the steal's flight avatar is a clone of the live character with its Humanoid switched
	off, and the driver you throw out is a rig built from a `HumanoidDescription` with no Humanoid
	logic at all — but the four things they both need are the same four things, and three of them
	are only obvious after they have gone wrong once:

	  • THE ASSET'S `Loop` FLAG IS NOT THE TRACK'S. A freshly loaded `AnimationTrack` inherits
	    whatever the upload was saved with, and the animation editor saves `Loop = true` by default.
	    All four of this game's clips carry it, which is why looping is written per clip in
	    `StealConfig.Animations.Clips` and stamped onto every track here — otherwise the bail clip
	    climbs out of the car over and over for the whole flight, and it looks like a state-machine
	    bug rather than an upload setting.
	  • THE FIRST PLAY IS A WEB FETCH. `LoadAnimation` does not block, so a track played on an asset
	    the client has never seen simply does nothing for a beat and then starts — which on a 0.8s
	    clip means the first bail of a session plays no animation at all. `preload` fixes that
	    once, at start-up, off the critical path.
	  • `Animation` INSTANCES ARE SHARED. One per id for the session, cached here, because loading
	    the same clip onto two rigs from two Instances fetches it twice. They are never parented and
	    never destroyed.
	  • SPEED IS THE ONE ENGINE-SIDE LEVER THAT OBEYS SLOW MOTION (Modules/TimeScale's header, and
	    the plan's own table). `setSpeed` is how a track joins the scaled clock everything else in a
	    flight already runs on.

	A rig with no Animator gets nil back rather than a broken object, and every caller here treats
	"no animator" and "animations switched off" identically — which is what makes
	`StealConfig.Animations.Enabled = false` a clean A/B instead of a code path.
]]

local ContentProvider = game:GetService("ContentProvider")

export type Clip = { Id: number, Length: number, Looped: boolean }

local RigAnimator = {}
RigAnimator.__index = RigAnimator

-- One `Animation` per asset id for the session; see the header.
local animations: { [number]: Animation } = {}

function RigAnimator.animation(id: number): Animation
	local existing = animations[id]
	if existing then
		return existing
	end
	local anim = Instance.new("Animation")
	anim.Name = tostring(id)
	anim.AnimationId = "rbxassetid://" .. tostring(id)
	animations[id] = anim
	return anim
end

--[[ Warm the cache. Non-blocking for the caller (it spawns), because nothing should wait on the
	network to finish starting up, and a clip that arrives late only costs the animation on a bail
	taken in the first second of a session. ]]
function RigAnimator.preload(clips: { [string]: Clip })
	local list = {}
	for _, clip in clips do
		table.insert(list, RigAnimator.animation(clip.Id))
	end
	if #list == 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

--[[ Load every clip onto `rig`'s Animator. Returns nil when the rig has no Animator, which the
	callers treat as "no animations" rather than as a failure. ]]
function RigAnimator.new(rig: Model, clips: { [string]: Clip })
	local humanoid = rig and rig:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end

	local self = setmetatable({
		_animator = animator,
		_clips = clips,
		_tracks = {} :: { [string]: AnimationTrack },
		_speed = 1,
	}, RigAnimator)

	for name, clip in clips do
		local ok, track = pcall(function()
			return animator:LoadAnimation(RigAnimator.animation(clip.Id))
		end)
		if ok and track then
			track.Looped = clip.Looped
			track.Priority = Enum.AnimationPriority.Action
			self._tracks[name] = track
		end
	end
	return self
end

--[[ How long a clip runs, in seconds.

	`AnimationTrack.Length` IS 0 UNTIL THE ASSET ARRIVES, so the authored value is the answer
	whenever the track can't give one. That is not just a start-up nicety: `Mount.Time` is sized off
	this, and a beat that reads 0 would cut the landing to a single frame — the failure would look
	like the handoff firing instantly rather than like a clip that hadn't downloaded. ]]
function RigAnimator.length(self, name: string): number
	local track = self._tracks[name]
	if track and track.Length > 0 then
		return track.Length
	end
	local clip = self._clips[name]
	return if clip then clip.Length else 0
end

function RigAnimator.isPlaying(self, name: string): boolean
	local track = self._tracks[name]
	return track ~= nil and track.IsPlaying
end

-- Start a clip, crossfading out of whatever else this rig is doing. Re-playing something already
-- playing is a no-op rather than a restart, so a caller can be dumb about it (`_playLand` is).
function RigAnimator.play(self, name: string, fade: number?): boolean
	local track = self._tracks[name]
	if not track then
		return false
	end
	if track.IsPlaying then
		return true
	end
	local blend = fade or 0
	for other, playing in self._tracks do
		if other ~= name and playing.IsPlaying then
			playing:Stop(blend)
		end
	end
	track:Play(blend)
	track:AdjustSpeed(self._speed)
	return true
end

-- The slow-motion hook (Modules/TimeScale). Written to every track, playing or not, so a clip
-- started mid-dip starts at the dipped speed.
function RigAnimator.setSpeed(self, scale: number)
	if math.abs(scale - self._speed) < 1e-3 then
		return
	end
	self._speed = scale
	for _, track in self._tracks do
		track:AdjustSpeed(scale)
	end
end

--[[ Stop everything.

	`fade = 0` is what a ragdoll wants and is the default for exactly that reason: a track still
	blending out is still writing Motor6D transforms, and on a rig whose Motor6Ds have just been
	replaced by ball sockets that is at best wasted work and at worst a limb being dragged back
	toward a pose it no longer has joints for. ]]
function RigAnimator.stop(self, fade: number?)
	for _, track in self._tracks do
		if track.IsPlaying then
			track:Stop(fade or 0)
		end
	end
end

return RigAnimator
