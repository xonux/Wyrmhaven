-- Clickable BillboardGui icon overlays for every interactive world object -
-- Habitats, Farm, Nursery, Incubator, and the individual dragons/eggs
-- sitting in them (genre-standard: tap a dragon's own icon to reach its
-- popup, tap the structure to reach the structure's popup/panel).
-- A GuiButton's MouseButton1Click is pixel-perfect regardless of camera
-- angle, unlike raycasting a thin top-down platform (see InteractionController,
-- kept as a fallback for clicking the platform/ground itself) - this is the
-- reliable primary click path.
local Workspace = game:GetService("Workspace")

local WorldIconController = {}

local BUILDING_ICONS = {
	HabitatId = { glyph = "\240\159\143\160", color = Color3.fromRGB(255, 214, 120), remoteName = "RequestInteractHabitat" }, -- house
	FarmId = { glyph = "\240\159\140\190", color = Color3.fromRGB(200, 230, 140), remoteName = "RequestInteractFarm" }, -- sheaf of rice
	NurseryId = { glyph = "\240\159\146\158", color = Color3.fromRGB(230, 170, 220), remoteName = "RequestInteractNursery" }, -- two hearts
	IncubatorId = { glyph = "\240\159\165\154", color = Color3.fromRGB(230, 210, 150), remoteName = "RequestInteractIncubator" }, -- egg
}

local STAGE_GLYPHS = {
	Egg = "\240\159\165\154", -- egg
	Baby = "\240\159\144\163", -- hatching chick (closest to "baby dragon" without real art)
	Adult = "\240\159\144\137", -- dragon face
}

local BUILDING_ICON_SIZE = 56
local DRAGON_ICON_SIZE = 40

local function createIconButton(part, size, studsOffsetY, backgroundColor)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "WorldIconGui"
	billboard.Size = UDim2.fromOffset(size, size)
	billboard.StudsOffset = Vector3.new(0, studsOffsetY, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local button = Instance.new("TextButton")
	button.Name = "IconButton"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = backgroundColor
	button.BackgroundTransparency = 0.1
	button.AutoButtonColor = true
	button.Text = ""
	button.TextScaled = true
	button.Font = Enum.Font.GothamBold
	button.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0) -- circular "case"
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Parent = button

	return button
end

function WorldIconController.Init(remotesFolder)
	local remoteCache = {}
	local function getRemote(name)
		if not remoteCache[name] then
			remoteCache[name] = remotesFolder:WaitForChild(name)
		end
		return remoteCache[name]
	end

	local function attachBuildingIcon(part, attrName, def)
		local value = part:GetAttribute(attrName)
		if not value then return end

		local button = createIconButton(part, BUILDING_ICON_SIZE, part.Size.Y / 2 + 2, def.color)
		button.Text = def.glyph

		button.MouseButton1Click:Connect(function()
			getRemote(def.remoteName):FireServer(value)
		end)
	end

	-- Dragons/eggs move between the Incubator and a Habitat over their
	-- lifetime (see DragonService.MoveToHabitat) - the same Part is reused,
	-- only its HabitatId/IncubatorId attribute changes, so the click handler
	-- reads both fresh at click time rather than capturing a stale value.
	local function attachDragonIcon(part)
		local button = createIconButton(part, DRAGON_ICON_SIZE, part.Size.Y / 2 + 1.5, part.Color)
		button.Text = STAGE_GLYPHS[part:GetAttribute("Stage")] or "?"

		part:GetAttributeChangedSignal("Stage"):Connect(function()
			button.Text = STAGE_GLYPHS[part:GetAttribute("Stage")] or "?"
		end)
		part:GetPropertyChangedSignal("Color"):Connect(function()
			button.BackgroundColor3 = part.Color
		end)

		button.MouseButton1Click:Connect(function()
			local habitatId = part:GetAttribute("HabitatId")
			local incubatorId = part:GetAttribute("IncubatorId")
			if habitatId then
				getRemote("RequestInteractDragon"):FireServer(part:GetAttribute("DragonId"))
			elseif incubatorId then
				getRemote("RequestInteractIncubator"):FireServer(incubatorId)
			end
		end)
	end

	local function attachToPart(part)
		if not part:IsA("BasePart") then return end
		if part:FindFirstChild("WorldIconGui") then return end -- already attached

		if part:GetAttribute("DragonId") then
			attachDragonIcon(part)
			return
		end

		for attrName, def in pairs(BUILDING_ICONS) do
			attachBuildingIcon(part, attrName, def)
		end
	end

	for _, part in ipairs(Workspace:GetDescendants()) do
		attachToPart(part)
	end

	Workspace.DescendantAdded:Connect(attachToPart)
end

return WorldIconController
