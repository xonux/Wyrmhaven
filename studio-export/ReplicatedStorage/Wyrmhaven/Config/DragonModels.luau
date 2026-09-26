-- Rigged dragon models by element and stage: Assets.Dragons.<Element>.<Stage>
-- (made with ServerStorage.WyrmhavenBuildKit.DragonBuilder; each carries
-- Element / Stage attributes). Shared by DragonService, which hides the
-- placeholder ball of a dragon that has a model, and the client, which draws
-- and animates that model (DragonVisualController, DragonViewport, Shop).
-- Elements or stages without a model (eggs, elements not modeled yet) keep
-- the placeholder.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DragonModels = {}

function DragonModels.Get(element, stage)
	local assets = ReplicatedStorage.Wyrmhaven:FindFirstChild("Assets")
	local dragons = assets and assets:FindFirstChild("Dragons")
	if not dragons or not element or not stage then
		return nil
	end
	local byElement = dragons:FindFirstChild(element)
	local model = byElement and byElement:FindFirstChild(stage)
	if model and model:IsA("Model") then
		return model
	end
	-- Tolerates the models being moved around under Dragons in Studio.
	for _, descendant in ipairs(dragons:GetDescendants()) do
		if descendant:IsA("Model") and descendant:GetAttribute("Element") == element and descendant:GetAttribute("Stage") == stage then
			return descendant
		end
	end
	return nil
end

return DragonModels
