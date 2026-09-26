-- A dragon's own level, shared by the server (DragonService) and the client
-- (DragonScreen). Every dragon hatches at level 1 and is fed Food to level up,
-- one level per feeding, up to MaxLevel. Each level costs more Food than the
-- last (FoodToNextLevel).
--
-- Becoming an Adult is no longer the end of the road, just the level from
-- which the dragon is really usable: it earns its species' full Coin rate,
-- can breed, and will be the one that fights. Below AdultLevel it is a Baby,
-- which still earns Coins but at GameConstants.BabyIncomeMultiplier of that
-- rate.
local GameConstants = require(script.Parent.GameConstants)

local DragonLevels = {}

DragonLevels.MaxLevel = GameConstants.DragonMaxLevel
DragonLevels.AdultLevel = GameConstants.DragonAdultLevel

-- Food to go from `level` to the next one, or nil at MaxLevel.
function DragonLevels.FoodToNextLevel(level)
	if level >= DragonLevels.MaxLevel then
		return nil
	end
	return GameConstants.DragonFeedFoodBase + GameConstants.DragonFeedFoodStep * (math.max(1, level) - 1)
end

-- Food a level-1 dragon needs in total to reach `level`.
function DragonLevels.TotalFoodTo(level)
	local total = 0
	for step = 1, math.min(level, DragonLevels.MaxLevel) - 1 do
		total += DragonLevels.FoodToNextLevel(step) or 0
	end
	return total
end

-- "Baby" or "Adult" (an egg has no level yet - it hatches into a level 1 Baby).
function DragonLevels.StageForLevel(level)
	return level >= DragonLevels.AdultLevel and "Adult" or "Baby"
end

function DragonLevels.Clamp(level)
	return math.clamp(math.floor(tonumber(level) or 1), 1, DragonLevels.MaxLevel)
end

return DragonLevels
