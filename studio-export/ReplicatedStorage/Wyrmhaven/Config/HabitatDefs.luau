-- Per-element habitat definitions, one per DragonDefs element (Fire, Water,
-- Nature, Earth, Electric, Metal, Dark, Light). Only Fire has a free starter
-- habitat (BaseCost = 0), the rest are shop-only from their very first habitat.
-- ShopBaseCost: the Shop price, the same for every habitat of that element.
-- StorageBase: Coins its dragons can pile up at level 1 before a harvest.
-- Levels 2 to 5 (upgrade costs, storage, dragons) come from HabitatLevels:
-- cheap elements make early-game habitats, and all meet at level 5.
-- Capacity: dragon slots of the model (what a level 5 habitat holds).
-- SortOrder: Shop order. BuildDuration: seconds of construction after a Shop
-- purchase - the habitat takes no dragon before, and its XP comes at the end
-- (placeholder values).
-- UnlockLevel: player level from which the Shop sells this element - its
-- habitats AND its dragons' eggs (ShopService refuses before; the Shop shows
-- the card locked). By price: the cheaper the element, the sooner (proposed
-- values).
local PLATFORM_SIZE = Vector3.new(16, 1, 16)

return {
	Fire = {
		DisplayName = "Fire Habitat",
		SortOrder = 1,
		BuildDuration = 60,
		Capacity = 4,
		BaseCost = 0, -- first habitat is free per design; real pricing wired up in Phase 1 step 5 (economy)
		ShopBaseCost = 200,
		UnlockLevel = 1,
		StorageBase = 200,
		PlatformSize = PLATFORM_SIZE,
		PlatformColor = Color3.fromRGB(214, 121, 76),
	},
	Water = {
		DisplayName = "Water Habitat",
		SortOrder = 2,
		BuildDuration = 120,
		Capacity = 4,
		BaseCost = 0, -- unused: Water has no free starter habitat, only ShopBaseCost applies
		ShopBaseCost = 300,
		UnlockLevel = 3,
		StorageBase = 300,
		PlatformSize = PLATFORM_SIZE,
		PlatformColor = Color3.fromRGB(94, 138, 168),
	},
	Nature = {
		DisplayName = "Nature Habitat",
		SortOrder = 3,
		BuildDuration = 120,
		Capacity = 4,
		BaseCost = 0,
		ShopBaseCost = 500,
		UnlockLevel = 5,
		StorageBase = 400,
		PlatformSize = PLATFORM_SIZE,
		PlatformColor = Color3.fromRGB(107, 158, 110),
	},
	-- Was "Lightning" in older saves - SaveService migrates the name.
	Electric = {
		DisplayName = "Electric Habitat",
		SortOrder = 5,
		BuildDuration = 180,
		Capacity = 4,
		BaseCost = 0,
		ShopBaseCost = 1200,
		UnlockLevel = 11,
		StorageBase = 800,
		PlatformSize = PLATFORM_SIZE,
		PlatformColor = Color3.fromRGB(196, 172, 90),
	},
	Earth = {
		DisplayName = "Earth Habitat",
		SortOrder = 4,
		BuildDuration = 180,
		Capacity = 4,
		BaseCost = 0,
		ShopBaseCost = 800,
		UnlockLevel = 8,
		StorageBase = 600,
		PlatformSize = PLATFORM_SIZE,
		PlatformColor = Color3.fromRGB(150, 124, 94),
	},
	Light = {
		DisplayName = "Light Habitat",
		SortOrder = 8,
		BuildDuration = 300,
		Capacity = 4,
		BaseCost = 0,
		ShopBaseCost = 2400,
		UnlockLevel = 20,
		StorageBase = 1400,
		PlatformSize = PLATFORM_SIZE,
		PlatformColor = Color3.fromRGB(226, 222, 204),
	},
	Dark = {
		DisplayName = "Dark Habitat",
		SortOrder = 7,
		BuildDuration = 300,
		Capacity = 4,
		BaseCost = 0,
		ShopBaseCost = 2000,
		UnlockLevel = 16,
		StorageBase = 1200,
		PlatformSize = PLATFORM_SIZE,
		PlatformColor = Color3.fromRGB(84, 70, 104),
	},
	Metal = {
		DisplayName = "Metal Habitat",
		SortOrder = 6,
		BuildDuration = 300,
		Capacity = 4,
		BaseCost = 0,
		ShopBaseCost = 1600,
		UnlockLevel = 13,
		StorageBase = 1000,
		PlatformSize = PLATFORM_SIZE,
		PlatformColor = Color3.fromRGB(128, 136, 146),
	},
}
