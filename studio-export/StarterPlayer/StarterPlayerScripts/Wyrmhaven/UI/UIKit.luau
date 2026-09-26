-- Reusable widget factories on top of UITheme: buttons, icons, portraits,
-- progress bars and the fly-to-HUD collect effect. Everything is built at the
-- screen's design size; each screen scales itself to fit (bindScreenScale).
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(script.Parent.UITheme)
local DragonRules = require(ReplicatedStorage:WaitForChild("Wyrmhaven"):WaitForChild("Config"):WaitForChild("DragonRules"))
local DragonModels = require(ReplicatedStorage:WaitForChild("Wyrmhaven"):WaitForChild("Config"):WaitForChild("DragonModels"))

-- 3D icon models, for UITheme.Icons entries with a Model field.
local iconModels = ReplicatedStorage:WaitForChild("Wyrmhaven"):WaitForChild("Assets"):WaitForChild("Icons")

local UIKit = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

function UIKit.new(className, props)
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	instance.Parent = props.Parent
	return instance
end

function UIKit.corner(parent, radius)
	return UIKit.new("UICorner", { CornerRadius = radius or UITheme.CardCornerRadius, Parent = parent })
end

function UIKit.stroke(parent, color, thickness, applyMode)
	return UIKit.new("UIStroke", {
		Color = color,
		Thickness = thickness or 3,
		ApplyStrokeMode = applyMode or Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

function UIKit.gradient(parent, topColor, bottomColor)
	return UIKit.new("UIGradient", { Color = ColorSequence.new(topColor, bottomColor), Rotation = 90, Parent = parent })
end

function UIKit.tween(instance, tweenInfo, goal)
	local tween = TweenService:Create(instance, tweenInfo, goal)
	tween:Play()
	return tween
end

-- Keeps every UIScale in `scales` at the ratio between `gui`'s on-screen size
-- and a design resolution, so fixed-pixel layouts read the same on a phone
-- and on a monitor.
function UIKit.bindScreenScale(gui, scales, designWidth, designHeight)
	local function apply()
		local size = gui.AbsoluteSize
		if size.X == 0 or size.Y == 0 then
			return
		end
		local scale = math.clamp(math.min(size.X / designWidth, size.Y / designHeight), 0.45, 1.75)
		for _, uiScale in ipairs(scales) do
			uiScale.Scale = scale
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	apply()
end

-- Keeps `object` in Roblox's top bar row, `rightOffset` pixels left of the end
-- of the part Roblox's own buttons leave free (GuiService.TopbarInset).
-- `object` needs AnchorPoint (1, 0.5) and a ScreenGui with IgnoreGuiInset.
function UIKit.placeInTopbar(object, rightOffset)
	local function apply()
		local inset = GuiService.TopbarInset
		local height = inset.Height > 0 and inset.Height or 58
		object.Position = UDim2.fromOffset(inset.Max.X - rightOffset, inset.Min.Y + height / 2)
	end
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(apply)
	apply()
end

-- Same, from the left end of that free part (just after Roblox's own buttons).
-- `object` needs AnchorPoint (0, 0.5) and a ScreenGui with IgnoreGuiInset.
function UIKit.placeInTopbarLeft(object, leftOffset)
	local function apply()
		local inset = GuiService.TopbarInset
		local height = inset.Height > 0 and inset.Height or 58
		object.Position = UDim2.fromOffset(inset.Min.X + leftOffset, inset.Min.Y + height / 2)
	end
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(apply)
	apply()
end

-- 95 -> "1:35", 3725 -> "1:02:05".
function UIKit.formatDuration(seconds)
	seconds = math.max(0, math.floor(seconds))
	local hours, minutes, secs = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

-- Compact form for durations shown as info: 30 -> "30 s", 120 -> "2 min",
-- 5400 -> "1 h 30".
function UIKit.formatShortDuration(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return string.format("%d s", seconds)
	end
	if seconds < 3600 then
		local minutes, rest = math.floor(seconds / 60), seconds % 60
		return rest > 0 and string.format("%d min %02d", minutes, rest) or string.format("%d min", minutes)
	end
	local hours, minutes = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
	return minutes > 0 and string.format("%d h %02d", hours, minutes) or string.format("%d h", hours)
end

-- 56234 -> "56 234", 1520000 -> "1,5M" (French grouping).
function UIKit.formatNumber(value)
	value = math.floor(value)
	if value >= 1e6 then
		return (string.format("%.1fM", value / 1e6):gsub("%.0M", "M"):gsub("%.", ","))
	end
	return (tostring(value):reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""))
end

-- TextLabel with theme defaults. Extra keys: `Outline` (Color3) adds a text
-- outline, `OutlineThickness` sets its width.
function UIKit.text(parent, props)
	local outline = props.Outline
	local outlineThickness = props.OutlineThickness
	props.Outline = nil
	props.OutlineThickness = nil

	local label = UIKit.new("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = UITheme.Font,
		TextColor3 = UITheme.Colors.Text,
		TextSize = 22,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	for key, value in pairs(props) do
		label[key] = value
	end
	if outline then
		UIKit.stroke(label, outline, outlineThickness or 2.5, Enum.ApplyStrokeMode.Contextual)
	end
	return label
end

-- Rounded bar used by the line-drawn icons (arrow, back, close).
local function iconBar(holder, color, position, size, rotation)
	local bar = UIKit.new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		Rotation = rotation or 0,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = holder,
	})
	UIKit.corner(bar, UDim.new(1, 0))
	return bar
end

-- Still copy of a 3D icon model, framed to fill the holder. def.Yaw/def.Rise
-- turn the camera around the model's front for a bit of depth.
local function fillModelIcon(holder, template, def)
	local viewport = UIKit.new("ViewportFrame", {
		Name = "Model",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(190, 190, 190),
		LightColor = WHITE,
		LightDirection = Vector3.new(-0.4, -1, -0.7),
		Parent = holder,
	})
	local camera = UIKit.new("Camera", { FieldOfView = 30, Parent = viewport })
	viewport.CurrentCamera = camera

	local model = template:Clone()
	model.Parent = viewport
	local box, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z) / 2 * 1.08
	local yaw = math.rad(def.Yaw or 0)
	local direction = (box.LookVector * math.cos(yaw) + box.RightVector * math.sin(yaw) + box.UpVector * (def.Rise or 0)).Unit
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2))
	camera.CFrame = CFrame.lookAt(box.Position + direction * distance, box.Position, box.UpVector)
