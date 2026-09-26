-- The PvE exploration map: ten stages along a path across two island
-- regions, each one a 3v3 fight against a set team. A stage opens when the
-- one before it is cleared, so the map is a single line of progress, and it
-- can be replayed for a smaller reward.
--
-- Two of them are bosses (stages 5 and 10). A boss is an ordinary dragon of
-- the game's own roster, drawn bigger and with better stats - nothing else
-- about it is special, so no new species or rule is needed for it.
--
-- Rewards are Food, Coins and XP, the three things the island already runs
-- on: Food raises the dragons that fight, Coins build, XP unlocks the next
-- element. They grow with the stage, and a boss pays about twice its
-- neighbours. See REWARD NOTES at the bottom for how the numbers were set.
local PveMap = {}

-- What a boss gets over the same dragon at the same level, and how much
-- bigger it is drawn. These numbers look timid and are not: measured against
-- teams of the same level, +40% Attack / +50% Health on ONE of three dragons
-- took the player from winning 47% of the time to winning 13%. A fight is a
-- race, so a dragon that both survives longer and kills faster keeps acting
-- while the other team shrinks, and the advantage compounds every round.
-- +20% / +30% is what makes a boss a wall without making it a brick.
PveMap.BossAttackMultiplier = 1.2
PveMap.BossHealthMultiplier = 1.3
PveMap.BossScale = 1.5 -- how much bigger its model is drawn

-- A stage already cleared can be fought again, for this share of its reward.
-- XP is cut harder than the rest: Coins and Food are spent again and again,
-- while XP only ever unlocks the next element, and that shouldn't be
-- farmable in a couple of minutes.
PveMap.RepeatShare = { Coins = 0.35, Food = 0.35, Xp = 0.2 }

-- The two island clusters the path crosses, in map studs (the map screen
-- lays its scenery out from this; x grows right, z grows toward the camera).
PveMap.Regions = {
	{ Id = 1, DisplayName = "Ember Coast", Center = { x = 50, z = 42 }, Size = { x = 96, z = 88 } },
	{ Id = 2, DisplayName = "Storm Reach", Center = { x = -45, z = -24 }, Size = { x = 96, z = 88 } },
}

-- Stepping stones drawn between the two regions, purely scenery.
PveMap.PathStones = {
	{ x = 14, z = 30 },
	{ x = -2, z = 14 },
}

