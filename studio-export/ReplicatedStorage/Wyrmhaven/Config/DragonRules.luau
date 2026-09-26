-- Rules about dragon species (DragonDefs ids), shared by the server and the
-- client: rarity, income, sell price and hatching / breeding times, the
-- habitats a species can live in, the level that unlocks it in the Shop,
-- breeding results, and the combat class and stats.
--
-- Breeding (user's rules, 2026-09-19):
-- * two Common dragons of different elements -> their Rare hybrid, 100%
--   (Fire + Water -> Fire-Water);
-- * the same species twice -> that species, 100%;
-- * any other pair -> either parent's species, 50% each
--   (Fire-Water + Fire -> 50% Fire-Water, 50% Fire).
-- The result is rolled when the pairing starts (BreedingService); the
-- Nursery screen shows the same outcomes with their chances.
local Config = script.Parent
local DragonClasses = require(Config.DragonClasses)
local DragonDefs = require(Config.DragonDefs)
local HabitatDefs = require(Config.HabitatDefs)
local GameConstants = require(Config.GameConstants)

local DragonRules = {}

DragonRules.RarityNames = { Common = "Common", Rare = "Rare", Epic = "Epic", Legendary = "Legendary" }

-- ["elementA|elementB"] (both orders) = hybrid species id.
local hybridByPair = {}
for id, def in pairs(DragonDefs) do
	if def.Elements and #def.Elements == 2 then
		hybridByPair[def.Elements[1] .. "|" .. def.Elements[2]] = id
		hybridByPair[def.Elements[2] .. "|" .. def.Elements[1]] = id
	end
end

function DragonRules.Rarity(speciesId)
	local def = DragonDefs[speciesId]
	return def and def.Rarity or "Common"
end

function DragonRules.RarityName(speciesId)
	local rarity = DragonRules.Rarity(speciesId)
	return DragonRules.RarityNames[rarity] or rarity
end

-- The habitat elements (HabitatDefs keys) it can live in.
function DragonRules.Elements(speciesId)
	local def = DragonDefs[speciesId]
	if def and def.Elements then
		return def.Elements
	end
	return { speciesId }
end

function DragonRules.CanLiveIn(speciesId, habitatElement)
	return table.find(DragonRules.Elements(speciesId), habitatElement) ~= nil
end

-- Coins this species makes, by its rarity. `stage` (optional) scales it: a
-- Baby earns GameConstants.BabyIncomeMultiplier of an Adult's rate; without
-- it you get the full Adult rate (what the Shop's cards advertise).
function DragonRules.IncomePerMinute(speciesId, stage)
	local byRarity = GameConstants.IncomePerMinuteByRarity
	local rate = byRarity[DragonRules.Rarity(speciesId)] or byRarity.Common
	if stage == "Baby" then
		rate *= GameConstants.BabyIncomeMultiplier
	end
	return rate
end

function DragonRules.IncomePerSecond(speciesId, stage)
	return DragonRules.IncomePerMinute(speciesId, stage) / 60
end

-- Coins it sells for, or nil when its rarity can't be sold.
function DragonRules.SellPrice(speciesId)
	return GameConstants.SellPriceByRarity[DragonRules.Rarity(speciesId)]
end

-- Seconds its egg takes to hatch in the Incubator.
function DragonRules.HatchSeconds(speciesId)
	local byRarity = GameConstants.HatchSecondsByRarity
	return byRarity[DragonRules.Rarity(speciesId)] or byRarity.Common
end

-- Seconds a Nursery pairing takes when it gives this species' egg.
function DragonRules.BreedingSeconds(speciesId)
	local byRarity = GameConstants.BreedingSecondsByRarity
	return byRarity[DragonRules.Rarity(speciesId)] or byRarity.Common
end

-- Player level from which the Shop sells it: all its elements unlocked.
function DragonRules.UnlockLevel(speciesId)
	local level = 1
	for _, element in ipairs(DragonRules.Elements(speciesId)) do
		local def = HabitatDefs[element]
		level = math.max(level, def and def.UnlockLevel or 1)
	end
	return level
end

-- Its role in a fight (Config/DragonClasses).
function DragonRules.Class(speciesId)
	local def = DragonDefs[speciesId]
	return def and def.Class or "Attacker"
end

function DragonRules.ClassDef(speciesId)
	return DragonClasses.Get(DragonRules.Class(speciesId))
end

function DragonRules.ClassName(speciesId)
	return DragonRules.ClassDef(speciesId).DisplayName
end

-- How many rarity steps above Common it is (Common 0, Rare 1...).
local RARITY_STEPS = { Common = 0, Rare = 1, Epic = 2, Legendary = 3 }

-- Its combat stats at `level` (default 1): { Attack, Health, Speed }, rounded.
-- base x class weight x rarity step x level growth, so two dragons of the
-- same class and rarity are near enough - what sets them apart is their
-- three skills.
function DragonRules.Stats(speciesId, level)
	local weights = DragonRules.ClassDef(speciesId).Weights
	local rarity = GameConstants.StatRarityStep ^ (RARITY_STEPS[DragonRules.Rarity(speciesId)] or 0)
	local growth = 1 + GameConstants.StatGrowthPerLevel * (math.max(1, level or 1) - 1)
	local stats = {}
	for stat, base in pairs(GameConstants.DragonBaseStats) do
		stats[stat] = math.round(base * (weights[stat] or 1) * rarity * growth)
	end
	return stats
end

-- A Common species of a single element (hybrids come from two of these).
local function isBaseCommon(speciesId)
	local def = DragonDefs[speciesId]
	return def ~= nil and DragonRules.Rarity(speciesId) == "Common" and #DragonRules.Elements(speciesId) == 1
end

-- Possible eggs of a pair, as { { id, chance (0..1) }, ... }, likeliest
-- first, then in Shop order.
function DragonRules.BreedingOutcomes(speciesA, speciesB)
	if speciesA == speciesB then
		return { { id = speciesA, chance = 1 } }
	end
	if isBaseCommon(speciesA) and isBaseCommon(speciesB) then
		local hybrid = hybridByPair[DragonRules.Elements(speciesA)[1] .. "|" .. DragonRules.Elements(speciesB)[1]]
		if hybrid then
			return { { id = hybrid, chance = 1 } }
		end
	end
	local outcomes = { { id = speciesA, chance = 0.5 }, { id = speciesB, chance = 0.5 } }
	table.sort(outcomes, function(a, b)
		if a.chance ~= b.chance then
			return a.chance > b.chance
		end
		local orderA = DragonDefs[a.id] and DragonDefs[a.id].SortOrder or math.huge
		local orderB = DragonDefs[b.id] and DragonDefs[b.id].SortOrder or math.huge
		return orderA < orderB
	end)
	return outcomes
end

-- One of the pair's possible eggs, drawn by their chances.
function DragonRules.RollBreeding(speciesA, speciesB)
	local outcomes = DragonRules.BreedingOutcomes(speciesA, speciesB)
	local roll = math.random()
	for _, outcome in ipairs(outcomes) do
		roll -= outcome.chance
		if roll < 0 then
			return outcome.id
		end
	end
	return outcomes[#outcomes].id
end

return DragonRules
