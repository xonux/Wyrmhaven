return {
	-- Dragon levels (see Config/DragonLevels). A dragon hatches at level 1 and
	-- is fed Food to level up, up to DragonMaxLevel. It turns from Baby into
	-- Adult at DragonAdultLevel: a Baby already earns Coins (at
	-- BabyIncomeMultiplier of the rate), an Adult earns the full rate, can
	-- breed and will be the one that fights - levelling past it keeps making
	-- it stronger.
	-- Food for the level after L: DragonFeedFoodBase + DragonFeedFoodStep * (L - 1),
	-- so 10, 15, 20... (45 Food to become an Adult, 270 to reach level 10).
	DragonMaxLevel = 10,
	DragonAdultLevel = 4,
	DragonFeedFoodBase = 10,
	DragonFeedFoodStep = 5,
	IslandSpacingStuds = 400, -- distance between player islands along X: room for each island's beach, lagoon and sea
	IncomeTickSeconds = 1, -- how often Adult dragons accrue pending income
	-- Coins an Adult makes per minute (into its habitat's storage), by the
	-- rarity of its species (DragonDefs Rarity, see Config/DragonRules).
	IncomePerMinuteByRarity = { Common = 30, Rare = 40, Epic = 50, Legendary = 60 },
	-- A Baby earns too, at this share of its species' rate (an Adult earns full).
	BabyIncomeMultiplier = 0.5,

	-- Combat stats (DragonRules.Stats): a level 1 Common of a neutral class.
	-- Its class tilts them (Config/DragonClasses Weights), its rarity scales
	-- them by StatRarityStep per step up (Common -> Rare -> Epic ->
	-- Legendary, so a Rare is ~25% above a Common), and every level above 1
	-- adds StatGrowthPerLevel of the base (level 10 = 1.9x).
	-- Attack against Health decides how long a fight runs. 60 against 130
	-- gives about 7 rounds - roughly 27 turns in all - which is the snappy
	-- pace the game is after. (20 against 200 used to give 25 rounds.)
	DragonBaseStats = { Attack = 60, Health = 130, Speed = 100 },
	-- Team spirit: every class beyond the first in a team gives all three of
	-- its dragons this much more Attack and Health (one class +0%, two +8%,
	-- three +16%). Without it, three Attackers simply beat any mixed team:
	-- a turn spent shielding or healing is worth less than a turn spent
	-- killing, so this is what pays for bringing a Tank or a Support.
	TeamClassBonus = 0.08,
	-- Elements (Config/ElementChart): every skill has one, and it decides how
	-- hard it lands. A skill hitting the element it beats does
	-- ElementAdvantageMultiplier; a skill hitting its own element does
	-- ElementSameMultiplier. Nothing else changes - the losing side of a
	-- matchup is not punished a second time.
	ElementAdvantageMultiplier = 1.5,
	ElementSameMultiplier = 0.5,
	StatRarityStep = 1.25,
	StatGrowthPerLevel = 0.1,
	RareEggGemPrice = 50, -- a rare (two-element) dragon's egg in the Shop
	-- Coins a dragon sells for (DragonScreen's Sell, or instead of placing a
	-- hatchling), by rarity. Epic / Legendary: not sellable until set.
	SellPriceByRarity = { Common = 100, Rare = 1000 },
	StartingCoins = 500, -- initial Coins balance on join, enough to test feeding/harvest loops
	StartingGems = 0, -- Gems have no source/sink for new players yet in Phase 1/2, ledger just needs to exist
	HudPushIntervalSeconds = 1, -- how often the server pushes Coins/Gems/Food to the HUD
	-- Seconds a Nursery pairing takes, by the rarity of the egg it gives
	-- (proposed values; Common as before). Skippable with Gems (GemSpeedUp).
	BreedingSecondsByRarity = { Common = 300, Rare = 900, Epic = 3600, Legendary = 14400 },
	NurseryMax = 2, -- the free one, plus one bought in the Shop (Buildings)
	NurseryGemPrice = 100, -- the 2nd Nursery, bought instantly with Gems
	BreedingTickSeconds = 1, -- how often BreedingService checks pairings / pushes status

	-- Incubator (Hatchery): every egg (starter or bred) sits here and hatches on
	-- a timer instead of being fed directly in a Habitat - see IncubatorService.
	-- Seconds an egg takes to hatch, by the rarity of its dragon (proposed
	-- values; Common as before). Skippable with Gems (GemSpeedUp).
	HatchSecondsByRarity = { Common = 90, Rare = 300, Epic = 1800, Legendary = 7200 },
	IncubatorTickSeconds = 1,
	IncubatorCapacity = 4, -- nests on the Incubator's rock once fully upgraded
	IncubatorStartNests = 1,
	-- Gems for each extra nest, bought in the Incubator's bar (2nd, 3rd, 4th).
	IncubatorNestGemPrices = { 25, 50, 100 },
	-- Skipping any timer (hatching, breeding, crops, construction, upgrade, clearing) costs Gems
	-- by the time left: see Config/GemSpeedUp.

	HabitatSellRefundPercent = 0.5, -- Coins refunded (of the price actually paid) when selling an empty Habitat
	DecorationSellRefundPercent = 0.5, -- Coins refunded (of its Shop price) when selling a decoration

	-- Player level (LevelService): XP needed to go from level L to L + 1 is
	-- XpBaseRequired * XpGrowth ^ (L - 1), rounded - 100, 120, 144, 173...
	XpBaseRequired = 100,
	XpGrowth = 1.2,
	LevelUpGems = 5, -- Gems given at each player level up (LevelService)
	-- XP for a hatched dragon, given when it's placed in a habitat, by its
	-- DragonDefs Rarity. Rarity doesn't exist
	-- yet: every dragon counts as Common until it does. Placeholder values.
	HatchXpByRarity = { Common = 50, Rare = 150, Epic = 400, Legendary = 1000 },

	-- Placement grid covering each island's buildable grass: GridTilesPerSide x
	-- GridTilesPerSide tiles of GridTileSize studs, tile (0,0) at the -X,-Z corner.
	GridTileSize = 4,
	GridTilesPerSide = 30,

	-- Square grid footprint (in 4-stud tiles) of each building type, shared by
	-- the services that place them and the client's placement preview.
	StructureTiles = { Habitat = 4, Farm = 3, Nursery = 3, Incubator = 3 },
}
