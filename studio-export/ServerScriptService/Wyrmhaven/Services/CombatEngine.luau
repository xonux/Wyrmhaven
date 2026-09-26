-- The fight itself: 3 dragons against 3, turn based, resolved in one go on
-- the server. Nothing here draws anything - Resolve returns the winner and a
-- full log of what happened, which a battle screen can replay later and which
-- makes the whole thing testable by simulation.
--
-- A round gives every living dragon one turn, fastest first (Speed is
-- re-read each round, so slows and hastes change the order). On its turn a
-- dragon:
--   1. takes its burn damage, then its cooldowns tick down;
--   2. skips everything if it is stunned;
--   3. otherwise picks a skill (options.choose, or the default policy below)
--      and resolves it;
--   4. its buffs, debuffs, burns and shield lose a turn.
-- The fight ends when a team is wiped out, or at MAX_ROUNDS - then the team
-- with the most Health left as a share of its total wins.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local GameConstants = require(Config.GameConstants)
local DragonDefs = require(Config.DragonDefs)
local DragonRules = require(Config.DragonRules)
local ElementChart = require(Config.ElementChart)
local SkillDefs = require(Config.SkillDefs)
local StatusDefs = require(Config.StatusDefs)
local SkillRules = require(Config.SkillRules)

local CombatEngine = {}

CombatEngine.MaxRounds = 30
CombatEngine.TeamSize = 3

-- A stat can never be pushed below this share of its base by debuffs.
local MIN_STAT_MULTIPLIER = 0.2

------------------------------------------------------------------ fighters

-- One dragon ready to fight. `source` is anything the caller wants to find
-- it again by (a dragon id, an enemy definition...).
function CombatEngine.Fighter(speciesId, level, name, source)
	local def = DragonDefs[speciesId]
	assert(def, "Unknown species: " .. tostring(speciesId))
	local stats = DragonRules.Stats(speciesId, level or 1)
	return {
		source = source,
		name = name or def.DisplayName,
		species = speciesId,
		level = level or 1,
		class = DragonRules.Class(speciesId),
		elements = DragonRules.Elements(speciesId),
		stats = stats,
		skills = SkillRules.SkillsOf(speciesId),
	}
end

-- The live state of a fighter inside a running battle.
local function spawn(entry, team, slot)
	return {
		source = entry.source,
		name = entry.name,
		species = entry.species,
		level = entry.level,
		class = entry.class,
		elements = entry.elements, -- what a skill's own element is measured against
		team = team,
		slot = slot,
		key = team .. slot, -- short id used in the log
		baseAttack = entry.stats.Attack,
		baseSpeed = entry.stats.Speed,
		maxHealth = entry.stats.Health,
		health = entry.stats.Health,
		shield = 0,
		shieldTurns = 0,
		skills = entry.skills,
		cooldowns = {}, -- [skillId] = turns left before it can be used again
		statuses = {}, -- buffs, debuffs and burns, each with `turns` left
		stunTurns = 0,
		alive = true,
	}
end

------------------------------------------------------------------ stats

-- Buffs and debuffs stack by adding up, and never take a stat below
-- MIN_STAT_MULTIPLIER of its base.
local function multiplier(fighter, stat)
	local value = 1
	for _, status in ipairs(fighter.statuses) do
		if status.stat == stat then
			value += status.kind == "Buff" and status.amount or -status.amount
		end
	end
	return math.max(MIN_STAT_MULTIPLIER, value)
end

local function attackOf(fighter)
	return fighter.baseAttack * multiplier(fighter, "Attack")
end

local function speedOf(fighter)
	return fighter.baseSpeed * multiplier(fighter, "Speed")
end

------------------------------------------------------------------ battle state

local Battle = {}
Battle.__index = Battle

