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
	why): the race camera after a run, and the NEW BEST cutscene that follows one. `watch` (2026-10-19)
	is the same write made every frame, to keep the camera facing something that moves.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
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

--[[ Swing the stock camera round behind the character to face a point, and keep facing it while it
	moves, until `stop` is called or `settings.MaxSeconds` runs out. Returns `stop`. The tutorial uses
	it to make a new player watch their first buyer walk up (`TutorialConfig.Look`, which documents
	`settings`).

	The same trick as `behindCharacter`, every frame: write the direction just after the stock camera
	has run, and it carries on from there. Eased toward the point (`Rate`), so it is a turn of the
	head rather than a cut, and the shot looks down at `PitchDeg` whatever the point's height, which
	keeps the point above the player's head on screen. Writing every frame means the player cannot
	turn the camera meanwhile, so callers keep it short. On `stop` the camera simply stays where it
	is looking. ]]
function CameraFacing.watch(point: () -> Vector3?, settings): () -> ()
	local name = "CameraFacingWatch"
	local started = os.clock()
	local done = false
	local function stop()
		if done then
			return
		end
		done = true
		RunService:UnbindFromRenderStep(name)
	end
	--- One watch at a time: a second one replaces the first.
	RunService:UnbindFromRenderStep(name)
	--[[ THE PLAYER TAKES IT BACK (`settings.StopOnInput`, 2026-10-20: "acts very weirdly if I start
		moving"). Walking is camera-relative, so a camera turned under a moving player bends their
		path every frame, and the turn overrides their own mouse-look. Any move or camera turn of
		theirs ends the watch at once; the camera stays where it is, which is the stock hand-back. ]]
	local inputConn: RBXScriptConnection? = nil
	if settings.StopOnInput then
		inputConn = UserInputService.InputBegan:Connect(function(input)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton2 or kind == Enum.UserInputType.Touch
				or input.KeyCode == Enum.KeyCode.Thumbstick2 then
				stop()
			end
		end)
	end
	local baseStop = stop
	stop = function()
		if inputConn then
			inputConn:Disconnect()
			inputConn = nil
		end
		baseStop()
	end
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		if os.clock() - started > settings.MaxSeconds then
			stop()
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera or camera.CameraType == Enum.CameraType.Scriptable then
			return
		end
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local at = point()
		if not (root and root:IsA("BasePart") and at) then
			stop()
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if settings.StopOnInput and humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
			stop()
			return
		end
		local focus = root.Position + Vector3.new(0, FOCUS_HEIGHT, 0)
		local flat = Vector3.new(at.X - focus.X, 0, at.Z - focus.Z)
		if flat.Magnitude < settings.MinStuds then
			return
		end
		local pitch = math.rad(settings.PitchDeg)
		local want = flat.Unit * math.cos(pitch) - Vector3.yAxis * math.sin(pitch)
		local look = camera.CFrame.LookVector:Lerp(want, 1 - math.exp(-settings.Rate * dt))
		if look.Magnitude < 1e-3 then
			return
		end
		local distance = math.clamp((camera.CFrame.Position - camera.Focus.Position).Magnitude, 0.5, 128)
		camera.CFrame = CFrame.lookAt(focus - look.Unit * distance, focus)
	end)
	return stop
end

return CameraFacing
