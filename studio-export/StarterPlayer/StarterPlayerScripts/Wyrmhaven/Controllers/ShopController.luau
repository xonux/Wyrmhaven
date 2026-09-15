-- Full-screen Shop (Habitats / Décorations / Dragons tabs), built entirely in
-- code like HudController. Each tab checks whether its backing RemoteEvent
-- exists yet (the 3 Shop backend tasks land independently and may not all be
-- done) and falls back to a "coming soon" placeholder instead of blocking the
-- whole Shop - see todo/shop-ui.md for why.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local HabitatDefs = require(Config.HabitatDefs)
local DragonDefs = require(Config.DragonDefs)

local ShopController = {}

local latestBalance = { Coins = 0, Gems = 0 }
local latestHabitatCounts = {} -- [element] = count, pushed via UpdateHud (see HudService)

local TABS = {
	{ id = "Habitats", label = "Habitats", remoteName = "RequestBuyHabitat" },
	{ id = "Decorations", label = "Décorations", remoteName = "RequestBuyDecoration" },
	{ id = "Dragons", label = "Dragons", remoteName = "RequestBuyDragon" },
}

local function createButton(parent, name, text, size, position)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = text
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	return button
end

local function createPlaceholder(parent, text)
	local label = Instance.new("TextLabel")
	label.Name = "Placeholder"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(200, 200, 200)
	label.Font = Enum.Font.Gotham
	label.TextScaled = true
	label.Text = text
	label.Parent = parent
	return label
end

