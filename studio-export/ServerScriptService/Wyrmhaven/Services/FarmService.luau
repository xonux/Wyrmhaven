-- Farms: each grows one crop at a time (Config/FarmCrops). The player pays
-- Coins to plant, waits, then harvests its Food into a stock shared by all
-- their farms. Every player starts with one farm; more are bought in the Shop
-- (Place) and built over FarmDefs.BuildDuration, then finished with a final
-- tap, like habitats. Ready times are absolute timestamps, so crops and
-- constructions keep going while the player is offline. Each farm has a
-- level: it grows the first `level` crops of FarmCrops, and an upgrade
-- (FarmDefs.UpgradeCost) unlocks the next one once its works are over (as
-- long as that crop takes to grow) and the player's final tap - the farm
-- keeps farming meanwhile.
--
-- The model (Assets.Buildings.Farm) is a windmill beside a field. The field
-- shows the crop with a model from Assets.FarmCrops ("Sprouts" while it grows,
-- the crop's own once ripe), and the Working attribute tells the client
-- (FarmVisualController) to turn the sails while a crop grows.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local FarmCrops = require(Config.FarmCrops)
local FarmDefs = require(Config.FarmDefs)
local GameConstants = require(Config.GameConstants)
local GemSpeedUp = require(Config.GemSpeedUp)

local LevelService = require(script.Parent.LevelService)
local ReadyGlow = require(script.Parent.ReadyGlow)
local Scaffold = require(script.Parent.Scaffold)

local FarmService = {}

local HabitatService
local EconomyService
local farmStatusUpdated

-- A harvest or a final construction tap this many seconds early still
-- counts, so a client countdown that reaches zero a moment early isn't refused.
local READY_GRACE_SECONDS = 1

local GRID_TILES = GameConstants.StructureTiles.Farm
-- A new player's farm (tiles 18-20, 7-9, in the island's starting area).
local DEFAULT_GRID_X, DEFAULT_GRID_Z = 18, 7
local UNDER_CONSTRUCTION_TRANSPARENCY = 0.6
local GROWING_MODEL = "Sprouts"
-- Sparkles over the field (ripe crop) or the windmill (construction over),
-- from the farm's base part.
local FIELD_GLOW_OFFSET = Vector3.new(0, 1.8, 2.8)
local BUILDING_GLOW_OFFSET = Vector3.new(0, 6, 0)
local TAG = "Farm" -- CollectionService tag the client's FarmVisualController follows

local assets = ReplicatedStorage.Wyrmhaven:WaitForChild("Assets")
local buildingTemplates = assets:FindFirstChild("Buildings")
local farmTemplate = buildingTemplates and buildingTemplates:FindFirstChild("Farm")
local cropTemplates = assets:FindFirstChild("FarmCrops")
-- Crop models are laid out for a farm whose base part stands where the
-- template's does.
local TEMPLATE_CFRAME = farmTemplate and farmTemplate.CFrame or CFrame.new(0, 0.5, 0)

-- [userId] = { farms = { [farmId] = record }, nextFarmId, foodStock, foodRateMultiplier }
-- record = { id, part, gridX, gridZ, purchasePrice, level, buildReadyAt?, buildNotified?,
-- upgradeReadyAt?, upgradeNotified?, cropId?, cropFood?, readyAt?, shownCrop? }. Farm ids count from 1 per player;
-- the FarmId attribute on the farm's parts routes client taps.
local playerFarms = {}

-- The crop and its place in FarmCrops (the farm level that unlocks it).
local function findCrop(cropId)
	for index, crop in ipairs(FarmCrops) do
		if crop.Id == cropId then
			return crop, index
		end
	end
	return nil
end

local function countFarms(data)
	local count = 0
	for _ in pairs(data.farms) do
		count += 1
	end
	return count
end

-- The farm record and the player's farm data (nil if unknown).
local function getFarm(player, farmId)
	local data = playerFarms[player.UserId]
	return data and data.farms[farmId], data
end

-- "Growing", "Ready", or nil for an empty field.
local function cropState(record)
	if not record.cropId then
		return nil
	end
	return os.time() < record.readyAt and "Growing" or "Ready"
end

