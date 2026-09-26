-- Full-screen Nursery view (Dragon Mania Legends breeding screen), drawn over
-- the Nursery itself: the world camera is lent (CameraController.Hold) to a
-- bigger copy of the building standing far from the islands, and the two
-- chosen dragons idle in front of its tree, at its breeding spots (Parent1 /
-- Parent2). An empty spot shows the list of adult dragons to pick from (only
-- one list at a time, left spot first); a chosen dragon has its name, level
-- and a Change button under its feet. The heart between them starts the pairing, shows its countdown, then
-- Collect once the egg is ready; Speed up under it skips the rest of a
-- pairing for Gems. "Eggs possibles" under the title lists the eggs the pair
-- can give (DragonRules.BreedingOutcomes): hovering one (or tapping it) shows
-- its dragon's name, chance and breeding / hatching times. Picks are
-- client-side until Breed.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UITheme = require(script.Parent.UITheme)
local UIKit = require(script.Parent.UIKit)
local Toast = require(script.Parent.Toast)
local DragonViewport = require(script.Parent.DragonViewport)
local DragonRig = require(script.Parent.DragonRig)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)

local Config = ReplicatedStorage.Wyrmhaven.Config
local DragonDefs = require(Config.DragonDefs)
local DragonModels = require(Config.DragonModels)
local DragonRules = require(Config.DragonRules)
local GemSpeedUp = require(Config.GemSpeedUp)

local buildingTemplates = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets"):FindFirstChild("Buildings")
local TEMPLATE_NAMES = { "Nursery", "NurseryMirror" } -- by nursery id, as in BreedingService

local BreedingScreen = {}

local MARGIN = 24
local ROW_HEIGHT = 76
local HEART_SIZE = 170
local HEART_COLOR = Color3.fromRGB(206, 86, 120)
local SIDES = { "A", "B" }
local EGG_SIZE = 64
local TOOLTIP_WIDTH = 260

-- The stage: far behind the islands like DragonViewport's (at another spot,
-- so the two never meet), the building drawn bigger than on the island so its
-- tree fills the background.
local STAGE_ORIGIN = Vector3.new(0, 0, -24000)
local NURSERY_SCALE = 2.6
local CAMERA_FOV = 40
-- From the building's base center: the lower half of the heart crown, the
-- trunk and the whole lawn, the dragons' feet about 4/5 down the screen.
local CAMERA_OFFSET = Vector3.new(0, 19, 46)
local CAMERA_LOOK = Vector3.new(0, 9.5, -6)
local SPOT_SPREAD = 1.15 -- the two breeding spots, a bit further apart than on the island
local FACE_OTHER = 0.4 -- how much each dragon turns from the camera toward the other one
local STRIPPED_CLASSES = { "LuaSourceContainer", "Sound", "Highlight", "LayerCollector" }

local WHITE = Color3.new(1, 1, 1)

local gui, root
local slots = {} -- [side] = spot widgets
local heartButton, heartText, heartIcon, heartColor, caption, speedHolder, speedButton
local gems = 0
local speedUpCost = 0
local eggsPanel, eggsTitle, eggsRow, eggsSignature
local callbacks
local status = nil
local selected = {} -- [side] = dragonId picked while no pairing runs
local isOpen = false
local hiddenGuis = {} -- the island's interfaces hidden while the screen is open
local stage = nil -- the building and dragons in the world, see buildStage
local render

local function otherSide(side)
	return side == "A" and "B" or "A"
end

local function findAvailable(dragonId)
	for _, card in ipairs(status.availableDragons or {}) do
		if card.id == dragonId then
			return card
		end
	end
	return nil
end

-- Dragon shown in a spot: the running pairing's parent, or the player's pick.
local function slotCard(side)
	local pairing = status and status.pairing
	if pairing then
		return side == "A" and pairing.dragonA or pairing.dragonB
	end
	return selected[side] and findAvailable(selected[side])
end

