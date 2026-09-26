local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local SaveService = {}

local HabitatService
local DragonService
local EconomyService
local FarmService
local IncubatorService
local DecorationService
local BreedingService
local IslandService

local LevelService = require(script.Parent.LevelService)
local PveService = require(script.Parent.PveService)

local store = DataStoreService:GetDataStore("Wyrmhaven_PlayerData_v1")

local AUTOSAVE_INTERVAL_SECONDS = 180

-- Players whose save was wiped this session (ResetPlayer): nothing is saved
-- for them any more - their leave / the autosave would write the old state
-- back - until they're gone (RemovePlayer).
local wiped = {} -- [userId] = true

-- Elements / species renamed or removed since older saves were written: old
-- name -> current DragonDefs/HabitatDefs key. Unknown names would make
-- CreateHabitat/SpawnEgg error while loading the player.
local RENAMED_ELEMENTS = {
	Lightning = "Electric",
	-- The Shop-exclusive "Ember Sovereign" was removed (2026-09-19): owned ones
	-- (and their eggs) become Fire dragons, which live in the same habitats.
	FireExclusive = "Fire",
}

local function migrateElementNames(data)
	for _, list in ipairs({ data.Habitats, data.Dragons, data.Incubator }) do
		for _, entry in ipairs(list or {}) do
			entry.element = RENAMED_ELEMENTS[entry.element] or entry.element
		end
	end
end

-- Island grid the saved building spots refer to. Saves without GridVersion
-- were written for the old 15x15 island, which is now the middle of the
-- 30x30 one (tiles 7 to 21, kept free of obstacles for them).
local GRID_VERSION = 2
local OLD_GRID_OFFSET = 7

local function migrateGrid(data)
	if (data.GridVersion or 1) >= GRID_VERSION then
		return
	end
	local function shift(entry)
		if entry and entry.gridX ~= nil and entry.gridZ ~= nil then
			entry.gridX += OLD_GRID_OFFSET
			entry.gridZ += OLD_GRID_OFFSET
		end
	end
	for _, habitat in ipairs(data.Habitats or {}) do
		shift(habitat)
	end
	shift(data.Farm)
	shift(data.Nursery)
	shift(data.IncubatorGrid)
	data.GridVersion = GRID_VERSION
end

function SaveService.Init(habitatServiceRef, dragonServiceRef, economyServiceRef, farmServiceRef, incubatorServiceRef)
	HabitatService = habitatServiceRef
	DragonService = dragonServiceRef
	EconomyService = economyServiceRef
	FarmService = farmServiceRef
	IncubatorService = incubatorServiceRef
end

function SaveService.SetDecorationService(decorationServiceRef)
	DecorationService = decorationServiceRef
end

function SaveService.SetBreedingService(breedingServiceRef)
	BreedingService = breedingServiceRef
end

function SaveService.SetIslandService(islandServiceRef)
	IslandService = islandServiceRef
end

local function buildSaveData(player)
	local balance = EconomyService.GetBalance(player)
	return {
		SavedAt = os.time(), -- lets the next load credit the time spent offline (see Server setupPlayer)
		GridVersion = GRID_VERSION,
		Coins = balance.Coins,
		Gems = balance.Gems,
		Level = LevelService.GetSaveState(player), -- {level, xp}
		Habitats = HabitatService.GetPlayerHabitats(player), -- array of {id, element, gridX, gridZ, purchasePrice, buildReadyAt?, level, storedCoins, upgradeReadyAt?}, in creation order
		Dragons = DragonService.GetPlayerDragons(player), -- array of {habitatId, slotIndex, element, stage, level, nickname?} - Habitat-placed dragons only (older saves have growth points instead of a level, and pendingIncome moved into the habitat at load)
		Incubator = IncubatorService.GetSaveState(player), -- array of {slotIndex, element, hatchAt, hatched, xpPaid} - eggs not yet placed in a Habitat
		IncubatorGrid = IncubatorService.GetGridState(player), -- {gridX, gridZ, nests} (older saves: no nests, see IncubatorService.RestoreEgg)
		Nursery = BreedingService and BreedingService.GetSaveState(player) or nil, -- {nurseries = array of {gridX, gridZ, pairing?}} (older saves: one Nursery's fields at the top level)
		Farm = FarmService.GetSaveState(player), -- {foodStock, foodRateMultiplier, farms = array of {gridX, gridZ, purchasePrice, buildReadyAt?, cropId?, cropFood?, readyAt?}} - older saves: a single farm's fields at the top level, see FarmService.LoadPlayer
		Decorations = DecorationService and DecorationService.GetSaveState(player) or nil, -- array of {defId, gridX, gridZ}
		Island = IslandService and IslandService.GetSaveState(player) or nil, -- {cleared = {obstacle ids}, clearing? = {id, readyAt}}
		Pve = PveService.GetSaveState(player), -- {cleared = highest exploration stage cleared}
	}
end

function SaveService.Save(player)
	if wiped[player.UserId] then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync("Player_" .. player.UserId, buildSaveData(player))
	end)
	if not ok then
		warn(string.format("[Wyrmhaven] Failed to save data for %s: %s", player.Name, tostring(err)))
	end
end

-- Returns nil on a fresh player (no save yet) OR if the DataStore call itself
-- fails (e.g. Studio API access disabled) - callers treat both the same way:
-- fall back to a brand new island.
function SaveService.Load(player)
	local ok, result = pcall(function()
		return store:GetAsync("Player_" .. player.UserId)
	end)
	if not ok then
		warn(string.format("[Wyrmhaven] Failed to load data for %s: %s", player.Name, tostring(result)))
		return nil
	end
	if result then
		migrateElementNames(result)
		migrateGrid(result)
	end
	return result
end

-- Deletes the player's save (testing: see DevCommands' /resetdata) and stops saving
-- them for the rest of the session, so their next join starts from scratch.
-- Returns whether the DataStore accepted the deletion.
function SaveService.ResetPlayer(player)
	wiped[player.UserId] = true
	local ok, err = pcall(function()
		store:RemoveAsync("Player_" .. player.UserId)
	end)
	if not ok then
		warn(string.format("[Wyrmhaven] Failed to reset data for %s: %s", player.Name, tostring(err)))
	end
	return ok
end

-- Called once the player has left (after their final Save).
function SaveService.RemovePlayer(player)
	wiped[player.UserId] = nil
end

function SaveService.StartAutosaveLoop()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				SaveService.Save(player)
			end
		end
	end)
end

return SaveService
