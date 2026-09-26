-- Everything a skill can put on a dragon besides damage: the burns, the
-- debuffs, the buffs, the shields, the heals. Each one is a NAMED status with
-- FIXED numbers - a skill only says which it applies, never how much.
--
-- Two reasons for that (the user's, 2026-09-26):
--   * damage over time is read off the VICTIM's own Health, not the
--     attacker's Attack, so a burn is worth the same against anyone;
--   * with the numbers fixed per status, the battle screen can show an icon
--     instead of a line of text, and the screen stops drowning in words.
--
-- It also decides what makes two skills different: same target, same set of
-- statuses and same cooldown means the same skill, whatever damage each
-- does (SkillRules.Validate refuses it).
--
-- Fields:
--   DisplayName  what the tooltip calls it.
--   Kind         "Dot" | "Debuff" | "Buff" | "Shield" | "Heal" | "Drain"
--                | "Stun" | "Taunt" | "Cleanse"
--   Stat         Buff / Debuff only: Attack, Speed or Health.
--   Amount       a share of the dragon it lands on - its max Health for a
--                Dot, a Shield or a Heal, its base stat for a Buff/Debuff.
--                Drain is a share of the CASTER's max Health.
--   Duration     turns it lasts (a Heal, a Drain and a Cleanse are instant).
--   Good         true when having it is good news (drives the icon's colour).
-- Each status is meant to end up with its own icon; Icon is left for that.
local StatusDefs = {}

StatusDefs.Defs = {
	-- Damage over time: a share of the victim's own max Health, each of its turns.
	Singe = { DisplayName = "Singe", Kind = "Dot", Amount = 0.04, Duration = 2 },
	Burn = { DisplayName = "Burn", Kind = "Dot", Amount = 0.1, Duration = 2 },
	Poison = { DisplayName = "Poison", Kind = "Dot", Amount = 0.05, Duration = 4 },
	Bleed = { DisplayName = "Bleed", Kind = "Dot", Amount = 0.18, Duration = 1 },

	-- Debuffs.
	Weaken = { DisplayName = "Weaken", Kind = "Debuff", Stat = "Attack", Amount = 0.15, Duration = 2 },
	Cripple = { DisplayName = "Cripple", Kind = "Debuff", Stat = "Attack", Amount = 0.3, Duration = 2 },
	Slow = { DisplayName = "Slow", Kind = "Debuff", Stat = "Speed", Amount = 0.2, Duration = 2 },
	Root = { DisplayName = "Root", Kind = "Debuff", Stat = "Speed", Amount = 0.4, Duration = 2 },
	Wither = { DisplayName = "Wither", Kind = "Debuff", Stat = "Health", Amount = 0.15, Duration = 3 },
	Stun = { DisplayName = "Stun", Kind = "Stun", Duration = 1 },

	-- Buffs, on the caster or on an ally.
	Focus = { DisplayName = "Focus", Kind = "Buff", Stat = "Attack", Amount = 0.15, Duration = 2, Good = true },
	Rage = { DisplayName = "Rage", Kind = "Buff", Stat = "Attack", Amount = 0.35, Duration = 2, Good = true },
	Quicken = { DisplayName = "Quicken", Kind = "Buff", Stat = "Speed", Amount = 0.2, Duration = 2, Good = true },
	Haste = { DisplayName = "Haste", Kind = "Buff", Stat = "Speed", Amount = 0.4, Duration = 2, Good = true },
	Taunt = { DisplayName = "Taunt", Kind = "Taunt", Duration = 2, Good = true },

	-- Shields absorb a share of the max Health of whoever carries them.
	Guard = { DisplayName = "Guard", Kind = "Shield", Amount = 0.15, Duration = 2, Good = true },
	Barrier = { DisplayName = "Barrier", Kind = "Shield", Amount = 0.35, Duration = 2, Good = true },
	Bulwark = { DisplayName = "Bulwark", Kind = "Shield", Amount = 0.6, Duration = 2, Good = true },

	-- Putting Health back.
	Mend = { DisplayName = "Mend", Kind = "Heal", Amount = 0.2, Good = true },
	Renewal = { DisplayName = "Renewal", Kind = "Heal", Amount = 0.4, Good = true },
	Drain = { DisplayName = "Drain", Kind = "Drain", Amount = 0.12, Good = true },
	Cleanse = { DisplayName = "Cleanse", Kind = "Cleanse", Good = true },
}

function StatusDefs.Get(statusId)
	return StatusDefs.Defs[statusId]
end

-- Is this status something the dragon carrying it wants? (Drain and Cleanse
-- are instant, so nothing carries them.)
function StatusDefs.IsGood(statusId)
	local def = StatusDefs.Defs[statusId]
	return def ~= nil and def.Good == true
end

-- The line a tooltip shows, built from the numbers so the two can never drift.
function StatusDefs.Describe(statusId)
	local def = StatusDefs.Defs[statusId]
	if not def then
		return ""
	end
	local function percent(amount)
		return string.format("%d%%", math.round((amount or 0) * 100))
	end
	local function turns(count)
		return count == 1 and "1 turn" or string.format("%d turns", count)
	end
	if def.Kind == "Dot" then
		return string.format("%s of its max Health a turn, %s", percent(def.Amount), turns(def.Duration))
	elseif def.Kind == "Debuff" then
		return string.format("-%s %s for %s", percent(def.Amount), def.Stat, turns(def.Duration))
	elseif def.Kind == "Buff" then
		return string.format("+%s %s for %s", percent(def.Amount), def.Stat, turns(def.Duration))
	elseif def.Kind == "Shield" then
		return string.format("absorbs %s of its max Health for %s", percent(def.Amount), turns(def.Duration))
	elseif def.Kind == "Heal" then
		return string.format("restores %s of its max Health", percent(def.Amount))
	elseif def.Kind == "Drain" then
		return string.format("the caster takes back %s of its own max Health", percent(def.Amount))
	elseif def.Kind == "Stun" then
		return string.format("skips its next turn (%s)", turns(def.Duration))
	elseif def.Kind == "Taunt" then
		return string.format("draws every single-target attack for %s", turns(def.Duration))
	elseif def.Kind == "Cleanse" then
		return "clears everything bad off it"
	end
	return def.DisplayName
end

return StatusDefs