-- Team spirit (GameConstants.TeamClassBonus): a team gets more Attack and
-- Health for every class beyond the first it brings. It is what pays for a
-- Tank's or a Support's slot - see the constant for why.
function Battle:applyTeamBonus(team)
	local classes, count = {}, 0
	for _, fighter in ipairs(self.fighters) do
		if fighter.team == team and fighter.class and not classes[fighter.class] then
			classes[fighter.class] = true
			count += 1
		end
	end
	local bonus = 1 + GameConstants.TeamClassBonus * math.max(0, count - 1)
	for _, fighter in ipairs(self.fighters) do
		if fighter.team == team then
			fighter.baseAttack *= bonus
			fighter.maxHealth *= bonus
			fighter.health = fighter.maxHealth
			fighter.teamBonus = bonus
		end
	end
	self:record({ t = "teamBonus", team = team, classes = count, bonus = math.round((bonus - 1) * 100) })
end

function Battle.new(teamA, teamB, options)
	local self = setmetatable({}, Battle)
	options = options or {}
	self.random = Random.new(options.seed or os.time())
	self.choose = options.choose -- optional: picks a skill for a fighter
	self.log = {}
	self.round = 0
	self.fighters = {}
	for slot, entry in ipairs(teamA) do
		table.insert(self.fighters, spawn(entry, "A", slot))
	end
	for slot, entry in ipairs(teamB) do
		table.insert(self.fighters, spawn(entry, "B", slot))
	end
	self:applyTeamBonus("A")
	self:applyTeamBonus("B")
	return self
end

function Battle:record(event)
	event.round = self.round
	table.insert(self.log, event)
end

function Battle:living(team)
	local list = {}
	for _, fighter in ipairs(self.fighters) do
		if fighter.alive and (team == nil or fighter.team == team) then
			table.insert(list, fighter)
		end
	end
	return list
end

local function other(team)
	return team == "A" and "B" or "A"
end

-- The one with the least Health left, as a share of its own maximum.
local function weakest(list)
	local best
	for _, fighter in ipairs(list) do
		if not best or fighter.health / fighter.maxHealth < best.health / best.maxHealth then
			best = fighter
		end
	end
	return best
end

local function hasStatus(fighter, kind)
	for _, status in ipairs(fighter.statuses) do
		if status.kind == kind then
			return true
		end
	end
	return false
end

function Battle:fighterByKey(key)
	for _, fighter in ipairs(self.fighters) do
		if fighter.key == key then
			return fighter
		end
	end
	return nil
end

-- Who a skill lands on, from its Target. `preferredKey` is the target the
-- chooser asked for (the AI, or the player on their own turn); it only
-- applies to skills that hit one dragon, and a taunt still overrides it.
function Battle:targetsFor(actor, skill, preferredKey)
	local allies, enemies = self:living(actor.team), self:living(other(actor.team))
	if skill.Target == "Self" then
		return { actor }
	elseif skill.Target == "AllEnemies" then
		return enemies
	elseif skill.Target == "AllAllies" then
		return allies
	elseif skill.Target == "Ally" or skill.Target == "WeakestAlly" then
		if preferredKey and skill.Target == "Ally" then
			local chosen = self:fighterByKey(preferredKey)
			if chosen and chosen.alive and chosen.team == actor.team then
				return { chosen }
			end
		end
		local target = weakest(allies)
		return target and { target } or {}
	end
	-- "Enemy": a dragon that is taunting takes the hit, whoever it was meant
	-- for - that is what makes a tank worth a slot. Otherwise the one closest
	-- to going down.
	for _, enemy in ipairs(enemies) do
		if hasStatus(enemy, "Taunt") then
			return { enemy }
		end
	end
	if preferredKey then
		local chosen = self:fighterByKey(preferredKey)
		if chosen and chosen.alive and chosen.team ~= actor.team then
			return { chosen }
		end
	end
	local target = weakest(enemies)
	return target and { target } or {}
end

