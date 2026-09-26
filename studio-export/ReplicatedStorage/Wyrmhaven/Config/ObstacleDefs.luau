-- Obstacles covering the outer tiles of every island (IslandObstacles says
-- where). Clearing one costs Price Coins and takes Duration seconds, then
-- frees its Tiles x Tiles footprint for building. First balance pass - tune
-- freely.
return {
	Rock = { DisplayName = "Rock", Tiles = 1, Price = 50, Duration = 30 },
	Tree = { DisplayName = "Tree", Tiles = 2, Price = 150, Duration = 120 },
	BigRock = { DisplayName = "Big Rock", Tiles = 3, Price = 500, Duration = 600 },
}
