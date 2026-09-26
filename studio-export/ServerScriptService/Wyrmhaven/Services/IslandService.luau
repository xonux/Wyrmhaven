-- Everything on a player's island that isn't a building: the low-poly scenery
-- around the grass plate (sea, lagoon, beach, cliffs, the mountain at the back,
-- palms) and the obstacles covering its outer tiles (IslandObstacles). An
-- obstacle blocks its tiles until the player pays its Coin price, waits its
-- duration (or skips it with Gems) and gives it a final tap. One clearing at a
-- time, from the payment to that tap; its end time is absolute, so the wait
-- also runs while the player is away.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = ReplicatedStorage.Wyrmhaven.Config
local GameConstants = require(Config.GameConstants)
local ObstacleDefs = require(Config.ObstacleDefs)
local IslandObstacles = require(Config.IslandObstacles)
local GemSpeedUp = require(Config.GemSpeedUp)

local LevelService = require(script.Parent.LevelService)
local ReadyGlow = require(script.Parent.ReadyGlow)

local READY_GRACE_SECONDS = 1 -- a client countdown reaching zero a moment early still counts

local IslandService = {}

local HabitatService
local EconomyService
local HudService
local obstacleStatusUpdated

local HALF = GameConstants.GridTileSize * GameConstants.GridTilesPerSide / 2 -- grass plate half size
local GRASS_TOP = 3 -- IslandBase top (see HabitatService)
local SCENERY_SEED = 4242
local FADE_OUT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local COLORS = {
	Ocean = Color3.fromRGB(40, 122, 178),
	Lagoon = Color3.fromRGB(78, 198, 204),
	Foam = Color3.fromRGB(228, 246, 244),
	Sand = Color3.fromRGB(238, 216, 162),
	Cliff = Color3.fromRGB(134, 118, 100),
	CliffDark = Color3.fromRGB(106, 94, 82),
	Rock = Color3.fromRGB(146, 146, 140),
	RockDark = Color3.fromRGB(114, 114, 110),
	Snow = Color3.fromRGB(242, 246, 250),
	Moss = Color3.fromRGB(108, 164, 74),
	Trunk = Color3.fromRGB(118, 84, 56),
	PalmTrunk = Color3.fromRGB(156, 118, 78),
	PalmLeaf = Color3.fromRGB(96, 176, 78),
	Leaves = { Color3.fromRGB(72, 150, 64), Color3.fromRGB(92, 170, 72), Color3.fromRGB(58, 132, 70) },
}

local obstaclesById = {}
for _, obstacle in ipairs(IslandObstacles) do
	obstaclesById[obstacle.Id] = obstacle
end

-- [userId] = { cleared = { [id] = true }, models = { [id] = Model }, clearing = { id, readyAt } | nil }
local states = {}

function IslandService.Init(habitatServiceRef, economyServiceRef, hudServiceRef, remotesFolder)
	HabitatService = habitatServiceRef
	EconomyService = economyServiceRef
	HudService = hudServiceRef

	obstacleStatusUpdated = remotesFolder:FindFirstChild("ObstacleStatusUpdated")
	if not obstacleStatusUpdated then
		obstacleStatusUpdated = Instance.new("RemoteEvent")
		obstacleStatusUpdated.Name = "ObstacleStatusUpdated"
		obstacleStatusUpdated.Parent = remotesFolder
	end
end

