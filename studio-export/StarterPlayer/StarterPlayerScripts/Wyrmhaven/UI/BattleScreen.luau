-- The fight itself, laid out like the reference the user gave (Monster
-- Legends' PvP screen): both teams side by side and facing each other, in the
-- same arrangement, the player's three on the left and the enemy's three
-- mirrored on the right. The arena is built far from the islands and the
-- world camera is lent to it (CameraController.Hold), with the interface over
-- the top.
--
-- A turn is taken in two steps, as in the reference:
--   1. SELECT SKILL - the three skills, each just its element and its name.
--   2. SELECT TARGET - the skill's own line of text appears, every dragon it
--      cannot land on turns see-through, and the player taps one of the ones
--      left. An arrow goes back to step 1. Even a skill that hits everything,
--      or only ever one dragon, is confirmed this way.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UITheme = require(script.Parent.UITheme)
local UIKit = require(script.Parent.UIKit)
local DragonRig = require(script.Parent.DragonRig)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)

local Config = ReplicatedStorage.Wyrmhaven.Config
local DragonDefs = require(Config.DragonDefs)
local DragonModels = require(Config.DragonModels)
local ElementChart = require(Config.ElementChart)
local StatusDefs = require(Config.StatusDefs)

local BattleScreen = {}

local STAGE_ORIGIN = Vector3.new(0, 0, -32000)
-- Picked by projecting all six dragons: everyone well inside the frame on a
-- wide screen and on a 4:3 one, heads clear of the top, feet high enough for
-- a Health bar underneath.
local CAMERA_OFFSET = Vector3.new(0, 26, 30)
local CAMERA_LOOK = Vector3.new(0, 2, -1)
local CAMERA_FOV = 33
local GROUND_TOP = 3
-- Each team stands in a triangle, as in the reference: one dragon at the
-- point, nearest the middle of the arena, and two behind it, one to each
-- side. Team A takes them on the left (x mirrored), team B on the right, so
-- both teams stand in the same arrangement.
local SPOTS = {
	{ x = 5.5, z = 0 },
	{ x = 12, z = 5.5 },
	{ x = 12, z = -6.5 },
}

-- The arena is a clearing in the Nature habitat's own colours, framed by
-- clumps of its trees (Assets.Habitats.Nature) - the fight happens somewhere
-- that belongs to the same world as the island.
local GRASS_COLOR = Color3.fromRGB(120, 178, 96)
local SAND_COLOR = Color3.fromRGB(224, 200, 146)
-- What closes the clearing off, from the back row to the bushes at the
-- player's feet: { what, x, z, scale }. "Clump" is the Nature habitat's own
-- tree union, the rest are the island's decorations, so the arena is built
-- out of pieces the player already knows. Nothing stands where a dragon does
-- (|x| 5 to 12, |z| under 7).
local DECOR = {
	{ "Clump", -23, -17, 1.15 }, { "TreeGreen", -15, -19, 1.2 }, { "Pine", -6, -20, 1.15 },
	{ "TreeAutumn", 6, -20, 1.2 }, { "TreeGreen", 15, -19, 1.1 }, { "Clump", 23, -17, 1.15 },
	-- The ones at the sides are the closest to the camera: kept small, or they
	-- eat the edges of the picture.
	{ "TreeMystic", -24, -8, 0.9 }, { "Pine", 24, -8, 0.95 },
	{ "TreeBlossom", -23, 4, 0.85 }, { "TreeAutumn", 23, 4, 0.9 },
	{ "Bush", -16, -13, 1.4 }, { "Bush", 16, -13, 1.4 },
	{ "Bush", -17, 1, 1.3 }, { "Bush", 17, 1, 1.3 },
	{ "FlowerBed", -15, 9, 1.3 }, { "FlowerBed", 15, 9, 1.3 },
	{ "FlowerBed", 0, -13, 1.2 }, { "Bush", -7, -14, 1.2 }, { "Bush", 7, -14, 1.2 },
	{ "Bush", -11, 11, 1.3 }, { "Bush", 11, 11, 1.3 },
	{ "Lantern", -13, -9, 1.1 }, { "Lantern", 13, -9, 1.1 },
}
local HEALTH_COLOR = Color3.fromRGB(104, 196, 112)
local HEALTH_LOW = Color3.fromRGB(214, 88, 76)
local SHIELD_COLOR = Color3.fromRGB(120, 180, 236)
local STRONG_COLOR = Color3.fromRGB(240, 196, 92)
local WEAK_COLOR = Color3.fromRGB(150, 155, 166)
local PREVIEW_COLOR = Color3.fromRGB(246, 214, 86) -- what a skill would take off, or put back
local MARKER_COLOR = Color3.fromRGB(250, 206, 84) -- the ring under whoever is acting
local ALLY_OUTLINE = Color3.fromRGB(104, 206, 118)
local ENEMY_OUTLINE = Color3.fromRGB(224, 92, 84)
local WHITE = Color3.new(1, 1, 1)

local DIMMED = 0.78 -- how see-through a dragon the skill cannot reach becomes
local DEAD = 0.75
local EVENT_GAP = 0.3 -- seconds between two things happening on screen
local STRIPPED_CLASSES = { "LuaSourceContainer", "Sound", "Highlight", "LayerCollector" }

