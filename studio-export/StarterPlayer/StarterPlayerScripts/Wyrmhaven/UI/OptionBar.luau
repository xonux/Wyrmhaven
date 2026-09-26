-- Bottom option bar shared by every building (Dragon Mania Legends style): a
-- row of round buttons, each with an optional pill on top (level, amount,
-- timer) and a caption underneath, plus the building's name floating above it
-- on the island. One building at a time - opening another swaps the content.
-- No backdrop: the island stays pannable, and a tap anywhere else closes it.
-- The building (or obstacle) the bar belongs to gets a white outline.
--
-- Controllers describe the bar with a spec, rebuilt on every server push:
--   title, subtitle
--   anchor = { attribute = "HabitatId", value = 3 } - island part the title floats over
--   persistent = true - taps elsewhere don't close it (e.g. placement mode)
--   items = list of:
--     key       unique in the bar; items are diffed by key, so keep it stable
--     dragonId  live 3D head of that dragon, or
--     element   that element's badge, or
--     icon      UITheme.Icons key (iconColor tints drawn icons)
--     top       pill text over the circle (topColor optional, topIcon = a
--               UITheme.Icons key shown before the text)
--     label     caption under the circle
--     detail    smaller second caption line (e.g. a duration)
--     badge     small UITheme.Icons key on the circle's side
--     palette   "Circle" (default) | "Danger" | "Confirm"
--     dimmed    greyed out (still tappable, e.g. to explain why in a toast)
--     onClick   function
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UITheme = require(script.Parent.UITheme)
local UIKit = require(script.Parent.UIKit)
local DragonViewport = require(script.Parent.DragonViewport)

local OptionBar = {}

local CIRCLE_SIZE = 116
local NAME_HEIGHT = 26 -- caption under each circle
local DETAIL_HEIGHT = 20 -- second caption line, only reserved when an item has one
local ITEM_GAP = 14
local ICON_SIZE = 52
local BOTTOM_MARGIN = 26
local POP_STAGGER_SECONDS = 0.04
local TITLE_CLEARANCE_STUDS = 3 -- keeps the title above what stands on the building
local CLOSE_GRACE_SECONDS = 0.3 -- a tap on another building swaps the bar instead of closing it first
local DRAG_THRESHOLD_PIXELS = 10 -- same as InteractionController: panning never closes the bar

local WHITE = Color3.new(1, 1, 1)
local PLATFORM_CORNERS = { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) }

local PALETTES = {
	Circle = {
		Top = UITheme.Colors.CircleTop,
		Bottom = UITheme.Colors.CircleBottom,
		Edge = UITheme.Colors.CircleEdge,
		InnerTop = UITheme.Colors.CircleInnerTop,
		InnerBottom = UITheme.Colors.CircleInnerBottom,
	},
	Danger = {
		Top = Color3.fromRGB(116, 50, 48),
		Bottom = Color3.fromRGB(76, 33, 32),
		Edge = Color3.fromRGB(168, 76, 70),
		InnerTop = Color3.fromRGB(66, 30, 29),
		InnerBottom = Color3.fromRGB(46, 21, 21),
	},
	Confirm = {
		Top = Color3.fromRGB(60, 112, 76),
		Bottom = Color3.fromRGB(38, 74, 50),
		Edge = Color3.fromRGB(96, 168, 118),
		InnerTop = Color3.fromRGB(40, 78, 54),
		InnerBottom = Color3.fromRGB(28, 54, 38),
	},
}

local gui, bar, row, title, titleLabel, subtitleLabel
local current = nil -- { owner, anchorPart, persistent, items = { [key] = item } }
local closingItems = {}
local closeToken = 0
local pressStart = nil
local pressedOnBar = false
local trackConnection = nil
local selection = nil -- Highlight around the selected building

-- What the outline goes around: the "Visual" model of habitats and
-- decorations (their base part is invisible), an obstacle's Model, or the part.
local function outlineTarget(part)
	if not part then
		return nil
	end
	local visual = part:FindFirstChild("Visual")
	if visual and visual:IsA("Model") then
		return visual
	end
	if part.Parent and part.Parent:IsA("Model") then
		return part.Parent
	end
	return part
end

