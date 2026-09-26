-- Reading Config/SkillDefs: the three skills a species brings to a fight, the
-- English line the UI shows for one (built from its numbers, never written by
-- hand), the damage / heal / shield it works out from a dragon's stats, and
-- the rules the whole catalogue must keep (Validate).
--
-- The user's rules for the catalogue, all checked by Validate:
--   * no two species share a skill (sharing all three was already banned and
--     two avoided; as it stands none is shared at all);
--   * every skill carries exactly one element, and a species only brings
--     skills of its own elements - a Common three of its element, a hybrid
--     two of one and one of the other;
--   * two names never mean the same move: no two skills hit the same kind of
--     target with the same set of statuses on the same cooldown, whatever
--     their elements and whatever damage each one does. Damage alone is not
--     a difference - of two skills that only differ there, nobody would ever
--     pick the weaker one (the user's rule, 2026-09-26).
local Config = script.Parent
local DragonDefs = require(Config.DragonDefs)
local DragonRules = require(Config.DragonRules)
local ElementChart = require(Config.ElementChart)
local SkillDefs = require(Config.SkillDefs)
local StatusDefs = require(Config.StatusDefs)

local SkillRules = {}

local TARGET_TEXT = {
	Enemy = "one enemy",
	AllEnemies = "all enemies",
	Self = "itself",
	Ally = "one ally",
	AllAllies = "all allies",
	WeakestAlly = "the ally with the least Health",
}

function SkillRules.Get(skillId)
	return SkillDefs[skillId]
end

-- The element a skill lands with (Config/ElementChart decides what that does).
function SkillRules.Element(skillId)
	local skill = SkillDefs[skillId]
	return skill and skill.Element
end

-- The species' three skill ids (empty while a species has none yet).
function SkillRules.SkillsOf(speciesId)
	local def = DragonDefs[speciesId]
	return (def and def.Skills) or {}
end

local function percent(amount)
	return string.format("%d%%", math.round(amount * 100))
end

local function turns(count)
	return count == 1 and "1 turn" or string.format("%d turns", count)
end

-- The whole skill as the UI shows it: the damage, the statuses it leaves
-- behind (each with what it is worth, from Config/StatusDefs so the wording
-- can never drift from the numbers), then its cooldown.
function SkillRules.Describe(skillId)
	local skill = SkillDefs[skillId]
	if not skill then
		return ""
	end
	local target = TARGET_TEXT[skill.Target] or skill.Target
	local parts = {}
	if skill.Power then
		table.insert(parts, string.format("Deals %s Attack to %s", percent(skill.Power), target))
	end
	for _, statusId in ipairs(skill.Effects or {}) do
		local def = StatusDefs.Get(statusId)
		if def then
			-- Without damage, the first status says who it lands on; "itself" is
			-- already clear from the wording when the skill targets the caster.
			local onWho = (#parts == 0 and skill.Target ~= "Self") and (" on " .. target) or ""
			table.insert(parts, string.format("%s%s (%s)", def.DisplayName, onWho, StatusDefs.Describe(statusId)))
		end
	end
	for _, statusId in ipairs(skill.SelfEffects or {}) do
		local def = StatusDefs.Get(statusId)
		if def then
			table.insert(parts, string.format("%s on itself (%s)", def.DisplayName, StatusDefs.Describe(statusId)))
		end
	end
	local text = table.concat(parts, ". ") .. "."
	if (skill.Cooldown or 0) > 0 then
		text ..= string.format(" Cooldown %s.", turns(skill.Cooldown))
	end
	return text
end

-- What the skill is worth for a dragon with `stats` (DragonRules.Stats):
-- { damage, heal, shield, dotShare }, only the fields it uses. Damage over
-- time has no number here on purpose - it is read off whoever it lands on,
-- so all the UI can say beforehand is the share.
function SkillRules.Amounts(skillId, stats)
	local skill = SkillDefs[skillId]
	if not skill or not stats then
		return {}
	end
	local amounts = {}
	if skill.Power then
		amounts.damage = math.round(stats.Attack * skill.Power)
	end
	local function read(statusId)
		local def = StatusDefs.Get(statusId)
		if not def then
			return
		end
		if def.Kind == "Heal" then
			-- On an ally, its own max Health decides; the caster's is the best
			-- guess the UI has before a fight.
			amounts.heal = math.round(stats.Health * def.Amount)
		elseif def.Kind == "Drain" then
			amounts.heal = math.round(stats.Health * def.Amount)
		elseif def.Kind == "Shield" then
			amounts.shield = math.round(stats.Health * def.Amount)
		elseif def.Kind == "Dot" then
			amounts.dotShare = def.Amount
			amounts.dotTurns = def.Duration
		end
	end
	for _, statusId in ipairs(skill.Effects or {}) do
		read(statusId)
	end
	for _, statusId in ipairs(skill.SelfEffects or {}) do
		read(statusId)
	end
	return amounts
end

-- The catalogue's own rules, for the test that runs after every change:
-- { ok, problems = { "..." }, warnings = { "..." }, covered = n, total = n }.
-- Problems: a species with a number of skills other than three, the same
-- skill twice on one species, an unknown skill id, or two species sharing
-- all three. Warnings: two species sharing two skills (allowed, but the user
-- would rather avoid it).
local VALID_TARGETS = { Enemy = true, AllEnemies = true, Self = true, Ally = true, AllAllies = true, WeakestAlly = true }

-- What makes two skills the same move: the same kind of target, the same set
-- of statuses (the ones it lands and the ones it puts on the caster) and the
-- same cooldown. Damage is deliberately left out - two skills that differ
-- only there give nobody a reason to ever pick the weaker one. A different
-- element is not a difference either; that was already the user's rule.
local function signatureOf(skill)
	local on, self_ = {}, {}
	for _, statusId in ipairs(skill.Effects or {}) do
		table.insert(on, statusId)
	end
	for _, statusId in ipairs(skill.SelfEffects or {}) do
		table.insert(self_, statusId)
	end
	table.sort(on)
	table.sort(self_)
	return table.concat({ skill.Target, table.concat(on, "+"), table.concat(self_, "+"), skill.Cooldown or 0 }, "|")
end

function SkillRules.Validate()
	local problems, warnings = {}, {}
	local withSkills = {}
	local total = 0

	-- The catalogue itself: a typo here would show up as a strange line in the
	-- UI rather than an error, so it is checked field by field.
	local bySignature = {}
	for skillId, skill in pairs(SkillDefs) do
		if not VALID_TARGETS[skill.Target] then
			table.insert(problems, string.format("%s targets %s, which is not a target", skillId, tostring(skill.Target)))
		end
		if not skill.Element or not ElementChart.Beats[skill.Element] then
			table.insert(problems, string.format("%s has no element (or an unknown one: %s)", skillId, tostring(skill.Element)))
		else
			local signature = signatureOf(skill)
			bySignature[signature] = bySignature[signature] or {}
			table.insert(bySignature[signature], skillId)
		end
		if not skill.Power and #(skill.Effects or {}) == 0 and #(skill.SelfEffects or {}) == 0 then
			table.insert(problems, string.format("%s does nothing: no Power, no Effects", skillId))
		end
		for _, statusId in ipairs(skill.Effects or {}) do
			if not StatusDefs.Get(statusId) then
				table.insert(problems, string.format("%s applies %s, which is not in StatusDefs", skillId, tostring(statusId)))
			end
		end
		for _, statusId in ipairs(skill.SelfEffects or {}) do
			local def = StatusDefs.Get(statusId)
			if not def then
				table.insert(problems, string.format("%s puts %s on itself, which is not in StatusDefs", skillId, tostring(statusId)))
			elseif not def.Good then
				table.insert(problems, string.format("%s puts %s on itself, which is not something you want", skillId, statusId))
			end
		end
	end

	for speciesId, def in pairs(DragonDefs) do
		total += 1
		local skills = def.Skills
		if skills then
			table.insert(withSkills, speciesId)
			if #skills ~= 3 then
				table.insert(problems, string.format("%s has %d skills, not 3", speciesId, #skills))
			end
			local seen = {}
			local perElement = {}
			for _, skillId in ipairs(skills) do
				local skill = SkillDefs[skillId]
				if not skill then
					table.insert(problems, string.format("%s uses an unknown skill: %s", speciesId, skillId))
				else
					if seen[skillId] then
						table.insert(problems, string.format("%s has %s twice", speciesId, skillId))
					end
					perElement[skill.Element] = (perElement[skill.Element] or 0) + 1
				end
				seen[skillId] = true
			end
			-- Its skills must be of its own elements, and cover each of them.
			local own = {}
			for _, element in ipairs(DragonRules.Elements(speciesId)) do
				own[element] = true
				if (perElement[element] or 0) < 1 then
					table.insert(problems, string.format("%s brings no %s skill", speciesId, element))
				end
			end
			for element in pairs(perElement) do
				if element and not own[element] then
					table.insert(problems, string.format("%s brings a %s skill, which is not one of its elements", speciesId, element))
				end
			end
		end
	end

	-- Two names, one move.
	for _, ids in pairs(bySignature) do
		if #ids > 1 then
			table.sort(ids)
			table.insert(problems, string.format("%s are the same move under %d names (same target, same statuses, same cooldown)",
				table.concat(ids, ", "), #ids))
		end
	end

	table.sort(withSkills)
	for i = 1, #withSkills - 1 do
		for j = i + 1, #withSkills do
			local a, b = withSkills[i], withSkills[j]
			local shared = {}
			for _, skillId in ipairs(DragonDefs[a].Skills) do
				if table.find(DragonDefs[b].Skills, skillId) then
					table.insert(shared, skillId)
				end
			end
			if #shared >= 2 then
				table.insert(problems, string.format("%s and %s share %d skills (%s)", a, b, #shared, table.concat(shared, ", ")))
			elseif #shared == 1 then
				table.insert(warnings, string.format("%s and %s share %s", a, b, shared[1]))
			end
		end
	end

	return {
		ok = #problems == 0,
		problems = problems,
		warnings = warnings,
		covered = #withSkills,
		total = total,
	}
end

return SkillRules
