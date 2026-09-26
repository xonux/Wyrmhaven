-- Dragon species. Keys are species ids (saved on every dragon as its
-- "element"): one Common species per element (Fire, Water, Nature, Earth,
-- Electric, Metal, Dark, Light - the HabitatDefs keys) and one Rare hybrid
-- per pair of elements, generated below - its id stays the two elements
-- ("FireWater") but it has a name of its own ("Smoke Dragon").
-- Rarity: Common / Rare / Epic / Legendary - sets its income
-- (GameConstants.IncomePerMinuteByRarity) and hatching XP (HatchXpByRarity).
-- Elements: the habitat elements it can live in (a hybrid: either of its
-- two). Class: its role in a fight (Config/DragonClasses) - it also sets how
-- its combat stats lean, which DragonRules.Stats works out from the class,
-- the rarity and the dragon's level rather than from a number per species.
-- Breeding results and helpers live in Config/DragonRules.
-- EggPrice: Coins for a Common egg in the Shop, the same as a habitat of its
-- element (HabitatDefs.ShopBaseCost). GemPrice: Gems instead (rare eggs).
-- Either is only sold from the player level that unlocks all its elements
-- (HabitatDefs.UnlockLevel). SortOrder: the Shop's dragons tab lists the
-- Commons first (unlock order), then the Rares.
-- Every bought or bred dragon starts as an egg in the Incubator.
local HabitatDefs = require(script.Parent.HabitatDefs)
local GameConstants = require(script.Parent.GameConstants)

local STAGE_SIZES = {
	Egg = Vector3.new(2, 2.6, 2),
	Baby = Vector3.new(3.5, 3.5, 4.5),
	Adult = Vector3.new(5.5, 5.5, 7.5),
}

local defs = {
	Fire = {
		DisplayName = "Fire Dragon",
		Rarity = "Common",
		Class = "Attacker",
		Skills = { "EmberBite", "FlameBurst", "SearingMark" },
		Elements = { "Fire" },
		SortOrder = 1,
		EggPrice = HabitatDefs.Fire.ShopBaseCost,
		-- Phase 3 prep (combat not implemented yet): global per-element defaults for
		-- now, so save data won't need migrating later. Once dragons can level up
		-- individually in Phase 3, move these to be tracked per dragon instance.
		StageColors = {
			Egg = Color3.fromRGB(232, 68, 42),
			Baby = Color3.fromRGB(242, 130, 59),
			Adult = Color3.fromRGB(242, 130, 59),
		},
		StageSizes = STAGE_SIZES,
	},
	Water = {
		DisplayName = "Water Dragon",
		Rarity = "Common",
		Class = "Support",
		Skills = { "WaterJet", "HealingTide", "SoothingCurrent" },
		Elements = { "Water" },
		SortOrder = 2,
		EggPrice = HabitatDefs.Water.ShopBaseCost,
		StageColors = {
			Egg = Color3.fromRGB(27, 90, 158),
			Baby = Color3.fromRGB(46, 134, 217),
			Adult = Color3.fromRGB(46, 134, 217),
		},
		StageSizes = STAGE_SIZES,
	},
	Nature = {
		DisplayName = "Nature Dragon",
		Rarity = "Common",
		Class = "Control",
		Skills = { "VineLash", "Entangle", "SporeCloud" },
		Elements = { "Nature" },
		SortOrder = 3,
		EggPrice = HabitatDefs.Nature.ShopBaseCost,
		StageColors = {
			Egg = Color3.fromRGB(46, 125, 50),
			Baby = Color3.fromRGB(76, 175, 80),
			Adult = Color3.fromRGB(76, 175, 80),
		},
		StageSizes = STAGE_SIZES,
	},
	-- Was "Lightning" in older saves - SaveService migrates the name.
	Electric = {
		DisplayName = "Electric Dragon",
		Rarity = "Common",
		Class = "Attacker",
		Skills = { "ArcStrike", "ChainLightning", "OverchargeCoil" },
		Elements = { "Electric" },
		SortOrder = 5,
		EggPrice = HabitatDefs.Electric.ShopBaseCost,
		StageColors = {
			Egg = Color3.fromRGB(200, 150, 20),
			Baby = Color3.fromRGB(240, 196, 40),
			Adult = Color3.fromRGB(240, 196, 40),
		},
		StageSizes = STAGE_SIZES,
	},
	Earth = {
		DisplayName = "Earth Dragon",
		Rarity = "Common",
		Class = "Tank",
		Skills = { "StoneSlam", "BedrockGuard", "Tremor" },
		Elements = { "Earth" },
		SortOrder = 4,
		EggPrice = HabitatDefs.Earth.ShopBaseCost,
		StageColors = {
			Egg = Color3.fromRGB(92, 69, 48),
			Baby = Color3.fromRGB(138, 106, 74),
			Adult = Color3.fromRGB(138, 106, 74),
		},
		StageSizes = STAGE_SIZES,
	},
	Light = {
		DisplayName = "Light Dragon",
		Rarity = "Common",
		Class = "Support",
		Skills = { "RadiantBeam", "DawnBlessing", "GuidingLight" },
		Elements = { "Light" },
		SortOrder = 8,
		EggPrice = HabitatDefs.Light.ShopBaseCost,
		StageColors = {
			Egg = Color3.fromRGB(220, 206, 160),
			Baby = Color3.fromRGB(246, 238, 212),
			Adult = Color3.fromRGB(246, 238, 212),
		},
		StageSizes = STAGE_SIZES,
	},
	Dark = {
		DisplayName = "Dark Dragon",
		Rarity = "Common",
		Class = "Control",
		Skills = { "ShadowRake", "CurseOfNight", "SoulDrain" },
		Elements = { "Dark" },
		SortOrder = 7,
		EggPrice = HabitatDefs.Dark.ShopBaseCost,
		StageColors = {
			Egg = Color3.fromRGB(58, 36, 86),
			Baby = Color3.fromRGB(98, 64, 142),
			Adult = Color3.fromRGB(98, 64, 142),
		},
		StageSizes = STAGE_SIZES,
	},
	Metal = {
		DisplayName = "Metal Dragon",
		Rarity = "Common",
		Class = "Tank",
		Skills = { "IronCharge", "PlatedHide", "MagnetPull" },
		Elements = { "Metal" },
		SortOrder = 6,
		EggPrice = HabitatDefs.Metal.ShopBaseCost,
		StageColors = {
			Egg = Color3.fromRGB(104, 112, 124),
			Baby = Color3.fromRGB(158, 168, 180),
			Adult = Color3.fromRGB(158, 168, 180),
		},
		StageSizes = STAGE_SIZES,
	},
}