local function setSelection(part)
	local target = outlineTarget(part)
	if not target then
		if selection then
			selection.Adornee = nil
			selection.Enabled = false
		end
		return
	end
	if not selection then
		selection = Instance.new("Highlight")
		selection.Name = "SelectionOutline"
		selection.OutlineColor = WHITE
		selection.OutlineTransparency = 0
		selection.FillColor = WHITE
		selection.FillTransparency = 0.86
		selection.DepthMode = Enum.HighlightDepthMode.Occluded
		selection.Parent = Workspace
		-- Slow breathing glow inside the outline
		TweenService:Create(selection, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { FillTransparency = 0.97 }):Play()
	end
	selection.Adornee = target
	selection.Enabled = true
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function markPressOnBar(input)
	if isPointer(input) then
		pressedOnBar = true
	end
end

-- Anything that changes what's drawn inside the circle forces a rebuild.
local function signatureOf(desc)
	return string.format("%s|%s|%s|%s|%s", tostring(desc.dragonId), tostring(desc.element), tostring(desc.icon), tostring(desc.iconColor), desc.palette or "Circle")
end

local function createItem(desc)
	local palette = PALETTES[desc.palette or "Circle"]

	local holder = UIKit.new("Frame", {
		Name = desc.key,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(CIRCLE_SIZE, CIRCLE_SIZE + NAME_HEIGHT),
		Parent = row,
	})
	local pop = UIKit.new("UIScale", { Name = "Pop", Scale = 0, Parent = holder })

	local button = UIKit.new("TextButton", {
		Name = "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = WHITE,
		Size = UDim2.fromOffset(CIRCLE_SIZE, CIRCLE_SIZE),
		Parent = holder,
	})
	UIKit.corner(button, UDim.new(1, 0))
	UIKit.gradient(button, palette.Top, palette.Bottom)
	UIKit.stroke(button, palette.Edge, 2)
	UIKit.pressable(button)
	button.InputBegan:Connect(markPressOnBar)

	local inner = UIKit.new("Frame", {
		Name = "Inner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		BackgroundColor3 = WHITE,
		Parent = button,
	})
	UIKit.corner(inner, UDim.new(1, 0))
	UIKit.gradient(inner, palette.InnerTop, palette.InnerBottom)
	UIKit.stroke(inner, palette.Edge, 1).Transparency = 0.6

	local item = { holder = holder, pop = pop, button = button, inner = inner, signature = signatureOf(desc) }

	if desc.dragonId then
		item.view = DragonViewport.new(inner, desc.dragonId, { Framing = "Head" })
	elseif desc.element then
		UIKit.elementBadge(inner, desc.element, ICON_SIZE + 22, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
	elseif desc.icon then
		UIKit.icon(inner, desc.icon, ICON_SIZE, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		}, desc.iconColor)
	end

	item.topPill = UIKit.new("Frame", {
		Name = "TopPill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 4),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		BackgroundColor3 = UITheme.Colors.Surface,
		Visible = false,
		ZIndex = 3,
		Parent = button,
	})
	UIKit.corner(item.topPill, UDim.new(1, 0))
	UIKit.stroke(item.topPill, UITheme.Colors.SurfaceStroke, 1)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = item.topPill })
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = item.topPill,
	})
	item.topLabel = UIKit.text(item.topPill, {
		Name = "Text",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextSize = 18,
		LayoutOrder = 2,
		ZIndex = 4,
	})

	item.label = UIKit.text(holder, {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, CIRCLE_SIZE + 4),
		Size = UDim2.new(1, 16, 0, NAME_HEIGHT - 4),
		TextScaled = true,
		Outline = UITheme.Colors.TextShadow,
		OutlineThickness = 1.5,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 18, Parent = item.label })

	item.detail = UIKit.text(holder, {
		Name = "Detail",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, CIRCLE_SIZE + NAME_HEIGHT - 2),
		Size = UDim2.new(1, 16, 0, DETAIL_HEIGHT - 2),
		TextScaled = true,
		TextColor3 = UITheme.Colors.TextMuted,
		Visible = false,
		Outline = UITheme.Colors.TextShadow,
		OutlineThickness = 1,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 15, Parent = item.detail })

	button.Activated:Connect(function()
		if item.onClick then
			item.onClick()
		end
	end)

	function item.destroy()
		if item.view then
			item.view.Destroy()
		end
		holder:Destroy()
	end
	return item
end

