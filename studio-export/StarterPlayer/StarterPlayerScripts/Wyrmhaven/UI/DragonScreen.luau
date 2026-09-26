-- Full-screen dragon view (Dragon Mania Legends feed screen): the dragon's
-- live 3D model idling in front of its habitat under the sky, name + level
-- card top-left, Coins/Food top-right, NOURRIR bottom-right, and the back and
-- Move buttons bottom-left. Opened from the dragon's portrait in its
-- habitat's bar (a tap on the dragon itself opens that bar); it blocks clicks
-- on the island while open. The scene is drawn
-- by the world camera (DragonViewport's World mode), which the screen
-- borrows from the island until it closes: the screen itself is see-through.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(script.Parent.UITheme)
local UIKit = require(script.Parent.UIKit)
local Toast = require(script.Parent.Toast)
local DragonViewport = require(script.Parent.DragonViewport)

local DragonDefs = require(ReplicatedStorage.Wyrmhaven.Config.DragonDefs)
local HabitatDefs = require(ReplicatedStorage.Wyrmhaven.Config.HabitatDefs)

local DragonScreen = {}

local MARGIN = 24
local MAX_NAME_LENGTH = 20 -- same limit DragonService.Rename enforces
local LEVEL_UP_SECONDS = 1.1
local STAGE_LABELS = { Egg = "Egg", Baby = "Baby", Adult = "Adult" }
local RARITY_LABELS = require(ReplicatedStorage.Wyrmhaven.Config.DragonRules).RarityNames
local DragonClasses = require(ReplicatedStorage.Wyrmhaven.Config.DragonClasses)
-- The three combat stats, in the order they show under the name.
local STAT_ROW = {
	{ key = "Attack", icon = "Attack", short = "ATK" },
	{ key = "Health", icon = "Health", short = "HP" },
	{ key = "Speed", icon = "Speed", short = "SPD" },
}
local SLIDE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FLASH_FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local BLACK = Color3.new(0, 0, 0)
-- The habitat behind the dragon, drawn this much bigger than on the island
-- (the dragon keeps its size): its platform then fills the view, with only
-- the sky above it.
local HABITAT_SCALE = 4
local BOTTOM_BUTTON_SIZE = 72
local MOVE_BUTTON_WIDTH = 230
local SELL_BUTTON_WIDTH = 230
local BOTTOM_BUTTON_GAP = 16

local gui, root, flash, viewHolder, dragonAnchor
local nameCard, nameBox, elementBadge, levelBar, speciesLabel, classChip, classLabel
local statValues = {} -- [stat key] = its label
local skillCard, skillRows = nil, {} -- its three skills, under the name card
local coinsLabel, foodLabel, feedButton, feedHolder, moveButton, sellButton
local sellBlockedReason = ""
local levelUpLabel, levelUpScale
local callbacks
local current = nil -- { id, data, view, renamePending }
local feedBlockedReason = ""
local levelUpToken = 0
local hiddenGuis = {} -- the island's interfaces hidden while the screen is open

-- The screen is see-through (the world camera draws the dragon's scene), so
-- the interfaces under it (HUD, option bar...) are switched off while it's
-- open, then back on.
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

-- Level up (server-confirmed feeding): a food icon flies into the dragon, it
-- bumps, and "LEVEL X!" pops above it.
local function celebrate(level)
	local feedRoot = feedButton.Instance
	local from = feedRoot.AbsolutePosition + feedRoot.AbsoluteSize / 2
	UIKit.flyIcons(gui, "Food", from, dragonAnchor, 1, function()
		if not current then
			return
		end
		current.view.Bump()

		levelUpToken += 1
		local token = levelUpToken
		levelUpLabel.Text = string.format("LEVEL %d!", level)
		levelUpLabel.Visible = true
		levelUpScale.Scale = 0
		UIKit.tween(levelUpScale, UITheme.Tweens.PopOpen, { Scale = 1 })
		task.delay(LEVEL_UP_SECONDS, function()
			if token ~= levelUpToken then
				return
			end
			UIKit.tween(levelUpScale, UITheme.Tweens.PopClose, { Scale = 0 }).Completed:Wait()
			if token == levelUpToken then
				levelUpLabel.Visible = false
			end
		end)
	end)
end

-- callbacks: onFeed(dragonId), onRename(dragonId, newName), onBack(habitatId),
-- onMove(data), onSell(data) (data: the dragon's last status push).
-- updateHud: the UpdateHud remote, for the Coins/Food counters.
function DragonScreen.Init(callbackTable, updateHud)
	local colors = UITheme.Colors
	callbacks = callbackTable
	local scales = {}

	gui = UIKit.new("ScreenGui", {
		Name = "DragonScreenGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 30,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	-- A full-screen button, so clicks and drags never reach the island below.
	-- See-through: the world camera draws the dragon's scene behind it.
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

	viewHolder = UIKit.new("Frame", { Name = "DragonView", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
	dragonAnchor = UIKit.new("Frame", {
		Name = "DragonAnchor",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromOffset(1, 1),
		Parent = root,
	})

	-- Name + level card (top-left).
	nameCard = UIKit.new("Frame", {
		Name = "NameCard",
		Position = UDim2.fromOffset(MARGIN, MARGIN),
		Size = UDim2.fromOffset(420, 252),
		BackgroundColor3 = colors.Surface,
		BackgroundTransparency = 0.05,
		Parent = root,
	})
	UIKit.corner(nameCard, UDim.new(0, 18))
	UIKit.stroke(nameCard, colors.SurfaceStroke, 1.5)
	table.insert(scales, UIKit.new("UIScale", { Parent = nameCard }))

	nameBox = UIKit.new("TextBox", {
		Name = "NameBox",
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		Font = UITheme.Font,
		TextScaled = true,
		TextColor3 = colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		PlaceholderText = "Dragon name",
		PlaceholderColor3 = colors.TextMuted,
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -44, 0, 64),
		Parent = nameCard,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 52, Parent = nameBox })

	nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		local text = nameBox.Text
		local length = utf8.len(text)
		if length and length > MAX_NAME_LENGTH then
			nameBox.Text = string.sub(text, 1, utf8.offset(text, MAX_NAME_LENGTH + 1) - 1)
		end
	end)
	nameBox.FocusLost:Connect(function()
		if not current or not current.data or nameBox.Text == current.data.name then
			return
		end
		-- Not optimistic: greyed out until the server's rename answer (a push
		-- carrying `renamed`) brings back the saved, filtered name - or the old
		-- one if it refused. Live refreshes in between leave the box alone.
		current.renamePending = true
		nameBox.TextEditable = false
		nameBox.TextTransparency = 0.45
		callbacks.onRename(current.id, nameBox.Text)
	end)

	levelBar = UIKit.progressBar(nameCard, {
		Name = "LevelBar",
		FillColor = colors.LevelFill,
		TrackColor = colors.BarTrack,
		StrokeColor = colors.SurfaceStroke,
		TextSize = 20,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(58, 104),
		Size = UDim2.new(1, -80, 0, 30),
	})
	-- Element badge at the bar's start (set per dragon in Update).
	elementBadge = UIKit.elementBadge(nameCard, nil, 46, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(40, 104),
		ZIndex = 2,
	})

	speciesLabel = UIKit.text(nameCard, {
		Name = "Species",
		Position = UDim2.fromOffset(22, 130),
		Size = UDim2.new(1, -44, 0, 28),
		TextSize = 18,
		TextColor3 = colors.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- Its role in a fight (Config/DragonClasses), in the class's own color.
	classChip = UIKit.new("Frame", {
		Name = "ClassChip",
		Position = UDim2.fromOffset(22, 162),
		Size = UDim2.fromOffset(160, 32),
		BackgroundColor3 = colors.SurfaceRaised,
		Parent = nameCard,
	})
	UIKit.corner(classChip, UDim.new(1, 0))
	classLabel = UIKit.text(classChip, {
		Name = "ClassName",
		Size = UDim2.fromScale(1, 1),
		TextSize = 19,
		TextColor3 = WHITE,
		Outline = colors.TextShadow,
		OutlineThickness = 1.5,
	})

	-- Attack / Health / Speed, from its class, rarity and level
	-- (DragonRules.Stats).
	local statsRow = UIKit.new("Frame", {
		Name = "StatsRow",
		Position = UDim2.fromOffset(22, 202),
		Size = UDim2.new(1, -44, 0, 36),
		BackgroundTransparency = 1,
		Parent = nameCard,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = statsRow,
	})
	for order, stat in ipairs(STAT_ROW) do
		local chip = UIKit.new("Frame", {
			Name = stat.key,
			Size = UDim2.fromOffset(120, 36),
			BackgroundColor3 = colors.SurfaceRaised,
			LayoutOrder = order,
			Parent = statsRow,
		})
		UIKit.corner(chip, UDim.new(0, 12))
		UIKit.icon(chip, stat.icon, 22, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
		})
		statValues[stat.key] = UIKit.text(chip, {
			Name = "Value",
			Position = UDim2.fromOffset(38, 0),
			Size = UDim2.new(1, -46, 1, 0),
			TextSize = 18,
			TextColor3 = colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	-- Its three skills (Config/SkillDefs), under the name card: name, cooldown
	-- and, on hover or tap, what it does.
	-- A child of the name card, so the two scale together on small screens.
	skillCard = UIKit.new("Frame", {
		Name = "SkillCard",
		Position = UDim2.fromOffset(0, 264),
		Size = UDim2.fromOffset(420, 152),
		BackgroundColor3 = colors.Surface,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = nameCard,
	})
	UIKit.corner(skillCard, UDim.new(0, 18))
	UIKit.stroke(skillCard, colors.SurfaceStroke, 1.5)
	UIKit.text(skillCard, {
		Name = "Header",
		Text = "Skills",
		Position = UDim2.fromOffset(22, 8),
		Size = UDim2.new(1, -44, 0, 24),
		TextSize = 18,
		TextColor3 = colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	for index = 1, 3 do
		local row = UIKit.new("TextButton", {
			Name = "Skill" .. index,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = colors.SurfaceRaised,
			Position = UDim2.fromOffset(16, 36 + (index - 1) * 38),
			Size = UDim2.new(1, -32, 0, 34),
			Parent = skillCard,
		})
		UIKit.corner(row, UDim.new(0, 12))
		local nameLabel = UIKit.text(row, {
			Name = "SkillName",
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -90, 1, 0),
			TextSize = 18,
			TextColor3 = colors.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local cooldownLabel = UIKit.text(row, {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 0),
			Size = UDim2.fromOffset(70, 34),
			TextSize = 16,
			TextColor3 = colors.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		-- What it does, to the right of the row.
		local tooltip = UIKit.new("Frame", {
			Name = "Tooltip",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(1, 12, 0.5, 0),
			Size = UDim2.fromOffset(320, 96),
			BackgroundColor3 = colors.Surface,
			Visible = false,
			ZIndex = 10,
			Parent = row,
		})
		UIKit.corner(tooltip, UDim.new(0, 12))
		UIKit.stroke(tooltip, colors.SurfaceStroke, 1.5)
		local tooltipText = UIKit.text(tooltip, {
			Name = "Text",
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, -24, 1, -16),
			TextSize = 16,
			TextColor3 = colors.Text,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 11,
		})
		row.MouseEnter:Connect(function()
			tooltip.Visible = tooltipText.Text ~= ""
		end)
		row.MouseLeave:Connect(function()
			tooltip.Visible = false
		end)
		row.Activated:Connect(function()
			tooltip.Visible = not tooltip.Visible and tooltipText.Text ~= ""
		end)
		skillRows[index] = { row = row, name = nameLabel, cooldown = cooldownLabel, tooltip = tooltip, text = tooltipText }
	end

	-- Coins / Food counters (top-right).
	local resources = UIKit.new("Frame", {
		Name = "Resources",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -MARGIN, 0, MARGIN + 10),
		Size = UDim2.fromOffset(480, 46),
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 28), -- room for the icons poking out of each pill
		Parent = resources,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = resources }))
	coinsLabel = UIKit.resourcePill(resources, "Coin", 1)
	foodLabel = UIKit.resourcePill(resources, "Food", 2)
	updateHud.OnClientEvent:Connect(function(data)
		coinsLabel.Text = UIKit.formatNumber(data.Coins or 0)
		foodLabel.Text = UIKit.formatNumber(data.Food or 0)
	end)

	-- NOURRIR (bottom-right). Holder carries the screen scale: the button
	-- already has its own press UIScale.
	feedHolder = UIKit.new("Frame", {
		Name = "FeedHolder",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -MARGIN, 1, -MARGIN),
		Size = UDim2.fromOffset(300, 84),
		BackgroundTransparency = 1,
		Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = feedHolder }))
	-- The Food cost of the next level rides on the button (SetCost), so it
	-- carries the Food icon itself.
	feedButton = UIKit.button(feedHolder, {
		Name = "FeedButton",
		Variant = "Confirm",
		Text = "Feed",
		TextSize = 34,
		CostTextSize = 30,
		CornerRadius = UDim.new(0, 18),
	})
	feedButton.OnActivated(function()
		if current then
			callbacks.onFeed(current.id)
		end
	end)
	feedButton.OnBlocked(function()
		Toast.Show(feedBlockedReason)
	end)

	-- Bottom-left row, scaled as one: back to the habitat, Move, Sell.
	local bottomLeft = UIKit.new("Frame", {
		Name = "BottomLeft",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, MARGIN, 1, -MARGIN),
		Size = UDim2.fromOffset(BOTTOM_BUTTON_SIZE + BOTTOM_BUTTON_GAP * 2 + MOVE_BUTTON_WIDTH + SELL_BUTTON_WIDTH, BOTTOM_BUTTON_SIZE),
		BackgroundTransparency = 1,
		Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = bottomLeft }))
	local backHolder = UIKit.new("Frame", {
		Name = "BackHolder",
		Size = UDim2.fromOffset(BOTTOM_BUTTON_SIZE, BOTTOM_BUTTON_SIZE),
		BackgroundTransparency = 1,
		Parent = bottomLeft,
	})
	local backButton = UIKit.button(backHolder, {
		Name = "BackButton",
		Variant = "Info",
		Text = "<",
		TextSize = 36,
		CornerRadius = UDim.new(1, 0),
	})
	backButton.OnActivated(function()
		if current then
			callbacks.onBack(current.data.habitatId)
		end
	end)

	local moveHolder = UIKit.new("Frame", {
		Name = "MoveHolder",
		Position = UDim2.fromOffset(BOTTOM_BUTTON_SIZE + BOTTOM_BUTTON_GAP, 0),
		Size = UDim2.fromOffset(MOVE_BUTTON_WIDTH, BOTTOM_BUTTON_SIZE),
		BackgroundTransparency = 1,
		Parent = bottomLeft,
	})
	moveButton = UIKit.button(moveHolder, {
		Name = "MoveButton",
		Variant = "Info",
		Text = "Move",
		TextSize = 28,
		CornerRadius = UDim.new(0, 18),
	})
	local moveFace = moveButton.Instance.Face
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 44), Parent = moveFace.Content })
	UIKit.icon(moveFace, "Move", 30, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 42, 0.5, 0), ZIndex = 2 })
	moveButton.OnActivated(function()
		if current and current.data then
			callbacks.onMove(current.data)
		end
	end)
	moveButton.OnBlocked(function()
		Toast.Show("This dragon is at the Nursery")
	end)

	-- Sell: its rarity's price on the button; the sale is confirmed in a
	-- window first (callbacks.onSell).
	local sellHolder = UIKit.new("Frame", {
		Name = "SellHolder",
		Position = UDim2.fromOffset(BOTTOM_BUTTON_SIZE + BOTTOM_BUTTON_GAP * 2 + MOVE_BUTTON_WIDTH, 0),
		Size = UDim2.fromOffset(SELL_BUTTON_WIDTH, BOTTOM_BUTTON_SIZE),
		BackgroundTransparency = 1,
		Parent = bottomLeft,
	})
	sellButton = UIKit.button(sellHolder, {
		Name = "SellButton",
		Variant = "Danger",
		Text = "Sell",
		TextSize = 26,
		CostTextSize = 22,
		CornerRadius = UDim.new(0, 18),
	})
	sellButton.OnActivated(function()
		if current and current.data then
			callbacks.onSell(current.data)
		end
	end)
	sellButton.OnBlocked(function()
		Toast.Show(sellBlockedReason)
	end)

	local levelUpHolder = UIKit.new("Frame", {
		Name = "LevelUp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromOffset(640, 100),
		BackgroundTransparency = 1,
		Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = levelUpHolder }))
	levelUpLabel = UIKit.text(levelUpHolder, {
		Name = "Text",
		TextSize = 56,
		TextColor3 = colors.Accent,
		Visible = false,
		Outline = colors.TextShadow,
		OutlineThickness = 2,
	})
	levelUpScale = UIKit.new("UIScale", { Scale = 0, Parent = levelUpLabel })

	flash = UIKit.new("Frame", {
		Name = "Flash",
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Visible = false,
		Parent = root,
	})

	UIKit.bindScreenScale(gui, scales, 1280, 720)