local gui, root
local scales = {}
local stage = nil -- the arena and the dragons in the world
local cards = {} -- [key] = what the server said about that dragon
local state = {} -- [key] = its Health, shield and statuses
local bars = {} -- [key] = the widgets under it, and its tap area
local callbacks = {}
local isOpen = false
local hiddenGuis = {}
local queue = {} -- pushes waiting to be played
local playing = false
local turn = nil -- the turn being asked of the player
local turnDeadline = nil -- when the server stops waiting for an answer
local aiming = nil -- the skill picked, waiting for its target
local actionBar, actionButtons, promptLabel, skillLine, backButton, roundLabel, logLabel, timerLabel
local turnStrip, turnSlots
local renderTurnStrip -- written further down, used while the fight plays
local resultCard, resultParts
local renderOverlay

------------------------------------------------------------------ helpers

local function otherTeam(team)
	return team == "A" and "B" or "A"
end

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

-- A copy of a piece of the island, stripped of anything that would run or
-- react, ready to stand in the arena.
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

-- Every part of a dragon, whether it is a rig or a placeholder ball.
local function partsOf(entry)
	if not entry or not entry.model then
		return {}
	end
	if entry.model:IsA("BasePart") then
		return { entry.model }
	end
	local list = {}
	for _, part in ipairs(entry.model:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(list, part)
		end
	end
	return list
end

local function setTransparency(key, value)
	for _, part in ipairs(partsOf(stage and stage.fighters[key])) do
		part.Transparency = value
	end
end

------------------------------------------------------------------ the arena

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

-- Everything standing around the clearing. A decoration is a flat root Part
-- with its Visual inside, so it travels as a whole: wrap it, pivot it by its
-- base, scale it, drop it on the ground.
local function placeDecor(folder, template, point, scale, yaw, noShadow)
	local clone = template:Clone()
	prepareClone(clone)
	if noShadow then
		for _, part in ipairs(clone:IsA("BasePart") and { clone } or {}) do
			part.CastShadow = false
		end
	end
	local holder = Instance.new("Model")
	clone.Parent = holder
	holder.WorldPivot = CFrame.new(clone.Position - Vector3.new(0, clone.Size.Y / 2, 0))
	holder:ScaleTo(scale)
	holder:PivotTo(CFrame.new(point) * CFrame.Angles(0, yaw, 0))
	for _, child in ipairs(holder:GetChildren()) do
		child.Parent = folder
	end
	holder:Destroy()
end

local function plantDecor(folder)
	local assets = ReplicatedStorage.Wyrmhaven:FindFirstChild("Assets")
	local decorations = assets and assets:FindFirstChild("Decorations")
	local habitats = assets and assets:FindFirstChild("Habitats")
	local nature = habitats and habitats:FindFirstChild("Nature")
	local visual = nature and nature:FindFirstChild("Visual")
	local clump = visual and visual:FindFirstChild("Trees")
	local rng = Random.new(2609)
	for _, entry in ipairs(DECOR) do
		local name, x, z, scale = entry[1], entry[2], entry[3], entry[4]
		local template = name == "Clump" and clump or (decorations and decorations:FindFirstChild(name))
		if template then
			placeDecor(folder, template, STAGE_ORIGIN + Vector3.new(x, GROUND_TOP, z),
				scale * rng:NextNumber(0.92, 1.12), rng:NextNumber(0, math.pi * 2), name == "Clump")
		end
	end
end

local function spotOf(team, slot)
	local spot = SPOTS[slot] or SPOTS[#SPOTS]
	local side = team == "A" and -1 or 1
	return STAGE_ORIGIN + Vector3.new(spot.x * side, GROUND_TOP, spot.z)
end

-- One dragon on its spot, turned to face the other team.
local function placeFighter(card, slot)
	local feet = spotOf(card.team, slot)
	-- A model faces -Z; a quarter turn puts it side on, looking across.
	local yaw = card.team == "A" and math.rad(-90) or math.rad(90)
	local pivot = CFrame.new(feet) * CFrame.Angles(0, yaw, 0)
	local entry = { key = card.key, pivot = pivot, feet = feet }
	local template = DragonModels.Get(card.species, "Adult")
	if template then
		local rig = DragonRig.new(template)
		rig:Apply(pivot, rig:Pose(os.clock(), 0, 0))
		entry.rig = rig
		entry.model = rig.model
		if card.scale and card.scale ~= 1 then
			local holder = Instance.new("Model")
			entry.model.Parent = holder
			holder.WorldPivot = CFrame.new(feet)
			holder:ScaleTo(card.scale)
			entry.model.Parent = stage.folder
			holder:Destroy()
		end
	else
		local def = DragonDefs[card.species]
		local size = (def and def.StageSizes.Adult or Vector3.new(6, 6, 8)) * (card.scale or 1)
		local diameter = math.min(size.X, size.Y, size.Z)
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * diameter
		ball.Color = card.color or WEAK_COLOR
		ball.Material = Enum.Material.SmoothPlastic
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		ball.CFrame = CFrame.new(feet + Vector3.new(0, diameter / 2, 0))
		entry.model = ball
	end
	entry.model.Parent = stage.folder
	entry.middle = feet + Vector3.new(0, 3 * (card.scale or 1), 0)
	return entry
end

local function buildStage(fighters)
	destroyStage()
	local folder = Instance.new("Folder")
	folder.Name = "BattleStage"
	stage = { folder = folder, connections = {}, fighters = {} }

	-- Grass out to well past the edges of the screen, the fighting floor in
	-- the middle, then the trees that frame it.
	-- Grass out past every edge of the screen, and nothing drawn on it: the
	-- dragons stand in a clearing, not in a ring.
	disc(folder, STAGE_ORIGIN, 150, 110, 4, GROUND_TOP, GRASS_COLOR)
	plantDecor(folder)
	folder.Parent = Workspace

	-- The ring that says whose turn it is, moved under each dragon in turn.
	stage.marker = disc(folder, STAGE_ORIGIN + Vector3.new(0, 0, 200), 9, 9, 0.3, GROUND_TOP + 0.08, MARKER_COLOR)
	stage.marker.Transparency = 1
	stage.marker.Material = Enum.Material.Neon

	local slots = { A = 0, B = 0 }
	for _, card in ipairs(fighters) do
		slots[card.team] += 1
		stage.fighters[card.key] = placeFighter(card, slots[card.team])
	end

	-- A short, wide window sees less from top to bottom: widen the field of
	-- view so the whole arena stays on screen whatever shape the window is.
	local function holdCamera()
		local viewport = Workspace.CurrentCamera.ViewportSize
		local aspect = viewport.Y > 0 and viewport.X / viewport.Y or 16 / 9
		local fov = CAMERA_FOV * math.clamp(aspect / (16 / 9), 0.95, 1.3)
		CameraController.Hold(CFrame.lookAt(STAGE_ORIGIN + CAMERA_OFFSET, STAGE_ORIGIN + CAMERA_LOOK), fov)
	end
	holdCamera()
	table.insert(stage.connections, Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(holdCamera))
	table.insert(stage.connections, RunService.RenderStepped:Connect(function()
		renderOverlay()
	end))
end

-- The ring on the ground under the dragon taking its turn.
local function setActiveMarker(key)
	if not stage or not stage.marker then
		return
	end
	local entry = key and stage.fighters[key]
	if not entry then
		stage.marker.Transparency = 1
		return
	end
	local card = cards[key]
	local width = 8 * ((card and card.scale) or 1)
	stage.marker.Size = Vector3.new(0.3, width, width)
	stage.marker.CFrame = CFrame.new(entry.feet + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	stage.marker.Transparency = 0.45
end

-- A step toward the enemy and back, so it is clear who is acting.
local function lunge(key)
	local entry = stage and stage.fighters[key]
	if not entry or not entry.model then
		return
	end
	local card = cards[key]
	local forward = (card and card.team == "A") and 1 or -1
	local start = entry.model:IsA("Model") and entry.model:GetPivot() or entry.model.CFrame
	local moved = start + Vector3.new(forward * 3, 0, 0)
	task.spawn(function()
		for _, target in ipairs({ moved, start }) do
			if entry.model and entry.model.Parent then
				if entry.model:IsA("Model") then
					entry.model:PivotTo(target)
				else
					entry.model.CFrame = target
				end
			end
			task.wait(0.12)
		end
	end)
end

-- A number (or a word) floating up from a dragon.
local function floatText(key, text, color)
	local entry = stage and stage.fighters[key]
	if not entry or not root then
		return
	end
	local label = UIKit.text(root, {
		Name = "Float",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(200, 40),
		Text = text,
		TextSize = 28,
		TextColor3 = color or WHITE,
		Outline = UITheme.Colors.TextShadow,
		OutlineThickness = 2.5,
		ZIndex = 8,
	})
	local camera = Workspace.CurrentCamera
	local point = camera:WorldToViewportPoint(entry.middle + Vector3.new(0, 3, 0))
	label.Position = UDim2.fromOffset(point.X, point.Y)
	TweenService:Create(label, TweenInfo.new(0.9), {
		Position = UDim2.fromOffset(point.X, point.Y - 60),
		TextTransparency = 1,
	}):Play()
	task.delay(1, function()
		label:Destroy()
	end)
end

------------------------------------------------------------------ health bars and tap areas

local function createBar(key)
	local card = cards[key]
	-- The bar hangs under the dragon, as in the reference.
	local holder = UIKit.new("Frame", {
		Name = "Bar" .. key,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(148, 50),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
		Parent = root,
	})
	local scale = UIKit.new("UIScale", { Scale = scales[1] and scales[1].Scale or 1, Parent = holder })
	table.insert(scales, scale)
	local name = UIKit.text(holder, {
		Name = "Name",
		Size = UDim2.new(1, 0, 0, 18),
		Text = string.format("%s  Lv %d", card.name, card.level or 1),
		TextSize = 15,
		TextColor3 = card.boss and STRONG_COLOR or WHITE,
		Outline = UITheme.Colors.TextShadow,
		OutlineThickness = 1.5,
		ZIndex = 3,
	})
	local track = UIKit.new("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(0, 19),
		Size = UDim2.new(1, 0, 0, 15),
		BackgroundColor3 = UITheme.Colors.BarTrack,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = holder,
	})
	UIKit.corner(track, UDim.new(1, 0))
	UIKit.stroke(track, UITheme.Colors.TextShadow, 1.5)
	local fill = UIKit.new("Frame", {
		Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = HEALTH_COLOR,
		BorderSizePixel = 0, ZIndex = 3, Parent = track,
	})
	UIKit.corner(fill, UDim.new(1, 0))
	local shield = UIKit.new("Frame", {
		Name = "Shield", Size = UDim2.fromScale(0, 1), BackgroundColor3 = SHIELD_COLOR,
		BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 4, Parent = track,
	})
	UIKit.corner(shield, UDim.new(1, 0))
	-- The slice a skill would take off (or put back), while a target is being
	-- chosen.
	local preview = UIKit.new("Frame", {
		Name = "Preview", Size = UDim2.fromScale(0, 1), BackgroundColor3 = PREVIEW_COLOR,
		BorderSizePixel = 0, Visible = false, ZIndex = 5, Parent = track,
	})
	UIKit.corner(preview, UDim.new(1, 0))
	-- How much Health is left, in plain numbers.
	local amount = UIKit.text(track, {
		Name = "Amount", Size = UDim2.fromScale(1, 1), TextSize = 12, TextColor3 = WHITE,
		Outline = UITheme.Colors.TextShadow, OutlineThickness = 1.5, ZIndex = 6,
	})
	local statuses = UIKit.text(holder, {
		Name = "Statuses", Position = UDim2.fromOffset(0, 35), Size = UDim2.new(1, 0, 0, 16), TextSize = 13,
		TextColor3 = UITheme.Colors.Accent, Outline = UITheme.Colors.TextShadow, OutlineThickness = 1.5, ZIndex = 3,
	})

	-- What the element would do to it, shown only while aiming.
	local hint = UIKit.text(root, {
		Name = "Hint" .. key, AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(180, 26), TextSize = 19,
		TextColor3 = STRONG_COLOR, Outline = UITheme.Colors.TextShadow, OutlineThickness = 2,
		Visible = false, ZIndex = 7,
	})
	table.insert(scales, UIKit.new("UIScale", { Scale = scale.Scale, Parent = hint }))

	-- The dragon itself is the button while a target is being chosen: a clear
	-- patch over it, so a tap never misses the way a raycast can.
	local tap = UIKit.new("TextButton", {
		Name = "Tap" .. key, Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(150, 150), Visible = false, ZIndex = 6, Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Scale = scale.Scale, Parent = tap }))
	tap.Activated:Connect(function()
		BattleScreen._tapped(key)
	end)

	return { holder = holder, fill = fill, shield = shield, preview = preview, amount = amount,
		statuses = statuses, name = name, scale = scale, hint = hint, tap = tap }
end

-- Paints the slice a skill would remove (at the end of what is left) or add
-- (just past it) in yellow.
local function setPreview(key, damage, heal)
	local bar, live = bars[key], state[key]
	if not bar or not live or live.maxHealth <= 0 then
		return
	end
	local share = math.clamp(live.health / live.maxHealth, 0, 1)
	if damage and damage > 0 then
		local lost = math.clamp(damage / live.maxHealth, 0, share)
		bar.preview.Position = UDim2.fromScale(share - lost, 0)
		bar.preview.Size = UDim2.fromScale(lost, 1)
		bar.preview.Visible = true
	elseif heal and heal > 0 then
		local gain = math.clamp(heal / live.maxHealth, 0, 1 - share)
		bar.preview.Position = UDim2.fromScale(share, 0)
		bar.preview.Size = UDim2.fromScale(gain, 1)
		bar.preview.Visible = true
	else
		bar.preview.Visible = false
	end
end

-- Each status is named and its numbers are fixed (Config/StatusDefs), so the
-- name and its turns left say everything - no "-15% Attack" to read mid-fight.
-- These are the labels the icons will replace.

local function refreshBar(key)
	local bar, live = bars[key], state[key]
	if not bar or not live then
		return
	end
	local share = live.maxHealth > 0 and math.clamp(live.health / live.maxHealth, 0, 1) or 0
	UIKit.tween(bar.fill, TweenInfo.new(0.25), { Size = UDim2.fromScale(share, 1) })
	bar.fill.BackgroundColor3 = share <= 0.3 and HEALTH_LOW or HEALTH_COLOR
	local shieldShare = live.maxHealth > 0 and math.clamp(live.shield / live.maxHealth, 0, 1) or 0
	bar.shield.Size = UDim2.fromScale(shieldShare, 1)
	-- (a Stun, Freeze or Sleep is in the list like any other status)
	local parts = {}
	for _, status in ipairs(live.statuses or {}) do
		local def = StatusDefs.Get(status.id)
		local label = (def and def.DisplayName) or status.id or status.kind
		table.insert(parts, string.format("%s %d", label, status.turns or 1))
	end
	bar.statuses.Text = table.concat(parts, "  ")
	bar.amount.Text = string.format("%d / %d", math.max(0, live.health), live.maxHealth)
	bar.name.TextTransparency = live.alive and 0 or 0.55
	bar.fill.BackgroundTransparency = live.alive and 0 or 0.6
	if not live.alive then
		setTransparency(key, DEAD)
	end
end

-- Every frame: the bars sit under their dragon, the tap areas over it.
function renderOverlay()
	if not stage or not isOpen then
		return
	end
	local camera = Workspace.CurrentCamera
	for key, bar in pairs(bars) do
		local entry = stage.fighters[key]
		if entry then
			local feet, onScreen = camera:WorldToViewportPoint(entry.feet)
			bar.holder.Visible = onScreen
			bar.holder.Position = UDim2.fromOffset(feet.X, feet.Y + 6)
			local middle = camera:WorldToViewportPoint(entry.middle)
			bar.tap.Position = UDim2.fromOffset(middle.X, middle.Y)
			local above = camera:WorldToViewportPoint(entry.middle + Vector3.new(0, 4.5, 0))
			bar.hint.Position = UDim2.fromOffset(above.X, above.Y)
		end
	end
	-- The clock on the player's turn: when it runs out the server takes it.
	if turn and turnDeadline then
		local left = math.max(0, turnDeadline - os.clock())
		timerLabel.Text = string.format("%d s", math.ceil(left))
		timerLabel.TextColor3 = left <= 10 and HEALTH_LOW or UITheme.Colors.TextMuted
	else
		timerLabel.Text = ""
	end
end

------------------------------------------------------------------ choosing a skill, then a target

-- Who a skill would land on. The server hands the legal list for skills that
-- hit one dragon; the rest follows from the skill's target.
local function targetsFor(action)
	local actorKey = turn and turn.actorKey
	local actor = actorKey and cards[actorKey]
	if not actor then
		return {}
	end
	local kind = action.target
	if kind == "Enemy" or kind == "Ally" then
		local keys = {}
		for _, entry in ipairs(action.targets or {}) do
			table.insert(keys, entry.key)
		end
		return keys
	end
	if kind == "Self" then
		return { actorKey }
	end
	local wanted = (kind == "AllEnemies") and otherTeam(actor.team) or actor.team
	local keys = {}
	for key, card in pairs(cards) do
		local live = state[key]
		if card.team == wanted and live and live.alive then
			table.insert(keys, key)
		end
	end
	if kind == "WeakestAlly" then
		local weakest, share = nil, math.huge
		for _, key in ipairs(keys) do
			local live = state[key]
			local value = live.maxHealth > 0 and live.health / live.maxHealth or 1
			if value < share then
				weakest, share = key, value
			end
		end
		return weakest and { weakest } or {}
	end
	return keys
end

local function clearAiming()
	aiming = nil
	for key, bar in pairs(bars) do
		bar.tap.Visible = false
		bar.hint.Visible = false
		bar.preview.Visible = false
		local live = state[key]
		setTransparency(key, (live and not live.alive) and DEAD or 0)
	end
	if backButton then
		backButton.Visible = false
	end
	if skillLine then
		skillLine.Text = ""
	end
end

local function renderActions()
	if not turn then
		actionBar.Visible = false
		return
	end
	actionBar.Visible = true
	local actor = cards[turn.actorKey]
	if aiming then
		promptLabel.Text = "SELECT TARGET"
	else
		promptLabel.Text = actor and string.format("SELECT SKILL  -  %s", string.upper(actor.name)) or "SELECT SKILL"
	end
	for index, button in ipairs(actionButtons) do
		local action = turn.actions[index]
		button.holder.Visible = action ~= nil
		if action then
			local element = UITheme.GetElement(action.element)
			button.name.Text = action.name
			UIKit.setElementBadge(button.element, action.element)
			button.element.ImageTransparency = action.ready and 0 or 0.5
			button.cooldown.Visible = not action.ready
			button.cooldown.Text = action.turnsLeft and string.format("%d", action.turnsLeft) or ""
			button.name.TextTransparency = action.ready and 0 or 0.45
			local picked = aiming ~= nil and aiming.action.skill == action.skill
			button.button.BackgroundColor3 = action.ready and (picked and element.Dark or UITheme.Colors.SurfaceRaised) or UITheme.Colors.Surface
			button.stroke.Color = picked and WHITE or (action.ready and element.Main or UITheme.Colors.SurfaceStroke)
			button.stroke.Thickness = picked and 3 or 2
		end
	end
end

local function sendAction(skillId, targetKey)
	if not turn then
		return
	end
	local token = turn.token
	turn = nil
	turnDeadline = nil
	clearAiming()
	actionBar.Visible = false
	if callbacks.onAction then
		callbacks.onAction(token, skillId, targetKey)
	end
end

-- Step two: show what the skill does, light up what it can land on and turn
-- everything else see-through.
local function startAiming(action)
	local keys = targetsFor(action)
	if #keys == 0 then
		return
	end
	aiming = { action = action, keys = keys }
	skillLine.Text = action.description or ""
	backButton.Visible = true
	local allowed = {}
	for _, key in ipairs(keys) do
		allowed[key] = true
	end
	-- What the server says the skill would do to each dragon it can reach.
	local numbers = {}
	for _, entry in ipairs(action.targets or {}) do
		numbers[entry.key] = entry
	end
	for key, bar in pairs(bars) do
		local live = state[key]
		local dead = live and not live.alive
		bar.tap.Visible = allowed[key] == true
		setTransparency(key, allowed[key] and (dead and DEAD or 0) or DIMMED)
		local entry = allowed[key] and numbers[key] or nil
		local card = cards[key]
		local factor = entry and entry.factor
			or ((allowed[key] and card and action.element) and ElementChart.Factor(action.element, card.elements) or 1)
		local label = action.target ~= "Self" and ElementChart.Label(factor) or nil
		bar.hint.Visible = allowed[key] == true and label ~= nil
		bar.hint.Text = label and string.format("%s  x%.1f", string.upper(label), factor) or ""
		bar.hint.TextColor3 = label == "Strong" and STRONG_COLOR or WEAK_COLOR
		if allowed[key] then
			setPreview(key, entry and entry.damage, entry and entry.heal)
		else
			bar.preview.Visible = false
		end
	end
	renderActions()
end

function BattleScreen._tapped(key)
	if not turn or not aiming then
		return
	end
	if not table.find(aiming.keys, key) then
		return
	end
	sendAction(aiming.action.skill, key)
end

local function pickSkill(index)
	if not turn or aiming then
		return
	end
	local action = turn.actions[index]
	if not action or not action.ready then
		return
	end
	startAiming(action)
end

------------------------------------------------------------------ playing what happened

local function playEvent(event)
	if event.t == "round" then
		roundLabel.Text = "Round " .. event.round
		return 0.1
	elseif event.t == "skill" then
		logLabel.Text = string.format("%s uses %s", event.name, event.skillName)
		lunge(event.actor)
		return EVENT_GAP
	elseif event.t == "damage" then
		local text = "-" .. event.amount
		if event.effectiveness == "Strong" then
			text ..= "  Strong!"
		elseif event.effectiveness == "Resisted" then
			text ..= "  Resisted"
		end
		floatText(event.target, text, event.effectiveness == "Strong" and STRONG_COLOR or HEALTH_LOW)
		return EVENT_GAP * 0.7
	elseif event.t == "heal" then
		floatText(event.target, "+" .. event.amount, HEALTH_COLOR)
		return EVENT_GAP * 0.7
	elseif event.t == "shield" then
		floatText(event.target, "shield " .. event.amount, SHIELD_COLOR)
		return EVENT_GAP * 0.6
	elseif event.t == "burn" then
		floatText(event.target, "-" .. event.amount, Color3.fromRGB(240, 140, 80))
		return EVENT_GAP * 0.6
	elseif event.t == "status" then
		local text = event.kind
		if event.stat then
			text = string.format("%s%s %s", event.kind == "Buff" and "+" or "-", math.round((event.amount or 0) * 100) .. "%", event.stat)
		end
		floatText(event.target, text, event.kind == "Buff" and HEALTH_COLOR or WEAK_COLOR)
		return EVENT_GAP * 0.5
	elseif event.t == "cleanse" then
		floatText(event.target, "cleansed", SHIELD_COLOR)
		return EVENT_GAP * 0.5
	elseif event.t == "miss" then
		floatText(event.target, event.reason == "Evade" and "dodged" or "missed", WEAK_COLOR)
		return EVENT_GAP * 0.5
	elseif event.t == "stunned" then
		local held = ({ Freeze = "frozen", Sleep = "asleep" })[event.status or ""] or "stunned"
		logLabel.Text = string.format("%s is %s", event.name, held)
		floatText(event.actor, held, WEAK_COLOR)
		return EVENT_GAP
	elseif event.t == "confused" then
		logLabel.Text = string.format("%s is confused", event.name)
		floatText(event.actor, "confused", WEAK_COLOR)
		return EVENT_GAP * 0.5
	elseif event.t == "immune" then
		floatText(event.target, "immune", SHIELD_COLOR)
		return EVENT_GAP * 0.5
	elseif event.t == "wake" then
		floatText(event.target, "woke up", SHIELD_COLOR)
		return EVENT_GAP * 0.5
	elseif event.t == "thaw" then
		floatText(event.target, "thawed", SHIELD_COLOR)
		return EVENT_GAP * 0.5
	elseif event.t == "revive" then
		logLabel.Text = string.format("%s gets back up", event.name)
		floatText(event.target, "revived", HEALTH_COLOR)
		return EVENT_GAP
	elseif event.t == "pass" then
		logLabel.Text = string.format("%s has nothing ready", event.name)
		return EVENT_GAP * 0.6
	elseif event.t == "death" then
		logLabel.Text = string.format("%s goes down", event.name)
		floatText(event.target, "down", HEALTH_LOW)
		return EVENT_GAP
	end
	return 0
end

local function applyState(list)
	for _, live in ipairs(list or {}) do
		state[live.key] = live
		refreshBar(live.key)
	end
end

local function playQueue()
	if playing then
		return
	end
	playing = true
	task.spawn(function()
		while #queue > 0 do
			local push = table.remove(queue, 1)
			for _, event in ipairs(push.events or {}) do
				local wait = playEvent(event)
				if wait > 0 then
					task.wait(wait)
				end
			end
			applyState(push.fighters)
			if push.upcoming then
				renderTurnStrip(push.upcoming)
			end
			setActiveMarker(push.actorKey)
			if push.finish then
				BattleScreen._showResult(push.finish)
			elseif push.yourTurn then
				turn = push
				turnDeadline = push.secondsLeft and (os.clock() + push.secondsLeft) or nil
				clearAiming()
				renderActions()
			else
				turn = nil
				clearAiming()
				renderActions()
			end
		end
		playing = false
	end)
end

------------------------------------------------------------------ the screen

-- The strip at the top: the next few dragons to act, in order, ringed green
-- when they are ours and red when they are not.
local function createTurnStrip()
	local colors = UITheme.Colors
	turnStrip = UIKit.new("Frame", {
		Name = "TurnOrder", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(268, 64), BackgroundColor3 = colors.Surface, BackgroundTransparency = 0.1,
		Visible = false, ZIndex = 4, Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = turnStrip }))
	UIKit.corner(turnStrip, UDim.new(0, 14))
	UIKit.stroke(turnStrip, colors.SurfaceStroke, 2)
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8), Parent = turnStrip,
	})
	turnSlots = {}
	for index = 1, 4 do
		local slot = UIKit.new("Frame", {
			Name = "Next" .. index, Size = UDim2.fromOffset(48, 48), BackgroundColor3 = colors.SurfaceRaised,
			LayoutOrder = index, Visible = false, ZIndex = 4, Parent = turnStrip,
		})
		UIKit.corner(slot, UDim.new(1, 0))
		local stroke = UIKit.stroke(slot, ALLY_OUTLINE, 3)
		-- The head goes in when the slot first shows that species (UIKit.dragonHead).
		table.insert(turnSlots, { frame = slot, stroke = stroke, species = nil, portrait = nil })
	end
