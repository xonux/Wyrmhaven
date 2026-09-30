-- How the other side plays. `CombatAI.Policy(difficulty)` returns a function
-- for CombatEngine.Resolve's `options.choose`: it is handed a dragon and the
-- running battle, and answers which skill it uses and on whom. The player's
-- own turns will come through the same door once the battle screen asks them.
--
-- Rather than a list of rules ("heal below 40%, then taunt, then..."), every
-- skill is priced in damage: what it takes off an enemy, what a heal puts
-- back, what a stolen turn was worth. The AI then plays the dearest one. A
-- rule list kept spending turns on taunts and buffs that were worth less than
-- simply hitting; pricing them side by side fixes that.
--
--   Easy    picks at random among what is ready.
--   Normal  prices its options, but ignores shields and does not count a
--           kill as special - it plays well without reading the fight.
--   Hard    prices them exactly: it sees shields, hunts finishing blows and
--           never overkills.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local ElementChart = require(Config.ElementChart)
local SkillDefs = require(Config.SkillDefs)
local StatusDefs = require(Config.StatusDefs)

local CombatAI = {}

CombatAI.Difficulties = { "Easy", "Normal", "Hard" }

-- How much a point of healing, of shield, of stolen turn... is worth against
-- a point of damage. Tuned so the AI beats a plain "always hit hardest".
local WEIGHTS = {
	heal = 1,
	shield = 0.8,
	burn = 0.9, -- per point of Health a damage-over-time will take off
	attackSwing = 0.45, -- per point of Attack a buff or debuff moves, per turn
	speedSwing = 0.12,
	stun = 1, -- a stolen turn is worth that dragon's Attack
	taunt = 0.55, -- a hit taken for someone else
	cleanse = 0.25, -- per debuff lifted, as a share of max Health
	guard = 0.5, -- per point of damage a defence (Thorns, Evade, Immune...) is expected to save or send back
}

-- How much of each stolen turn a control is worth: a Freeze can be thawed by
-- Fire and a Sleep breaks on the first hit, so neither is sure to last.
local CONTROL_WORTH = { Stun = 1, Freeze = 0.85, Sleep = 0.5 }

local TUNING = {
	Easy = { random = true },
	Normal = { seesShields = false, killBonus = 0, noise = 0.15 },
	Hard = { seesShields = true, killBonus = 1.5, noise = 0 },
}

local function healthShare(fighter)
	return fighter.health / fighter.maxHealth
end

local function statusCount(fighter, kind, stat)
	local count = 0
	for _, status in ipairs(fighter.statuses) do
		if status.kind == kind and (not stat or status.stat == stat) then
			count += 1
		end
	end
	return count
end

local function sumAttack(list)
	local total = 0
	for _, fighter in ipairs(list) do
		total += fighter.baseAttack
	end
	return total
end