end

-- tint: optional color for the drawn icons that take one (defaults to def.Color).
local function fillIcon(holder, def, size, tint)
	tint = tint or def.Color
	if def.Image and def.Image ~= "" then
		UIKit.new("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = def.Image,
			ScaleType = Enum.ScaleType.Fit,
			Parent = holder,
		})
	elseif def.Model and iconModels:FindFirstChild(def.Model) then
		fillModelIcon(holder, iconModels[def.Model], def)
	elseif def.Drawn == "Coin" then
		local disc = UIKit.new("Frame", { Name = "Coin", BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), Parent = holder })
		UIKit.corner(disc, UDim.new(1, 0))
		UIKit.gradient(disc, UITheme.Colors.CoinFaceTop, UITheme.Colors.CoinFaceBottom)
		UIKit.stroke(disc, UITheme.Colors.CoinEdge, math.max(1, size / 20))

		local rim = UIKit.new("Frame", {
			Name = "Rim",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.62, 0.62),
			BackgroundTransparency = 1,
			Parent = disc,
		})
		UIKit.corner(rim, UDim.new(1, 0))
		UIKit.stroke(rim, UITheme.Colors.CoinEdge, math.max(1, size / 30)).Transparency = 0.35
	elseif def.Drawn == "Food" then
		-- A round fruit with a small leaf.
		local fruit = UIKit.new("Frame", {
			Name = "Fruit",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(0.86, 0.86),
			BackgroundColor3 = WHITE,
			Parent = holder,
		})
		UIKit.corner(fruit, UDim.new(1, 0))
		UIKit.gradient(fruit, UITheme.Colors.FoodFace:Lerp(WHITE, 0.2), UITheme.Colors.FoodFace:Lerp(BLACK, 0.15))
		local leaf = UIKit.new("Frame", {
			Name = "Leaf",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.64, 0.16),
			Size = UDim2.fromScale(0.36, 0.2),
			Rotation = -30,
			BackgroundColor3 = UITheme.Colors.FoodLeaf,
			Parent = holder,
		})
		UIKit.corner(leaf, UDim.new(1, 0))
	elseif def.Drawn == "Dot" then
		local dot = UIKit.new("Frame", {
			Name = "Dot",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			BackgroundColor3 = tint or UITheme.Colors.TextMuted,
			Parent = holder,
		})
		UIKit.corner(dot, UDim.new(1, 0))
	elseif def.Drawn == "ArrowUp" then
		local color = tint or UITheme.Colors.Text
		iconBar(holder, color, UDim2.fromScale(0.5, 0.56), UDim2.fromScale(0.16, 0.66))
		iconBar(holder, color, UDim2.fromScale(0.33, 0.33), UDim2.fromScale(0.5, 0.16), -45)
		iconBar(holder, color, UDim2.fromScale(0.67, 0.33), UDim2.fromScale(0.5, 0.16), 45)
	elseif def.Drawn == "Back" then
		local color = tint or UITheme.Colors.Text
		iconBar(holder, color, UDim2.fromScale(0.45, 0.33), UDim2.fromScale(0.5, 0.16), -45)
		iconBar(holder, color, UDim2.fromScale(0.45, 0.67), UDim2.fromScale(0.5, 0.16), 45)
	elseif def.Drawn == "Check" then
		local color = tint or UITheme.Colors.Text
		iconBar(holder, color, UDim2.fromScale(0.33, 0.6), UDim2.fromScale(0.34, 0.16), 45)
		iconBar(holder, color, UDim2.fromScale(0.6, 0.5), UDim2.fromScale(0.62, 0.16), -45)
	elseif def.Drawn == "Move" then
		-- A cross with a diamond at each end (four-way arrow).
		local color = tint or UITheme.Colors.Text
		iconBar(holder, color, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.66, 0.12))
		iconBar(holder, color, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.12, 0.66))
		for _, tip in ipairs({ Vector2.new(0.5, 0.16), Vector2.new(0.5, 0.84), Vector2.new(0.16, 0.5), Vector2.new(0.84, 0.5) }) do
			local diamond = UIKit.new("Frame", {
				Name = "Tip",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(tip.X, tip.Y),
				Size = UDim2.fromScale(0.22, 0.22),
				Rotation = 45,
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Parent = holder,
			})
			UIKit.corner(diamond, UDim.new(0.15, 0))
		end
	elseif def.Drawn == "Plus" then
		local color = tint or UITheme.Colors.Text
		iconBar(holder, color, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.74, 0.16))
		iconBar(holder, color, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.16, 0.74))
	elseif def.Drawn == "Close" then
		local color = tint or UITheme.Colors.Text
		iconBar(holder, color, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.8, 0.16), 45)
		iconBar(holder, color, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.8, 0.16), -45)
	elseif def.Drawn == "Heart" then
		-- A diamond with two discs on its upper edges.
		local color = tint or Color3.fromRGB(206, 86, 120)
		local diamond = UIKit.new("Frame", {
			Name = "Diamond",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.56),
			Size = UDim2.fromScale(0.56, 0.56),
			Rotation = 45,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = holder,
		})
		UIKit.corner(diamond, UDim.new(0.12, 0))
		for _, side in ipairs({ -1, 1 }) do
			local lobe = UIKit.new("Frame", {
				Name = "Lobe",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + side * 0.2, 0.38),
				Size = UDim2.fromScale(0.56, 0.56),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Parent = holder,
			})
			UIKit.corner(lobe, UDim.new(1, 0))
		end
	elseif def.Drawn == "Egg" then
		local color = tint or UITheme.Colors.TextMuted
		local egg = UIKit.new("Frame", {
			Name = "Egg",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.64, 0.86),
			BackgroundColor3 = WHITE,
			Parent = holder,
		})
		UIKit.corner(egg, UDim.new(0.5, 0))
		UIKit.gradient(egg, color:Lerp(WHITE, 0.25), color:Lerp(BLACK, 0.2))
	elseif def.Drawn == "Swatch" then
		-- Rounded square in a habitat's platform color.
		local color = tint or UITheme.Colors.TextMuted
		local swatch = UIKit.new("Frame", {
			Name = "Swatch",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.76, 0.76),
			BackgroundColor3 = WHITE,
			Parent = holder,
		})
		UIKit.corner(swatch, UDim.new(0.24, 0))
		UIKit.gradient(swatch, color:Lerp(WHITE, 0.2), color:Lerp(BLACK, 0.2))
	elseif def.Drawn == "Lock" then
		-- Padlock: a shackle ring over a rounded body with a keyhole.
		local color = tint or UITheme.Colors.Text
		local shackle = UIKit.new("Frame", {
			Name = "Shackle",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.06),
			Size = UDim2.fromScale(0.48, 0.6),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		UIKit.corner(shackle, UDim.new(0.5, 0))
		UIKit.stroke(shackle, color, math.max(2, size * 0.1))
		local body = UIKit.new("Frame", {
			Name = "Body",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.96),
			Size = UDim2.fromScale(0.76, 0.54),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = holder,
		})
		UIKit.corner(body, UDim.new(0.2, 0))
		local keyhole = UIKit.new("Frame", {
			Name = "Keyhole",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.46),
			Size = UDim2.fromScale(0.16, 0.34),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			Parent = body,
		})
		UIKit.corner(keyhole, UDim.new(1, 0))
	elseif def.Drawn == "Axe" then
		-- Wooden handle with a steel blade on its upper end.
		local handle = iconBar(holder, Color3.fromRGB(176, 128, 82), UDim2.fromScale(0.46, 0.54), UDim2.fromScale(0.13, 0.84), 35)
		UIKit.gradient(handle, WHITE, Color3.fromRGB(200, 200, 200))
		local blade = UIKit.new("Frame", {
			Name = "Blade",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.64, 0.3),
			Size = UDim2.fromScale(0.44, 0.3),
			Rotation = 35,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Parent = holder,
		})
		UIKit.corner(blade, UDim.new(0.35, 0))
		UIKit.gradient(blade, Color3.fromRGB(226, 230, 236), Color3.fromRGB(150, 156, 168))
	else
		UIKit.new("TextLabel", {
			Name = "Glyph",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = UITheme.Font,
			Text = def.Glyph or "",
			TextScaled = true,
			TextColor3 = UITheme.Colors.Text,
			Parent = holder,
		})
	end
