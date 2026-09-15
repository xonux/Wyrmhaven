-- Per-element habitat definitions. Phase 2 (docs/design/phase2-elements.md)
-- adds Water/Nature/Lightning/Earth; only Fire has a free starter habitat
-- (BaseCost = 0), the rest are shop-only from their very first habitat.
-- ShopBaseCost is the real Shop price (see shop-habitats.md), consumed by
-- ShopService as: ShopBaseCost * CostGrowth ^ (habitats already owned).
local PLATFORM_SIZE = Vector3.new(16, 1, 16)

return {
	Fire = {
		DisplayName = "Fire Habitat",
		Capacity = 4,
		BaseCost = 0, -- first habitat is free per design; real pricing wired up in Phase 1 step 5 (economy)
		ShopBaseCost = 200, -- price of the 2nd+ Fire habitat via the Shop
		CostGrowth = 1.6, -- multiplier applied per additional habitat of this element
		PlatformSize = PLATFORM_SIZE,
		PlatformColor = Color3.fromRGB(214, 121, 76),
	},
	Water = {
		DisplayName = "Water Habitat",
		Capacity = 4,
		BaseCost = 0, -- unused: Water has no free starter habitat, only ShopBaseCost applies
		ShopBaseCost = 350,
		CostGrowth = 1.6,
		PlatformSize = PLATFORM_SIZE,
		PlatformColor = Color3.fromRGB(94, 138, 168),
	},
	Nature = {
		DisplayName = "Nature Habitat",
		Capacity = 4,
		BaseCost = 0,
		ShopBaseCost = 350,
		CostGrowth = 1.6,
		PlatformSize = PLATFORM_SIZE,
		PlatformColor = Color3.fromRGB(107, 158, 110),
	},
	Lightning = {
		DisplayName = "Lightning Habitat",
		Capacity = 4,
		BaseCost = 0,
		ShopBaseCost = 450,
		CostGrowth = 1.6,
		PlatformSize = PLATFORM_SIZE,
		PlatformColor = Color3.fromRGB(150, 124, 186),
	},
	Earth = {
		DisplayName = "Earth Habitat",
		Capacity = 4,
		BaseCost = 0,
		ShopBaseCost = 450,
		CostGrowth = 1.6,
		PlatformSize = PLATFORM_SIZE,
		PlatformColor = Color3.fromRGB(150, 124, 94),
	},
}
