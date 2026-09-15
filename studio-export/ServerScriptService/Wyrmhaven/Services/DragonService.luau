local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local DragonDefs = require(Config.DragonDefs)
local GameConstants = require(Config.GameConstants)

local DragonService = {}

local HabitatService
local EconomyService
local FarmService
local DecorationService

local dragons = {} -- [dragonId] = record
local nextDragonId = 1

local function stageLabel(record, def)
	if record.stage == "Egg" then
		return string.format("%s - Egg\nGrowth: %d/%d", def.DisplayName, record.growth, def.EggGrowthRequired)
	elseif record.stage == "Baby" then
		return string.format("%s - Baby\nGrowth: %d/%d", def.DisplayName, record.growth, def.BabyGrowthRequired)
	elseif record.isBreeding then
		return string.format("%s - Adult\n(Breeding...)", def.DisplayName)
	else
		return string.format("%s - Adult\nIncome: %d/%d (Harvest!)", def.DisplayName, record.pendingIncome, def.IncomeCap)
	end
end

local function refreshVisual(record)
	local def = DragonDefs[record.element]
	local size = def.StageSizes[record.stage]
	record.part.Size = size
	record.part.Color = def.StageColors[record.stage]
	record.part.CFrame = record.slotTopCFrame + Vector3.new(0, size.Y / 2, 0)
	record.label.Text = stageLabel(record, def)
end

function DragonService.Init(habitatServiceRef, economyServiceRef, farmServiceRef)
	HabitatService = habitatServiceRef
	EconomyService = economyServiceRef
	FarmService = farmServiceRef
end

function DragonService.SetDecorationService(decorationServiceRef)
	DecorationService = decorationServiceRef
end

function DragonService.SpawnDragon(player, habitatRecord, slotIndex, element, initialState)
	local def = DragonDefs[element]
	assert(def, "Unknown dragon element: " .. tostring(element))

	local dragonId = nextDragonId
	nextDragonId += 1

	local part = Instance.new("Part")
	part.Name = def.DisplayName .. " Egg"
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = habitatRecord.model
	part:SetAttribute("DragonId", dragonId)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(200, 50)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	local record = {
		id = dragonId,
		ownerUserId = player.UserId,
		element = element,
		stage = (initialState and initialState.stage) or "Egg",
		growth = (initialState and initialState.growth) or 0,
		pendingIncome = (initialState and initialState.pendingIncome) or 0,
		isBreeding = false,
		part = part,
		label = label,
		habitatRecord = habitatRecord,
		habitatId = habitatRecord.id,
		slotIndex = slotIndex,
		slotTopCFrame = HabitatService.GetSlotCFrame(habitatRecord, slotIndex),
	}
	dragons[dragonId] = record
	HabitatService.OccupySlot(habitatRecord, slotIndex, dragonId)

	refreshVisual(record)

	return record
end

function DragonService.Feed(player, dragonId)
	local record = dragons[dragonId]
	if not record then return end
	if record.ownerUserId ~= player.UserId then return end
	if record.stage == "Adult" then return end
	if record.isBreeding then return end
	if not FarmService.TrySpendFood(player, GameConstants.FoodCostPerFeed) then return end

	local def = DragonDefs[record.element]
	record.growth += GameConstants.FoodGrowthAmount

	if record.stage == "Egg" and record.growth >= def.EggGrowthRequired then
		record.stage = "Baby"
		record.growth = 0
	elseif record.stage == "Baby" and record.growth >= def.BabyGrowthRequired then
		record.stage = "Adult"
		record.growth = 0
	end

	refreshVisual(record)
end

function DragonService.Harvest(player, dragonId)
	local record = dragons[dragonId]
	if not record then return 0 end
	if record.ownerUserId ~= player.UserId then return 0 end
	if record.stage ~= "Adult" then return 0 end
	if record.isBreeding then return 0 end

	local amount = record.pendingIncome
	record.pendingIncome = 0
	refreshVisual(record)
	EconomyService.AddCoins(player, amount)
	return amount
end

function DragonService.Interact(player, dragonId)
	local record = dragons[dragonId]
	if not record then return end
	if record.ownerUserId ~= player.UserId then return end

	if record.stage == "Adult" then
		DragonService.Harvest(player, dragonId)
	else
		DragonService.Feed(player, dragonId)
	end
end

-- Save-relevant snapshot of every dragon this player owns, keyed by nothing in
-- particular (order doesn't matter) - SaveService reconstructs slots from slotIndex.
function DragonService.GetPlayerDragons(player)
	local result = {}
	for _, record in pairs(dragons) do
		if record.ownerUserId == player.UserId then
			table.insert(result, {
				id = record.id, -- live-session id, used by BreedingService; meaningless across a save/load (ids aren't persisted as stable identity)
				habitatId = record.habitatId,
				slotIndex = record.slotIndex,
				element = record.element,
				stage = record.stage,
				growth = record.growth,
				pendingIncome = record.pendingIncome,
				isBreeding = record.isBreeding,
			})
		end
	end
	return result
end

-- Read-only snapshot for other services (e.g. BreedingService) to validate
-- against without reaching into the internal `dragons` table directly.
function DragonService.GetDragonInfo(dragonId)
	local record = dragons[dragonId]
	if not record then return nil end
	return {
		ownerUserId = record.ownerUserId,
		element = record.element,
		stage = record.stage,
		isBreeding = record.isBreeding,
	}
end

function DragonService.SetBreeding(dragonId, isBreeding)
	local record = dragons[dragonId]
	if not record then return end
	record.isBreeding = isBreeding
	refreshVisual(record)
end

-- Drops this player's dragon records; the Parts themselves are destroyed via
-- HabitatService.RemovePlayer (they're parented under the habitat/island).
function DragonService.RemovePlayerDragons(player)
	for dragonId, record in pairs(dragons) do
		if record.ownerUserId == player.UserId then
			dragons[dragonId] = nil
		end
	end
end

function DragonService.StartIncomeLoop()
	task.spawn(function()
		while true do
			task.wait(GameConstants.IncomeTickSeconds)
			for _, record in pairs(dragons) do
				if record.stage == "Adult" then
					local def = DragonDefs[record.element]
					local multiplier = DecorationService and DecorationService.GetBonusMultiplier(record.ownerUserId, record.habitatRecord.model.Position, "Coins") or 1
					local before = record.pendingIncome
					record.pendingIncome = math.min(record.pendingIncome + def.IncomeRatePerSecond * multiplier * GameConstants.IncomeTickSeconds, def.IncomeCap)
					if record.pendingIncome ~= before then
						refreshVisual(record)
					end
				end
			end
		end
	end)
end

return DragonService
