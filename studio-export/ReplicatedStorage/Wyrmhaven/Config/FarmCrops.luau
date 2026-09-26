-- Crops the Farm can grow, cheapest first (FarmService, FarmPanelController).
-- One crop at a time: pay Price Coins, wait Duration seconds, harvest Food.
-- Pricier crops take longer but give more Food per Coin. A farm at level N
-- grows the first N (see FarmDefs.UpgradeCost).
--
-- Food was doubled on 2026-09-26 (the user's call): the pace they had been
-- playing at was the Starter Pack's x2 bonus, and they wanted it for every
-- player. Prices and growing times are unchanged, so a Coin now buys twice
-- the Food and raising a dragon takes half as long (10 to 55 Food a level,
-- 270 for all ten - see Config/DragonLevels). The Starter Pack still
-- doubles these numbers on top (FarmDefs.FoodFor).
return {
	{ Id = "Berries", DisplayName = "Berries", Price = 20, Duration = 30, Food = 10 },
	{ Id = "Carrots", DisplayName = "Carrots", Price = 60, Duration = 120, Food = 40 },
	{ Id = "Apples", DisplayName = "Apples", Price = 150, Duration = 600, Food = 120 },
	{ Id = "Pumpkins", DisplayName = "Pumpkins", Price = 400, Duration = 3600, Food = 400 },
	{ Id = "Melons", DisplayName = "Melons", Price = 1000, Duration = 14400, Food = 1200 },
}
