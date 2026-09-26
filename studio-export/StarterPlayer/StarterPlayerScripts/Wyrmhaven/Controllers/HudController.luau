-- Persistent HUD in Roblox's top bar row. Top-right: one pill per resource
-- (Coins/Gems/Food) with its 3D icon and the amount, no text label. Top-left:
-- the player's level - their avatar in a circle, an XP ring filling around it
-- clockwise and the level number on a badge. Kept in sync purely by listening
-- for the server's periodic UpdateHud push (see HudService) - no client-side
-- prediction, same authoritative-server approach as the rest of the project.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConstants = require(ReplicatedStorage.Wyrmhaven.Config.GameConstants)

local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local UITheme = require(UI.UITheme)
local Toast = require(UI.Toast)

local HudController = {}

local RESOURCES = {
	{ name = "Coins", icon = "Coin" },
	{ name = "Gems", icon = "Gem" },
	{ name = "Food", icon = "Food" },
}
local MAX_FLYING_ICONS = 8
-- Space kept free at the right edge for ShopController's Shop button
-- (150px wide, 12px from the edge) plus a gap.
local RIGHT_RESERVED = 12 + 150 + 24
local BUMP_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local LEVEL_SIZE = 54 -- outer diameter of the XP ring, fits the top bar row
local RING_WIDTH = 5
local LEVEL_LEFT_OFFSET = 12 -- gap after Roblox's own top bar buttons
local FILL_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Opaque on one half of the circle only; rotating it sweeps the edge around.
local HALF_MASK = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.499, 1),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 0),
})

local hudGui
local counters = {} -- [resource] = { amount = TextLabel, icon = Frame, bump = UIScale }
local holds = { Coins = 0, Gems = 0, Food = 0 }
local latest = nil -- last UpdateHud payload

local function render(resource)
	if latest and holds[resource] == 0 then
		counters[resource].amount.Text = UIKit.formatNumber(latest[resource] or 0)
	end
end

-- The resource's icon on the HUD (e.g. where flying collect icons land).
function HudController.GetCounter(resource)
	return counters[resource] and counters[resource].icon
end

-- Freezes one counter until the returned release() runs (e.g. when collect
-- icons land on it), then shows the latest server value with a small bump.
function HudController.Hold(resource)
	holds[resource] += 1
	local released = false
	return function()
		if released then
			return
		end
		released = true
		holds[resource] -= 1
		render(resource)

		local bump = counters[resource].bump
		bump.Scale = 1.35
		TweenService:Create(bump, BUMP_TWEEN, { Scale = 1 }):Play()
	end
end

-- Collect effect: icons burst out of `fromButton` and fly into the resource's
-- counter, which shows the new balance once they land.
function HudController.PlayCollect(resource, iconKey, fromButton, amount)
	if not fromButton or not counters[resource] then
		return
	end
	local release = HudController.Hold(resource)
	local from = fromButton.AbsolutePosition + fromButton.AbsoluteSize / 2
	local count = math.clamp(math.ceil(amount / 10), 3, MAX_FLYING_ICONS)
	UIKit.flyIcons(hudGui, iconKey, from, counters[resource].icon, count, release)
end