end

function renderTurnStrip(keys)
	if not turnStrip then
		return
	end
	keys = keys or {}
	turnStrip.Visible = #keys > 0
	for index, slot in ipairs(turnSlots) do
		local card = cards[keys[index]]
		slot.frame.Visible = card ~= nil
		if card then
			slot.frame.BackgroundColor3 = card.color or UITheme.Colors.SurfaceRaised
			slot.stroke.Color = card.team == "A" and ALLY_OUTLINE or ENEMY_OUTLINE
			-- The one acting now sits leftmost, with a thicker ring.
			slot.stroke.Thickness = index == 1 and 4 or 3
			slot.frame.Size = UDim2.fromOffset(index == 1 and 54 or 48, index == 1 and 54 or 48)
			if slot.species ~= card.species then
				if slot.portrait then
					slot.portrait:Destroy()
				end
				slot.portrait = UIKit.dragonHead(slot.frame, card.species, 46, card.color, {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 5,
				})
				slot.species = card.species
			end
		end
	end
end

local function createResultCard()
	local colors = UITheme.Colors
	resultParts = {}
	resultCard = UIKit.new("Frame", {
		Name = "Result", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 300), BackgroundColor3 = colors.Surface, Visible = false, ZIndex = 12, Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = resultCard }))
	UIKit.corner(resultCard, UDim.new(0, 18))
	UIKit.stroke(resultCard, colors.SurfaceStroke, 2)
	resultParts.title = UIKit.text(resultCard, {
		Name = "Title", Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 40), TextSize = 34, ZIndex = 12,
	})
	resultParts.subtitle = UIKit.text(resultCard, {
		Name = "Subtitle", Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 26), TextSize = 19,
		TextColor3 = colors.TextMuted, ZIndex = 12,
	})
	resultParts.rewards = UIKit.text(resultCard, {
		Name = "Rewards", Position = UDim2.fromOffset(0, 112), Size = UDim2.new(1, 0, 0, 78), TextSize = 22,
		TextColor3 = colors.Accent, ZIndex = 12,
	})
	local holder = UIKit.new("Frame", {
		Name = "ButtonHolder", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(220, 52), BackgroundTransparency = 1, ZIndex = 12, Parent = resultCard,
	})
	local button = UIKit.button(holder, { Name = "Continue", Variant = "Confirm", Text = "Continue", TextSize = 24 })
	button.OnActivated(function()
		BattleScreen.Close()
	end)