end

-- tint: optional color for drawn icons (Dot, ArrowUp, Heart, Egg, Swatch...).
function UIKit.icon(parent, iconKey, size, props, tint)
	local def = UITheme.Icons[iconKey]
	assert(def, "Unknown icon: " .. tostring(iconKey))

	local holder = UIKit.new("Frame", {
		Name = "Icon" .. iconKey,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	for key, value in pairs(props or {}) do
		holder[key] = value
	end
	fillIcon(holder, def, size, tint)
	return holder
end

local function paintBadge(badge, element)
	local accent = UITheme.GetElement(element)
	badge.Image = accent.Icon or ""
	badge.BackgroundColor3 = accent.Main
	badge.BackgroundTransparency = accent.Icon and 1 or 0
end

-- Points an element badge at another element - or at a dragon species: a
-- hybrid shows its first element with a smaller badge of the second one on
-- its lower right. Elements without an Icon (e.g. Default) fall back to a
-- plain disc in their color.
function UIKit.setElementBadge(badge, element)
	local elements = element and not UITheme.Elements[element] and DragonRules.Elements(element) or { element }
	paintBadge(badge, elements[1])
	local second = badge:FindFirstChild("Second")
	if elements[2] then
		if not second then
			second = UIKit.new("ImageLabel", {
				Name = "Second",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.86, 0.86),
				Size = UDim2.fromScale(0.62, 0.62),
				BorderSizePixel = 0,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = badge.ZIndex + 1,
				Parent = badge,
			})
			UIKit.corner(second, UDim.new(1, 0))
		end
		paintBadge(second, elements[2])
	elseif second then
		second:Destroy()
	end
end

-- Round element badge (UITheme.Elements[element].Icon).
function UIKit.elementBadge(parent, element, size, props)
	local badge = UIKit.new("ImageLabel", {
		Name = "ElementBadge",
		BorderSizePixel = 0,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	for key, value in pairs(props or {}) do
		badge[key] = value
	end
	UIKit.corner(badge, UDim.new(1, 0))
	UIKit.setElementBadge(badge, element)
	return badge
end

-- Balance counter pill (icon + right-aligned amount), e.g. the HUD, Coins/Food
-- on the Dragon screen or Coins/Gems in the Shop. The icon pokes out of the
-- pill's left end, the amount is centered in the space left. Returns the
-- amount label, the pill and the icon.
function UIKit.resourcePill(parent, iconKey, layoutOrder)
	local pill = UIKit.new("Frame", {
		Name = iconKey .. "Pill",
		BackgroundColor3 = UITheme.Colors.Surface,
		BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(180, 46),
		LayoutOrder = layoutOrder,
		Parent = parent,
	})
	UIKit.corner(pill, UDim.new(1, 0))
	UIKit.stroke(pill, UITheme.Colors.SurfaceStroke, 1)
	local icon = UIKit.icon(pill, iconKey, 52, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 12, 0.5, 0), ZIndex = 2 })
	local amount = UIKit.text(pill, {
		Name = "Amount",
		Text = "0",
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -52, 1, 0),
		TextSize = 24,
		TextColor3 = UITheme.Colors.Text,
	})
	return amount, pill, icon
