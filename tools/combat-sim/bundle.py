"""Bundles studio-export modules + a test script into one Luau file with
stubs for the Roblox bits (game, script, require by instance, Random, Vector3...)."""
import os, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "studio-export")
mods = []
for base in ("ReplicatedStorage/Wyrmhaven/Config", "ServerScriptService/Wyrmhaven/Services"):
    for f in sorted(os.listdir(os.path.join(ROOT, base))):
        if f.endswith(".luau") and not f.endswith((".server.luau", ".client.luau")):
            mods.append((base + "/" + f[:-5], open(os.path.join(ROOT, base, f)).read()))
prelude = r'''
local MODULES = {}
local CACHE = {}
local function node(path)
  return setmetatable({ __path = path }, { __index = function(t, k)
    if k == "Parent" then local p = string.match(t.__path, "^(.*)/[^/]+$"); return node(p or "") end
    if k == "WaitForChild" or k == "FindFirstChild" then return function(self, name) return node(self.__path .. "/" .. name) end end
    return node(t.__path .. "/" .. k) end })
end
game = { GetService = function(_, name) return node(name) end }
local realRequire = require
require = function(m)
  local p = m.__path
  if CACHE[p] == nil then
    local f = MODULES[p]; assert(f, "no module " .. p)
    CACHE[p] = f(node(p))
  end
  return CACHE[p]
end
Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
local C3 = {}
C3.__index = C3
function C3:Lerp(o, t) return setmetatable({ self[1] + (o[1] - self[1]) * t, self[2] + (o[2] - self[2]) * t, self[3] + (o[3] - self[3]) * t }, C3) end
Color3 = { fromRGB = function(r, g, b) return setmetatable({ r, g, b }, C3) end, new = function(r, g, b) return setmetatable({ r, g, b }, C3) end,
  fromHSV = function(h, s, v) return setmetatable({ h, s, v }, C3) end }
local function anyStub() return setmetatable({}, { __index = function() return anyStub end, __call = function() return anyStub() end }) end
UDim2 = anyStub(); Enum = anyStub(); TweenInfo = anyStub(); Instance = anyStub(); NumberSequence = anyStub(); ColorSequence = anyStub()
local function mkRandom(seed)
  local s = (seed or 1) % 2147483647; if s <= 0 then s += 2147483646 end
  local r = {}
  function r:NextNumber(a, b) s = (s * 16807) % 2147483647; local x = s / 2147483647; if a then return a + (b - a) * x end return x end
  function r:NextInteger(a, b) return a + math.floor(self:NextNumber() * (b - a + 1)) end
  return r
end
Random = { new = mkRandom }
os = os or {}
'''
out = [prelude]
for path, src in mods:
    out.append(f'MODULES["{path}"] = function(script)\n{src}\nend\n')
out.append(open(sys.argv[1]).read())
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "bundle.luau"), "w").write("\n".join(out))
