local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Players.CharacterAutoLoads = false -- top-down management camera, no on-foot avatar
-- workspace.StreamingEnabled is set to false in Studio (Edit-time only property, a live Script can't write it)

local Services = ServerScriptService.Wyrmhaven.Services
local HabitatService = require(Services.HabitatService)
local DragonService = require(Services.DragonService)
local EconomyService = require(Services.EconomyService)
local FarmService = require(Services.FarmService)
local SaveService = require(Services.SaveService)
local HudService = require(Services.HudService)
local MonetizationService = require(Services.MonetizationService)
local ShopService = require(Services.ShopService)
local BreedingService = require(Services.BreedingService)
local DecorationService = require(Services.DecorationService)
local IncubatorService = require(Services.IncubatorService)
local IslandService = require(Services.IslandService)
local LevelService = require(Services.LevelService)
local PveService = require(Services.PveService)
local DevCommands = require(Services.DevCommands)

LevelService.Init(EconomyService) -- Gems at each level up
DragonService.Init(HabitatService, EconomyService, FarmService)
DragonService.StartIncomeLoop()

SaveService.Init(HabitatService, DragonService, EconomyService, FarmService, IncubatorService)
SaveService.StartAutosaveLoop()

MonetizationService.Init(EconomyService, FarmService)

ShopService.Init(HabitatService, DragonService, EconomyService)

ShopService.SetIncubatorService(IncubatorService)
SaveService.SetDecorationService(DecorationService)
SaveService.SetBreedingService(BreedingService)
SaveService.SetIslandService(IslandService)
-- "/resetdata" and "/give" in the chat (testing)
DevCommands.Init({
	SaveService = SaveService,
	EconomyService = EconomyService,
	FarmService = FarmService,
	LevelService = LevelService,
	IncubatorService = IncubatorService,
	HudService = HudService,
})

local wyrmhaven = ReplicatedStorage.Wyrmhaven
local remotes = wyrmhaven:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = wyrmhaven

local function getOrCreateRemoteEvent(name)
	local existing = remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remotes
	return event
end

local requestInteractFarm = getOrCreateRemoteEvent("RequestInteractFarm")
local requestCollectFarm = getOrCreateRemoteEvent("RequestCollectFarm")
local requestPlantCrop = getOrCreateRemoteEvent("RequestPlantCrop")
local requestPlaceFarm = getOrCreateRemoteEvent("RequestPlaceFarm")
local requestFinishFarm = getOrCreateRemoteEvent("RequestFinishFarm")
local requestSpeedUpFarm = getOrCreateRemoteEvent("RequestSpeedUpFarm")
local requestSellFarm = getOrCreateRemoteEvent("RequestSellFarm")
local requestUpgradeFarm = getOrCreateRemoteEvent("RequestUpgradeFarm")
local setCameraTarget = getOrCreateRemoteEvent("SetCameraTarget")
local requestBuyDragon = getOrCreateRemoteEvent("RequestBuyDragon")
local shopPurchaseResult = getOrCreateRemoteEvent("ShopPurchaseResult")
local requestInteractNursery = getOrCreateRemoteEvent("RequestInteractNursery")
local requestStartBreeding = getOrCreateRemoteEvent("RequestStartBreeding")
local requestCollectEgg = getOrCreateRemoteEvent("RequestCollectEgg")
local requestPlaceNursery = getOrCreateRemoteEvent("RequestPlaceNursery")
local requestUpgradeHabitat = getOrCreateRemoteEvent("RequestUpgradeHabitat")
local requestPlaceDecoration = getOrCreateRemoteEvent("RequestPlaceDecoration")
local requestInteractDecoration = getOrCreateRemoteEvent("RequestInteractDecoration")
local requestSellDecoration = getOrCreateRemoteEvent("RequestSellDecoration")
local requestPlaceHabitat = getOrCreateRemoteEvent("RequestPlaceHabitat")
local requestMoveStructure = getOrCreateRemoteEvent("RequestMoveStructure")
local requestInteractHabitat = getOrCreateRemoteEvent("RequestInteractHabitat")
local requestInteractDragon = getOrCreateRemoteEvent("RequestInteractDragon")
local requestRenameDragon = getOrCreateRemoteEvent("RequestRenameDragon")
local requestFeedDragon = getOrCreateRemoteEvent("RequestFeedDragon")
local requestMoveDragon = getOrCreateRemoteEvent("RequestMoveDragon")
local requestCollectHabitatIncome = getOrCreateRemoteEvent("RequestCollectHabitatIncome")
local requestSellHabitat = getOrCreateRemoteEvent("RequestSellHabitat")
local requestInteractIncubator = getOrCreateRemoteEvent("RequestInteractIncubator")
local requestPlaceEggInHabitat = getOrCreateRemoteEvent("RequestPlaceEggInHabitat")
local requestSpeedUpEgg = getOrCreateRemoteEvent("RequestSpeedUpEgg")
local requestUpgradeIncubator = getOrCreateRemoteEvent("RequestUpgradeIncubator")
local requestInteractObstacle = getOrCreateRemoteEvent("RequestInteractObstacle")
local requestClearObstacle = getOrCreateRemoteEvent("RequestClearObstacle")
local requestFinishObstacle = getOrCreateRemoteEvent("RequestFinishObstacle")
local requestSpeedUpObstacle = getOrCreateRemoteEvent("RequestSpeedUpObstacle")
local requestFinishHabitat = getOrCreateRemoteEvent("RequestFinishHabitat")
local requestSpeedUpHabitat = getOrCreateRemoteEvent("RequestSpeedUpHabitat")
local requestSpeedUpBreeding = getOrCreateRemoteEvent("RequestSpeedUpBreeding")
local requestSpeedUpCrop = getOrCreateRemoteEvent("RequestSpeedUpCrop")
local requestSellDragon = getOrCreateRemoteEvent("RequestSellDragon")
local dragonSold = getOrCreateRemoteEvent("DragonSold") -- (dragonId, coins) to the seller
-- Exploration map (PveService)
local requestPveInfo = getOrCreateRemoteEvent("RequestPveInfo")
local requestPveTeam = getOrCreateRemoteEvent("RequestPveTeam")
local requestPveFight = getOrCreateRemoteEvent("RequestPveFight")
local requestPveAction = getOrCreateRemoteEvent("RequestPveAction")
getOrCreateRemoteEvent("PveStatusUpdated")
getOrCreateRemoteEvent("PveBattleStarted")
getOrCreateRemoteEvent("PveBattleUpdate")
getOrCreateRemoteEvent("PveBattleResult")

FarmService.Init(HabitatService, EconomyService, remotes)
FarmService.StartTickLoop()
HabitatService.Init(DragonService, EconomyService, remotes)
HabitatService.StartConstructionLoop()
DecorationService.Init(HabitatService, EconomyService, remotes)
DragonService.InitRemotes(remotes)
IncubatorService.Init(HabitatService, DragonService, EconomyService, remotes)
IncubatorService.StartTickLoop(function()
	return Players:GetPlayers()
end)

BreedingService.Init(HabitatService, DragonService, IncubatorService, remotes, EconomyService)
BreedingService.StartStatusLoop(function()
	return Players:GetPlayers()
end)

HudService.Init(remotes, EconomyService, FarmService, HabitatService, BreedingService)
HudService.StartPushLoop(function()
	return Players:GetPlayers()
end)

IslandService.Init(HabitatService, EconomyService, HudService, remotes)
IslandService.StartTickLoop()

PveService.Init(DragonService, EconomyService, FarmService, LevelService, HudService, remotes)

-- The exploration map: open it, pick the team that fights, run a stage.
requestPveInfo.OnServerEvent:Connect(function(player)
	PveService.RequestInfo(player)
end)

requestPveTeam.OnServerEvent:Connect(function(player, dragonIds)
	if typeof(dragonIds) ~= "table" then return end
	if PveService.SetTeam(player, dragonIds) then
		PveService.RefreshStatus(player)
	end
end)

-- Starts the fight; it then runs turn by turn (PveBattleUpdate) and pays out
-- at the end (PveBattleResult), so there is nothing to do here on success.
requestPveFight.OnServerEvent:Connect(function(player, levelId)
	if typeof(levelId) ~= "number" then return end
	local ok, reason = PveService.Fight(player, math.floor(levelId))
	if not ok then
		PveService.RefreshStatus(player, { fightError = reason })
	end
end)

-- The player's move on their dragon's turn.
requestPveAction.OnServerEvent:Connect(function(player, token, skillId, targetKey)
	if typeof(token) ~= "number" or typeof(skillId) ~= "string" then return end
	if targetKey ~= nil and typeof(targetKey) ~= "string" then return end
	PveService.SubmitAction(player, token, skillId, targetKey)
end)

requestInteractObstacle.OnServerEvent:Connect(function(player, obstacleId)
	if typeof(obstacleId) ~= "string" then return end
	IslandService.RequestInfo(player, obstacleId)
end)

requestClearObstacle.OnServerEvent:Connect(function(player, obstacleId)
	if typeof(obstacleId) ~= "string" then return end
	IslandService.StartClearing(player, obstacleId)
end)

requestFinishObstacle.OnServerEvent:Connect(function(player, obstacleId)
	if typeof(obstacleId) ~= "string" then return end
	IslandService.FinishClearing(player, obstacleId) -- pushes the HUD itself (freed tiles, XP)
end)

requestSpeedUpObstacle.OnServerEvent:Connect(function(player, obstacleId)
	if typeof(obstacleId) ~= "string" then return end
	IslandService.SpeedUpClearing(player, obstacleId)
end)

-- Construction of a habitat bought in the Shop: final tap, or Gems to skip the wait.
-- The same two remotes serve an upgrade's works (a habitat never has both).
requestFinishHabitat.OnServerEvent:Connect(function(player, habitatId)
	if typeof(habitatId) ~= "number" then return end
	if HabitatService.FinishConstruction(player, habitatId) or HabitatService.FinishUpgrade(player, habitatId) then
		HudService.PushUpdate(player) -- XP
	end
end)

requestSpeedUpHabitat.OnServerEvent:Connect(function(player, habitatId)
	if typeof(habitatId) ~= "number" then return end
	if HabitatService.SpeedUpConstruction(player, habitatId) or HabitatService.SpeedUpUpgrade(player, habitatId) then
		HudService.PushUpdate(player) -- Gems spent
	end
end)

-- A habitat's next level: pays and starts the works (refusals come back as
-- the habitat's upgradeError).
requestUpgradeHabitat.OnServerEvent:Connect(function(player, habitatId)
	if typeof(habitatId) ~= "number" then return end
	if HabitatService.StartUpgrade(player, habitatId) then
		HudService.PushUpdate(player) -- Coins spent
	end
end)

-- silent = true: live refresh of an already-open popup (never forces it open).
-- A real tap on the habitat also harvests its stored Coins (RequestInfo).
requestInteractHabitat.OnServerEvent:Connect(function(player, habitatId, silent)
	if typeof(habitatId) ~= "number" then return end
	if silent == true then
		HabitatService.RefreshStatus(player, habitatId)
	elseif HabitatService.RequestInfo(player, habitatId) > 0 then
		HudService.PushUpdate(player)
	end
end)

requestInteractDragon.OnServerEvent:Connect(function(player, dragonId, silent)
	if typeof(dragonId) ~= "number" then return end
	if silent == true then
		DragonService.RefreshStatus(player, dragonId)
	else
		DragonService.RequestInfo(player, dragonId)
	end
end)

requestRenameDragon.OnServerEvent:Connect(function(player, dragonId, newName)
	if typeof(dragonId) ~= "number" or typeof(newName) ~= "string" then return end
	local ok = DragonService.Rename(player, dragonId, newName)
	-- Always answer, even on refusal, so the popup drops back to the saved name.
	DragonService.RefreshStatus(player, dragonId, { renamed = ok })
	local habitatId = DragonService.GetDragonHabitatId(player, dragonId)
	if habitatId then
		HabitatService.RefreshStatus(player, habitatId)
	end
end)

requestFeedDragon.OnServerEvent:Connect(function(player, dragonId)
	if typeof(dragonId) ~= "number" then return end
	local habitatId = DragonService.GetDragonHabitatId(player, dragonId)
	-- ok, then whether this feeding grew the dragon into an Adult.
	local ok, result = DragonService.Feed(player, dragonId)
	if habitatId then
		HabitatService.RefreshStatus(player, habitatId)
	end
	DragonService.RefreshStatus(player, dragonId, {
		feedError = not ok and result or nil,
		grewUp = ok and result == true or nil,
	})
	if ok then
		HudService.PushUpdate(player) -- show the Food spent right away, not on the next tick
	end
end)

-- A dragon changing habitat (DragonScreen's Move, then a tap on the
-- chosen habitat): the new habitat's bar opens on success, a refusal comes
-- back as the dragon's moveError.
requestMoveDragon.OnServerEvent:Connect(function(player, dragonId, habitatId)
	if typeof(dragonId) ~= "number" or typeof(habitatId) ~= "number" then return end
	local ok, reason = DragonService.MoveToOtherHabitat(player, dragonId, habitatId)
	if ok then
		HabitatService.RequestInfo(player, habitatId)
	else
		DragonService.RefreshStatus(player, dragonId, { moveError = reason })
	end
end)

requestCollectHabitatIncome.OnServerEvent:Connect(function(player, habitatId)
	if typeof(habitatId) ~= "number" then return end
	local amount = HabitatService.CollectIncome(player, habitatId)
	if amount and amount > 0 then
		HudService.PushUpdate(player)
	end
end)

requestSellHabitat.OnServerEvent:Connect(function(player, habitatId)
	if typeof(habitatId) ~= "number" then return end
	local ok = HabitatService.Sell(player, habitatId)
	if ok then
		HudService.PushUpdate(player)
	end
end)

requestInteractIncubator.OnServerEvent:Connect(function(player, incubatorId)
	if typeof(incubatorId) ~= "number" then return end
	IncubatorService.RequestInfo(player, incubatorId)
end)

requestPlaceEggInHabitat.OnServerEvent:Connect(function(player, dragonId, habitatId)
	if typeof(dragonId) ~= "number" then return end
	if habitatId ~= nil and typeof(habitatId) ~= "number" then return end
	if IncubatorService.PlaceInHabitat(player, dragonId, habitatId) then
		HudService.PushUpdate(player) -- the hatching XP, given at placement
	end
end)

requestSpeedUpEgg.OnServerEvent:Connect(function(player, dragonId)
	if typeof(dragonId) ~= "number" then return end
	local ok = IncubatorService.SpeedUpWithGems(player, dragonId)
	if ok then
		HudService.PushUpdate(player)
	end
end)

-- Sells a dragon: a hatchling in the Incubator instead of placing it (its XP
-- comes all the same), or one living in a habitat (DragonScreen's Sell),
-- whose habitat's bar then opens. A refusal comes back as the dragon's
-- sellError.
requestSellDragon.OnServerEvent:Connect(function(player, dragonId)
	if typeof(dragonId) ~= "number" then return end
	local ok, coins, habitatId = IncubatorService.SellHatchling(player, dragonId)
	if not ok then
		ok, coins, habitatId = DragonService.Sell(player, dragonId)
	end
	if not ok then
		DragonService.RefreshStatus(player, dragonId, { sellError = coins })
		return
	end
	HudService.PushUpdate(player) -- Coins, and XP for a hatchling
	dragonSold:FireClient(player, dragonId, coins)
	if habitatId then
		HabitatService.OpenInfo(player, habitatId)
	end
end)

-- A new nest on the Incubator's rock, bought with Gems.
requestUpgradeIncubator.OnServerEvent:Connect(function(player)
	if IncubatorService.UpgradeNests(player) then
		HudService.PushUpdate(player) -- Gems spent
	end
end)

requestInteractFarm.OnServerEvent:Connect(function(player, farmId)
	if typeof(farmId) ~= "number" then return end
	FarmService.RequestInfo(player, farmId)
end)

requestCollectFarm.OnServerEvent:Connect(function(player, farmId)
	if typeof(farmId) ~= "number" then return end
	local amount = FarmService.Harvest(player, farmId)
	if amount and amount > 0 then
		HudService.PushUpdate(player)
	end
end)

-- Gems to ripen a growing crop at once.
requestSpeedUpCrop.OnServerEvent:Connect(function(player, farmId)
	if typeof(farmId) ~= "number" then return end
	if FarmService.SpeedUpCrop(player, farmId) then
		HudService.PushUpdate(player) -- Gems spent
	end
end)

requestPlantCrop.OnServerEvent:Connect(function(player, farmId, cropId)
	if typeof(farmId) ~= "number" or typeof(cropId) ~= "string" then return end
	local ok, reason = FarmService.Plant(player, farmId, cropId)
	if ok then
		HudService.PushUpdate(player) -- show the Coins spent right away
	else
		FarmService.RefreshStatus(player, farmId, { plantError = reason })
	end
end)

-- A farm bought in the Shop (grid placement confirmed): Coins are spent here.
requestPlaceFarm.OnServerEvent:Connect(function(player, gridX, gridZ)
	if typeof(gridX) ~= "number" or typeof(gridZ) ~= "number" then return end
	local ok, reason = FarmService.Place(player, math.floor(gridX), math.floor(gridZ))
	if ok then
		HudService.PushUpdate(player)
	end
	shopPurchaseResult:FireClient(player, ok, reason, "Farm")
end)

-- Construction of a bought farm: final tap, or Gems to skip the wait.
-- The same two remotes serve a farm's upgrade works (never at the same time
-- as its construction).
requestFinishFarm.OnServerEvent:Connect(function(player, farmId)
	if typeof(farmId) ~= "number" then return end
	if FarmService.FinishConstruction(player, farmId) or FarmService.FinishUpgrade(player, farmId) then
		HudService.PushUpdate(player) -- XP
	end
end)

requestSpeedUpFarm.OnServerEvent:Connect(function(player, farmId)
	if typeof(farmId) ~= "number" then return end
	if FarmService.SpeedUpConstruction(player, farmId) or FarmService.SpeedUpUpgrade(player, farmId) then
		HudService.PushUpdate(player) -- Gems spent
	end
end)

requestSellFarm.OnServerEvent:Connect(function(player, farmId)
	if typeof(farmId) ~= "number" then return end
	if FarmService.Sell(player, farmId) then
		HudService.PushUpdate(player)
	end
end)

-- A farm's next level (its next crop): pays and starts the works; refusals
-- come back as the farm's upgradeError.
requestUpgradeFarm.OnServerEvent:Connect(function(player, farmId)
	if typeof(farmId) ~= "number" then return end
	if FarmService.Upgrade(player, farmId) then
		HudService.PushUpdate(player) -- Coins spent, XP
	end
end)

requestBuyDragon.OnServerEvent:Connect(function(player, dragonDefId)
	if typeof(dragonDefId) ~= "string" then return end
	local ok, reason = ShopService.BuyDragonEgg(player, dragonDefId)
	if ok then
		HudService.PushUpdate(player) -- reflect the spend immediately, not just on the next tick
	end
	-- After the HUD push, so the Shop re-renders with the new balance.
	shopPurchaseResult:FireClient(player, ok, reason, "Dragon")
end)

requestInteractNursery.OnServerEvent:Connect(function(player, nurseryId)
	if typeof(nurseryId) ~= "number" then return end
	BreedingService.RequestInfo(player, nurseryId)
end)

requestStartBreeding.OnServerEvent:Connect(function(player, dragonIdA, dragonIdB, nurseryId)
	if typeof(dragonIdA) ~= "number" or typeof(dragonIdB) ~= "number" or typeof(nurseryId) ~= "number" then return end
	BreedingService.StartBreeding(player, nurseryId, dragonIdA, dragonIdB)
end)

requestCollectEgg.OnServerEvent:Connect(function(player, nurseryId)
	if typeof(nurseryId) ~= "number" then return end
	BreedingService.CollectEgg(player, nurseryId)
end)

-- Gems to finish a pairing at once (its egg is then ready to collect).
requestSpeedUpBreeding.OnServerEvent:Connect(function(player, nurseryId)
	if typeof(nurseryId) ~= "number" then return end
	if BreedingService.SpeedUpWithGems(player, nurseryId) then
		HudService.PushUpdate(player) -- Gems spent
	end
end)

-- The second Nursery, bought in the Shop (grid placement confirmed): Gems
-- are spent here.
requestPlaceNursery.OnServerEvent:Connect(function(player, gridX, gridZ)
	if typeof(gridX) ~= "number" or typeof(gridZ) ~= "number" then return end
	local ok, reason = BreedingService.BuyNursery(player, math.floor(gridX), math.floor(gridZ))
	if ok then
		HudService.PushUpdate(player)
	end
	shopPurchaseResult:FireClient(player, ok, reason, "Nursery")
end)

requestPlaceDecoration.OnServerEvent:Connect(function(player, defId, gridX, gridZ)
	if typeof(defId) ~= "string" or typeof(gridX) ~= "number" or typeof(gridZ) ~= "number" then return end
	local ok, reason = DecorationService.Place(player, defId, math.floor(gridX), math.floor(gridZ))
	if ok then
		HudService.PushUpdate(player)
	end
	shopPurchaseResult:FireClient(player, ok, reason, "Decoration")
end)

requestInteractDecoration.OnServerEvent:Connect(function(player, decorationId)
	if typeof(decorationId) ~= "number" then return end
	DecorationService.RequestInfo(player, decorationId)
end)

requestSellDecoration.OnServerEvent:Connect(function(player, decorationId)
	if typeof(decorationId) ~= "number" then return end
	if DecorationService.Sell(player, decorationId) then
		HudService.PushUpdate(player)
	end
end)

requestPlaceHabitat.OnServerEvent:Connect(function(player, element, gridX, gridZ)
	if typeof(element) ~= "string" or typeof(gridX) ~= "number" or typeof(gridZ) ~= "number" then return end
	gridX, gridZ = math.floor(gridX), math.floor(gridZ)
	local ok, reason = ShopService.PlaceHabitat(player, element, gridX, gridZ)
	if ok then
		HudService.PushUpdate(player)
	else
		-- e.g. "Locked" (level too low) or a spot taken meanwhile
		shopPurchaseResult:FireClient(player, false, reason, "Habitat")
	end
end)

-- kind: "Habitat" (id = habitatId) | "Decoration" (id = decorationId) |
-- "Farm" (id = farmId) | "Nursery" (id = nurseryId) | "Incubator" (one per
-- player, id unused).
requestMoveStructure.OnServerEvent:Connect(function(player, kind, id, gridX, gridZ)
	if typeof(kind) ~= "string" or typeof(gridX) ~= "number" or typeof(gridZ) ~= "number" then return end
	gridX, gridZ = math.floor(gridX), math.floor(gridZ)
	local ok = false
	if kind == "Habitat" then
		ok = typeof(id) == "number" and HabitatService.MoveHabitat(player, id, gridX, gridZ)
	elseif kind == "Decoration" then
		ok = typeof(id) == "number" and DecorationService.Move(player, id, gridX, gridZ)
	elseif kind == "Farm" then
		ok = typeof(id) == "number" and FarmService.MoveFarm(player, id, gridX, gridZ)
	elseif kind == "Nursery" then
		ok = typeof(id) == "number" and BreedingService.MoveNursery(player, id, gridX, gridZ)
	elseif kind == "Incubator" then
		ok = IncubatorService.MoveIncubator(player, gridX, gridZ)
	end
	if ok then
		HudService.PushUpdate(player) -- fresh OccupiedTiles for the placement grid
	end
end)

local function setupPlayer(player)
	local saveData = SaveService.Load(player)

	EconomyService.InitPlayer(player, saveData and saveData.Coins, saveData and saveData.Gems)
	LevelService.InitPlayer(player, saveData and saveData.Level)
	PveService.LoadPlayer(player, saveData and saveData.Pve)

	-- Island (and its placement grid) must exist, and the farms/Nursery must
	-- claim their tiles, BEFORE any Habitat is placed - otherwise a Habitat
	-- (grid fallback or player-chosen) could land on top of them.
	HabitatService.EnsureIsland(player)
	FarmService.LoadPlayer(player, saveData and saveData.Farm)
	BreedingService.LoadPlayer(player, saveData and saveData.Nursery)
	IncubatorService.CreateIncubator(player, saveData and saveData.IncubatorGrid)

	-- Multiple habitats are possible once the player buys more via the Shop;
	-- recreate every saved habitat at its saved grid position (CreateHabitat
	-- hands out sequential ids per island, matching what was saved) and keep
	-- a lookup so each saved dragon goes back into the right one.
	local habitatsById = {}
	if saveData and saveData.Habitats and #saveData.Habitats > 0 then
		for _, habitatSave in ipairs(saveData.Habitats) do
			local gridX, gridZ = habitatSave.gridX, habitatSave.gridZ
			if gridX == nil or gridZ == nil then
				-- Migration fallback: save written before the placement grid
				-- existed. Find any free 4x4 spot instead of erroring.
				gridX, gridZ = HabitatService.FindFreeGridSlot(player, 4, 4)
			end
			if gridX ~= nil then
				local habitatRecord = HabitatService.CreateHabitat(player, habitatSave.element, gridX, gridZ, habitatSave.purchasePrice or 0, habitatSave.buildReadyAt, habitatSave)
				habitatsById[habitatRecord.id] = habitatRecord
			end
		end
	else
		local habitatRecord = HabitatService.CreateHabitat(player, "Fire", 7, 7, 0)
		habitatsById[habitatRecord.id] = habitatRecord
	end

	DecorationService.LoadPlayer(player, saveData and saveData.Decorations)

	-- Scenery and obstacles last, once every building and decoration has
	-- claimed its tiles.
	IslandService.LoadPlayer(player, saveData and saveData.Island)

	-- habitatsById[1] is a defensive fallback for saves written before
	-- habitatId existed on a dragon record (single-habitat era). An
	-- Egg-stage entry is old-format data from before the Incubator existed
	-- (eggs used to live directly in a Habitat slot) - route it through the
	-- Incubator instead, with a fresh hatch timer, rather than erroring.
	if saveData and saveData.Dragons and #saveData.Dragons > 0 then
		for _, dragonSave in ipairs(saveData.Dragons) do
			if dragonSave.stage == "Egg" then
				IncubatorService.AddEgg(player, dragonSave.element)
			else
				local habitatRecord = habitatsById[dragonSave.habitatId] or habitatsById[1]
				if habitatRecord then
					DragonService.SpawnDragon(player, habitatRecord, dragonSave.slotIndex, dragonSave.element, {
						level = dragonSave.level,
						-- saves written before dragons had levels: stage + growth points
						stage = dragonSave.stage,
						growth = dragonSave.growth,
						pendingIncome = dragonSave.pendingIncome, -- older saves: goes into its habitat's storage
						nickname = dragonSave.nickname,
					})
				end
			end
		end
	end

	-- Time away still counts: Adults earn the Coins they would have made, and a
	-- running pairing keeps its absolute ready time (eggs and crops store theirs
	-- too, see below and FarmService). The pairing comes back first: its two
	-- parents were at the Nursery all along and earned nothing.
	local offlineSeconds = (saveData and saveData.SavedAt) and math.max(0, os.time() - saveData.SavedAt) or 0
	BreedingService.RestorePairing(player, saveData and saveData.Nursery)
	DragonService.AccrueOfflineIncome(player, offlineSeconds)

	-- Restores eggs still waiting in the Incubator (their hatchAt is an
	-- absolute timestamp, so remaining time survives a server restart). A
	-- brand new player (no save at all) gets the starter Fire egg here instead.
	if saveData and saveData.Incubator and #saveData.Incubator > 0 then
		for _, eggSave in ipairs(saveData.Incubator) do
			IncubatorService.RestoreEgg(player, eggSave.slotIndex, eggSave.element, eggSave.hatchAt, eggSave.hatched, eggSave.xpPaid)
		end
	elseif not saveData then
		IncubatorService.AddEgg(player, "Fire")
	end

	local islandCenter = HabitatService.GetIslandBasePosition(player)
	setCameraTarget:FireClient(player, islandCenter)
	HudService.PushUpdate(player)

	MonetizationService.LoadPlayer(player)
	task.spawn(function()
		-- UserOwnsGamePassAsync can yield/retry-fail, so this runs off the main
		-- setupPlayer path rather than delaying camera/dragon setup.
		MonetizationService.CheckStarterPack(player)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	SaveService.Save(player)
	-- Order matters: drop the in-memory dragon/farm records before
	-- HabitatService destroys the island model + all its Parts, then clear
	-- Economy last - otherwise a same-server rejoin would layer a second
	-- island/habitat/farm/dragon set on top of stale leftovers.
	DragonService.RemovePlayerDragons(player)
	FarmService.RemovePlayer(player)
	HabitatService.RemovePlayer(player)
	EconomyService.RemovePlayer(player)
	MonetizationService.RemovePlayer(player)
	BreedingService.RemovePlayer(player)
	DecorationService.RemovePlayer(player)
	IncubatorService.RemovePlayer(player)
	IslandService.RemovePlayer(player)
	LevelService.RemovePlayer(player)
	PveService.RemovePlayer(player)
	SaveService.RemovePlayer(player) -- after the Save above
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		SaveService.Save(player)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		player.Character:Destroy()
	end
	setupPlayer(player)
end