end

-- id of the dragon shown, or nil.
function DragonScreen.GetCurrent()
	return current and current.id
end

function DragonScreen.IsShowing(dragonId)
	return current ~= nil and current.id == dragonId
end

function DragonScreen.Update(data)
	if not DragonScreen.IsShowing(data.id) then
		return
	end
	local previous = current.data
	current.data = data

	-- Its species: a hybrid shows both elements.
	UIKit.setElementBadge(elementBadge, data.element)
	local rarity = RARITY_LABELS[data.rarity] or data.rarity
	speciesLabel.Text = rarity
		and string.format("%s  ·  %s  ·  %s", data.speciesName, rarity, STAGE_LABELS[data.stage] or data.stage)
		or string.format("%s  ·  %s", data.speciesName, STAGE_LABELS[data.stage] or data.stage)

	if data.renamed ~= nil then
		current.renamePending = false
	end
	if not current.renamePending and not nameBox:IsFocused() then
		nameBox.Text = data.name
		nameBox.TextEditable = true
		nameBox.TextTransparency = 0
	end

	local level, maxLevel = data.level or 1, data.maxLevel or 1
	levelBar.SetText(string.format("Lv %d / %d", level, maxLevel))
	levelBar.Set(maxLevel > 1 and (level - 1) / (maxLevel - 1) or 1, previous ~= nil)

	local classDef = DragonClasses.Get(data.class)
	classLabel.Text = data.className or classDef.DisplayName
	classChip.BackgroundColor3 = classDef.Color
	for _, stat in ipairs(STAT_ROW) do
		statValues[stat.key].Text = string.format("%s %s", stat.short, UIKit.formatNumber((data.stats and data.stats[stat.key]) or 0))
	end

	-- Skills: hidden entirely for a species that has none yet.
	local skills = data.skills or {}
	skillCard.Visible = #skills > 0
	for index, entry in ipairs(skillRows) do
		local skill = skills[index]
		entry.row.Visible = skill ~= nil
		entry.tooltip.Visible = false
		if skill then
			entry.name.Text = skill.name
			entry.cooldown.Text = (skill.cooldown or 0) > 0 and string.format("CD %d", skill.cooldown) or "Every turn"
			entry.text.Text = skill.description or ""
		end
	end

	-- A dragon at the Nursery stays put: its pairing points at its habitat.
	moveButton.SetEnabled(not data.isBreeding)
	if data.sellPrice then
		sellButton.SetCost("Coin", "+" .. UIKit.formatNumber(data.sellPrice))
	else
		sellButton.SetCost(nil)
	end
	sellButton.SetEnabled(data.sellPrice ~= nil and not data.isBreeding)
	sellBlockedReason = data.isBreeding and "This dragon is at the Nursery" or "This dragon can't be sold"

	-- Feeding never stops at Adult any more: one feeding = one level, for the
	-- Food that level costs, up to the max level.
	if data.feedCost then
		feedButton.SetText("Feed")
		feedButton.SetCost("Food", UIKit.formatNumber(data.feedCost))
		feedButton.SetEnabled(not data.isBreeding)
		feedBlockedReason = "This dragon is at the Nursery"
	else
		feedButton.SetText("Max level")
		feedButton.SetCost(nil)
		feedButton.SetEnabled(false)
		feedBlockedReason = "This dragon is fully grown"
	end

	if previous and level > (previous.level or 1) then
		celebrate(level)
	end
	-- The level that turns it into an Adult: full Coin rate (a Baby earns half)
	-- and breeding from now on.
	if data.grewUp then
		Toast.Show(string.format("%s is now an adult: full Coin income and it can breed", data.name or "Your dragon"))
	end
	if data.feedError == "NotEnoughFood" then
		feedButton.Shake()
		Toast.Show(string.format("Not enough Food: %s needed - harvest the Farm", UIKit.formatNumber(data.feedCost or 0)))
	end
