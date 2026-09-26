-- Habitats: where dragons live, on the island's placement grid. Each has a
-- level (1 to 5, HabitatLevels) setting how many dragons it holds and how
-- many Coins it stores: its Adults' income piles up in the habitat
-- (StoreCoins) until the player harvests it - any tap on the habitat does
-- (RequestInfo), as does the bar's Collect. A full habitat gets a floating
-- coin (CoinsFull attribute). An upgrade is paid, built over its works time,
-- then finished with a final tap, like a construction; meanwhile its dragons
-- keep producing but its Coins can't be harvested.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local HabitatDefs = require(Config.HabitatDefs)
local HabitatLevels = require(Config.HabitatLevels)
local GameConstants = require(Config.GameConstants)

local GemSpeedUp = require(Config.GemSpeedUp)

local LevelService = require(script.Parent.LevelService)
local ReadyGlow = require(script.Parent.ReadyGlow)
local Scaffold = require(script.Parent.Scaffold)

local HabitatService = {}

local DragonService
local EconomyService
local habitatStatusUpdated

function HabitatService.Init(dragonServiceRef, economyServiceRef, remotesFolder)
	DragonService = dragonServiceRef
	EconomyService = economyServiceRef

	habitatStatusUpdated = remotesFolder:FindFirstChild("HabitatStatusUpdated")
	if not habitatStatusUpdated then
		habitatStatusUpdated = Instance.new("RemoteEvent")
		habitatStatusUpdated.Name = "HabitatStatusUpdated"
		habitatStatusUpdated.Parent = remotesFolder
	end
end

-- Placement grid: the island's grass plate (IslandBase) cut into tiles, tile
-- (0,0) at the -X,-Z corner (sizes in GameConstants). A Habitat occupies
-- 4x4 tiles. The scenery around it and the obstacles on it are IslandService's.
local TILE_SIZE = GameConstants.GridTileSize
local GRID_TILES_PER_SIDE = GameConstants.GridTilesPerSide
local ISLAND_HALF_SIZE = TILE_SIZE * GRID_TILES_PER_SIDE / 2

-- Habitat models, one per element: an invisible 16x1x16 "platform" Part (what
-- the grid, taps and dragons refer to) with the scenery parts and Slot1..Slot4
-- attachments (where dragons stand) parented under it.
local habitatTemplates = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets"):FindFirstChild("Habitats")

local islandsFolder = Workspace:FindFirstChild("Islands")
if not islandsFolder then
	islandsFolder = Instance.new("Folder")
	islandsFolder.Name = "Islands"
	islandsFolder.Parent = Workspace
end

local playerIslands = {} -- [userId] = { model, base, habitats = {}, nextHabitatId }
local nextIslandIndex = 0

local function getHabitat(player, habitatId)
	local island = playerIslands[player.UserId]
	return island and island.habitats[habitatId]
end

-- CoinsFull on the habitat's part tells the client (HabitatCoinController) to
-- float a coin over it: its storage is full and it's not under works (no
-- harvest then, so no coin either).
local function refreshCoinSign(record)
	local full = not record.upgradeReadyAt and not record.buildReadyAt
		and record.storedCoins >= HabitatLevels.Storage(record.element, record.level)
	record.model:SetAttribute("CoinsFull", full)
end

-- Moves a part together with every part parented under it (scenery, dragons).
-- Also used for decorations (DecorationService).
function HabitatService.PivotTree(root, cframe)
	local delta = cframe * root.CFrame:Inverse()
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CFrame = delta * descendant.CFrame
		end
	end
	root.CFrame = cframe
end
local pivotTree = HabitatService.PivotTree

