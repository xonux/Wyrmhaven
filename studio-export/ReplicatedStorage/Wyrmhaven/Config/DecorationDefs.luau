-- Shop decorations (docs/design/phase2-shop.md, "Décorations" section).
-- Each entry targets exactly one resource (Coins or Food) - buying the
-- "Coins" vs "Food" variant of a tier is the player's choice of what to
-- boost, rather than a runtime parameter on a shared catalog entry.
return {
	SmallCoins = { DisplayName = "Small Coin Charm", Price = 300, Radius = 20, BonusPercent = 5, Resource = "Coins", PlatformColor = Color3.fromRGB(255, 215, 90) },
	MediumCoins = { DisplayName = "Medium Coin Charm", Price = 800, Radius = 20, BonusPercent = 10, Resource = "Coins", PlatformColor = Color3.fromRGB(255, 200, 60) },
	LargeCoins = { DisplayName = "Large Coin Charm", Price = 2000, Radius = 20, BonusPercent = 15, Resource = "Coins", PlatformColor = Color3.fromRGB(255, 180, 30) },
	SmallFood = { DisplayName = "Small Farm Charm", Price = 300, Radius = 20, BonusPercent = 5, Resource = "Food", PlatformColor = Color3.fromRGB(160, 210, 110) },
	MediumFood = { DisplayName = "Medium Farm Charm", Price = 800, Radius = 20, BonusPercent = 10, Resource = "Food", PlatformColor = Color3.fromRGB(130, 195, 90) },
	LargeFood = { DisplayName = "Large Farm Charm", Price = 2000, Radius = 20, BonusPercent = 15, Resource = "Food", PlatformColor = Color3.fromRGB(95, 170, 65) },
}
