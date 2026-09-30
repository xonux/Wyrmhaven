local RS = game:GetService("ReplicatedStorage")
local Config = RS.Wyrmhaven.Config
local SS = game:GetService("ServerScriptService")
local CombatEngine = require(SS.Wyrmhaven.Services.CombatEngine)
local CombatAI = require(SS.Wyrmhaven.Services.CombatAI)
local DragonDefs = require(Config.DragonDefs)
local SkillRules = require(Config.SkillRules)
local v = SkillRules.Validate()
print("validate ok:", v.ok, "problems:", #v.problems)
for _, p in ipairs(v.problems) do print("  ", p) end
local species = {}
for id in pairs(DragonDefs) do if type(DragonDefs[id]) == "table" and DragonDefs[id].Rarity then table.insert(species, id) end end
table.sort(species)
print("species:", #species)
local rng = Random.new(7)
local wins = { A = 0, B = 0, Draw = 0 }
local rounds, timeouts, kinds = 0, 0, {}
local N = tonumber(ARG_N) or 300
for i = 1, N do
  local function team()
    local t = {}
    for k = 1, 3 do local s = species[rng:NextInteger(1, #species)]; table.insert(t, CombatEngine.Fighter(s, 10)) end
    return t
  end
  local a, b = team(), team()
  local ai, bi = CombatAI.Policy("Hard", i), CombatAI.Policy("Normal", i + 1000)
  local result = CombatEngine.Resolve(a, b, { seed = i, choose = function(f, battle) if f.team == "A" then return ai(f, battle) end return bi(f, battle) end })
  wins[result.winner] += 1
  rounds += result.rounds
  if result.timedOut then timeouts += 1 end
  for _, e in ipairs(result.log) do kinds[e.t] = (kinds[e.t] or 0) + 1 end
end
print(string.format("fights %d  A(Hard) %d  B(Normal) %d  draw %d  avg rounds %.1f  timeouts %d", N, wins.A, wins.B, wins.Draw, rounds / N, timeouts))
local ks = {} for k, n in pairs(kinds) do table.insert(ks, k .. "=" .. n) end table.sort(ks) print(table.concat(ks, " "))
