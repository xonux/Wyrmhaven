local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local GameConstants = require(Config.GameConstants)

local FarmService = {}

local HabitatService
local DecorationService

-- One Farm per player, so the FarmId attribute (used by the client raycast to
-- route clicks) is just the owning player's UserId - no separate id counter needed.
local farms = {} -- [userId] = record

local function stageLabel(record)
	return string.format("Farm\nFood: %d/%d (Harvest!)", record.pendingFood, GameConstants.FarmFoodCap)
end

local function refreshVisual(record)
	record.label.Text = stageLabel(record)
end

function FarmService.Init(habitatServiceRef)
	HabitatService = habitatServiceRef
end

function FarmService.SetDecorationService(decorationServiceRef)
	DecorationService = decorationServiceRef
end

function FarmService.CreateFarm(player, initialState)
	local islandModel = HabitatService.GetIslandModel(player)
	local islandBasePosition = HabitatService.GetIslandBasePosition(player)

	local size = Vector3.new(12, 1, 12)
	local part = Instance.new("Part")
	part.Name = "Farm"
	part.Anchored = true
	part.CanCollide = false
	part.Size = size
	part.Color = Color3.fromRGB(196, 164, 92)
	part.Material = Enum.Material.Ground
	-- Island base is a 60x60x2 plate (see HabitatService); habitats cluster near
	-- offset (-10,-10), so the Farm sits on the opposite corner to stay clear of them.
	part.Position = islandBasePosition + Vector3.new(15, 1 + size.Y / 2, 15)
	part.Parent = islandModel
	part:SetAttribute("FarmId", player.UserId)

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
		ownerUserId = player.UserId,
		part = part,
		label = label,
		pendingFood = (initialState and initialState.pendingFood) or 0,
		foodStock = (initialState and initialState.foodStock) or 0,
		-- Boosted by the monetization Starter Pack Game Pass (see
		-- MonetizationService.SetFoodRateMultiplier); 1 = no boost.
		foodRateMultiplier = (initialState and initialState.foodRateMultiplier) or 1,
	}
	farms[player.UserId] = record
	refreshVisual(record)

	return record
end

function FarmService.Harvest(player, farmId)
	if farmId ~= player.UserId then return 0 end
	local record = farms[player.UserId]
	if not record then return 0 end

	local amount = record.pendingFood
	record.pendingFood = 0
	record.foodStock += amount
	refreshVisual(record)
	return amount
end

function FarmService.GetFoodStock(player)
	local record = farms[player.UserId]
	return record and record.foodStock or 0
end

function FarmService.GetSaveState(player)
	local record = farms[player.UserId]
	if not record then return { foodStock = 0, pendingFood = 0, foodRateMultiplier = 1 } end
	return { foodStock = record.foodStock, pendingFood = record.pendingFood, foodRateMultiplier = record.foodRateMultiplier }
end

-- Called by MonetizationService once the Starter Pack Game Pass is confirmed
-- owned (or immediately granted on purchase).
function FarmService.SetFoodRateMultiplier(player, multiplier)
	local record = farms[player.UserId]
	if not record then return end
	record.foodRateMultiplier = multiplier
end

function FarmService.TrySpendFood(player, amount)
	local record = farms[player.UserId]
	if not record or record.foodStock < amount then return false end
	record.foodStock -= amount
	return true
end

-- Drops this player's farm record; the Part itself is destroyed via
-- HabitatService.RemovePlayer (parented under the island model).
function FarmService.RemovePlayer(player)
	farms[player.UserId] = nil
end

function FarmService.StartAccrualLoop()
	task.spawn(function()
		while true do
			task.wait(GameConstants.FarmFoodTickSeconds)
			for _, record in pairs(farms) do
				local decorationMultiplier = DecorationService and DecorationService.GetBonusMultiplier(record.ownerUserId, record.part.Position, "Food") or 1
				local before = record.pendingFood
				record.pendingFood = math.min(
					record.pendingFood + GameConstants.FarmFoodRatePerSecond * record.foodRateMultiplier * decorationMultiplier * GameConstants.FarmFoodTickSeconds,
					GameConstants.FarmFoodCap
				)
				if record.pendingFood ~= before then
					refreshVisual(record)
				end
			end
		end
	end)
end

return FarmService