-- The screen is see-through (the world camera draws the Nursery), so the
-- interfaces under it (HUD, option bar...) are switched off while it's open.
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

------------------------------------------------------------------ stage

local function yawToward(from, to)
	local offset = to - from
	return math.atan2(-offset.X, -offset.Z)
end

local function prepareClone(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		for _, className in ipairs(STRIPPED_CLASSES) do
			if descendant:IsA(className) then
				descendant:Destroy()
				break
			end
		end
	end
	for _, part in ipairs(instance:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
		instance.CanTouch = false
	end
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

-- A copy of the Nursery (its model for that nursery id) at STAGE_ORIGIN,
-- scaled up about its base, and the camera lent to it.
local function buildStage(nurseryId)
	destroyStage()
	local folder = Instance.new("Folder")
	folder.Name = "NurseryStage"
	stage = { folder = folder, nurseryId = nurseryId, dragons = {}, connections = {} }

	local template = buildingTemplates and buildingTemplates:FindFirstChild(TEMPLATE_NAMES[nurseryId] or TEMPLATE_NAMES[1])
	if template then
		local building = template:Clone()
		prepareClone(building)
		local holder = Instance.new("Model")
		holder.WorldPivot = CFrame.new(building.Position - Vector3.new(0, building.Size.Y / 2, 0))
		building.Parent = holder
		holder:ScaleTo(NURSERY_SCALE)
		holder:PivotTo(CFrame.new(STAGE_ORIGIN))
		building.Parent = folder
		holder:Destroy()
		stage.building = building
		local love = building:FindFirstChild("Love")
		stage.love = love and love:FindFirstChildOfClass("ParticleEmitter")
	end
	folder.Parent = Workspace

	stage.cameraPosition = STAGE_ORIGIN + CAMERA_OFFSET
	CameraController.Hold(CFrame.lookAt(stage.cameraPosition, STAGE_ORIGIN + CAMERA_LOOK), CAMERA_FOV)

	-- The breeding spots, the left one for spot A.
	local spotA = stage.building and stage.building:FindFirstChild("Parent1")
	local spotB = stage.building and stage.building:FindFirstChild("Parent2")
	local a = spotA and spotA.WorldPosition or STAGE_ORIGIN + Vector3.new(-7, 0, 7)
	local b = spotB and spotB.WorldPosition or STAGE_ORIGIN + Vector3.new(7, 0, 7)
	if a.X > b.X then
		a, b = b, a
	end
	local middle = (a + b) / 2
	stage.middle = middle
	stage.spots = { A = middle + (a - middle) * SPOT_SPREAD, B = middle + (b - middle) * SPOT_SPREAD }

	-- The dragons idle.
	table.insert(stage.connections, RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for _, entry in pairs(stage.dragons) do
			if entry.rig then
				entry.rig:Apply(entry.pivot, entry.rig:Pose(now, 0, 0))
			end
		end
	end))
	-- A new window size moves the dragons on screen: their names follow.
	table.insert(stage.connections, Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		render()
	end))
end

-- Where a spot's dragon stands on screen (0..1 of the width and height).
local function spotOnScreen(side)
	local camera = Workspace.CurrentCamera
	local point = camera:WorldToViewportPoint(stage.spots[side])
	local viewport = camera.ViewportSize
	return Vector2.new(point.X / viewport.X, point.Y / viewport.Y)
end

