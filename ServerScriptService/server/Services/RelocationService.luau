--[[
	RelocationService  (server — boot-time relocation of authored content)
	----------------------------------------------------------------------
	Takes content the MODELLER needs to see in Workspace and that NOTHING READS AT RUNTIME, and
	moves it out of Workspace as the server boots. Tag a model `RelocateObject`, optionally give it
	a `Location` string attribute saying where to send it, and it is gone by the time the game runs.

	Ported from Meteor's service of the same name (`FlipHousesToBeRich` and `SaveBaddiesFromLava`
	carry older copies of it). Two things are deliberately different here; both are noted below.

	=== WHY THIS EXISTS AND NOT JUST "DELETE IT" ===============================================

	Raw car art, prop libraries and reference layouts are working material. `Workspace.CarArt` is
	the input to `RigCarBody`; `Workspace.OrderedCarsByWorld` is the authored source of the car
	ladder that `WorldConfig` note 1 tells you to re-derive by sorting on pivot Z. Both have to stay
	somewhere a person can look at them in the Explorer and drag things around in. Neither should
	ship inside a live Workspace, where every instance is server memory and a streaming candidate.

	This resolves that: the place file keeps them where they were authored, and the running game
	does not have them. It is the same idea `GetawayService` and `RoadService` already apply to the
	truck and the road tile — but those two PUBLISH (clone out, edit the clone, stash the original),
	which is a different job. This service only ever re-parents. It cannot replace either of them.

	=== THE ONE RULE ===========================================================================

	ONLY TAG THINGS NOTHING READS. There is no fallback here and there must not be one: a consumer
	that has to cope with "it might have moved already, it might not have" is the pattern Meteor
	ended up carrying in three separate services (`BaseService._resolveTemplate`,
	`MeteorSpawnService._resolveTemplatesFolder`, `UpgraderService`), each re-resolving its folder
	lazily on every call because the move is deferred and races their init.

	CarSteal does not have that problem and this file is written to keep it that way — see the sweep
	below. But the guarantee only holds for content with no consumer.

	`CarSystem` WAS the obvious thing to want to tag next (16% of Workspace on its own, and ~6,800
	instances on every client's join for art no client can read), and it could not be tagged while
	`RaceService`, `TrafficService`, `LobbyCarService` and `CarDisplay` each read `workspace.CarSystem`
	live. It is tagged now, and the real change that had to come first is `Modules/CarRoster`: one
	resolver, asked by all four, which reads this service's answer instead of assuming Workspace. Its
	header argues why asking in two places there is not the lazy re-resolution warned about above,
	and the short version is the sweep below: `init` is finished before any of them looks.

	=== DIFFERENCE 1: THE SWEEP IS SYNCHRONOUS =================================================

	`observeTag` is deferred TWICE — once to enumerate instances that already carry the tag, and
	again inside `AttemptStartup` before it calls back (see `Packages/_Index/sleitnick_observers`).
	So a service that observes a tag at `init` has not seen a single instance by the time `start`
	runs. That window is the whole reason Meteor's consumers need fallbacks.

	Everything this service moves is authored in the place file, so it does not need an observer to
	find any of it: `init` walks `CollectionService:GetTagged` in a straight loop and is finished
	before it returns. Shard runs every service's `init` before any service's `start`, so by the
	time anything is looking at Workspace, the relocation has happened.

	The observer is still attached, for one narrow case: something tagged AFTER boot, by a command
	or a plugin, mid-session. That path is deferred and always will be; nothing should depend on it.

	=== DIFFERENCE 2: AN UNTAGGED `Location` GOES TO SERVERSTORAGE =============================

	Meteor defaults a missing `Location` to `ReplicatedStorage`. Here the default is `ServerStorage`,
	because the reason to relocate anything in this game is to stop it reaching clients, and
	ReplicatedStorage replicates in full. A default that quietly leaves 4,000 instances on every
	client would do nothing but move the problem out of the Explorer.

	=== WHY THE TAG IS DROPPED AFTER THE MOVE ==================================================

	Meteor's comment on this is worth keeping verbatim in spirit: relocation is one-shot, so a
	`Clone()` of a relocated template does not inherit a live directive and get yanked out to its
	own `Location` (or, with `Location` already cleared, dumped in the default). The place file
	still carries the tag, so every fresh server boot relocates again.

	=== WHAT A BAD `Location` DOES =============================================================

	Nothing. It warns, naming the instance and the path that failed, and LEAVES THE INSTANCE WHERE
	IT IS. That is the safe direction: the thing stays visible in Workspace where a person will
	notice it, rather than being moved somewhere unintended or vanishing. The path is hand-typed in
	Studio, so a typo is the expected failure and it must not throw — an error raised inside an
	`observeTag` callback is swallowed into a traceback warning with no context about which
	instance caused it.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Trove = require(ReplicatedStorage.Packages.Trove)
local observeTag = require(ReplicatedStorage.Packages.Observers).observeTag

local RelocationService = Shard.new("RelocationService")

--[[ The contract, and it is authored in Studio rather than in code — which makes these two strings
	the one way to break this layer silently. Renaming either here without re-tagging the place
	leaves the content sitting in Workspace with nothing logged, because an untagged instance is
	indistinguishable from one that was never meant to move. ]]
RelocationService.Tag = "RelocateObject"
RelocationService.LocationAttribute = "Location"

-- Where a tagged instance goes when it names no `Location`. See "difference 2" above.
local DEFAULT_PARENT = ServerStorage

--[[ Resolve a `Location` string to a container.

	Two spellings, both from the original: a bare service name (`"ServerStorage"`), or a dotted path
	whose first segment is a service and whose remaining segments are children
	(`"ServerStorage.Assets.Base"`).

	Returns nil plus a reason rather than throwing, for the reason in the header. Every hop uses
	`FindFirstChild`; the original indexed the child directly off its parent, which raises on a
	missing child and takes the callback down with it.

	(Do not write that index expression out longhand in a comment here. Its closing double bracket
	ends this block comment, and the syntax error Luau then reports points at a later line.) ]]
local function resolveLocation(location: string): (Instance?, string?)
	local segments = string.split(location, ".")

	local ok, service = pcall(game.GetService, game, segments[1])
	if not ok or not service then
		return nil, string.format("'%s' is not a service", segments[1])
	end

	local parent: Instance = service
	for index = 2, #segments do
		local child = parent:FindFirstChild(segments[index])
		if not child then
			return nil, string.format("'%s' has no child '%s'", parent:GetFullName(), segments[index])
		end
		parent = child
	end

	return parent, nil
end

--[[ Move one tagged instance. Returns whether it moved.

	The tag comes off ONLY on success, so a mistyped `Location` can be corrected in Studio and
	re-run next boot without having to re-tag anything. ]]
function RelocationService._relocate(self, instance: Instance): boolean
	local location = instance:GetAttribute(self.LocationAttribute)
	local destination: Instance? = DEFAULT_PARENT

	if location ~= nil then
		if typeof(location) ~= "string" then
			self.log:warn(string.format(
				"%s has a non-string %s attribute (%s); left in place.",
				instance:GetFullName(),
				self.LocationAttribute,
				typeof(location)
			))
			return false
		end

		local resolved, reason = resolveLocation(location)
		if not resolved then
			self.log:warn(string.format(
				"%s wants '%s' but %s; left in place.",
				instance:GetFullName(),
				location,
				reason
			))
			return false
		end
		destination = resolved
	end

	local from = instance:GetFullName()
	instance.Parent = destination
	instance:SetAttribute(self.LocationAttribute, nil)
	-- One-shot: see the header. A clone taken later must not inherit a live directive.
	CollectionService:RemoveTag(instance, self.Tag)

	self.log:info(string.format("Relocated %s -> %s", from, (destination :: Instance):GetFullName()))
	return true
end

RelocationService:withLifecycle({
	--[[ `init`, not `start`, and synchronous — the whole point (see "difference 1"). Every service's
		`init` runs before any service's `start`, so anything that looks at Workspace when it starts
		is looking at a Workspace this has already emptied. ]]
	init = function(self)
		self._trove = Trove.new()

		local moved = 0
		--[[ `GetTagged` hands back a fresh array, so removing the tag as we go is safe. ]]
		for _, instance in CollectionService:GetTagged(self.Tag) do
			if self:_relocate(instance) then
				moved += 1
			end
		end
		if moved > 0 then
			self.log:info(string.format("Relocated %d authored instance(s) out of Workspace at boot.", moved))
		end

		--[[ For anything tagged mid-session only. Deferred, so nothing may depend on it — the boot
			sweep above has already dealt with everything the place file carries, and this observer
			will find that list empty when it eventually runs. ]]
		self._trove:Add(observeTag(self.Tag, function(instance)
			self:_relocate(instance)
		end))
	end,
})

RelocationService:withCleanup(function(self)
	if self._trove then
		self._trove:Destroy()
		self._trove = nil
	end
end)

return RelocationService
