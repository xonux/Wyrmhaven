-- Fixed angled top-down camera (Dragon Mania Legends-style), no character to follow.
local CameraController = {}

local PITCH_DEGREES = 55 -- angle down from horizontal - fixed, never changes
local DISTANCE = 70 -- studs from focus point to camera, frames a 60x60 island - fixed, never changes
local FIELD_OF_VIEW = 60
local PAN_STUDS_PER_PIXEL = 0.08
-- How far the focus point may stray from the island center: across the whole
-- 120x120 grass plate, and further back (-Z) to see the mountain behind it.
local PAN_LIMIT_SIDES = 62
local PAN_LIMIT_FRONT = 60
local PAN_LIMIT_BACK = 95

local camera = workspace.CurrentCamera
local islandCenter = Vector3.new(0, 0, 0)
local focus = Vector3.new(0, 0, 0)
-- True while another view has the camera (the Dragon screen's stage, see
-- Hold): island updates wait until it's handed back.
local held = false

local pitchRad = math.rad(PITCH_DEGREES)
local cameraOffset = Vector3.new(0, math.sin(pitchRad) * DISTANCE, math.cos(pitchRad) * DISTANCE)

-- Ground-plane axes for a camera with fixed yaw/pitch: panning only ever slides
-- the focus point across this plane, so the look angle never changes.
local RIGHT_XZ = Vector3.new(1, 0, 0)
local FORWARD_XZ = Vector3.new(0, 0, -1)

local function updateCamera()
	if held then
		return
	end
	camera.CFrame = CFrame.lookAt(focus + cameraOffset, focus)
end

local function clampFocus()
	focus = Vector3.new(
		math.clamp(focus.X, islandCenter.X - PAN_LIMIT_SIDES, islandCenter.X + PAN_LIMIT_SIDES),
		islandCenter.Y,
		math.clamp(focus.Z, islandCenter.Z - PAN_LIMIT_BACK, islandCenter.Z + PAN_LIMIT_FRONT)
	)
end

function CameraController.Init(remotesFolder)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FIELD_OF_VIEW
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

-- Lends the camera to a full-screen view rendered in the world (the Dragon
-- screen's stage, DragonViewport's World mode) until Release.
function CameraController.Hold(cframe, fieldOfView)
	held = true
	camera.FieldOfView = fieldOfView
	camera.CFrame = cframe
end

-- Back to the island, where it was.
function CameraController.Release()
	held = false
	camera.FieldOfView = FIELD_OF_VIEW
	updateCamera()
end

return CameraController