-- Shows `card`'s dragon (an Adult) under that spot, or nothing.
local function setStageDragon(side, card)
	if not stage then
		return
	end
	local current = stage.dragons[side]
	if current and card and current.id == card.id then
		return
	end
	if current then
		current.model:Destroy()
		stage.dragons[side] = nil
	end
	if not card then
		return
	end

	local feet = stage.spots[side]
	local target = stage.cameraPosition:Lerp(stage.middle, FACE_OTHER)
	local pivot = CFrame.new(feet) * CFrame.Angles(0, yawToward(feet, target), 0)
	local entry = { id = card.id, pivot = pivot }
	local template = DragonModels.Get(card.element, "Adult")
	if template then
		entry.rig = DragonRig.new(template)
		entry.model = entry.rig.model
		entry.rig:Apply(pivot, entry.rig:Pose(os.clock(), 0, 0))
	else
		-- No model yet: the placeholder ball, as on the island.
		local def = DragonDefs[card.element]
		local size = def and def.StageSizes.Adult or Vector3.new(5.5, 5.5, 7.5)
		local diameter = math.min(size.X, size.Y, size.Z)
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * diameter
		ball.Color = def and def.StageColors.Adult or UITheme.Colors.TextMuted
		ball.Material = Enum.Material.SmoothPlastic
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		ball.CFrame = pivot + Vector3.new(0, diameter / 2, 0)
		entry.model = ball
	end
	entry.model.Parent = stage.folder
	stage.dragons[side] = entry
end

------------------------------------------------------------------ UI

local function createSlot(side, scales)
	local colors = UITheme.Colors
	local slot = { rowViews = {} }

	slot.frame = UIKit.new("Frame", {
		Name = "Spot" .. side,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(side == "A" and 0.22 or 0.78, 0.54),
		Size = UDim2.fromScale(0.4, 0.84),
		BackgroundTransparency = 1,
		Parent = root,
	})

	-- Name, level and Change under a chosen dragon's feet (it stands in the
	-- world: renderSlot follows it on screen).
	slot.info = UIKit.new("Frame", {
		Name = "Info" .. side,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(side == "A" and 0.34 or 0.66, 0.8),
		Size = UDim2.fromOffset(300, 124),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = slot.info }))
	slot.nameLabel = UIKit.text(slot.info, {
		Name = "DragonName",
		Size = UDim2.new(1, 0, 0, 34),
		TextSize = 30,
		TextColor3 = WHITE,
		Outline = colors.TextShadow,
		OutlineThickness = 1.5,
	})
	slot.levelLabel = UIKit.text(slot.info, {
		Name = "Level",
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 20,
		TextColor3 = colors.Accent,
		Outline = colors.TextShadow,
		OutlineThickness = 1.5,
	})
	slot.changeHolder = UIKit.new("Frame", {
		Name = "ChangeHolder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(200, 54),
		BackgroundTransparency = 1,
		Parent = slot.info,
	})
	local changeButton = UIKit.button(slot.changeHolder, { Name = "ChangeButton", Variant = "Info", Text = "Change", TextSize = 24 })
	changeButton.OnActivated(function()
		selected[side] = nil
		render()
	end)

	-- Dragon picker.
	slot.list = UIKit.new("Frame", {
		Name = "DragonList",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 480),
		BackgroundColor3 = colors.Surface,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = slot.frame,
	})
	UIKit.corner(slot.list, UDim.new(0, 18))
	UIKit.stroke(slot.list, colors.SurfaceStroke, 1.5)
	table.insert(scales, UIKit.new("UIScale", { Parent = slot.list }))
	UIKit.text(slot.list, {
		Name = "Header",
		Text = "Choose a dragon",
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -40, 0, 36),
		TextSize = 24,
		TextColor3 = colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	slot.listScroll = UIKit.new("ScrollingFrame", {
		Name = "Rows",
		Position = UDim2.fromOffset(12, 56),
		Size = UDim2.new(1, -24, 1, -68),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = colors.SurfaceStroke,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = slot.list,
	})
	UIKit.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = slot.listScroll })

	-- Second spot while the first one is still empty.
	slot.placeholder = UIKit.new("Frame", {
		Name = "Placeholder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(240, 220),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = slot.frame,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = slot.placeholder }))
	local disc = UIKit.new("Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = colors.Surface,
		BackgroundTransparency = 0.3,
		Parent = slot.placeholder,
	})
	UIKit.corner(disc, UDim.new(1, 0))
	UIKit.stroke(disc, colors.SurfaceStroke, 1.5)
	UIKit.text(disc, { Name = "Mark", Text = "?", TextSize = 64, TextColor3 = colors.TextMuted })
	UIKit.text(slot.placeholder, {
		Name = "Hint",
		Text = "Choose the first dragon first",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 50),
		TextSize = 20,
		TextWrapped = true,
		TextColor3 = WHITE,
		Outline = colors.TextShadow,
		OutlineThickness = 1.5,
	})

	return slot
