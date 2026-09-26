-- Turns the sails of the farms' windmills while a crop grows (FarmService sets
-- the farm's Working attribute), easing in and out. Client-side only: the
-- server never turns them, so each frame rebuilds the sails' CFrame from the
-- farm's current spot (it can be moved) and the angle reached so far.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FarmVisualController = {}

local TAG = "Farm" -- set by FarmService on every farm's base part
local FULL_SPEED = math.pi / 2 -- radians per second: a quarter turn
local ACCELERATION = math.pi / 2 -- radians per second, per second

local spinning = {} -- [farm base part] = { angle, speed }

function FarmVisualController.Init()
	local buildings = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets"):FindFirstChild("Buildings")
	local template = buildings and buildings:FindFirstChild("Farm")
	local templateVisual = template and template:FindFirstChild("Visual")
	local templateBlades = templateVisual and templateVisual:FindFirstChild("Blades")
	if not templateBlades then
		return
	end
	-- The sails' pivot (their hub, axle along its Z) from the farm's base part.
	local bladesOffset = template.CFrame:ToObjectSpace(templateBlades:GetPivot())

	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(farm)
		spinning[farm] = nil
	end)

	RunService.RenderStepped:Connect(function(dt)
		for _, farm in ipairs(CollectionService:GetTagged(TAG)) do
			local visual = farm:FindFirstChild("Visual")
			local blades = visual and visual:FindFirstChild("Blades")
			if blades and farm:IsA("BasePart") then
				local state = spinning[farm]
				if not state then
					state = { angle = 0, speed = 0 }
					spinning[farm] = state
				end
				local target = farm:GetAttribute("Working") and FULL_SPEED or 0
				state.speed += math.clamp(target - state.speed, -ACCELERATION * dt, ACCELERATION * dt)
				state.angle = (state.angle + state.speed * dt) % (2 * math.pi)
				blades:PivotTo(farm.CFrame * bladesOffset * CFrame.Angles(0, 0, state.angle))
			end
		end
	end)
end

return FarmVisualController
