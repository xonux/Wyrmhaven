-- Persistent top-left resource bar (Coins/Gems/Food). Kept in sync purely by
-- listening for the server's periodic UpdateHud push (see HudService) - no
-- client-side prediction, same authoritative-server approach as the rest of
-- the project.
local Players = game:GetService("Players")

local HudController = {}

local function createLabel(parent, name, layoutOrder)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = layoutOrder
	label.Size = UDim2.fromOffset(90, 32)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.Text = name .. ": 0"
	label.Parent = parent
	return label
end

function HudController.Init(remotesFolder)
	local updateHud = remotesFolder:WaitForChild("UpdateHud")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HudGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local container = Instance.new("Frame")
	container.Name = "ResourceBar"
	container.Position = UDim2.fromOffset(12, 12)
	container.Size = UDim2.fromOffset(300, 40)
	container.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	container.BackgroundTransparency = 0.35
	container.BorderSizePixel = 0
	container.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 14)
	layout.Parent = container

	local coinsLabel = createLabel(container, "Coins", 1)
	local gemsLabel = createLabel(container, "Gems", 2)
	local foodLabel = createLabel(container, "Food", 3)

	updateHud.OnClientEvent:Connect(function(data)
		coinsLabel.Text = string.format("Coins: %d", data.Coins)
		gemsLabel.Text = string.format("Gems: %d", data.Gems)
		foodLabel.Text = string.format("Food: %d", data.Food)
	end)
end

return HudController