-- Values that change without rebuilding the circle.
local function applyItem(item, desc)
	item.onClick = desc.onClick
	item.topPill.Visible = desc.top ~= nil
	item.topLabel.Text = desc.top or ""
	item.topLabel.TextColor3 = desc.topColor or UITheme.Colors.Text
	item.label.Text = desc.label or ""
	item.detail.Text = desc.detail or ""
	item.detail.Visible = desc.detail ~= nil

	if desc.topIcon ~= item.topIconKey then
		if item.topIcon then
			item.topIcon:Destroy()
			item.topIcon = nil
		end
		if desc.topIcon then
			item.topIcon = UIKit.icon(item.topPill, desc.topIcon, 22, { LayoutOrder = 1, ZIndex = 4 })
		end
		item.topIconKey = desc.topIcon
	end

	local fade = desc.dimmed and 0.55 or 0
	item.button.BackgroundTransparency = fade
	item.inner.BackgroundTransparency = fade
	item.label.TextTransparency = desc.dimmed and 0.4 or 0

	if desc.badge ~= item.badgeKey then
		if item.badge then
			item.badge:Destroy()
			item.badge = nil
		end
		if desc.badge then
			item.badge = UIKit.icon(item.button, desc.badge, 26, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				ZIndex = 4,
			})
		end
		item.badgeKey = desc.badge
	end
end