local function computeSlotCFrames(platform)
	-- The model's Slot1..Slot4 attachments (its level decides how many are used)
	local fromModel = {}
	for i = 1, 4 do
		local attachment = platform:FindFirstChild("Slot" .. i)
		if attachment and attachment:IsA("Attachment") then
			fromModel[i] = CFrame.new(attachment.WorldPosition)
		end
	end
	if #fromModel == 4 then
		return fromModel
	end

	-- No model: 2x2 grid of slots on top of the platform
	local top = platform.Position + Vector3.new(0, platform.Size.Y / 2, 0)
	local offsets = {
		Vector3.new(-3, 0, -3),
		Vector3.new(3, 0, -3),
		Vector3.new(-3, 0, 3),
		Vector3.new(3, 0, 3),
	}
	local cframes = {}
	for i, offset in ipairs(offsets) do
		cframes[i] = CFrame.new(top + offset)
	end
	return cframes
end

local function getOrCreateIsland(player)
	local existing = playerIslands[player.UserId]
	if existing then
		return existing
	end

	nextIslandIndex += 1

	local islandModel = Instance.new("Folder")
	islandModel.Name = tostring(player.UserId)
	islandModel.Parent = islandsFolder

	local baseplate = Instance.new("Part")
	baseplate.Name = "IslandBase"
	baseplate.Anchored = true
	baseplate.Size = Vector3.new(ISLAND_HALF_SIZE * 2, 2, ISLAND_HALF_SIZE * 2)
	-- Top at Y = 3, above the sea and beach IslandService builds around it.
	baseplate.Position = Vector3.new(nextIslandIndex * GameConstants.IslandSpacingStuds, 2, 0)
	baseplate.Color = Color3.fromRGB(126, 196, 86)
	baseplate.Material = Enum.Material.SmoothPlastic
	baseplate.Parent = islandModel

	local record = {
		model = islandModel,
		base = baseplate,
		habitats = {},
		nextHabitatId = 1,
		occupiedTiles = {}, -- ["x,z"] = true
	}
	playerIslands[player.UserId] = record
	return record
end

-- Triggers island creation without placing anything - Farm/Nursery need the
-- island (and its grid) to exist before they reserve their fixed tiles, but
-- neither of them creates a Habitat to trigger it implicitly.
function HabitatService.EnsureIsland(player)
	getOrCreateIsland(player)
end

-- HABITAT_TILES: a Habitat's footprint on the placement grid (4x4 tiles ==
-- its 16x16 PlatformSize). Fixed for Phase 2 - if HabitatDefs ever varies
-- PlatformSize per element this needs to derive from that instead.
local HABITAT_TILES = GameConstants.StructureTiles.Habitat

local UNDER_CONSTRUCTION_TRANSPARENCY = 0.6

