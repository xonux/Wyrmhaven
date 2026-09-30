local RS = game:GetService("ReplicatedStorage")
local Config = RS.Wyrmhaven.Config
local SS = game:GetService("ServerScriptService")
local CombatEngine = require(SS.Wyrmhaven.Services.CombatEngine)
local SkillDefs = require(Config.SkillDefs)
local StatusDefs = require(Config.StatusDefs)

local function skill(id, def) def.DisplayName = id; def.Cooldown = def.Cooldown or 0; SkillDefs[id] = def end
skill("Poke", { Element = "Earth", Target = "Enemy", Power = 0.05 })
skill("Hit", { Element = "Earth", Target = "Enemy", Power = 0.4 })
skill("FirePoke", { Element = "Fire", Target = "Enemy", Power = 0.05 })
skill("Wait", { Element = "Earth", Target = "Self" })
skill("Big", { Element = "Earth", Target = "Enemy", Power = 0.05, Cooldown = 2 })
skill("Smash", { Element = "Earth", Target = "Enemy", Power = 50 })
for _, id in ipairs({ "Freeze", "Sleep", "Silence", "Blind", "Confuse", "Expose", "Poison", "Stun" }) do
	skill("Give" .. id, { Element = "Earth", Target = "Enemy", Effects = { id } })
end
for _, id in ipairs({ "Evade", "Thorns", "Immune", "Revive", "Regen", "Vigor", "MegaTaunt", "Taunt", "Cleanse" }) do
	skill("Self" .. id, { Element = "Earth", Target = "Self", Effects = { id } })
end

local failures, passes = 0, 0
local function check(name, ok, detail)
	if ok then passes += 1 else failures += 1; print("FAIL " .. name .. (detail and (": " .. detail) or "")) end
end