end

-- Stage portrait (the Image if one is set in UITheme.Portraits, otherwise the
-- optional text placeholder), centered in `holder` at `scale` of its size.
function UIKit.portraitImage(holder, stage, scale)
	local def = UITheme.Portraits[stage] or UITheme.Portraits.Adult
	local image = UIKit.new("ImageLabel", {
		Name = "PortraitImage",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(scale, scale),
		Image = def.Image,
		ScaleType = Enum.ScaleType.Fit,
		Parent = holder,
	})
	if def.Image == "" and def.Glyph then
		UIKit.new("TextLabel", {
			Name = "Glyph",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = UITheme.Font,
			Text = def.Glyph,
			TextScaled = true,
			Parent = image,
		})
	end
	return image
end

-- A portrait only needs the head end of a rigged model - the rest is most of
-- its triangles, drawn only to fall outside the frame.
local PORTRAIT_PARTS = { "Head", "Jaw", "Neck" }
local HEAD_FOV = 30
local HEAD_FILL = 0.78 -- share of the frame the head covers

-- Round portrait of a species' HEAD, for telling dragons apart at a glance -
-- an element badge cannot, since several species share an element. The head
-- stays still: moving parts inside a ViewportFrame makes Roblox rebuild all
-- of its geometry every frame. Species without a model yet fall back to their
-- element badge on their own colour.
function UIKit.dragonHead(parent, species, size, color, props)
	local holder = UIKit.new("Frame", {
		Name = "Head",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color or UITheme.Colors.SurfaceRaised,
		Parent = parent,
	})
	for key, value in pairs(props or {}) do
		holder[key] = value
	end
	UIKit.corner(holder, UDim.new(1, 0))

	local template = DragonModels.Get(species, "Adult")
	local head = template and template:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		UIKit.elementBadge(holder, species, math.floor(size * 0.74), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = (holder.ZIndex or 1) + 1,
		})
		return holder
	end

	local viewport = UIKit.new("ViewportFrame", {
		Name = "Portrait",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(180, 180, 180),
		LightColor = Color3.fromRGB(255, 248, 235),
		ZIndex = (holder.ZIndex or 1) + 1,
		Parent = holder,
	})
	UIKit.corner(viewport, UDim.new(1, 0))
	local camera = UIKit.new("Camera", { FieldOfView = HEAD_FOV, Parent = viewport })
	viewport.CurrentCamera = camera

	local model = Instance.new("Model")
	for _, name in ipairs(PORTRAIT_PARTS) do
		local part = template:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local clone = part:Clone()
			for _, descendant in ipairs(clone:GetDescendants()) do
				if descendant:IsA("JointInstance") then
					descendant:Destroy()
				end
			end
			clone.Anchored = true
			clone.Parent = model
		end
	end
	model.Parent = viewport

	-- Three quarters on, from a little above: the model faces -Z.
	local radius = math.max(head.Size.X, head.Size.Y, head.Size.Z) / 2
	local distance = radius / (HEAD_FILL * math.tan(math.rad(HEAD_FOV / 2)))
	local offset = CFrame.Angles(0, math.rad(28), 0) * Vector3.new(0, radius * 0.45, -distance)
	camera.CFrame = CFrame.lookAt(head.Position + offset, head.Position)
	return holder
