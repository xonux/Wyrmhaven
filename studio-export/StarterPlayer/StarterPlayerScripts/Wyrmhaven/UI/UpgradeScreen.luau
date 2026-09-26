-- Upgrade window (Dragon Mania Legends layout): the building's next level
-- turning in 3D on the left with a line about what it does, what the upgrade
-- brings on the right ("Nests  1 -> 2"), and the price button under
-- it. Centered over the dimmed island; the X or a tap outside closes it. One
-- upgrade at a time: Open replaces what's shown, Update refreshes it (e.g.
-- its button when the balance changes).
--
-- spec: key (what's upgraded, e.g. "Incubator"), previewKey (the preview is
-- rebuilt only when it changes, e.g. the next level), title, description,
-- makeTemplate() -> Part/Model of the next level, stats = { { label, icon,
-- from, to } }, currency ("Gem" | "Coin"), price, buttonText, canAfford,
-- blockedMessage (toast when tapped unaffordable), onConfirm. Optional, to
-- confirm other things (e.g. selling a dragon): statsTitle (default "Niveau
-- suivant"), priceText (default: the price), buttonVariant (UITheme.Buttons
-- key, default "Confirm"), previewOptions (ModelPreview options).
-- Selling a dragon (HabitatUIController, IncubatorController) goes through it too.
local Players = game:GetService("Players")

local UITheme = require(script.Parent.UITheme)
local UIKit = require(script.Parent.UIKit)
local Toast = require(script.Parent.Toast)
local ModelPreview = require(script.Parent.ModelPreview)

local UpgradeScreen = {}

local PANEL_WIDTH, PANEL_HEIGHT = 820, 440
local MARGIN = 24
local LEFT_WIDTH = 360
local RIGHT_X = MARGIN * 2 + LEFT_WIDTH
local RIGHT_WIDTH = PANEL_WIDTH - RIGHT_X - MARGIN
local CONTENT_TOP = 84
local STAT_HEIGHT = 100
local POP_OPEN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local WHITE = Color3.new(1, 1, 1)
local GAIN_HEX = "#7AD287" -- the "to" value of a stat

local gui, popScale
local titleLabel, descriptionLabel, previewHolder, statsList, confirmButton, statsTitleLabel
local preview = nil
local current = nil -- the spec shown

