-- Habitat levels 1 to 5 (HabitatService, the Habitat bar's upgrade window,
-- the Shop cards). Each element starts at its own price and gold storage
-- (HabitatDefs ShopBaseCost / StorageBase), and every element meets at level
-- 5: the last upgrade costs FinalUpgradeCost and stores FinalStorage for all.
-- Levels 2 to 4 grow exponentially from the element's level 1 toward those
-- values, so cheap elements stay cheaper (and smaller) on the way up - they
-- are the early-game habitats. Values are rounded to two significant digits.
local HabitatDefs = require(script.Parent.HabitatDefs)

local HabitatLevels = {
	MaxLevel = 5,
	FinalUpgradeCost = 250000,
	FinalStorage = 50000,
	-- Dragons a habitat holds at level 1..5.
	DragonsByLevel = { 2, 2, 3, 3, 4 },
	-- Works of the upgrade to level 2, 3, 4, 5, in seconds (then the final tap).
	UpgradeDurations = { 300, 1800, 7200, 28800 },
}

local function roundTwoDigits(value)
	if value <= 0 then
		return 0
	end
	local unit = 10 ^ (math.floor(math.log10(value)) - 1)
	return math.floor(value / unit + 0.5) * unit
end

-- Exponential step from `base` (level 1) to `final` (MaxLevel).
local function curve(base, final, level)
	local t = (level - 1) / (HabitatLevels.MaxLevel - 1)
	return roundTwoDigits(base * (final / base) ^ t)
end

-- Coins for the upgrade from level - 1 to `level` (2..MaxLevel).
function HabitatLevels.UpgradeCost(element, level)
	if level >= HabitatLevels.MaxLevel then
		return HabitatLevels.FinalUpgradeCost
	end
	return curve(HabitatDefs[element].ShopBaseCost, HabitatLevels.FinalUpgradeCost, level)
end

-- Coins the habitat can store at `level`.
function HabitatLevels.Storage(element, level)
	local base = HabitatDefs[element].StorageBase
	if level <= 1 then
		return base
	end
	if level >= HabitatLevels.MaxLevel then
		return HabitatLevels.FinalStorage
	end
	return curve(base, HabitatLevels.FinalStorage, level)
end

-- Dragons the habitat holds at `level`.
function HabitatLevels.Dragons(level)
	local list = HabitatLevels.DragonsByLevel
	return list[math.clamp(level, 1, #list)]
end

-- Seconds of works of the upgrade to `level` (2..MaxLevel).
function HabitatLevels.UpgradeDuration(level)
	return HabitatLevels.UpgradeDurations[level - 1] or 0
end

-- Lowest level whose habitat has a slot number `slotIndex`.
function HabitatLevels.LevelForSlot(slotIndex)
	for level, dragons in ipairs(HabitatLevels.DragonsByLevel) do
		if dragons >= slotIndex then
			return level
		end
	end
	return HabitatLevels.MaxLevel
end

return HabitatLevels