end

function DragonScreen.Open(data)
	if DragonScreen.IsShowing(data.id) then
		DragonScreen.Update(data)
		return
	end
	if current then
		current.view.Destroy()
	end

	local accent = UITheme.GetElement(data.habitatElement)
	local habitatDef = HabitatDefs[data.habitatElement]
	local groundColor = habitatDef and habitatDef.PlatformColor or accent.Main
	local dragonDef = DragonDefs[data.element]
	local adultSize = dragonDef and dragonDef.StageSizes.Adult

	current = {
		id = data.id,
		renamePending = false,
		view = DragonViewport.new(viewHolder, data.id, {
			Framing = "Body",
			Stage = data.stage,
			Animate = true,
			World = true, -- the dragon idles: too costly in a ViewportFrame
			Habitat = data.habitatElement,
			HabitatScale = HABITAT_SCALE,
			GroundColor = groundColor:Lerp(BLACK, 0.45), -- only if that habitat has no model
			ReferenceRadius = adultSize and math.max(adultSize.X, adultSize.Y, adultSize.Z) / 2,
		}),
	}
	DragonScreen.Update(data)

	if not root.Visible then
		hideLowerGuis(true)
	end
	root.Visible = true
	flash.Visible = true
	flash.BackgroundTransparency = 0
	UIKit.tween(flash, FLASH_FADE, { BackgroundTransparency = 1 }).Completed:Connect(function()
		flash.Visible = false
	end)
	nameCard.Position = UDim2.fromOffset(-520, MARGIN)
	UIKit.tween(nameCard, SLIDE_IN, { Position = UDim2.fromOffset(MARGIN, MARGIN) })
	feedHolder.Position = UDim2.new(1, 420, 1, -MARGIN)
	UIKit.tween(feedHolder, SLIDE_IN, { Position = UDim2.new(1, -MARGIN, 1, -MARGIN) })
end

function DragonScreen.Close()
	if not current then
		return
	end
	nameBox:ReleaseFocus()
	current.view.Destroy()
	current = nil
	root.Visible = false
	hideLowerGuis(false)
	levelUpLabel.Visible = false
end

return DragonScreen