local function ensureGui()
	if gui then
		return
	end
	local colors = UITheme.Colors

	gui = UIKit.new("ScreenGui", {
		Name = "UpgradeScreenGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	-- Dimmed island; a tap on it closes the window.
	local backdrop = UIKit.new("TextButton", {
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = colors.Backdrop,
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	backdrop.Activated:Connect(function()
		UpgradeScreen.Close()
	end)

	-- The holder carries the screen scale, the panel its pop-in scale.
	local holder = UIKit.new("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local screenScale = UIKit.new("UIScale", { Parent = holder })
	-- A button, so taps on the panel never reach the backdrop behind it.
	local panel = UIKit.new("TextButton", {
		Name = "Panel",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = WHITE,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	UIKit.corner(panel, UDim.new(0, 22))
	UIKit.stroke(panel, colors.SurfaceStroke, 2)
	UIKit.gradient(panel, colors.PopupTop, colors.PopupBottom)
	popScale = UIKit.new("UIScale", { Parent = panel })

	titleLabel = UIKit.text(panel, {
		Name = "Title",
		Position = UDim2.fromOffset(MARGIN, 16),
		Size = UDim2.new(1, -MARGIN * 2 - 60, 0, 48),
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	UIKit.new("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(MARGIN, 70),
		Size = UDim2.new(1, -MARGIN * 2, 0, 1),
		BackgroundColor3 = colors.SurfaceStroke,
		BorderSizePixel = 0,
		Parent = panel,
	})

	local closeHolder = UIKit.new("Frame", {
		Name = "CloseHolder",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(46, 46),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	local closeButton = UIKit.button(closeHolder, { Name = "CloseButton", Variant = "Danger", Text = "", CornerRadius = UDim.new(1, 0) })
	UIKit.icon(closeButton.Instance.Face, "Close", 22, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 2,
	})
	closeButton.OnActivated(function()
		UpgradeScreen.Close()
	end)

	-- Left: the next level, turning, and what the building is for.
	previewHolder = UIKit.new("Frame", {
		Name = "Preview",
		Position = UDim2.fromOffset(MARGIN, CONTENT_TOP + 4),
		Size = UDim2.fromOffset(LEFT_WIDTH, 250),
		BackgroundColor3 = WHITE,
		Parent = panel,
	})
	UIKit.corner(previewHolder, UDim.new(0, 16))
	UIKit.stroke(previewHolder, colors.SurfaceStroke, 1.5)
	UIKit.gradient(previewHolder, colors.CircleInnerTop, colors.CircleInnerBottom)
	descriptionLabel = UIKit.text(panel, {
		Name = "Description",
		Position = UDim2.fromOffset(MARGIN, CONTENT_TOP + 266),
		Size = UDim2.fromOffset(LEFT_WIDTH, 70),
		TextSize = 20,
		TextColor3 = colors.TextMuted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	-- Right: what the next level brings, and the price.
	statsTitleLabel = UIKit.text(panel, {
		Name = "NextLevel",
		Text = "Next level",
		Position = UDim2.fromOffset(RIGHT_X, CONTENT_TOP),
		Size = UDim2.fromOffset(RIGHT_WIDTH, 32),
		TextSize = 24,
		TextColor3 = colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	statsList = UIKit.new("Frame", {
		Name = "Stats",
		Position = UDim2.fromOffset(RIGHT_X, CONTENT_TOP + 42),
		Size = UDim2.fromOffset(RIGHT_WIDTH, 200),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	UIKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = statsList,
	})

	local confirmHolder = UIKit.new("Frame", {
		Name = "ConfirmHolder",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, RIGHT_X, 1, -MARGIN),
		Size = UDim2.fromOffset(RIGHT_WIDTH, 72),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	confirmButton = UIKit.button(confirmHolder, {
		Name = "ConfirmButton",
		Variant = "Confirm",
		Text = "",
		TextSize = 28,
		CostTextSize = 28,
		CornerRadius = UDim.new(0, 18),
	})
	confirmButton.OnActivated(function()
		if current and current.onConfirm then
			current.onConfirm()
		end
	end)
	confirmButton.OnBlocked(function()
		if current and current.blockedMessage then
			Toast.Show(current.blockedMessage)
		end
	end)

	UIKit.bindScreenScale(gui, { screenScale }, 1280, 720)
end

-- One stat: its name, then a row with its icon and "from -> to".
local function addStat(stat, order)
	local colors = UITheme.Colors
	local frame = UIKit.new("Frame", {
		Name = "Stat" .. order,
		Size = UDim2.new(1, 0, 0, STAT_HEIGHT),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = statsList,
	})
	UIKit.text(frame, {
		Name = "Label",
		Text = stat.label,
		Size = UDim2.new(1, 0, 0, 26),
		TextSize = 19,
		TextColor3 = colors.TextMuted,
	})
	local row = UIKit.new("Frame", {
		Name = "Row",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 66),
		BackgroundColor3 = colors.SurfaceRaised,
		Parent = frame,
	})
	UIKit.corner(row, UDim.new(0, 14))
	UIKit.stroke(row, colors.SurfaceStroke, 1.5)
	if stat.icon then
		UIKit.icon(row, stat.icon, 52, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 18, 0.5, 0),
		})
	end
	UIKit.text(row, {
		Name = "Value",
		RichText = true,
		Text = string.format('%s  <font color="%s">→  %s</font>', tostring(stat.from), GAIN_HEX, tostring(stat.to)),
		Position = UDim2.fromOffset(80, 0),
		Size = UDim2.new(1, -100, 1, 0),
		TextSize = 34,
	})
end

local function apply(spec)
	local samePreview = preview ~= nil and current ~= nil and current.key == spec.key and current.previewKey == spec.previewKey
	current = spec
	titleLabel.Text = spec.title or ""
	descriptionLabel.Text = spec.description or ""

	for _, child in ipairs(statsList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, stat in ipairs(spec.stats or {}) do
		addStat(stat, i)
	end

	statsTitleLabel.Text = spec.statsTitle or "Next level"
	confirmButton.SetVariant(spec.buttonVariant or "Confirm")
	confirmButton.SetText(spec.buttonText or "Upgrade")
	confirmButton.SetCost(spec.currency or "Gem", spec.priceText or UIKit.formatNumber(spec.price or 0))
	confirmButton.SetEnabled(spec.canAfford ~= false)

	if not samePreview then
		if preview then
			preview.Destroy()
			preview = nil
		end
		local template = spec.makeTemplate and spec.makeTemplate()
		if template then
			preview = ModelPreview.new(previewHolder, template, spec.previewOptions)
			template:Destroy()
		end
	end
end

function UpgradeScreen.Open(spec)
	ensureGui()
	apply(spec)
	if not gui.Enabled then
		gui.Enabled = true
		popScale.Scale = 0.85
		UIKit.tween(popScale, POP_OPEN, { Scale = 1 })
	end
end

-- Refreshes the window if it's showing `spec.key` (e.g. new balance).
function UpgradeScreen.Update(spec)
	if UpgradeScreen.IsOpen(spec.key) then
		apply(spec)
	end
end

-- key: only when that upgrade is the one shown.
function UpgradeScreen.IsOpen(key)
	return gui ~= nil and gui.Enabled and current ~= nil and (key == nil or current.key == key)
end

function UpgradeScreen.Close()
	if not gui or not gui.Enabled then
		return
	end
	gui.Enabled = false
	if preview then
		preview.Destroy()
		preview = nil
	end
	current = nil
end

return UpgradeScreen