end

local function clearRows(slot)
	for _, view in ipairs(slot.rowViews) do
		view.Destroy()
	end
	slot.rowViews = {}
	for _, child in ipairs(slot.listScroll:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	slot.listSignature = nil
end

-- Rows are only rebuilt when the list itself changes, so the 3D portraits
-- don't flicker on every server push.
local function rebuildList(side)
	local slot = slots[side]
	local excluded = selected[otherSide(side)]
	local cards = {}
	local signatureParts = { tostring(excluded) }
	for _, card in ipairs(status.availableDragons or {}) do
		if card.id ~= excluded then
			table.insert(cards, card)
			table.insert(signatureParts, string.format("%d:%s:%s", card.id, card.name, tostring(card.level)))
		end
	end
	local signature = table.concat(signatureParts, ",")
	if slot.listSignature == signature then
		return
	end
	clearRows(slot)
	slot.listSignature = signature

	local colors = UITheme.Colors
	if #cards == 0 then
		UIKit.text(slot.listScroll, {
			Name = "Empty",
			Text = "No adult dragon available",
			Size = UDim2.new(1, -8, 0, 60),
			TextSize = 20,
			TextWrapped = true,
			TextColor3 = colors.TextMuted,
		})
		return
	end

	for index, card in ipairs(cards) do
		local rowButton = UIKit.new("TextButton", {
			Name = "Dragon" .. card.id,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = colors.SurfaceRaised,
			Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
			LayoutOrder = index,
			Parent = slot.listScroll,
		})
		UIKit.corner(rowButton, UDim.new(0, 14))
		UIKit.stroke(rowButton, colors.SurfaceStroke, 1)
		UIKit.pressable(rowButton)

		local portrait = UIKit.new("Frame", {
			Name = "Portrait",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(58, 58),
			BackgroundColor3 = WHITE,
			Parent = rowButton,
		})
		UIKit.corner(portrait, UDim.new(1, 0))
		UIKit.gradient(portrait, colors.CircleInnerTop, colors.CircleInnerBottom)
		UIKit.stroke(portrait, colors.CircleEdge, 1)
		table.insert(slot.rowViews, DragonViewport.new(portrait, card.id, { Framing = "Head" }))

		UIKit.text(rowButton, {
			Name = "DragonName",
			Text = card.name,
			Position = UDim2.fromOffset(82, 12),
			Size = UDim2.new(1, -130, 0, 28),
			TextSize = 22,
			TextColor3 = colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		UIKit.text(rowButton, {
			Name = "Level",
			Text = string.format("Lv %s  \u{00B7}  %s", tostring(card.level or 1), DragonRules.RarityName(card.element)),
			Position = UDim2.fromOffset(82, 42),
			Size = UDim2.new(1, -130, 0, 22),
			TextSize = 18,
			TextColor3 = colors.Accent,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		UIKit.elementBadge(rowButton, card.element, 36, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
		})

		rowButton.Activated:Connect(function()
			selected[side] = card.id
			render()
		end)
	end
end

local function renderSlot(side)
	local slot = slots[side]
	local pairing = status.pairing
	local card = slotCard(side)
	local showList = not pairing and not card and (side == "A" or slotCard("A") ~= nil)

	slot.info.Visible = card ~= nil
	slot.changeHolder.Visible = not pairing
	slot.list.Visible = showList
	slot.placeholder.Visible = not card and not showList

	setStageDragon(side, card)
	if card then
		slot.nameLabel.Text = card.name
		slot.levelLabel.Text = string.format("Lv %s  ·  %s", tostring(card.level or 1), DragonRules.RarityName(card.element))
		if stage then
			local feet = spotOnScreen(side)
			slot.info.Position = UDim2.new(feet.X, 0, feet.Y, 8)
		end
	end

	if showList then
		rebuildList(side)
	end
end

-- One egg of the "Eggs possibles" row; hovering it (or tapping it) shows its
-- dragon's name and chance under it.
local function eggButton(outcome, index, showChance)
	local colors = UITheme.Colors
	local def = DragonDefs[outcome.id]
	local button = UIKit.new("TextButton", {
		Name = "Egg" .. index,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(EGG_SIZE, EGG_SIZE),
		LayoutOrder = index,
		Parent = eggsRow,
	})
	UIKit.icon(button, "Egg", EGG_SIZE, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	}, def and def.StageColors.Egg or colors.TextMuted)
	UIKit.elementBadge(button, outcome.id, 28, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 6, 1, 2),
		ZIndex = 2,
	})

	local tooltip = UIKit.new("Frame", {
		Name = "Tooltip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 10),
		Size = UDim2.fromOffset(TOOLTIP_WIDTH, showChance and 86 or 42),
		BackgroundColor3 = colors.Surface,
		Visible = false,
		ZIndex = 10,
		Parent = button,
	})
	UIKit.corner(tooltip, UDim.new(0, 12))
	UIKit.stroke(tooltip, colors.SurfaceStroke, 1.5)
	UIKit.text(tooltip, {
		Name = "DragonName",
		Text = def and def.DisplayName or outcome.id,
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 28),
		TextSize = 20,
		TextColor3 = colors.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 11,
	})
	if showChance then
		UIKit.text(tooltip, {
			Name = "Chance",
			Text = string.format("%s  \u{00B7}  %d %% chance", DragonRules.RarityName(outcome.id), math.round(outcome.chance * 100)),
			Position = UDim2.fromOffset(10, 34),
			Size = UDim2.new(1, -20, 0, 22),
			TextSize = 17,
			TextColor3 = colors.Accent,
			ZIndex = 11,
		})
		UIKit.text(tooltip, {
			Name = "Times",
			Text = string.format("Breeding %s  \u{00B7}  Hatching %s",
				UIKit.formatShortDuration(DragonRules.BreedingSeconds(outcome.id)), UIKit.formatShortDuration(DragonRules.HatchSeconds(outcome.id))),
			Position = UDim2.fromOffset(10, 58),
			Size = UDim2.new(1, -20, 0, 20),
			TextSize = 15,
			TextColor3 = colors.TextMuted,
			ZIndex = 11,
		})
	end

	button.MouseEnter:Connect(function()
		tooltip.Visible = true
	end)
	button.MouseLeave:Connect(function()
		tooltip.Visible = false
	end)
	button.Activated:Connect(function()
		tooltip.Visible = not tooltip.Visible
	end)
