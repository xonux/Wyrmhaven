-- Pushes Coins/Gems/Food to each client on a timer, rather than hooking every
-- EconomyService/FarmService mutation site individually (simpler, and avoids
-- touching those services while other work may be in flight on them).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local GameConstants = require(Config.GameConstants)

local HudService = {}

local EconomyService
local FarmService
local HabitatService
local updateHudRemote

function HudService.Init(remotesFolder, economyServiceRef, farmServiceRef, habitatServiceRef)
	EconomyService = economyServiceRef
	FarmService = farmServiceRef
	HabitatService = habitatServiceRef

	updateHudRemote = remotesFolder:FindFirstChild("UpdateHud")
	if not updateHudRemote then
		updateHudRemote = Instance.new("RemoteEvent")
		updateHudRemote.Name = "UpdateHud"
		updateHudRemote.Parent = remotesFolder
	end
end

function HudService.PushUpdate(player)
	local balance = EconomyService.GetBalance(player)

	-- Lets client UI (ShopController's Habitats tab) compute the real
	-- CostGrowth-scaled price without a dedicated query remote.
	local habitatCounts = {}
	for _, habitat in ipairs(HabitatService.GetPlayerHabitats(player)) do
		habitatCounts[habitat.element] = (habitatCounts[habitat.element] or 0) + 1
	end

	updateHudRemote:FireClient(player, {
		Coins = balance.Coins,
		Gems = balance.Gems,
		Food = FarmService.GetFoodStock(player),
		HabitatCounts = habitatCounts,
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