-- name/price/onBuy generic card - every tab builds its item list into this
-- same shape so the rendering itself doesn't need to know which tab it's for.
local function createCard(parent, layoutOrder, displayName, priceText, canAfford, alreadyOwned, onBuy)
	local card = Instance.new("Frame")
	card.Name = displayName
	card.LayoutOrder = layoutOrder
	card.Size = UDim2.new(1, 0, 0, 64)
	card.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.5, -10, 1, 0)
	nameLabel.Position = UDim2.fromOffset(12, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = displayName
	nameLabel.Parent = card

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Size = UDim2.new(0.25, 0, 1, 0)
	priceLabel.Position = UDim2.new(0.5, 0, 0, 0)
	priceLabel.BackgroundTransparency = 1
	priceLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	priceLabel.Font = Enum.Font.Gotham
	priceLabel.TextScaled = true
	priceLabel.Text = priceText
	priceLabel.Parent = card

	local buyButton = createButton(card, "BuyButton", alreadyOwned and "Possédé" or "Acheter", UDim2.new(0.22, -12, 0.7, 0), UDim2.new(0.78, 0, 0.15, 0))
	local disabled = alreadyOwned or not canAfford
	buyButton.AutoButtonColor = not disabled
	buyButton.BackgroundColor3 = disabled and Color3.fromRGB(60, 60, 60) or Color3.fromRGB(50, 120, 60)
	if not disabled then
		buyButton.MouseButton1Click:Connect(onBuy)
	end

	return card
end

-- Habitats: price scales with how many of that element the player already
-- owns (ShopBaseCost * CostGrowth ^ owned), mirroring ShopService.BuyHabitat
-- exactly. latestHabitatCounts comes from UpdateHud (see HudService).
local function populateHabitats(content, requestBuyHabitat)
	local order = 0
	for element, def in pairs(HabitatDefs) do
		order += 1
		local ownedCount = latestHabitatCounts[element] or 0
		local price = math.floor((def.ShopBaseCost or 0) * (def.CostGrowth ^ ownedCount))
		local displayName = ownedCount > 0 and string.format("%s (x%d)", def.DisplayName, ownedCount) or def.DisplayName
		createCard(content, order, displayName, string.format("%d Pièces", price), latestBalance.Coins >= price, false, function()
			requestBuyHabitat:FireServer(element)
		end)
	end
end

-- Decorations: ReplicatedStorage.Wyrmhaven.Config.DecorationDefs doesn't exist
-- yet (shop-decorations.md not landed) - required lazily via pcall so this
-- tab degrades to the placeholder instead of erroring.
local function populateDecorations(content, requestBuyDecoration)
	local ok, DecorationDefs = pcall(function()
		return require(Config:WaitForChild("DecorationDefs"))
	end)
	if not ok then
		createPlaceholder(content, "Bientôt disponible")
		return
	end

	local order = 0
	for decorationId, def in pairs(DecorationDefs) do
		order += 1
		createCard(content, order, def.DisplayName or decorationId, string.format("%d Pièces", def.Price or 0), latestBalance.Coins >= (def.Price or 0), false, function()
			-- TODO shop-decorations: real placement UX (pick a spot on the island)
			-- instead of a fixed origin, once that task defines how placement works.
			requestBuyDecoration:FireServer(decorationId, Vector3.new())
		end)
	end
end

-- Dragons exclusifs: looks for DragonDefs entries flagged Exclusive (see
-- shop-exclusive-dragons.md) - none exist yet, so this is empty today.
local function populateDragons(content, requestBuyDragon)
	local order = 0
	for element, def in pairs(DragonDefs) do
		if def.Exclusive then
			order += 1
			local price = def.GemPrice or 0
			createCard(content, order, def.DisplayName, string.format("%d Gemmes", price), latestBalance.Gems >= price, false, function()
				requestBuyDragon:FireServer(element)
			end)
		end
	end
	if order == 0 then
		createPlaceholder(content, "Bientôt disponible")
	end
end

local POPULATORS = {
	Habitats = populateHabitats,
	Decorations = populateDecorations,
	Dragons = populateDragons,
}

function ShopController.Init(remotesFolder)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local updateHud = remotesFolder:FindFirstChild("UpdateHud")
	if updateHud then
		updateHud.OnClientEvent:Connect(function(data)
			latestBalance.Coins = data.Coins
			latestBalance.Gems = data.Gems
			latestHabitatCounts = data.HabitatCounts or latestHabitatCounts
		end)
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ShopGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	-- y=56 clears Roblox's default top-right CoreGui icons (chat/leaderboard),
	-- which otherwise intercept clicks meant for this button.
	createButton(screenGui, "ShopButton", "Shop", UDim2.fromOffset(90, 36), UDim2.new(1, -102, 0, 56))

	local panel = Instance.new("Frame")
	panel.Name = "ShopPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.7, 0.75)
	panel.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = screenGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	createButton(panel, "CloseButton", "X", UDim2.fromOffset(32, 32), UDim2.new(1, -44, 0, 12))

	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, -24, 0, 44)
	tabBar.Position = UDim2.fromOffset(12, 12)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = panel

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabBar

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -24, 1, -68)
	content.Position = UDim2.fromOffset(12, 68)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.Parent = panel

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Padding = UDim.new(0, 8)
	contentLayout.Parent = content

	local activeTabId = TABS[1].id
	local tabButtons = {}

	local function renderActiveTab()
		content:ClearAllChildren() -- also destroys the previous render's UIListLayout, recreated below
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 8)
		layout.Parent = content

		for _, tab in ipairs(TABS) do
			tabButtons[tab.id].BackgroundColor3 = (tab.id == activeTabId) and Color3.fromRGB(70, 70, 90) or Color3.fromRGB(40, 40, 40)
		end

		local activeTab
		for _, tab in ipairs(TABS) do
			if tab.id == activeTabId then
				activeTab = tab
				break
			end
		end

		local remote = remotesFolder:FindFirstChild(activeTab.remoteName)
		if not remote then
			createPlaceholder(content, "Bientôt disponible")
			return
		end

		POPULATORS[activeTab.id](content, remote)
	end

	for index, tab in ipairs(TABS) do
		local tabButton = createButton(tabBar, tab.id, tab.label, UDim2.fromOffset(140, 44), UDim2.new())
		tabButton.LayoutOrder = index
		tabButtons[tab.id] = tabButton
		tabButton.MouseButton1Click:Connect(function()
			activeTabId = tab.id
			renderActiveTab()
		end)
	end

	screenGui.ShopButton.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			renderActiveTab()
		end
	end)

	panel.CloseButton.MouseButton1Click:Connect(function()
		panel.Visible = false
	end)
end

return ShopController
