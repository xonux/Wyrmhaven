-- Shop decorations: passive % bonus on nearby structures' income (see
-- docs/design/phase2-shop.md). Kept as its own service (not folded into
-- ShopService) so DragonService/FarmService can query bonuses without
-- depending on ShopService, which itself depends on them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local DecorationDefs = require(Config.DecorationDefs)

local DecorationService = {}

local HabitatService

-- Default placement anchors relative to the island base, matching the
-- structures they're meant to boost exactly (HabitatService's first habitat
-- offset (-10,-10), FarmService's Farm offset (+15,+15)) - Phase 2 doesn't
-- support free player placement (see shop-decorations.md).
local RESOURCE_ANCHORS = {
	Coins = Vector3.new(-10, 2, -10),
	Food = Vector3.new(15, 2, 15),
}

-- Spacing between stacked decorations of the same resource, small enough
-- that several fit within a typical decoration's Radius (20 studs) before
-- falling out of range - otherwise the design doc's +50% stacking cap is
-- never reachable in practice.
local STACK_OFFSET_STUDS = 2

local decorations = {} -- [userId] = { {defId, resource, bonusPercent, radius, position, part}, ... }

function DecorationService.Init(habitatServiceRef)
	HabitatService = habitatServiceRef
end

local function spawnPart(islandModel, def, position)
	local part = Instance.new("Part")
	part.Name = def.DisplayName
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(3, 3, 3)
	part.Color = def.PlatformColor
	part.Material = Enum.Material.Neon
	part.Position = position
	part.Parent = islandModel
	return part
end

local function addDecoration(player, defId, position)
	local def = DecorationDefs[defId]
	assert(def, "Unknown decoration: " .. tostring(defId))

	local islandModel = HabitatService.GetIslandModel(player)
	local part = spawnPart(islandModel, def, position)

	local list = decorations[player.UserId]
	if not list then
		list = {}
		decorations[player.UserId] = list
	end

	table.insert(list, {
		defId = defId,
		resource = def.Resource,
		bonusPercent = def.BonusPercent,
		radius = def.Radius,
		position = position,
		part = part,
	})
end

-- Buys and places a new decoration at its resource's default anchor,
-- offset along X per existing decoration of that resource so multiple
-- copies don't stack exactly on top of each other.
function DecorationService.CreateDecoration(player, defId)
	local def = DecorationDefs[defId]
	assert(def, "Unknown decoration: " .. tostring(defId))

	local islandBasePosition = HabitatService.GetIslandBasePosition(player)
	local anchor = RESOURCE_ANCHORS[def.Resource]

	local existingCount = 0
	local list = decorations[player.UserId]
	if list then
		for _, rec in ipairs(list) do
			if rec.resource == def.Resource then
				existingCount += 1
			end
		end
	end

	local position = islandBasePosition + anchor + Vector3.new(existingCount * STACK_OFFSET_STUDS, 0, 0)
	addDecoration(player, defId, position)
end

-- Loaded at join (see Server.script) - resets this player's decoration
-- list and recreates any saved ones at their saved positions.
function DecorationService.LoadPlayer(player, savedList)
	decorations[player.UserId] = {}
	if not savedList then return end
	for _, saved in ipairs(savedList) do
		addDecoration(player, saved.defId, Vector3.new(saved.position.X, saved.position.Y, saved.position.Z))
	end
end

function DecorationService.RemovePlayer(player)
	decorations[player.UserId] = nil
end

function DecorationService.GetSaveState(player)
	local list = decorations[player.UserId]
	if not list then return {} end
	local result = {}
	for _, rec in ipairs(list) do
		table.insert(result, {
			defId = rec.defId,
			position = { X = rec.position.X, Y = rec.position.Y, Z = rec.position.Z },
		})
	end
	return result
end

-- Sum of BonusPercent for this player's decorations of `resource` within
-- range of `position`, capped at 50% total (see design doc).
function DecorationService.GetBonusMultiplier(userId, position, resource)
	local list = decorations[userId]
	if not list then return 1 end

	local totalPercent = 0
	for _, rec in ipairs(list) do
		if rec.resource == resource and (rec.position - position).Magnitude <= rec.radius then
			totalPercent += rec.bonusPercent
		end
	end
	totalPercent = math.min(totalPercent, 50)

	return 1 + totalPercent / 100
end

return DecorationService