end

local function createActionBar()
	local colors = UITheme.Colors
	actionBar = UIKit.new("Frame", {
		Name = "ActionBar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(940, 142), BackgroundColor3 = colors.Surface, BackgroundTransparency = 0.06,
		Visible = false, ZIndex = 5, Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = actionBar }))
	UIKit.corner(actionBar, UDim.new(0, 18))
	UIKit.stroke(actionBar, colors.SurfaceStroke, 2)
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = actionBar,
	})

	-- "SELECT SKILL", then "SELECT TARGET" with the skill's own line under it.
	promptLabel = UIKit.text(actionBar, {
		Name = "Prompt", Size = UDim2.new(1, 0, 0, 20), Text = "SELECT SKILL", TextSize = 18,
		TextColor3 = colors.TextLight, ZIndex = 5,
	})
	timerLabel = UIKit.text(actionBar, {
		Name = "Timer", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(120, 20),
		TextSize = 17, TextColor3 = colors.TextMuted, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5,
	})
	-- The skill's own line, right under the prompt once it has been picked.
	skillLine = UIKit.text(actionBar, {
		Name = "SkillLine", Position = UDim2.fromOffset(0, 21),
		Size = UDim2.new(1, 0, 0, 18), TextSize = 15, TextColor3 = colors.TextMuted, ZIndex = 5,
	})

	local row = UIKit.new("Frame", {
		Name = "Skills", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46),
		Size = UDim2.new(1, -80, 0, 64), BackgroundTransparency = 1, ZIndex = 5, Parent = actionBar,
	})
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12), Parent = row,
	})
	actionButtons = {}
	for index = 1, 3 do
		local holder = UIKit.new("Frame", {
			Name = "Skill" .. index, Size = UDim2.fromOffset(268, 64), BackgroundTransparency = 1,
			LayoutOrder = index, ZIndex = 5, Parent = row,
		})
		local button = UIKit.new("TextButton", {
			Name = "Button", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = colors.SurfaceRaised, ZIndex = 5, Parent = holder,
		})
		UIKit.corner(button, UDim.new(0, 14))
		local stroke = UIKit.stroke(button, colors.SurfaceStroke, 2)
		UIKit.pressable(button)
		local element = UIKit.elementBadge(button, "Fire", 40, {
			Name = "Element", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), ZIndex = 6,
		})
		local name = UIKit.text(button, {
			Name = "Name", Position = UDim2.fromOffset(58, 0), Size = UDim2.new(1, -70, 1, 0), TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6,
		})
		local cooldown = UIKit.text(button, {
			Name = "Cooldown", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(40, 28), TextSize = 20, TextColor3 = colors.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Right, Visible = false, ZIndex = 6,
		})
		button.Activated:Connect(function()
			pickSkill(index)
		end)
		table.insert(actionButtons, { holder = holder, button = button, stroke = stroke, name = name, element = element, cooldown = cooldown })
	end

	-- Back to the skills, when a target has been asked for.
	local backHolder = UIKit.new("Frame", {
		Name = "BackHolder", Position = UDim2.fromOffset(0, 46),
		Size = UDim2.fromOffset(56, 64), BackgroundTransparency = 1, ZIndex = 6, Parent = actionBar,
	})
	backButton = UIKit.new("TextButton", {
		Name = "Back", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.SurfaceRaised, Visible = false, ZIndex = 6, Parent = backHolder,
	})
	UIKit.corner(backButton, UDim.new(0, 14))
	UIKit.stroke(backButton, colors.SurfaceStroke, 2)
	UIKit.pressable(backButton)
	UIKit.icon(backButton, "Back", 30, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 7 })
	backButton.Activated:Connect(function()
		clearAiming()
		renderActions()
	end)
