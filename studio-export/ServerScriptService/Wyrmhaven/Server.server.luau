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

FarmService.Init(HabitatService)
FarmService.StartAccrualLoop()

DragonService.Init(HabitatService, EconomyService, FarmService)
DragonService.StartIncomeLoop()

SaveService.Init(HabitatService, DragonService, EconomyService, FarmService)
SaveService.StartAutosaveLoop()

MonetizationService.Init(EconomyService, FarmService)

ShopService.Init(HabitatService, DragonService, EconomyService)

DecorationService.Init(HabitatService)
DragonService.SetDecorationService(DecorationService)
FarmService.SetDecorationService(DecorationService)
ShopService.SetDecorationService(DecorationService)
SaveService.SetDecorationService(DecorationService)

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

local requestInteractDragon = getOrCreateRemoteEvent("RequestInteractDragon")
local requestInteractFarm = getOrCreateRemoteEvent("RequestInteractFarm")
local setCameraTarget = getOrCreateRemoteEvent("SetCameraTarget")
local requestBuyDragon = getOrCreateRemoteEvent("RequestBuyDragon")
local requestInteractNursery = getOrCreateRemoteEvent("RequestInteractNursery")
local requestStartBreeding = getOrCreateRemoteEvent("RequestStartBreeding")
local requestCollectEgg = getOrCreateRemoteEvent("RequestCollectEgg")
local requestBuyDecoration = getOrCreateRemoteEvent("RequestBuyDecoration")
local requestBuyHabitat = getOrCreateRemoteEvent("RequestBuyHabitat")

BreedingService.Init(HabitatService, DragonService, remotes)
BreedingService.StartStatusLoop(function()
	return Players:GetPlayers()
end)

HudService.Init(remotes, EconomyService, FarmService, HabitatService)
HudService.StartPushLoop(function()
	return Players:GetPlayers()
end)

requestInteractDragon.OnServerEvent:Connect(function(player, dragonId)
	if typeof(dragonId) ~= "number" then return end
	DragonService.Interact(player, dragonId)
end)

requestInteractFarm.OnServerEvent:Connect(function(player, farmId)
	if typeof(farmId) ~= "number" then return end
	FarmService.Harvest(player, farmId)
end)

requestBuyDragon.OnServerEvent:Connect(function(player, dragonDefId)
	if typeof(dragonDefId) ~= "string" then return end
	local ok = ShopService.BuyExclusiveDragon(player, dragonDefId)
	if ok then
		HudService.PushUpdate(player) -- reflect the Gem spend immediately, not just on the next tick
	end
end)

requestInteractNursery.OnServerEvent:Connect(function(player, nurseryId)
	if typeof(nurseryId) ~= "number" then return end
	BreedingService.RequestInfo(player, nurseryId)
end)

requestStartBreeding.OnServerEvent:Connect(function(player, dragonIdA, dragonIdB)
	if typeof(dragonIdA) ~= "number" or typeof(dragonIdB) ~= "number" then return end
	BreedingService.StartBreeding(player, dragonIdA, dragonIdB)
end)

requestCollectEgg.OnServerEvent:Connect(function(player)
	BreedingService.CollectEgg(player)
end)

requestBuyDecoration.OnServerEvent:Connect(function(player, decorationId)
	if typeof(decorationId) ~= "string" then return end
	local ok = ShopService.BuyDecoration(player, decorationId)
	if ok then
		HudService.PushUpdate(player)
	end
end)

requestBuyHabitat.OnServerEvent:Connect(function(player, element)
	if typeof(element) ~= "string" then return end
	local ok = ShopService.BuyHabitat(player, element)
	if ok then
		HudService.PushUpdate(player)
	end
end)

local function setupPlayer(player)
	local saveData = SaveService.Load(player)

	EconomyService.InitPlayer(player, saveData and saveData.Coins, saveData and saveData.Gems)

	-- Multiple habitats are possible once the player buys more via the Shop
	-- (shop-habitats.md); recreate every saved habitat in order (CreateHabitat
	-- hands out sequential ids per island, matching what was saved) and keep a
	-- lookup so each saved dragon goes back into the right one.
	local habitatsById = {}
	if saveData and saveData.Habitats and #saveData.Habitats > 0 then
		for _, habitatSave in ipairs(saveData.Habitats) do
			local habitatRecord = HabitatService.CreateHabitat(player, habitatSave.element)
			habitatsById[habitatRecord.id] = habitatRecord
		end
	else
		local habitatRecord = HabitatService.CreateHabitat(player, "Fire")
		habitatsById[habitatRecord.id] = habitatRecord
	end

	FarmService.CreateFarm(player, saveData and saveData.Farm)
	BreedingService.CreateNursery(player)
	DecorationService.LoadPlayer(player, saveData and saveData.Decorations)

	if saveData and saveData.Dragons and #saveData.Dragons > 0 then
		for _, dragonSave in ipairs(saveData.Dragons) do
			-- habitatsById[1] is a defensive fallback for saves written before
			-- habitatId existed on a dragon record (single-habitat era).
			local habitatRecord = habitatsById[dragonSave.habitatId] or habitatsById[1]
			if habitatRecord then
				DragonService.SpawnDragon(player, habitatRecord, dragonSave.slotIndex, dragonSave.element, {
					stage = dragonSave.stage,
					growth = dragonSave.growth,
					pendingIncome = dragonSave.pendingIncome,
				})
			end
		end
	else
		local firstHabitat = habitatsById[1]
		local slotIndex = HabitatService.FindFreeSlot(firstHabitat)
		DragonService.SpawnDragon(player, firstHabitat, slotIndex, "Fire")
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
	-- Order matters: drop the in-memory Dragon/Farm records before
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
