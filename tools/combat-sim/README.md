# combat-sim

Runs the combat code of `studio-export/` outside Roblox, with the standalone
Luau interpreter, to test it before pasting it into Studio.

`bundle.py` packs every module of `ReplicatedStorage/Wyrmhaven/Config` and
`ServerScriptService/Wyrmhaven/Services` plus one test script into
`bundle.luau`, with stand-ins for the Roblox bits (`game:GetService`,
`script.Parent`, `require` of an instance, `Random`, `Vector3`, `Color3`).

```
# Luau: https://github.com/luau-lang/luau/releases (luau-ubuntu.zip)
python3 bundle.py tests.luau && luau bundle.luau      # one scripted fight per status, pass/fail
python3 bundle.py simulate.luau && luau bundle.luau   # 300 AI vs AI fights + SkillRules.Validate
```

`tests.luau` injects test-only skills into SkillDefs at runtime (nothing is
written back). `simulate.luau` is the regression check: after a change that
should not alter existing fights, its numbers must stay the same.
