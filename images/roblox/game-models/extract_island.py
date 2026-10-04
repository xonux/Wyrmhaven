"""Runs IslandService's own scenery and obstacle builders under standalone
Luau (island_stubs.luau stands in for Roblox) and saves every part they
create to island_parts.json: shape, size, position, rotation, colour.
The service is bundled with its Config modules; two lines appended to the
bundled copy only (never to the game's file) expose its local builders.
Usage: python3 extract_island.py /path/to/luau"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..", "studio-export")


def main():
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    mods = []
    cfg = "ReplicatedStorage/Wyrmhaven/Config"
    for f in sorted(os.listdir(os.path.join(ROOT, cfg))):
        if f.endswith(".luau"):
            mods.append((f"{cfg}/{f[:-5]}", open(os.path.join(ROOT, cfg, f)).read()))
    svc = "ServerScriptService/Wyrmhaven/Services"
    src = open(os.path.join(ROOT, svc, "IslandService.luau")).read()
    i = src.rindex("return IslandService")
    src = src[:i] + "IslandService._buildScenery = buildScenery\nIslandService._buildObstacle = buildObstacle\n" + src[i:]
    mods.append((f"{svc}/IslandService", src))
    mods.append((f"{svc}/LevelService", "return {}"))
    mods.append((f"{svc}/ReadyGlow", "return {}"))
    out = [open(os.path.join(HERE, "island_stubs.luau")).read(), r'''
local MODULES, CACHE = {}, {}
function node(path)
  return setmetatable({ __path = path }, { __index = function(t, k)
    if k == "Parent" then return node(string.match(t.__path, "^(.*)/[^/]+$") or "") end
    if k == "WaitForChild" or k == "FindFirstChild" then return function(self, name) return node(self.__path .. "/" .. name) end end
    return node(t.__path .. "/" .. k) end })
end
game = { GetService = function(_, name) return node(name) end }
require = function(m)
  local p = m.__path
  if CACHE[p] == nil then CACHE[p] = assert(MODULES[p], "no module " .. p)(node(p)) end
  return CACHE[p]
end
''']
    for path, code in mods:
        out.append(f'MODULES["{path}"] = function(script)\n{code}\nend\n')
    out.append(open(os.path.join(HERE, "dump_island.luau")).read())
    bundle = os.path.join(HERE, "_bundle.luau")
    open(bundle, "w").write("\n".join(out))
    res = subprocess.run([luau, bundle], capture_output=True, text=True)
    os.remove(bundle)
    if res.returncode:
        print(res.stdout[-2000:], res.stderr[-2000:])
        sys.exit(1)
    parts = []
    for line in res.stdout.splitlines():
        p = line.split()
        if p and p[0] == "p":
            v = list(map(float, p[2:]))
            parts.append({"shape": p[1].split(".")[-1], "size": v[0:3], "pos": v[3:6], "rot": v[6:15], "color": v[15:18]})
    json.dump(parts, open(os.path.join(HERE, "island_parts.json"), "w"))
    from collections import Counter
    print(len(parts), "parts", Counter(x["shape"] for x in parts))


if __name__ == "__main__":
    main()
