-- Shop purchase flows (docs/design/phase2-shop.md): dragon eggs and habitats -
-- check here before creating a second ShopService. Decorations are bought
-- through DecorationService.Place. An element is only sold from its
-- HabitatDefs.UnlockLevel on (player level, LevelService), eggs and habitats
-- alike.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local DragonDefs = require(Config.DragonDefs)
local DragonRules = require(Config.DragonRules)
local HabitatDefs = require(Config.HabitatDefs)
local LevelService = require(script.Parent.LevelService)

local ShopService = {}

local HabitatService
local DragonService
local EconomyService
local IncubatorService

function ShopService.Init(habitatServiceRef, dragonServiceRef, economyServiceRef)
	HabitatService = habitatServiceRef
	DragonService = dragonServiceRef
	EconomyService = economyServiceRef
end

function ShopService.SetIncubatorService(incubatorServiceRef)
	IncubatorService = incubatorServiceRef
end

-- Whether the player's level lets them buy `element`'s eggs and habitats.
function ShopService.IsElementUnlocked(player, element)
	local def = HabitatDefs[element]
	local level = LevelService.GetProgress(player)
	return def ~= nil and level >= (def.UnlockLevel or 1)
end

-- Buys an egg of a DragonDefs entry: Coins (EggPrice) for Common dragons,
-- Gems (GemPrice) for Rare ones, once the player's level unlocks all its
-- elements (DragonRules.UnlockLevel). Every bought dragon starts as an egg in
-- the Incubator, like bred ones, and is placed in a habitat once hatched.
-- Checks the Incubator has room BEFORE spending, so a failed purchase never
-- charges.
function ShopService.BuyDragonEgg(player, dragonDefId)
	local def = DragonDefs[dragonDefId]
	if not def then return false, "UnknownDragon" end

	local usesGems = def.GemPrice ~= nil
	local price = usesGems and def.GemPrice or def.EggPrice
	if not price then return false, "NotForSale" end
	if LevelService.GetProgress(player) < DragonRules.UnlockLevel(dragonDefId) then return false, "Locked" end
	if not IncubatorService.HasFreeSlot(player) then return false, "IncubatorFull" end

	if usesGems then
		if not EconomyService.TrySpendGems(player, price) then
			return false, "InsufficientGems"
		end
	elseif not EconomyService.TrySpendCoins(player, price) then
		return false, "InsufficientCoins"
	end

	IncubatorService.AddEgg(player, dragonDefId)
	return true
end

-- A habitat of `element` always costs its ShopBaseCost, however many the
-- player owns (the Shop card and the placement show the same number).
function ShopService.GetHabitatPrice(player, element)
	local def = HabitatDefs[element]
	return def and def.ShopBaseCost or nil
end

-- Places a habitat of `element` at grid tile (gridX, gridZ) (4x4 footprint,
-- see HabitatService). Validates the area is free BEFORE spending Coins, so
-- a rejected placement (occupied tiles, out of bounds, race with another
-- purchase) never charges. Coins are only ever spent here, at confirmed
-- placement - the Shop's "Buy" button just starts client-side placement
-- mode, no server call, so a cancelled placement costs nothing.
function ShopService.PlaceHabitat(player, element, gridX, gridZ)
	local def = HabitatDefs[element]
	if not def then return false, "UnknownElement" end
	if not ShopService.IsElementUnlocked(player, element) then return false, "Locked" end

	if not HabitatService.IsAreaFree(player, gridX, gridZ, 4, 4) then
		return false, "TilesOccupied"
	end

	local price = ShopService.GetHabitatPrice(player, element)
	if not EconomyService.TrySpendCoins(player, price) then
		return false, "InsufficientCoins"
	end

	-- Built over BuildDuration; its XP comes when the construction ends.
	HabitatService.CreateHabitat(player, element, gridX, gridZ, price, os.time() + (def.BuildDuration or 0))
	return true
end

return ShopService