-- A habitat under construction: its scenery see-through with its effects
-- off, inside a wooden scaffold - all undone when the construction ends.
local function setUnderConstruction(platform, building)
	local visual = platform:FindFirstChild("Visual")
	if visual then
		for _, part in ipairs(visual:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = building and UNDER_CONSTRUCTION_TRANSPARENCY or 0
			end
		end
	end
	for _, effect in ipairs(platform:GetDescendants()) do
		if effect:IsA("ParticleEmitter") or effect:IsA("Light") or effect:IsA("Beam") then
			effect.Enabled = not building
		end
	end

	Scaffold.Set(platform, building)
end

-- buildReadyAt: os.time() its construction ends, or nil for a finished habitat
-- (the free starter one, older saves). state: its saved { level, storedCoins,
-- upgradeReadyAt? }, or nil for a new level 1 habitat.
function HabitatService.CreateHabitat(player, element, gridX, gridZ, purchasePrice, buildReadyAt, state)
	local island = getOrCreateIsland(player)
	local def = HabitatDefs[element]
	assert(def, "Unknown habitat element: " .. tostring(element))
	assert(gridX ~= nil and gridZ ~= nil, "CreateHabitat requires explicit grid coordinates")

	local habitatId = island.nextHabitatId
	island.nextHabitatId += 1

	local center = HabitatService.GridCenterFor(player, gridX, gridZ, HABITAT_TILES, HABITAT_TILES)

	local template = habitatTemplates and habitatTemplates:FindFirstChild(element)
	local platform
	if template then
		platform = template:Clone()
		pivotTree(platform, CFrame.new(center + Vector3.new(0, platform.Size.Y / 2, 0)))
	else
		platform = Instance.new("Part")
		platform.Size = def.PlatformSize
		platform.Color = def.PlatformColor
		platform.Material = Enum.Material.SmoothPlastic
		platform.Position = center + Vector3.new(0, def.PlatformSize.Y / 2, 0)
	end
	platform.Name = def.DisplayName .. " " .. habitatId
	platform.Anchored = true
	-- On every piece, so a tap on the scenery opens the habitat too.
	platform:SetAttribute("HabitatId", habitatId)
	for _, descendant in ipairs(platform:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("HabitatId", habitatId)
		end
	end
	if buildReadyAt then
		setUnderConstruction(platform, true)
	end
	platform.Parent = island.model

	HabitatService.OccupyArea(player, gridX, gridZ, HABITAT_TILES, HABITAT_TILES)

	local level = math.clamp((state and state.level) or 1, 1, HabitatLevels.MaxLevel)
	local record = {
		id = habitatId,
		element = element,
		model = platform,
		level = level,
		capacity = HabitatLevels.Dragons(level),
		occupied = {},
		slotCFrames = computeSlotCFrames(platform),
		gridX = gridX,
		gridZ = gridZ,
		purchasePrice = purchasePrice or 0,
		buildReadyAt = buildReadyAt, -- nil once built; no dragon moves in before
		storedCoins = (state and state.storedCoins) or 0,
		upgradeReadyAt = state and state.upgradeReadyAt, -- set while an upgrade's works run
	}
	if record.upgradeReadyAt then
		Scaffold.Set(platform, true)
	end
	refreshCoinSign(record)
	island.habitats[habitatId] = record
	return record
end

-- Coins its dragons make go into the habitat, up to its storage.
function HabitatService.StoreCoins(habitatRecord, amount)
	local storage = HabitatLevels.Storage(habitatRecord.element, habitatRecord.level)
	if habitatRecord.storedCoins < storage then
		habitatRecord.storedCoins = math.min(storage, habitatRecord.storedCoins + amount)
		refreshCoinSign(habitatRecord)
	end
end

function HabitatService.FindFreeSlot(habitatRecord)
	for i = 1, habitatRecord.capacity do
		if not habitatRecord.occupied[i] then
			return i
		end
	end
	return nil
end

function HabitatService.OccupySlot(habitatRecord, slotIndex, dragonId)
	-- Saves from before levels had dragons in all 4 slots: such a habitat
	-- takes the level that has room for them.
	if slotIndex > habitatRecord.capacity then
		habitatRecord.level = math.max(habitatRecord.level, HabitatLevels.LevelForSlot(slotIndex))
		habitatRecord.capacity = HabitatLevels.Dragons(habitatRecord.level)
	end
	habitatRecord.occupied[slotIndex] = dragonId
end

function HabitatService.FreeSlot(habitatRecord, slotIndex)
	habitatRecord.occupied[slotIndex] = nil
end

function HabitatService.GetSlotCFrame(habitatRecord, slotIndex)
	return habitatRecord.slotCFrames[slotIndex]
end

function HabitatService.GetIslandBasePosition(player)
	local island = playerIslands[player.UserId]
	return island and island.base.Position
end

function HabitatService.GetIslandModel(player)
	local island = playerIslands[player.UserId]
	return island and island.model
end

-- The grass plate the grid lies on (IslandService builds the scenery around it).
function HabitatService.GetIslandBase(player)
	local island = playerIslands[player.UserId]
	return island and island.base
end

local function tileKey(x, z)
	return x .. "," .. z
end

-- World-space center of a widthTiles x depthTiles footprint anchored at grid
-- tile (gridX, gridZ), at the island's top surface (Y). Callers add their own
-- half-height on top (center + Vector3.new(0, structureHeight/2, 0)).
function HabitatService.GridCenterFor(player, gridX, gridZ, widthTiles, depthTiles)
	local island = playerIslands[player.UserId]
	if not island then return nil end

	local originX = island.base.Position.X - ISLAND_HALF_SIZE
	local originZ = island.base.Position.Z - ISLAND_HALF_SIZE
	local centerX = originX + gridX * TILE_SIZE + widthTiles * TILE_SIZE / 2
	local centerZ = originZ + gridZ * TILE_SIZE + depthTiles * TILE_SIZE / 2
	return Vector3.new(centerX, island.base.Position.Y + island.base.Size.Y / 2, centerZ)
end

-- True if every tile in the widthTiles x depthTiles area starting at
-- (gridX, gridZ) is inside the island and unoccupied.
function HabitatService.IsAreaFree(player, gridX, gridZ, widthTiles, depthTiles)
	local island = playerIslands[player.UserId]
	if not island then return false end
	if gridX ~= gridX or gridZ ~= gridZ then return false end -- NaN from a client would slip past the bounds checks
	if gridX < 0 or gridZ < 0 or gridX + widthTiles > GRID_TILES_PER_SIDE or gridZ + depthTiles > GRID_TILES_PER_SIDE then
		return false
	end

	for x = gridX, gridX + widthTiles - 1 do
		for z = gridZ, gridZ + depthTiles - 1 do
			if island.occupiedTiles[tileKey(x, z)] then
				return false
			end
		end
	end
	return true
end

-- Marks every tile in the area occupied. Doesn't check IsAreaFree itself -
-- callers (CreateHabitat, Farm/Nursery setup) are expected to have already
-- validated (or, for the fixed Farm/Nursery spots, know they're free by
-- construction since they're reserved before any Habitat can be placed).
function HabitatService.OccupyArea(player, gridX, gridZ, widthTiles, depthTiles)
	local island = playerIslands[player.UserId]
	if not island then return end
	for x = gridX, gridX + widthTiles - 1 do
		for z = gridZ, gridZ + depthTiles - 1 do
			island.occupiedTiles[tileKey(x, z)] = true
		end
	end
end

-- Opposite of OccupyArea: a Habitat sold, a building moved, an obstacle cleared.
function HabitatService.FreeArea(player, gridX, gridZ, widthTiles, depthTiles)
	local island = playerIslands[player.UserId]
	if not island then return end
	for x = gridX, gridX + widthTiles - 1 do
		for z = gridZ, gridZ + depthTiles - 1 do
			island.occupiedTiles[tileKey(x, z)] = nil
		end
	end
end

-- Moves a footprint from (fromX, fromZ) to (toX, toZ): its own current tiles
-- don't block the move. No yield in between, so false leaves the grid exactly
-- as it was.
function HabitatService.TryMoveArea(player, fromX, fromZ, toX, toZ, widthTiles, depthTiles)
	HabitatService.FreeArea(player, fromX, fromZ, widthTiles, depthTiles)
	if not HabitatService.IsAreaFree(player, toX, toZ, widthTiles, depthTiles) then
		HabitatService.OccupyArea(player, fromX, fromZ, widthTiles, depthTiles)
		return false
	end
	HabitatService.OccupyArea(player, toX, toZ, widthTiles, depthTiles)
	return true
end

-- First free widthTiles x depthTiles area, scanning row by row from (0,0).
-- Used as a migration fallback for save data written before the grid existed.
function HabitatService.FindFreeGridSlot(player, widthTiles, depthTiles)
	for z = 0, GRID_TILES_PER_SIDE - depthTiles do
		for x = 0, GRID_TILES_PER_SIDE - widthTiles do
			if HabitatService.IsAreaFree(player, x, z, widthTiles, depthTiles) then
				return x, z
			end
		end
	end
	return nil
end

-- Flat {x,z} list for pushing to the client (see HudService) so it can render
-- a red/green placement ghost without a round trip per mouse move.
function HabitatService.GetOccupiedTiles(player)
	local island = playerIslands[player.UserId]
	if not island then return {} end

	local list = {}
	for key in pairs(island.occupiedTiles) do
		local x, z = key:match("(-?%d+),(-?%d+)")
		table.insert(list, { tonumber(x), tonumber(z) })
	end
	return list
end

-- Ordered by habitatId (creation order) so SaveService can recreate habitats
-- via CreateHabitat in the same order and get matching ids back.
function HabitatService.GetPlayerHabitats(player)
	local island = playerIslands[player.UserId]
	if not island then return {} end

	local ids = {}
	for id in pairs(island.habitats) do
		table.insert(ids, id)
	end
	table.sort(ids)

	local list = {}
	for _, id in ipairs(ids) do
		local record = island.habitats[id]
		table.insert(list, {
			id = record.id,
			element = record.element,
			gridX = record.gridX,
			gridZ = record.gridZ,
			purchasePrice = record.purchasePrice or 0,
			buildReadyAt = record.buildReadyAt,
			level = record.level,
			storedCoins = math.floor(record.storedCoins),
			upgradeReadyAt = record.upgradeReadyAt,
		})
	end
	return list
end

-- Whether a habitat of `element` suits a dragon that can live in `elements`
-- (one habitat element, or a list: a hybrid lives in either of its two).
local function accepts(elements, element)
	if type(elements) == "table" then
		return table.find(elements, element) ~= nil
	end
	return elements == element
end

-- First free slot among this player's habitats of the given element(s), in
-- habitat creation order. Used by purchase flows (e.g. ShopService buying an
-- exclusive dragon) that need a slot without reaching into the internal
-- habitat records themselves.
function HabitatService.FindFreeSlotForElement(player, element)
	local island = playerIslands[player.UserId]
	if not island then return nil end

	local ids = {}
	for id in pairs(island.habitats) do
		table.insert(ids, id)
	end
	table.sort(ids)

	for _, id in ipairs(ids) do
		local record = island.habitats[id]
		if accepts(element, record.element) and not record.buildReadyAt then
			local slotIndex = HabitatService.FindFreeSlot(record)
			if slotIndex then
				return record, slotIndex
			end
		end
	end
	return nil
end

-- Moves a habitat (and the dragons standing on it) to another grid spot.
function HabitatService.MoveHabitat(player, habitatId, gridX, gridZ)
	local island = playerIslands[player.UserId]
	local record = island and island.habitats[habitatId]
	if not record then return false end
	if not HabitatService.TryMoveArea(player, record.gridX, record.gridZ, gridX, gridZ, HABITAT_TILES, HABITAT_TILES) then
		return false
	end

	local center = HabitatService.GridCenterFor(player, gridX, gridZ, HABITAT_TILES, HABITAT_TILES)
	pivotTree(record.model, CFrame.new(center + Vector3.new(0, record.model.Size.Y / 2, 0)))
	record.gridX, record.gridZ = gridX, gridZ
	record.slotCFrames = computeSlotCFrames(record.model)
	DragonService.RefreshSlotPositions(record)
	return true
end

-- Every habitat of this player with how full it is, in creation order - lets
-- the Incubator UI list the habitats a hatchling can move into.
function HabitatService.GetHabitatSummaries(player)
	local island = playerIslands[player.UserId]
	if not island then return {} end

	local ids = {}
	for id in pairs(island.habitats) do
		table.insert(ids, id)
	end
	table.sort(ids)

	local list = {}
	for _, id in ipairs(ids) do
		local record = island.habitats[id]
		local used = 0
		for i = 1, record.capacity do
			if record.occupied[i] then
				used += 1
			end
		end
		table.insert(list, {
			id = id,
			element = record.element,
			used = used,
			capacity = record.capacity,
			building = record.buildReadyAt ~= nil,
		})
	end
	return list
end

-- Free slot in one specific habitat, only if that habitat houses `element`
-- (a habitat element or a list of them, see accepts).
function HabitatService.FindFreeSlotInHabitat(player, habitatId, element)
	local island = playerIslands[player.UserId]
	local record = island and island.habitats[habitatId]
	if not record or not accepts(element, record.element) or record.buildReadyAt then return nil end
	local slotIndex = HabitatService.FindFreeSlot(record)
	if not slotIndex then return nil end
	return record, slotIndex
end

-- Status for the Habitat bar (HabitatUIController):
-- per-dragon detail comes from DragonService (which owns dragon records),
-- level, storage and sell value from this module's own habitat record.
-- upgrade: what the next level costs and brings (nil at the top level).
local function buildStatus(player, habitatId)
	local record = getHabitat(player, habitatId)
	if not record then return nil end

	local dragonInfos = DragonService.GetHabitatDragons(player, habitatId)
	local upgrade = nil
	if record.level < HabitatLevels.MaxLevel then
		local nextLevel = record.level + 1
		upgrade = {
			level = nextLevel,
			cost = HabitatLevels.UpgradeCost(record.element, nextLevel),
			duration = HabitatLevels.UpgradeDuration(nextLevel),
			dragons = HabitatLevels.Dragons(nextLevel),
			storage = HabitatLevels.Storage(record.element, nextLevel),
		}
	end
	local storedCoins = math.floor(record.storedCoins)

	local isEmpty = true
	for i = 1, record.capacity do
		if record.occupied[i] then
			isEmpty = false
			break
		end
	end

	return {
		habitatId = habitatId,
		element = record.element,
		level = record.level,
		maxLevel = HabitatLevels.MaxLevel,
		capacity = record.capacity,
		dragons = dragonInfos,
		storedCoins = storedCoins,
		storage = HabitatLevels.Storage(record.element, record.level),
		upgrade = upgrade,
		upgradeSecondsLeft = record.upgradeReadyAt and math.max(0, record.upgradeReadyAt - os.time()) or nil,
		canSell = isEmpty and not record.upgradeReadyAt,
		-- Its stored Coins come along with the refund.
		sellValue = math.floor((record.purchasePrice or 0) * GameConstants.HabitatSellRefundPercent) + storedCoins,
		buildSecondsLeft = record.buildReadyAt and math.max(0, record.buildReadyAt - os.time()) or nil,
	}
end

-- collected: Coins just harvested by this action, so the client plays the
-- collect animation only once the server has actually paid out.
-- extra: fields merged into the push (e.g. speedUpError).
local function pushStatus(player, habitatId, openRequest, collected, extra)
	local status = buildStatus(player, habitatId)
	if not status then return end
	status.openRequest = openRequest or false
	status.collected = collected
	for key, value in pairs(extra or {}) do
		status[key] = value
	end
	habitatStatusUpdated:FireClient(player, status)
end

-- Gives the player the Coins stored in the habitat - not during an upgrade's
-- works, when they keep piling up. Returns the amount.
local function harvest(player, record)
	if record.upgradeReadyAt then
		return 0
	end
	local amount = math.floor(record.storedCoins)
	if amount > 0 then
		record.storedCoins -= amount
		EconomyService.AddCoins(player, amount)
		refreshCoinSign(record)
	end
	return amount
end

-- Explicit click on the Habitat: harvests its Coins and forces its bar open
-- on the client. Returns the Coins harvested.
function HabitatService.RequestInfo(player, habitatId)
	local record = getHabitat(player, habitatId)
	if not record then
		return 0
	end
	local collected = harvest(player, record)
	pushStatus(player, habitatId, true, collected > 0 and collected or nil)
	return collected
end

-- Opens the habitat's bar without harvesting it (e.g. after one of its
-- dragons was sold from the Dragon screen).
function HabitatService.OpenInfo(player, habitatId)
	if getHabitat(player, habitatId) then
		pushStatus(player, habitatId, true)
	end
end

-- Silent refresh (feed/collect actions) - must never yank the panel back
-- open after the player closes it, same rule as BreedingService/pushStatus.
function HabitatService.RefreshStatus(player, habitatId)
	pushStatus(player, habitatId, false)
end

-- The bar's Collect; refused during an upgrade's works (collectError).
function HabitatService.CollectIncome(player, habitatId)
	local record = getHabitat(player, habitatId)
	if not record then return 0 end
	if record.upgradeReadyAt then
		pushStatus(player, habitatId, false, nil, { collectError = "Upgrading" })
		return 0
	end
	local amount = harvest(player, record)
	pushStatus(player, habitatId, false, amount)
	return amount
end

local READY_GRACE_SECONDS = 1 -- a client countdown reaching zero a moment early still counts

-- Timer over: sparkles tell the player the construction waits for their tap.
local function markConstructionReady(player, record)
	record.buildNotified = true
	ReadyGlow.Set(record.model, true, (record.model:GetAttribute("TitleHeight") or 4) * 0.7)
	pushStatus(player, record.id, false)
end

-- Same for an upgrade's works.
local function markUpgradeReady(player, record)
	record.upgradeNotified = true
	ReadyGlow.Set(record.model, true, (record.model:GetAttribute("TitleHeight") or 4) * 0.7)
	pushStatus(player, record.id, false)
end

-- Watches constructions and upgrades reach their end time, including ones
-- that ended while the player was away (right after their island loads).
-- They still need the player's final tap (FinishConstruction, FinishUpgrade).
function HabitatService.StartConstructionLoop()
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for userId, island in pairs(playerIslands) do
				local player = Players:GetPlayerByUserId(userId)
				if player then
					for _, record in pairs(island.habitats) do
						if record.buildReadyAt and not record.buildNotified and now >= record.buildReadyAt then
							markConstructionReady(player, record)
						elseif record.upgradeReadyAt and not record.upgradeNotified and now >= record.upgradeReadyAt then
							markUpgradeReady(player, record)
						end
					end
				end
			end
		end
	end)
end

-- The player's final tap on a construction whose time is up: the habitat
-- takes its real look, accepts dragons, and they get the XP of its price.
function HabitatService.FinishConstruction(player, habitatId)
	local island = playerIslands[player.UserId]
	local record = island and island.habitats[habitatId]
	if not record or not record.buildReadyAt or os.time() + READY_GRACE_SECONDS < record.buildReadyAt then
		return false
	end
	record.buildReadyAt = nil
	record.buildNotified = nil
	ReadyGlow.Set(record.model, false)
	setUnderConstruction(record.model, false)
	LevelService.AddXp(player, record.purchasePrice or 0)
	pushStatus(player, habitatId, false)
	return true
end

-- Skips the rest of the construction for Gems (Config/GemSpeedUp). It still
-- waits for the final tap. A refusal is pushed back as speedUpError.
function HabitatService.SpeedUpConstruction(player, habitatId)
	local island = playerIslands[player.UserId]
	local record = island and island.habitats[habitatId]
	if not record or not record.buildReadyAt then
		return false
	end
	local secondsLeft = record.buildReadyAt - os.time()
	if secondsLeft <= 0 then
		return false
	end
	if not EconomyService.TrySpendGems(player, GemSpeedUp(secondsLeft)) then
		pushStatus(player, habitatId, false, nil, { speedUpError = "NotEnoughGems" })
		return false
	end
	record.buildReadyAt = os.time()
	markConstructionReady(player, record)
	return true
end

-- Pays for the next level and starts its works (HabitatLevels). The habitat
-- keeps working meanwhile; its level only rises at the final tap
-- (FinishUpgrade). Returns true, or false plus a reason ("Building", "Busy",
-- "MaxLevel", "InsufficientCoins") that is also pushed as upgradeError.
function HabitatService.StartUpgrade(player, habitatId)
	local record = getHabitat(player, habitatId)
	if not record then return false, "NotFound" end
	local reason = nil
	if record.buildReadyAt then
		reason = "Building"
	elseif record.upgradeReadyAt then
		reason = "Busy"
	elseif record.level >= HabitatLevels.MaxLevel then
		reason = "MaxLevel"
	elseif not EconomyService.TrySpendCoins(player, HabitatLevels.UpgradeCost(record.element, record.level + 1)) then
		reason = "InsufficientCoins"
	end
	if reason then
		pushStatus(player, habitatId, false, nil, { upgradeError = reason })
		return false, reason
	end
	record.upgradeReadyAt = os.time() + HabitatLevels.UpgradeDuration(record.level + 1)
	Scaffold.Set(record.model, true)
	refreshCoinSign(record)
	pushStatus(player, habitatId, false)
	return true
end

-- The player's final tap on upgrade works whose time is up: the habitat
-- reaches its next level (more dragons and storage), and they get the XP of
-- its cost.
function HabitatService.FinishUpgrade(player, habitatId)
	local record = getHabitat(player, habitatId)
	if not record or not record.upgradeReadyAt or os.time() + READY_GRACE_SECONDS < record.upgradeReadyAt then
		return false
	end
	local cost = HabitatLevels.UpgradeCost(record.element, record.level + 1)
	record.level = math.min(record.level + 1, HabitatLevels.MaxLevel)
	record.capacity = HabitatLevels.Dragons(record.level)
	record.upgradeReadyAt = nil
	record.upgradeNotified = nil
	ReadyGlow.Set(record.model, false)
	Scaffold.Set(record.model, false)
	refreshCoinSign(record)
	LevelService.AddXp(player, cost)
	pushStatus(player, habitatId, false)
	return true
end

-- Skips the rest of the upgrade works for Gems (Config/GemSpeedUp). It still
-- waits for the final tap. A refusal is pushed back as speedUpError.
function HabitatService.SpeedUpUpgrade(player, habitatId)
	local record = getHabitat(player, habitatId)
	if not record or not record.upgradeReadyAt then
		return false
	end
	local secondsLeft = record.upgradeReadyAt - os.time()
	if secondsLeft <= 0 then
		return false
	end
	if not EconomyService.TrySpendGems(player, GemSpeedUp(secondsLeft)) then
		pushStatus(player, habitatId, false, nil, { speedUpError = "NotEnoughGems" })
		return false
	end
	record.upgradeReadyAt = os.time()
	markUpgradeReady(player, record)
	return true
end

-- Sells an empty Habitat for HabitatSellRefundPercent of what was paid for it
-- (0 for the free starter Habitat), plus the Coins stored in it. Refuses if
-- any slot is still occupied - the player must move dragons out first - or
-- while an upgrade's works run.
function HabitatService.Sell(player, habitatId)
	local island = playerIslands[player.UserId]
	if not island then return false end
	local record = island.habitats[habitatId]
	if not record then return false end
	if record.upgradeReadyAt then return false, "Busy" end

	for i = 1, record.capacity do
		if record.occupied[i] then
			return false, "NotEmpty"
		end
	end

	local refund = math.floor((record.purchasePrice or 0) * GameConstants.HabitatSellRefundPercent) + math.floor(record.storedCoins)
	record.model:Destroy()
	HabitatService.FreeArea(player, record.gridX, record.gridZ, HABITAT_TILES, HABITAT_TILES)
	island.habitats[habitatId] = nil

	EconomyService.AddCoins(player, refund)
	return true, refund
end

-- Destroys the whole island model (habitats, dragons, farms all parent under
-- it), so a rejoin on the same live server doesn't layer a second island on
-- top of the leftover one from before this player left.
function HabitatService.RemovePlayer(player)
	local island = playerIslands[player.UserId]
	if not island then return end
	island.model:Destroy()
	playerIslands[player.UserId] = nil
end

return HabitatService
