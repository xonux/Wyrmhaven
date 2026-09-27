# Baby fire dragon (test mesh)

Test: a smooth, textured baby fire dragon modeled as closely as possible
after `references/dragon_baby.jpg`. It is **not** in the game's low-poly
style (see `studio-export/ServerStorage/WyrmhavenBuildKit/DragonBuilder.luau`
for the in-game models); it's a one-piece mesh with no rig.

## Files

- `BabyFireDragon.glb` — mesh + texture in one file (preferred for Studio)
- `BabyFireDragon.obj` / `.mtl` / `.png` — same model as OBJ, texture beside it
- `preview_comparison.png` — reference vs render, `preview_views.png` — 4 angles

~19k triangles (Roblox caps a mesh at 20k), 1024×1024 texture. Model space:
Y up, feet at Y = 0, facing +X, about 5 studs tall once imported.

## Import into Roblox Studio

Avatar tab → **Import 3D** (or File → Import 3D) → pick `BabyFireDragon.glb`
→ Import. The texture is applied automatically; resize/rotate the resulting
MeshPart as needed.

## Regenerate

```
pip install numpy scikit-image trimesh fast-simplification xatlas pillow
python3 build_dragon.py      # SDF shape -> marching cubes -> decimation (_raw.ply)
python3 export_dragon.py     # UV unwrap, bake texture, write .glb/.obj
python3 preview.py           # preview_*.png
```

The shape lives in `build_parts()` in `build_dragon.py` (spheres, ellipsoids
and tapered tubes blended together); colors are the constants at its top.