-- What a skill takes off (or puts back on) that dragon THE MOMENT it lands,
-- for the bar's preview: the hit itself, shields counted, never more than the
-- dragon has. A burn is deliberately left out - it is dealt later, turn by
-- turn, and counting it made the bar promise a kill the hit did not deliver.
function Battle:previewOn(actor, skill, target)
	local factor = ElementChart.Factor(skill.Element, target.elements)
	local damage = 0
	if skill.Power then
		local raw = attackOf(actor) * skill.Power * factor
		damage = math.min(math.max(0, raw - target.shield), target.health)
	end
	local heal = 0
	for _, statusId in ipairs(skill.Effects or {}) do
		local def = StatusDefs.Get(statusId)
		if def and def.Kind == "Heal" then
			heal += math.min(target.maxHealth * def.Amount, target.maxHealth - target.health)
		end
	end
	return math.round(damage), math.round(heal), factor
end

-- What this dragon could do right now: its ready skills and, for the ones
-- that hit a single dragon, who they may be aimed at. The battle screen will
-- build the player's buttons from this.
function Battle:availableActions(fighter)
	local actions = {}
	for _, skillId in ipairs(fighter.skills) do
		local skill = SkillDefs[skillId]
		if skill then
			-- Who it may be aimed at, what the element does to each of them and
			-- what it would cost them, so the screen can show it before the
			-- player commits.
			local choices = {}
			if skill.Target == "Enemy" or skill.Target == "Ally" then
				local candidates = self:living(skill.Target == "Enemy" and other(fighter.team) or fighter.team)
				if skill.Target == "Enemy" then
					-- A taunting enemy takes every single-target hit: it is then the
					-- only one that can be aimed at, and the screen greys the rest.
					for _, candidate in ipairs(candidates) do
						if hasStatus(candidate, "Taunt") then
							candidates = { candidate }
							break
						end
					end
				end
				for _, candidate in ipairs(candidates) do
					local damage, heal, factor = self:previewOn(fighter, skill, candidate)
					table.insert(choices, {
						key = candidate.key,
						factor = factor,
						effectiveness = ElementChart.Label(factor),
						damage = damage > 0 and damage or nil,
						heal = heal > 0 and heal or nil,
					})
				end
			else
				-- Everything else lands on a set the screen works out itself; it
				-- still needs the numbers for each of them.
				local wanted = skill.Target == "AllEnemies" and self:living(other(fighter.team))
					or skill.Target == "Self" and { fighter }
					or self:living(fighter.team)
				for _, candidate in ipairs(wanted) do
					local damage, heal, factor = self:previewOn(fighter, skill, candidate)
					if damage > 0 or heal > 0 then
						table.insert(choices, {
							key = candidate.key,
							factor = factor,
							effectiveness = skill.Power and ElementChart.Label(factor) or nil,
							damage = damage > 0 and damage or nil,
							heal = heal > 0 and heal or nil,
							previewOnly = true, -- not a choice, just what it would do
						})
					end
				end
			end
			table.insert(actions, {
				skill = skillId,
				name = skill.DisplayName,
				element = skill.Element,
				target = skill.Target, -- lets the screen light up who it would land on
				cooldown = skill.Cooldown or 0,
				ready = fighter.cooldowns[skillId] == nil,
				turnsLeft = fighter.cooldowns[skillId],
				targets = choices,
			})
		end
	end
	return actions
end

------------------------------------------------------------------ effects

-- `factor` is the element multiplier that was already applied to `amount`
-- (ElementChart): the log carries it so the battle screen can say a hit was
-- strong or resisted.
function Battle:damage(target, amount, source, factor)
	if amount <= 0 or not target.alive then
		return
	end
	local absorbed = math.min(target.shield, amount)
	target.shield -= absorbed
	if target.shield <= 0 then
		target.shieldTurns = 0
	end
	local taken = amount - absorbed
	target.health = math.max(0, target.health - taken)
	self:record({
		t = "damage",
		target = target.key,
		name = target.name,
		amount = math.round(taken),
		absorbed = math.round(absorbed),
		health = math.round(target.health),
		source = source,
		factor = (factor and math.abs(factor - 1) > 0.001) and factor or nil,
		effectiveness = factor and ElementChart.Label(factor) or nil,
	})
	if target.health <= 0 then
		target.alive = false
		target.statuses = {}
		target.shield, target.shieldTurns, target.stunTurns = 0, 0, 0
		self:record({ t = "death", target = target.key, name = target.name })
	end
