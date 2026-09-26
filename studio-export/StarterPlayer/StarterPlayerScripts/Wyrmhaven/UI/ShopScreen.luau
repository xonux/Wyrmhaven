-- Full-screen Shop (Dragon Mania Legends layout): tabs down the left side,
-- and the rest of the screen is a horizontal row of product cards, each with a
-- turning 3D preview (ModelPreview), name, details and a price button. Coins,
-- Gems and the close button sit top-right. ShopController provides the cards
-- as specs and re-sends them when balances change; cards are diffed by key so
-- their previews keep turning instead of restarting.
--
-- Card spec: key, title, subtitle, footer, element (badge over the preview)
-- or accentColor (small color line instead), currency ("Coin" |
-- "Gem"), price, canAfford, blockedMessage (toast when tapped unaffordable),
-- lockedLevel (not sold yet: a padlock and "Level X" over the preview, the
-- button disabled), makeTemplate() -> Part/Model (only called when the card is
-- created), preview (ModelPreview options, e.g. a still profile; default:
-- turning), onBuy.
local Players = game:GetService("Players")

local UITheme = require(script.Parent.UITheme)
local UIKit = require(script.Parent.UIKit)
local Toast = require(script.Parent.Toast)
local ModelPreview = require(script.Parent.ModelPreview)

local ShopScreen = {}

-- Laid out on a canvas 720 design pixels tall and as wide as the screen
-- allows (at least MIN_DESIGN_WIDTH), so tabs hug the left edge on any ratio.
local DESIGN_HEIGHT = 720
local MIN_DESIGN_WIDTH = 1000
local SIDEBAR_WIDTH = 260
local MARGIN = 24
local CONTENT_LEFT = SIDEBAR_WIDTH + MARGIN
local CONTENT_TOP = 84
local CARD_WIDTH = 250
local CARD_HEIGHT = 470
local CARD_GAP = 20
local ARROW_SIZE = 56
local TAB_HEIGHT = 72
local TAB_SHIFT = 22 -- the selected tab sticks out of the sidebar
local TAB_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SCROLL_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local WHITE = Color3.new(1, 1, 1)

local gui, root, canvas, canvasScale
local tabTitle, scroller, emptyLabel, leftArrow, rightArrow
local coinsLabel, gemsLabel
local tabs = {} -- [tabId] = { button, label, stroke, title }
local tabOrder = {}
local cards = {} -- [key] = card widgets
local callbacks
local currentTab = nil
local lastTab = nil
local isOpen = false

local function fitCanvas()
	local size = gui.AbsoluteSize
	if size.X == 0 or size.Y == 0 then
		return
	end
	local scale = math.min(size.Y / DESIGN_HEIGHT, size.X / MIN_DESIGN_WIDTH)
	canvasScale.Scale = scale
	canvas.Size = UDim2.fromOffset(size.X / scale, size.Y / scale)
end

local function updateArrows()
	local overflows = scroller.AbsoluteCanvasSize.X > scroller.AbsoluteWindowSize.X + 1
	leftArrow.Visible = overflows
	rightArrow.Visible = overflows
end

-- Scrolls the row by about one card.
local function scrollBy(direction)
	local maxX = math.max(0, scroller.AbsoluteCanvasSize.X - scroller.AbsoluteWindowSize.X)
	local step = (CARD_WIDTH + CARD_GAP) * canvasScale.Scale
	local targetX = math.clamp(scroller.CanvasPosition.X + direction * step, 0, maxX)
	UIKit.tween(scroller, SCROLL_TWEEN, { CanvasPosition = Vector2.new(targetX, 0) })
end

