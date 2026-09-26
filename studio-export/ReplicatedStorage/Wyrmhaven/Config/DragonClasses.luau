-- The four roles a dragon can have in a fight (every species picks one in
-- DragonDefs). A class sets which of the three combat stats it leans on
-- (Weights, see DragonRules.Stats) and what its skills will be about when the
-- combat step lands: an Attacker hits hard, a Tank keeps itself alive, a
-- Support heals and buffs, a Control debuffs and disrupts. Skills may borrow
-- from another class here and there, on purpose.
--
-- Weights multiply the base stats (GameConstants.DragonBaseStats) and average
-- out to about 1 per class, so no class is simply stronger than another:
-- Attack for the Attacker, Health for the Tank, Speed for the Support and the
-- Control.
local DragonClasses = {}

DragonClasses.Order = { "Attacker", "Tank", "Support", "Control" }

DragonClasses.Defs = {
	Attacker = {
		DisplayName = "Attacker",
		Description = "Hits hard, takes hits badly.",
		Color = Color3.fromRGB(214, 88, 76),
		Weights = { Attack = 1.1, Health = 0.9, Speed = 1 },
	},
	Tank = {
		DisplayName = "Tank",
		Description = "Soaks damage and holds the front.",
		Color = Color3.fromRGB(96, 150, 220),
		-- A turn spent shielding is a turn not spent killing, so a Tank needs
		-- enough Attack to be worth its slot in a short fight.
		Weights = { Attack = 1, Health = 1.5, Speed = 0.85 },
	},
	Support = {
		DisplayName = "Support",
		Description = "Heals and buffs its team, early.",
		Color = Color3.fromRGB(110, 190, 110),
		-- Fights are short, so a Support that only heals never pays for its
		-- slot: it needs to hurt a little too.
		Weights = { Attack = 0.95, Health = 1, Speed = 1.2 },
	},
	Control = {
		DisplayName = "Control",
		Description = "Debuffs and disrupts before the enemy acts.",
		Color = Color3.fromRGB(170, 124, 214),
		Weights = { Attack = 0.95, Health = 0.95, Speed = 1.2 },
	},
}

function DragonClasses.Get(classId)
	return DragonClasses.Defs[classId] or DragonClasses.Defs.Attacker
end

return DragonClasses