end

local function createScreen()
	local colors = UITheme.Colors
	gui = UIKit.new("ScreenGui", {
		Name = "BattleGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 25,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	root = UIKit.new("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })

	-- Top left, clear of the dragons and their bars.
	local header = UIKit.new("Frame", {
		Name = "Header", Position = UDim2.fromOffset(26, 18), Size = UDim2.fromOffset(560, 60),
		BackgroundTransparency = 1, Parent = root,
	})
	table.insert(scales, UIKit.new("UIScale", { Parent = header }))
	roundLabel = UIKit.text(header, {
		Name = "Round", Size = UDim2.new(1, 0, 0, 30), Text = "Round 1", TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = colors.TextLight, Outline = colors.TextShadow, OutlineThickness = 2,
	})
	logLabel = UIKit.text(header, {
		Name = "Log", Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 26), TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = colors.Accent, Outline = colors.TextShadow, OutlineThickness = 1.5,
	})

	createTurnStrip()
	createActionBar()
	createResultCard()
	UIKit.bindScreenScale(gui, scales, 1280, 720)
end

-- callbacks: onAction(token, skillId, targetKey), onClose()
function BattleScreen.Init(handlers)
	callbacks = handlers or {}
	if not gui then
		createScreen()
	end
end

function BattleScreen.IsOpen()
	return isOpen