end

-- The eggs a pair can give: the chosen dragons' (or running pairing's)
-- outcomes with their chances; once the egg is ready, just that egg.
local function renderEggs()
	local pairing = status.pairing
	local outcomes, title, showChance = nil, "Possible eggs", true
	if pairing and pairing.ready and pairing.resultElement then
		outcomes, title, showChance = { { id = pairing.resultElement, chance = 1 } }, "Your egg", false
	else
		local cardA, cardB = slotCard("A"), slotCard("B")
		if cardA and cardB then
			outcomes = DragonRules.BreedingOutcomes(cardA.element, cardB.element)
		end
	end
	eggsPanel.Visible = outcomes ~= nil
	if not outcomes then
		eggsSignature = nil
		return
	end
	local parts = { title }
	for _, outcome in ipairs(outcomes) do
		table.insert(parts, outcome.id .. ":" .. outcome.chance)
	end
	local signature = table.concat(parts, ",")
	if signature == eggsSignature then
		return
	end
	eggsSignature = signature
	eggsTitle.Text = title
	for _, child in ipairs(eggsRow:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	for index, outcome in ipairs(outcomes) do
		eggButton(outcome, index, showChance)
	end
end

local function setHeartColor(color)
	if heartColor == color then
		return
	end
	heartColor = color
	if heartIcon then
		heartIcon:Destroy()
	end
	heartIcon = UIKit.icon(heartButton, "Heart", HEART_SIZE, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	}, color)
