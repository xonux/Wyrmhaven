-- Owns the pointer lifecycle: a short drag pans the camera (translate only,
-- see CameraController.Pan), a stationary click/tap raycasts and opens the
-- relevant bottom/center panel for whatever structure is under the pointer
-- (Habitat, Incubator, Farm, Nursery, a decoration, or an obstacle to clear). No character to stand next to, so the
-- server validates ownership once we tell it a structure id.
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local InteractionController = {}

local DRAG_THRESHOLD_PIXELS = 10 -- a tap that wobbles a little is still a tap

-- A single exact-pixel raycast makes small/thin targets (a Habitat platform
-- seen at a steep top-down angle, a dragon ball) easy to narrowly miss -
-- retries a small cross/diagonal pattern of nearby points before giving up,
-- same "forgiving tap target" idea mobile games rely on.
local CLICK_ASSIST_RADIUS_PIXELS = 14
local CLICK_ASSIST_OFFSETS = {
	Vector2.new(0, 0),
	Vector2.new(CLICK_ASSIST_RADIUS_PIXELS, 0),
	Vector2.new(-CLICK_ASSIST_RADIUS_PIXELS, 0),
	Vector2.new(0, CLICK_ASSIST_RADIUS_PIXELS),
	Vector2.new(0, -CLICK_ASSIST_RADIUS_PIXELS),
	Vector2.new(CLICK_ASSIST_RADIUS_PIXELS, CLICK_ASSIST_RADIUS_PIXELS),
	Vector2.new(-CLICK_ASSIST_RADIUS_PIXELS, CLICK_ASSIST_RADIUS_PIXELS),
	Vector2.new(CLICK_ASSIST_RADIUS_PIXELS, -CLICK_ASSIST_RADIUS_PIXELS),
	Vector2.new(-CLICK_ASSIST_RADIUS_PIXELS, -CLICK_ASSIST_RADIUS_PIXELS),
}

-- Checked in this order at each candidate point; every interactive
-- structure's Part (or the dragons/eggs sitting on it) carries exactly one
-- of these. A dragon counts as its building: a tap on it opens its habitat's
-- bar, never the Dragon screen directly (too easy to hit by mistake while
-- aiming at the habitat) - the screen opens from the dragon's portrait there.
local TRACKED_ATTRIBUTES = { "HabitatId", "IncubatorId", "FarmId", "NurseryId", "DecorationId", "ObstacleId" }

-- While set, every tap on something tracked goes to this function instead
-- of opening its panel: handler(attributeName, value). A dragon in a habitat
-- counts as its habitat. See SetTapHandler.
local tapHandler = nil

-- Selection modes (e.g. choosing the habitat of a hatchling) take over taps;
-- nil gives them back to the panels.
function InteractionController.SetTapHandler(handler)
	tapHandler = handler
end

local function isPointerInput(inputType)
	return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
end

-- A dragon's model is a client-side stand-in (DragonVisualController) hung
-- under the server's anchor part, which carries the dragon's attributes.
local function resolveHit(instance)
	local visual = instance:FindFirstAncestor("DragonVisual")
	return visual and visual.Parent or instance
end

function InteractionController.Init(remotesFolder, cameraController, placementController)
	local requestInteractHabitat = remotesFolder:WaitForChild("RequestInteractHabitat")
	local requestInteractIncubator = remotesFolder:WaitForChild("RequestInteractIncubator")
	local requestInteractFarm = remotesFolder:WaitForChild("RequestInteractFarm")
	local requestInteractNursery = remotesFolder:WaitForChild("RequestInteractNursery")
	local requestInteractObstacle = remotesFolder:WaitForChild("RequestInteractObstacle")
	local requestInteractDecoration = remotesFolder:WaitForChild("RequestInteractDecoration")

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

		if placementController.IsActive() then
			placementController.PointerTap(releasePos)
			return
		end

		local camera = Workspace.CurrentCamera
		for _, offset in ipairs(CLICK_ASSIST_OFFSETS) do
			local point = releasePos + offset
			-- InputObject.Position excludes the top-bar GUI inset. ScreenPointToRay
			-- accounts for it; ViewportPointToRay doesn't, which aimed every click
			-- about one top-bar height above the cursor.
			local ray = camera:ScreenPointToRay(point.X, point.Y)
			local result = Workspace:Raycast(ray.Origin, ray.Direction * 500)
			local hit = result and resolveHit(result.Instance)
			if hit and tapHandler then
				for _, attrName in ipairs(TRACKED_ATTRIBUTES) do
					local value = hit:GetAttribute(attrName)
					if value then
						tapHandler(attrName, value)
						return
					end
				end
			elseif hit then
				for _, attrName in ipairs(TRACKED_ATTRIBUTES) do
					local value = hit:GetAttribute(attrName)
					if value then
						if attrName == "HabitatId" then
							requestInteractHabitat:FireServer(value)
						elseif attrName == "IncubatorId" then
							requestInteractIncubator:FireServer(value)
						elseif attrName == "FarmId" then
							requestInteractFarm:FireServer(value)
						elseif attrName == "NurseryId" then
							requestInteractNursery:FireServer(value)
						elseif attrName == "DecorationId" then
							requestInteractDecoration:FireServer(value)
						elseif attrName == "ObstacleId" then
							requestInteractObstacle:FireServer(value)
						end
						return
					end
				end
			end
		end
	end)
end

return InteractionController