local function createCard(spec)
	local colors = UITheme.Colors
	local card = {}

	card.frame = UIKit.new("Frame", {
		Name = spec.key,
		BackgroundColor3 = colors.SurfaceRaised,
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		Parent = scroller,
	})
	UIKit.corner(card.frame, UDim.new(0, 18))
	UIKit.stroke(card.frame, colors.SurfaceStroke, 1.5)

	local previewHolder = UIKit.new("Frame", {
		Name = "Preview",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 240),
		BackgroundColor3 = WHITE,
		Parent = card.frame,
	})
	UIKit.corner(previewHolder, UDim.new(0, 14))
	UIKit.gradient(previewHolder, colors.CircleInnerTop, colors.CircleInnerBottom)
	if spec.element then
		UIKit.elementBadge(previewHolder, spec.element, 44, {
			Position = UDim2.fromOffset(10, 10),
			ZIndex = 2,
		})
	elseif spec.accentColor then
		local accent = UIKit.new("Frame", {
			Name = "Accent",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.fromOffset(56, 5),
			BackgroundColor3 = spec.accentColor,
			ZIndex = 2,
			Parent = previewHolder,
		})
		UIKit.corner(accent, UDim.new(1, 0))
	end
	local template = spec.makeTemplate and spec.makeTemplate()
	if template then
		card.preview = ModelPreview.new(previewHolder, template, spec.preview)
		template:Destroy()
	end
	-- Locked product: a dark veil over the preview, a padlock and the level
	-- that unlocks it (shown by applyCard).
	card.lock = UIKit.new("Frame", {
		Name = "Lock",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Visible = false,
		ZIndex = 3,
		Parent = previewHolder,
	})
	UIKit.corner(card.lock, UDim.new(0, 14))
	UIKit.icon(card.lock, "Lock", 72, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
	}, colors.Text)
	card.lockLabel = UIKit.text(card.lock, {
		Name = "Level",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.64),
		Size = UDim2.new(1, -20, 0, 34),
		TextSize = 28,
		TextColor3 = colors.Text,
	})

	card.title = UIKit.text(card.frame, {
		Name = "Title",
		Position = UDim2.fromOffset(16, 262),
		Size = UDim2.new(1, -32, 0, 32),
		TextSize = 24,
		TextColor3 = colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	card.subtitle = UIKit.text(card.frame, {
		Name = "Subtitle",
		Position = UDim2.fromOffset(16, 296),
		Size = UDim2.new(1, -32, 0, 24),
		TextSize = 18,
		TextColor3 = colors.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	card.footer = UIKit.text(card.frame, {
		Name = "Footer",
		Position = UDim2.fromOffset(16, 322),
		Size = UDim2.new(1, -32, 0, 22),
		TextSize = 16,
		TextColor3 = colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local buyHolder = UIKit.new("Frame", {
		Name = "BuyHolder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -28, 0, 62),
		BackgroundTransparency = 1,
		Parent = card.frame,
	})
	card.buyButton = UIKit.button(buyHolder, { Name = "BuyButton", Variant = "Confirm", Text = "", CostTextSize = 26 })
	card.buyButton.OnActivated(function()
		if card.onBuy then
			card.onBuy()
		end
	end)
	card.buyButton.OnBlocked(function()
		if card.blockedMessage then
			Toast.Show(card.blockedMessage)
		end
	end)

	return card
end

local function applyCard(card, spec, layoutOrder)
	card.frame.LayoutOrder = layoutOrder
	card.title.Text = spec.title or ""
	card.subtitle.Text = spec.subtitle or ""
	card.footer.Text = spec.footer or ""
	card.buyButton.SetCost(spec.currency or "Coin", UIKit.formatNumber(spec.price or 0))
	local locked = spec.lockedLevel ~= nil
	card.lock.Visible = locked
	card.lockLabel.Text = locked and ("Level " .. spec.lockedLevel) or ""
	card.buyButton.SetEnabled(spec.canAfford ~= false and not locked)
	card.onBuy = spec.onBuy
	card.blockedMessage = spec.blockedMessage
end

local function destroyCard(card)
	if card.preview then
		card.preview.Destroy()
	end
	card.frame:Destroy()
end

local function clearCards()
	for key, card in pairs(cards) do
		destroyCard(card)
		cards[key] = nil
	end
end

local function styleTabs()
	local colors = UITheme.Colors
	for id, tab in pairs(tabs) do
		local selected = id == currentTab
		UIKit.tween(tab.button, TAB_TWEEN, { Position = UDim2.fromOffset(MARGIN - 10 + (selected and TAB_SHIFT or 0), 0) })
		tab.button.BackgroundColor3 = selected and colors.CircleTop or colors.SurfaceRaised
		tab.stroke.Color = selected and colors.Accent or colors.SurfaceStroke
		tab.label.TextColor3 = selected and colors.Text or colors.TextMuted
	end
end

local function createTab(parent, tab, index)
	local colors = UITheme.Colors
	local holder = UIKit.new("Frame", {
		Name = tab.id,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, TAB_HEIGHT),
		LayoutOrder = index,
		Parent = parent,
	})
	local button = UIKit.new("TextButton", {
		Name = "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = colors.SurfaceRaised,
		Position = UDim2.fromOffset(MARGIN - 10, 0),
		Size = UDim2.new(1, -(MARGIN - 10) * 2, 1, 0),
		Parent = holder,
	})
	UIKit.corner(button, UDim.new(0, 14))
	local stroke = UIKit.stroke(button, colors.SurfaceStroke, 1.5)
	UIKit.pressable(button)
	UIKit.icon(button, tab.icon, 34, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
	}, tab.iconColor)
	local label = UIKit.text(button, {
		Name = "Label",
		Text = tab.label,
		Position = UDim2.fromOffset(64, 0),
		Size = UDim2.new(1, -76, 1, 0),
		TextSize = 24,
		TextColor3 = colors.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	button.Activated:Connect(function()
		ShopScreen.SelectTab(tab.id)
	end)
	tabs[tab.id] = { button = button, label = label, stroke = stroke, title = tab.label }
	table.insert(tabOrder, tab.id)
end

-- Round scroll button centered on the left (positionX = 0) or right (1) edge
-- of `parent`; rotation 180 turns the back chevron into a forward one.
local function createArrowButton(parent, name, rotation, positionX)
	local holder = UIKit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(positionX, 0, 0.5, 0),
		Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	})
	local button = UIKit.button(holder, { Name = "Button", Variant = "Info", Text = "", CornerRadius = UDim.new(1, 0) })
	UIKit.icon(button.Instance.Face, "Back", 26, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Rotation = rotation,
		ZIndex = 2,
	})
	return holder, button
end

-- options: tabs = { { id, label, icon, iconColor }, ... } (sidebar order),
-- onTabChanged(tabId) - should answer with ShopScreen.SetCards.
function ShopScreen.Init(options)
	local colors = UITheme.Colors
	callbacks = options

	-- Default GUI inset: the canvas stays clear of Roblox's top bar.
	gui = UIKit.new("ScreenGui", {
		Name = "ShopScreenGui",
		ResetOnSpawn = false,
		DisplayOrder = 30,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	-- Oversized upward to also cover the top-bar inset; a button so clicks
	-- never reach the island below.
	root = UIKit.new("TextButton", {
		Name = "Root",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = WHITE,
		Position = UDim2.new(0, 0, 0, -100),
		Size = UDim2.new(1, 0, 1, 100),
		Visible = false,
		Parent = gui,
	})
	UIKit.gradient(root, colors.BackgroundTop, colors.BackgroundBottom)

	canvas = UIKit.new("Frame", {
		Name = "Canvas",
		Position = UDim2.fromOffset(0, 100),
		BackgroundTransparency = 1,
		Parent = root,
	})
	canvasScale = UIKit.new("UIScale", { Parent = canvas })

	-- Sidebar: title and tabs.
	local sidebar = UIKit.new("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0),
		BackgroundColor3 = colors.Surface,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Parent = canvas,
	})
	UIKit.new("Frame", {
		Name = "Divider",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = colors.SurfaceStroke,
		BorderSizePixel = 0,
		Parent = sidebar,
	})
	UIKit.text(sidebar, {
		Name = "Title",
		Text = "Shop",
		Position = UDim2.fromOffset(MARGIN, 18),
		Size = UDim2.new(1, -MARGIN * 2, 0, 48),
		TextSize = 36,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local tabList = UIKit.new("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(1, 0, 1, -96),
		BackgroundTransparency = 1,
		Parent = sidebar,
	})
	UIKit.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12), Parent = tabList })
	for index, tab in ipairs(options.tabs) do
		createTab(tabList, tab, index)
	end

	-- Top bar: current tab name, balances, close.
	tabTitle = UIKit.text(canvas, {
		Name = "TabTitle",
		Position = UDim2.fromOffset(CONTENT_LEFT, 18),
		Size = UDim2.fromOffset(400, 48),
		TextSize = 32,
		TextColor3 = colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local closeHolder = UIKit.new("Frame", {
		Name = "CloseHolder",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -MARGIN, 0, 16),
		Size = UDim2.fromOffset(56, 56),
		BackgroundTransparency = 1,
		Parent = canvas,
	})
	local closeButton = UIKit.button(closeHolder, { Name = "CloseButton", Variant = "Info", Text = "", CornerRadius = UDim.new(1, 0) })
	UIKit.icon(closeButton.Instance.Face, "Close", 24, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 2,
	})
	closeButton.OnActivated(function()
		ShopScreen.Close()
	end)

	local balances = UIKit.new("Frame", {
		Name = "Balances",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -MARGIN - 56 - 16, 0, 21),
		Size = UDim2.fromOffset(372, 46),
		BackgroundTransparency = 1,
		Parent = canvas,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 28), -- room for the icons poking out of each pill
		Parent = balances,
	})
	coinsLabel = UIKit.resourcePill(balances, "Coin", 1)
	gemsLabel = UIKit.resourcePill(balances, "Gem", 2)

	-- Content: a horizontal row of cards, with arrows when it overflows.
	local content = UIKit.new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(CONTENT_LEFT, CONTENT_TOP),
		Size = UDim2.new(1, -CONTENT_LEFT - MARGIN, 1, -CONTENT_TOP - MARGIN),
		BackgroundTransparency = 1,
		Parent = canvas,
	})
	scroller = UIKit.new("ScrollingFrame", {
		Name = "Cards",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = colors.SurfaceStroke,
		Parent = content,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, CARD_GAP),
		Parent = scroller,
	})
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 30), PaddingRight = UDim.new(0, 30), Parent = scroller })
	emptyLabel = UIKit.text(content, {
		Name = "Empty",
		Text = "Nothing for sale here yet",
		TextSize = 24,
		TextColor3 = colors.TextMuted,
		Visible = false,
	})

	local leftButton, rightButton
	leftArrow, leftButton = createArrowButton(content, "ScrollLeft", 0, 0)
	rightArrow, rightButton = createArrowButton(content, "ScrollRight", 180, 1)
	leftButton.OnActivated(function()
		scrollBy(-1)
	end)
	rightButton.OnActivated(function()
		scrollBy(1)
	end)
	scroller:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(updateArrows)
	scroller:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(updateArrows)

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitCanvas)
	fitCanvas()