end

local function renderCenter()
	local colors = UITheme.Colors
	local pairing = status.pairing
	if pairing and pairing.ready then
		setHeartColor(UITheme.Buttons.Confirm.Face)
		heartText.Text = "Collect"
		caption.Text = "The egg is ready"
	elseif pairing then
		setHeartColor(HEART_COLOR:Lerp(colors.Surface, 0.35))
		heartText.Text = UIKit.formatDuration(pairing.secondsLeft or 0)
		caption.Text = ""
		speedUpCost = GemSpeedUp(pairing.secondsLeft or 0)
		speedButton.SetCost("Gem", UIKit.formatNumber(speedUpCost))
		speedButton.SetEnabled(gems >= speedUpCost)
	else
		local bothChosen = slotCard("A") ~= nil and slotCard("B") ~= nil
		setHeartColor(bothChosen and HEART_COLOR or colors.SurfaceRaised)
		heartText.Text = "Breed"
		caption.Text = bothChosen and "" or "Choose two adult dragons"
	end
	speedHolder.Visible = pairing ~= nil and not pairing.ready
	-- The tree's pink sparkles while the pairing runs, as on the island.
	if stage and stage.love then
		stage.love.Enabled = pairing ~= nil and not pairing.ready
	end
end

render = function()
	if not isOpen or not status then
		return
	end
	if status.pairing then
		selected = {}
	else
		-- Drop picks that are no longer available (e.g. sold since).
		for _, side in ipairs(SIDES) do
			if selected[side] and not findAvailable(selected[side]) then
				selected[side] = nil
			end
		end
	end
	for _, side in ipairs(SIDES) do
		renderSlot(side)
	end
	renderCenter()
	renderEggs()
end