end

function Battle:heal(target, amount)
	if not target.alive or amount <= 0 then
		return
	end
	local before = target.health
	target.health = math.min(target.maxHealth, target.health + amount)
	-- Nothing to say when it was already at full Health.
	if target.health > before then
		self:record({ t = "heal", target = target.key, name = target.name, amount = math.round(target.health - before), health = math.round(target.health) })
	end
end

-- Buffs, debuffs and damage over time all live in `statuses`; the same one
-- from the same dragon refreshes instead of stacking forever. Returns the
-- live status and whether it is a new one (damage over time carries
-- `damage`, a buff carries `amount`).
function Battle:addStatus(target, status)
	for _, existing in ipairs(target.statuses) do
		if existing.id == status.id and existing.sourceKey == status.sourceKey then
			if status.amount and existing.amount then
				existing.amount = math.max(existing.amount, status.amount)
			end
			if status.damage and existing.damage then
				existing.damage = math.max(existing.damage, status.damage)
			end
			existing.turns = math.max(existing.turns, status.turns)
			return existing, false
		end
	end
	table.insert(target.statuses, status)
	return status, true
end

-- Puts one status (Config/StatusDefs) on `landsOn`. Every number comes from
-- the status itself, and every share is read off the dragon it lands on -
-- damage over time included, which is what makes a burn worth the same
-- whoever cast it. The element multiplier is not applied here: it belongs to
-- the blow, not to what the blow leaves behind.
function Battle:applyStatus(actor, landsOn, statusId, skillId)
	local def = StatusDefs.Get(statusId)
	if not def or not landsOn.alive then
		return
	end
	local turns = def.Duration or 1

	if def.Kind == "Heal" then
		self:heal(landsOn, landsOn.maxHealth * def.Amount)
	elseif def.Kind == "Drain" then
		-- The caster takes Health back, whoever it hit.
		self:heal(actor, actor.maxHealth * def.Amount)
	elseif def.Kind == "Shield" then
		-- One shield at a time. A dragon still carrying one cannot brace again:
		-- without that, a skill with no cooldown that shields its own caster
		-- puts a fresh shield up before the last one has been used, and two
		-- such dragons lock a fight until the round limit (seen between two
		-- Earth dragons, each resisting the other and absorbing every hit).
		if landsOn.shield > 0 then
			return
		end
		local amount = landsOn.maxHealth * def.Amount
		landsOn.shield = amount
		landsOn.shieldTurns = turns
		self:record({ t = "shield", target = landsOn.key, name = landsOn.name, status = statusId,
			amount = math.round(amount), turns = landsOn.shieldTurns })
	elseif def.Kind == "Dot" then
		-- Locked in when it lands, off the victim's own Health.
		self:addStatus(landsOn, {
			id = statusId,
			kind = "Dot",
			damage = landsOn.maxHealth * def.Amount,
			turns = turns,
			sourceKey = actor.key,
		})
		self:record({ t = "status", target = landsOn.key, name = landsOn.name, status = statusId, kind = "Dot", turns = turns })
	elseif def.Kind == "Buff" or def.Kind == "Debuff" then
		if def.Stat == "Health" then
			-- Room for more Health rather than a multiplier: the bonus is handed
			-- back when the status ends. Only a brand new one adds room, so
			-- recasting it can never pile up Health for good.
			local status, isNew = self:addStatus(landsOn, { id = statusId, kind = def.Kind, stat = "Health",
				amount = def.Amount, bonus = 0, turns = turns, sourceKey = actor.key })
			if isNew then
				status.bonus = landsOn.maxHealth * def.Amount * (def.Kind == "Buff" and 1 or -1)
				landsOn.maxHealth += status.bonus
				landsOn.health = math.clamp(landsOn.health + math.max(0, status.bonus), 0, landsOn.maxHealth)
			end
		else
			self:addStatus(landsOn, { id = statusId, kind = def.Kind, stat = def.Stat, amount = def.Amount,
				turns = turns, sourceKey = actor.key })
		end
		self:record({ t = "status", target = landsOn.key, name = landsOn.name, status = statusId,
			kind = def.Kind, stat = def.Stat, amount = def.Amount, turns = turns })
	elseif def.Kind == "Stun" then
		landsOn.stunTurns = math.max(landsOn.stunTurns, turns)
		self:record({ t = "status", target = landsOn.key, name = landsOn.name, status = statusId, kind = "Stun", turns = landsOn.stunTurns })
	elseif def.Kind == "Taunt" then
		self:addStatus(landsOn, { id = statusId, kind = "Taunt", turns = turns, sourceKey = actor.key })
		self:record({ t = "status", target = landsOn.key, name = landsOn.name, status = statusId, kind = "Taunt", turns = turns })
	elseif def.Kind == "Cleanse" then
		-- Everything bad, in one go.
		local removed = 0
		for index = #landsOn.statuses, 1, -1 do
			local status = landsOn.statuses[index]
			if status.kind == "Debuff" or status.kind == "Dot" then
				if status.stat == "Health" and status.bonus then
					landsOn.maxHealth -= status.bonus
					landsOn.health = math.min(landsOn.health, landsOn.maxHealth)
				end
				table.remove(landsOn.statuses, index)
				removed += 1
			end
		end
		if landsOn.stunTurns > 0 then
			landsOn.stunTurns = 0
			removed += 1
		end
		self:record({ t = "cleanse", target = landsOn.key, name = landsOn.name, removed = removed })
	end
