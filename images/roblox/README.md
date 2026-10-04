# Roblox game page images

| File | Roblox slot | Size |
|---|---|---|
| `Icon.png` | Game icon (Creator Hub > the experience > Places / Configure > Icon) | 512×512 |
| `Thumbnail.png` | Thumbnail, with the white logo | 1920×1080 (16:9) |
| `Thumbnail_Clean.png` | Same thumbnail, no text (Roblox shows the name next to it anyway) | 1920×1080 |

`_preview_icon.png` shows the icon with Roblox's rounded corners at 512,
150 and 50 px.

**What's in them, and why it's coherent with the game:** the island in the
game's faceted low-poly look, at the game's own scale — habitat platforms
16×16 studs in their `HabitatDefs.PlatformColor` (Fire, Water, Nature,
Electric), adult dragon 5.5 studs tall, baby 3.65, eggs 2×2.6 in their
`DragonDefs.StageColors.Egg`, a farm, trees and the sea. The Fire Baby and
Adult are **the real in-game meshes**: `dragon-mesh/extract.py` runs
`DragonBuilder.luau` under standalone Luau and dumps its triangles (Fire is
the only element with a model so far, the others are still placeholders —
so they appear as eggs and habitats only).

## Re-render

```
npm i three playwright-core          # in this folder
python3 dragon-mesh/extract.py luau  # only if DragonBuilder changed
node render.cjs                      # scene.html -> Icon_raw.png, Thumbnail_raw.png
python3 compose.py                   # -> Icon.png, Thumbnail.png, Thumbnail_Clean.png
```

Cameras, dragon poses and props are in the `SHOTS` of `scene.html`.