-- What a skill is worth this turn, and the dragon to aim it at.
local function price(skillId, fighter, battle, allies, enemies, tuning)
	local skill = SkillDefs[skillId]
	local attack = fighter.baseAttack
	local value, targetKey = 0, nil

	-- Damage first: it also decides who a single-target skill goes to. The
	-- element multiplier is part of the price, which is what makes the AI aim
	-- a skill at the dragon it is strong against.
	if skill.Power then
		local raw = attack * skill.Power
		if skill.Target == "AllEnemies" then
			for _, enemy in ipairs(enemies) do
				local hit = raw * ElementChart.Factor(skill.Element, enemy.elements)
				local dealt = tuning.seesShields and math.max(0, hit - enemy.shield) or hit
				dealt = math.min(dealt, enemy.health)
				value += dealt
				if dealt >= enemy.health then
					value += enemy.baseAttack * tuning.killBonus
				end
			end
		else
			local best, bestValue = nil, -1
			for _, enemy in ipairs(enemies) do
				local hit = raw * ElementChart.Factor(skill.Element, enemy.elements)
				local dealt = tuning.seesShields and math.max(0, hit - enemy.shield) or hit
				dealt = math.min(dealt, enemy.health)
				local score = dealt
				if dealt >= enemy.health then
					score += enemy.baseAttack * tuning.killBonus
				end
				if score > bestValue then
					best, bestValue = enemy, score
				end
			end
			if best then
				value += bestValue
				targetKey = best.key
			end
		end
	end

	-- Then everything else the skill does.
	local ally = allies[1]
	local hurt = ally
	for _, other in ipairs(allies) do
		if healthShare(other) < healthShare(hurt) then
			hurt = other
		end
	end
	-- One status, priced from Config/StatusDefs. `onSelf` is true for the ones
	-- a skill puts on its caster (SelfEffects) - those never land on a target.
	local function priceStatus(statusId, onSelf)
		local def = StatusDefs.Get(statusId)
		if not def then
			return
		end
		local duration = def.Duration or 1
		-- Who a good status lands on (for the defences below).
		local receivers = onSelf and { fighter }
			or (skill.Target == "AllAllies" and allies)
			or { skill.Target == "Self" and fighter or hurt }
		-- What the enemy side hits for in a turn, split over our dragons.
		local incoming = sumAttack(enemies) / math.max(1, #allies)
		local share = skill.Target == "AllEnemies" and 1 or 1 / math.max(1, #enemies)
		if def.Kind == "Heal" then
			local receivers = onSelf and { fighter }
				or (skill.Target == "AllAllies" and allies)
				or { skill.Target == "Self" and fighter or hurt }
			for _, receiver in ipairs(receivers) do
				-- Healing a dragon that is already full is worth nothing.
				value += math.min(receiver.maxHealth * def.Amount, receiver.maxHealth - receiver.health) * WEIGHTS.heal
			end
			if not onSelf and (skill.Target == "Ally" or skill.Target == "WeakestAlly") then
				targetKey = hurt.key
			end
		elseif def.Kind == "Drain" then
			-- Always back into the caster, whoever the skill hit.
			value += math.min(fighter.maxHealth * def.Amount, fighter.maxHealth - fighter.health) * WEIGHTS.heal
		elseif def.Kind == "Shield" then
			-- Sized on whoever carries it, so price it on them. A dragon that
			-- still has a shield up cannot take another (CombatEngine), so that
			-- one is worth nothing.
			local receivers = onSelf and { fighter }
				or (skill.Target == "AllAllies" and allies)
				or { skill.Target == "Self" and fighter or hurt }
			for _, receiver in ipairs(receivers) do
				if receiver.shield <= 0 then
					value += receiver.maxHealth * def.Amount * WEIGHTS.shield
				end
			end
		elseif def.Kind == "Dot" then
			-- A share of the VICTIM's own Health each turn: worth more against a
			-- big dragon, and no element multiplier to account for. Never more
			-- than what it has left.
			local victims = skill.Target == "AllEnemies" and enemies
				or { (targetKey and battle:fighterByKey(targetKey)) or enemies[1] }
			for _, victim in ipairs(victims) do
				if victim then
					value += math.min(victim.maxHealth * def.Amount * duration, victim.health) * WEIGHTS.burn
				end
			end
		elseif def.Kind == "Buff" and def.Stat == "Attack" then
			local receivers = (not onSelf and skill.Target == "AllAllies") and allies or { fighter }
			-- Stacking the same buff again does nothing.
			local already = 0
			for _, receiver in ipairs(receivers) do
				already += statusCount(receiver, "Buff", "Attack") > 0 and 1 or 0
			end
			if already < #receivers then
				value += sumAttack(receivers) * def.Amount * duration * WEIGHTS.attackSwing
			end
		elseif def.Kind == "Debuff" and def.Stat == "Attack" then
			value += sumAttack(enemies) * def.Amount * duration * WEIGHTS.attackSwing
				* (skill.Target == "AllEnemies" and 1 or 1 / math.max(1, #enemies))
		elseif def.Kind == "Debuff" and def.Stat == "Health" then
			-- Room taken away is Health taken away, near enough.
			local victims = skill.Target == "AllEnemies" and enemies
				or { (targetKey and battle:fighterByKey(targetKey)) or enemies[1] }
			for _, victim in ipairs(victims) do
				if victim then
					value += victim.maxHealth * def.Amount * WEIGHTS.heal
				end
			end
		elseif def.Kind == "Buff" or def.Kind == "Debuff" then
			value += attack * def.Amount * duration * WEIGHTS.speedSwing
		elseif StatusDefs.Controls[def.Kind] then
			local victim = nil
			for _, enemy in ipairs(enemies) do
				if not battle:isDisabled(enemy) and (not victim or enemy.baseAttack > victim.baseAttack) then
					victim = enemy
				end
			end
			if victim then
				value += victim.baseAttack * duration * WEIGHTS.stun * (CONTROL_WORTH[def.Kind] or 1)
					* (skill.Target == "AllEnemies" and #enemies or 1)
				if skill.Target == "Enemy" then
					targetKey = victim.key
				end
			end
		elseif def.Kind == "Taunt" then
			-- Worth the hits it takes for the others, and only while it can
			-- take them.
			local incoming = sumAttack(enemies) * duration
			local weakerAllies = 0
			for _, other in ipairs(allies) do
				if other ~= fighter and other.maxHealth < fighter.maxHealth then
					weakerAllies += 1
				end
			end
			if weakerAllies > 0 and fighter.health > incoming * 0.5 then
				value += incoming * WEIGHTS.taunt * (1 + (def.Amount or 0))
			end
		elseif def.Kind == "Cleanse" then
			-- It clears everything bad, so it is worth what is there to clear.
			local receiver = (onSelf or skill.Target == "Self") and fighter or hurt
			local removable = 0
			for _, status in ipairs(receiver.statuses) do
				if StatusDefs.IsBad(status.id) then
					removable += 1
				end
			end
			value += removable * receiver.maxHealth * WEIGHTS.cleanse
		elseif def.Kind == "Hot" then
			for _, receiver in ipairs(receivers) do
				value += math.min(receiver.maxHealth * def.Amount * duration, receiver.maxHealth - receiver.health) * WEIGHTS.heal
			end
		elseif def.Kind == "Silence" then
			-- Worth what its big skills would have done.
			value += sumAttack(enemies) * share * duration * WEIGHTS.stun * 0.4
		elseif def.Kind == "Blind" or def.Kind == "Confuse" then
			-- Like an Attack debuff of that share (a Confuse only misfires some of the time).
			value += sumAttack(enemies) * share * def.Amount * duration * WEIGHTS.attackSwing * (def.Kind == "Confuse" and 0.7 or 1)
		elseif def.Kind == "Expose" then
			-- Every hit our side lands on it is worth more.
			value += sumAttack(allies) * share * def.Amount * duration * WEIGHTS.attackSwing
		elseif def.Kind == "Thorns" or def.Kind == "Evade" then
			for _ in ipairs(receivers) do
				value += incoming * def.Amount * duration * WEIGHTS.guard
			end
		elseif def.Kind == "Immune" then
			for _, receiver in ipairs(receivers) do
				value += receiver.maxHealth * 0.05 * duration * WEIGHTS.guard
			end
		elseif def.Kind == "Revive" then
			-- Worth more the closer it is to going down.
			for _, receiver in ipairs(receivers) do
				value += receiver.maxHealth * def.Amount * (1 - healthShare(receiver)) * WEIGHTS.heal
			end
		end
	end

	for _, statusId in ipairs(skill.Effects or {}) do
		priceStatus(statusId, false)
	end
	for _, statusId in ipairs(skill.SelfEffects or {}) do
		priceStatus(statusId, true)
	end
	return value, targetKey
end

function CombatAI.Policy(difficulty, seed)
	local tuning = TUNING[difficulty] or TUNING.Normal
	local random = Random.new(seed or 1)

	return function(fighter, battle)
		local allies = battle:living(fighter.team)
		local enemies = battle:living(fighter.team == "A" and "B" or "A")
		if #enemies == 0 then
			return nil
		end
		local ready = {}
		for _, skillId in ipairs(fighter.skills) do
			if battle:canUse(fighter, skillId) then
				table.insert(ready, skillId)
			end
		end
		if #ready == 0 then
			return nil
		end
		if tuning.random then
			return ready[random:NextInteger(1, #ready)]
		end

		local bestSkill, bestTarget, bestValue = nil, nil, -math.huge
		for _, skillId in ipairs(ready) do
			local value, targetKey = price(skillId, fighter, battle, allies, enemies, tuning)
			if tuning.noise > 0 then
				value *= 1 + (random:NextNumber() - 0.5) * 2 * tuning.noise
			end
			if value > bestValue then
				bestSkill, bestTarget, bestValue = skillId, targetKey, value
			end
		end
		return bestSkill or ready[1], bestTarget
	end
end

return CombatAI
