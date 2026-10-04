"""Re-extracts the in-game Fire dragon meshes (Baby, Adult) from
studio-export/ServerStorage/WyrmhavenBuildKit/DragonBuilder.luau into
fire_dragons.json, by running the builder under standalone Luau with the
stand-ins of roblox_stubs.luau (geometry only, no Instances).
Usage: python3 extract.py /path/to/luau"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BUILDER = os.path.join(HERE, "..", "..", "..", "studio-export", "ServerStorage", "WyrmhavenBuildKit", "DragonBuilder.luau")


def main():
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    src = (open(os.path.join(HERE, "roblox_stubs.luau")).read() + "\nlocal function BUILDER()\n" + open(BUILDER).read()
           + "\nend\n" + open(os.path.join(HERE, "dump.luau")).read())
    bundle = os.path.join(HERE, "_bundle.luau")
    open(bundle, "w").write(src)
    out = subprocess.run([luau, bundle], capture_output=True, text=True, check=True).stdout
    os.remove(bundle)
    data, stage = {}, None
    for line in out.splitlines():
        p = line.split()
        if p and p[0] == "stage":
            stage = p[1]
            data[stage] = {"pos": [], "col": [], "plate": []}
        elif p and p[0] == "t":
            v = list(map(float, p[1:13]))
            data[stage]["pos"] += v[:9]
            data[stage]["col"] += v[9:12]
            data[stage]["plate"].append(int(p[13]))
    json.dump(data, open(os.path.join(HERE, "fire_dragons.json"), "w"))
    print({k: len(d["plate"]) for k, d in data.items()}, "triangles")


if __name__ == "__main__":
    main()