-- Each hybrid's own name, by its two elements in unlock order. Saves only
-- ever store the id ("FireWater"), so renaming one here is free.
-- Each hybrid's class, kept next to its name so the two read together.
-- Roughly even across the four: 8 Attackers, 7 Tanks, 6 Supports, 7 Controls.
local HYBRID_CLASSES = {
	FireWater = "Control", -- Smoke
	FireNature = "Attacker", -- Ash
	FireEarth = "Attacker", -- Lava
	FireElectric = "Attacker", -- Plasma
	FireMetal = "Tank", -- Forge
	FireDark = "Attacker", -- Inferno
	FireLight = "Support", -- Solar
	WaterNature = "Control", -- Swamp
	WaterEarth = "Control", -- Ice
	WaterElectric = "Attacker", -- Storm
	WaterMetal = "Tank", -- Rust
	WaterDark = "Control", -- Abyss
	WaterLight = "Support", -- Rainbow
	NatureEarth = "Tank", -- Forest
	NatureElectric = "Support", -- Pollen
	NatureMetal = "Tank", -- Thorn
	NatureDark = "Control", -- Poison
	NatureLight = "Support", -- Blossom
	EarthElectric = "Control", -- Magnet
	EarthMetal = "Tank", -- Bronze
	EarthDark = "Tank", -- Fossil
	EarthLight = "Support", -- Crystal
	ElectricMetal = "Attacker", -- Circuit
	ElectricDark = "Attacker", -- Thunder
	ElectricLight = "Support", -- Aurora
	MetalDark = "Attacker", -- Blade
	MetalLight = "Tank", -- Silver
	DarkLight = "Control", -- Eclipse
}

