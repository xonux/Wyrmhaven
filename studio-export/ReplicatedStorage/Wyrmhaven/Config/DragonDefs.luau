-- Per-element dragon definitions. Phase 2 (docs/design/phase2-elements.md)
-- adds Water/Nature/Lightning/Earth alongside Fire; all share Fire's growth
-- thresholds/income (deliberately not power-creeping the newer elements) and
-- only differ in palette + Attack/Defense/Health orientation.
local STAGE_SIZES = {
	Egg = Vector3.new(2, 2.6, 2),
	Baby = Vector3.new(3.5, 3.5, 4.5),
	Adult = Vector3.new(5.5, 5.5, 7.5),
}

return {
	Fire = {
		DisplayName = "Fire Dragon",
		EggGrowthRequired = 100,
		BabyGrowthRequired = 150,
		IncomeRatePerSecond = 1,
		IncomeCap = 100,
		-- Phase 3 prep (combat not implemented yet): global per-element defaults for
		-- now, so save data won't need migrating later. Once dragons can level up
		-- individually in Phase 3, move these to be tracked per dragon instance.
		Attack = 12,
		Defense = 8,
		Health = 100,
		StageColors = {
			Egg = Color3.fromRGB(232, 68, 42),
			Baby = Color3.fromRGB(242, 130, 59),
			Adult = Color3.fromRGB(242, 130, 59),
		},
		StageSizes = STAGE_SIZES,
	},
	Water = {
		DisplayName = "Water Dragon",
		EggGrowthRequired = 100,
		BabyGrowthRequired = 150,
		IncomeRatePerSecond = 1,
		IncomeCap = 100,
		Attack = 8,
		Defense = 14, -- Defense-leaning per phase2-elements.md
		Health = 100,
		StageColors = {
			Egg = Color3.fromRGB(27, 90, 158),
			Baby = Color3.fromRGB(46, 134, 217),
			Adult = Color3.fromRGB(46, 134, 217),
		},
		StageSizes = STAGE_SIZES,
	},
	Nature = {
		DisplayName = "Nature Dragon",
		EggGrowthRequired = 100,
		BabyGrowthRequired = 150,
		IncomeRatePerSecond = 1,
		IncomeCap = 100,
		Attack = 8,
		Defense = 8,
		Health = 130, -- Health-leaning per phase2-elements.md
		StageColors = {
			Egg = Color3.fromRGB(46, 125, 50),
			Baby = Color3.fromRGB(76, 175, 80),
			Adult = Color3.fromRGB(76, 175, 80),
		},
		StageSizes = STAGE_SIZES,
	},
	Lightning = {
		DisplayName = "Lightning Dragon",
		EggGrowthRequired = 100,
		BabyGrowthRequired = 150,
		IncomeRatePerSecond = 1,
		IncomeCap = 100,
		Attack = 16, -- Attack-leaning per phase2-elements.md
		Defense = 6,
		Health = 90,
		StageColors = {
			Egg = Color3.fromRGB(90, 46, 158),
			Baby = Color3.fromRGB(142, 95, 209),
			Adult = Color3.fromRGB(142, 95, 209),
		},
		StageSizes = STAGE_SIZES,
	},
	Earth = {
		DisplayName = "Earth Dragon",
		EggGrowthRequired = 100,
		BabyGrowthRequired = 150,
		IncomeRatePerSecond = 1,
		IncomeCap = 100,
		Attack = 7,
		Defense = 15, -- Defense-leaning per phase2-elements.md
		Health = 110,
		StageColors = {
			Egg = Color3.fromRGB(92, 69, 48),
			Baby = Color3.fromRGB(138, 106, 74),
			Adult = Color3.fromRGB(138, 106, 74),
		},
		StageSizes = STAGE_SIZES,
	},

	-- Shop-exclusive dragon (docs/design/phase2-shop.md "Dragons exclusifs"):
	-- bought directly for Gems via ShopService.BuyExclusiveDragon, spawns
	-- straight to Adult, never obtainable via egg/breeding. HabitatElement
	-- says which habitat element it slots into - it isn't itself a
	-- purchasable habitat element like Fire/Water/etc, so it isn't in
	-- HabitatDefs. GemPrice/IncomeRatePerSecond below are a proposal, not
	-- confirmed by the user yet (see shop-exclusive-dragons.md).
	FireExclusive = {
		DisplayName = "Ember Sovereign",
		HabitatElement = "Fire",
		Exclusive = true,
		GemPrice = 250,
		Breedable = true, -- can still be used as a breeding parent; set false per-def to opt out
		EggGrowthRequired = 100,
		BabyGrowthRequired = 150,
		IncomeRatePerSecond = 2, -- premium: double Fire's rate to justify spending Gems on it
		IncomeCap = 150,
		Attack = 18,
		Defense = 10,
		Health = 120,
		StageColors = {
			Egg = Color3.fromRGB(232, 68, 42),
			Baby = Color3.fromRGB(242, 130, 59),
			Adult = Color3.fromRGB(255, 200, 40), -- gold, visually distinct from standard Fire
		},
		StageSizes = STAGE_SIZES,
	},
}