-- Scenery pieces are never clicked (CanQuery off), so taps go through them to
-- the buildings and obstacles.
local function piece(parent, size, cframe, color, props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props and props.Shape then
		part.Shape = props.Shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Transparency = props and props.Transparency or 0
	part.CastShadow = not (props and props.NoShadow)
	part.Parent = parent
	return part
end

-- Flat round slab whose top is at topY.
local function disc(parent, x, z, topY, diameter, thickness, color)
	return piece(
		parent,
		Vector3.new(thickness, diameter, diameter),
		CFrame.new(x, topY - thickness / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		{ Shape = Enum.PartType.Cylinder, NoShadow = true }
	)
end

-- A block standing on (x, bottomY, z), turned by yaw and slightly tilted.
local function boulder(parent, x, bottomY, z, size, color, yaw, tiltX, tiltZ)
	local cframe = CFrame.new(x, bottomY + size.Y / 2, z)
		* CFrame.Angles(0, math.rad(yaw or 0), 0)
		* CFrame.Angles(math.rad(tiltX or 0), 0, math.rad(tiltZ or 0))
	return piece(parent, size, cframe, color)
end

local function palm(parent, x, z, groundY, random)
	local cframe = CFrame.new(x, groundY, z) * CFrame.Angles(0, math.rad(random:NextNumber(0, 360)), 0)
	for _ = 1, 4 do
		cframe *= CFrame.Angles(math.rad(7), 0, 0)
		piece(parent, Vector3.new(1.1, 2.5, 1.1), cframe * CFrame.new(0, 1.2, 0), COLORS.PalmTrunk)
		cframe *= CFrame.new(0, 2.4, 0)
	end
	local top = cframe.Position
	local start = random:NextNumber(0, 60)
	for k = 0, 5 do
		local leaf = CFrame.new(top)
			* CFrame.Angles(0, math.rad(start + k * 60), 0)
			* CFrame.Angles(math.rad(-20), 0, 0)
			* CFrame.new(0, 0, -2.6)
		piece(parent, Vector3.new(1.6, 0.35, 5.4), leaf, COLORS.PalmLeaf)
	end
end

-- Rocky rim along the grass plate's four edges, with a lower row of stones
-- where the cliff meets the beach.
local function cliffs(parent, cx, cz, random)
	for side = 0, 3 do
		for _, row in ipairs({
			{ out = { 1.6, 2.6 }, width = { 5, 8.5 }, depth = { 3.5, 5 }, top = { 3.2, 4 }, step = { 0.6, 0.85 } },
			{ out = { 5, 7.5 }, width = { 2.5, 4.5 }, depth = { 2.5, 4 }, top = { 1.6, 2.6 }, step = { 1.4, 2.6 } },
		}) do
			local along = -HALF - 3
			while along < HALF + 3 do
				local width = random:NextNumber(row.width[1], row.width[2])
				local depth = random:NextNumber(row.depth[1], row.depth[2])
				local top = random:NextNumber(row.top[1], row.top[2])
				local out = HALF + random:NextNumber(row.out[1], row.out[2])
				local lx, lz
				if side == 0 then
					lx, lz = along, -out
				elseif side == 1 then
					lx, lz = out, along
				elseif side == 2 then
					lx, lz = -along, out
				else
					lx, lz = -out, -along
				end
				local height = top + 0.6
				boulder(
					parent,
					cx + lx,
					top - height,
					cz + lz,
					Vector3.new(width, height, depth),
					random:NextNumber() < 0.5 and COLORS.Cliff or COLORS.CliffDark,
					side * 90 + random:NextNumber(-16, 16),
					random:NextNumber(-6, 6),
					random:NextNumber(-6, 6)
				)
				along += width * random:NextNumber(row.step[1], row.step[2])
			end
		end
	end
end

-- Snowy rock peaks rising from the beach behind the island's back edge (-Z,
-- the top of the screen).
local function mountain(parent, cx, cz)
	local function rock(dx, bottomY, dz, size, color, yaw, tiltX, tiltZ)
		return boulder(parent, cx + dx, bottomY, cz + dz, size, color, yaw, tiltX, tiltZ)
	end
	local function peak(dx, y, dz, size, color)
		-- A cube balanced on a corner reads as a sharp low-poly summit.
		piece(parent, Vector3.new(size, size, size), CFrame.new(cx + dx, y, cz + dz) * CFrame.Angles(math.rad(45), math.rad(20), math.rad(35.26)), color)
	end

	-- Main peak
	rock(24, 0, -84, Vector3.new(44, 12, 26), COLORS.Rock, 10, 0, 3)
	rock(8, 0, -80, Vector3.new(28, 9, 20), COLORS.RockDark, -24, 0, -4)
	rock(40, 0, -78, Vector3.new(22, 8, 18), COLORS.RockDark, 32, 4, 0)
	rock(24, 10, -86, Vector3.new(30, 11, 20), COLORS.RockDark, 38, 5, -4)
	rock(26, 19, -87, Vector3.new(19, 9, 15), COLORS.Rock, 62, -6, 6)
	rock(26, 26.5, -87, Vector3.new(16, 2.2, 13), COLORS.Snow, 62, -6, 6)
	peak(27, 31, -88, 10, COLORS.Snow)

	-- Smaller peak on its left
	rock(-12, 0, -82, Vector3.new(24, 10, 20), COLORS.Rock, -30, 0, 4)
	rock(-12, 8, -84, Vector3.new(15, 8, 13), COLORS.RockDark, 14, 5, -5)
	peak(-12, 17.5, -84, 7, COLORS.Snow)
end

local function buildScenery(islandModel, base)
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	local cx, cz = base.Position.X, base.Position.Z
	local random = Random.new(SCENERY_SEED)

	-- Deep sea, just above the place's default baseplate.
	piece(folder, Vector3.new(760, 1, 760), CFrame.new(cx, -0.1, cz), COLORS.Ocean, { NoShadow = true })

	-- Shallow lagoon, foam line, beach.
	for _, spot in ipairs({ { 0, 0, 240 }, { -44, 34, 196 }, { 48, -36, 190 } }) do
		disc(folder, cx + spot[1], cz + spot[2], 0.8, spot[3], 1, COLORS.Lagoon)
	end
	local beach = { { 0, 4, 186 }, { -18, 30, 158 }, { 30, -22, 150 }, { -52, -30, 108 } }
	for _, spot in ipairs(beach) do
		disc(folder, cx + spot[1], cz + spot[2], 1.05, spot[3] + 4, 0.4, COLORS.Foam)
	end
	for _, spot in ipairs(beach) do
		disc(folder, cx + spot[1], cz + spot[2], 1.3, spot[3], 0.8, COLORS.Sand)
	end

	-- Rock under the grass plate's edge, then the rim.
	piece(folder, Vector3.new(HALF * 2 + 3, 2.6, HALF * 2 + 3), CFrame.new(cx, GRASS_TOP - 0.1 - 1.3, cz), COLORS.CliffDark)
	cliffs(folder, cx, cz, random)
	mountain(folder, cx, cz)

	for _, spot in ipairs({ { -80, 38 }, { 70, 52 }, { 18, 80 }, { -30, 82 }, { -76, -48 }, { 82, 10 } }) do
		palm(folder, cx + spot[1], cz + spot[2], 1.3, random)
	end

	-- Stones in the lagoon.
	for i = 1, 9 do
		local angle = (i / 9) * math.pi * 2 + random:NextNumber(-0.2, 0.2)
		local distance = random:NextNumber(102, 122)
		local size = random:NextNumber(2.5, 6)
		boulder(
			folder,
			cx + math.cos(angle) * distance,
			-0.5,
			cz + math.sin(angle) * distance,
			Vector3.new(size, random:NextNumber(2, 3.5), size * random:NextNumber(0.7, 1)),
			random:NextNumber() < 0.5 and COLORS.Rock or COLORS.RockDark,
			random:NextNumber(0, 90),
			random:NextNumber(-8, 8),
			random:NextNumber(-8, 8)
		)
	end

	folder.Parent = islandModel
end

-- Same look for an obstacle on every island and every session.
local function randomFor(id)
	local seed = 0
	for i = 1, #id do
		seed = (seed * 31 + string.byte(id, i)) % 2147483647
	end
	return Random.new(seed)
end

local function buildRock(model, center, random)
	local x, z = center.X, center.Z
	boulder(model, x + random:NextNumber(-0.3, 0.3), GRASS_TOP - 0.3, z, Vector3.new(random:NextNumber(2.4, 3), random:NextNumber(1.8, 2.4), random:NextNumber(2.2, 2.8)), COLORS.Rock, random:NextNumber(0, 90), random:NextNumber(-8, 8), random:NextNumber(-8, 8))
	boulder(model, x + random:NextNumber(0.8, 1.2), GRASS_TOP - 0.2, z + random:NextNumber(0.6, 1.1), Vector3.new(1.4, 1.1, 1.3), COLORS.RockDark, random:NextNumber(0, 90), 6, -8)
end

local function buildTree(model, center, random)
	local x, z = center.X + random:NextNumber(-0.8, 0.8), center.Z + random:NextNumber(-0.8, 0.8)
	local leaves = COLORS.Leaves[random:NextInteger(1, #COLORS.Leaves)]
	local yaw = random:NextNumber(0, 90)
	if random:NextNumber() < 0.5 then
		-- Round tree
		boulder(model, x, GRASS_TOP - 0.2, z, Vector3.new(1.2, 4.4, 1.2), COLORS.Trunk, yaw)
		boulder(model, x, GRASS_TOP + 3.6, z, Vector3.new(5.8, 3.4, 5.8), leaves, yaw)
		boulder(model, x, GRASS_TOP + 6.4, z, Vector3.new(4.2, 2.8, 4.2), leaves:Lerp(Color3.new(1, 1, 1), 0.08), yaw + 45, 4, -4)
		boulder(model, x, GRASS_TOP + 8.6, z, Vector3.new(2.4, 1.8, 2.4), leaves:Lerp(Color3.new(1, 1, 1), 0.14), yaw + 20)
	else
		-- Pine
		boulder(model, x, GRASS_TOP - 0.2, z, Vector3.new(1, 3.2, 1), COLORS.Trunk, yaw)
		boulder(model, x, GRASS_TOP + 2.4, z, Vector3.new(6, 2.2, 6), leaves, yaw + 45)
		boulder(model, x, GRASS_TOP + 4.3, z, Vector3.new(4.4, 2.2, 4.4), leaves:Lerp(Color3.new(1, 1, 1), 0.06), yaw)
		boulder(model, x, GRASS_TOP + 6.2, z, Vector3.new(2.8, 2, 2.8), leaves:Lerp(Color3.new(1, 1, 1), 0.12), yaw + 45)
		boulder(model, x, GRASS_TOP + 7.9, z, Vector3.new(1.3, 1.5, 1.3), leaves:Lerp(Color3.new(1, 1, 1), 0.18), yaw)
	end
	-- Bush at its foot
	local angle = random:NextNumber(0, math.pi * 2)
	boulder(model, center.X + math.cos(angle) * 2.6, GRASS_TOP - 0.3, center.Z + math.sin(angle) * 2.6, Vector3.new(2, 1.5, 1.8), leaves:Lerp(Color3.new(0, 0, 0), 0.1), random:NextNumber(0, 90))
end

local function buildBigRock(model, center, random)
	local x, z = center.X, center.Z
	local yaw = random:NextNumber(0, 90)
	boulder(model, x, GRASS_TOP - 0.5, z, Vector3.new(7, 5.2, 6), COLORS.Rock, yaw, random:NextNumber(-5, 5), random:NextNumber(-5, 5))
	boulder(model, x, GRASS_TOP + 4.5, z, Vector3.new(5.4, 0.7, 4.6), COLORS.Moss, yaw + 8)
	boulder(model, x + 3.2, GRASS_TOP - 0.4, z + 2.4, Vector3.new(4.6, 3.8, 4.4), COLORS.RockDark, yaw + 30, 6, -6)
	boulder(model, x - 3, GRASS_TOP - 0.4, z - 2.6, Vector3.new(4, 3.2, 3.8), COLORS.Rock, yaw - 25, -5, 7)
	boulder(model, x + 3.8, GRASS_TOP - 0.2, z - 3.6, Vector3.new(1.6, 1.2, 1.5), COLORS.RockDark, yaw + 60)
end

local BUILDERS = { Rock = buildRock, Tree = buildTree, BigRock = buildBigRock }
local TITLE_HEIGHTS = { Rock = 3, Tree = 10, BigRock = 6 } -- about the top of each kind

-- An invisible flat box over the footprint makes the whole tile area tappable
-- and anchors the option bar's title (TitleHeight). The visible pieces are
-- tappable too; nothing taller than them catches taps meant for what stands
-- behind.
local function buildObstacle(parent, obstacle, center)
	local tiles = ObstacleDefs[obstacle.Kind].Tiles
	local model = Instance.new("Model")
	model.Name = obstacle.Id

	local span = tiles * GameConstants.GridTileSize - 0.4
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CastShadow = false
	hitbox.Transparency = 1
	hitbox.Size = Vector3.new(span, 1, span)
	hitbox.CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0))
	hitbox:SetAttribute("ObstacleId", obstacle.Id)
	hitbox:SetAttribute("TitleHeight", (TITLE_HEIGHTS[obstacle.Kind] or 4) - 0.5)
	hitbox.Parent = model
	model.PrimaryPart = hitbox

	BUILDERS[obstacle.Kind](model, center, randomFor(obstacle.Id))
	for _, piece in ipairs(model:GetDescendants()) do
		if piece:IsA("BasePart") and piece ~= hitbox then
			piece.CanQuery = true
			piece:SetAttribute("ObstacleId", obstacle.Id)
		end
	end
	model.Parent = parent
	return model
end

local function buildStatus(player, obstacleId)
	local state = states[player.UserId]
	local obstacle = obstaclesById[obstacleId]
	if not state or not obstacle then
		return nil
	end
	local def = ObstacleDefs[obstacle.Kind]
	return {
		obstacleId = obstacleId,
		kind = obstacle.Kind,
		price = def.Price,
		duration = def.Duration,
		cleared = state.cleared[obstacleId] == true,
		clearingId = state.clearing and state.clearing.id,
		secondsLeft = state.clearing and math.max(0, state.clearing.readyAt - os.time()) or nil,
	}
end

-- extra: fields merged into the status (e.g. clearError).
local function pushStatus(player, obstacleId, openRequest, extra)
	local status = buildStatus(player, obstacleId)
	if not status then
		return
	end
	status.openRequest = openRequest or false
	for key, value in pairs(extra or {}) do
		status[key] = value
	end
	obstacleStatusUpdated:FireClient(player, status)
end

-- Timer over: sparkles tell the player the obstacle waits for their tap.
local function markClearingReady(player, state)
	state.clearing.notified = true
	local model = state.models[state.clearing.id]
	local hitbox = model and model.PrimaryPart
	if hitbox then
		ReadyGlow.Set(hitbox, true, hitbox:GetAttribute("TitleHeight") or 3)
	end
	pushStatus(player, state.clearing.id, false)
end

-- The final tap: the obstacle goes, its tiles free up, the player gets the XP
-- of the Coins it cost.
local function finishClearing(player, state)
	local id = state.clearing.id
	state.clearing = nil
	state.cleared[id] = true

	local model = state.models[id]
	state.models[id] = nil
	if model then
		if model.PrimaryPart then
			ReadyGlow.Set(model.PrimaryPart, false)
		end
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Transparency < 1 then
				TweenService:Create(part, FADE_OUT, { Transparency = 1 }):Play()
			end
		end
		task.delay(FADE_OUT.Time, function()
			model:Destroy()
		end)
	end

	local obstacle = obstaclesById[id]
	if obstacle then
		local def = ObstacleDefs[obstacle.Kind]
		HabitatService.FreeArea(player, obstacle.GridX, obstacle.GridZ, def.Tiles, def.Tiles)
		LevelService.AddXp(player, def.Price)
	end
	pushStatus(player, id, false) -- cleared = true: the client closes its bar
	HudService.PushUpdate(player) -- fresh OccupiedTiles for the placement grid
end

-- Builds the scenery and every obstacle not cleared yet. Called once the
-- buildings stand, so an obstacle whose tiles are already taken (the layout
-- changed since that save) counts as cleared instead of overlapping them.
-- saveState: { cleared = { ids }, clearing = { id, readyAt } } or nil.
function IslandService.LoadPlayer(player, saveState)
	local islandModel = HabitatService.GetIslandModel(player)
	local base = HabitatService.GetIslandBase(player)
	if not islandModel or not base then
		return
	end

	local state = { cleared = {}, models = {}, clearing = nil }
	states[player.UserId] = state
	for _, id in ipairs(saveState and saveState.cleared or {}) do
		state.cleared[id] = true
	end

	buildScenery(islandModel, base)

	local folder = Instance.new("Folder")
	folder.Name = "Obstacles"
	for _, obstacle in ipairs(IslandObstacles) do
		if not state.cleared[obstacle.Id] then
			local tiles = ObstacleDefs[obstacle.Kind].Tiles
			if HabitatService.IsAreaFree(player, obstacle.GridX, obstacle.GridZ, tiles, tiles) then
				HabitatService.OccupyArea(player, obstacle.GridX, obstacle.GridZ, tiles, tiles)
				local center = HabitatService.GridCenterFor(player, obstacle.GridX, obstacle.GridZ, tiles, tiles)
				state.models[obstacle.Id] = buildObstacle(folder, obstacle, center)
			else
				state.cleared[obstacle.Id] = true
			end
		end
	end
	folder.Parent = islandModel

	local clearing = saveState and saveState.clearing
	if clearing and state.models[clearing.id] and typeof(clearing.readyAt) == "number" then
		state.clearing = { id = clearing.id, readyAt = clearing.readyAt }
	end
end

function IslandService.GetSaveState(player)
	local state = states[player.UserId]
	if not state then
		return nil
	end
	local cleared = {}
	for id in pairs(state.cleared) do
		table.insert(cleared, id)
	end
	table.sort(cleared)
	return {
		cleared = cleared,
		clearing = state.clearing and { id = state.clearing.id, readyAt = state.clearing.readyAt } or nil,
	}
end

-- Tap on an obstacle: opens its option bar on the client.
function IslandService.RequestInfo(player, obstacleId)
	local state = states[player.UserId]
	if state and state.models[obstacleId] then
		pushStatus(player, obstacleId, true)
	end
end

-- Pays and starts clearing. Refusals are pushed back as clearError
-- ("Busy" | "InsufficientCoins").
function IslandService.StartClearing(player, obstacleId)
	local state = states[player.UserId]
	local obstacle = obstaclesById[obstacleId]
	if not state or not obstacle or not state.models[obstacleId] then
		return false
	end
	if state.clearing then
		pushStatus(player, obstacleId, false, { clearError = "Busy" })
		return false
	end
	local def = ObstacleDefs[obstacle.Kind]
	if not EconomyService.TrySpendCoins(player, def.Price) then
		pushStatus(player, obstacleId, false, { clearError = "InsufficientCoins" })
		return false
	end
	state.clearing = { id = obstacleId, readyAt = os.time() + def.Duration }
	pushStatus(player, obstacleId, false)
	HudService.PushUpdate(player) -- show the Coins spent right away
	return true
end

-- Final tap on an obstacle whose clearing time is up.
function IslandService.FinishClearing(player, obstacleId)
	local state = states[player.UserId]
	local clearing = state and state.clearing
	if not clearing or clearing.id ~= obstacleId or os.time() + READY_GRACE_SECONDS < clearing.readyAt then
		return false
	end
	finishClearing(player, state)
	return true
end

-- Skips the rest of the clearing for Gems (Config/GemSpeedUp). It still waits
-- for the final tap. A refusal is pushed back as clearError "NotEnoughGems".
function IslandService.SpeedUpClearing(player, obstacleId)
	local state = states[player.UserId]
	local clearing = state and state.clearing
	if not clearing or clearing.id ~= obstacleId then
		return false
	end
	local secondsLeft = clearing.readyAt - os.time()
	if secondsLeft <= 0 then
		return false
	end
	if not EconomyService.TrySpendGems(player, GemSpeedUp(secondsLeft)) then
		pushStatus(player, obstacleId, false, { clearError = "NotEnoughGems" })
		return false
	end
	clearing.readyAt = os.time()
	markClearingReady(player, state)
	HudService.PushUpdate(player) -- show the Gems spent right away
	return true
end

-- Watches clearings reach their end time (including ones that ran out while
-- the player was away: right after loading). They still need the final tap.
function IslandService.StartTickLoop()
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for userId, state in pairs(states) do
				local player = Players:GetPlayerByUserId(userId)
				if player and state.clearing and not state.clearing.notified and now >= state.clearing.readyAt then
					markClearingReady(player, state)
				end
			end
		end
	end)
end

function IslandService.RemovePlayer(player)
	states[player.UserId] = nil
end

return IslandService