-- Each hybrid's three skills (Config/SkillDefs), by its id.
local HYBRID_SKILLS = {
	DarkLight = { "EclipseSlash", "TotalDarkness", "EquinoxGrace" },
	EarthDark = { "FossilCrush", "AncientCarapace", "BoneShards" },
	EarthElectric = { "MagneticJolt", "PolarityShift", "GravityGrip" },
	EarthLight = { "CrystalShard", "RefractiveWard", "CrystalSong" },
	EarthMetal = { "BronzeBash", "AegisStance", "GuardianCall" },
	ElectricDark = { "ThunderFang", "BlackBolt", "StormCurse" },
	ElectricLight = { "AuroraBeam", "PolarLights", "DazzlingFlash" },
	ElectricMetal = { "CircuitStrike", "OverloadSurge", "SystemPurge" },
	FireDark = { "HellfireBite", "InfernalRoar", "SoulEmber" },
	FireEarth = { "MoltenFang", "LavaFlow", "EruptionCore" },
	FireElectric = { "PlasmaLance", "IonBlast", "StaticField" },
	FireLight = { "SunRay", "SolarFlare", "Sunbath" },
	FireMetal = { "AnvilStrike", "MoltenPlating", "ForgeHeat" },
	FireNature = { "AshClaw", "EmberStorm", "BrambleSnare" },
	FireWater = { "CinderSpit", "SmokeScreen", "ChokingHaze" },
	MetalDark = { "BladeDance", "ShadowCut", "EdgeSharpening" },
	MetalLight = { "SilverStrike", "MirrorPlating", "PurifyingGleam" },
	NatureDark = { "VenomBite", "ToxicBloom", "Neurotoxin" },
	NatureEarth = { "RootSmash", "Ironbark", "Landslide" },
	NatureElectric = { "PollenDart", "BloomingAura", "StaticBloom" },
	NatureLight = { "PetalSlash", "SpringBloom", "SunlitGift" },
	NatureMetal = { "BarbedLash", "SpikedShell", "ThornVolley" },
	WaterDark = { "AbyssalPull", "CrushingDepths", "DrowningGrasp" },
	WaterEarth = { "FrostFang", "Permafrost", "StoneTomb" },
	WaterElectric = { "SquallStrike", "ThunderSurge", "Downpour" },
	WaterLight = { "PrismJet", "PrismaticVeil", "TideMend" },
	WaterMetal = { "CorrodedClaw", "RustArmor", "OxideCloud" },
	WaterNature = { "MireSpit", "QuagmireGrip", "BlightCloud" },
}

local HYBRID_NAMES = {
	FireWater = "Smoke",
	FireNature = "Ash",
	FireEarth = "Lava",
	FireElectric = "Plasma",
	FireMetal = "Forge",
	FireDark = "Inferno",
	FireLight = "Solar",
	WaterNature = "Swamp",
	WaterEarth = "Ice",
	WaterElectric = "Storm",
	WaterMetal = "Rust",
	WaterDark = "Abyss",
	WaterLight = "Rainbow",
	NatureEarth = "Forest",
	NatureElectric = "Pollen",
	NatureMetal = "Thorn",
	NatureDark = "Poison",
	NatureLight = "Blossom",
	EarthElectric = "Magnet",
	EarthMetal = "Bronze",
	EarthDark = "Fossil",
	EarthLight = "Crystal",
	ElectricMetal = "Circuit",
	ElectricDark = "Thunder",
	ElectricLight = "Aurora",
	MetalDark = "Blade",
	MetalLight = "Silver",
	DarkLight = "Eclipse",
}

-- Rare hybrids: one per pair of elements, bred from their two Common dragons
-- or bought for Gems. The id follows the elements' unlock order
-- ("FireWater"), the name comes from HYBRID_NAMES ("Smoke Dragon") and the
-- class from HYBRID_CLASSES; colors are a blend of the two parents'
-- (placeholders until they get models).
local elements = {}
for element in pairs(HabitatDefs) do
	table.insert(elements, element)
end
table.sort(elements, function(a, b)
	return HabitatDefs[a].SortOrder < HabitatDefs[b].SortOrder
end)

local hybrids = {}
for i = 1, #elements - 1 do
	for j = i + 1, #elements do
		table.insert(hybrids, { elements[i], elements[j] })
	end
end
-- Shop order: by the level that unlocks both elements, then by element order.
local function unlockLevel(element)
	return HabitatDefs[element].UnlockLevel or 1
end
table.sort(hybrids, function(a, b)
	local levelA = math.max(unlockLevel(a[1]), unlockLevel(a[2]))
	local levelB = math.max(unlockLevel(b[1]), unlockLevel(b[2]))
	if levelA ~= levelB then
		return levelA < levelB
	end
	if a[1] ~= b[1] then
		return HabitatDefs[a[1]].SortOrder < HabitatDefs[b[1]].SortOrder
	end
	return HabitatDefs[a[2]].SortOrder < HabitatDefs[b[2]].SortOrder
end)

for index, pair in ipairs(hybrids) do
	local a, b = defs[pair[1]], defs[pair[2]]
	local colors = {}
	for stage, color in pairs(a.StageColors) do
		colors[stage] = color:Lerp(b.StageColors[stage], 0.5)
	end
	local id = pair[1] .. pair[2]
	defs[id] = {
		DisplayName = string.format("%s Dragon", HYBRID_NAMES[id] or (pair[1] .. "-" .. pair[2])),
		Rarity = "Rare",
		Elements = { pair[1], pair[2] },
		SortOrder = 10 + index, -- after every Common (1 to 8)
		GemPrice = GameConstants.RareEggGemPrice,
		Class = HYBRID_CLASSES[id] or "Attacker",
		Skills = HYBRID_SKILLS[id],
		StageColors = colors,
		StageSizes = STAGE_SIZES,
	}
end

return defs
