# Roblox game page images (2D)

| File | Roblox slot | Size |
|---|---|---|
| `Icon.png` | Game icon | 512×512 |
| `Thumbnail.png` | Thumbnail, with the white logo | 1920×1080 (16:9) |
| `Thumbnail_Clean.png` | Same thumbnail, no text (Roblox shows the name next to it) | 1920×1080 |

`_preview_icon.png` shows the icon with Roblox's rounded corners at 512,
150 and 50 px.

Glossy 2D illustration only (SVG sources `Icon.svg`, `Thumbnail.svg`), in
the spirit of mobile-game key art, with Wyrmhaven's own content:
- **Icon:** a baby Fire dragon hatching from a Fire egg (DragonDefs egg
  colour) on a pile of gold Coins, on a blue bokeh background.
- **Thumbnail:** the white logo centred at the top; the adult Fire dragon
  (DragonBuilder's Fire palette) on the left, a baby Water dragon on the
  right at about 2/3 of the adult's height (game ratio 3.65 / 5.5), a baby
  Nature dragon flying, Fire and Nature eggs in the grass, hills, snowy
  mountains and clouds. Baby colours are each element's
  `DragonDefs.StageColors.Baby`.

Pieces: `cute.py` (chibi baby in any element's colours, egg shell, coins,
gradients), `dragons.py` (the adult), `keyart.py` (both layouts).

## Re-render

```
npm i playwright-core     # in this folder
python3 compose.py        # keyart.py -> SVGs -> Icon.png, Thumbnail*.png, _preview_icon.png
```
