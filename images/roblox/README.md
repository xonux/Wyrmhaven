# Roblox game page images (2D)

| File | Roblox slot | Size |
|---|---|---|
| `Icon.png` | Game icon | 512×512 |
| `Thumbnail.png` | Thumbnail, with the white logo | 1920×1080 (16:9) |
| `Thumbnail_Clean.png` | Same thumbnail, no text (Roblox shows the name next to it) | 1920×1080 |

`_preview_icon.png` shows the icon with Roblox's rounded corners at 512,
150 and 50 px.

Flat 2D vector illustration only (SVG sources: `Icon.svg`, `Thumbnail.svg`).
Kept coherent with the game's content and numbers:
- the Fire dragons use the Fire palette of `DragonBuilder.luau`
  (`dragons.py`), baby next to adult in the game's 3.65 / 5.5 height ratio;
- habitat platforms in their `HabitatDefs.PlatformColor` (Fire with its
  volcano, Water pool, Nature trees, Electric crystals), a farm, a nest of
  eggs in their `DragonDefs` egg colours (an egg about half an adult's
  height, 2.6 / 5.5);
- the island and sea, like the reference island; the white logo from
  `../logo/Logo_White.png`.

## Re-render

```
npm i playwright-core     # in this folder
python3 compose.py        # scene.py -> SVGs -> Icon.png, Thumbnail*.png, _preview_icon.png
```

Layout, sizes and colours are in `scene.py`; the dragons in `dragons.py`.