end

-- Round portrait disc in the dragon's accent colors (see UITheme.AccentFromColor).
function UIKit.portrait(parent, stage, accent, size, props)
	local holder = UIKit.new("Frame", {
		Name = "Portrait",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	for key, value in pairs(props or {}) do
		holder[key] = value
	end
	UIKit.corner(holder, UDim.new(1, 0))
	UIKit.gradient(holder, accent.Light, accent.Main)
	UIKit.stroke(holder, WHITE, 3)
	UIKit.portraitImage(holder, stage, 0.74)
	return holder
end

-- Squash-on-press feedback for any GuiButton.
function UIKit.pressable(button)
	local scale = UIKit.new("UIScale", { Name = "PressScale", Parent = button })
	local function release()
		UIKit.tween(scale, UITheme.Tweens.Press, { Scale = 1 })
	end
	button.MouseButton1Down:Connect(function()
		UIKit.tween(scale, UITheme.Tweens.Press, { Scale = 0.92 })
	end)
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			release()
		end
	end)
	return scale
end

-- Clean button: colored face over a thin darker lip, a light edge stroke,
-- optional cost (icon + amount) either beside the label or stacked under it.
-- opts: Name, Variant (UITheme.Buttons key), Text, TextSize, CostTextSize,
-- Stacked, Size, CornerRadius, LayoutOrder.
function UIKit.button(parent, opts)
	local variantName = opts.Variant or "Confirm"
	local radius = opts.CornerRadius or UITheme.ButtonCornerRadius

	local root = UIKit.new("TextButton", {
		Name = opts.Name or "Button",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Size = opts.Size or UDim2.fromScale(1, 1),
		LayoutOrder = opts.LayoutOrder or 0,
		Parent = parent,
	})
	UIKit.corner(root, radius)
	local outline = UIKit.stroke(root, BLACK, 1.5)
	outline.Transparency = 0.2
	UIKit.pressable(root)

	local face = UIKit.new("Frame", { Name = "Face", BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, -3), Parent = root })
	UIKit.corner(face, radius)
	UIKit.gradient(face, WHITE, Color3.fromRGB(215, 215, 215))

	local content = UIKit.new("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = face })
	UIKit.new("UIListLayout", {
		FillDirection = opts.Stacked and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, opts.Stacked and 0 or 6),
		Parent = content,
	})

	local label = UIKit.text(content, {
		Name = "Label",
		TextSize = opts.TextSize or 24,
		TextColor3 = WHITE,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		LayoutOrder = 1,
	})

	local costTextSize = opts.CostTextSize or 22
	local cost = UIKit.new("Frame", {
		Name = "Cost",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		LayoutOrder = 2,
		Visible = false,
		Parent = content,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = cost,
	})
	local costLabel = UIKit.text(cost, {
		Name = "Amount",
		TextSize = costTextSize,
		TextColor3 = WHITE,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		LayoutOrder = 2,
	})
	local costIcon, costIconKey = nil, nil

	local enabled = true
	local onActivated, onBlocked = nil, nil
	local api = { Instance = root }

	local function applyColors()
		local variant = UITheme.Buttons[enabled and variantName or "Disabled"]
		root.BackgroundColor3 = variant.Lip
		face.BackgroundColor3 = variant.Face
		outline.Color = variant.Outline
		label.TextTransparency = enabled and 0 or 0.45
		costLabel.TextTransparency = enabled and 0 or 0.45
	end

	function api.SetText(text)
		label.Text = text
		label.Visible = text ~= ""
	end

	-- iconKey nil hides the cost.
	function api.SetCost(iconKey, amount)
		if iconKey == nil then
			cost.Visible = false
			return
		end
		if iconKey ~= costIconKey then
			if costIcon then
				costIcon:Destroy()
			end
			costIcon = UIKit.icon(cost, iconKey, costTextSize + 4, { LayoutOrder = 1 })
			costIconKey = iconKey
		end
		costLabel.Text = tostring(amount)
		cost.Visible = true
	end

	function api.SetVariant(name)
		variantName = name
		applyColors()
	end

	function api.SetEnabled(on)
		enabled = on
		applyColors()
	end

	function api.OnActivated(fn)
		onActivated = fn
	end

	-- Tapped while disabled: lets the caller explain why instead of ignoring the tap.
	function api.OnBlocked(fn)
		onBlocked = fn
	end

	function api.Shake()
		task.spawn(function()
			for _, angle in ipairs({ 7, -6, 4, -2, 0 }) do
				UIKit.tween(root, TweenInfo.new(0.05), { Rotation = angle }).Completed:Wait()
			end
		end)
	end

	root.Activated:Connect(function()
		if enabled then
			if onActivated then
				onActivated()
			end
		elseif onBlocked then
			onBlocked()
		end
	end)

	api.SetText(opts.Text or "")
	applyColors()
	return api