-- Swaps the model on the field (modelName nil: bare soil).
local function showCrop(record, modelName)
	local visual = record.part:FindFirstChild("Visual")
	if not visual then
		return
	end
	local current = visual:FindFirstChild("Crop")
	if current then
		current:Destroy()
	end
	local template = modelName and cropTemplates and cropTemplates:FindFirstChild(modelName)
	if not template then
		return
	end
	local crop = template:Clone()
	crop.Name = "Crop"
	local delta = record.part.CFrame * TEMPLATE_CFRAME:Inverse()
	for _, descendant in ipairs(crop:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CFrame = delta * descendant.CFrame
			descendant:SetAttribute("FarmId", record.id)
		end
	end
	crop.Parent = visual
end

-- Field, sails and sparkles, from the record: bare soil while empty or being
-- built, sprouts and turning sails while a crop grows, the ripe crop with
-- sparkles once it can be harvested. Only changes what differs, so the tick
-- loop calls it freely.
local function refreshLook(record)
	local state = cropState(record)
	local cropModel = (state == "Growing" and GROWING_MODEL) or (state == "Ready" and record.cropId) or nil
	if record.shownCrop ~= cropModel then
		record.shownCrop = cropModel
		showCrop(record, cropModel)
	end
	record.part:SetAttribute("Working", state == "Growing")
	-- Works over (construction or upgrade): sparkles over the windmill instead
	-- of the field.
	local worksDone = (record.buildReadyAt ~= nil and record.buildNotified == true)
		or (record.upgradeReadyAt ~= nil and record.upgradeNotified == true)
	local offset = worksDone and BUILDING_GLOW_OFFSET or FIELD_GLOW_OFFSET
	local glow = record.part:FindFirstChild("ReadyGlow")
	if glow and glow.Position ~= offset then
		ReadyGlow.Set(record.part, false)
	end
	ReadyGlow.Set(record.part, worksDone or state == "Ready", offset)
end

-- See-through windmill inside a wooden scaffold while a bought farm is built.
local function setUnderConstruction(record, building)
	local visual = record.part:FindFirstChild("Visual")
	if visual then
		for _, descendant in ipairs(visual:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Transparency = building and UNDER_CONSTRUCTION_TRANSPARENCY or 0
			end
		end
	end
	Scaffold.Set(record.part, building)
end

-- Click-to-open bar status (see FarmPanelController). planted is nil while
-- the field is empty, buildSecondsLeft only while the farm is being built,
-- upgrade (the next level's cost and crop) nil at the top level.
local function buildStatus(player, farmId)
	local record, data = getFarm(player, farmId)
	if not record then
		return nil
	end
	local planted = nil
	if record.cropId then
		planted = {
			cropId = record.cropId,
			food = record.cropFood,
			secondsLeft = math.max(0, record.readyAt - os.time()),
		}
	end
	local upgrade = nil
	if record.level < FarmDefs.MaxLevel then
		upgrade = {
			level = record.level + 1,
			cost = FarmDefs.UpgradeCost(record.level + 1),
			duration = FarmDefs.UpgradeDuration(record.level + 1),
			cropId = FarmCrops[record.level + 1].Id,
		}
	end
	return {
		farmId = farmId,
		foodStock = data.foodStock,
		-- The Food bonus this player has (1 = none): the Farm bar prices every
		-- crop with it, so what it announces is what the harvest gives.
		foodMultiplier = data.foodRateMultiplier,
		planted = planted,
		level = record.level,
		maxLevel = FarmDefs.MaxLevel,
		upgrade = upgrade,
		upgradeSecondsLeft = record.upgradeReadyAt and math.max(0, record.upgradeReadyAt - os.time()) or nil,
		buildSecondsLeft = record.buildReadyAt and math.max(0, record.buildReadyAt - os.time()) or nil,
		-- Never the last farm: without one there's no Food at all.
		canSell = not record.buildReadyAt and not record.upgradeReadyAt and not record.cropId and countFarms(data) > 1,
		sellValue = math.floor(record.purchasePrice * FarmDefs.SellRefundPercent),
	}
end

-- extra: optional fields merged into the push - collected (Food just
-- harvested, so the client animates only real payouts), plantError,
-- speedUpError or upgradeError.
local function pushStatus(player, farmId, openRequest, extra)
	local status = buildStatus(player, farmId)
	if not status then return end
	status.openRequest = openRequest or false
	for key, value in pairs(extra or {}) do
		status[key] = value
	end
	farmStatusUpdated:FireClient(player, status)
end

function FarmService.Init(habitatServiceRef, economyServiceRef, remotesFolder)
	HabitatService = habitatServiceRef
	EconomyService = economyServiceRef

	farmStatusUpdated = remotesFolder:FindFirstChild("FarmStatusUpdated")
	if not farmStatusUpdated then
		farmStatusUpdated = Instance.new("RemoteEvent")
		farmStatusUpdated.Name = "FarmStatusUpdated"
		farmStatusUpdated.Parent = remotesFolder
	end
end

-- Explicit click on a farm: forces its bar open on the client.
function FarmService.RequestInfo(player, farmId)
	pushStatus(player, farmId, true)
end

-- Silent refresh (e.g. to report a refused planting) - never reopens the bar.
function FarmService.RefreshStatus(player, farmId, extra)
	pushStatus(player, farmId, false, extra)
end

-- A farm at grid tile (gridX, gridZ). buildReadyAt: os.time() its
-- construction ends, nil for a finished farm. crop: saved fields {level,
-- upgradeReadyAt, cropId, cropFood, readyAt}, if any (a new farm is level 1).
local function createFarm(player, data, gridX, gridZ, purchasePrice, buildReadyAt, crop)
	local farmId = data.nextFarmId
	data.nextFarmId += 1

	local center = HabitatService.GridCenterFor(player, gridX, gridZ, GRID_TILES, GRID_TILES)
	local part
	if farmTemplate then
		part = farmTemplate:Clone()
		HabitatService.PivotTree(part, CFrame.new(center + Vector3.new(0, part.Size.Y / 2, 0)))
	else
		local side = GRID_TILES * GameConstants.GridTileSize
		part = Instance.new("Part")
		part.Size = Vector3.new(side, 1, side)
		part.Color = Color3.fromRGB(196, 164, 92)
		part.Material = Enum.Material.Ground
		part.Position = center + Vector3.new(0, part.Size.Y / 2, 0)
	end
	part.Name = "Farm " .. farmId
	part.Anchored = true
	part.CanCollide = false
	-- On every piece, so a tap on the windmill or the field opens the farm too.
	part:SetAttribute("FarmId", farmId)
	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("FarmId", farmId)
		end
	end
	CollectionService:AddTag(part, TAG)
	HabitatService.OccupyArea(player, gridX, gridZ, GRID_TILES, GRID_TILES)

	local record = {
		id = farmId,
		part = part,
		gridX = gridX,
		gridZ = gridZ,
		purchasePrice = purchasePrice or 0,
		level = math.clamp((crop and crop.level) or 1, 1, FarmDefs.MaxLevel),
		buildReadyAt = buildReadyAt, -- nothing is planted before the final tap
		upgradeReadyAt = crop and crop.upgradeReadyAt, -- set while an upgrade's works run
	}
	if record.upgradeReadyAt then
		Scaffold.Set(part, true)
	end
	if crop and crop.cropId and crop.cropFood and crop.readyAt then
		record.cropId, record.cropFood, record.readyAt = crop.cropId, crop.cropFood, crop.readyAt
	end
	if buildReadyAt then
		setUnderConstruction(record, true)
	end
	refreshLook(record)
	part.Parent = HabitatService.GetIslandModel(player)
	data.farms[farmId] = record
	return record
end

-- state: the save's Farm entry - { foodStock, foodRateMultiplier, farms = {
-- {gridX, gridZ, purchasePrice, level, buildReadyAt?, cropId?, cropFood?, readyAt?} } } -
-- or nil for a new player, who gets one farm at the default spot. Saves from
-- before farms could be bought hold their only farm's fields at the top level
-- instead, maybe with the old non-stop Farm's unharvested pendingFood. Runs
-- before the other buildings claim their tiles (see Server setupPlayer).
function FarmService.LoadPlayer(player, state)
	HabitatService.EnsureIsland(player)
	state = state or {}
	local data = {
		farms = {},
		nextFarmId = 1,
		foodStock = (state.foodStock or 0) + math.floor(state.pendingFood or 0),
		-- Boosted by the monetization Starter Pack Game Pass (see
		-- MonetizationService.SetFoodRateMultiplier); 1 = no boost.
		foodRateMultiplier = state.foodRateMultiplier or 1,
	}
	playerFarms[player.UserId] = data

	local saved = state.farms
	if not saved or #saved == 0 then
		saved = { { gridX = state.gridX, gridZ = state.gridZ, cropId = state.cropId, cropFood = state.cropFood, readyAt = state.readyAt } }
	end
	for _, farmSave in ipairs(saved) do
		local gridX, gridZ = farmSave.gridX or DEFAULT_GRID_X, farmSave.gridZ or DEFAULT_GRID_Z
		if not HabitatService.IsAreaFree(player, gridX, gridZ, GRID_TILES, GRID_TILES) then
			gridX, gridZ = HabitatService.FindFreeGridSlot(player, GRID_TILES, GRID_TILES)
		end
		if gridX then
			createFarm(player, data, gridX, gridZ, farmSave.purchasePrice, farmSave.buildReadyAt, farmSave)
		end
	end
end

-- Buys a farm at grid tile (gridX, gridZ), from the Shop's placement mode.
-- Checks the spot before spending, so a refused placement never charges. The
-- farm is then built over FarmDefs.BuildDuration; its XP comes at the end.
function FarmService.Place(player, gridX, gridZ)
	local data = playerFarms[player.UserId]
	if not data then
		return false, "NotFound"
	end
	if not HabitatService.IsAreaFree(player, gridX, gridZ, GRID_TILES, GRID_TILES) then
		return false, "TilesOccupied"
	end
	local price = FarmDefs.GetPrice(countFarms(data))
	if not EconomyService.TrySpendCoins(player, price) then
		return false, "InsufficientCoins"
	end
	createFarm(player, data, gridX, gridZ, price, os.time() + FarmDefs.BuildDuration)
	return true
end

-- Farms owned, the ones being built included (sets the next one's price).
function FarmService.GetFarmCount(player)
	local data = playerFarms[player.UserId]
	return data and countFarms(data) or 0
end

-- Pays for and plants `cropId`. Returns true, or false plus a reason the Farm
-- bar explains ("Busy", "Building", "Locked", "InsufficientCoins").
function FarmService.Plant(player, farmId, cropId)
	local record, data = getFarm(player, farmId)
	if not record then return false, "NotFound" end
	if record.buildReadyAt then return false, "Building" end
	if record.cropId then return false, "Busy" end
	local crop, cropIndex = findCrop(cropId)
	if not crop then return false, "UnknownCrop" end
	if cropIndex > record.level then return false, "Locked" end
	if not EconomyService.TrySpendCoins(player, crop.Price) then return false, "InsufficientCoins" end

	-- The Starter Pack Food bonus is locked in at planting.
	record.cropId = crop.Id
	record.cropFood = FarmDefs.FoodFor(crop, data.foodRateMultiplier)
	record.readyAt = os.time() + crop.Duration
	refreshLook(record)
	pushStatus(player, farmId, false)
	return true
end

-- Skips the rest of a growing crop for Gems (Config/GemSpeedUp): it's ripe
-- at once, ready to harvest. A refusal is pushed back as speedUpError.
function FarmService.SpeedUpCrop(player, farmId)
	local record = getFarm(player, farmId)
	if not record or cropState(record) ~= "Growing" then
		return false
	end
	if not EconomyService.TrySpendGems(player, GemSpeedUp(record.readyAt - os.time())) then
		pushStatus(player, farmId, false, { speedUpError = "NotEnoughGems" })
		return false
	end
	record.readyAt = os.time()
	refreshLook(record)
	pushStatus(player, farmId, false)
	return true
end

-- Moves a grown crop into the Food stock. Returns the Food harvested (0 if
-- nothing is ready yet).
function FarmService.Harvest(player, farmId)
	local record, data = getFarm(player, farmId)
	if not record or not record.cropId then return 0 end
	if os.time() + READY_GRACE_SECONDS < record.readyAt then return 0 end

	local amount = record.cropFood
	data.foodStock += amount
	-- XP for the Coins this crop cost, earned at harvest.
	local crop = findCrop(record.cropId)
	LevelService.AddXp(player, crop and crop.Price or 0)
	record.cropId, record.cropFood, record.readyAt = nil, nil, nil
	refreshLook(record)
	pushStatus(player, farmId, false, { collected = amount })
	return amount
end

-- Timer over: sparkles tell the player the construction waits for their tap.
local function markConstructionReady(player, record)
	record.buildNotified = true
	refreshLook(record)
	pushStatus(player, record.id, false)
end

-- Watches constructions and upgrade works reach their end time (including
-- ones that ended while the player was away) and crops ripen, to update the
-- farms' look.
function FarmService.StartTickLoop()
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for userId, data in pairs(playerFarms) do
				local player = Players:GetPlayerByUserId(userId)
				if player then
					for _, record in pairs(data.farms) do
						if record.buildReadyAt and not record.buildNotified and now >= record.buildReadyAt then
							markConstructionReady(player, record)
						elseif record.upgradeReadyAt and not record.upgradeNotified and now >= record.upgradeReadyAt then
							-- (as markUpgradeReady, declared further down)
							record.upgradeNotified = true
							refreshLook(record)
							pushStatus(player, record.id, false)
						elseif record.cropId then
							refreshLook(record)
						end
					end
				end
			end
		end
	end)
end

-- The player's final tap on a construction whose time is up: the windmill
-- takes its real look, the field can be planted, and they get the XP of its
-- price.
function FarmService.FinishConstruction(player, farmId)
	local record = getFarm(player, farmId)
	if not record or not record.buildReadyAt or os.time() + READY_GRACE_SECONDS < record.buildReadyAt then
		return false
	end
	record.buildReadyAt, record.buildNotified = nil, nil
	setUnderConstruction(record, false)
	refreshLook(record)
	LevelService.AddXp(player, record.purchasePrice)
	pushStatus(player, farmId, false)
	return true
end

-- Skips the rest of the construction for Gems (Config/GemSpeedUp). It still
-- waits for the final tap. A refusal is pushed back as speedUpError.
function FarmService.SpeedUpConstruction(player, farmId)
	local record = getFarm(player, farmId)
	if not record or not record.buildReadyAt then
		return false
	end
	local secondsLeft = record.buildReadyAt - os.time()
	if secondsLeft <= 0 then
		return false
	end
	if not EconomyService.TrySpendGems(player, GemSpeedUp(secondsLeft)) then
		pushStatus(player, farmId, false, { speedUpError = "NotEnoughGems" })
		return false
	end
	record.buildReadyAt = os.time()
	markConstructionReady(player, record)
	return true
end

-- Pays for the farm's next level and starts its works (as long as the crop it
-- unlocks takes to grow, in a scaffold). The farm keeps farming meanwhile;
-- the crop only unlocks at the final tap (FinishUpgrade). Returns true, or
-- false plus a reason also pushed as upgradeError ("Building", "Busy",
-- "MaxLevel", "InsufficientCoins").
function FarmService.Upgrade(player, farmId)
	local record = getFarm(player, farmId)
	if not record then return false, "NotFound" end
	local reason = nil
	local cost = FarmDefs.UpgradeCost(record.level + 1)
	if record.buildReadyAt then
		reason = "Building"
	elseif record.upgradeReadyAt then
		reason = "Busy"
	elseif record.level >= FarmDefs.MaxLevel or not cost then
		reason = "MaxLevel"
	elseif not EconomyService.TrySpendCoins(player, cost) then
		reason = "InsufficientCoins"
	end
	if reason then
		pushStatus(player, farmId, false, { upgradeError = reason })
		return false, reason
	end
	record.upgradeReadyAt = os.time() + FarmDefs.UpgradeDuration(record.level + 1)
	Scaffold.Set(record.part, true)
	pushStatus(player, farmId, false)
	return true