end

------------------------------------------------------------------ turns

-- Burn damage, then cooldowns: both happen before the dragon may act.
function Battle:startTurn(fighter)
	for _, status in ipairs(fighter.statuses) do
		if status.kind == "Dot" then
			self:record({ t = "burn", target = fighter.key, name = fighter.name, status = status.id, amount = math.round(status.damage) })
			self:damage(fighter, status.damage, status.id or "Dot")
		end
	end
	for skillId, turns in pairs(fighter.cooldowns) do
		if turns <= 1 then
			fighter.cooldowns[skillId] = nil
		else
			fighter.cooldowns[skillId] = turns - 1
		end
	end
end

-- Everything that was put on this dragon loses a turn at the end of its own.
function Battle:endTurn(fighter)
	for index = #fighter.statuses, 1, -1 do
		local status = fighter.statuses[index]
		status.turns -= 1
		if status.turns <= 0 then
			if status.stat == "Health" and status.bonus then
				fighter.maxHealth -= status.bonus
				fighter.health = math.min(fighter.health, fighter.maxHealth)
			end
			table.remove(fighter.statuses, index)
		end
	end
	if fighter.shieldTurns > 0 then
		fighter.shieldTurns -= 1
		if fighter.shieldTurns <= 0 then
			fighter.shield = 0
		end
	end
end

-- Default policy, good enough to test the engine: heal when someone is hurt,
-- otherwise the readiest heavy skill, otherwise the basic attack. The real
-- opponent AI replaces this through options.choose.
function Battle:defaultChoice(fighter)
	local ready, best = {}, nil
	for _, skillId in ipairs(fighter.skills) do
		if not fighter.cooldowns[skillId] then
			table.insert(ready, skillId)
		end
	end
	if #ready == 0 then
		return nil
	end

	local hurt = false
	for _, ally in ipairs(self:living(fighter.team)) do
		if ally.health / ally.maxHealth <= 0.6 then
			hurt = true
			break
		end
	end
	for _, skillId in ipairs(ready) do
		local skill = SkillDefs[skillId]
		local heals = false
		for _, statusId in ipairs(skill.Effects or {}) do
			local def = StatusDefs.Get(statusId)
			if def and def.Kind == "Heal" then
				heals = true
			end
		end
		if heals then
			-- A heal is worth a turn only when someone needs it; otherwise it
			-- is skipped entirely rather than wasted at full Health.
			if hurt then
				return skillId
			end
		elseif not best or (skill.Cooldown or 0) > (SkillDefs[best].Cooldown or 0) then
			best = skillId
		end
	end
	return best or ready[1]