end

local function dropBars()
	for _, bar in pairs(bars) do
		for _, object in ipairs({ bar.holder, bar.hint, bar.tap }) do
			local uiScale = object:FindFirstChildOfClass("UIScale")
			local index = uiScale and table.find(scales, uiScale)
			if index then
				table.remove(scales, index)
			end
			object:Destroy()
		end
	end
	table.clear(bars)
end

-- The fight begins: who is on the field, and the arena they stand in.
function BattleScreen.Start(info)
	if not gui then
		createScreen()
	end
	dropBars()
	table.clear(cards)
	table.clear(state)
	table.clear(queue)
	turn, aiming, playing = nil, nil, false

	for _, card in ipairs(info.fighters or {}) do
		cards[card.key] = card
	end
	isOpen = true
	gui.Enabled = true
	hideLowerGuis(true)
	resultCard.Visible = false
	actionBar.Visible = false
	renderTurnStrip(nil)
	roundLabel.Text = info.name or "Round 1"
	logLabel.Text = info.boss and "A boss is waiting for you." or ""
	buildStage(info.fighters or {})
	for key in pairs(cards) do
		bars[key] = createBar(key)
	end
	clearAiming()
	applyState(info.fighterState)
	renderOverlay()
	if info.events and #info.events > 0 then
		table.insert(queue, { events = info.events, fighters = info.fighterState })
		playQueue()
	end
