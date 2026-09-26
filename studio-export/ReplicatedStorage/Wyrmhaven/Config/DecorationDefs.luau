-- Purely decorative items for the island - no gameplay effect. Bought in the
-- Shop and placed on the grid like a building (TilesX wide along X, TilesZ deep
-- along Z; models face the camera, towards +Z), then
-- movable and sellable (DecorationService). Each has a model in
-- ReplicatedStorage.Wyrmhaven.Assets.Decorations. Prices are a first pass.
local rgb = Color3.fromRGB

return {
	PavingStone = { DisplayName = "Stone Paving", Price = 20, TilesX = 1, TilesZ = 1, SortOrder = 1, AccentColor = rgb(150, 152, 150) },
	PavingSand = { DisplayName = "Light Paving", Price = 30, TilesX = 1, TilesZ = 1, SortOrder = 2, AccentColor = rgb(226, 206, 160) },
	Bush = { DisplayName = "Flowering Bush", Price = 50, TilesX = 1, TilesZ = 1, SortOrder = 3, AccentColor = rgb(96, 168, 80) },
	FlowerBed = { DisplayName = "Flower Bed", Price = 60, TilesX = 1, TilesZ = 1, SortOrder = 4, AccentColor = rgb(214, 96, 120) },
	TreeGreen = { DisplayName = "Green Tree", Price = 80, TilesX = 2, TilesZ = 2, SortOrder = 5, AccentColor = rgb(98, 172, 70) },
	Pine = { DisplayName = "Pine Tree", Price = 100, TilesX = 2, TilesZ = 2, SortOrder = 6, AccentColor = rgb(52, 120, 76) },
	TreeAutumn = { DisplayName = "Autumn Tree", Price = 120, TilesX = 2, TilesZ = 2, SortOrder = 7, AccentColor = rgb(226, 120, 48) },
	TreeBlossom = { DisplayName = "Cherry Blossom", Price = 180, TilesX = 2, TilesZ = 2, SortOrder = 8, AccentColor = rgb(240, 160, 196) },
	TreeMystic = { DisplayName = "Mystic Tree", Price = 250, TilesX = 2, TilesZ = 2, SortOrder = 9, AccentColor = rgb(150, 104, 214) },
	Bench = { DisplayName = "Bench", Price = 120, TilesX = 2, TilesZ = 1, SortOrder = 10, AccentColor = rgb(170, 116, 70) },
	Lantern = { DisplayName = "Lantern", Price = 150, TilesX = 1, TilesZ = 1, SortOrder = 11, AccentColor = rgb(250, 204, 100) },
	Fountain = { DisplayName = "Fountain", Price = 600, TilesX = 3, TilesZ = 3, SortOrder = 12, AccentColor = rgb(110, 196, 226) },
}
