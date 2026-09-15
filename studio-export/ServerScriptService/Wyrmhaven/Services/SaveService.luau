local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local SaveService = {}

local HabitatService
local DragonService
local EconomyService
local FarmService
local DecorationService

local store = DataStoreService:GetDataStore("Wyrmhaven_PlayerData_v1")

local AUTOSAVE_INTERVAL_SECONDS = 180

function SaveService.Init(habitatServiceRef, dragonServiceRef, economyServiceRef, farmServiceRef)
	HabitatService = habitatServiceRef
	DragonService = dragonServiceRef
	EconomyService = economyServiceRef
	FarmService = farmServiceRef
end

function SaveService.SetDecorationService(decorationServiceRef)
	DecorationService = decorationServiceRef
end

local function buildSaveData(player)
	local balance = EconomyService.GetBalance(player)
	return {
		Coins = balance.Coins,
		Gems = balance.Gems,
		Habitats = HabitatService.GetPlayerHabitats(player), -- array of {id, element}, in creation order
		Dragons = DragonService.GetPlayerDragons(player), -- array of {habitatId, slotIndex, element, stage, growth, pendingIncome}
		Farm = FarmService.GetSaveState(player), -- {foodStock, pendingFood}
		Decorations = DecorationService and DecorationService.GetSaveState(player) or nil, -- array of {defId, position}
	}
end

function SaveService.Save(player)
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
	return result
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
