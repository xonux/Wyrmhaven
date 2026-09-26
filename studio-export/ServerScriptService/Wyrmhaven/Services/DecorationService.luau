-- Decorations: purely decorative items (trees, paving, lanterns...) bought in
-- the Shop and placed on the island grid like buildings - they take their
-- tiles, can be moved (RequestMoveStructure "Decoration") and sold back.
-- Models: ReplicatedStorage.Wyrmhaven.Assets.Decorations.<defId>, built like
-- the habitat models (invisible base part, "Visual" model, PreviewSize).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local DecorationDefs = require(Config.DecorationDefs)
local GameConstants = require(Config.GameConstants)

local DecorationService = {}

local HabitatService
local EconomyService
local decorationStatusUpdated

local templates = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets"):FindFirstChild("Decorations")

-- The bonus "charms" decorations used to be, with what they cost: a save
-- still holding one gets its Coins back.
local LEGACY_CHARM_PRICES = {
	SmallCoins = 300, MediumCoins = 800, LargeCoins = 2000,
	SmallFood = 300, MediumFood = 800, LargeFood = 2000,
}

local islands = {} -- [userId] = { nextId, items = { [id] = { id, defId, gridX, gridZ, part } } }

function DecorationService.Init(habitatServiceRef, economyServiceRef, remotesFolder)
	HabitatService = habitatServiceRef
	EconomyService = economyServiceRef

	decorationStatusUpdated = remotesFolder:FindFirstChild("DecorationStatusUpdated")
	if not decorationStatusUpdated then
		decorationStatusUpdated = Instance.new("RemoteEvent")
		decorationStatusUpdated.Name = "DecorationStatusUpdated"
		decorationStatusUpdated.Parent = remotesFolder
	end
end

local function getItem(player, id)
	local state = islands[player.UserId]
	return state and state.items[id], state
end

local function sellValue(defId)
	local def = DecorationDefs[defId]
	return def and math.floor(def.Price * GameConstants.DecorationSellRefundPercent) or 0
end

-- Builds the decoration and claims its tiles (callers checked they're free).
local function spawn(player, defId, gridX, gridZ)
	local def = DecorationDefs[defId]
	local state = islands[player.UserId]
	local id = state.nextId
	state.nextId += 1

	local center = HabitatService.GridCenterFor(player, gridX, gridZ, def.TilesX, def.TilesZ)
	local template = templates and templates:FindFirstChild(defId)
	local part
	if template then
		part = template:Clone()
		HabitatService.PivotTree(part, CFrame.new(center + Vector3.new(0, part.Size.Y / 2, 0)))
	else
		part = Instance.new("Part")
		part.Size = Vector3.new(def.TilesX * GameConstants.GridTileSize, 1, def.TilesZ * GameConstants.GridTileSize)
		part.Color = def.AccentColor
		part.Material = Enum.Material.SmoothPlastic
		part.CanCollide = false
		part.Position = center + Vector3.new(0, 0.5, 0)
	end
	part.Name = def.DisplayName .. " " .. id
	part.Anchored = true
	-- On every piece, so a tap anywhere on the model selects it.
	part:SetAttribute("DecorationId", id)
	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("DecorationId", id)
		end
	end
	part.Parent = HabitatService.GetIslandModel(player)
	HabitatService.OccupyArea(player, gridX, gridZ, def.TilesX, def.TilesZ)

	state.items[id] = { id = id, defId = defId, gridX = gridX, gridZ = gridZ, part = part }
	return id
end

-- Loaded at join, after the buildings and before the obstacles (which then
-- stay off the decorations' tiles). Whatever can't be placed back - an old
-- bonus charm, a spot taken since - is refunded.
function DecorationService.LoadPlayer(player, savedList)
	islands[player.UserId] = { nextId = 1, items = {} }
	local refund = 0
	for _, saved in ipairs(savedList or {}) do
		local def = DecorationDefs[saved.defId]
		if def and saved.gridX and saved.gridZ and HabitatService.IsAreaFree(player, saved.gridX, saved.gridZ, def.TilesX, def.TilesZ) then
			spawn(player, saved.defId, saved.gridX, saved.gridZ)
		elseif def then
			refund += def.Price
		elseif LEGACY_CHARM_PRICES[saved.defId] then
			refund += LEGACY_CHARM_PRICES[saved.defId]
		end
	end
	if refund > 0 then
		EconomyService.AddCoins(player, refund)
	end
end

-- Shop purchase at the spot chosen in placement mode. The spot is checked
-- before any Coins are spent.
function DecorationService.Place(player, defId, gridX, gridZ)
	local def = DecorationDefs[defId]
	if not def or not islands[player.UserId] then return false, "UnknownDecoration" end
	if not HabitatService.IsAreaFree(player, gridX, gridZ, def.TilesX, def.TilesZ) then return false, "TilesOccupied" end
	if not EconomyService.TrySpendCoins(player, def.Price) then return false, "InsufficientCoins" end
	spawn(player, defId, gridX, gridZ)
	return true
end

function DecorationService.Move(player, id, gridX, gridZ)
	local item = getItem(player, id)
	if not item then return false end
	local def = DecorationDefs[item.defId]
	if not HabitatService.TryMoveArea(player, item.gridX, item.gridZ, gridX, gridZ, def.TilesX, def.TilesZ) then
		return false
	end
	local center = HabitatService.GridCenterFor(player, gridX, gridZ, def.TilesX, def.TilesZ)
	HabitatService.PivotTree(item.part, CFrame.new(center + Vector3.new(0, item.part.Size.Y / 2, 0)))
	item.gridX, item.gridZ = gridX, gridZ
	return true
end

-- Refunds DecorationSellRefundPercent of its price and frees its tiles.
function DecorationService.Sell(player, id)
	local item, state = getItem(player, id)
	if not item then return false end
	local def = DecorationDefs[item.defId]
	item.part:Destroy()
	HabitatService.FreeArea(player, item.gridX, item.gridZ, def.TilesX, def.TilesZ)
	state.items[id] = nil
	EconomyService.AddCoins(player, sellValue(item.defId))
	return true
end

-- Tap on a decoration: opens its option bar on the client.
function DecorationService.RequestInfo(player, id)
	local item = getItem(player, id)
	if not item then return end
	decorationStatusUpdated:FireClient(player, {
		decorationId = id,
		defId = item.defId,
		sellValue = sellValue(item.defId),
		openRequest = true,
	})
end

-- Array of { defId, gridX, gridZ }, in placement order.
function DecorationService.GetSaveState(player)
	local state = islands[player.UserId]
	local list = {}
	if not state then return list end
	local ids = {}
	for id in pairs(state.items) do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local item = state.items[id]
		table.insert(list, { defId = item.defId, gridX = item.gridX, gridZ = item.gridZ })
	end
	return list
end

-- The parts go with the island (HabitatService.RemovePlayer).
function DecorationService.RemovePlayer(player)
	islands[player.UserId] = nil
end

return DecorationService
