-- Owns the pointer lifecycle: a short drag pans the camera (translate only,
-- see CameraController.Pan), a stationary click/tap raycasts and interacts
-- with whatever dragon part is under the pointer. No character to stand next
-- to, so the server validates ownership/stage once we tell it a dragon id.
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local InteractionController = {}

local DRAG_THRESHOLD_PIXELS = 6

local function isPointerInput(inputType)
	return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
end

function InteractionController.Init(remotesFolder, cameraController)
	local camera = Workspace.CurrentCamera
	local requestInteractDragon = remotesFolder:WaitForChild("RequestInteractDragon")
	local requestInteractFarm = remotesFolder:WaitForChild("RequestInteractFarm")
	local requestInteractNursery = remotesFolder:WaitForChild("RequestInteractNursery")

	local tracking = false
	local dragging = false
	local startPos = Vector2.new()
	local lastPos = Vector2.new()

	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then return end
		if not isPointerInput(input.UserInputType) then return end

		tracking = true
		dragging = false
		startPos = Vector2.new(input.Position.X, input.Position.Y)
		lastPos = startPos
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not tracking then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local pos = Vector2.new(input.Position.X, input.Position.Y)
		local delta = pos - lastPos
		lastPos = pos

		if not dragging and (pos - startPos).Magnitude > DRAG_THRESHOLD_PIXELS then
			dragging = true
		end

		if dragging then
			cameraController.Pan(delta.X, delta.Y)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not tracking then return end
		if not isPointerInput(input.UserInputType) then return end

		tracking = false

		if dragging then return end

		local releasePos = Vector2.new(input.Position.X, input.Position.Y)
		local ray = camera:ViewportPointToRay(releasePos.X, releasePos.Y)
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 500)
		if not result then return end

		local dragonId = result.Instance:GetAttribute("DragonId")
		if dragonId then
			requestInteractDragon:FireServer(dragonId)
			return
		end

		local farmId = result.Instance:GetAttribute("FarmId")
		if farmId then
			requestInteractFarm:FireServer(farmId)
			return
		end

		local nurseryId = result.Instance:GetAttribute("NurseryId")
		if nurseryId then
			requestInteractNursery:FireServer(nurseryId)
		end
	end)
end

return InteractionController
