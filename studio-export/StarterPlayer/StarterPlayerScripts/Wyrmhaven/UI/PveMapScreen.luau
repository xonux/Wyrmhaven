-- The exploration map (Config/PveMap), drawn like the island screens: the
-- archipelago is built far from the islands and the world camera is lent to it
-- (CameraController.Hold), with the interface floating over it. Each stage is
-- a marker standing on an island; its button follows it on screen
-- (WorldToViewportPoint), which clicks far better than anything world-space.
--
-- Tapping a stage shows who is waiting there and what it pays. The row at the
-- bottom is the team that goes in - up to three Adults, tap a slot to change
-- one. Fight sends it; the result comes back through ShowResult.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UITheme = require(script.Parent.UITheme)
local UIKit = require(script.Parent.UIKit)
local DragonRig = require(script.Parent.DragonRig)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)

local Config = ReplicatedStorage.Wyrmhaven.Config
local DragonDefs = require(Config.DragonDefs)
local DragonModels = require(Config.DragonModels)
local DragonClasses = require(Config.DragonClasses)
local PveMap = require(Config.PveMap)

local decorationTemplates = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets"):FindFirstChild("Decorations")

local PveMapScreen = {}

-- The stage, far behind the islands (each screen that borrows the world camera
-- has its own spot so two of them never meet).
local STAGE_ORIGIN = Vector3.new(0, 0, -28000)
-- Picked by projecting the ten stages and keeping the view where they all sit
-- clear of the header and the bottom bar, on a wide screen and on a 4:3 one.
-- The narrow field of view flattens the perspective, which reads like a map.
local CAMERA_LOOK = Vector3.new(10, 0, 30) -- the point it aims at, from STAGE_ORIGIN
local CAMERA_OFFSET = Vector3.new(0, 160, 220) -- where it stands, from that point
local CAMERA_FOV = 24
local GRASS_TOP = 3 -- height the markers and scenery stand at
-- A boss is drawn far bigger here than in a fight: on a map the size of two
-- islands, a dragon at its own scale is a speck.
local MAP_BOSS_SCALE = 3

local SEA_COLOR = Color3.fromRGB(38, 110, 158)
local SHALLOW_COLOR = Color3.fromRGB(92, 178, 206)
local GRASS_COLOR = Color3.fromRGB(108, 172, 94)
local SAND_COLOR = Color3.fromRGB(226, 208, 160)
local STONE_COLOR = Color3.fromRGB(188, 182, 170)
local CLEARED_COLOR = Color3.fromRGB(230, 192, 110)
local OPEN_COLOR = Color3.fromRGB(226, 96, 84)
local LOCKED_COLOR = Color3.fromRGB(120, 126, 136)

local WHITE = Color3.new(1, 1, 1)
local STRIPPED_CLASSES = { "LuaSourceContainer", "Sound", "Highlight", "LayerCollector" }
local SCENERY = { "TreeGreen", "Pine", "Bush", "TreeAutumn" }


local gui, root
local scales = {}
local stage = nil -- the archipelago in the world, see buildStage
local status = nil
local selectedId = nil
local callbacks = {}
local isOpen = false
local hiddenGuis = {}
local nodeButtons = {} -- [levelId] = { button, label, badge }
local panel, panelParts
local progressLabel
local teamSlots = {}
local picker, pickerRows
local resultCard, resultParts
local pickingSlot = nil
local renderNodes, renderNodeLooks

------------------------------------------------------------------ helpers

local function levelById(levelId)
	for _, level in ipairs(status and status.levels or {}) do
		if level.id == levelId then
			return level
		end
	end
	return nil
end

local function rosterById(dragonId)
	for _, dragon in ipairs(status and status.roster or {}) do
		if dragon.id == dragonId then
			return dragon
		end
	end
	return nil
end

-- The screen is see-through (the world camera draws the map), so the
-- interfaces under it are switched off while it is open.
local function hideLowerGuis(hide)
	if hide then
		for _, other in ipairs(gui.Parent:GetChildren()) do
			if other:IsA("ScreenGui") and other ~= gui and other.Enabled and other.DisplayOrder < gui.DisplayOrder then
				other.Enabled = false
				table.insert(hiddenGuis, other)
			end
		end
	else
		for _, other in ipairs(hiddenGuis) do
			other.Enabled = true
		end
		table.clear(hiddenGuis)
	end
end

------------------------------------------------------------------ the map in the world