end

-- Works over: sparkles tell the player the upgrade waits for their tap.
local function markUpgradeReady(player, record)
	record.upgradeNotified = true
	refreshLook(record)
	pushStatus(player, record.id, false)
end

-- The player's final tap on upgrade works whose time is up: the farm reaches
-- its next level (its next crop), and they get the XP of its cost.
function FarmService.FinishUpgrade(player, farmId)
	local record = getFarm(player, farmId)
	if not record or not record.upgradeReadyAt or os.time() + READY_GRACE_SECONDS < record.upgradeReadyAt then
		return false
	end
	local cost = FarmDefs.UpgradeCost(record.level + 1) or 0
	record.level = math.min(record.level + 1, FarmDefs.MaxLevel)
	record.upgradeReadyAt, record.upgradeNotified = nil, nil
	Scaffold.Set(record.part, false)
	refreshLook(record)
	LevelService.AddXp(player, cost)
	pushStatus(player, farmId, false)
	return true
end

-- Skips the rest of the upgrade works for Gems (Config/GemSpeedUp). It still
-- waits for the final tap. A refusal is pushed back as speedUpError.
function FarmService.SpeedUpUpgrade(player, farmId)
	local record = getFarm(player, farmId)
	if not record or not record.upgradeReadyAt then
		return false
	end
	local secondsLeft = record.upgradeReadyAt - os.time()
	if secondsLeft <= 0 then
		return false
	end
	if not EconomyService.TrySpendGems(player, GemSpeedUp(secondsLeft)) then
		pushStatus(player, farmId, false, { speedUpError = "NotEnoughGems" })
		return false
	end
	record.upgradeReadyAt = os.time()
	markUpgradeReady(player, record)
	return true