end

function Battle:takeTurn(fighter)
	self:startTurn(fighter)
	if not fighter.alive then
		return
	end
	if fighter.stunTurns > 0 then
		fighter.stunTurns -= 1
		self:record({ t = "stunned", actor = fighter.key, name = fighter.name })
		self:endTurn(fighter)
		return
	end

	-- The chooser may also name a target; without one the skill picks its own.
	local skillId, targetKey
	if self.choose then
		skillId, targetKey = self.choose(fighter, self)
	end
	skillId = skillId or self:defaultChoice(fighter)
	local skill = skillId and SkillDefs[skillId]
	if not skill then
		self:record({ t = "pass", actor = fighter.key, name = fighter.name })
		self:endTurn(fighter)
		return
	end

	local targets = self:targetsFor(fighter, skill, targetKey)
	local keys = {}
	for _, target in ipairs(targets) do
		table.insert(keys, target.key)
	end
	self:record({ t = "skill", actor = fighter.key, name = fighter.name, skill = skillId, skillName = skill.DisplayName, targets = keys })

	if (skill.Cooldown or 0) > 0 then
		-- +1: it also ticks down at the start of this dragon's next turn.
		fighter.cooldowns[skillId] = skill.Cooldown + 1
	end

	for _, target in ipairs(targets) do
		-- Each target answers to the skill's element on its own (a hybrid on
		-- both of its halves).
		local factor = ElementChart.Factor(skill.Element, target.elements)
		if skill.Power then
			self:damage(target, attackOf(fighter) * skill.Power * factor, skillId, factor)
		end
		for _, statusId in ipairs(skill.Effects or {}) do
			self:applyStatus(fighter, target, statusId, skillId)
		end
	end
	-- What the caster does to itself happens once, however many it hit.
	for _, statusId in ipairs(skill.SelfEffects or {}) do
		self:applyStatus(fighter, fighter, statusId, skillId)
	end
	self:endTurn(fighter)
end

-- Fastest first; a tie goes to team A's dragon, then to the lower slot, so a
-- battle always plays out the same way from the same seed.
function Battle:order()
	local list = self:living()
	table.sort(list, function(a, b)
		local speedA, speedB = speedOf(a), speedOf(b)
		if math.abs(speedA - speedB) > 0.001 then
			return speedA > speedB
		end
		if a.team ~= b.team then
			return a.team < b.team
		end
		return a.slot < b.slot
	end)
	return list
end

function Battle:teamHealthShare(team)
	local current, total = 0, 0
	for _, fighter in ipairs(self.fighters) do
		if fighter.team == team then
			current += math.max(0, fighter.health)
			total += fighter.maxHealth
		end
	end
	return total > 0 and current / total or 0
end

-- The dragons due to act, starting with the one acting right now: the rest
-- of this round, then the start of the next one as the speeds stand. The
-- battle screen shows the first few, the current one leftmost.
function Battle:upcoming(count)
	local list = {}
	for index = math.max(1, self.queueIndex or 1), #(self.queue or {}) do
		local fighter = self.queue[index]
		if fighter.alive and #list < count then
			table.insert(list, fighter.key)
		end
	end
	for _, fighter in ipairs(self:order()) do
		if #list >= count then
			break
		end
		table.insert(list, fighter.key)
	end
	return list
end