end

-- Rounded bar with a tweenable fill, optional segment dividers (one per
-- feeding step, for example) and centered outlined text. Optional colors:
-- TrackColor, StrokeColor, TextOutline (theme dark grey by default).
function UIKit.progressBar(parent, opts)
	local track = UIKit.new("Frame", {
		Name = opts.Name or "ProgressBar",
		BackgroundColor3 = opts.TrackColor or UITheme.Colors.BarTrack,
		BorderSizePixel = 0,
		Size = opts.Size,
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		Parent = parent,
	})
	UIKit.corner(track, UDim.new(1, 0))
	UIKit.stroke(track, opts.StrokeColor or UITheme.Colors.BarStroke, 1.5)

	local fill = UIKit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = opts.FillColor,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Visible = false,
		ZIndex = 1,
		Parent = track,
	})
	UIKit.corner(fill, UDim.new(1, 0))
	UIKit.gradient(fill, WHITE, Color3.fromRGB(205, 205, 205))

	local segments = UIKit.new("Frame", { Name = "Segments", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = track })
	local text = UIKit.text(track, {
		Name = "Text",
		Text = "",
		TextSize = opts.TextSize or 20,
		TextColor3 = WHITE,
		ZIndex = 3,
		Outline = opts.TextOutline or UITheme.Colors.TextShadow,
		OutlineThickness = 1.5,
	})

	local api = { Instance = track }
	local target = 0

	function api.Set(fraction, animate)
		fraction = math.clamp(fraction, 0, 1)
		target = fraction
		local goal = UDim2.fromScale(fraction, 1)
		if not animate then
			fill.Size = goal
			fill.Visible = fraction > 0
			return
		end
		fill.Visible = true
		UIKit.tween(fill, UITheme.Tweens.BarFill, { Size = goal }).Completed:Connect(function()
			if target == 0 then
				fill.Visible = false
			end
		end)
	end

	function api.SetText(value)
		text.Text = value
	end

	function api.SetFillColor(color)
		fill.BackgroundColor3 = color
	end

	function api.SetSegments(count)
		segments:ClearAllChildren()
		for i = 1, (count or 0) - 1 do
			UIKit.new("Frame", {
				Name = "Divider",
				BackgroundColor3 = UITheme.Colors.BarStroke,
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(i / count, 0),
				Size = UDim2.new(0, 2, 1, 0),
				Parent = segments,
			})
		end
	end

	return api
