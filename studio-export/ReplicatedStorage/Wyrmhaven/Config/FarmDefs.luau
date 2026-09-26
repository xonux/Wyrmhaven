-- The Farm building (FarmService): every player starts with one, and more are
-- bought in the Shop's Buildings tab and placed on the grid like a habitat.
-- A bought farm is built over BuildDuration seconds, then finished with a tap
-- (XP of its price). An empty farm sells for SellRefundPercent of its price,
-- as long as the player keeps at least one. Placeholder values.
--
-- Levels: a farm at level N grows the first N crops of FarmCrops (a new farm
-- only the cheapest one). The upgrade to level N unlocks crop N and costs
-- UpgradeCostFactor times its price; its works last as long as that crop
-- takes to grow, then need a final tap (the farm keeps farming meanwhile).
local FarmCrops = require(script.Parent.FarmCrops)

local FarmDefs = {
	DisplayName = "Farm",
	ShopBaseCost = 250, -- price of the 2nd farm
	CostGrowth = 1.6, -- multiplier per farm already owned beyond the first
	BuildDuration = 60,
	SellRefundPercent = 0.5,
	UpgradeCostFactor = 3,
	MaxLevel = #FarmCrops,
}

-- Coins for the upgrade to `level` (2..MaxLevel): 180, 450, 1200, 3000.
function FarmDefs.UpgradeCost(level)
	local crop = FarmCrops[level]
	return crop and crop.Price * FarmDefs.UpgradeCostFactor or nil
end

-- Seconds of works of the upgrade to `level`: its crop's growing time.
function FarmDefs.UpgradeDuration(level)
	local crop = FarmCrops[level]
	return crop and crop.Duration or 0
end

-- The Food a crop really gives this player: its own Food times their Food
-- bonus (FarmService's foodRateMultiplier, raised by the Starter Pack). The
-- server locks this in when the crop is planted and the Farm bar shows the
-- same number - both call this, so the amount announced is the amount
-- harvested.
function FarmDefs.FoodFor(crop, multiplier)
	if not crop then
		return 0
	end
	return math.floor((crop.Food or 0) * (multiplier or 1))
end

-- Price of the next farm when `ownedCount` are already owned (the free
-- starting farm included): 250, 400, 640, 1024...
function FarmDefs.GetPrice(ownedCount)
	return math.floor(FarmDefs.ShopBaseCost * FarmDefs.CostGrowth ^ math.max(0, ownedCount - 1))
end

return FarmDefs