function Battle:run()
	while self.round < CombatEngine.MaxRounds do
		self.round += 1
		self:record({ t = "round", round = self.round })
		-- Kept so `upcoming` can say who is due after the dragon acting now.
		self.queue = self:order()
		self.queueIndex = 0
		for _, fighter in ipairs(self.queue) do
			self.queueIndex += 1
			if fighter.alive then
				self:takeTurn(fighter)
				if #self:living("A") == 0 or #self:living("B") == 0 then
					break
				end
			end
		end
		if #self:living("A") == 0 or #self:living("B") == 0 then
			break
		end
	end

	local aliveA, aliveB = #self:living("A"), #self:living("B")
	local winner
	if aliveA > 0 and aliveB == 0 then
		winner = "A"
	elseif aliveB > 0 and aliveA == 0 then
		winner = "B"
	else
		-- Time ran out: whoever is in better shape takes it.
		local shareA, shareB = self:teamHealthShare("A"), self:teamHealthShare("B")
		winner = math.abs(shareA - shareB) < 0.01 and "Draw" or (shareA > shareB and "A" or "B")
	end
	self:record({ t = "end", winner = winner, rounds = self.round })

	local survivors = {}
	for _, fighter in ipairs(self.fighters) do
		table.insert(survivors, {
			key = fighter.key,
			name = fighter.name,
			species = fighter.species,
			team = fighter.team,
			source = fighter.source,
			alive = fighter.alive,
			health = math.round(fighter.health),
			maxHealth = math.round(fighter.maxHealth),
		})
	end
	return {
		winner = winner,
		rounds = self.round,
		timedOut = aliveA > 0 and aliveB > 0,
		fighters = survivors,
		log = self.log,
	}
end

------------------------------------------------------------------ public

-- teamA / teamB: lists of up to CombatEngine.TeamSize fighters
-- (CombatEngine.Fighter). options: seed (same seed = same fight), choose
-- (skill picker, for the opponent AI).
function CombatEngine.Resolve(teamA, teamB, options)
	assert(#teamA > 0 and #teamB > 0, "Both teams need at least one dragon")
	assert(#teamA <= CombatEngine.TeamSize and #teamB <= CombatEngine.TeamSize, "A team holds at most " .. CombatEngine.TeamSize .. " dragons")
	return Battle.new(teamA, teamB, options):run()
end

-- The log as lines of text, for tests and for reading a fight in the output
-- window.
function CombatEngine.FormatLog(result)
	local lines = {}
	for _, event in ipairs(result.log) do
		if event.t == "teamBonus" then
			table.insert(lines, string.format("Team %s brings %d %s: +%d%% Attack and Health", event.team, event.classes,
				event.classes == 1 and "class" or "classes", event.bonus))
		elseif event.t == "round" then
			table.insert(lines, string.format("-- Round %d", event.round))
		elseif event.t == "skill" then
			table.insert(lines, string.format("%s (%s) uses %s on %s", event.name, event.actor, event.skillName, table.concat(event.targets, ", ")))
		elseif event.t == "damage" then
			table.insert(lines, string.format("   %s takes %d%s%s, %d Health left", event.name, event.amount,
				event.effectiveness and (" [" .. event.effectiveness .. "]") or "",
				event.absorbed > 0 and string.format(" (%d absorbed)", event.absorbed) or "", event.health))
		elseif event.t == "heal" then
			table.insert(lines, string.format("   %s heals %d, now %d", event.name, event.amount, event.health))
		elseif event.t == "shield" then
			table.insert(lines, string.format("   %s gets a %d shield for %d turns", event.name, event.amount, event.turns))
		elseif event.t == "status" then
			table.insert(lines, string.format("   %s: %s for %d turns", event.name, event.status or event.kind, event.turns))
		elseif event.t == "burn" then
			table.insert(lines, string.format("   %s takes %d from %s", event.name, event.amount, event.status or "a wound"))
		elseif event.t == "cleanse" then
			table.insert(lines, string.format("   %s shakes off %d effect(s)", event.name, event.removed))
		elseif event.t == "stunned" then
			table.insert(lines, string.format("%s (%s) is stunned and skips its turn", event.name, event.actor))
		elseif event.t == "pass" then
			table.insert(lines, string.format("%s (%s) has nothing ready", event.name, event.actor))
		elseif event.t == "death" then
			table.insert(lines, string.format("   %s goes down", event.name))
		elseif event.t == "end" then
			table.insert(lines, string.format("== %s wins after %d rounds", event.winner, event.rounds))
		end
	end
	return table.concat(lines, "\n")
end

return CombatEngine
