-- Pushes Coins/Gems/Food to each client on a timer, rather than hooking every
-- EconomyService/FarmService mutation site individually (simpler, and avoids
-- touching those services while other work may be in flight on them).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local GameConstants = require(Config.GameConstants)
local LevelService = require(script.Parent.LevelService)

local HudService = {}

local EconomyService
local FarmService
local HabitatService
local BreedingService
local updateHudRemote

function HudService.Init(remotesFolder, economyServiceRef, farmServiceRef, habitatServiceRef, breedingServiceRef)
	EconomyService = economyServiceRef
	FarmService = farmServiceRef
	HabitatService = habitatServiceRef
	BreedingService = breedingServiceRef

	updateHudRemote = remotesFolder:FindFirstChild("UpdateHud")
	if not updateHudRemote then
		updateHudRemote = Instance.new("RemoteEvent")
		updateHudRemote.Name = "UpdateHud"
		updateHudRemote.Parent = remotesFolder
	end
end

function HudService.PushUpdate(player)
	local balance = EconomyService.GetBalance(player)

	-- Habitats owned per element, for the Shop cards' footer.
	local habitatCounts = {}
	for _, habitat in ipairs(HabitatService.GetPlayerHabitats(player)) do
		habitatCounts[habitat.element] = (habitatCounts[habitat.element] or 0) + 1
	end

	local level, xp, xpRequired = LevelService.GetProgress(player)
	updateHudRemote:FireClient(player, {
		Level = level,
		Xp = xp,
		XpRequired = xpRequired,
		Coins = balance.Coins,
		Gems = balance.Gems,
		Food = FarmService.GetFoodStock(player),
		HabitatCounts = habitatCounts,
		FarmCount = FarmService.GetFarmCount(player), -- the Shop's farm price (FarmDefs.GetPrice)
		NurseryCount = BreedingService.GetNurseryCount(player), -- the Shop's Nursery card (GameConstants.NurseryMax)
		-- Lets the client-side placement ghost (PlacementController) render a
		-- red/green preview without a round trip per mouse move; up to 1s stale,
		-- fine since ShopService.PlaceHabitat re-validates authoritatively anyway.
		OccupiedTiles = HabitatService.GetOccupiedTiles(player),
	})
end

function HudService.StartPushLoop(getPlayers)
	task.spawn(function()
		while true do
			task.wait(GameConstants.HudPushIntervalSeconds)
			for _, player in ipairs(getPlayers()) do
				HudService.PushUpdate(player)
			end
		end
	end)
end

return HudService