local function findAnchorPart(anchor)
	if not anchor then
		return nil
	end
	local islands = Workspace:FindFirstChild("Islands")
	local island = islands and islands:FindFirstChild(tostring(Players.LocalPlayer.UserId))
	if not island then
		return nil
	end
	for _, child in ipairs(island:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute(anchor.attribute) == anchor.value then
			return child
		end
	end
	-- Buildings are direct children; obstacles sit deeper (Obstacles folder, one Model each).
	for _, descendant in ipairs(island:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute(anchor.attribute) == anchor.value then
			return descendant
		end
	end
	return nil
end

-- Title sits just above the building's on-screen top edge, whatever the pan.
local function updateTitle()
	local part = current and current.anchorPart
	if not part or not part.Parent then
		title.Visible = false
		return
	end
	local camera = Workspace.CurrentCamera
	local half = part.Size / 2
	-- TitleHeight (studs above the part's center): buildings whose scenery rises
	-- above their base part, like habitat models.
	local y = part.Position.Y + (part:GetAttribute("TitleHeight") or half.Y) + TITLE_CLEARANCE_STUDS
	local minY, sumX, inFront = math.huge, 0, true
	for _, corner in ipairs(PLATFORM_CORNERS) do
		local point = camera:WorldToScreenPoint(Vector3.new(part.Position.X + corner.X * half.X, y, part.Position.Z + corner.Y * half.Z))
		inFront = inFront and point.Z > 0
		minY = math.min(minY, point.Y)
		sumX += point.X
	end
	title.Visible = inFront
	title.Position = UDim2.fromOffset(sumX / #PLATFORM_CORNERS, minY)
end

local function render(spec, popIn)
	titleLabel.Text = spec.title or ""
	subtitleLabel.Text = spec.subtitle or ""

	local wanted = {}
	local order = {}
	for _, desc in ipairs(spec.items) do
		wanted[desc.key] = true
		local item = current.items[desc.key]
		if item and item.signature ~= signatureOf(desc) then
			item.destroy()
			item = nil
		end
		if not item then
			item = createItem(desc)
			current.items[desc.key] = item
			local pop = item.pop
			task.delay(popIn and #order * POP_STAGGER_SECONDS or 0, function()
				UIKit.tween(pop, UITheme.Tweens.PopOpen, { Scale = 1 })
			end)
		end
		applyItem(item, desc)
		table.insert(order, item)
	end

	for key, item in pairs(current.items) do
		if not wanted[key] then
			item.destroy()
			current.items[key] = nil
		end
	end
	local itemHeight = CIRCLE_SIZE + NAME_HEIGHT
	for _, desc in ipairs(spec.items) do
		if desc.detail then
			itemHeight += DETAIL_HEIGHT
			break
		end
	end
	for index, item in ipairs(order) do
		item.holder.LayoutOrder = index
		item.holder.Size = UDim2.fromOffset(CIRCLE_SIZE, itemHeight)
	end
	local count = math.max(#order, 1)
	bar.Size = UDim2.fromOffset(count * CIRCLE_SIZE + (count - 1) * ITEM_GAP, itemHeight)
end

local function destroyClosingItems()
	for _, item in pairs(closingItems) do
		item.destroy()
	end
	closingItems = {}
end

local function ensureGui()
	if gui then
		return
	end

	-- Default GUI inset, same as HudGui, so fly-to-HUD icons can mix
	-- AbsolutePosition values from both.
	gui = UIKit.new("ScreenGui", {
		Name = "OptionBarGui",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	bar = UIKit.new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN),
		Size = UDim2.fromOffset(CIRCLE_SIZE, CIRCLE_SIZE + NAME_HEIGHT),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local barScale = UIKit.new("UIScale", { Parent = bar })

	local band = UIKit.new("Frame", {
		Name = "Band",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 48, 1, 36),
		BackgroundColor3 = UITheme.Colors.Surface,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Active = true, -- a press on the band is a UI press, not a click on the island under it
		Parent = bar,
	})
	UIKit.corner(band, UDim.new(0, 22))
	UIKit.stroke(band, UITheme.Colors.SurfaceStroke, 1).Transparency = 0.4
	band.InputBegan:Connect(markPressOnBar)

	row = UIKit.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = bar,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, ITEM_GAP),
		Parent = row,
	})

	title = UIKit.new("Frame", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(440, 80),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local titleScale = UIKit.new("UIScale", { Parent = title })
	titleLabel = UIKit.text(title, {
		Name = "BuildingName",
		Size = UDim2.new(1, 0, 0, 48),
		TextSize = 40,
		TextColor3 = WHITE,
		Outline = UITheme.Colors.TextShadow,
		OutlineThickness = 2,
	})
	subtitleLabel = UIKit.text(title, {
		Name = "Subtitle",
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 24,
		TextColor3 = UITheme.Colors.Accent,
		Outline = UITheme.Colors.TextShadow,
		OutlineThickness = 1.5,
	})

	UIKit.bindScreenScale(gui, { barScale, titleScale }, 1280, 720)

	-- Tap elsewhere (not a pan, not on the bar) closes the bar after a short
	-- grace period; a building push arriving meanwhile cancels it.
	UserInputService.InputBegan:Connect(function(input)
		if isPointer(input) then
			pressStart = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not isPointer(input) then
			return
		end
		local onBar = pressedOnBar
		pressedOnBar = false
		if not current or current.persistent or onBar or not pressStart then
			return
		end
		if (Vector2.new(input.Position.X, input.Position.Y) - pressStart).Magnitude > DRAG_THRESHOLD_PIXELS then
			return
		end
		closeToken += 1
		local token = closeToken
		task.delay(CLOSE_GRACE_SECONDS, function()
			if token == closeToken then
				OptionBar.Close()
			end
		end)
	end)
end

function OptionBar.GetGui()
	ensureGui()
	return gui
end

-- Owner of the bar shown (e.g. "Farm:1", "Habitat:3"), or nil.
function OptionBar.GetOwner()
	return current and current.owner
end

function OptionBar.IsShowing(owner)
	return current ~= nil and current.owner == owner
end

function OptionBar.GetItemButton(key)
	local item = current and current.items[key]
	return item and item.button
end

-- Explicit open: shows the bar for `owner`, or swaps it from another building.
function OptionBar.Open(owner, spec)
	ensureGui()
	closeToken += 1 -- cancels a close scheduled by the tap that led here
	destroyClosingItems()

	if current and current.owner ~= owner then
		for _, item in pairs(current.items) do
			item.destroy()
		end
		current = nil
	end

	local popIn = current == nil
	if not current then
		current = { owner = owner, items = {} }
		bar.Visible = true
		if not trackConnection then
			trackConnection = RunService.RenderStepped:Connect(updateTitle)
		end
	end
	current.anchorPart = findAnchorPart(spec.anchor)
	setSelection(current.anchorPart)
	current.persistent = spec.persistent == true
	render(spec, popIn)
	updateTitle()
end

-- Silent refresh: only applies while `owner`'s bar is the one shown.
function OptionBar.Update(owner, spec)
	if OptionBar.IsShowing(owner) then
		render(spec, false)
	end
end

function OptionBar.Close()
	-- Already closed/closing: leave the token alone, or the pending hide below
	-- would be cancelled and leave an empty band on screen.
	if not current then
		return
	end
	closeToken += 1
	for key, item in pairs(current.items) do
		closingItems[key .. "#" .. tostring(closeToken)] = item
		UIKit.tween(item.pop, UITheme.Tweens.PopClose, { Scale = 0 })
	end
	current = nil
	setSelection(nil)
	title.Visible = false
	if trackConnection then
		trackConnection:Disconnect()
		trackConnection = nil
	end

	local token = closeToken
	task.delay(UITheme.Tweens.PopClose.Time, function()
		if token == closeToken then
			destroyClosingItems()
			bar.Visible = false
		end
	end)
end

return OptionBar