end

function ShopScreen.IsOpen()
	return isOpen
end

function ShopScreen.GetTab()
	return currentTab
end

function ShopScreen.SetBalance(coins, gems)
	coinsLabel.Text = UIKit.formatNumber(coins or 0)
	gemsLabel.Text = UIKit.formatNumber(gems or 0)
end

-- Cards of the current tab, in display order.
function ShopScreen.SetCards(specs)
	local wanted = {}
	for index, spec in ipairs(specs) do
		wanted[spec.key] = true
		local card = cards[spec.key]
		if not card then
			card = createCard(spec)
			cards[spec.key] = card
		end
		applyCard(card, spec, index)
	end
	for key, card in pairs(cards) do
		if not wanted[key] then
			destroyCard(card)
			cards[key] = nil
		end
	end
	emptyLabel.Visible = #specs == 0
	task.defer(updateArrows)
end

function ShopScreen.SelectTab(tabId)
	if currentTab == tabId or not tabs[tabId] then
		return
	end
	currentTab = tabId
	styleTabs()
	tabTitle.Text = tabs[tabId].title
	clearCards()
	scroller.CanvasPosition = Vector2.zero
	callbacks.onTabChanged(tabId)
end

-- Opens on `tabId`, or the tab shown last time.
function ShopScreen.Open(tabId)
	isOpen = true
	root.Visible = true
	currentTab = nil
	ShopScreen.SelectTab(tabId or lastTab or tabOrder[1])
end

function ShopScreen.Close()
	if not isOpen then
		return
	end
	isOpen = false
	root.Visible = false
	lastTab = currentTab
	currentTab = nil
	clearCards() -- stops the turning previews
end

return ShopScreen
