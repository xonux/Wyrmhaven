-- Fixed angled top-down camera (Dragon Mania Legends-style), no character to follow.
local CameraController = {}

local PITCH_DEGREES = 55 -- angle down from horizontal - fixed, never changes
local DISTANCE = 70 -- studs from focus point to camera, frames a 60x60 island - fixed, never changes
local PAN_STUDS_PER_PIXEL = 0.08
local MAX_PAN_RADIUS = 45 -- studs the focus point may stray from the island center

local camera = workspace.CurrentCamera
local islandCenter = Vector3.new(0, 0, 0)
local focus = Vector3.new(0, 0, 0)

local pitchRad = math.rad(PITCH_DEGREES)
local cameraOffset = Vector3.new(0, math.sin(pitchRad) * DISTANCE, math.cos(pitchRad) * DISTANCE)

-- Ground-plane axes for a camera with fixed yaw/pitch: panning only ever slides
-- the focus point across this plane, so the look angle never changes.
local RIGHT_XZ = Vector3.new(1, 0, 0)
local FORWARD_XZ = Vector3.new(0, 0, -1)

local function updateCamera()
	camera.CFrame = CFrame.lookAt(focus + cameraOffset, focus)
end

local function clampFocus()
	local offset = focus - islandCenter
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude > MAX_PAN_RADIUS then
		flat = flat.Unit * MAX_PAN_RADIUS
		focus = islandCenter + flat
	end
end

function CameraController.Init(remotesFolder)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 60
	updateCamera()

	local setCameraTarget = remotesFolder:WaitForChild("SetCameraTarget")
	setCameraTarget.OnClientEvent:Connect(function(center)
		islandCenter = center
		focus = center
		updateCamera()
	end)
end

-- Translates the focus point by a screen-space drag delta; pitch/distance are
-- constants above and are never touched here, so the viewing angle can't change.
function CameraController.Pan(screenDeltaX, screenDeltaY)
	focus = focus - RIGHT_XZ * (screenDeltaX * PAN_STUDS_PER_PIXEL) + FORWARD_XZ * (screenDeltaY * PAN_STUDS_PER_PIXEL)
	clampFocus()
	updateCamera()
end

return CameraController
