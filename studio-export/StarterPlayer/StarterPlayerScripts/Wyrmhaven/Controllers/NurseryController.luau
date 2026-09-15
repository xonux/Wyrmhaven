-- Minimal Nursery UI: clicking the Nursery (see InteractionController) opens
-- this panel. Server pushes BreedingStatusUpdated whenever the player's
-- pairing state changes (or on request) - no client-side prediction, same
-- authoritative-server approach as the rest of the project.
local Players = game:GetService("Players")

local NurseryController = {}

function NurseryController.Init(remotesFolder)
	local requestInteractNursery = remotesFolder:WaitForChild("RequestInteractNursery")
	local requestStartBreeding = remotesFolder:WaitForChild("RequestStartBreeding")
	local requestCollectEgg = remotesFolder:WaitForChild("RequestCollectEgg")
	local breedingStatusUpdated = remotesFolder:WaitForChild("BreedingStatusUpdated")

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "NurseryGui"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(300, 360)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	frame.Parent = screenGui

	local outerLayout = Instance.new("UIListLayout")
	outerLayout.Padding = UDim.new(0, 6)
	outerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	outerLayout.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame

	local statusLabel = Instance.new("TextLabel")
	statusLabel.LayoutOrder = 1
	statusLabel.Size = UDim2.new(1, 0, 0, 40)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = Color3.new(1, 1, 1)
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextScaled = true
	statusLabel.Text = ""
	statusLabel.Parent = frame

	local collectButton = Instance.new("TextButton")
	collectButton.LayoutOrder = 2
	collectButton.Size = UDim2.new(1, 0, 0, 34)
	collectButton.Text = "Collect Egg"
	collectButton.Visible = false
	collectButton.Parent = frame
	collectButton.MouseButton1Click:Connect(function()
		requestCollectEgg:FireServer()
	end)

	local dragonListFrame = Instance.new("Frame")
	dragonListFrame.LayoutOrder = 3
	dragonListFrame.Size = UDim2.new(1, 0, 0, 240)
	dragonListFrame.BackgroundTransparency = 1
	dragonListFrame.Parent = frame

	local closeButton = Instance.new("TextButton")
	closeButton.LayoutOrder = 4
	closeButton.Size = UDim2.new(1, 0, 0, 30)
	closeButton.Text = "Close"
	closeButton.Parent = frame
	closeButton.MouseButton1Click:Connect(function()
		screenGui.Enabled = false
	end)

	local selected = {}

	local function rebuildDragonButtons(dragons)
		dragonListFrame:ClearAllChildren()
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.Parent = dragonListFrame

		if #dragons == 0 then
			local empty = Instance.new("TextLabel")
			empty.Size = UDim2.new(1, 0, 0, 30)
			empty.BackgroundTransparency = 1
			empty.TextColor3 = Color3.new(1, 1, 1)
			empty.Text = "No Adult dragons available"
			empty.Parent = dragonListFrame
			return
		end

		for _, dragon in ipairs(dragons) do
			local button = Instance.new("TextButton")
			button.Size = UDim2.new(1, 0, 0, 30)
			button.Text = string.format("%s Dragon #%d", dragon.element, dragon.id)
			button.Parent = dragonListFrame
			button.MouseButton1Click:Connect(function()
				table.insert(selected, dragon.id)
				button.Text = button.Text .. " (selected)"
				button.Active = false
				if #selected == 2 then
					requestStartBreeding:FireServer(selected[1], selected[2])
					selected = {}
				end
			end)
		end
	end

	-- Every push (explicit click, tick countdown, or after an action) refreshes
	-- content, but only an explicit click (openRequest) is allowed to force the
	-- panel open - otherwise the background tick would yank it back open right
	-- after the player hits Close.
	breedingStatusUpdated.OnClientEvent:Connect(function(state)
		selected = {}

		if state.openRequest then
			screenGui.Enabled = true
		end

		if state.pairing then
			dragonListFrame.Visible = false
			collectButton.Visible = state.pairing.ready
			if state.pairing.ready then
				statusLabel.Text = "Egg ready to collect!"
			else
				statusLabel.Text = string.format("Breeding... %ds left", state.pairing.secondsLeft)
			end
		else
			dragonListFrame.Visible = true
			collectButton.Visible = false
			statusLabel.Text = "Select 2 Adult dragons to breed"
			rebuildDragonButtons(state.availableDragons or {})
		end
	end)
end

return NurseryController
