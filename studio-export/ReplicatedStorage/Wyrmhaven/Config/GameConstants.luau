return {
	FoodGrowthAmount = 25, -- growth points added per feeding (single food type for now)
	IslandSpacingStuds = 80, -- distance between player islands along X, avoids overlap for multiple testers
	IncomeTickSeconds = 1, -- how often Adult dragons accrue pending income
	StartingCoins = 500, -- initial Coins balance on join, enough to test feeding/harvest loops
	StartingGems = 0, -- Gems have no source/sink for new players yet in Phase 1/2, ledger just needs to exist
	FoodCostPerFeed = 1, -- Food units consumed per feeding (replaces the old free/Coins-based feeding)
	FarmFoodTickSeconds = 1, -- how often the Farm accrues pending Food
	FarmFoodRatePerSecond = 1, -- Food accrued per tick
	FarmFoodCap = 20, -- max Food the Farm can bank before it needs harvesting
	HudPushIntervalSeconds = 1, -- how often the server pushes Coins/Gems/Food to the HUD
	BreedingDurationSeconds = 300, -- Nursery pairing time (5 min, testable) before the egg is ready to collect
	BreedingTickSeconds = 1, -- how often BreedingService checks pairings / pushes status
}