-- Difficulty is the AI the other side plays with (Services/CombatAI):
-- Easy picks at random, Normal plays well, Hard reads the fight.
PveMap.Levels = {
	{
		Id = 1,
		DisplayName = "Scorched Sands",
		Region = 1,
		Position = { x = 70, z = 62 },
		Difficulty = "Easy",
		RecommendedLevel = 4,
		Enemies = {
			{ Species = "Fire", Level = 2 },
			{ Species = "Earth", Level = 2 },
			{ Species = "Nature", Level = 2 },
		},
		Rewards = { Coins = 120, Food = 8, Xp = 40 },
	},
	{
		Id = 2,
		DisplayName = "Ashen Trail",
		Region = 1,
		Position = { x = 52, z = 46 },
		Difficulty = "Easy",
		RecommendedLevel = 4,
		Enemies = {
			{ Species = "Fire", Level = 3 },
			{ Species = "Water", Level = 3 },
			{ Species = "Nature", Level = 3 },
		},
		Rewards = { Coins = 180, Food = 12, Xp = 60 },
	},
	{
		Id = 3,
		DisplayName = "Cinder Ridge",
		Region = 1,
		Position = { x = 62, z = 24 },
		Difficulty = "Normal",
		RecommendedLevel = 5,
		Enemies = {
			{ Species = "Fire", Level = 5 },
			{ Species = "Metal", Level = 5 },
			{ Species = "Nature", Level = 5 },
		},
		Rewards = { Coins = 260, Food = 16, Xp = 85 },
	},
	{
		Id = 4,
		DisplayName = "Emberfall Pass",
		Region = 1,
		Position = { x = 38, z = 20 },
		Difficulty = "Normal",
		RecommendedLevel = 6,
		Enemies = {
			{ Species = "Electric", Level = 5 },
			{ Species = "Earth", Level = 5 },
			{ Species = "Light", Level = 5 },
		},
		Rewards = { Coins = 360, Food = 20, Xp = 110 },
	},
	{
		Id = 5,
		DisplayName = "Magma Tyrant",
		Region = 1,
		Position = { x = 28, z = 46 },
		Boss = true,
		Difficulty = "Normal",
		RecommendedLevel = 6,
		-- An ordinary Fire Dragon, one level above its escort and with a boss's
		-- bonus. A Rare was tried here first and had to go: a rare boss this
		-- early asked for level 8 Commons, when the stage before it asks for 5.
		Enemies = {
			{ Species = "Fire", Level = 6, Boss = true, Name = "Magma Tyrant" },
			{ Species = "Earth", Level = 5 },
			{ Species = "Water", Level = 5 },
		},
		Rewards = { Coins = 700, Food = 40, Xp = 220 },
	},
	{
		Id = 6,
		DisplayName = "Windswept Cliffs",
		Region = 2,
		Position = { x = -18, z = -2 },
		Difficulty = "Normal",
		RecommendedLevel = 6,
		Enemies = {
			{ Species = "Electric", Level = 7 },
			{ Species = "Metal", Level = 7 },
			{ Species = "Water", Level = 7 },
		},
		Rewards = { Coins = 520, Food = 26, Xp = 150 },
	},
	{
		Id = 7,
		DisplayName = "Thunder Hollow",
		Region = 2,
		Position = { x = -34, z = -22 },
		Difficulty = "Normal",
		RecommendedLevel = 7,
		-- The first stage with a Rare on the other side: from here on, breeding
		-- hybrids is the way forward, not only feeding what you already have.
		Enemies = {
			{ Species = "WaterElectric", Level = 7 },
			{ Species = "Metal", Level = 7 },
			{ Species = "Nature", Level = 7 },
		},
		Rewards = { Coins = 680, Food = 32, Xp = 190 },
	},
	{
		Id = 8,
		DisplayName = "Iron Bluffs",
		Region = 2,
		Position = { x = -58, z = -12 },
		Difficulty = "Hard",
		RecommendedLevel = 8,
		Enemies = {
			{ Species = "EarthMetal", Level = 8 },
			{ Species = "ElectricMetal", Level = 8 },
			{ Species = "Light", Level = 8 },
		},
		Rewards = { Coins = 880, Food = 38, Xp = 240 },
	},
	{
		Id = 9,
		DisplayName = "Nightfall Crag",
		Region = 2,
		Position = { x = -70, z = -36 },
		Difficulty = "Hard",
		RecommendedLevel = 9,
		Enemies = {
			{ Species = "ElectricDark", Level = 9 },
			{ Species = "NatureDark", Level = 9 },
			{ Species = "EarthLight", Level = 9 },
		},
		Rewards = { Coins = 1100, Food = 44, Xp = 300 },
	},
	{
		Id = 10,
		DisplayName = "Blade Tyrant",
		Region = 2,
		Position = { x = -46, z = -46 },
		Boss = true,
		Difficulty = "Hard",
		RecommendedLevel = 10,
		-- Its escort is deliberately two levels down and short on healing: with
		-- the Eclipse / Silver pair (two team heals and a taunt) behind it, a
		-- full team of level 10 Rares still lost four fights out of five.
		Enemies = {
			{ Species = "MetalDark", Level = 10, Boss = true, Name = "Blade Tyrant" },
			{ Species = "FireDark", Level = 8 },
			{ Species = "EarthDark", Level = 8 },
		},
		Rewards = { Coins = 2200, Food = 90, Xp = 600 },
	},
}

PveMap.Count = #PveMap.Levels

function PveMap.Get(levelId)
	return PveMap.Levels[levelId]
end

function PveMap.GetRegion(regionId)
	for _, region in ipairs(PveMap.Regions) do
		if region.Id == regionId then
			return region
		end
	end
	return nil
end

-- What clearing this stage pays. `firstClear` is the full reward; replaying
-- it pays RepeatShare of each, rounded down but never to nothing.
function PveMap.Rewards(levelId, firstClear)
	local level = PveMap.Levels[levelId]
	if not level then
		return nil
	end
	if firstClear then
		return { Coins = level.Rewards.Coins, Food = level.Rewards.Food, Xp = level.Rewards.Xp }
	end
	local function share(amount, ratio)
		return math.max(1, math.floor(amount * ratio))
	end
	return {
		Coins = share(level.Rewards.Coins, PveMap.RepeatShare.Coins),
		Food = share(level.Rewards.Food, PveMap.RepeatShare.Food),
		Xp = share(level.Rewards.Xp, PveMap.RepeatShare.Xp),
	}
end

-- REWARD NOTES (the reasoning behind the numbers, so a later pass can move
-- them knowingly):
--   Food is the point of the map. Feeding a dragon its ten levels costs 270
--   Food (DragonLevels), and clearing the whole map once gives 326 - about
--   one fighter raised from scratch, which is exactly what the player needs
--   in order to go further along the map.
--   Coins: 7000 for a full clear, near the price of an Electric habitat
--   (1200) plus a farm upgrade, and about an hour and a quarter of what one
--   Adult earns idle. It helps, it doesn't replace the island.
--   XP: 1995 for a full clear, roughly four player levels around level 6-10.
--   A single habitat already gives its price in XP (200 to 2400), so a whole
--   map chapter at 1995 stays in line with what the island pays.

return PveMap