local function prepareClone(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		for _, className in ipairs(STRIPPED_CLASSES) do
			if descendant:IsA(className) then
				descendant:Destroy()
				break
			end
		end
	end
	local function lock(part)
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	lock(instance)
	for _, part in ipairs(instance:GetDescendants()) do
		lock(part)
	end
end

local function worldPosition(point, height)
	return STAGE_ORIGIN + Vector3.new(point.x, height or 0, point.z)
end

-- Flat elliptical slab: islands, beaches and markers are all one of these.
-- A Cylinder's axis runs along its X, so it is turned onto its side and its
-- other two sizes become the diameters.
local function disc(parent, center, diameterX, diameterZ, height, top, color)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameterX, diameterZ)
	part.CFrame = CFrame.new(center + Vector3.new(0, top - height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = parent
	return part
end

local function destroyStage()
	if not stage then
		return
	end
	for _, connection in ipairs(stage.connections) do
		connection:Disconnect()
	end
	stage.folder:Destroy()
	stage = nil
	CameraController.Release()
end

-- Trees and bushes scattered over an island, away from its markers so nothing
-- hides a stage. Same seed every time, so the map always looks the same.
local function scatterScenery(folder, region, markers, rng)
	if not decorationTemplates then
		return
	end
	local center = Vector2.new(region.Center.x, region.Center.z)
	local radiusX, radiusZ = region.Size.x / 2, region.Size.z / 2
	local placed = 0
	for _ = 1, 90 do
		if placed >= 18 then
			break
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local spread = math.sqrt(rng:NextNumber(0.1, 0.86))
		local point = Vector2.new(center.X + math.cos(angle) * radiusX * spread, center.Y + math.sin(angle) * radiusZ * spread)
		local clear = true
		for _, marker in ipairs(markers) do
			if (point - marker).Magnitude < 12 then
				clear = false
				break
			end
		end
		if clear then
			local template = decorationTemplates:FindFirstChild(SCENERY[rng:NextInteger(1, #SCENERY)])
			if template then
				local clone = template:Clone()
				prepareClone(clone)
				local model = Instance.new("Model")
				clone.Parent = model
				model.WorldPivot = CFrame.new(clone.Position - Vector3.new(0, clone.Size.Y / 2, 0))
				model:ScaleTo(rng:NextNumber(0.8, 1.25))
				model:PivotTo(CFrame.new(worldPosition({ x = point.X, z = point.Y }, GRASS_TOP)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
				clone.Parent = folder
				model:Destroy()
				placed += 1
			end
		end
	end
end

-- Dotted trail from one stage to the next, stepping over the water between
-- the two regions.
local function layPath(folder, from, to)
	local a = Vector2.new(from.x, from.z)
	local b = Vector2.new(to.x, to.z)
	local span = (b - a).Magnitude
	local steps = math.max(1, math.floor(span / 7))
	for i = 1, steps - 1 do
		local point = a:Lerp(b, i / steps)
		disc(folder, worldPosition({ x = point.X, z = point.Y }, 0), 3, 3, 0.6, GRASS_TOP + 0.15, STONE_COLOR)
	end
end

-- The boss itself stands on its marker, drawn bigger - that is all a boss is.
local function placeBoss(folder, level)
	local boss
	for _, enemy in ipairs(level.enemies) do
		if enemy.boss then
			boss = enemy
			break
		end
	end
	if not boss then
		return
	end
	-- A step behind its marker, so the stage's own button stays clear of it.
	local feet = worldPosition(level.position, GRASS_TOP + 0.6) - Vector3.new(0, 0, 7)
	local pivot = CFrame.new(feet) * CFrame.Angles(0, math.rad(180), 0)
	local template = DragonModels.Get(boss.species, "Adult")
	if template then
		local rig = DragonRig.new(template)
		rig:Apply(pivot, rig:Pose(os.clock(), 0, 0))
		local holder = Instance.new("Model")
		rig.model.Parent = holder
		holder.WorldPivot = CFrame.new(feet)
		holder:ScaleTo(MAP_BOSS_SCALE)
		rig.model.Parent = folder
		holder:Destroy()
	else
		local def = DragonDefs[boss.species]
		local size = (def and def.StageSizes.Adult or Vector3.new(6, 6, 8)) * MAP_BOSS_SCALE
		local diameter = math.min(size.X, size.Y, size.Z)
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * diameter
		ball.Color = boss.color or LOCKED_COLOR
		ball.Material = Enum.Material.SmoothPlastic
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		ball.CFrame = CFrame.new(feet + Vector3.new(0, diameter / 2, 0))
		ball.Parent = folder
	end
end

local function buildStage()
	destroyStage()
	local folder = Instance.new("Folder")
	folder.Name = "PveMapStage"
	stage = { folder = folder, connections = {}, markers = {} }

	local regions = (status and status.regions) or PveMap.Regions
	local levels = (status and status.levels) or {}

	-- Sea, then each island: a sand shelf with a grass cap on top.
	disc(folder, STAGE_ORIGIN, 1400, 1200, 4, 0, SEA_COLOR)
	local rng = Random.new(1704)
	for _, region in ipairs(regions) do
		local center = worldPosition(region.Center, 0)
		disc(folder, center, region.Size.x + 34, region.Size.z + 34, 1.2, 0.6, SHALLOW_COLOR)
		disc(folder, center, region.Size.x + 14, region.Size.z + 14, 3, 1.8, SAND_COLOR)
		disc(folder, center, region.Size.x, region.Size.z, 3.4, GRASS_TOP, GRASS_COLOR)
	end

	-- Trail first, so the markers sit on top of it.
	for index = 1, #levels - 1 do
		layPath(folder, levels[index].position, levels[index + 1].position)
	end

	for _, level in ipairs(levels) do
		local center = worldPosition(level.position, 0)
		local size = level.boss and 17 or 11
		disc(folder, center, size, size, 1, GRASS_TOP + 0.3, SAND_COLOR)
		disc(folder, center, size - 3, size - 3, 1, GRASS_TOP + 0.45, STONE_COLOR)
		if level.boss then
			placeBoss(folder, level)
		end
	end

	for _, region in ipairs(regions) do
		local markers = {}
		for _, level in ipairs(levels) do
			if level.region == region.Id then
				table.insert(markers, Vector2.new(level.position.x, level.position.z))
			end
		end
		scatterScenery(folder, region, markers, rng)
	end

	folder.Parent = Workspace
	local aim = STAGE_ORIGIN + CAMERA_LOOK
	CameraController.Hold(CFrame.lookAt(aim + CAMERA_OFFSET, aim), CAMERA_FOV)

	table.insert(stage.connections, Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		renderNodes()
	end))
	table.insert(stage.connections, RunService.RenderStepped:Connect(function()
		renderNodes()
	end))
end

------------------------------------------------------------------ small widgets

local function classChip(parent, className, color, props)
	local chip = UIKit.new("Frame", {
		Name = "ClassChip",
		BackgroundColor3 = color,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromOffset(96, 24),
		Parent = parent,
	})
	for key, value in pairs(props or {}) do
		chip[key] = value
	end
	UIKit.corner(chip, UDim.new(1, 0))
	UIKit.text(chip, { Name = "Name", Text = className, TextSize = 16, TextColor3 = WHITE })
	return chip
end

-- Round portrait for a dragon or an enemy: its own head, which is what tells
-- two dragons of the same element apart (UIKit.dragonHead falls back to the
-- element badge for a species that has no model yet).
local function dragonBadge(parent, species, color, size, props)
	local holder = UIKit.dragonHead(parent, species, size, color, props)
	UIKit.stroke(holder, UITheme.Colors.SurfaceStroke, 2)
	return holder
end

------------------------------------------------------------------ bottom sheet

local function sendTeam(team)
	if callbacks.onTeam then
		callbacks.onTeam(team)
	end
end

local function setSlot(slotIndex, dragonId)
	local team = table.clone(status and status.team or {})
	-- Already in another slot: the two swap rather than the dragon fighting twice.
	for index, id in ipairs(team) do
		if id == dragonId and index ~= slotIndex then
			team[index] = team[slotIndex]
		end
	end
	team[slotIndex] = dragonId
	local cleaned = {}
	for _, id in ipairs(team) do
		if id then
			table.insert(cleaned, id)
		end
	end
	sendTeam(cleaned)
end

local function removeSlot(slotIndex)
	local team = {}
	for index, id in ipairs(status and status.team or {}) do
		if index ~= slotIndex then
			table.insert(team, id)
		end
	end
	sendTeam(team)
end

local renderPicker

-- The bar along the bottom, in the same spirit as the island's option bar:
-- the stage on the left, the team that goes in, the reward and Fight. The
-- whole screen above it stays map.
local function createPanel()
	local colors = UITheme.Colors
	panelParts = { enemyCards = {} }

	panel = UIKit.new("Frame", {
		Name = "Sheet",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(1200, 200),
		BackgroundColor3 = colors.Surface,
		BackgroundTransparency = 0.06,
		Visible = false,
		ZIndex = 3, -- over the stage buttons (created later, so drawn later)
		Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = panel }))
	UIKit.corner(panel, UDim.new(0, 20))
	UIKit.stroke(panel, colors.SurfaceStroke, 2)
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 18),
		Parent = panel,
	})

	panelParts.title = UIKit.text(panel, {
		Name = "Title",
		Size = UDim2.fromOffset(560, 28),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	panelParts.subtitle = UIKit.text(panel, {
		Name = "Subtitle",
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.fromOffset(560, 20),
		TextSize = 17,
		TextColor3 = colors.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	panelParts.note = UIKit.text(panel, {
		Name = "Note",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(560, 46),
		TextSize = 17,
		TextColor3 = colors.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = true,
	})

	-- Who is waiting there.
	local enemies = UIKit.new("Frame", {
		Name = "Enemies",
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.fromOffset(446, 122),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = enemies,
	})
	for index = 1, 3 do
		local card = UIKit.new("Frame", {
			Name = "Enemy" .. index,
			Size = UDim2.fromOffset(142, 122),
			BackgroundColor3 = colors.SurfaceRaised,
			LayoutOrder = index,
			Visible = false,
			Parent = enemies,
		})
		UIKit.corner(card, UDim.new(0, 14))
		local entry = { card = card, stroke = UIKit.stroke(card, colors.SurfaceStroke, 2) }
		entry.badgeHolder = UIKit.new("Frame", {
			Name = "BadgeHolder",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 8),
			Size = UDim2.fromOffset(46, 46),
			BackgroundTransparency = 1,
			Parent = card,
		})
		entry.name = UIKit.text(card, {
			Name = "Name",
			Position = UDim2.fromOffset(6, 56),
			Size = UDim2.new(1, -12, 0, 20),
			TextSize = 17,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		entry.detail = UIKit.text(card, {
			Name = "Detail",
			Position = UDim2.fromOffset(6, 74),
			Size = UDim2.new(1, -12, 0, 18),
			TextSize = 14,
			TextColor3 = colors.TextMuted,
		})
		entry.chipHolder = UIKit.new("Frame", {
			Name = "ChipHolder",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.fromOffset(104, 22),
			BackgroundTransparency = 1,
			Parent = card,
		})
		table.insert(panelParts.enemyCards, entry)
	end

	-- The team that goes in (createTeamRow fills it).
	local team = UIKit.new("Frame", {
		Name = "Team",
		Position = UDim2.fromOffset(466, 50),
		Size = UDim2.fromOffset(330, 122),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	UIKit.text(team, {
		Name = "Title",
		Size = UDim2.fromOffset(330, 18),
		Text = "Your team",
		TextSize = 15,
		TextColor3 = colors.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	panelParts.teamHolder = UIKit.new("Frame", {
		Name = "Slots",
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.fromOffset(330, 100),
		BackgroundTransparency = 1,
		Parent = team,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = panelParts.teamHolder,
	})

	-- What it pays, and the button.
	local reward = UIKit.new("Frame", {
		Name = "Reward",
		Position = UDim2.fromOffset(816, 50),
		Size = UDim2.fromOffset(348, 122),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	panelParts.rewardsTitle = UIKit.text(reward, {
		Name = "RewardTitle",
		Size = UDim2.fromOffset(348, 18),
		Text = "Reward",
		TextSize = 15,
		TextColor3 = colors.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local pills = UIKit.new("Frame", {
		Name = "Pills",
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.fromOffset(348, 38),
		BackgroundTransparency = 1,
		Parent = reward,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = pills,
	})
	local function rewardPill(iconKey, width, layoutOrder, textColor)
		local pill = UIKit.new("Frame", {
			Name = iconKey .. "Reward",
			BackgroundColor3 = colors.SurfaceRaised,
			Size = UDim2.fromOffset(width, 38),
			LayoutOrder = layoutOrder,
			Parent = pills,
		})
		UIKit.corner(pill, UDim.new(1, 0))
		if iconKey ~= "Xp" then
			UIKit.icon(pill, iconKey, 36, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 14, 0.5, 0), ZIndex = 2 })
			return UIKit.text(pill, {
				Name = "Amount",
				Position = UDim2.fromOffset(30, 0),
				Size = UDim2.new(1, -38, 1, 0),
				TextSize = 19,
			})
		end
		return UIKit.text(pill, { Name = "Amount", Size = UDim2.fromScale(1, 1), TextSize = 19, TextColor3 = textColor })
	end
	panelParts.coins = rewardPill("Coin", 112, 1)
	panelParts.food = rewardPill("Food", 96, 2)
	panelParts.xp = rewardPill("Xp", 126, 3, colors.XpFill)

	local fightHolder = UIKit.new("Frame", {
		Name = "FightHolder",
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.fromOffset(348, 54),
		BackgroundTransparency = 1,
		Parent = reward,
	})
	panelParts.fight = UIKit.button(fightHolder, { Name = "FightButton", Variant = "Confirm", Text = "Fight", TextSize = 26 })
	panelParts.fight.OnActivated(function()
		if selectedId and callbacks.onFight then
			callbacks.onFight(selectedId)
		end
	end)
end

local function renderPanel()
	if not panel then
		return
	end
	local level = selectedId and levelById(selectedId)
	panel.Visible = level ~= nil
	if not level then
		return
	end

	panelParts.title.Text = string.format("%d. %s", level.id, level.name)
	local pieces = { level.difficulty }
	if level.recommendedLevel then
		table.insert(pieces, string.format("dragons around level %d", level.recommendedLevel))
	end
	if level.boss then
		table.insert(pieces, "BOSS")
	end
	panelParts.subtitle.Text = table.concat(pieces, "  -  ")

	for index, entry in ipairs(panelParts.enemyCards) do
		local enemy = level.enemies[index]
		entry.card.Visible = enemy ~= nil
		if enemy then
			entry.badgeHolder:ClearAllChildren()
			dragonBadge(entry.badgeHolder, enemy.species, enemy.color, 46)
			entry.name.Text = enemy.name
			entry.name.TextColor3 = enemy.boss and CLEARED_COLOR or UITheme.Colors.Text
			entry.stroke.Color = enemy.boss and CLEARED_COLOR or UITheme.Colors.SurfaceStroke
			entry.detail.Text = string.format("Lv %d  -  %d ATK  -  %d HP", enemy.level, math.round(enemy.stats.Attack), math.round(enemy.stats.Health))
			entry.chipHolder:ClearAllChildren()
			classChip(entry.chipHolder, enemy.className, DragonClasses.Get(enemy.class).Color, { Size = UDim2.fromScale(1, 1) })
		end
	end

	panelParts.coins.Text = UIKit.formatNumber(level.rewards.Coins)
	panelParts.food.Text = UIKit.formatNumber(level.rewards.Food)
	panelParts.xp.Text = "+" .. UIKit.formatNumber(level.rewards.Xp) .. " XP"
	panelParts.rewardsTitle.Text = level.cleared and "Reward (cleared, so it pays less)" or "Reward"

	local teamCount = #(status and status.team or {})
	if not level.unlocked then
		panelParts.note.Text = "Clear the stage before it first."
		panelParts.fight.SetEnabled(false)
	elseif teamCount == 0 then
		panelParts.note.Text = "Pick at least one Adult dragon."
		panelParts.fight.SetEnabled(false)
	else
		panelParts.note.Text = ""
		panelParts.fight.SetEnabled(true)
	end
end

------------------------------------------------------------------ the team slots

local function createTeamRow()
	local colors = UITheme.Colors
	for index = 1, 3 do
		local slot = {}
		slot.button = UIKit.new("TextButton", {
			Name = "Slot" .. index,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = colors.SurfaceRaised,
			Size = UDim2.fromOffset(100, 100),
			LayoutOrder = index,
			Parent = panelParts.teamHolder,
		})
		UIKit.corner(slot.button, UDim.new(0, 14))
		UIKit.stroke(slot.button, colors.SurfaceStroke, 2)
		UIKit.pressable(slot.button)
		slot.badgeHolder = UIKit.new("Frame", {
			Name = "BadgeHolder",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(42, 42),
			BackgroundTransparency = 1,
			Parent = slot.button,
		})
		slot.name = UIKit.text(slot.button, {
			Name = "Name",
			Position = UDim2.fromOffset(4, 50),
			Size = UDim2.new(1, -8, 0, 20),
			TextSize = 15,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		slot.detail = UIKit.text(slot.button, {
			Name = "Detail",
			Position = UDim2.fromOffset(4, 70),
			Size = UDim2.new(1, -8, 0, 20),
			TextSize = 14,
			TextColor3 = colors.TextMuted,
		})
		slot.empty = UIKit.text(slot.button, {
			Name = "Empty",
			Size = UDim2.fromScale(1, 1),
			Text = "+",
			TextSize = 42,
			TextColor3 = colors.TextMuted,
		})
		slot.button.Activated:Connect(function()
			pickingSlot = index
			renderPicker()
		end)
		table.insert(teamSlots, slot)
	end
end

local function renderTeam()
	local team = status and status.team or {}
	for index, slot in ipairs(teamSlots) do
		local dragon = rosterById(team[index])
		slot.badgeHolder:ClearAllChildren()
		slot.empty.Visible = dragon == nil
		slot.name.Visible = dragon ~= nil
		slot.detail.Visible = dragon ~= nil
		if dragon then
			dragonBadge(slot.badgeHolder, dragon.species, dragon.color, 42)
			slot.name.Text = dragon.name
			slot.detail.Text = string.format("Lv %d  -  %s", dragon.level, dragon.className)
			slot.detail.TextColor3 = DragonClasses.Get(dragon.class).Color
		end
	end
end

------------------------------------------------------------------ dragon picker

local function createPicker()
	local colors = UITheme.Colors
	picker = UIKit.new("Frame", {
		Name = "Picker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 460),
		BackgroundColor3 = colors.Surface,
		Visible = false,
		ZIndex = 10,
		Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = picker }))
	UIKit.corner(picker, UDim.new(0, 18))
	UIKit.stroke(picker, colors.SurfaceStroke, 2)
	UIKit.text(picker, {
		Name = "Title",
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 30),
		Text = "Send which dragon?",
		TextSize = 24,
	})
	local list = UIKit.new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(14, 52),
		Size = UDim2.new(1, -28, 1, -118),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = picker,
	})
	UIKit.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = list })
	pickerRows = { list = list, rows = {} }

	local buttons = UIKit.new("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -28, 0, 48),
		BackgroundTransparency = 1,
		Parent = picker,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = buttons,
	})
	local removeHolder = UIKit.new("Frame", { Name = "RemoveHolder", Size = UDim2.fromOffset(170, 48), BackgroundTransparency = 1, LayoutOrder = 1, Parent = buttons })
	local remove = UIKit.button(removeHolder, { Name = "Remove", Variant = "Danger", Text = "Leave empty", TextSize = 20 })
	remove.OnActivated(function()
		if pickingSlot then
			removeSlot(pickingSlot)
		end
		pickingSlot = nil
		renderPicker()
	end)
	local cancelHolder = UIKit.new("Frame", { Name = "CancelHolder", Size = UDim2.fromOffset(140, 48), BackgroundTransparency = 1, LayoutOrder = 2, Parent = buttons })
	local cancel = UIKit.button(cancelHolder, { Name = "Cancel", Variant = "Info", Text = "Cancel", TextSize = 20 })
	cancel.OnActivated(function()
		pickingSlot = nil
		renderPicker()
	end)
end

function renderPicker()
	if not picker then
		return
	end
	picker.Visible = pickingSlot ~= nil
	if not pickingSlot then
		return
	end
	for _, row in ipairs(pickerRows.rows) do
		row:Destroy()
	end
	table.clear(pickerRows.rows)

	local colors = UITheme.Colors
	local team = status and status.team or {}
	for index, dragon in ipairs(status and status.roster or {}) do
		local row = UIKit.new("TextButton", {
			Name = "Dragon" .. dragon.id,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = colors.SurfaceRaised,
			Size = UDim2.new(1, 0, 0, 62),
			LayoutOrder = index,
			Parent = pickerRows.list,
		})
		UIKit.corner(row, UDim.new(0, 12))
		UIKit.pressable(row)
		local holder = UIKit.new("Frame", {
			Name = "BadgeHolder",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(46, 46),
			BackgroundTransparency = 1,
			Parent = row,
		})
		dragonBadge(holder, dragon.species, dragon.color, 46)
		UIKit.text(row, {
			Name = "Name",
			Position = UDim2.fromOffset(64, 8),
			Size = UDim2.new(1, -74, 0, 24),
			Text = dragon.name,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		UIKit.text(row, {
			Name = "Detail",
			Position = UDim2.fromOffset(64, 32),
			Size = UDim2.new(1, -74, 0, 22),
			Text = string.format("Lv %d  -  %s  -  %d ATK  -  %d HP", dragon.level, dragon.className,
				math.round(dragon.stats.Attack), math.round(dragon.stats.Health)),
			TextSize = 15,
			TextColor3 = colors.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		if table.find(team, dragon.id) then
			UIKit.text(row, {
				Name = "InTeam",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(90, 24),
				Text = "in team",
				TextSize = 16,
				TextColor3 = colors.Accent,
			})
		end
		row.Activated:Connect(function()
			local slotIndex = pickingSlot
			pickingSlot = nil
			renderPicker()
			if slotIndex then
				setSlot(slotIndex, dragon.id)
			end
		end)
		table.insert(pickerRows.rows, row)
	end
end

------------------------------------------------------------------ result card

local function createResultCard()
	local colors = UITheme.Colors
	resultParts = {}
	resultCard = UIKit.new("Frame", {
		Name = "Result",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 300),
		BackgroundColor3 = colors.Surface,
		Visible = false,
		ZIndex = 10,
		Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = resultCard }))
	UIKit.corner(resultCard, UDim.new(0, 18))
	UIKit.stroke(resultCard, colors.SurfaceStroke, 2)
	resultParts.title = UIKit.text(resultCard, {
		Name = "Title",
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 34,
	})
	resultParts.subtitle = UIKit.text(resultCard, {
		Name = "Subtitle",
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 0, 26),
		TextSize = 19,
		TextColor3 = colors.TextMuted,
	})
	resultParts.rewards = UIKit.text(resultCard, {
		Name = "Rewards",
		Position = UDim2.fromOffset(0, 118),
		Size = UDim2.new(1, 0, 0, 70),
		TextSize = 22,
		TextColor3 = colors.Accent,
	})
	local holder = UIKit.new("Frame", {
		Name = "ButtonHolder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(200, 52),
		BackgroundTransparency = 1,
		Parent = resultCard,
	})
	resultParts.close = UIKit.button(holder, { Name = "Continue", Variant = "Confirm", Text = "Continue", TextSize = 24 })
	resultParts.close.OnActivated(function()
		resultCard.Visible = false
	end)
end

function PveMapScreen.ShowResult(result)
	if not resultCard then
		return
	end
	resultParts.title.Text = result.won and "Victory" or "Defeat"
	resultParts.title.TextColor3 = result.won and CLEARED_COLOR or OPEN_COLOR
	resultParts.subtitle.Text = string.format("%s  -  %d rounds", result.name or "", result.rounds or 0)
	if result.won then
		local rewards = result.rewards or {}
		resultParts.rewards.Text = string.format("+%s Coins\n+%s Food\n+%s XP",
			UIKit.formatNumber(rewards.Coins or 0), UIKit.formatNumber(rewards.Food or 0), UIKit.formatNumber(rewards.Xp or 0))
	else
		resultParts.rewards.Text = "Your dragons were beaten.\nFeed them a level or change the team."
	end
	resultCard.Visible = true
end

------------------------------------------------------------------ stage markers

local function createNodeButtons()
	for _, entry in pairs(nodeButtons) do
		local index = table.find(scales, entry.screenScale)
		if index then
			table.remove(scales, index)
		end
		entry.holder:Destroy()
	end
	table.clear(nodeButtons)

	local colors = UITheme.Colors
	for _, level in ipairs(status and status.levels or {}) do
		local size = level.boss and 74 or 58
		-- The holder follows the marker and shrinks with the screen; the button
		-- inside keeps its own press squash (one UIScale per object).
		local holder = UIKit.new("Frame", {
			Name = "Stage" .. level.id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = root,
		})
		-- bindScreenScale only reaches it from the next resize on, so it starts
		-- at the current scale.
		local screenScale = UIKit.new("UIScale", { Scale = scales[1] and scales[1].Scale or 1, Parent = holder })
		table.insert(scales, screenScale)
		local button = UIKit.new("TextButton", {
			Name = "Button",
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = colors.Surface,
			Parent = holder,
		})
		UIKit.corner(button, UDim.new(1, 0))
		local stroke = UIKit.stroke(button, WHITE, 3)
		UIKit.pressable(button)
		local label = UIKit.text(button, {
			Name = "Number",
			Size = UDim2.fromScale(1, 1),
			Text = tostring(level.id),
			TextSize = level.boss and 34 or 28,
			TextColor3 = WHITE,
			Outline = colors.TextShadow,
			OutlineThickness = 2,
		})
		button.Activated:Connect(function()
			selectedId = level.id
			renderNodeLooks()
			renderPanel()
		end)
		nodeButtons[level.id] = { holder = holder, button = button, label = label, stroke = stroke, screenScale = screenScale }
	end
end

function renderNodeLooks()
	for _, level in ipairs(status and status.levels or {}) do
		local entry = nodeButtons[level.id]
		if entry then
			local color = LOCKED_COLOR
			if level.cleared then
				color = CLEARED_COLOR
			elseif level.unlocked then
				color = OPEN_COLOR
			end
			entry.button.BackgroundColor3 = color
			entry.stroke.Color = selectedId == level.id and WHITE or Color3.new(0, 0, 0)
			entry.stroke.Transparency = selectedId == level.id and 0 or 0.45
			entry.label.Text = level.unlocked and tostring(level.id) or "?"
			entry.label.TextTransparency = level.unlocked and 0 or 0.3
		end
	end
end

-- Every frame: each button sits over its marker in the world.
function renderNodes()
	if not stage or not isOpen then
		return
	end
	local camera = Workspace.CurrentCamera
	for _, level in ipairs(status and status.levels or {}) do
		local entry = nodeButtons[level.id]
		if entry then
			local point, onScreen = camera:WorldToViewportPoint(worldPosition(level.position, GRASS_TOP + 1.5))
			entry.holder.Visible = onScreen
			entry.holder.Position = UDim2.fromOffset(point.X, point.Y)
		end
	end
end

------------------------------------------------------------------ screen

local function createScreen()
	local colors = UITheme.Colors
	gui = UIKit.new("ScreenGui", {
		Name = "PveMapGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	root = UIKit.new("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})

	local header = UIKit.new("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(28, 22),
		Size = UDim2.fromOffset(360, 66),
		BackgroundTransparency = 1,
		Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = header }))
	UIKit.text(header, {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 40),
		Text = "Adventure",
		TextSize = 36,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = colors.TextLight,
		Outline = colors.TextShadow,
		OutlineThickness = 2,
	})
	progressLabel = UIKit.text(header, {
		Name = "Progress",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = colors.Accent,
		Outline = colors.TextShadow,
		OutlineThickness = 1.5,
	})

	local backHolder = UIKit.new("Frame", {
		Name = "BackHolder",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -28, 0, 22),
		Size = UDim2.fromOffset(140, 52),
		BackgroundTransparency = 1,
		Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = backHolder }))
	local back = UIKit.button(backHolder, { Name = "Back", Variant = "Info", Text = "Back", TextSize = 22 })
	back.OnActivated(function()
		PveMapScreen.Close()
	end)

	createPanel()
	createTeamRow()
	createPicker()
	createResultCard()
	UIKit.bindScreenScale(gui, scales, 1280, 720)
end

-- callbacks: onFight(levelId), onTeam(dragonIds), onClose()
function PveMapScreen.Init(handlers)
	callbacks = handlers or {}
	if not gui then
		createScreen()
	end
end

function PveMapScreen.IsOpen()
	return isOpen
end

function PveMapScreen.SetStatus(newStatus)
	status = newStatus
	if not gui then
		return
	end
	if not next(nodeButtons) then
		createNodeButtons()
	end
	if isOpen and not stage then
		buildStage()
	end
	if selectedId == nil then
		-- Opens on the next stage to clear.
		selectedId = math.min((status.cleared or 0) + 1, status.count or 1)
	end
	progressLabel.Text = string.format("%d of %d stages cleared", status.cleared or 0, status.count or 0)
	renderNodeLooks()
	renderNodes()
	renderPanel()
	renderTeam()
	if pickingSlot then
		renderPicker()
	end
end

function PveMapScreen.Open()
	if isOpen then
		return
	end
	isOpen = true
	gui.Enabled = true
	hideLowerGuis(true)
	buildStage()
	renderNodeLooks()
	renderNodes()
	renderPanel()
	renderTeam()
end

function PveMapScreen.Close()
	if not isOpen then
		return
	end
	isOpen = false
	pickingSlot = nil
	if picker then
		picker.Visible = false
	end
	if resultCard then
		resultCard.Visible = false
	end
	destroyStage()
	gui.Enabled = false
	hideLowerGuis(false)
	if callbacks.onClose then
		callbacks.onClose()
	end
end

return PveMapScreen