end

-- Collect effect: `count` icons burst out of `fromPosition` (an
-- AbsolutePosition) then fly into `target` (e.g. a HUD counter); `onArrived`
-- runs once the last one lands. AbsolutePositions are measured below the
-- top bar even in a ScreenGui that ignores the GUI inset, so such a `layer`
-- shifts them back down by the inset.
function UIKit.flyIcons(layer, iconKey, fromPosition, target, count, onArrived)
	local inset = layer.IgnoreGuiInset and GuiService:GetGuiInset() or Vector2.zero
	fromPosition += inset
	local destination = target.AbsolutePosition + target.AbsoluteSize / 2 + inset
	local remaining = count

	for i = 1, count do
		local icon = UIKit.icon(layer, iconKey, 36, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(fromPosition.X, fromPosition.Y),
			ZIndex = 50,
		})
		task.delay((i - 1) * 0.06, function()
			local angle = math.random() * math.pi * 2
			local burst = fromPosition + Vector2.new(math.cos(angle), math.sin(angle)) * math.random(40, 80)
			UIKit.tween(icon, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(burst.X, burst.Y),
			}).Completed:Wait()
			UIKit.tween(icon, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(destination.X, destination.Y),
				Size = UDim2.fromOffset(22, 22),
			}).Completed:Wait()
			icon:Destroy()
			remaining -= 1
			if remaining == 0 and onArrived then
				onArrived()
			end
		end)
	end
end

return UIKit