-- Level widget: returns update(level, xp, xpRequired).
local function createLevelWidget(parent, userId)
	local colors = UITheme.Colors
	local holder = UIKit.new("Frame", {
		Name = "Level",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(LEVEL_SIZE, LEVEL_SIZE),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.placeInTopbarLeft(holder, LEVEL_LEFT_OFFSET)

	local track = UIKit.new("Frame", {
		Name = "Track",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.BarTrack,
		Parent = holder,
	})
	UIKit.corner(track, UDim.new(1, 0))
	UIKit.stroke(track, colors.SurfaceStroke, 1)

	-- The fill is two half-circle masks: the right half covers the first half
	-- of the level (from the top, clockwise), the left half the second.
	local function halfFill(name, maskX, circleX)
		local mask = UIKit.new("Frame", {
			Name = name,
			Position = UDim2.fromScale(maskX, 0),
			Size = UDim2.fromScale(0.5, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 2,
			Parent = holder,
		})
		local circle = UIKit.new("Frame", {
			Name = "Fill",
			Position = UDim2.fromScale(circleX, 0),
			Size = UDim2.fromScale(2, 1),
			BackgroundColor3 = colors.XpFill,
			ZIndex = 2,
			Parent = mask,
		})
		UIKit.corner(circle, UDim.new(1, 0))
		return UIKit.new("UIGradient", { Transparency = HALF_MASK, Parent = circle })
	end
	local rightMask = halfFill("RightHalf", 0.5, -1)
	local leftMask = halfFill("LeftHalf", 0, 0)

	local avatar = UIKit.new("ImageLabel", {
		Name = "Avatar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(LEVEL_SIZE - RING_WIDTH * 2, LEVEL_SIZE - RING_WIDTH * 2),
		BackgroundColor3 = colors.SurfaceRaised,
		Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId),
		ZIndex = 3,
		Parent = holder,
	})
	UIKit.corner(avatar, UDim.new(1, 0))
	UIKit.stroke(avatar, colors.Surface, 2)
	local avatarBump = UIKit.new("UIScale", { Name = "Bump", Parent = avatar })

	local badge = UIKit.new("Frame", {
		Name = "LevelBadge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 1, -6),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = colors.Surface,
		ZIndex = 4,
		Parent = holder,
	})
	UIKit.corner(badge, UDim.new(1, 0))
	UIKit.stroke(badge, colors.Accent, 1.5)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7), Parent = badge })
	local badgeBump = UIKit.new("UIScale", { Name = "Bump", Parent = badge })
	local levelLabel = UIKit.text(badge, {
		Name = "Level",
		Text = "1",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextSize = 15,
		TextColor3 = colors.Accent,
		ZIndex = 5,
	})

	local fill = UIKit.new("NumberValue", { Name = "FillFraction", Parent = holder })
	local function renderFill(fraction)
		fraction = math.clamp(fraction, 0, 1)
		rightMask.Rotation = 180 + 360 * math.min(fraction, 0.5)
		leftMask.Rotation = 360 * math.max(fraction, 0.5) - 180
	end
	fill.Changed:Connect(renderFill)
	renderFill(0)

	local shown = nil -- { level, fraction } displayed (or being tweened to)
	local animating = false
	local pending = nil

	local function update(level, fraction)
		if animating then
			pending = { level, fraction }
			return
		end
		if not shown then
			shown = { level = level, fraction = fraction }
			levelLabel.Text = tostring(level)
			fill.Value = fraction
			return
		end
		if level == shown.level and fraction == shown.fraction then
			return
		end
		if level > shown.level then
			-- Level up: the ring closes, the badge pops, then the ring starts over.
			animating = true
			local gems = (level - shown.level) * GameConstants.LevelUpGems -- given by the server (LevelService)
			local closing = TweenService:Create(fill, FILL_TWEEN, { Value = 1 })
			closing.Completed:Connect(function()
				levelLabel.Text = tostring(level)
				badgeBump.Scale = 1.6
				TweenService:Create(badgeBump, BUMP_TWEEN, { Scale = 1 }):Play()
				avatarBump.Scale = 1.12
				TweenService:Create(avatarBump, BUMP_TWEEN, { Scale = 1 }):Play()
				Toast.Show(string.format("Level %d reached! +%d Gems", level, gems))
				fill.Value = 0
				shown = { level = level, fraction = 0 }
				animating = false
				local nextProgress = pending or { level, fraction }
				pending = nil
				update(nextProgress[1], nextProgress[2])
			end)
			closing:Play()
		else
			shown = { level = level, fraction = fraction }
			levelLabel.Text = tostring(level)
			TweenService:Create(fill, FILL_TWEEN, { Value = fraction }):Play()
		end
	end

	return function(level, xp, xpRequired)
		update(level, (xpRequired and xpRequired > 0) and (xp or 0) / xpRequired or 0)
	end
end

function HudController.Init(remotesFolder)
	local updateHud = remotesFolder:WaitForChild("UpdateHud")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- Above the option bars, so collect icons flying up stay visible.
	hudGui = UIKit.new("ScreenGui", {
		Name = "HudGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 15,
		Parent = playerGui,
	})

	-- In Roblox's top bar row, just left of the Shop button.
	local bar = UIKit.new("Frame", {
		Name = "ResourceBar",
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(0, 42),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = hudGui,
	})
	UIKit.placeInTopbar(bar, RIGHT_RESERVED)
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 30),
		Parent = bar,
	})

	for index, resource in ipairs(RESOURCES) do
		local amount, pill, icon = UIKit.resourcePill(bar, resource.icon, index)
		pill.Size = UDim2.fromOffset(130, 42)
		counters[resource.name] = {
			amount = amount,
			icon = icon,
			bump = UIKit.new("UIScale", { Name = "Bump", Parent = icon }),
		}
	end

	local updateLevel = createLevelWidget(hudGui, player.UserId)

	updateHud.OnClientEvent:Connect(function(data)
		latest = data
		for _, resource in ipairs(RESOURCES) do
			render(resource.name)
		end
		if data.Level then
			updateLevel(data.Level, data.Xp, data.XpRequired)
		end
	end)
end

return HudController