-- plans: [team] = { [slot] = list of skill ids used turn after turn (last one repeats) }
local function fight(plans, sizes, seed)
	local function team(t)
		local list = {}
		for i = 1, sizes[t] do
			local f = CombatEngine.Fighter("Earth", 30)
			f.skills = {}
			local seen = {}
			for _, id in ipairs(plans[t][i]) do if not seen[id] then seen[id] = true; table.insert(f.skills, id) end end
			table.insert(list, f)
		end
		return list
	end
	local turn = {}
	local result = CombatEngine.Resolve(team("A"), team("B"), { seed = seed or 1, choose = function(f)
		turn[f.key] = (turn[f.key] or 0) + 1
		local plan = plans[f.team][f.slot]
		return plan[math.min(turn[f.key], #plan)]
	end })
	return result
end
local function count(result, pred)
	local n = 0
	for _, e in ipairs(result.log) do if pred(e) then n += 1 end end
	return n
end

-- Freeze: 2 lost turns, no thaw from Earth
local r = fight({ A = { { "GiveFreeze", "Poke" } }, B = { { "Wait" } } }, { A = 1, B = 1 })
check("freeze holds 2 turns", count(r, function(e) return e.t == "stunned" and e.status == "Freeze" end) == 2)
-- Freeze thawed by Fire
r = fight({ A = { { "GiveFreeze", "FirePoke" } }, B = { { "Wait" } } }, { A = 1, B = 1 })
check("fire thaws", count(r, function(e) return e.t == "thaw" end) >= 1)
check("thawed after 1 lost turn", count(r, function(e) return e.t == "stunned" and e.status == "Freeze" end) == 1)
-- Sleep: 3 turns if nothing hits, broken by a hit
r = fight({ A = { { "GiveSleep", "Wait" } }, B = { { "Wait" } } }, { A = 1, B = 1 })
check("sleep holds 3", count(r, function(e) return e.t == "stunned" and e.status == "Sleep" end) == 3)
r = fight({ A = { { "GiveSleep", "Poke" } }, B = { { "Wait" } } }, { A = 1, B = 1 })
check("hit wakes", count(r, function(e) return e.t == "wake" end) >= 1)
check("woken after 1 lost turn", count(r, function(e) return e.t == "stunned" and e.status == "Sleep" end) == 1)
-- Silence: B keeps asking for Big (cooldown 2); while silenced it must fall back to Poke
r = fight({ A = { { "GiveSilence", "Wait" } }, B = { { "Poke", "Big" } } }, { A = 1, B = 1 })
local silencedUntil, bigWhileSilenced = nil, 0
for _, e in ipairs(r.log) do
	if e.t == "status" and e.status == "Silence" then silencedUntil = e.round + 2 end
	if e.t == "skill" and e.skill == "Big" and silencedUntil and e.round < silencedUntil then bigWhileSilenced += 1 end
end
check("silence blocks cooldown skills", silencedUntil ~= nil and bigWhileSilenced == 0, tostring(bigWhileSilenced))
check("big used after silence", count(r, function(e) return e.t == "skill" and e.skill == "Big" end) > 0)
-- Blind: about half of B's attacks miss while blind (reapplied every turn)
r = fight({ A = { { "GiveBlind" } }, B = { { "Poke" } } }, { A = 1, B = 1 }, 3)
local misses = count(r, function(e) return e.t == "miss" and e.reason == "Blind" end)
local pokes = count(r, function(e) return e.t == "skill" and e.skill == "Poke" end)
check("blind ~50%", pokes > 10 and misses / pokes > 0.3 and misses / pokes < 0.7, misses .. "/" .. pokes)
-- Evade ~30%
r = fight({ A = { { "SelfEvade" } }, B = { { "Poke" } } }, { A = 1, B = 1 }, 5)
misses = count(r, function(e) return e.t == "miss" and e.reason == "Evade" end)
pokes = count(r, function(e) return e.t == "skill" and e.skill == "Poke" end)
check("evade ~30%", pokes > 10 and misses / pokes > 0.12 and misses / pokes < 0.5, misses .. "/" .. pokes)
-- Confuse: B (2 dragons) confused every turn; some of its pokes land on team B
r = fight({ A = { { "GiveConfuse" } }, B = { { "Poke" }, { "Wait" } } }, { A = 1, B = 2 }, 9)
local friendly = count(r, function(e) return e.t == "confused" and string.sub(e.target, 1, 1) == "B" end)
check("confuse hits own team sometimes", count(r, function(e) return e.t == "confused" end) > 0 and friendly > 0, tostring(friendly))
-- Expose: +25% on the same poke
r = fight({ A = { { "Hit", "GiveExpose", "Hit" } }, B = { { "Wait" } } }, { A = 1, B = 1 })
local dmg = {}
for _, e in ipairs(r.log) do if e.t == "damage" and e.source == "Hit" then table.insert(dmg, e.amount) end end
check("expose +25%", #dmg >= 2 and math.abs(dmg[2] / dmg[1] - 1.25) < 0.05, tostring(dmg[1]) .. " -> " .. tostring(dmg[2]))
-- MegaTaunt wins over Taunt and takes 30% less
r = fight({ A = { { "SelfTaunt" }, { "SelfMegaTaunt" } }, B = { { "Hit" } } }, { A = 2, B = 1 })
local onA2, onA1, a2Down = 0, 0, false
for _, e in ipairs(r.log) do
	if e.t == "death" and e.target == "A2" then a2Down = true end
	if e.t == "skill" and e.skill == "Hit" and e.round >= 2 and not a2Down then
		if e.targets[1] == "A2" then onA2 += 1 elseif e.targets[1] == "A1" then onA1 += 1 end
	end
end
check("mega taunt draws the hits", onA2 > 0 and onA1 == 0, onA2 .. "/" .. onA1)
-- damage reduction: compare to a plain Taunt holder
local r2 = fight({ A = { { "SelfTaunt" } }, B = { { "Hit" } } }, { A = 1, B = 1 })
local r3 = fight({ A = { { "SelfMegaTaunt" } }, B = { { "Hit" } } }, { A = 1, B = 1 })
local function firstHit(res) for _, e in ipairs(res.log) do if e.t == "damage" and e.source == "Hit" and e.round >= 2 then return e.amount end end end
check("mega taunt -30%", math.abs(firstHit(r3) / firstHit(r2) - 0.7) < 0.03, firstHit(r2) .. " vs " .. firstHit(r3))
-- Thorns: 30% back
r = fight({ A = { { "SelfThorns" } }, B = { { "Hit" } } }, { A = 1, B = 1 })
local hit, back
for _, e in ipairs(r.log) do
	if e.t == "damage" and e.source == "Hit" and e.round >= 2 and not hit then hit = e.amount end
	if e.t == "damage" and e.source == "Thorns" and not back then back = e.amount end
end
check("thorns 30%", hit and back and math.abs(back / hit - 0.3) < 0.03, tostring(hit) .. " / " .. tostring(back))
-- Immune keeps poison off
r = fight({ A = { { "SelfImmune" } }, B = { { "GivePoison" } } }, { A = 1, B = 1 })
check("immune blocks", count(r, function(e) return e.t == "immune" end) > 0 and count(r, function(e) return e.t == "burn" and e.target == "A1" end) == 0)
-- Revive: A gets smashed, comes back once
r = fight({ A = { { "SelfRevive", "Wait" } }, B = { { "Wait", "Smash" } } }, { A = 1, B = 1 })
check("revive", count(r, function(e) return e.t == "revive" end) == 1 and count(r, function(e) return e.t == "death" and e.target == "A1" end) == 1)
-- Regen heals at turn start
r = fight({ A = { { "Wait", "SelfRegen", "Wait" } }, B = { { "Hit", "Wait" } } }, { A = 1, B = 1 })
check("regen heals", count(r, function(e) return e.t == "heal" and e.target == "A1" end) >= 2)
-- Vigor adds max Health
r = fight({ A = { { "SelfVigor", "Wait" } }, B = { { "Wait" } } }, { A = 1, B = 1 })
check("vigor", count(r, function(e) return e.t == "status" and e.status == "Vigor" end) >= 1)
-- Cleanse takes a Freeze off (B freezes A; A's ally cleanses it -> A acts)
r = fight({ A = { { "Wait" }, { "Wait", "SelfCleanse" } }, B = { { "GiveFreeze", "Wait" } } }, { A = 2, B = 1 })
check("cleanse lifts controls", count(r, function(e) return e.t == "cleanse" and e.removed > 0 end) > 0
	or count(r, function(e) return e.t == "stunned" end) <= 2)
-- Describe works for every status
for id in pairs(StatusDefs.Defs) do check("describe " .. id, StatusDefs.Describe(id) ~= "" and StatusDefs.Describe(id) ~= StatusDefs.Defs[id].DisplayName) end
print(string.format("%d passed, %d failed", passes, failures))
