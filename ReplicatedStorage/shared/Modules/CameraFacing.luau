--[[
	CameraFacing
	------------
	Turns the stock camera to stand behind the local character, looking the way they face.

	The stock camera keeps no heading of its own: every frame it takes its DIRECTION from wherever
	`Camera.CFrame` points and only its zoom from its own state. So anything that borrowed the camera
	and lets go of it leaves the player looking wherever the borrowed shot looked, and writing one
	`CFrame` is the whole of turning it back. Zoom is left alone for the same reason: the stock camera
	puts the shot at its own distance on the next frame whatever distance is written here.

	Used where a borrowed shot is handed back in the lobby (`CameraConfig.Landing` says which and
	why): the race camera after a run, and the NEW BEST cutscene that follows one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CameraConfig = require(ReplicatedStorage.shared.Configs.CameraConfig)

local CameraFacing = {}

--- Studs above the root the stock camera frames for a humanoid (its head offset), so the shot written
--- here is the one the next frame would draw anyway.
local FOCUS_HEIGHT = 1.5

--[[ Point the camera along the character's facing, `CameraConfig.Landing.PitchDeg` below level.
	Returns whether it did: nothing happens with `Landing` off, with no character, or while somebody
	holds the camera as Scriptable (that owner hands it back with its own view). ]]
function CameraFacing.behindCharacter(): boolean
	local landing = CameraConfig.Landing
	if not landing.Enabled then
		return false
	end
	local camera = Workspace.CurrentCamera
	if not camera or camera.CameraType == Enum.CameraType.Scriptable then
		return false
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	local facing = root.CFrame.LookVector
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude < 1e-3 then
		return false
	end
	local pitch = math.rad(landing.PitchDeg)
	local look = flat.Unit * math.cos(pitch) - Vector3.yAxis * math.sin(pitch)
	local focus = root.Position + Vector3.new(0, FOCUS_HEIGHT, 0)
	--- The shot's current distance, which is the player's zoom unless something pulled it in; only the
	--- first frame ever sees it.
	local distance = math.clamp((camera.CFrame.Position - camera.Focus.Position).Magnitude, 0.5, 128)
	camera.CFrame = CFrame.lookAt(focus - look * distance, focus)
	return true
end

return CameraFacing
