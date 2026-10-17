--[[
	SunBurst component  (client)
	----------------------------
	Tag any GuiObject `SunBurst` and it turns, forever. The radiating rays behind an offer card or a
	reveal panel — the thing that makes a car being handed over read as a prize rather than as a row
	in a list.

		RotateSpeed    number   degrees/second, default 20. Negative turns the other way.

	PORTED FROM NEEDOHESCAPE, verbatim in behaviour, which is the same provenance `UIController`
	itself has ("the structure the boss wants us on" — see its header). Two games in the same house
	spinning their bursts at different speeds is the sort of difference nobody can name and everybody
	feels, so the default is theirs and the attribute is the per-instance escape hatch.

	=== IT IS A COMPONENT AND NOT A LINE IN A CONTROLLER =======================================

	`RandomCarController` draws two bursts — one on the card, one on the reveal — and `RaceUIController`
	already draws a third behind the run results. Three `RenderStepped` connections turning three
	images would be three copies of `Rotation = (Rotation + speed * dt) % 360`, and the first one to
	be tuned would be the only one that changed.

	ONE LOOP FOR ALL OF THEM, started on the first tagged instance and torn down with the last. The
	cost of a burst nobody is looking at is therefore nothing at all: a hidden card's image is still
	in `active`, but a `ScreenGui` that is not rendering is not a frame anybody pays for, and the
	whole set is one iteration of a table with two entries in it.

	`RotateSpeed` IS RE-READ EVERY FRAME rather than cached at tag time, on purpose: it makes the
	speed draggable in the Explorer during a playtest, which is the only way a number like this ever
	gets picked. It is one attribute read per burst per frame and it buys the tuning loop.

	=== WHAT IT DOES NOT DO ===================================================================

	IT DOES NOT COLOUR ANYTHING. `UIAssets.Results.Sunburst` is pure white by construction so that
	`ImageColor3` picks the colour — see the long note in `UIAssets` on why the burst was drawn
	rather than sliced out of a mockup, and why white is what lets one upload serve every screen that
	wants a different tint. A component that also painted would take that choice away from the
	screens.

	IT DOES NOT SET `Rotation` TO ANYTHING AT TEARDOWN. A card that slides off screen keeps the angle
	it stopped at and picks it up from there next time, which is right: a burst that snapped back to
	0 every time the card hid would flicker on every appearance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIControllerTypes = require(script.Parent.Parent.UIControllerTypes)
local observeTag = require(ReplicatedStorage.Packages.Observers).observeTag

local DEFAULT_SPEED = 20 -- degrees/second

return function(_UIController: UIControllerTypes.UIController)
	local active: { [GuiObject]: true } = {}
	local renderConn: RBXScriptConnection?

	observeTag("SunBurst", function(instance: GuiObject)
		if not instance:IsA("GuiObject") then
			return
		end

		active[instance] = true
		if not renderConn then
			renderConn = RunService.RenderStepped:Connect(function(dt)
				for sunburst in active do
					local speed = sunburst:GetAttribute("RotateSpeed") or DEFAULT_SPEED
					sunburst.Rotation = (sunburst.Rotation + speed * dt) % 360
				end
			end)
		end

		return function()
			active[instance] = nil
			if renderConn and next(active) == nil then
				renderConn:Disconnect()
				renderConn = nil
			end
		end
	end)
end