end

-- Sells an empty farm for FarmDefs.SellRefundPercent of its price (nothing for
-- the free first one). Refused while it's being built or growing a crop, and
-- for the player's last farm.
function FarmService.Sell(player, farmId)
	local status = buildStatus(player, farmId)
	if not status or not status.canSell then
		return false
	end
	local record, data = getFarm(player, farmId)
	record.part:Destroy()
	HabitatService.FreeArea(player, record.gridX, record.gridZ, GRID_TILES, GRID_TILES)
	data.farms[farmId] = nil
	EconomyService.AddCoins(player, status.sellValue)
	return true
end

-- Food stock shared by all the player's farms.
function FarmService.GetFoodStock(player)
	local data = playerFarms[player.UserId]
	return data and data.foodStock or 0
end

-- Farms in creation order (the next load numbers them 1, 2, 3... again).
function FarmService.GetSaveState(player)
	local data = playerFarms[player.UserId]
	if not data then
		return nil
	end
	local ids = {}
	for id in pairs(data.farms) do
		table.insert(ids, id)
	end
	table.sort(ids)
	local farms = {}
	for _, id in ipairs(ids) do
		local record = data.farms[id]
		table.insert(farms, {
			gridX = record.gridX,
			gridZ = record.gridZ,
			purchasePrice = record.purchasePrice,
			level = record.level,
			buildReadyAt = record.buildReadyAt,
			upgradeReadyAt = record.upgradeReadyAt,
			cropId = record.cropId,
			cropFood = record.cropFood,
			readyAt = record.readyAt,
		})
	end
	return { foodStock = data.foodStock, foodRateMultiplier = data.foodRateMultiplier, farms = farms }