-- callbacks: onBreed(dragonIdA, dragonIdB), onCollect(), onSpeedUp(gemCost).
function BreedingScreen.Init(callbackTable)
	local colors = UITheme.Colors
	callbacks = callbackTable
	local scales = {}

	gui = UIKit.new("ScreenGui", {
		Name = "BreedingScreenGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 30,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	-- A full-screen button, so clicks and drags never reach the island below.
	-- See-through: the world camera draws the Nursery behind it.
	root = UIKit.new("TextButton", {
		Name = "Root",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = gui,
	})

	for _, side in ipairs(SIDES) do
		slots[side] = createSlot(side, scales)
	end

	local header = UIKit.new("Frame", {
		Name = "Header",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, MARGIN),
		Size = UDim2.fromOffset(400, 48),
		BackgroundTransparency = 1,
		Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = header }))
	UIKit.text(header, { Name = "Title", Text = "Nursery", TextSize = 36, TextColor3 = WHITE, Outline = colors.TextShadow, OutlineThickness = 2 })

	local closeHolder = UIKit.new("Frame", {
		Name = "CloseHolder",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -MARGIN, 0, MARGIN),
		Size = UDim2.fromOffset(60, 60),
		BackgroundTransparency = 1,
		Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = closeHolder }))
	local closeButton = UIKit.button(closeHolder, { Name = "CloseButton", Variant = "Info", Text = "", CornerRadius = UDim.new(1, 0) })
	UIKit.icon(closeButton.Instance.Face, "Close", 26, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 2,
	})
	closeButton.OnActivated(function()
		BreedingScreen.Close()
	end)

	-- Heart button between the two spots, caption underneath.
	local heartHolder = UIKit.new("Frame", {
		Name = "HeartHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(190, 250),
		BackgroundTransparency = 1,
		Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = heartHolder }))
	heartButton = UIKit.new("TextButton", {
		Name = "HeartButton",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(190, 190),
		Parent = heartHolder,
	})
	UIKit.pressable(heartButton)
	heartText = UIKit.text(heartButton, {
		Name = "Label",
		Position = UDim2.fromOffset(0, 6),
		TextSize = 26,
		TextColor3 = WHITE,
		ZIndex = 2,
		Outline = colors.TextShadow,
		OutlineThickness = 1.5,
	})
	caption = UIKit.text(heartHolder, {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 80, 0, 50),
		TextSize = 20,
		TextWrapped = true,
		TextColor3 = WHITE,
		Outline = colors.TextShadow,
		OutlineThickness = 1.5,
	})

	-- Speed up, under the heart while a pairing runs.
	speedHolder = UIKit.new("Frame", {
		Name = "SpeedUpHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromOffset(230, 62),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = heartHolder,
	})
	speedButton = UIKit.button(speedHolder, {
		Name = "SpeedUpButton",
		Variant = "Gem",
		Text = "Speed up",
		TextSize = 24,
		CostTextSize = 22,
		CornerRadius = UDim.new(0, 16),
	})
	speedButton.OnActivated(function()
		callbacks.onSpeedUp(speedUpCost)
	end)
	speedButton.OnBlocked(function()
		Toast.Show("Not enough Gems")
	end)

	heartButton.Activated:Connect(function()
		local pairing = status and status.pairing
		if pairing then
			if pairing.ready then
				callbacks.onCollect()
			else
				Toast.Show("Breeding in progress...")
			end
			return
		end
		local cardA, cardB = slotCard("A"), slotCard("B")
		if cardA and cardB then
			callbacks.onBreed(cardA.id, cardB.id)
		else
			Toast.Show("Choose two adult dragons")
		end
	end)

	-- "Eggs possibles" (top center, under the title).
	eggsPanel = UIKit.new("Frame", {
		Name = "Eggs",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, MARGIN + 58),
		Size = UDim2.fromOffset(280, 124),
		BackgroundColor3 = colors.Surface,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = root,
	})
	UIKit.corner(eggsPanel, UDim.new(0, 18))
	UIKit.stroke(eggsPanel, colors.SurfaceStroke, 1.5)
	table.insert(scales, UIKit.new("UIScale", { Parent = eggsPanel }))
	eggsTitle = UIKit.text(eggsPanel, {
		Name = "Title",
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 28),
		TextSize = 22,
		TextColor3 = colors.Text,
	})
	eggsRow = UIKit.new("Frame", {
		Name = "Row",
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, EGG_SIZE),
		BackgroundTransparency = 1,
		Parent = eggsPanel,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 24),
		Parent = eggsRow,
	})

	UIKit.bindScreenScale(gui, scales, 1280, 720)
end

-- The player's Gems (Speed up greys out when short).
function BreedingScreen.SetGems(amount)
	gems = amount
	if isOpen and status then
		render()
	end
end

function BreedingScreen.IsOpen()
	return isOpen
end

-- newStatus: the Nursery's last push (its nurseryId picks the building).
function BreedingScreen.Open(newStatus)
	status = newStatus
	if not isOpen then
		isOpen = true
		selected = {}
		hideLowerGuis(true)
		root.Visible = true
	end
	if not stage or stage.nurseryId ~= newStatus.nurseryId then
		buildStage(newStatus.nurseryId)
	end
	render()
end

-- Server push: refreshes the screen if it is open (no-op otherwise).
function BreedingScreen.Update(newStatus)
	status = newStatus
	render()
end

function BreedingScreen.Close()
	if not isOpen then
		return
	end
	isOpen = false
	root.Visible = false
	for _, side in ipairs(SIDES) do
		clearRows(slots[side])
	end
	eggsSignature = nil
	destroyStage()
	hideLowerGuis(false)
end

return BreedingScreen