end

-- One turn: what happened, and what this dragon can do if it is the player's.
function BattleScreen.Update(push)
	if not isOpen then
		return
	end
	table.insert(queue, push)
	playQueue()
end

function BattleScreen.Finish(result)
	if not isOpen then
		return
	end
	-- `fighterState` is how everyone ends: without it the last blows (a burn
	-- finishing a dragon off on its own turn, say) would play out and leave
	-- the dragon standing.
	table.insert(queue, { events = result.events, fighters = result.fighterState, finish = result })
	playQueue()
end

function BattleScreen._showResult(result)
	turn = nil
	clearAiming()
	actionBar.Visible = false
	-- Nobody is due to act any more.
	renderTurnStrip(nil)
	setActiveMarker(nil)
	resultParts.title.Text = result.won and "Victory" or "Defeat"
	resultParts.title.TextColor3 = result.won and STRONG_COLOR or HEALTH_LOW
	resultParts.subtitle.Text = string.format("%s  -  %d rounds", result.name or "", result.rounds or 0)
	if result.won then
		local rewards = result.rewards or {}
		resultParts.rewards.Text = string.format("+%s Coins\n+%s Food\n+%s XP",
			UIKit.formatNumber(rewards.Coins or 0), UIKit.formatNumber(rewards.Food or 0), UIKit.formatNumber(rewards.Xp or 0))
	else
		resultParts.rewards.Text = "Your dragons were beaten.\nFeed them a level, or bring other elements."
	end
	resultCard.Visible = true
end

function BattleScreen.Close()
	if not isOpen then
		return
	end
	isOpen = false
	turn, aiming = nil, nil
	table.clear(queue)
	renderTurnStrip(nil)
	destroyStage()
	dropBars()
	resultCard.Visible = false
	actionBar.Visible = false
	gui.Enabled = false
	hideLowerGuis(false)
	if callbacks.onClose then
		callbacks.onClose()
	end
end

return BattleScreen
