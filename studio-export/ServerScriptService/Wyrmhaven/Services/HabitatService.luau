local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local HabitatDefs = require(Config.HabitatDefs)
local GameConstants = require(Config.GameConstants)

local HabitatService = {}

local islandsFolder = Workspace:FindFirstChild("Islands")
if not islandsFolder then
	islandsFolder = Instance.new("Folder")
	islandsFolder.Name = "Islands"
	islandsFolder.Parent = Workspace
end

local playerIslands = {} -- [userId] = { model, base, habitats = {}, nextHabitatId }
local nextIslandIndex = 0

local function computeSlotCFrames(platform)
	-- 2x2 grid of slots on top of the platform (Phase 1 habitats are always capacity 4)
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
	baseplate.Size = Vector3.new(60, 2, 60)
	baseplate.Position = Vector3.new(nextIslandIndex * GameConstants.IslandSpacingStuds, 0, 0)
	baseplate.Color = Color3.fromRGB(120, 200, 120)
	baseplate.Material = Enum.Material.Grass
	baseplate.Parent = islandModel

	local record = {
		model = islandModel,
		base = baseplate,
		habitats = {},
		nextHabitatId = 1,
	}
	playerIslands[player.UserId] = record
	return record
end

function HabitatService.CreateHabitat(player, element)
	local island = getOrCreateIsland(player)
	local def = HabitatDefs[element]
	assert(def, "Unknown habitat element: " .. tostring(element))

	local habitatId = island.nextHabitatId
	island.nextHabitatId += 1

	local offsetIndex = habitatId - 1
	local platform = Instance.new("Part")
	platform.Name = def.DisplayName .. " " .. habitatId
	platform.Anchored = true
	platform.Size = def.PlatformSize
	platform.Color = def.PlatformColor
	platform.Material = Enum.Material.SmoothPlastic
	platform.Position = island.base.Position
		+ Vector3.new((offsetIndex % 2) * 20 - 10, island.base.Size.Y / 2 + def.PlatformSize.Y / 2, math.floor(offsetIndex / 2) * 20 - 10)
	platform.Parent = island.model

	local record = {
		id = habitatId,
		element = element,
		model = platform,
		capacity = def.Capacity,
		occupied = {},
		slotCFrames = computeSlotCFrames(platform),
	}
	island.habitats[habitatId] = record
	return record
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
		table.insert(list, { id = record.id, element = record.element })
	end
	return list
end

-- Destroys the whole island model (habitats, dragons, Farm all parent under
-- it), so a rejoin on the same live server doesn't layer a second island on
-- top of the leftover one from before this player left.
function HabitatService.RemovePlayer(player)
	local island = playerIslands[player.UserId]
	if not island then return end
	island.model:Destroy()
	playerIslands[player.UserId] = nil
end

return HabitatService
