-- Shop purchase flows (docs/design/phase2-shop.md). Currently just exclusive
-- dragons (Gems); habitat/decoration purchases land here too if/when
-- shop-habitats.md / shop-decorations.md extend this module - check before
-- creating a second ShopService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local DragonDefs = require(Config.DragonDefs)
local DecorationDefs = require(Config.DecorationDefs)
local HabitatDefs = require(Config.HabitatDefs)

local ShopService = {}

local HabitatService
local DragonService
local EconomyService
local DecorationService

function ShopService.Init(habitatServiceRef, dragonServiceRef, economyServiceRef)
	HabitatService = habitatServiceRef
	DragonService = dragonServiceRef
	EconomyService = economyServiceRef
end

function ShopService.SetDecorationService(decorationServiceRef)
	DecorationService = decorationServiceRef
end

-- Buys an Exclusive DragonDefs entry for Gems and spawns it straight to
-- Adult in a free slot of a habitat matching its HabitatElement. Checks slot
-- availability BEFORE spending Gems so a failed purchase never charges.
function ShopService.BuyExclusiveDragon(player, dragonDefId)
	local def = DragonDefs[dragonDefId]
	if not def or not def.Exclusive then return false, "UnknownDragon" end

	local habitatRecord, slotIndex = HabitatService.FindFreeSlotForElement(player, def.HabitatElement)
	if not habitatRecord then return false, "NoFreeSlot" end

	if not EconomyService.TrySpendGems(player, def.GemPrice) then
		return false, "InsufficientGems"
	end

	DragonService.SpawnDragon(player, habitatRecord, slotIndex, dragonDefId, {
		stage = "Adult",
		growth = 0,
		pendingIncome = 0,
	})

	return true
end

-- Buys an additional habitat of `element` for Coins. Price grows with how
-- many of that element the player already owns:
-- ShopBaseCost * CostGrowth ^ (owned count). The free starter Fire habitat
-- (created directly by Server.script, not through here) still counts toward
-- "owned" so the 2nd Fire habitat is priced correctly.
function ShopService.BuyHabitat(player, element)
	local def = HabitatDefs[element]
	if not def then return false, "UnknownElement" end

	local ownedCount = 0
	for _, habitat in ipairs(HabitatService.GetPlayerHabitats(player)) do
		if habitat.element == element then
			ownedCount += 1
		end
	end

	local price = math.floor((def.ShopBaseCost or 0) * (def.CostGrowth ^ ownedCount))
	if not EconomyService.TrySpendCoins(player, price) then
		return false, "InsufficientCoins"
	end

	HabitatService.CreateHabitat(player, element)
	return true
end

-- Buys a decoration for Coins and places it near the structure its resource
-- targets (see DecorationService for placement/bonus logic).
function ShopService.BuyDecoration(player, decorationId)
	local def = DecorationDefs[decorationId]
	if not def then return false, "UnknownDecoration" end

	if not EconomyService.TrySpendCoins(player, def.Price) then
		return false, "InsufficientCoins"
	end

	DecorationService.CreateDecoration(player, decorationId)
	return true
end

return ShopService