end

function FarmService.MoveFarm(player, farmId, gridX, gridZ)
	local record = getFarm(player, farmId)
	if not record then return false end
	if not HabitatService.TryMoveArea(player, record.gridX, record.gridZ, gridX, gridZ, GRID_TILES, GRID_TILES) then
		return false
	end
	local center = HabitatService.GridCenterFor(player, gridX, gridZ, GRID_TILES, GRID_TILES)
	HabitatService.PivotTree(record.part, CFrame.new(center + Vector3.new(0, record.part.Size.Y / 2, 0)))
	record.gridX, record.gridZ = gridX, gridZ
	return true
end

-- Called by MonetizationService once the Starter Pack Game Pass is confirmed
-- owned (or immediately granted on purchase). Multiplies the Food of crops
-- planted from then on, on every farm.
function FarmService.SetFoodRateMultiplier(player, multiplier)
	local data = playerFarms[player.UserId]
	if not data then return end
	data.foodRateMultiplier = multiplier
end

function FarmService.TrySpendFood(player, amount)
	local data = playerFarms[player.UserId]
	if not data or data.foodStock < amount then return false end
	data.foodStock -= amount
	return true
end

-- Food added straight to the stock (the /give test command).
function FarmService.AddFood(player, amount)
	local data = playerFarms[player.UserId]
	if not data then return end
	data.foodStock += amount
end

-- Drops this player's farm records; the parts themselves are destroyed via
-- HabitatService.RemovePlayer (parented under the island model).
function FarmService.RemovePlayer(player)
	playerFarms[player.UserId] = nil
end

return FarmService
